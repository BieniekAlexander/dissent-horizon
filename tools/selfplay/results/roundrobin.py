#!/usr/bin/env python3
"""Archetype payoff matrix, Bradley-Terry fit, and an explicit search for a cycle.

SCORED AT A FIXED SIMULATED TIME, not at whatever tick the match stopped on. Matches that
hit the harness's wall-clock cap end a few simulated seconds short, and a margin read at the
end of a short match is not comparable with one read at the end of a long match; reading both
at t = SCORE_AT makes every cell the same measurement.

THE OBJECTIVE is the 2026-09-05 note's, kept so the two matrices can be read against one
another: a win scores 0.75-1.00 (sooner is better), a loss 0.00-0.25 (later is better), and
an undecided match 0.25-0.75 on material margin, material being
army_energy_value + energy + 250 * structure_count. The tanh scale is stated here rather than
buried: MARGIN_SCALE is the margin at which an undecided match scores ~0.69, and it is chosen
as roughly the start-position advantage this campaign measured, so an archetype has to beat
the map's own handicap before it scores like a winner.

BOTH SIDES ARE AVERAGED, and on this map that is not a nicety. The start-position advantage
measured in the same campaign is worth ~10,000 material by minute 8 -- the same order as the
archetype differences here -- and it cancels exactly when a pair is played once from each
start point.
"""
import itertools, json, math, sys

SCORE_AT = 420.0
STRUCTURE_PRICE = 250.0
MARGIN_SCALE = 10000.0


def material(slot):
    return slot["army_energy_value"] + slot["energy"] + STRUCTURE_PRICE * slot["structure_count"]


def sample_at(row, t):
    best = None
    for s in row["samples"]:
        if s["simulated_seconds"] <= t + 1e-6:
            best = s
    return best


def score(row, slot, cap):
    """Slot `slot`'s objective in [0, 1]."""
    if row["outcome"] == "elimination":
        frac = min(1.0, row["simulated_seconds"] / cap)
        return 0.75 + 0.25 * (1.0 - frac) if row["winner"] == slot else 0.25 * frac
    s = sample_at(row, SCORE_AT)
    if s is None:
        return 0.5
    margin = material(s["slots"][slot]) - material(s["slots"][1 - slot])
    return 0.5 + 0.25 * math.tanh(margin / MARGIN_SCALE)


def load(path):
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    return [r for r in rows if r.get("ok")]


def main(path, seeds=None):
    rows = load(path)
    cells, names = {}, []
    for r in rows:
        rid = r["id"]
        if not rid.startswith("rr_"):
            continue
        body = rid[3:]
        pair, seed_side = body.rsplit("_s", 1)
        seed, side = seed_side.split("_A")
        if seeds and int(seed) not in seeds:
            continue
        a, b = pair.split("_vs_")
        # side 0 puts `a` in slot 0; side 1 puts `b` there.
        row_name, col_name = (a, b) if side == "0" else (b, a)
        cap = r.get("simulated_seconds") and 480.0
        cells.setdefault((a, b), []).append(
            score(r, 0 if side == "0" else 1, cap))
        for n in (a, b):
            if n not in names:
                names.append(n)
    names.sort()
    print("archetypes: %s   cells: %d   matches: %d"
          % (", ".join(names), len(cells), sum(len(v) for v in cells.values())))
    print("\nPAYOFF MATRIX -- row's mean objective against column (>0.5 = row ahead)")
    hdr = "%-11s" % "" + "".join("%11s" % n[:10] for n in names) + "%9s" % "mean"
    print(hdr)
    P = {}
    for a in names:
        line = "%-11s" % a
        vals = []
        for b in names:
            if a == b:
                line += "%11s" % "--"
                continue
            if (a, b) in cells:
                v = sum(cells[(a, b)]) / len(cells[(a, b)])
            elif (b, a) in cells:
                v = 1.0 - sum(cells[(b, a)]) / len(cells[(b, a)])
            else:
                line += "%11s" % "?"
                continue
            P[(a, b)] = v
            vals.append(v)
            line += "%11.3f" % v
        line += "%9.3f" % (sum(vals) / len(vals)) if vals else ""
        print(line)

    # Bradley-Terry by gradient descent on squared error against the logistic.
    r = {n: 0.0 for n in names}
    for _ in range(20000):
        g = {n: 0.0 for n in names}
        for (a, b), p in P.items():
            q = 1.0 / (1.0 + math.exp(-(r[a] - r[b])))
            e = q - p
            d = e * q * (1 - q)
            g[a] += d
            g[b] -= d
        for n in names:
            r[n] -= 0.5 * g[n]
        m = sum(r.values()) / len(r)
        for n in names:
            r[n] -= m
    rss = sum((1.0 / (1.0 + math.exp(-(r[a] - r[b]))) - p) ** 2 for (a, b), p in P.items())
    tss = sum((p - 0.5) ** 2 for p in P.values())
    print("\nBRADLEY-TERRY strengths (a single linear ordering):")
    for n, v in sorted(r.items(), key=lambda kv: -kv[1]):
        print("   %-11s %+7.3f" % (n, v))
    print("   residual SS %.4f / total SS %.4f  ->  R2 = %.3f  (cyclic component %.1f%%)"
          % (rss, tss, 1 - rss / tss, 100 * rss / tss))
    print("   largest residuals:")
    res = sorted(((abs(1.0 / (1.0 + math.exp(-(r[a] - r[b]))) - p), a, b, p)
                  for (a, b), p in P.items()), reverse=True)[:4]
    for d, a, b, p in res:
        print("      %-11s vs %-11s observed %.3f  fitted %.3f  residual %+.3f"
              % (a, b, p, 1.0 / (1.0 + math.exp(-(r[a] - r[b]))), p - 1.0 / (1.0 + math.exp(-(r[a] - r[b])))))

    print("\nCYCLE SEARCH -- every ordered 3-cycle with all three legs above 0.5:")
    found = 0
    for a, b, c in itertools.permutations(names, 3):
        if a > b or a > c:
            continue        # each undirected triple once, both orientations
        for triple in ((a, b, c), (a, c, b)):
            x, y, z = triple
            if P.get((x, y), 0) > 0.5 and P.get((y, z), 0) > 0.5 and P.get((z, x), 0) > 0.5:
                print("   CYCLE  %s > %s (%.3f) > %s (%.3f) > %s (%.3f)"
                      % (x, y, P[(x, y)], z, P[(y, z)], x, P[(z, x)]))
                found += 1
    if not found:
        print("   none: the matrix is transitive.")

    print("\nPER-CELL DETAIL (both sides; a cell whose two sides disagree is a coin flip)")
    for (a, b), v in sorted(cells.items()):
        sides = ", ".join("%.3f" % x for x in v)
        agree = all(x > 0.5 for x in v) or all(x < 0.5 for x in v)
        print("   %-11s vs %-11s  n=%d  sides [%s]  %s"
              % (a, b, len(v), sides, "SAME winner both sides" if agree else "split"))


if __name__ == "__main__":
    seeds = {int(s) for s in sys.argv[2].split(",")} if len(sys.argv) > 2 else None
    main(sys.argv[1], seeds)
