# Training report

Generation 2, 52 ledger rows, 6 live of 13 members, cap 900 s.

## Roster

| member | cell | rating | matches | first attack s | structures built | mech | mixture | parent |
|---|---|---|---|---|---|---|---|---|
| s_rusher | a0_g0 | +1.67 | 12 | 67 | 15.3 | 0.06 | 1.00 | None |
| s_tier | a2_g3 | +0.90 | 20 | 241 | 21.1 | 0.13 | 0.00 | None |
| g001_c0 | a1_g0 | +0.49 | 6 | 97 | 13.7 | 0.04 | 0.00 | s_rusher |
| g001_c2 | a2_g2 | +0.23 | 8 | 249 | 18.9 | 0.20 | 0.00 | s_skirmisher |
| g002_c3 | a4_g2 | -0.14 | 4 | 726 | 19.5 | 0.08 | 0.00 | g001_c0 |
| s_economist | a4_g3 | -0.17 | 14 | 900 | 23.1 | 0.21 | 0.00 | None |

## Equilibrium

Support: 1 of 6 bots play at 5% or more. Exploitability: +0.000 (best single bot's mean score gain over the mixture; 0 is unexploitable).

## Score matrix (row vs column, mean score; * = predicted, unplayed)

| | s_rusher | s_tier | g001_c0 | g001_c2 | g002_c3 | s_economist |
|---|---|---|---|---|---|---|
| s_rusher | · | 0.86 | 0.77* | 0.81* | 0.86* | 0.90 |
| s_tier | 0.14 | · | 0.86 | 0.52 | 0.87 | 0.71 |
| g001_c0 | 0.23* | 0.14 | · | 0.56* | 0.65* | 0.83 |
| g001_c2 | 0.19* | 0.48 | 0.44* | · | 0.59* | 0.59 |
| g002_c3 | 0.14* | 0.13 | 0.35* | 0.41* | · | 0.62 |
| s_economist | 0.10 | 0.29 | 0.17 | 0.41 | 0.38 | · |

## Vectors

| field | s_rusher | s_tier | g001_c0 | g001_c2 | g002_c3 | s_economist |
|---|---|---|---|---|---|---|
| army_commit_threshold | 1 | 3 | 2 | 3 | 7 | 8 |
| preserve_min_cost | 0 | 0 | -1 | -1 | -1 | 0 |
| retarget_switch_margin | 1.3 | 1.3 | 1.202 | 1.172 | 1.331 | 1.3 |
| scout_unit_budget | 3 | 3 | 2 | 4 | 3 | 3 |
| economy_reserve | 0 | 450 | 0 | 450 | 1421 | 1200 |
| build_concurrency | 3 | 3 | 2 | 4 | 3 | 4 |
| production_structure_cap | -1 | -1 | -1 | 2 | -1 | -1 |
| utility_unit_cap | 1 | 3 | 0 | 4 | 1 | 6 |
| income_structure_target | 1 | 1 | 3 | 3 | 3 | 4 |
| structure_demand_weight | 0.4 | 0.4 | 0.541 | 0.305 | 0.669 | 0.4 |
| demand_coverage_falloff | 1.0 | 1.0 | 0.538 | 2.05 | 1.044 | 1.0 |
| attack_value_ratio | 0.8 | 1.3 | 0.8 | 0.8 | 1.934 | 2.0 |
| assumed_enemy_parity | 0.0 | 0.85 | 0.205 | 0.437 | 0.903 | 1.2 |
| wave_abort_fraction | 0.0 | 0.7 | 0.0 | 0.56 | 0.7 | 0.7 |
| reinforce_fraction | 0.0 | 0.5 | 0.06 | 1.0 | 0.576 | 0.5 |
| defend_threat_radius | 10.0 | 10.0 | 11.718 | 10.711 | 14.263 | 10.0 |
| retarget_weight_effectiveness | 1.0 | 1.0 | 1.944 | 3.0 | 0.73 | 1.0 |
| retarget_weight_finishability | 1.0 | 1.0 | 1.483 | 2.208 | 1.343 | 1.0 |
| retarget_weight_proximity | 0.5 | 0.5 | 0.405 | 0.318 | 0.0 | 0.5 |
| place_frontage_bias | 0.6 | 0.6 | 0.237 | 0.802 | 0.362 | 0.6 |
| place_shelter_bias | 0.6 | 0.6 | 0.272 | 0.303 | 0.063 | 0.6 |
| place_corridor_weight | 0.8 | 0.8 | 0.64 | 2.191 | 0.99 | 0.8 |

## Generations

- g000: 20 matches; s_economist new cell a4_g4; s_rusher new cell a0_g4; s_skirmisher new cell a2_g4; s_tier new cell a3_g4; s_turtle loses a4_g4 to s_economist
- g001: 16 matches; g001_c0 new cell a1_g4; g001_c1 loses a0_g4 to s_rusher; g001_c2 new cell a3_g4; g001_c3 loses a4_g4 to s_economist
- g002: 16 matches; g002_c0 loses a4_g2 to g002_c3; g002_c1 loses a4_g2 to g002_c3; g002_c2 loses a1_g0 to g001_c0; g002_c3 new cell a4_g2
