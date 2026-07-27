import json, copy
from space import BASE, m, var

# ---- A: full-length confirmation of the two fields that were inert at BOTH extremes ----
A = []
for s in (11, 12):
    A.append(m("cf_preserve_off_s%d" % s, s, var(preserve_min_cost=-1), BASE, cap=1200, samp=5.0))
    A.append(m("cf_defrad_max_s%d" % s,  s, var(defend_threat_radius=30.0), BASE, cap=1200, samp=5.0))
json.dump(A, open("confirm.json", "w")); print("confirm", len(A))

# ---- B: Part 1 sensitivity, 4 params x 2 directions x 2 sides x 2 seeds ----
ARMS = [("reserve", "economy_reserve", 150, 1200),
        ("ratio",   "attack_value_ratio", 0.9, 2.0),
        ("utility", "utility_unit_cap", 1, 5),
        ("defrad",  "defend_threat_radius", 4.0, 25.0)]
B = [m("s1_base_s12", 12, BASE, BASE)]
for name, f, lo, hi in ARMS:
    for tag, v in (("lo", lo), ("hi", hi)):
        p = var(**{f: v})
        for s in (11, 12):
            B.append(m("s1_%s_%s_s%d_A0" % (name, tag, s), s, p, BASE))
            B.append(m("s1_%s_%s_s%d_A1" % (name, tag, s), s, BASE, p))
json.dump(B, open("part1c.json", "w")); print("part1c", len(B))

# ---- C: Part 3 round-robin. think_interval_ticks held at 20 for every archetype. ----
ARCH = {
 "MEDIUM":  dict(BASE),
 "RUSHER":  var(army_commit_threshold=2, economy_reserve=0, attack_value_ratio=0.8,
                assumed_enemy_parity=0.0, wave_abort_fraction=0.0, utility_unit_cap=1),
 "ECONOMIST": var(economy_reserve=1200, build_concurrency=4, utility_unit_cap=6,
                attack_value_ratio=2.0, assumed_enemy_parity=1.2, scout_unit_budget=2),
 "TURTLE":  var(defend_threat_radius=30.0, attack_value_ratio=2.5, wave_abort_fraction=1.0,
                army_commit_threshold=12, scout_unit_budget=0, economy_reserve=900),
 "SKIRMISH": var(retarget_switch_margin=1.0, retarget_weight_effectiveness=3.0,
                retarget_weight_finishability=3.0, retarget_weight_proximity=0.0,
                scout_unit_budget=4, attack_value_ratio=1.1, production_structure_cap=3),
}
json.dump({k: v for k, v in ARCH.items()}, open("archetypes.json", "w"))
names = list(ARCH)
C = []
for i in range(len(names)):
    for j in range(i + 1, len(names)):
        a, b = names[i], names[j]
        C.append(m("rr_%s_vs_%s_s11_A0" % (a, b), 11, ARCH[a], ARCH[b]))
        C.append(m("rr_%s_vs_%s_s11_A1" % (a, b), 11, ARCH[b], ARCH[a]))
json.dump(C, open("part3.json", "w")); print("part3", len(C))
