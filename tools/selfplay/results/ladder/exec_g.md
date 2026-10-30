# Difficulty ladder: exec_g.jsonl

| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 30 | 29 | 1 | 0 | 0 | 0 | 97% (83–99%) | 0.87 | 538 | 14–1 / 15–0 |
| MEDIUM < HARD | 30 | 12 | 9 | 5 | 4 | 0 | 57% (37–76%) | 0.54 | 728 | 8–5 / 4–4 |
| HARD < IMPOSSIBLE | 30 | 21 | 8 | 1 | 0 | 0 | 72% (54–85%) | 0.68 | 539 | 10–5 / 11–3 |

- EASY < MEDIUM: clears the 80% bar (97% of 30 decided, 0 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (57% of 21 decided, 5 stalemates, 4 cut by the wall clock)
- HARD < IMPOSSIBLE: FAILS the 80% bar (72% of 29 decided, 1 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 709 | 207 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 529 | 150 | ok |
| easy_v_medium_map7101_base | elimination | MEDIUM | 655 | 229 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 1128 | 483 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 542 | 152 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 751 | 166 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 442 | 122 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 528 | 141 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 789 | 195 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 469 | 140 | ok |
| easy_v_medium_map7105_base | elimination | MEDIUM | 439 | 104 | ok |
| easy_v_medium_map7105_swap | elimination | EASY | 778 | 193 | ok |
| easy_v_medium_map7106_base | elimination | MEDIUM | 397 | 102 | ok |
| easy_v_medium_map7106_swap | elimination | MEDIUM | 637 | 166 | ok |
| easy_v_medium_map7107_base | elimination | MEDIUM | 627 | 147 | ok |
| easy_v_medium_map7107_swap | elimination | MEDIUM | 356 | 101 | ok |
| easy_v_medium_map7108_base | elimination | MEDIUM | 255 | 59 | ok |
| easy_v_medium_map7108_swap | elimination | MEDIUM | 496 | 116 | ok |
| easy_v_medium_map7109_base | elimination | MEDIUM | 384 | 106 | ok |
| easy_v_medium_map7109_swap | elimination | MEDIUM | 544 | 261 | ok |
| easy_v_medium_map7110_base | elimination | MEDIUM | 346 | 80 | ok |
| easy_v_medium_map7110_swap | elimination | MEDIUM | 347 | 272 | ok |
| easy_v_medium_map7111_base | elimination | MEDIUM | 828 | 615 | ok |
| easy_v_medium_map7111_swap | elimination | MEDIUM | 572 | 469 | ok |
| easy_v_medium_map7112_base | elimination | MEDIUM | 371 | 314 | ok |
| easy_v_medium_map7112_swap | elimination | MEDIUM | 327 | 262 | ok |
| easy_v_medium_map7113_base | elimination | MEDIUM | 387 | 304 | ok |
| easy_v_medium_map7113_swap | elimination | MEDIUM | 414 | 342 | ok |
| easy_v_medium_map7114_base | elimination | MEDIUM | 532 | 457 | ok |
| easy_v_medium_map7114_swap | elimination | MEDIUM | 552 | 527 | ok |
| medium_v_hard_map7100_base | wall_clock_cap | - | 609 | 900 | ok |
| medium_v_hard_map7100_swap | wall_clock_cap | - | 886 | 900 | ok |
| medium_v_hard_map7101_base | wall_clock_cap | - | 726 | 900 | ok |
| medium_v_hard_map7101_swap | elimination | HARD | 643 | 708 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 634 | 610 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 457 | 478 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 459 | 436 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 369 | 376 | ok |
| medium_v_hard_map7104_base | elimination | MEDIUM | 850 | 875 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 542 | 726 | ok |
| medium_v_hard_map7105_base | wall_clock_cap | - | 1026 | 900 | ok |
| medium_v_hard_map7105_swap | elimination | MEDIUM | 434 | 418 | ok |
| medium_v_hard_map7106_base | elimination | MEDIUM | 487 | 424 | ok |
| medium_v_hard_map7106_swap | stalemate | - | 1200 | 427 | ok |
| medium_v_hard_map7107_base | elimination | HARD | 494 | 167 | ok |
| medium_v_hard_map7107_swap | elimination | HARD | 983 | 320 | ok |
| medium_v_hard_map7108_base | stalemate | - | 1200 | 327 | ok |
| medium_v_hard_map7108_swap | stalemate | - | 1200 | 371 | ok |
| medium_v_hard_map7109_base | elimination | MEDIUM | 556 | 213 | ok |
| medium_v_hard_map7109_swap | elimination | HARD | 442 | 162 | ok |
| medium_v_hard_map7110_base | elimination | MEDIUM | 362 | 144 | ok |
| medium_v_hard_map7110_swap | stalemate | - | 1200 | 515 | ok |
| medium_v_hard_map7111_base | elimination | HARD | 982 | 407 | ok |
| medium_v_hard_map7111_swap | elimination | HARD | 332 | 120 | ok |
| medium_v_hard_map7112_base | elimination | HARD | 1189 | 472 | ok |
| medium_v_hard_map7112_swap | elimination | MEDIUM | 499 | 193 | ok |
| medium_v_hard_map7113_base | elimination | MEDIUM | 1038 | 433 | ok |
| medium_v_hard_map7113_swap | elimination | MEDIUM | 313 | 118 | ok |
| medium_v_hard_map7114_base | elimination | HARD | 534 | 237 | ok |
| medium_v_hard_map7114_swap | stalemate | - | 1200 | 492 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 598 | 341 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 531 | 247 | ok |
| hard_v_impossible_map7101_base | stalemate | - | 1200 | 749 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 764 | 512 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 357 | 178 | ok |
| hard_v_impossible_map7102_swap | elimination | IMPOSSIBLE | 521 | 273 | ok |
| hard_v_impossible_map7103_base | elimination | IMPOSSIBLE | 648 | 334 | ok |
| hard_v_impossible_map7103_swap | elimination | IMPOSSIBLE | 374 | 190 | ok |
| hard_v_impossible_map7104_base | elimination | IMPOSSIBLE | 748 | 431 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 443 | 212 | ok |
| hard_v_impossible_map7105_base | elimination | IMPOSSIBLE | 390 | 201 | ok |
| hard_v_impossible_map7105_swap | elimination | HARD | 495 | 224 | ok |
| hard_v_impossible_map7106_base | elimination | IMPOSSIBLE | 431 | 227 | ok |
| hard_v_impossible_map7106_swap | elimination | IMPOSSIBLE | 473 | 243 | ok |
| hard_v_impossible_map7107_base | elimination | IMPOSSIBLE | 426 | 212 | ok |
| hard_v_impossible_map7107_swap | elimination | IMPOSSIBLE | 512 | 255 | ok |
| hard_v_impossible_map7108_base | elimination | IMPOSSIBLE | 768 | 362 | ok |
| hard_v_impossible_map7108_swap | elimination | IMPOSSIBLE | 501 | 236 | ok |
| hard_v_impossible_map7109_base | elimination | IMPOSSIBLE | 375 | 195 | ok |
| hard_v_impossible_map7109_swap | elimination | HARD | 359 | 207 | ok |
| hard_v_impossible_map7110_base | elimination | HARD | 524 | 283 | ok |
| hard_v_impossible_map7110_swap | elimination | IMPOSSIBLE | 365 | 155 | ok |
| hard_v_impossible_map7111_base | elimination | HARD | 397 | 185 | ok |
| hard_v_impossible_map7111_swap | elimination | IMPOSSIBLE | 540 | 252 | ok |
| hard_v_impossible_map7112_base | elimination | HARD | 1037 | 511 | ok |
| hard_v_impossible_map7112_swap | elimination | IMPOSSIBLE | 410 | 192 | ok |
| hard_v_impossible_map7113_base | elimination | HARD | 365 | 154 | ok |
| hard_v_impossible_map7113_swap | elimination | HARD | 446 | 205 | ok |
| hard_v_impossible_map7114_base | elimination | IMPOSSIBLE | 438 | 248 | ok |
| hard_v_impossible_map7114_swap | elimination | IMPOSSIBLE | 737 | 306 | ok |
