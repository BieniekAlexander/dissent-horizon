import json

# MEDIUM baseline, stated explicitly so nothing depends on the tier table not moving.
BASE = {
    "think_interval_ticks": 20, "army_commit_threshold": 5, "preserve_min_cost": 250,
    "retarget_switch_margin": 1.6, "scout_unit_budget": 1, "economy_reserve": 600,
    "may_attack": True, "build_concurrency": 1, "production_structure_cap": -1,
    "utility_unit_cap": 3, "structure_demand_weight": 0.4, "demand_coverage_falloff": 1.0,
    "attack_value_ratio": 1.3, "assumed_enemy_parity": 0.85, "wave_abort_fraction": 0.70,
    "defend_threat_radius": 10.0, "retarget_weight_effectiveness": 1.0,
    "retarget_weight_finishability": 1.0, "retarget_weight_proximity": 0.5,
}

# 5 params x 2 directions. lo/hi are absolute values within bot-parameter-space.md bounds.
ARMS = [
    ("commit",  "army_commit_threshold", 2,    9),      # range 1-12,  base 5
    ("reserve", "economy_reserve",       150,  1200),   # range 0-1500, base 600
    ("ratio",   "attack_value_ratio",    0.9,  2.0),    # range 0.8-2.5, base 1.3
    ("utility", "utility_unit_cap",      1,    5),      # range 0-6,   base 3
    ("defrad",  "defend_threat_radius",  4.0,  25.0),   # range 3-30,  base 10
]
SEEDS = [11, 12]

def slot(cfg):
    return {"difficulty": "MEDIUM", "config": cfg}

def match(mid, seed, cfg0, cfg1):
    return {"id": mid, "seed": seed, "max_simulated_seconds": 1200,
            "max_wall_seconds": 600, "sample_interval_seconds": 5.0,
            "deterministic_navigation": True,
            "slots": [slot(cfg0), slot(cfg1)]}

out = []
# Mirror control: measures the map's side bias with strategy held perfectly equal.
for s in [101, 102, 103, 104]:
    out.append(match("p1_mirror_s%d" % s, s, dict(BASE), dict(BASE)))

for name, field, lo, hi in ARMS:
    for tag, val in (("lo", lo), ("hi", hi)):
        pert = dict(BASE); pert[field] = val
        for s in SEEDS:
            out.append(match("p1_%s_%s_s%d_A0" % (name, tag, s), s, pert, dict(BASE)))
            out.append(match("p1_%s_%s_s%d_A1" % (name, tag, s), s, dict(BASE), pert))

json.dump(out, open("part1.json", "w"), indent=0)
print(len(out), "matches")
