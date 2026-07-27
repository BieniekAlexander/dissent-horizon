import json, sys, math, itertools
sys.path.insert(0, '.')
from analyze import score, win, wilson

R = {json.loads(l)["id"]: json.loads(l) for l in open("part3_results.jsonl")}
NAMES = ["MEDIUM", "RUSHER", "ECONOMIST", "TURTLE", "SKIRMISH"]
cell = {}   # (a,b) -> list of a's scores
for a, b in itertools.combinations(NAMES, 2):
    xs = []
    for tag, slot in (("A0", 0), ("A1", 1)):
        i = "rr_%s_vs_%s_s11_%s" % (a, b, tag)
        if i in R:
            s = score(R[i], slot)
            if s is not None: xs.append((s, R[i].get("outcome"), R[i].get("winner"), slot))
    cell[(a, b)] = xs

print("PAYOFF MATRIX - row's mean shaped objective vs column, both sides aggregated")
print("(>0.5 = row is ahead;  n = sides measured)")
print()
hdr = "%-11s" % "" + "".join("%12s" % n[:10] for n in NAMES)
print(hdr); print("-" * len(hdr))
M = {}
for a in NAMES:
    row = "%-11s" % a
    for b in NAMES:
        if a == b: row += "%12s" % "-"; continue
        if (a, b) in cell: xs = cell[(a, b)]; v = [x[0] for x in xs]
        else: xs = cell[(b, a)]; v = [1 - x[0] for x in xs]
        if not v: row += "%12s" % "n/a"; M[(a, b)] = None; continue
        m = sum(v) / len(v); M[(a, b)] = m
        row += "%12s" % ("%.3f(%d)" % (m, len(v)))
    print(row)

print()
print("DOMINANCE:")
for a in NAMES:
    beats = [b for b in NAMES if b != a and M.get((a, b)) is not None and M[(a, b)] > 0.5]
    print("  %-10s beats %s" % (a, ", ".join(beats) if beats else "(nothing)"))

print()
print("CYCLES (3-cycles where A>B>C>A on the shaped objective):")
found = []
for tri in itertools.permutations(NAMES, 3):
    a, b, c = tri
    if tri[0] != min(tri): continue
    if all(M.get(p) is not None for p in [(a, b), (b, c), (c, a)]):
        if M[(a, b)] > .5 and M[(b, c)] > .5 and M[(c, a)] > .5:
            found.append(tri)
for t in found:
    print("  %s > %s > %s > %s   (%.3f / %.3f / %.3f)" % (
        t[0], t[1], t[2], t[0], M[(t[0], t[1])], M[(t[1], t[2])], M[(t[2], t[0])]))
if not found: print("  none")

# ---- Bradley-Terry fit on the shaped objective, and its residuals ----
print()
print("BRADLEY-TERRY / linear-strength fit (how well one ordering explains the matrix):")
s = {n: 0.0 for n in NAMES}
obs = [(a, b, M[(a, b)]) for a, b in itertools.combinations(NAMES, 2) if M.get((a, b)) is not None]
for _ in range(4000):
    g = {n: 0.0 for n in NAMES}
    for a, b, y in obs:
        p = 1 / (1 + math.exp(-(s[a] - s[b])))
        g[a] += (y - p); g[b] -= (y - p)
    for n in NAMES: s[n] += 0.05 * g[n]
    mu = sum(s.values()) / len(s)
    for n in NAMES: s[n] -= mu
print("  fitted strengths:", "  ".join("%s=%+.2f" % (n, s[n]) for n in sorted(NAMES, key=lambda x: -s[x])))
ss_res = ss_tot = 0.0
ybar = sum(y for _, _, y in obs) / len(obs)
for a, b, y in obs:
    p = 1 / (1 + math.exp(-(s[a] - s[b])))
    ss_res += (y - p) ** 2; ss_tot += (y - ybar) ** 2
print("  pairs fitted: %d   residual SS = %.4f   total SS = %.4f   R^2 = %.3f" % (
    len(obs), ss_res, ss_tot, 1 - ss_res / ss_tot if ss_tot else float('nan')))
print("  worst-fit pairs (a cyclic component shows up here):")
rs = sorted(obs, key=lambda t: -abs(t[2] - 1 / (1 + math.exp(-(s[t[0]] - s[t[1]])))))
for a, b, y in rs[:4]:
    p = 1 / (1 + math.exp(-(s[a] - s[b])))
    print("    %-10s vs %-10s observed %.3f  predicted %.3f  residual %+.3f" % (a, b, y, p, y - p))

print()
print("POWER - which cells are distinguishable from a coin flip?")
print("  Every cell has n=2 (one match per side) or n=1. A 2-sample cell cannot reject")
print("  p=0.5 at any conventional level: the exact two-sided p-value floor is 0.50.")
for a, b in itertools.combinations(NAMES, 2):
    xs = cell[(a, b)]
    dec = [x for x in xs if x[1] == "elimination"]
    swept = len(dec) == 2 and len(set((x[2] == x[3]) for x in dec)) == 1
    print("    %-10s vs %-10s  sides=%d  decisive=%d  %s" % (
        a, b, len(xs), len(dec),
        "SAME WINNER ON BOTH SIDES (side-bias controlled)" if swept else
        ("split / not decisive on both sides" if len(xs) == 2 else "INCOMPLETE - one side only")))
