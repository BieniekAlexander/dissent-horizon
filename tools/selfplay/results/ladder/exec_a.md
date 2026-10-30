# Difficulty ladder: exec_a.jsonl

| pair | n | higher wins | lower wins | stalemate | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 10 | 8 | 0 | 2 | 0 | 100% (68–100%) | 0.79 | 824 | 4–0 / 4–0 |
| MEDIUM < HARD | 10 | 6 | 2 | 2 | 0 | 75% (41–93%) | 0.66 | 663 | 4–0 / 2–2 |
| HARD < IMPOSSIBLE | 10 | 4 | 5 | 1 | 0 | 44% (19–73%) | 0.44 | 640 | 2–2 / 2–3 |

- EASY < MEDIUM: clears the 80% bar (100% of 8 decided, 2 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (75% of 8 decided, 2 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (44% of 9 decided, 1 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | stalemate | - | 1200 | 261 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 1103 | 298 | ok |
| easy_v_medium_map7101_base | stalemate | - | 1200 | 324 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 747 | 189 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 604 | 149 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 679 | 154 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 1159 | 351 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 575 | 132 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 512 | 120 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 459 | 103 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 839 | 262 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 630 | 262 | ok |
| medium_v_hard_map7101_base | stalemate | - | 1200 | 403 | ok |
| medium_v_hard_map7101_swap | stalemate | - | 1200 | 501 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 442 | 131 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 352 | 78 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 555 | 158 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 497 | 133 | ok |
| medium_v_hard_map7104_base | elimination | HARD | 398 | 123 | ok |
| medium_v_hard_map7104_swap | elimination | MEDIUM | 518 | 130 | ok |
| hard_v_impossible_map7100_base | stalemate | - | 1200 | 545 | ok |
| hard_v_impossible_map7100_swap | elimination | IMPOSSIBLE | 875 | 402 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 485 | 151 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 545 | 214 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 522 | 219 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 460 | 138 | ok |
| hard_v_impossible_map7103_base | elimination | HARD | 517 | 206 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 705 | 260 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 546 | 246 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 548 | 218 | ok |
