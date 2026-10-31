# Difficulty ladder: exec_k.jsonl

| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |
|---|---|---|---|---|---|---|---|---|---|---|
| EASY < MEDIUM | 30 | 26 | 4 | 0 | 0 | 0 | 87% (70–95%) | 0.81 | 495 | 13–2 / 13–2 |
| MEDIUM < HARD | 30 | 19 | 10 | 1 | 0 | 0 | 66% (47–80%) | 0.62 | 632 | 8–7 / 11–3 |
| HARD < IMPOSSIBLE | 30 | 15 | 15 | 0 | 0 | 0 | 50% (33–67%) | 0.50 | 590 | 4–11 / 11–4 |

- EASY < MEDIUM: clears the 80% bar (87% of 30 decided, 0 stalemates)
- MEDIUM < HARD: FAILS the 80% bar (66% of 29 decided, 1 stalemates)
- HARD < IMPOSSIBLE: FAILS the 80% bar (50% of 30 decided, 0 stalemates)

## Matches

| id | outcome | winner tier | sim-s | wall-s | status |
|---|---|---|---|---|---|
| easy_v_medium_map7100_base | elimination | MEDIUM | 375 | 92 | ok |
| easy_v_medium_map7100_swap | elimination | MEDIUM | 344 | 85 | ok |
| easy_v_medium_map7101_base | elimination | EASY | 1041 | 318 | ok |
| easy_v_medium_map7101_swap | elimination | MEDIUM | 378 | 105 | ok |
| easy_v_medium_map7102_base | elimination | MEDIUM | 337 | 84 | ok |
| easy_v_medium_map7102_swap | elimination | MEDIUM | 630 | 152 | ok |
| easy_v_medium_map7103_base | elimination | MEDIUM | 539 | 141 | ok |
| easy_v_medium_map7103_swap | elimination | MEDIUM | 508 | 130 | ok |
| easy_v_medium_map7104_base | elimination | MEDIUM | 543 | 143 | ok |
| easy_v_medium_map7104_swap | elimination | MEDIUM | 495 | 130 | ok |
| easy_v_medium_map7105_base | elimination | MEDIUM | 420 | 104 | ok |
| easy_v_medium_map7105_swap | elimination | EASY | 804 | 197 | ok |
| easy_v_medium_map7106_base | elimination | MEDIUM | 370 | 90 | ok |
| easy_v_medium_map7106_swap | elimination | MEDIUM | 390 | 98 | ok |
| easy_v_medium_map7107_base | elimination | MEDIUM | 361 | 91 | ok |
| easy_v_medium_map7107_swap | elimination | MEDIUM | 439 | 122 | ok |
| easy_v_medium_map7108_base | elimination | EASY | 495 | 132 | ok |
| easy_v_medium_map7108_swap | elimination | MEDIUM | 453 | 112 | ok |
| easy_v_medium_map7109_base | elimination | MEDIUM | 756 | 183 | ok |
| easy_v_medium_map7109_swap | elimination | MEDIUM | 383 | 99 | ok |
| easy_v_medium_map7110_base | elimination | MEDIUM | 548 | 152 | ok |
| easy_v_medium_map7110_swap | elimination | EASY | 749 | 233 | ok |
| easy_v_medium_map7111_base | elimination | MEDIUM | 317 | 77 | ok |
| easy_v_medium_map7111_swap | elimination | MEDIUM | 324 | 83 | ok |
| easy_v_medium_map7112_base | elimination | MEDIUM | 428 | 112 | ok |
| easy_v_medium_map7112_swap | elimination | MEDIUM | 742 | 264 | ok |
| easy_v_medium_map7113_base | elimination | MEDIUM | 465 | 113 | ok |
| easy_v_medium_map7113_swap | elimination | MEDIUM | 498 | 120 | ok |
| easy_v_medium_map7114_base | elimination | MEDIUM | 340 | 98 | ok |
| easy_v_medium_map7114_swap | elimination | MEDIUM | 388 | 113 | ok |
| medium_v_hard_map7100_base | elimination | HARD | 429 | 126 | ok |
| medium_v_hard_map7100_swap | elimination | HARD | 550 | 172 | ok |
| medium_v_hard_map7101_base | elimination | MEDIUM | 574 | 195 | ok |
| medium_v_hard_map7101_swap | elimination | HARD | 715 | 229 | ok |
| medium_v_hard_map7102_base | elimination | HARD | 432 | 122 | ok |
| medium_v_hard_map7102_swap | elimination | MEDIUM | 755 | 244 | ok |
| medium_v_hard_map7103_base | elimination | HARD | 458 | 155 | ok |
| medium_v_hard_map7103_swap | elimination | HARD | 620 | 224 | ok |
| medium_v_hard_map7104_base | elimination | MEDIUM | 829 | 301 | ok |
| medium_v_hard_map7104_swap | elimination | HARD | 506 | 158 | ok |
| medium_v_hard_map7105_base | elimination | HARD | 559 | 164 | ok |
| medium_v_hard_map7105_swap | elimination | MEDIUM | 905 | 290 | ok |
| medium_v_hard_map7106_base | elimination | HARD | 583 | 181 | ok |
| medium_v_hard_map7106_swap | elimination | HARD | 620 | 208 | ok |
| medium_v_hard_map7107_base | elimination | HARD | 422 | 122 | ok |
| medium_v_hard_map7107_swap | elimination | MEDIUM | 881 | 271 | ok |
| medium_v_hard_map7108_base | elimination | MEDIUM | 362 | 108 | ok |
| medium_v_hard_map7108_swap | elimination | HARD | 878 | 284 | ok |
| medium_v_hard_map7109_base | elimination | HARD | 445 | 146 | ok |
| medium_v_hard_map7109_swap | elimination | MEDIUM | 1142 | 382 | ok |
| medium_v_hard_map7110_base | elimination | MEDIUM | 469 | 160 | ok |
| medium_v_hard_map7110_swap | elimination | HARD | 546 | 176 | ok |
| medium_v_hard_map7111_base | elimination | HARD | 403 | 115 | ok |
| medium_v_hard_map7111_swap | elimination | HARD | 991 | 277 | ok |
| medium_v_hard_map7112_base | elimination | MEDIUM | 615 | 211 | ok |
| medium_v_hard_map7112_swap | stalemate | - | 1200 | 392 | ok |
| medium_v_hard_map7113_base | elimination | HARD | 707 | 207 | ok |
| medium_v_hard_map7113_swap | elimination | HARD | 401 | 115 | ok |
| medium_v_hard_map7114_base | elimination | HARD | 346 | 110 | ok |
| medium_v_hard_map7114_swap | elimination | MEDIUM | 621 | 198 | ok |
| hard_v_impossible_map7100_base | elimination | IMPOSSIBLE | 514 | 175 | ok |
| hard_v_impossible_map7100_swap | elimination | HARD | 806 | 318 | ok |
| hard_v_impossible_map7101_base | elimination | HARD | 417 | 220 | ok |
| hard_v_impossible_map7101_swap | elimination | HARD | 1191 | 1334 | ok |
| hard_v_impossible_map7102_base | elimination | HARD | 351 | 134 | ok |
| hard_v_impossible_map7102_swap | elimination | HARD | 294 | 99 | ok |
| hard_v_impossible_map7103_base | elimination | IMPOSSIBLE | 582 | 388 | ok |
| hard_v_impossible_map7103_swap | elimination | HARD | 764 | 519 | ok |
| hard_v_impossible_map7104_base | elimination | HARD | 468 | 317 | ok |
| hard_v_impossible_map7104_swap | elimination | IMPOSSIBLE | 551 | 786 | ok |
| hard_v_impossible_map7105_base | elimination | IMPOSSIBLE | 530 | 943 | ok |
| hard_v_impossible_map7105_swap | elimination | IMPOSSIBLE | 606 | 756 | ok |
| hard_v_impossible_map7106_base | elimination | IMPOSSIBLE | 538 | 810 | ok |
| hard_v_impossible_map7106_swap | elimination | IMPOSSIBLE | 697 | 1073 | ok |
| hard_v_impossible_map7107_base | elimination | IMPOSSIBLE | 555 | 769 | ok |
| hard_v_impossible_map7107_swap | elimination | HARD | 691 | 893 | ok |
| hard_v_impossible_map7108_base | elimination | HARD | 360 | 494 | ok |
| hard_v_impossible_map7108_swap | elimination | IMPOSSIBLE | 666 | 1007 | ok |
| hard_v_impossible_map7109_base | elimination | IMPOSSIBLE | 412 | 623 | ok |
| hard_v_impossible_map7109_swap | elimination | HARD | 505 | 863 | ok |
| hard_v_impossible_map7110_base | elimination | HARD | 371 | 468 | ok |
| hard_v_impossible_map7110_swap | elimination | HARD | 575 | 821 | ok |
| hard_v_impossible_map7111_base | elimination | IMPOSSIBLE | 391 | 721 | ok |
| hard_v_impossible_map7111_swap | elimination | IMPOSSIBLE | 437 | 648 | ok |
| hard_v_impossible_map7112_base | elimination | HARD | 418 | 624 | ok |
| hard_v_impossible_map7112_swap | elimination | IMPOSSIBLE | 737 | 335 | ok |
| hard_v_impossible_map7113_base | elimination | IMPOSSIBLE | 685 | 317 | ok |
| hard_v_impossible_map7113_swap | elimination | HARD | 1193 | 595 | ok |
| hard_v_impossible_map7114_base | elimination | HARD | 596 | 304 | ok |
| hard_v_impossible_map7114_swap | elimination | IMPOSSIBLE | 799 | 379 | ok |
