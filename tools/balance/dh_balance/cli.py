"""Command-line entry point.

    python -m dh_balance obsolete <faction>
    python -m dh_balance unanswered <attacker> <defender>
    python -m dh_balance tier-gap <low_faction> <low_tier> <high_faction> <high_tier>
    python -m dh_balance tiers <faction>
    python -m dh_balance mermaid <faction>
    python -m dh_balance list
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from . import combat, effectiveness, graph, queries
from .loader import load_world


def _fmt_xc(xc: float) -> str:
    return "INF (cannot hit)" if math.isinf(xc) else f"{xc:.0f}"


# Bounds of the generated region when a graph is baked into a gdd note. They
# are mermaid comments, so they sit INSIDE the ```mermaid fence and stay
# invisible in the rendered diagram. gdd/_scripts/tech-graph.js rewrites what
# lies between them, leaving the fence itself alone.
GRAPH_START_MARKER = "%% tech-graph:start"
GRAPH_END_MARKER = "%% tech-graph:end"


def _mermaid_placeholder(label: str, why: str) -> str:
    """A one-node stand-in for a graph that cannot be drawn. A bodyless
    flowchart renders as an unexplained blank box, so state the reason."""
    return f'flowchart LR\n    empty["{label}: {why}"]'


# Tech-gate highlight palette, cycled in id order; each entry is (fill, stroke).
# Saturated fills carrying white text, because the class has to read on BOTH of
# Obsidian's themes off ONE literal: a border-only treatment is swallowed by the
# dark theme's own node border, and a pale fill loses its text against it.
# Ordered so the first two colours a faction draws are far apart in hue and are
# not the red/green pair, which is the one axis worth avoiding outright.
_TECH_PALETTE: tuple[tuple[str, str], ...] = (
    ("#6d28d9", "#c4b5fd"),  # violet
    ("#0e7490", "#67e8f9"),  # teal
    ("#b45309", "#fcd34d"),  # amber
    ("#be185d", "#f9a8d4"),  # magenta
    ("#15803d", "#86efac"),  # green
    ("#1d4ed8", "#93c5fd"),  # blue
)

# Producer clusters. A translucent grey resolves to a light panel on Obsidian's
# light theme and a dark one on its dark theme, from a single literal — so the
# box reads as a container on both without a theme-conditional.
_PRODUCER_STYLE = "fill:#80808020,stroke:#8a8a8a,stroke-width:1px"

# Layout. `rankSpacing` is the gap ALONG the flow, which in a TB chart is the gap
# between the stacked units inside a producer — so it is the knob that decides how
# tightly a production line reads, and it is turned well below mermaid's default
# 50. `nodeSpacing` separates siblings ACROSS the flow and holds the backbone's
# columns apart. `subGraphTitleMargin` keeps a cluster's title off the first unit
# under it, which the tightened ranks otherwise let it touch.
_LAYOUT_DIRECTIVE = ("%%{init: {'flowchart': {'nodeSpacing': 25, 'rankSpacing': 18, "
                     "'subGraphTitleMargin': {'top': 0, 'bottom': 8}}}}%%")


def _producer_lines(faction, nodes) -> tuple[dict[str, list[str]], dict[str, str]]:
    """``(structure id -> units it trains, unit id -> its producer)``, over drawn
    nodes only.

    **A producer's units keep the order its doc lists them in**, not id order.
    That list is authored, and it is authored for a reason the diagram should not
    throw away: the command grid takes a train button's COLUMN from the unit's
    index in its producer's ``trains:`` (see CLAUDE.md), so the list is already
    the left-to-right order the player reads off the HUD. Sorting it here made
    the diagram disagree with the game over the shape of its own roster — the
    Sky Port trains Clipper, Drake, Reverence, Caravel and the chart drew
    Clipper, Drake, Caravel, Reverence — and it obscured the deliberate
    progressions (cheap to expensive, or basic to specialist) a roster is usually
    written in.

    The OUTER loop stays id-sorted: a node can sit in exactly one mermaid
    subgraph, so a unit named by two producers is drawn inside the first in id
    order. Nothing in the rosters does that today; the tie-break exists so the
    emitter degrades to a readable diagram rather than invalid mermaid if one
    ever does.
    """
    producer_of: dict[str, str] = {}
    trains: dict[str, list[str]] = {}
    for sid in sorted(nodes):
        b = faction.buildables[sid]
        if b.is_unit:
            continue
        for uid in b.trains:
            if uid in nodes and uid not in producer_of:
                producer_of[uid] = sid
                trains.setdefault(sid, []).append(uid)
    return trains, producer_of


def _tech_gates(faction, nodes, producer_of: dict[str, str]) -> dict[str, list[str]]:
    """Structure id -> the units it gates, for the structures that gate anything.

    A TECH GATE is a structure named in a unit's ``requires`` that does not also
    train that unit. The self-naming case — an_airField requiring itself for the
    transport it builds — is a production line stated twice, and colouring it
    would announce a tech step the faction has not actually got.
    """
    gates: dict[str, list[str]] = {}
    for uid in sorted(n for n in nodes if faction.buildables[n].is_unit):
        for req in sorted(faction.buildables[uid].requires):
            if (req in nodes and not faction.buildables[req].is_unit
                    and producer_of.get(uid) != req):
                gates.setdefault(req, []).append(uid)
    return gates


def _declaration_order(backbone: list[str], edges: list[tuple[str, str]]) -> list[str]:
    """Backbone ids in the order they should be DECLARED, chosen to keep edges from
    crossing each other.

    **Declaration order is the only lever the emitter has over layout.** Mermaid lays
    flowcharts out with dagre, which is a Sugiyama pipeline: assign ranks, ORDER within
    each rank, then position. The ordering step is a heuristic (median/barycenter, a
    handful of sweeps) seeded by the order nodes were declared in — so on a graph where
    the heuristic gets stuck, the seed decides the picture. Declaring in id order handed
    it a seed that had nothing to do with the shape of the tree.

    This does one forward barycenter sweep: rank by rank, put each node at the mean
    position of its parents in the rank above, breaking ties by id so the result stays
    deterministic and a re-run is a no-op. That hands dagre a seed already close to a
    crossing-free layout instead of one derived from spelling.

    Measured against dagre itself (the real engine, driven directly): the Colonials went
    from 2 crossings to 0 — the Production Yard's edge no longer cuts across the
    Operations Center's two — and every other faction stayed at 0. It is a heuristic, not
    a solver, so a future roster could still need a hand; it cannot do WORSE than the
    id-order seed for any tree, since a tree's barycenter sweep is exact.
    """
    preds: dict[str, list[str]] = {n: [] for n in backbone}
    for u, v in edges:
        preds[v].append(u)
    # Longest-path ranks — the same assignment dagre makes, so the sweep below is
    # ordering the same layers the renderer will.
    rank: dict[str, int] = {n: 0 for n in backbone}
    for _ in range(len(backbone)):
        changed = False
        for u, v in edges:
            if rank[v] < rank[u] + 1:
                rank[v], changed = rank[u] + 1, True
        if not changed:
            break

    order: list[str] = []
    index: dict[str, int] = {}          # id -> its position within its own rank

    def barycenter(node: str) -> float:
        # Every parent sits in an EARLIER rank (ranks are longest-path), so by the time a
        # node is sorted its parents are already indexed. The empty case is therefore
        # reached only at rank 0, where nothing has parents and everything ties — which
        # is to say rank 0 is ordered by id, and the roots keep a stable, readable order.
        placed = [index[p] for p in preds[node] if p in index]
        return sum(placed) / len(placed) if placed else math.inf

    for r in range(max(rank.values(), default=0) + 1):
        here = sorted((n for n in backbone if rank[n] == r), key=lambda n: (barycenter(n), n))
        for i, node in enumerate(here):
            index[node] = i
        order.extend(here)
    return order


def _mermaid(faction, reachable_only: bool) -> str:
    """A ``flowchart TB`` rendering of ``faction``'s tech DAG (graph.tech_graph).

    Three devices carry the three relations, each picked so one glance answers
    one question instead of the reader tracing arrows across the whole diagram:

    * **Containment** — a producing structure is a SUBGRAPH holding the units it
      trains, titled with the structure's own name. A production line is then a
      box rather than a fan of edges, which is what pulls a faction's units into
      tight clusters. Units keep their stadium shape, structures rectangles.
    * **Arrows** — every edge that survives is a ``requires`` between two
      STRUCTURES, so an arrow means one thing only: the tech backbone. All solid;
      there is no second relation left for a dashed arrow to distinguish.
    * **Colour** — a tech gate (``_tech_gates``) and every unit it gates share one
      class off ``_TECH_PALETTE``, so "what does this lab unlock?" is answered by
      scanning for its colour. This REPLACES the dashed prerequisite arrows, which
      crossed the diagram to say the same thing and collided with the production
      lines on the way.

    A gating structure that also trains is styled as a coloured BORDER rather
    than a fill: a cluster is a region, so filling it recolours the ground behind
    the units it holds. No faction authors that today.

    **The chart is TB because that is the only way to stack a producer's units in
    a column.** Mermaid ignores a subgraph's own ``direction`` whenever that
    subgraph is linked to anything outside it — which every producer here is, by
    the backbone arrow that reaches it — so the units always lay out along the
    PARENT's flow axis, and the parent's axis is the only lever on them. Two
    workarounds were tried against the renderer and both failed: a nested inner
    subgraph carrying its own ``direction TB`` (the inner cluster has no external
    link of its own, but its direction is ignored just the same, and it adds dead
    space), and an invisible anchor node fanning ``~~~`` links at the units to
    force them onto one rank (they stayed in a row, and the anchor reserved a
    blank cell). So a horizontal backbone and columnar production lines cannot be
    had at once, and the columns are worth more — they are what makes a roster
    scannable, and a top-down tech tree suits a note's narrow column anyway.

    ``reachable_only`` restricts to graph.reachable_from(faction), matching the
    balance queries' default.
    """
    g = graph.tech_graph(faction)
    nodes = set(g.nodes)
    if reachable_only:
        nodes &= graph.reachable_from(faction)

    if not nodes:
        return _mermaid_placeholder(
            faction.id,
            "no starts_with in the faction doc, so nothing is reachable"
            if not faction.starts_with else "nothing reachable from starts_with")

    trains, producer_of = _producer_lines(faction, nodes)
    gates = _tech_gates(faction, nodes, producer_of)
    palette = {sid: _TECH_PALETTE[i % len(_TECH_PALETTE)]
               for i, sid in enumerate(sorted(gates))}
    class_name = {sid: f"tech{i}" for i, sid in enumerate(sorted(gates))}

    lines = [_LAYOUT_DIRECTIVE, "flowchart TB"]
    for sid in sorted(gates):
        fill, stroke = palette[sid]
        lines.append(f"    classDef {class_name[sid]} fill:{fill},stroke:{stroke},"
                     f"stroke-width:3px,color:#ffffff")

    def declare(bid: str) -> str:
        b = faction.buildables[bid]
        open_b, close_b = ("([", "])") if b.is_unit else ("[", "]")
        return f'    {bid}{open_b}"{b.name}"{close_b}'

    # Only structure -> structure prerequisites are drawn: a `trains` edge is the
    # subgraph the unit sits in, and a unit's `requires` is the shared colour.
    # Resolved BEFORE the declarations because the declaration ORDER is derived from
    # them (see _declaration_order).
    edges = [(u, v) for u, v in g.edges
             if u in nodes and v in nodes and not faction.buildables[v].is_unit]

    # The backbone, declared in an order chosen to keep its edges from crossing rather
    # than in id order. Producer clusters take their place in that sequence like any
    # other structure — a cluster is one node as far as the backbone is concerned, since
    # no edge ever reaches past it to a unit. Units nobody trains have no edges at all,
    # so they go last, where they cannot influence anything.
    backbone = _declaration_order(
        [n for n in nodes if not faction.buildables[n].is_unit], edges)
    for sid in backbone:
        if sid in trains:
            lines.append(f'    subgraph {sid}["{faction.buildables[sid].name}"]')
            for uid in trains[sid]:
                lines.append("    " + declare(uid))
            lines.append("    end")
        else:
            lines.append(declare(sid))
    for uid in sorted(n for n in nodes
                      if faction.buildables[n].is_unit and n not in producer_of):
        lines.append(declare(uid))

    for u, v in sorted(edges):
        lines.append(f"    {u} --> {v}")

    for sid in sorted(gates):
        members = gates[sid] if sid in trains else [sid] + gates[sid]
        lines.append(f"    class {','.join(members)} {class_name[sid]}")
    for sid in sorted(trains):
        if sid in gates:
            # `class` on a subgraph only reaches its label, so a cluster carries
            # its colour through `style` — as a border, per the docstring.
            _, stroke = palette[sid]
            lines.append(f"    style {sid} fill:none,stroke:{stroke},"
                         f"stroke-width:3px,color:{stroke}")
        else:
            lines.append(f"    style {sid} {_PRODUCER_STYLE}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="dh_balance", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--data-dir", type=Path, default=None,
                   help="data directory to load (default: bundled data/; "
                        "use data_exported/ for a fresh Godot export)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("list", help="list factions and units")
    sp = sub.add_parser("tiers", help="show tech tiers for a faction")
    sp.add_argument("faction")
    sp = sub.add_parser("mermaid", help="tech DAG as a Mermaid flowchart (for Obsidian/docs embedding)")
    sp.add_argument("faction", nargs="?", help="omit with --all for every faction")
    sp.add_argument("--all", action="store_true", help="emit one flowchart per faction")
    sp.add_argument("--full", action="store_true",
                    help="include buildables unreachable from starts_with too (default: reachable-only)")
    sp = sub.add_parser("obsolete", help="units off the Pareto frontier")
    sp.add_argument("faction")
    sp = sub.add_parser("unanswered", help="threats A has that B can't answer")
    sp.add_argument("attacker")
    sp.add_argument("defender")
    sp = sub.add_parser("tier-gap", help="tech-tier asymmetry")
    sp.add_argument("low_faction")
    sp.add_argument("low_tier", type=int)
    sp.add_argument("high_faction")
    sp.add_argument("high_tier", type=int)
    sp = sub.add_parser("matchup", help="emergent-factor breakdown for an attacker vs target")
    sp.add_argument("attacker", help="uid faction:id")
    sp.add_argument("target", help="uid faction:id")
    sp = sub.add_parser("distinctness",
                        help="faction roster distinctness: matrix, or detail for one pair")
    sp.add_argument("faction_a", nargs="?", help="omit both for the all-pairs matrix")
    sp.add_argument("faction_b", nargs="?")
    sp.add_argument("--tier", type=int, action="append",
                    help="restrict to these tech tiers (repeatable, e.g. --tier 1 --tier 2)")
    sp = sub.add_parser("import", help="dry-run: preview YAML -> Godot changes")
    sp.add_argument("--current", type=Path, required=True,
                    help="current Godot state (a fresh data_exported/)")
    sp.add_argument("--desired", type=Path, required=True,
                    help="edited YAML to push back")
    sp.add_argument("--manifest", type=Path,
                    default=Path(__file__).resolve().parents[2] / "balance_export" / "manifest.json",
                    help="export manifest, for annotating owning scenes")
    sp.add_argument("--apply", action="store_true",
                    help="actually write the changes (default: dry run). "
                         "Mutates game scene files + manifest.json — commit/stash first.")

    args = p.parse_args(argv)

    if args.cmd == "import":
        from . import importer
        current = load_world(args.current)
        desired = load_world(args.desired)
        scene_for = {}
        if args.manifest and args.manifest.exists():
            scene_for = importer.scene_map_from_manifest(args.manifest, current)
        changes, added, removed = importer.diff_worlds(current, desired, scene_for)
        edits = importer.plan(changes, desired)
        importer.apply(edits, args.manifest, dry_run=not args.apply)

        mode = "APPLIED" if args.apply else "DRY RUN (no files modified — pass --apply to write)"
        applied = [e for e in edits if e.applied]
        skipped = [e for e in edits if e.scope != "skip" and not e.applied]
        manual = [e for e in edits if e.scope == "skip"]
        # Entities described in the flat files but absent from the Godot export
        # (`current`) have no scene to write to. This is a non-fatal WARNING, not
        # an error — you may be sketching a unit in YAML before authoring it.
        print(f"{mode}\n{len(changes)} change(s): {len(applied)} writable, "
              f"{len(skipped)} unwritable, {len(manual)} structural; "
              f"{len(added)} not in Godot, {len(removed)} removed.\n")
        for e in applied:
            if e.created:
                prefix = "CREATED " if args.apply else "WOULD CREATE "
            else:
                prefix = "WROTE " if args.apply else "WOULD "
            print("  ", prefix + e.describe()[5:])
        for e in skipped:
            print(f"   UNWRITABLE  {e.change.kind} {e.change.id}.{e.change.field}  ({e.skip_reason})")
        for e in manual:
            print("  ", e.describe())
        for a in added:
            print(f"   WARNING  {a.kind} '{a.id}' is described in the flat files but "
                  f"not found in the Godot files (no scene) — skipped, not applied")
        for r in removed:
            print(f"   - GONE {r.kind} {r.id} (in current only)")
        return 0

    world = load_world(args.data_dir)

    if args.cmd == "list":
        for f in world.factions.values():
            print(f"\n{f.id}  ({f.name}) — {f.description.strip()}")
            tiers = graph.tech_tiers(f)
            for b in f.buildables.values():
                tag = "unit" if b.is_unit else "bldg"
                wpns = ", ".join(w.name for w in b.weapons) or "-"
                print(f"  [T{tiers.get(b.id,1)}] {tag} {b.id:12} ore={b.cost.ore:<4} "
                      f"hp={b.hp:<6g} armour={b.armour.value if b.armour else '-':9} weapons={wpns}")

    elif args.cmd == "tiers":
        for uid, tier in sorted(graph.tech_tiers(world.factions[args.faction]).items(),
                                key=lambda kv: kv[1]):
            print(f"T{tier}  {uid}")

    elif args.cmd == "mermaid":
        if not args.all and not args.faction:
            print("provide a faction, or --all for every faction.")
            return 2
        fids = list(world.factions) if args.all else [args.faction]
        for fid in fids:
            if args.all:
                print(f"## {fid}\n")
            faction = world.factions.get(fid)
            print("```mermaid")
            print(GRAPH_START_MARKER)
            if faction is None:
                # A faction with no unit/structure docs yet — it never reaches
                # the export at all. Draw the moot graph rather than failing.
                print(_mermaid_placeholder(fid, "no pieces authored yet"))
            else:
                faction = graph.with_external_buildables(world, faction)
                print(_mermaid(faction, reachable_only=not args.full))
            print(GRAPH_END_MARKER)
            print("```")
            if args.all:
                print()

    elif args.cmd == "obsolete":
        res = queries.obsolete_units(world, args.faction)
        if not res:
            print(f"No obsolete units in {args.faction}: every unit is on the Pareto frontier.")
        for d in res:
            print(f"OBSOLETE  {d.unit}  — dominated by {d.dominated_by}")

    elif args.cmd == "unanswered":
        res = queries.unanswered_threats(world, args.attacker, args.defender)
        if not res:
            print(f"{args.defender} has a favorable answer to every {args.attacker} threat.")
        for u in res:
            best = u.best_response or "—"
            print(f"UNANSWERED  {u.threat} (ore {u.threat_cost:.0f})  "
                  f"best {args.defender} response: {best} "
                  f"[exchange_cost={_fmt_xc(u.best_exchange_cost)}]  ({u.reason})")

    elif args.cmd == "tier-gap":
        r = queries.tech_tier_gap(world, args.low_faction, args.low_tier,
                                  args.high_faction, args.high_tier)
        print(f"{r.low_faction} @T{r.low_tier} vs {r.high_faction} @T{r.high_tier}:")
        if not r.struggles_against:
            print("  no unanswered threats at this tier gap.")
        for u in r.struggles_against:
            best = u.best_response or "—"
            print(f"  STRUGGLES vs {u.threat} (ore {u.threat_cost:.0f})  "
                  f"best response: {best} [exchange_cost={_fmt_xc(u.best_exchange_cost)}]  ({u.reason})")

    elif args.cmd == "matchup":
        a = world.get(args.attacker)
        t = world.get(args.target)
        d = world.damage
        print(f"{a.uid}  ->  {t.uid}")
        print(f"  base dps        {combat.dps(d, a, t):.2f}")
        for name, v in effectiveness.matchup_factors(d, a, t).items():
            print(f"    x {name:9}   {v:.3f}")
        print(f"  combined factor {effectiveness.combined_factor(d, a, t):.3f}")
        print(f"  effective dps   {effectiveness.effective_dps(d, a, t):.2f}")
        print(f"  exchange_cost   base={_fmt_xc(combat.exchange_cost(d, a, t))}  "
              f"effective={_fmt_xc(effectiveness.effective_exchange_cost(d, a, t))}")

    elif args.cmd == "distinctness":
        tiers = set(args.tier) if args.tier else None
        suffix = f"  (tiers {sorted(tiers)})" if tiers else ""
        if args.faction_a and args.faction_b:
            r = queries.faction_distinctness(world, args.faction_a, args.faction_b, tiers)
            print(f"{r.faction_a} vs {r.faction_b}{suffix}")
            print(f"  {r.faction_a:>12} -> {r.faction_b:<12}  {r.a_to_b:.2f}  (how poorly {r.faction_b} shadows {r.faction_a})")
            print(f"  {r.faction_b:>12} -> {r.faction_a:<12}  {r.b_to_a:.2f}")
            if r.most_similar:
                ms = r.most_similar
                print(f"  most similar: {ms.unit_a} ~ {ms.unit_b}  (distinctness {ms.distinctness:.2f})")
        elif args.faction_a:
            print("provide BOTH factions for a pair, or NEITHER for the matrix.")
            return 2
        else:
            m = queries.distinctness_matrix(world, tiers)
            fids = list(world.factions)
            print(f"set_distinctness  (row shadowed by col; higher = more distinct){suffix}")
            print("            " + "".join(f"{c[:11]:>13}" for c in fids))
            for a in fids:
                cells = "".join("-".rjust(13) if a == b else f"{m[(a, b)]:>13.1f}"
                                for b in fids)
                print(f"{a[:11]:>12}" + cells)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
