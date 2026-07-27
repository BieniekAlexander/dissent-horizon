#!/usr/bin/env python3
"""Per-parameter effect on the objective, with a confidence interval, both sides averaged.

Each arm is one changed field played against an unchanged MEDIUM, from BOTH start points on
each seed. Playing both sides is not optional on this map: the 2026-09-06 campaign measured a
start-position advantage worth ~10,000 material by minute 8, which is larger than any
parameter effect here, and it cancels only when the arm is played once from each corner.

The interval is Student-t on the per-match objective. n is small by construction (the budget
buys ~4 matches per arm), so the honest reading of a CI that spans 0.5 is "this run cannot
tell this arm from the unchanged bot", and the printed n90 says how many matches it would
take to resolve the observed difference at 80% power.
"""
import json, math, sys
from collections import defaultdict

sys.path.insert(0, __import__("os").path.dirname(__file__))
from roundrobin import score  # same shaped objective, same fixed scoring time

T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306,
       9: 2.262, 10: 2.228, 15: 2.131, 20: 2.086, 30: 2.042}


def tcrit(df):
    if df <= 0:
        return float("nan")
    for k in sorted(T95):
        if df <= k:
            return T95[k]
    return 1.96


def main(path):
    arms = defaultdict(list)
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        if not r.get("ok") or not r["id"].startswith("eff_"):
            continue
        body = r["id"][4:]
        arm, tail = body.rsplit("_s", 1)
        side = int(tail.split("_A")[1])
        arms[arm].append((tail.split("_A")[0], score(r, side, 480.0)))
    print("%-30s %3s %9s %9s %-22s %s"
          % ("arm", "n", "mean", "sd", "95% CI", "reading"))
    for arm, rows in sorted(arms.items()):
        vals = [v for _, v in rows]
        n = len(vals)
        m = sum(vals) / n
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / (n - 1)) if n > 1 else float("nan")
        half = tcrit(n - 1) * sd / math.sqrt(n) if n > 1 else float("nan")
        spans = (m - half) <= 0.5 <= (m + half)
        need = ""
        if sd and not math.isnan(sd) and abs(m - 0.5) > 1e-9:
            need = "  (n=%d for 80%% power at this effect)" % max(
                2, math.ceil((2.8 * sd / (m - 0.5)) ** 2))
        print("%-30s %3d %9.3f %9.3f [%+.3f, %+.3f]  %s%s"
              % (arm, n, m, sd, m - half, m + half,
                 "SPANS 0.5 - indistinguishable from the unchanged bot" if spans
                 else "differs from the unchanged bot", need))
        print("      per-match: %s" % ", ".join("%.3f" % v for v in vals))
        # SIDE-PAIRED: the two sides of one seed averaged BEFORE the statistics, which
        # cancels the start-position advantage inside each pair instead of leaving it in
        # the residual. It is the same data with a tighter variance and half the n.
        byseed = {}
        for seed, v in rows:
            byseed.setdefault(seed, []).append(v)
        pairs = [sum(v) / len(v) for v in byseed.values() if len(v) == 2]
        if len(pairs) > 1:
            pm = sum(pairs) / len(pairs)
            psd = math.sqrt(sum((v - pm) ** 2 for v in pairs) / (len(pairs) - 1))
            ph = tcrit(len(pairs) - 1) * psd / math.sqrt(len(pairs))
            print("      side-paired: %d seed-pairs, mean %.3f  95%% CI [%+.3f, %+.3f]  (%s)"
                  % (len(pairs), pm, pm - ph, pm + ph,
                     ", ".join("%.3f" % v for v in pairs)))


if __name__ == "__main__":
    main(sys.argv[1])
