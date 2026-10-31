# Difficulty ladder: exec_i.jsonl

| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 30 | 25 | 3 | 2 | 0 | 0 | 89% (73–96%) | 0.80 | 480 | 12–2 / 13–1 |
| MEDIUM < HARD | 30 | 18 | 9 | 3 | 0 | 0 | 67% (48–81%) | 0.62 | 623 | 9–5 / 9–4 |
| HARD < IMPOSSIBLE | 30 | 17 | 11 | 2 | 0 | 0 | 61% (42–76%) | 0.60 | 564 | 7–6 / 10–5 |

- EASY < MEDIUM: clears the 80% bar (89% of 28 decided, 2 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (67% of 27 decided, 3 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (61% of 28 decided, 2 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 355 | 103 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 277 | 76 | ok |
| easy_v_medium_map7101_base | elimination | MEDIUM | 477 | 141 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 447 | 137 | ok |
| easy_v_medium_map7102_base | stalemate | - | 1200 | 351 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 565 | 155 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 505 | 169 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 417 | 128 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 1139 | 368 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 377 | 126 | ok |
| easy_v_medium_map7105_base | elimination | MEDIUM | 391 | 121 | ok |
| easy_v_medium_map7105_swap | elimination | EASY | 504 | 149 | ok |
| easy_v_medium_map7106_base | elimination | MEDIUM | 349 | 99 | ok |
| easy_v_medium_map7106_swap | elimination | MEDIUM | 256 | 74 | ok |
| easy_v_medium_map7107_base | stalemate | - | 1200 | 321 | ok |
| easy_v_medium_map7107_swap | elimination | MEDIUM | 380 | 134 | ok |
| easy_v_medium_map7108_base | elimination | EASY | 464 | 133 | ok |
| easy_v_medium_map7108_swap | elimination | EASY | 481 | 120 | ok |
| easy_v_medium_map7109_base | elimination | MEDIUM | 287 | 81 | ok |
| easy_v_medium_map7109_swap | elimination | MEDIUM | 570 | 138 | ok |
| easy_v_medium_map7110_base | elimination | MEDIUM | 229 | 54 | ok |
| easy_v_medium_map7110_swap | elimination | MEDIUM | 407 | 121 | ok |
| easy_v_medium_map7111_base | elimination | MEDIUM | 332 | 78 | ok |
| easy_v_medium_map7111_swap | elimination | MEDIUM | 298 | 71 | ok |
| easy_v_medium_map7112_base | elimination | MEDIUM | 327 | 88 | ok |
| easy_v_medium_map7112_swap | elimination | MEDIUM | 378 | 105 | ok |
| easy_v_medium_map7113_base | elimination | MEDIUM | 455 | 110 | ok |
| easy_v_medium_map7113_swap | elimination | MEDIUM | 404 | 93 | ok |
| easy_v_medium_map7114_base | elimination | MEDIUM | 561 | 168 | ok |
| easy_v_medium_map7114_swap | elimination | MEDIUM | 356 | 95 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 469 | 136 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 553 | 179 | ok |
| medium_v_hard_map7101_base | elimination | MEDIUM | 861 | 267 | ok |
| medium_v_hard_map7101_swap | elimination | MEDIUM | 742 | 219 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 307 | 88 | ok |
| medium_v_hard_map7102_swap | elimination | HARD | 477 | 156 | ok |
| medium_v_hard_map7103_base | stalemate | - | 1200 | 276 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 518 | 138 | ok |
| medium_v_hard_map7104_base | elimination | HARD | 999 | 350 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 725 | 269 | ok |
| medium_v_hard_map7105_base | elimination | HARD | 310 | 90 | ok |
| medium_v_hard_map7105_swap | elimination | MEDIUM | 461 | 138 | ok |
| medium_v_hard_map7106_base | stalemate | - | 1200 | 367 | ok |
| medium_v_hard_map7106_swap | elimination | MEDIUM | 779 | 232 | ok |
| medium_v_hard_map7107_base | elimination | HARD | 301 | 86 | ok |
| medium_v_hard_map7107_swap | elimination | HARD | 427 | 127 | ok |
| medium_v_hard_map7108_base | elimination | MEDIUM | 352 | 99 | ok |
| medium_v_hard_map7108_swap | stalemate | - | 1200 | 395 | ok |
| medium_v_hard_map7109_base | elimination | MEDIUM | 424 | 137 | ok |
| medium_v_hard_map7109_swap | elimination | HARD | 497 | 144 | ok |
| medium_v_hard_map7110_base | elimination | MEDIUM | 555 | 177 | ok |
| medium_v_hard_map7110_swap | elimination | MEDIUM | 424 | 131 | ok |
| medium_v_hard_map7111_base | elimination | HARD | 779 | 214 | ok |
| medium_v_hard_map7111_swap | elimination | HARD | 456 | 129 | ok |
| medium_v_hard_map7112_base | elimination | HARD | 671 | 201 | ok |
| medium_v_hard_map7112_swap | elimination | HARD | 738 | 216 | ok |
| medium_v_hard_map7113_base | elimination | HARD | 1004 | 284 | ok |
| medium_v_hard_map7113_swap | elimination | MEDIUM | 622 | 183 | ok |
| medium_v_hard_map7114_base | elimination | HARD | 332 | 107 | ok |
| medium_v_hard_map7114_swap | elimination | HARD | 312 | 97 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 423 | 164 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 652 | 263 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 518 | 219 | ok |
| hard_v_impossible_map7101_swap | stalemate | - | 1200 | 504 | ok |
| hard_v_impossible_map7102_base | elimination | HARD | 1130 | 459 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 684 | 258 | ok |
| hard_v_impossible_map7103_base | elimination | IMPOSSIBLE | 686 | 181 | ok |
| hard_v_impossible_map7103_swap | stalemate | - | 1200 | 529 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 270 | 87 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 448 | 156 | ok |
| hard_v_impossible_map7105_base | elimination | IMPOSSIBLE | 475 | 167 | ok |
| hard_v_impossible_map7105_swap | elimination | IMPOSSIBLE | 567 | 186 | ok |
| hard_v_impossible_map7106_base | elimination | HARD | 342 | 99 | ok |
| hard_v_impossible_map7106_swap | elimination | IMPOSSIBLE | 475 | 205 | ok |
| hard_v_impossible_map7107_base | elimination | IMPOSSIBLE | 382 | 147 | ok |
| hard_v_impossible_map7107_swap | elimination | IMPOSSIBLE | 420 | 134 | ok |
| hard_v_impossible_map7108_base | elimination | HARD | 623 | 192 | ok |
| hard_v_impossible_map7108_swap | elimination | IMPOSSIBLE | 568 | 222 | ok |
| hard_v_impossible_map7109_base | elimination | IMPOSSIBLE | 350 | 125 | ok |
| hard_v_impossible_map7109_swap | elimination | HARD | 319 | 108 | ok |
| hard_v_impossible_map7110_base | elimination | IMPOSSIBLE | 672 | 283 | ok |
| hard_v_impossible_map7110_swap | elimination | HARD | 515 | 176 | ok |
| hard_v_impossible_map7111_base | elimination | IMPOSSIBLE | 497 | 188 | ok |
| hard_v_impossible_map7111_swap | elimination | IMPOSSIBLE | 428 | 179 | ok |
| hard_v_impossible_map7112_base | elimination | IMPOSSIBLE | 497 | 184 | ok |
| hard_v_impossible_map7112_swap | elimination | IMPOSSIBLE | 304 | 106 | ok |
| hard_v_impossible_map7113_base | elimination | IMPOSSIBLE | 357 | 117 | ok |
| hard_v_impossible_map7113_swap | elimination | HARD | 833 | 315 | ok |
| hard_v_impossible_map7114_base | elimination | IMPOSSIBLE | 523 | 210 | ok |
| hard_v_impossible_map7114_swap | elimination | HARD | 559 | 245 | ok |
