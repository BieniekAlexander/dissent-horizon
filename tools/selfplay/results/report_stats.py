import json, sys, math, itertools
sys.path.insert(0, '.')
from analyze import score, win, mean_ci, wilson, diff_prop_ci, traj_distance, n_for_effect

R = {}
for f in ["part1_results.jsonl", "part1c_results.jsonl", "screen_results.jsonl",
          "repro_results.jsonl", "confirm_results.jsonl", "part3_results.jsonl",
          "es_results.jsonl"]:
    for l in open(f):
        r = json.loads(l); R[r["id"]] = r
print("TOTAL MATCH ROWS: %d   (ok=%d)" % (len(R), sum(1 for r in R.values() if r.get("ok"))))
outc = {}
for r in R.values(): outc[r.get("outcome")] = outc.get(r.get("outcome"), 0) + 1
print("outcomes:", outc)
print()

# ---------- PART 1: perturbation vs unchanged baseline ----------
print("=" * 78); print("PART 1  perturbed-vs-baseline, aggregated over BOTH SIDES")
print("=" * 78)
def arm_scores(prefix, ids):
    """score of the PERTURBED bot: slot 0 in _A0 rows, slot 1 in _A1 rows."""
    xs, wins, n = [], 0, 0
    for i in ids:
        if i not in R: continue
        slot = 0 if i.endswith("A0") else 1
        s = score(R[i], slot)
        if s is None: continue
        xs.append(s)
        w = win(R[i], slot)
        if w is not None: wins += w; n += 1
    return xs, wins, n

ARMS1 = [
 ("army_commit_threshold", 5, "lo", 2, ["p1_commit_lo_s%d_%s"%(s,a) for s in (11,12) for a in ("A0","A1")]),
 ("army_commit_threshold", 5, "hi", 9, ["p1_commit_hi_s%d_%s"%(s,a) for s in (11,12) for a in ("A0","A1")]),
 ("economy_reserve", 600, "lo", 150, ["s1_reserve_lo_s%d_%s"%(s,a) for s in (11,12) for a in ("A0","A1")]),
 ("economy_reserve", 600, "hi", 1200, ["s1_reserve_hi_s%d_%s"%(s,a) for s in (11,12) for a in ("A0","A1")]),
]
res1 = {}
print("%-24s %-10s %5s  %-22s %-18s" % ("field", "value", "n", "objective mean [95% CI]", "wins/decisive"))
for f, b, tag, v, ids in ARMS1:
    xs, wins, n = arm_scores(tag, ids)
    m, lo, hi = mean_ci(xs)
    res1[(f, tag)] = (m, lo, hi, len(xs), wins, n)
    wl, wh = wilson(wins, n)
    print("%-24s %-10s %5d  %.3f [%+.3f, %+.3f]   %d/%d  [%.2f,%.2f]" % (
        f, "%s->%s" % (b, v), len(xs), m, lo, hi, wins, n, wl, wh))
print()
print("FINITE DIFFERENCES on the shaped objective (baseline = 0.500 by mirror symmetry):")
for f, b, lo_v, hi_v in [("army_commit_threshold", 5, 2, 9), ("economy_reserve", 600, 150, 1200)]:
    ml = res1[(f, "lo")]; mh = res1[(f, "hi")]
    d = mh[0] - ml[0]; span = hi_v - lo_v
    se = math.sqrt(max(0.0, ((mh[2]-mh[0])/1.96)**2 + ((ml[2]-ml[0])/1.96)**2))
    print("  d(objective)/d(%s) = %+.5f per unit   95%% CI [%+.5f, %+.5f]  %s" % (
        f, d/span, (d-1.96*se)/span, (d+1.96*se)/span,
        "SPANS ZERO" if (d-1.96*se) * (d+1.96*se) <= 0 else "SIGNED"))
print()
print("Matches PER ARM needed to resolve a win-rate shift of size delta (95%%/80%%):")
for dd in (0.30, 0.20, 0.15, 0.10):
    print("   delta=%.2f -> %d matches per arm" % (dd, n_for_effect(dd)))
