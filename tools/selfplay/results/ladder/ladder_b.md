# Difficulty ladder: ladder_b.jsonl

| pair | n | higher wins | lower wins | stalemate | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 10 | 8 | 1 | 1 | 0 | 89% (56–98%) | 0.74 | 725 | 5–0 / 3–1 |
| MEDIUM < HARD | 10 | 7 | 3 | 0 | 0 | 70% (40–89%) | 0.65 | 638 | 4–1 / 3–2 |
| HARD < IMPOSSIBLE | 10 | 4 | 6 | 0 | 0 | 40% (17–69%) | 0.44 | 476 | 3–2 / 1–4 |

- EASY < MEDIUM: clears the 80% bar (89% of 9 decided, 1 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (70% of 10 decided, 0 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (40% of 10 decided, 0 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 1039 | 578 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 745 | 318 | ok |
| easy_v_medium_map7101_base | stalemate | - | 1200 | 648 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 737 | 305 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 328 | 120 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 571 | 271 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 498 | 224 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 914 | 391 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 500 | 225 | ok |
| easy_v_medium_map7104_swap | elimination | EASY | 721 | 257 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 391 | 179 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 617 | 318 | ok |
| medium_v_hard_map7101_base | elimination | MEDIUM | 643 | 254 | ok |
| medium_v_hard_map7101_swap | elimination | HARD | 709 | 299 | ok |
| medium_v_hard_map7102_base | elimination | MEDIUM | 1068 | 397 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 387 | 133 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 633 | 388 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 394 | 153 | ok |
| medium_v_hard_map7104_base | elimination | HARD | 449 | 183 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 1085 | 378 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 295 | 117 | ok |
| hard_v_impossible_map7100_swap | elimination | IMPOSSIBLE | 287 | 97 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 859 | 394 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 459 | 167 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 294 | 140 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 446 | 160 | ok |
| hard_v_impossible_map7103_base | elimination | HARD | 325 | 116 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 954 | 367 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 407 | 151 | ok |
| hard_v_impossible_map7104_swap | elimination | HARD | 432 | 157 | ok |
