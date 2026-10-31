# Difficulty ladder: exec_j.jsonl

| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 30 | 24 | 1 | 1 | 0 | 4 | 96% (80–99%) | 0.86 | 508 | 12–1 / 12–0 |
| MEDIUM < HARD | 30 | 17 | 13 | 0 | 0 | 0 | 57% (39–73%) | 0.55 | 570 | 8–7 / 9–6 |
| HARD < IMPOSSIBLE | 30 | 14 | 15 | 1 | 0 | 0 | 48% (31–66%) | 0.49 | 572 | 7–8 / 7–7 |

- EASY < MEDIUM: clears the 80% bar (96% of 25 decided, 1 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (57% of 30 decided, 0 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (48% of 29 decided, 1 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 354 | 111 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 367 | 114 | ok |
| easy_v_medium_map7101_base | elimination | MEDIUM | 510 | 160 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 449 | 146 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 348 | 93 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 563 | 154 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 363 | 105 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 552 | 170 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 636 | 185 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 431 | 131 | ok |
| easy_v_medium_map7105_base | elimination | MEDIUM | 435 | 137 | ok |
| easy_v_medium_map7105_swap | elimination | EASY | 691 | 217 | ok |
| easy_v_medium_map7106_base | elimination | MEDIUM | 349 | 112 | ok |
| easy_v_medium_map7106_swap | elimination | MEDIUM | 719 | 243 | ok |
| easy_v_medium_map7107_base | elimination | MEDIUM | 380 | 130 | ok |
| easy_v_medium_map7107_swap | elimination | MEDIUM | 487 | 193 | ok |
| easy_v_medium_map7108_base | elimination | MEDIUM | 864 | 294 | ok |
| easy_v_medium_map7108_swap | elimination | MEDIUM | 400 | 129 | ok |
| easy_v_medium_map7109_base | stalemate | - | 1200 | 408 | ok |
| easy_v_medium_map7109_swap | elimination | MEDIUM | 396 | 133 | ok |
| easy_v_medium_map7110_base | elimination | MEDIUM | 599 | 206 | ok |
| easy_v_medium_map7110_swap | elimination | MEDIUM | 512 | 215 | ok |
| easy_v_medium_map7111_base | elimination | MEDIUM | 287 | 94 | ok |
| easy_v_medium_map7111_swap | elimination | MEDIUM | 466 | 187 | ok |
| easy_v_medium_map7112_base | elimination | MEDIUM | 453 | 153 | ok |
| easy_v_medium_map7112_swap | elimination | EASY | 794 | 360 | script_error |
| easy_v_medium_map7113_base | elimination | MEDIUM | 468 | 156 | script_error |
| easy_v_medium_map7113_swap | elimination | MEDIUM | 450 | 140 | script_error |
| easy_v_medium_map7114_base | elimination | MEDIUM | 367 | 133 | script_error |
| easy_v_medium_map7114_swap | elimination | MEDIUM | 395 | 151 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 521 | 227 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 424 | 167 | ok |
| medium_v_hard_map7101_base | elimination | HARD | 427 | 182 | ok |
| medium_v_hard_map7101_swap | elimination | HARD | 445 | 189 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 594 | 284 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 623 | 294 | ok |
| medium_v_hard_map7103_base | elimination | MEDIUM | 404 | 179 | ok |
| medium_v_hard_map7103_swap | elimination | MEDIUM | 570 | 254 | ok |
| medium_v_hard_map7104_base | elimination | MEDIUM | 440 | 213 | ok |
| medium_v_hard_map7104_swap | elimination | MEDIUM | 978 | 394 | ok |
| medium_v_hard_map7105_base | elimination | HARD | 1125 | 370 | ok |
| medium_v_hard_map7105_swap | elimination | MEDIUM | 466 | 139 | ok |
| medium_v_hard_map7106_base | elimination | MEDIUM | 602 | 200 | ok |
| medium_v_hard_map7106_swap | elimination | HARD | 452 | 145 | ok |
| medium_v_hard_map7107_base | elimination | HARD | 753 | 269 | ok |
| medium_v_hard_map7107_swap | elimination | HARD | 569 | 178 | ok |
| medium_v_hard_map7108_base | elimination | MEDIUM | 522 | 191 | ok |
| medium_v_hard_map7108_swap | elimination | HARD | 652 | 224 | ok |
| medium_v_hard_map7109_base | elimination | MEDIUM | 776 | 246 | ok |
| medium_v_hard_map7109_swap | elimination | HARD | 455 | 162 | ok |
| medium_v_hard_map7110_base | elimination | MEDIUM | 278 | 96 | ok |
| medium_v_hard_map7110_swap | elimination | MEDIUM | 534 | 182 | ok |
| medium_v_hard_map7111_base | elimination | HARD | 332 | 107 | ok |
| medium_v_hard_map7111_swap | elimination | HARD | 470 | 163 | ok |
| medium_v_hard_map7112_base | elimination | HARD | 636 | 214 | ok |
| medium_v_hard_map7112_swap | elimination | MEDIUM | 801 | 258 | ok |
| medium_v_hard_map7113_base | elimination | HARD | 861 | 283 | ok |
| medium_v_hard_map7113_swap | elimination | MEDIUM | 548 | 168 | ok |
| medium_v_hard_map7114_base | elimination | HARD | 497 | 177 | ok |
| medium_v_hard_map7114_swap | elimination | HARD | 343 | 120 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 500 | 194 | ok |
| hard_v_impossible_map7100_swap | elimination | IMPOSSIBLE | 1020 | 537 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 556 | 255 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 574 | 318 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 324 | 123 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 366 | 134 | ok |
| hard_v_impossible_map7103_base | elimination | HARD | 624 | 253 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 905 | 374 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 406 | 155 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 568 | 217 | ok |
| hard_v_impossible_map7105_base | stalemate | - | 1200 | 599 | ok |
| hard_v_impossible_map7105_swap | elimination | HARD | 354 | 113 | ok |
| hard_v_impossible_map7106_base | elimination | HARD | 442 | 212 | ok |
| hard_v_impossible_map7106_swap | elimination | HARD | 423 | 167 | ok |
| hard_v_impossible_map7107_base | elimination | IMPOSSIBLE | 670 | 365 | ok |
| hard_v_impossible_map7107_swap | elimination | IMPOSSIBLE | 410 | 203 | ok |
| hard_v_impossible_map7108_base | elimination | HARD | 627 | 205 | ok |
| hard_v_impossible_map7108_swap | elimination | IMPOSSIBLE | 633 | 263 | ok |
| hard_v_impossible_map7109_base | elimination | HARD | 429 | 149 | ok |
| hard_v_impossible_map7109_swap | elimination | HARD | 346 | 126 | ok |
| hard_v_impossible_map7110_base | elimination | HARD | 496 | 196 | ok |
| hard_v_impossible_map7110_swap | elimination | HARD | 617 | 202 | ok |
| hard_v_impossible_map7111_base | elimination | HARD | 389 | 161 | ok |
| hard_v_impossible_map7111_swap | elimination | IMPOSSIBLE | 478 | 198 | ok |
| hard_v_impossible_map7112_base | elimination | IMPOSSIBLE | 507 | 248 | ok |
| hard_v_impossible_map7112_swap | elimination | IMPOSSIBLE | 528 | 229 | ok |
| hard_v_impossible_map7113_base | elimination | IMPOSSIBLE | 656 | 241 | ok |
| hard_v_impossible_map7113_swap | elimination | HARD | 1052 | 447 | ok |
| hard_v_impossible_map7114_base | elimination | IMPOSSIBLE | 466 | 219 | ok |
| hard_v_impossible_map7114_swap | elimination | IMPOSSIBLE | 583 | 284 | ok |
