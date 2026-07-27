#!/usr/bin/env python3
"""Start-position bias: slot-1 advantage, its confidence interval, and its attribution.

Two readouts per match, because at the match length this campaign could afford almost
nothing is decided by elimination:
  * `winner`  — the harness verdict, when there is one;
  * `margin`  — slot 1's material lead at the final sample, material being
                army_energy_value + energy + 250 * structure_count (the 2026-09-05 note's
                shaping constant, kept so the two corpora are comparable).
The sign of `margin` is a paired Bernoulli trial per seed, which is what makes a 16-seed
run able to say anything at all.
"""
import json, math, sys
from collections import defaultdict

STRUCTURE_PRICE = 250.0


def material(slot):
    return slot["army_energy_value"] + slot["energy"] + STRUCTURE_PRICE * slot["structure_count"]


def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        if line.strip():
            rows.append(json.loads(line))
    return rows


def wilson(k, n, z=1.959963985):
    """Wilson score interval — the right one for a proportion at n = 16."""
    if n == 0:
        return (float("nan"),) * 3
    p = k / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return p, max(0.0, centre - half), min(1.0, centre + half)


def binom_p(k, n, p0=0.5):
    """Exact two-sided binomial test against p0 = 0.5."""
    if n == 0:
        return float("nan")
    def pmf(i):
        return math.comb(n, i) * p0 ** n
    obs = pmf(k)
    return min(1.0, sum(pmf(i) for i in range(n + 1) if pmf(i) <= obs * (1 + 1e-12)))


def summarize(rows, label):
    seeds, margins, wins, decisive = [], [], 0, 0
    for r in rows:
        if not r.get("ok"):
            continue
        s = r["samples"][-1]["slots"]
        m = material(s[1]) - material(s[0])
        margins.append((r["seed"], m, r["outcome"], r.get("winner", -1),
                        s[0]["extractor_count"], s[1]["extractor_count"],
                        s[0]["structure_count"], s[1]["structure_count"]))
        seeds.append(r["seed"])
        if r["outcome"] in ("elimination",):
            decisive += 1
            if r.get("winner") == 1:
                wins += 1
    k = sum(1 for _, m, *_ in margins if m > 0)
    n = len(margins)
    p, lo, hi = wilson(k, n)
    print("--- %s  (n = %d matches) ---" % (label, n))
    print("  decisive by elimination: %d  (slot 1 won %d)" % (decisive, wins))
    print("  slot-1 material margin POSITIVE in %d/%d = %.3f  95%% CI [%.3f, %.3f]  binom p = %.4g"
          % (k, n, p, lo, hi, binom_p(k, n)))
    if margins:
        ms = sorted(m for _, m, *_ in margins)
        mean = sum(ms) / len(ms)
        print("  margin: mean %+.0f  median %+.0f  min %+.0f  max %+.0f"
              % (mean, ms[len(ms) // 2], ms[0], ms[-1]))
        ex0 = sum(x[4] for x in margins) / n
        ex1 = sum(x[5] for x in margins) / n
        st0 = sum(x[6] for x in margins) / n
        st1 = sum(x[7] for x in margins) / n
        print("  mean final extractors  slot0 %.2f  slot1 %.2f   structures  slot0 %.2f  slot1 %.2f"
              % (ex0, ex1, st0, st1))
    return {s: m for s, m, *_ in margins}


def main(path):
    rows = load(path)
    base = [r for r in rows if not r.get("swap_start_points")]
    swap = [r for r in rows if r.get("swap_start_points")]
    mb = summarize(base, "A: authored assignment (slot 0 at StartPoint1)")
    ms = summarize(swap, "B: assignment SWAPPED (slot 0 at StartPoint1_mirror)")
    common = sorted(set(mb) & set(ms))
    if not common:
        return
    print("--- attribution, %d paired seeds ---" % len(common))
    print("  If the advantage follows the SLOT INDEX, margin stays positive in B.")
    print("  If it follows the POSITION,           margin flips sign in B.")
    flips = sum(1 for s in common if (mb[s] > 0) != (ms[s] > 0))
    print("  sign flipped on %d/%d seeds" % (flips, len(common)))
    print("  %-8s %12s %12s %s" % ("seed", "margin A", "margin B", "reading"))
    for s in common:
        reading = "follows POSITION" if (mb[s] > 0) != (ms[s] > 0) else "follows SLOT INDEX"
        print("  %-8d %12.0f %12.0f %s" % (s, mb[s], ms[s], reading))


if __name__ == "__main__":
    main(sys.argv[1])
