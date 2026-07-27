#!/usr/bin/env python3
"""Prove a scenario's symmetry with numbers, not with the eye.

Reflects EVERY terrain corner height, EVERY terrain cell tile type and EVERY authored node
position under the candidate isometry and reports the residual: the max and mean absolute
height difference, the count of mismatched tile cells, and for each authored entity the
distance from its reflected image to the nearest entity of the SAME kind (an entity whose
image lands on nothing is unpaired, and that is the failure this catches).

Terrain is scored only inside the PLAY DIAMOND -- the corner grid is square but the play
rectangle is screen-aligned, so the grid corners outside it are void by construction and
their heights are not part of the map.

    python3 tools/selfplay/results/verify_symmetry.py \
        scenes/scenarios/skirmish.tscn resources/terrain/mesh_plateau_terrain.tres
"""
import base64
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

REFLECTIONS = {
    "point (x,z)->(-x,-z)": lambda x, z: (-x, -z),
    "flip-Z (x,z)->(x,-z)": lambda x, z: (x, -z),
    "flip-X (x,z)->(-x,z)": lambda x, z: (-x, z),
}


def parse_terrain(path):
    text = open(os.path.join(REPO, path), encoding="utf-8").read()
    m = re.search(r"^play_size = Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", text, re.M)
    play = (int(m.group(1)), int(m.group(2)))
    W = D = play[0] + play[1] + 2
    m = re.search(r"^heights = PackedFloat32Array\(([^)]*)\)", text, re.M | re.S)
    heights = [float(v) for v in m.group(1).replace("\n", " ").split(",") if v.strip()]
    m = re.search(r"^tile_types = PackedByteArray\((.*?)\)\s*$", text, re.M | re.S)
    tiles = base64.b64decode("".join(re.findall(r'"([^"]*)"', m.group(1)))) if m else b""
    return heights, tiles, W, D, play


def parse_nodes(path):
    text = open(os.path.join(REPO, path), encoding="utf-8").read()
    ext = {m.group(3): m.group(2) for m in re.finditer(
        r'^\[ext_resource type="(\w+)"[^\]]*path="([^"]+)" id="([^"]+)"\]', text, re.M)}
    nodes, cur = [], None
    for line in text.splitlines():
        m = re.match(r'^\[node name="([^"]+)" (?:type="(\w+)" )?parent="([^"]*)"'
                     r'[^\]]*?(?:instance=ExtResource\("([^"]+)"\))?\]', line)
        if m:
            cur = {"name": m.group(1), "type": m.group(2), "parent": m.group(3),
                   "kind": ext.get(m.group(4)) or m.group(2), "pos": None,
                   "start": "start_position" in line}
            nodes.append(cur)
            continue
        if cur is not None and line.startswith("transform = Transform3D("):
            v = [float(x) for x in line[len("transform = Transform3D("):-1].split(",")]
            cur["pos"] = (v[9], v[10], v[11])
        elif line.startswith("["):
            cur = None
    return [n for n in nodes if n["pos"] is not None
            and n["parent"] == "." and n["type"] != "DirectionalLight3D"]


def report(tscn, tres):
    heights, tiles, W, D, play = parse_terrain(tres)
    nodes = parse_nodes(tscn)
    hw = hd = (W - 1) / 2.0
    gw = gd = W - 1
    chw = chd = (gw - 1) / 2.0
    # The play diamond: |x + z| and |x - z| within the play rectangle's diagonal extent.
    limit = float(play[0])

    def in_play(x, z):
        return abs(x + z) <= limit and abs(x - z) <= limit

    print("%s + %s" % (tscn, tres))
    print("  corner grid %dx%d, cells %dx%d, %d authored entities"
          % (W, D, gw, gd, len(nodes)))
    kinds = {}
    for n in nodes:
        kinds.setdefault(n["kind"], []).append(n)

    print("  %-24s %9s %9s %14s %11s %10s %s"
          % ("reflection", "h_mean", "h_max", "tiles_differ", "node_mean", "node_max",
             "worst"))
    for label, f in REFLECTIONS.items():
        total = worst = 0.0
        n = 0
        for j in range(D):
            for i in range(W):
                x, z = i - hw, j - hd
                if not in_play(x, z):
                    continue
                rx, rz = f(x, z)
                ri, rj = int(round(rx + hw)), int(round(rz + hd))
                if not (0 <= ri < W and 0 <= rj < D):
                    continue
                dv = abs(heights[j * W + i] - heights[rj * W + ri])
                total += dv
                worst = max(worst, dv)
                n += 1
        mism = cells = 0
        for j in range(gd):
            for i in range(gw):
                x, z = i - chw, j - chd
                if not in_play(x, z):
                    continue
                rx, rz = f(x, z)
                ri, rj = int(round(rx + chw)), int(round(rz + chd))
                if not (0 <= ri < gw and 0 <= rj < gd):
                    continue
                cells += 1
                if tiles[j * gw + i] != tiles[rj * gw + ri]:
                    mism += 1
        ntot = nmax = 0.0
        nworst = ""
        for kind, group in kinds.items():
            for nd in group:
                x, _, z = nd["pos"]
                rx, rz = f(x, z)
                best = min((((rx - m["pos"][0]) ** 2 + (rz - m["pos"][2]) ** 2) ** 0.5, m["name"])
                           for m in group)
                ntot += best[0]
                if best[0] > nmax:
                    nmax, nworst = best[0], "%s->%s" % (nd["name"], best[1])
        print("  %-24s %9.5f %9.3f %7d/%-6d %11.3f %10.3f %s"
              % (label, total / max(n, 1), worst, mism, cells,
                 ntot / max(len(nodes), 1), nmax, nworst))

    # Two entities on the same tile would be an authoring fault the reflection introduced.
    closest, pair = 1e9, None
    for i, a in enumerate(nodes):
        for b in nodes[i + 1:]:
            d = ((a["pos"][0] - b["pos"][0]) ** 2 + (a["pos"][2] - b["pos"][2]) ** 2) ** 0.5
            if d < closest:
                closest, pair = d, (a["name"], b["name"])
    print("  closest pair of authored entities: %.3f  (%s, %s)" % (closest, pair[0], pair[1]))
    starts = sorted([n for n in parse_nodes(tscn) if n["start"]], key=lambda n: n["name"])
    if len(starts) == 2:
        a, b = starts[0]["pos"], starts[1]["pos"]
        for label, f in REFLECTIONS.items():
            rx, rz = f(a[0], a[2])
            d = ((rx - b[0]) ** 2 + (rz - b[2]) ** 2) ** 0.5
            print("  start points under %-24s residual %.3f" % (label, d))


if __name__ == "__main__":
    report(sys.argv[1], sys.argv[2])
