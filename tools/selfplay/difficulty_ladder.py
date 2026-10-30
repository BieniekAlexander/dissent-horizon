#!/usr/bin/env python3
"""Measure the difficulty ladder: does each tier beat the tier below it?

    python3 tools/selfplay/difficulty_ladder.py run --maps 5 --jobs 4
    python3 tools/selfplay/difficulty_ladder.py report tools/selfplay/results/ladder/<stamp>.jsonl

THE QUESTION IT ANSWERS (gdd/systems/ai/bot-roadmap.md §Difficulty first): on randomly
generated maps, does the higher of two adjacent tiers win 80% or more of their matches? Every
tier below IMPOSSIBLE is meant to be a handicap of the one above, so a pair that falls short
is a tier whose parameters do not yet buy the strength its name promises.

HOW A PAIR IS MEASURED. For each adjacent pair of tiers and each of `--maps` generated maps
(one `map_seed` per map), two matches are played that differ only in which start point each
slot deploys at (`swap_start_points`): the start-position advantage is larger than most
parameter effects (selfplay-results-2026-09-06.md), and playing both assignments cancels it.
The match `seed` is shared by the two, so each slot's personality draw is the same in both.
Which SLOT the higher tier sits in alternates with the map, since deploy order and think order
follow the slot index and that bias is separate from the position's.

A stalemate at the cap is not a win for anybody and is reported as its own column; the shaped
score (analyze.score: a win beats any stalemate beats any loss) is reported beside the win
rate so a pair that stalls still reads.

Only the Colonial bot is ready to be measured (Alex, 2026-10-28), so both slots are Colonial.
The tiers are played AS SHIPPED, personality draw and decision sampling included, because that
is what a player meets; `--pinned` sets personality_spread and decision_temperature to 0 for a
controlled reading of the tier table alone.

Never run alongside another Godot process: an overlapping import or test run rewrites the
scenes a match is loading (the memory on vision shapes being zeroed).
"""

import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "results"))
import analyze  # noqa: E402  (tools/selfplay/results/analyze.py: the shared scoring)

RUN_BATCH = os.path.join(HERE, "run_batch.py")
RESULTS_DIR = os.path.join(HERE, "results", "ladder")
TIERS = ["PASSIVE", "EASY", "MEDIUM", "HARD", "IMPOSSIBLE"]
## The bar a pair must clear (bot-roadmap.md §Difficulty first).
TARGET_WIN_RATE = 0.8
## How far under run_batch's kill run_match's own wall-clock cap sits, so the row is written.
WALL_CAP_MARGIN_SECONDS = 120.0
## The first map seed; the maps are this and the next `--maps` - 1 seeds. Deliberately not the
## training runs' seeds, so a ladder reading is on maps nothing was tuned on.
DEFAULT_FIRST_MAP_SEED = 7100


def adjacent_pairs(tiers):
    """(lower, higher) for each adjacent pair of the tiers given, in ladder order."""
    ordered = [tier for tier in TIERS if tier in tiers]
    return list(zip(ordered[:-1], ordered[1:]))


def match_configs(pairs, maps, first_map_seed, cap_seconds, pinned, overrides,
                  max_wall_seconds=None):
    """The batch: per pair, per map, both start assignments; the higher tier alternates slots.

    `overrides` is {tier: {field: value}} applied as that tier's `config` block, which is how a
    candidate tier table is tried without editing BotDifficulty.for_tier (selfplay-harness.md
    §Input schema). `max_wall_seconds` is run_match's own wall-clock cap, under which a match
    still writes its row (`wall_clock_cap`); None keeps run_match's default of 900 s, which a
    late game with eighty-unit armies runs into at below real time (exec_g, 2026-10-30).
    """
    configs = []
    for lower, higher in pairs:
        for map_index in range(maps):
            map_seed = first_map_seed + map_index
            higher_slot = map_index % 2
            slots = [None, None]
            slots[higher_slot] = _slot(higher, pinned, overrides)
            slots[1 - higher_slot] = _slot(lower, pinned, overrides)
            for swapped in (False, True):
                configs.append({
                    "id": "%s_v_%s_map%d_%s" % (
                        lower.lower(), higher.lower(), map_seed, "swap" if swapped else "base"),
                    "seed": map_seed,
                    "map_seed": map_seed,
                    "swap_start_points": swapped,
                    "max_simulated_seconds": cap_seconds,
                    **({"max_wall_seconds": max_wall_seconds} if max_wall_seconds else {}),
                    "slots": slots,
                    # Read back by the report; run_match echoes every unknown top-level key? It
                    # does not, so the report re-derives these from `id` and `slots`.
                })
    return configs


def _slot(tier, pinned, overrides):
    config = dict(overrides.get(tier, {}))
    if pinned:
        config["personality_spread"] = 0.0
        config["decision_temperature"] = 0.0
    slot = {"difficulty": tier}
    if config:
        slot["config"] = config
    return slot


def run(args):
    os.makedirs(RESULTS_DIR, exist_ok=True)
    stamp = args.name or time.strftime("%Y-%m-%dT%H%M")
    list_path = os.path.join(RESULTS_DIR, "%s.matches.json" % stamp)
    out_path = os.path.join(RESULTS_DIR, "%s.jsonl" % stamp)
    tiers = args.tiers.split(",") if args.tiers else TIERS[1:]
    overrides = json.load(open(args.overrides, encoding="utf-8")) if args.overrides else {}
    # run_match's cap sits under run_batch's kill, so a slow match reports itself rather than
    # being killed without a row.
    configs = match_configs(adjacent_pairs(tiers), args.maps, args.first_map_seed,
                            args.cap, args.pinned, overrides,
                            max_wall_seconds=args.timeout - WALL_CAP_MARGIN_SECONDS)
    with open(list_path, "w", encoding="utf-8") as handle:
        json.dump(configs, handle, indent=1)
    print("%d matches -> %s" % (len(configs), out_path), file=sys.stderr)
    command = [sys.executable, RUN_BATCH, list_path, "--out", out_path,
               "--jobs", str(args.jobs), "--timeout", str(args.timeout)]
    if args.godot:
        command += ["--godot", args.godot]
    if os.path.exists(out_path):
        command.append("--resume")
    subprocess.run(command, cwd=PROJECT, check=True)
    report(out_path, args.cap)


def _tiers_of(row):
    """(lower, higher, higher_slot) from a result row's slots."""
    tiers = [slot.get("difficulty") for slot in row.get("slots", [])]
    if len(tiers) != 2:
        return None
    ranks = [TIERS.index(tier) for tier in tiers]
    higher_slot = 0 if ranks[0] > ranks[1] else 1
    return tiers[1 - higher_slot], tiers[higher_slot], higher_slot


def report(path, cap):
    """Per pair: wins by the higher tier, by the lower, stalemates; the win rate with its
    Wilson interval against TARGET_WIN_RATE; the shaped score; and the same split by which
    start point the higher tier held, which is what shows a position bias surviving the swap."""
    rows = [row for row in analyze.load(path)]
    by_pair = {}
    for row in rows:
        tiers = _tiers_of(row)
        if tiers is None:
            continue
        lower, higher, higher_slot = tiers
        by_pair.setdefault((lower, higher), []).append((row, higher_slot))

    lines = ["# Difficulty ladder: %s" % os.path.basename(path), "",
             "| pair | n | higher wins | lower wins | stalemate | wall-clock | errors | win rate (95% CI) | score | mean sim-s | by higher's start (A / B) |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    verdicts = []
    for (lower, higher) in sorted(by_pair, key=lambda pair: TIERS.index(pair[1])):
        played = by_pair[(lower, higher)]
        wins = losses = draws = capped = errors = 0
        scores = []
        seconds = []
        by_start = {"A": [0, 0], "B": [0, 0]}
        for row, higher_slot in played:
            if not row.get("ok") or row.get("batch_status") == "script_error":
                errors += 1
                continue
            outcome = analyze.win(row, higher_slot)
            scores.append(analyze.score(row, higher_slot, cap))
            seconds.append(row.get("simulated_seconds", 0.0))
            # Which start point the higher tier held: slot 0 holds the first marker unless the
            # starts were swapped.
            start = "A" if (higher_slot == 0) != bool(row.get("swap_start_points")) else "B"
            if outcome == 1:
                wins += 1
                by_start[start][0] += 1
            elif outcome == 0:
                losses += 1
                by_start[start][1] += 1
            elif row.get("outcome") == "wall_clock_cap":
                capped += 1
            else:
                draws += 1
        decided = wins + losses
        rate = wins / decided if decided else float("nan")
        low, high = analyze.wilson(wins, decided) if decided else (0.0, 1.0)
        mean_score = sum(scores) / len(scores) if scores else float("nan")
        mean_seconds = sum(seconds) / len(seconds) if seconds else float("nan")
        clears = decided > 0 and rate >= TARGET_WIN_RATE
        verdicts.append((lower, higher, rate, decided, draws, capped, clears))
        lines.append("| %s < %s | %d | %d | %d | %d | %d | %d | %.0f%% (%.0f–%.0f%%) | %.2f | %.0f | %d–%d / %d–%d |" % (
            lower, higher, len(played), wins, losses, draws, capped, errors,
            100 * rate if decided else float("nan"), 100 * low, 100 * high, mean_score,
            mean_seconds, by_start["A"][0], by_start["A"][1], by_start["B"][0], by_start["B"][1]))
    lines.append("")
    for lower, higher, rate, decided, draws, capped, clears in verdicts:
        undecided = "%d stalemates" % draws + (", %d cut by the wall clock" % capped if capped else "")
        if decided == 0:
            lines.append("- %s < %s: NO DECIDED MATCH (%s)" % (lower, higher, undecided))
        else:
            lines.append("- %s < %s: %s the %.0f%% bar (%.0f%% of %d decided, %s)" % (
                lower, higher, "clears" if clears else "FAILS", 100 * TARGET_WIN_RATE,
                100 * rate, decided, undecided))
    lines.append("")
    lines.append("## Matches")
    lines.append("")
    lines.append("| id | outcome | winner tier | sim-s | wall-s | status |")
    lines.append("|---|---|---|---|---|---|")
    for row in rows:
        tiers = [slot.get("difficulty") for slot in row.get("slots", [])]
        winner = row.get("winner", -1)
        winner_tier = tiers[winner] if 0 <= winner < len(tiers) else "-"
        lines.append("| %s | %s | %s | %.0f | %.0f | %s |" % (
            row.get("id"), row.get("outcome", "-"), winner_tier,
            row.get("simulated_seconds", 0.0) or 0.0, row.get("wall_seconds", 0.0) or 0.0,
            row.get("batch_status")))
    text = "\n".join(lines) + "\n"
    report_path = os.path.splitext(path)[0] + ".md"
    with open(report_path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print(text)
    print("wrote %s" % report_path, file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    runner = commands.add_parser("run", help="play the ladder and report it")
    runner.add_argument("--maps", type=int, default=5, help="generated maps per pair (default: %(default)s)")
    runner.add_argument("--first-map-seed", type=int, default=DEFAULT_FIRST_MAP_SEED)
    runner.add_argument("--tiers", default="",
                        help="comma-separated tiers to ladder (default: EASY,MEDIUM,HARD,IMPOSSIBLE)")
    runner.add_argument("--cap", type=float, default=1200.0, help="simulated seconds per match")
    runner.add_argument("--jobs", type=int, default=4)
    runner.add_argument("--timeout", type=float, default=1800.0, help="wall-clock kill per match")
    runner.add_argument("--godot", default=os.environ.get("GODOT", ""))
    runner.add_argument("--pinned", action="store_true",
                        help="personality_spread and decision_temperature 0: the tier table exactly")
    runner.add_argument("--overrides", default="",
                        help="JSON file {tier: {field: value}}: a candidate tier table, injected per slot")
    runner.add_argument("--name", default="", help="results file stem (default: a timestamp)")
    reporter = commands.add_parser("report", help="re-read a results file")
    reporter.add_argument("results")
    reporter.add_argument("--cap", type=float, default=1200.0)
    args = parser.parse_args()
    if args.command == "run":
        run(args)
    else:
        report(args.results, args.cap)


if __name__ == "__main__":
    main()
