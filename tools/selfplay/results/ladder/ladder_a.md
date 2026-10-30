# Difficulty ladder: ladder_a.jsonl

| pair | n | higher wins | lower wins | stalemate | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 10 | 5 | 3 | 2 | 0 | 62% (31–86%) | 0.57 | 726 | 4–0 / 1–3 |
| MEDIUM < HARD | 10 | 4 | 4 | 2 | 0 | 50% (22–78%) | 0.51 | 711 | 2–2 / 2–2 |
| HARD < IMPOSSIBLE | 10 | 6 | 4 | 0 | 0 | 60% (31–83%) | 0.58 | 535 | 4–1 / 2–3 |

- EASY < MEDIUM: FAILS the 80% bar (62% of 8 decided, 2 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (50% of 8 decided, 2 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (60% of 10 decided, 0 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 586 | 214 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 666 | 269 | ok |
| easy_v_medium_map7101_base | stalemate | - | 1200 | 524 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 891 | 394 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 364 | 124 | ok |
| easy_v_medium_map7102_swap | elimination | EASY | 905 | 330 | ok |
| easy_v_medium_map7103_base | elimination | EASY | 611 | 207 | ok |
| easy_v_medium_map7103_swap | stalemate | - | 1200 | 415 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 440 | 148 | ok |
| easy_v_medium_map7104_swap | elimination | EASY | 402 | 133 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 470 | 194 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 326 | 133 | ok |
| medium_v_hard_map7101_base | stalemate | - | 1200 | 687 | ok |
| medium_v_hard_map7101_swap | stalemate | - | 1200 | 493 | ok |
| medium_v_hard_map7102_base | elimination | MEDIUM | 717 | 333 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 578 | 236 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 622 | 284 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 367 | 150 | ok |
| medium_v_hard_map7104_base | elimination | MEDIUM | 637 | 303 | ok |
| medium_v_hard_map7104_swap | elimination | MEDIUM | 994 | 440 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 555 | 243 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 904 | 469 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 307 | 132 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 429 | 205 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 556 | 243 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 263 | 98 | ok |
| hard_v_impossible_map7103_base | elimination | IMPOSSIBLE | 830 | 357 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 700 | 303 | ok |
| hard_v_impossible_map7104_base | elimination | IMPOSSIBLE | 434 | 185 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 372 | 138 | ok |
