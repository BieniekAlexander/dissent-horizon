import json, sys, collections
sys.path.insert(0, '.')
R = []
for f in ["part1_results.jsonl","part1c_results.jsonl","screen_results.jsonl","repro_results.jsonl",
          "confirm_results.jsonl","part3_results.jsonl","es_results.jsonl"]:
    for l in open(f): R.append(json.loads(l))

print("1. HYSTERESIS - posture A->B->A within 3 samples, whole corpus")
osc = collections.Counter(); slots_scanned = 0
for r in R:
    for s in (0, 1):
        slots_scanned += 1
        seq = [x["slots"][s]["brain"]["posture"] for x in r["samples"]]
        for i in range(len(seq) - 2):
            w = seq[i:i+4]
            for j in range(2, len(w)):
                if w[0] != w[1] and w[j] == w[0] and w[0]:
                    osc[(w[0], w[1])] += 1; break
print("   slot-trajectories scanned: %d" % slots_scanned)
print("   A->B->A occurrences:", dict(osc) or "NONE")

print()
print("2. THE UNWINNABLE WIN - a slot reduced to 0 structures that survives to the cap")
n = 0
for r in R:
    if r.get("outcome") != "stalemate": continue
    fin = r["samples"][-1]["slots"]
    for s in (0, 1):
        if fin[s]["structure_count"] == 0 and fin[s]["unit_count"] > 0:
            n += 1
            if n <= 6: print("   %-30s slot%d: 0 structures, %d unit(s) left, opponent had %d structures" % (
                r["id"], s, fin[s]["unit_count"], fin[1-s]["structure_count"]))
print("   TOTAL such matches: %d of %d stalemates" % (n, sum(1 for r in R if r.get("outcome")=="stalemate")))

print()
print("3. ECONOMY PINNED AT ZERO - fraction of samples with energy == 0")
z = t = 0
for r in R:
    for x in r["samples"][1:]:
        for s in (0, 1):
            t += 1; z += (x["slots"][s]["energy"] == 0)
print("   %d / %d slot-samples (%.1f%%) have exactly zero banked energy" % (z, t, 100.0*z/t))

print()
print("4. SCOUT COVERAGE ceiling and IDLE UNITS")
cov = [max(x["slots"][s]["brain"]["scout_observed_fraction"] for x in r["samples"]) for r in R for s in (0,1)]
idle = [max(x["slots"][s]["brain"]["idle_units"] for x in r["samples"]) for r in R for s in (0,1)]
cov.sort(); idle.sort()
print("   peak scout coverage: min %.2f  median %.2f  max %.2f" % (cov[0], cov[len(cov)//2], cov[-1]))
print("   peak idle units:     min %d  median %d  max %d" % (idle[0], idle[len(idle)//2], idle[-1]))

print()
print("5. BELIEF NEVER FORMED - matches where a slot's believed_enemy_army_value stays 0")
n = 0
for r in R:
    for s in (0, 1):
        if max(x["slots"][s]["brain"]["believed_enemy_army_value"] for x in r["samples"]) == 0.0:
            n += 1
print("   %d of %d slot-trajectories never saw an enemy army at all" % (n, slots_scanned))

print()
print("6. MATCH COST OUTLIERS (wall seconds per simulated second)")
c = sorted(((r["wall_seconds"]/max(1.0,r["simulated_seconds"]), r["id"], r["simulated_seconds"]) for r in R if r.get("ok")), reverse=True)
for v, i, ss in c[:4]: print("   %-32s %.0f sim-s cost %.3f wall-s per sim-s" % (i, ss, v))
print("   median: %.3f" % c[len(c)//2][0])

print()
print("7. DEPLOY LATENCY / opening")
dt = collections.Counter(tuple(r.get("deployed_ticks", [])) for r in R)
print("   deployed_ticks values:", dict(dt))
