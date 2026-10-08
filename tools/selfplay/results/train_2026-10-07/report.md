# Training report

Generation 0, 20 ledger rows, 4 live of 5 members, cap 900 s.

## Roster

| member | cell | rating | matches | first attack s | structures built | mech | mixture | parent |
|---|---|---|---|---|---|---|---|---|
| s_rusher | a0_g0 | +1.08 | 8 | 71 | 12.8 | 0.10 | 1.00 | None |
| s_tier | a2_g2 | +0.27 | 8 | 236 | 19.1 | 0.16 | 0.00 | None |
| s_economist | a4_g2 | -0.48 | 8 | 740 | 19.2 | 0.12 | 0.00 | None |
| s_turtle | a4_g0 | -1.02 | 8 | 728 | 11.6 | 0.14 | 0.00 | None |

## Equilibrium

Support: 1 of 4 bots play at 5% or more. Exploitability: +0.000 (best single bot's mean score gain over the mixture; 0 is unexploitable).

## Score matrix (row vs column, mean score; * = predicted, unplayed)

| | s_rusher | s_tier | s_economist | s_turtle |
|---|---|---|---|---|
| s_rusher | · | 0.88 | 0.54 | 0.92 |
| s_tier | 0.12 | · | 0.84 | 0.88 |
| s_economist | 0.46 | 0.16 | · | 0.49 |
| s_turtle | 0.08 | 0.12 | 0.51 | · |

## Vectors

| field | s_rusher | s_tier | s_economist | s_turtle |
|---|---|---|---|---|
| army_commit_threshold | 1 | 3 | 8 | 12 |
| preserve_min_cost | 0 | 0 | 0 | 0 |
| retarget_switch_margin | 1.3 | 1.3 | 1.3 | 1.3 |
| scout_unit_budget | 3 | 3 | 3 | 0 |
| economy_reserve | 0 | 450 | 1200 | 900 |
| build_concurrency | 3 | 3 | 4 | 3 |
| production_structure_cap | -1 | -1 | -1 | -1 |
| utility_unit_cap | 1 | 3 | 6 | 3 |
| income_structure_target | 1 | 1 | 4 | 1 |
| defence_propensity | 1.0 | 1.0 | 1.0 | 1.0 |
| tech_value_margin | 1.3 | 1.3 | 1.3 | 1.3 |
| structure_demand_weight | 0.4 | 0.4 | 0.4 | 0.4 |
| demand_coverage_falloff | 1.0 | 1.0 | 1.0 | 1.0 |
| attack_value_ratio | 0.8 | 1.3 | 2.0 | 2.5 |
| assumed_enemy_parity | 0.0 | 0.85 | 1.15 | 0.85 |
| wave_abort_fraction | 0.0 | 0.7 | 0.7 | 1.0 |
| reinforce_fraction | 0.0 | 0.5 | 0.5 | 0.5 |
| squad_cap | 3 | 3 | 3 | 3 |
| defend_threat_radius | 10.0 | 10.0 | 10.0 | 30.0 |
| retarget_weight_effectiveness | 1.0 | 1.0 | 1.0 | 1.0 |
| retarget_weight_finishability | 1.0 | 1.0 | 1.0 | 1.0 |
| retarget_weight_proximity | 0.5 | 0.5 | 0.5 | 0.5 |
| place_frontage_bias | 0.6 | 0.6 | 0.6 | 1.5 |
| place_shelter_bias | 0.6 | 0.6 | 0.6 | 0.6 |
| place_corridor_weight | 0.8 | 0.8 | 0.8 | 0.8 |
| guard_strength_ratio | 1.5 | 1.5 | 1.5 | 1.5 |

## Generations

- g000: 20 matches; s_rusher new cell a0_g0; s_tier new cell a2_g2; s_skirmisher loses a2_g2 to s_tier; s_economist new cell a4_g2; s_turtle new cell a4_g0
