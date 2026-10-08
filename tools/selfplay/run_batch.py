#!/usr/bin/env python3
"""Run a BATCH of self-play matches and append one JSON result per line.

The parameter search the bot roadmap wants (gdd/systems/ai/bot-roadmap.md §The training
harness) is many matches, not one, so this is the interface the next stage drives: hand it a
list of match configs, get back a JSONL file whose every row carries both the parameters that
were played and what happened.

    python3 tools/selfplay/run_batch.py matches.json --out results.jsonl --jobs 2

WHY A POOL OF TWO, and why that is the default: one match saturates one core, and the
machine this was built against has four with 3 GB of RAM. Three concurrent Godots swap. Raise
it only after measuring `wall_seconds` per match at the higher setting -- a batch that runs
twice as many matches half as fast has bought nothing.

INPUT (`matches.json`): either a JSON array of match configs, or a JSONL file with one config
per line. A config is exactly what tools/selfplay/run_match.gd reads (see
gdd/systems/ai/selfplay-harness.md for the schema); this adds one optional key:

    "id": "hard-vs-medium-seed7"   # names the row, and makes --resume able to skip it

OUTPUT (`results.jsonl`): one run_match result object per line, each with `id` and
`batch_status` added. A match that crashed or timed out still gets a row -- a silently
missing result would make a search read a failure as an absence.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

RESULT_BEGIN = "---SELFPLAY-RESULT-BEGIN---"
RESULT_END = "---SELFPLAY-RESULT-END---"
DEFAULT_SCENE = "tools/selfplay/run_match.tscn"


def load_configs(path):
    """Read the match list, accepting a JSON array or one config per line (JSONL)."""
    text = open(path, encoding="utf-8").read().strip()
    if text.startswith("["):
        configs = json.loads(text)
    else:
        configs = [json.loads(line) for line in text.splitlines() if line.strip()]
    for i, config in enumerate(configs):
        config.setdefault("id", "match_%04d" % i)
    return configs


def run_one(config, args):
    """Run one match in its own Godot process and return its result object.

    The config is written to a temp file rather than passed on the command line because it is
    a document, and `--fixed-fps 30` is not optional: it detaches the main loop from wall
    time, which is the difference between a 20-minute match costing ~3 minutes and costing 20.
    """
    match_id = config["id"]
    started = time.time()
    with tempfile.TemporaryDirectory() as workdir:
        config_path = os.path.join(workdir, "match.json")
        out_path = os.path.join(workdir, "result.json")
        with open(config_path, "w", encoding="utf-8") as handle:
            json.dump(config, handle)

        command = [
            args.godot, "--headless", "--path", args.project,
            "--fixed-fps", str(args.fixed_fps), args.scene, "--",
            "config=%s" % config_path, "out=%s" % out_path,
        ]
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, timeout=args.timeout
            )
        except subprocess.TimeoutExpired:
            return _failure(match_id, config, "timeout", started,
                            "killed after %ss of wall clock" % args.timeout)

        if os.path.exists(out_path):
            result = json.load(open(out_path, encoding="utf-8"))
        else:
            result = _from_stdout(completed.stdout)
        if result is None:
            return _failure(match_id, config, "no_result", started,
                            (completed.stderr or "")[-2000:])
        result["event_log"] = _keep_event_log(result.get("event_log", ""), match_id, args.out)

    result["id"] = match_id
    result["batch_status"] = _status(result)
    result["batch_wall_seconds"] = time.time() - started
    return result


def _keep_event_log(path, match_id, out):
    """Move a match's event log out of its temporary directory, which is deleted with the
    match, to `<out without .jsonl>.events/<id>.events.jsonl.gz` beside the batch's rows.
    The new path, or "" when the match wrote none."""
    if not path or not os.path.exists(path):
        return ""
    folder = os.path.splitext(os.path.abspath(out))[0] + ".events"
    os.makedirs(folder, exist_ok=True)
    kept = os.path.join(folder, "%s.events.jsonl.gz" % match_id)
    shutil.move(path, kept)
    return kept


def _status(result):
    """`ok`, `error` (no verdict), or `script_error`: a verdict reached through a GDScript
    runtime error, which without a debugger does not stop the match -- the failing function
    returns a default and play goes on -- so the verdict is not evidence of anything."""
    if not result.get("ok"):
        return "error"
    if result.get("clean") is False:
        return "script_error"
    return "ok"


def _error_line(result):
    """One line of error counts for the progress log, empty for a match that raised none."""
    errors = result.get("errors") or {}
    counts = [(kind, errors.get(kind, 0)) for kind in ("script", "engine", "push_error")]
    return ", ".join("%d %s" % (n, kind) for kind, n in counts if n)


def _from_stdout(stdout):
    """The result as printed between the markers -- the fallback when the out file is
    missing (a crash after printing, a read-only output directory)."""
    if RESULT_BEGIN not in stdout:
        return None
    body = stdout.split(RESULT_BEGIN, 1)[1].split(RESULT_END, 1)[0]
    try:
        return json.loads(body.strip())
    except json.JSONDecodeError:
        return None


def _failure(match_id, config, status, started, detail):
    return {
        "id": match_id, "ok": False, "batch_status": status, "error": detail,
        "batch_wall_seconds": time.time() - started, "config": config,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("matches", help="JSON array or JSONL file of match configs")
    parser.add_argument("--out", default="selfplay_results.jsonl",
                        help="JSONL file to APPEND results to (default: %(default)s)")
    parser.add_argument("--jobs", type=int, default=2,
                        help="concurrent matches; see the module docstring (default: %(default)s)")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"),
                        help="Godot binary (default: $GODOT, else 'godot')")
    parser.add_argument("--project", default=".", help="project directory (default: %(default)s)")
    parser.add_argument("--scene", default=DEFAULT_SCENE, help="runner scene (default: %(default)s)")
    parser.add_argument("--fixed-fps", type=int, default=30,
                        help="engine frame rate; 30 = one physics tick per iteration (default: %(default)s)")
    parser.add_argument("--timeout", type=float, default=1800.0,
                        help="wall-clock kill per match, seconds (default: %(default)s)")
    parser.add_argument("--resume", action="store_true",
                        help="skip ids already present in --out")
    args = parser.parse_args()

    configs = load_configs(args.matches)
    if args.resume and os.path.exists(args.out):
        done = {json.loads(line).get("id") for line in open(args.out, encoding="utf-8") if line.strip()}
        configs = [c for c in configs if c["id"] not in done]
        print("resuming: %d already done, %d to run" % (len(done), len(configs)), file=sys.stderr)

    # Appended as each match finishes rather than written at the end, so a batch that is
    # interrupted -- or watched while it runs -- still has every result it has earned.
    with open(args.out, "a", encoding="utf-8") as sink:
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            for result in pool.map(lambda c: run_one(c, args), configs):
                sink.write(json.dumps(result) + "\n")
                sink.flush()
                print("%-28s %-16s %-12s winner=%-3s %6.0f sim-s  %6.1f wall-s  %s" % (
                    result["id"], result.get("outcome", result["batch_status"]),
                    result["batch_status"], result.get("winner", "-"),
                    result.get("simulated_seconds", 0.0),
                    result.get("wall_seconds", result.get("batch_wall_seconds", 0.0)),
                    _error_line(result),
                ), file=sys.stderr)

    print("wrote %s" % args.out, file=sys.stderr)


if __name__ == "__main__":
    main()
