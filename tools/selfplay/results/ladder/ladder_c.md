# Difficulty ladder: ladder_c.jsonl

| pair | n | higher wins | lower wins | stalemate | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|
| MEDIUM < HARD | 10 | 4 | 5 | 1 | 0 | 44% (19–73%) | 0.49 | 715 | 2–2 / 2–3 |
| HARD < IMPOSSIBLE | 10 | 4 | 5 | 1 | 0 | 44% (19–73%) | 0.44 | 643 | 3–2 / 1–3 |

- MEDIUM < HARD: FAILS the 80% bar (44% of 9 decided, 1 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (44% of 9 decided, 1 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| medium_v_hard_map7100_base | elimination | HARD | 435 | 169 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 793 | 518 | ok |
| medium_v_hard_map7101_base | elimination | MEDIUM | 564 | 228 | ok |
| medium_v_hard_map7101_swap | elimination | MEDIUM | 1075 | 473 | ok |
| medium_v_hard_map7102_base | elimination | MEDIUM | 640 | 258 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 698 | 250 | ok |
| medium_v_hard_map7103_base | elimination | MEDIUM | 733 | 315 | ok |
| medium_v_hard_map7103_swap | stalemate | - | 1200 | 520 | ok |
| medium_v_hard_map7104_base | elimination | HARD | 464 | 188 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 544 | 229 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 703 | 309 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 390 | 141 | ok |
| hard_v_impossible_map7101_base | stalemate | - | 1200 | 469 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 455 | 176 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 401 | 184 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 311 | 120 | ok |
| hard_v_impossible_map7103_base | elimination | HARD | 515 | 227 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 811 | 329 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 526 | 201 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 1122 | 386 | ok |
