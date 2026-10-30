# Difficulty ladder: exec_h.jsonl

| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 30 | 28 | 1 | 1 | 0 | 0 | 97% (83–99%) | 0.85 | 560 | 14–1 / 14–0 |
| MEDIUM < HARD | 30 | 14 | 12 | 4 | 0 | 0 | 54% (35–71%) | 0.53 | 735 | 8–5 / 6–7 |
| HARD < IMPOSSIBLE | 30 | 21 | 9 | 0 | 0 | 0 | 70% (52–83%) | 0.65 | 526 | 11–4 / 10–5 |

- EASY < MEDIUM: clears the 80% bar (97% of 29 decided, 1 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (54% of 26 decided, 4 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (70% of 30 decided, 0 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 709 | 252 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 529 | 183 | ok |
| easy_v_medium_map7101_base | elimination | MEDIUM | 731 | 322 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 1154 | 592 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 541 | 182 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 751 | 201 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 478 | 155 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 528 | 169 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 756 | 227 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 475 | 164 | ok |
| easy_v_medium_map7105_base | elimination | MEDIUM | 426 | 123 | ok |
| easy_v_medium_map7105_swap | elimination | EASY | 842 | 355 | ok |
| easy_v_medium_map7106_base | elimination | MEDIUM | 397 | 122 | ok |
| easy_v_medium_map7106_swap | elimination | MEDIUM | 627 | 310 | ok |
| easy_v_medium_map7107_base | elimination | MEDIUM | 600 | 274 | ok |
| easy_v_medium_map7107_swap | elimination | MEDIUM | 354 | 479 | ok |
| easy_v_medium_map7108_base | elimination | MEDIUM | 254 | 618 | ok |
| easy_v_medium_map7108_swap | elimination | MEDIUM | 496 | 796 | ok |
| easy_v_medium_map7109_base | elimination | MEDIUM | 384 | 767 | ok |
| easy_v_medium_map7109_swap | elimination | MEDIUM | 580 | 603 | ok |
| easy_v_medium_map7110_base | elimination | MEDIUM | 346 | 194 | ok |
| easy_v_medium_map7110_swap | elimination | MEDIUM | 347 | 107 | ok |
| easy_v_medium_map7111_base | stalemate | - | 1200 | 319 | ok |
| easy_v_medium_map7111_swap | elimination | MEDIUM | 561 | 172 | ok |
| easy_v_medium_map7112_base | elimination | MEDIUM | 382 | 114 | ok |
| easy_v_medium_map7112_swap | elimination | MEDIUM | 332 | 95 | ok |
| easy_v_medium_map7113_base | elimination | MEDIUM | 391 | 109 | ok |
| easy_v_medium_map7113_swap | elimination | MEDIUM | 414 | 122 | ok |
| easy_v_medium_map7114_base | elimination | MEDIUM | 656 | 202 | ok |
| easy_v_medium_map7114_swap | elimination | MEDIUM | 552 | 183 | ok |
| medium_v_hard_map7100_base | stalemate | - | 1200 | 597 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 1092 | 436 | ok |
| medium_v_hard_map7101_base | stalemate | - | 1200 | 579 | ok |
| medium_v_hard_map7101_swap | elimination | HARD | 708 | 281 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 633 | 206 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 457 | 172 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 565 | 205 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 369 | 137 | ok |
| medium_v_hard_map7104_base | elimination | MEDIUM | 1000 | 333 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 567 | 200 | ok |
| medium_v_hard_map7105_base | stalemate | - | 1200 | 397 | ok |
| medium_v_hard_map7105_swap | elimination | MEDIUM | 414 | 142 | ok |
| medium_v_hard_map7106_base | elimination | MEDIUM | 522 | 161 | ok |
| medium_v_hard_map7106_swap | elimination | HARD | 864 | 269 | ok |
| medium_v_hard_map7107_base | elimination | HARD | 438 | 135 | ok |
| medium_v_hard_map7107_swap | elimination | HARD | 983 | 337 | ok |
| medium_v_hard_map7108_base | stalemate | - | 1200 | 371 | ok |
| medium_v_hard_map7108_swap | elimination | MEDIUM | 654 | 201 | ok |
| medium_v_hard_map7109_base | elimination | MEDIUM | 492 | 165 | ok |
| medium_v_hard_map7109_swap | elimination | HARD | 406 | 136 | ok |
| medium_v_hard_map7110_base | elimination | MEDIUM | 381 | 133 | ok |
| medium_v_hard_map7110_swap | elimination | MEDIUM | 1148 | 410 | ok |
| medium_v_hard_map7111_base | elimination | HARD | 456 | 159 | ok |
| medium_v_hard_map7111_swap | elimination | HARD | 335 | 105 | ok |
| medium_v_hard_map7112_base | elimination | HARD | 1192 | 421 | ok |
| medium_v_hard_map7112_swap | elimination | MEDIUM | 501 | 172 | ok |
| medium_v_hard_map7113_base | elimination | MEDIUM | 1038 | 404 | ok |
| medium_v_hard_map7113_swap | elimination | MEDIUM | 313 | 110 | ok |
| medium_v_hard_map7114_base | elimination | HARD | 534 | 224 | ok |
| medium_v_hard_map7114_swap | elimination | MEDIUM | 1195 | 476 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 461 | 221 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 560 | 253 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 675 | 365 | ok |
| hard_v_impossible_map7101_swap | elimination | IMPOSSIBLE | 995 | 606 | ok |
| hard_v_impossible_map7102_base | elimination | IMPOSSIBLE | 358 | 165 | ok |
| hard_v_impossible_map7102_swap | elimination | IMPOSSIBLE | 521 | 241 | ok |
| hard_v_impossible_map7103_base | elimination | IMPOSSIBLE | 643 | 301 | ok |
| hard_v_impossible_map7103_swap | elimination | IMPOSSIBLE | 380 | 178 | ok |
| hard_v_impossible_map7104_base | elimination | IMPOSSIBLE | 748 | 393 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 443 | 192 | ok |
| hard_v_impossible_map7105_base | elimination | IMPOSSIBLE | 383 | 174 | ok |
| hard_v_impossible_map7105_swap | elimination | HARD | 658 | 317 | ok |
| hard_v_impossible_map7106_base | elimination | IMPOSSIBLE | 431 | 209 | ok |
| hard_v_impossible_map7106_swap | elimination | IMPOSSIBLE | 473 | 208 | ok |
| hard_v_impossible_map7107_base | elimination | IMPOSSIBLE | 447 | 198 | ok |
| hard_v_impossible_map7107_swap | elimination | IMPOSSIBLE | 523 | 240 | ok |
| hard_v_impossible_map7108_base | elimination | IMPOSSIBLE | 787 | 345 | ok |
| hard_v_impossible_map7108_swap | elimination | IMPOSSIBLE | 505 | 215 | ok |
| hard_v_impossible_map7109_base | elimination | IMPOSSIBLE | 370 | 179 | ok |
| hard_v_impossible_map7109_swap | elimination | HARD | 360 | 195 | ok |
| hard_v_impossible_map7110_base | elimination | HARD | 513 | 260 | ok |
| hard_v_impossible_map7110_swap | elimination | IMPOSSIBLE | 360 | 155 | ok |
| hard_v_impossible_map7111_base | elimination | HARD | 397 | 182 | ok |
| hard_v_impossible_map7111_swap | elimination | IMPOSSIBLE | 881 | 409 | ok |
| hard_v_impossible_map7112_base | elimination | IMPOSSIBLE | 400 | 180 | ok |
| hard_v_impossible_map7112_swap | elimination | HARD | 518 | 239 | ok |
| hard_v_impossible_map7113_base | elimination | HARD | 364 | 149 | ok |
| hard_v_impossible_map7113_swap | elimination | HARD | 446 | 177 | ok |
| hard_v_impossible_map7114_base | elimination | IMPOSSIBLE | 438 | 219 | ok |
| hard_v_impossible_map7114_swap | elimination | IMPOSSIBLE | 737 | 264 | ok |
