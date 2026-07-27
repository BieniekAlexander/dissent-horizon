import json
BASE = {
    "think_interval_ticks": 20, "army_commit_threshold": 5, "preserve_min_cost": 250,
    "retarget_switch_margin": 1.6, "scout_unit_budget": 1, "economy_reserve": 600,
    "may_attack": True, "build_concurrency": 1, "production_structure_cap": -1,
    "utility_unit_cap": 3, "structure_demand_weight": 0.4, "demand_coverage_falloff": 1.0,
    "attack_value_ratio": 1.3, "assumed_enemy_parity": 0.85, "wave_abort_fraction": 0.70,
    "defend_threat_radius": 10.0, "retarget_weight_effectiveness": 1.0,
    "retarget_weight_finishability": 1.0, "retarget_weight_proximity": 0.5,
}
# Every searchable field except may_attack, each pushed to the FAR END of its documented
# range. If a match against an identically-seeded baseline never diverges, the field cannot
# be reached from MEDIUM at all.
ARMS = [
    ("think_lo",     "think_interval_ticks",          5),
    ("think_hi",     "think_interval_ticks",          60),
    ("commit_max",   "army_commit_threshold",         12),
    ("commit_min",   "army_commit_threshold",         1),
    ("preserve_off", "preserve_min_cost",             -1),
    ("preserve_all", "preserve_min_cost",             0),
    ("margin_lo",    "retarget_switch_margin",        1.0),
    ("margin_hi",    "retarget_switch_margin",        3.0),
    ("scout_hi",     "scout_unit_budget",             4),
    ("scout_zero",   "scout_unit_budget",             0),
    ("reserve_zero", "economy_reserve",               0),
    ("reserve_max",  "economy_reserve",               1500),
    ("concur_max",   "build_concurrency",             4),
    ("pcap_1",       "production_structure_cap",      1),
    ("utility_zero", "utility_unit_cap",              0),
    ("utility_max",  "utility_unit_cap",              6),
    ("sdw_max",      "structure_demand_weight",       1.0),
    ("falloff_zero", "demand_coverage_falloff",       0.0),
    ("ratio_lo",     "attack_value_ratio",            0.8),
    ("ratio_hi",     "attack_value_ratio",            2.5),
    ("parity_zero",  "assumed_enemy_parity",          0.0),
    ("parity_max",   "assumed_enemy_parity",          1.5),
    ("abort_zero",   "wave_abort_fraction",           0.0),
    ("abort_max",    "wave_abort_fraction",           1.0),
    ("defrad_max",   "defend_threat_radius",          30.0),
    ("defrad_min",   "defend_threat_radius",          3.0),
    ("w_eff_max",    "retarget_weight_effectiveness", 3.0),
    ("w_fin_max",    "retarget_weight_finishability", 3.0),
    ("w_prox_max",   "retarget_weight_proximity",     3.0),
]
def m(mid, cfg0):
    return {"id": mid, "seed": 11, "max_simulated_seconds": 600, "max_wall_seconds": 400,
            "sample_interval_seconds": 2.0, "deterministic_navigation": True,
            "slots": [{"difficulty": "MEDIUM", "config": cfg0},
                      {"difficulty": "MEDIUM", "config": dict(BASE)}]}
out = [m("scr_BASELINE", dict(BASE))]
for name, field, val in ARMS:
    c = dict(BASE); c[field] = val
    out.append(m("scr_" + name, c))
json.dump(out, open("screen.json", "w"))
print(len(out), "matches")
