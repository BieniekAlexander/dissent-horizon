# Difficulty ladder: exec_b.jsonl

| pair | n | higher wins | lower wins | stalemate | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 10 | 2 | 2 | 6 | 0 | 50% (15–85%) | 0.53 | 954 | 1–2 / 1–0 |
| MEDIUM < HARD | 10 | 5 | 0 | 5 | 0 | 100% (57–100%) | 0.71 | 851 | 3–0 / 2–0 |
| HARD < IMPOSSIBLE | 10 | 6 | 4 | 0 | 0 | 60% (31–83%) | 0.58 | 557 | 4–1 / 2–3 |

- EASY < MEDIUM: FAILS the 80% bar (50% of 4 decided, 6 stalemates)
- MEDIUM < HARD: clears the 80% bar (100% of 5 decided, 5 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (60% of 10 decided, 0 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 651 | 143 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 400 | 82 | ok |
| easy_v_medium_map7101_base | stalemate | - | 1200 | 265 | ok |
| easy_v_medium_map7101_swap | stalemate | - | 1200 | 273 | ok |
| easy_v_medium_map7102_base | stalemate | - | 1200 | 244 | ok |
| easy_v_medium_map7102_swap | stalemate | - | 1200 | 278 | ok |
| easy_v_medium_map7103_base | stalemate | - | 1200 | 253 | ok |
| easy_v_medium_map7103_swap | elimination | EASY | 495 | 108 | ok |
| easy_v_medium_map7104_base | elimination | EASY | 793 | 172 | ok |
| easy_v_medium_map7104_swap | stalemate | - | 1200 | 259 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 761 | 235 | ok |
| medium_v_hard_map7100_swap | stalemate | - | 1200 | 281 | ok |
| medium_v_hard_map7101_base | stalemate | - | 1200 | 341 | ok |
| medium_v_hard_map7101_swap | stalemate | - | 1200 | 339 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 403 | 102 | ok |
| medium_v_hard_map7102_swap | elimination | HARD | 484 | 118 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 532 | 150 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 327 | 83 | ok |
| medium_v_hard_map7104_base | stalemate | - | 1200 | 249 | ok |
| medium_v_hard_map7104_swap | stalemate | - | 1200 | 287 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 461 | 171 | ok |
| hard_v_impossible_map7100_swap | elimination | IMPOSSIBLE | 672 | 282 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 694 | 276 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 543 | 194 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 426 | 172 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 595 | 165 | ok |
| hard_v_impossible_map7103_base | elimination | HARD | 395 | 137 | ok |
| hard_v_impossible_map7103_swap | elimination | IMPOSSIBLE | 562 | 210 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 674 | 296 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 546 | 221 | ok |
