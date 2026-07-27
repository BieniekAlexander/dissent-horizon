BASE = {
    "think_interval_ticks": 20, "army_commit_threshold": 5, "preserve_min_cost": 250,
    "retarget_switch_margin": 1.6, "scout_unit_budget": 1, "economy_reserve": 600,
    "may_attack": True, "build_concurrency": 1, "production_structure_cap": -1,
    "utility_unit_cap": 3, "structure_demand_weight": 0.4, "demand_coverage_falloff": 1.0,
    "attack_value_ratio": 1.3, "assumed_enemy_parity": 0.85, "wave_abort_fraction": 0.70,
    "defend_threat_radius": 10.0, "retarget_weight_effectiveness": 1.0,
    "retarget_weight_finishability": 1.0, "retarget_weight_proximity": 0.5,
}
def m(mid, seed, c0, c1, cap=600, samp=2.0):
    return {"id": mid, "seed": seed, "max_simulated_seconds": cap, "max_wall_seconds": 400,
            "sample_interval_seconds": samp, "deterministic_navigation": True,
            "slots": [{"difficulty": "MEDIUM", "config": dict(c0)},
                      {"difficulty": "MEDIUM", "config": dict(c1)}]}
def var(**kw):
    c = dict(BASE); c.update(kw); return c
