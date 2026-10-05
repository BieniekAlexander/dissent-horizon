#!/usr/bin/env python3
"""Run the GUT suite as several Godot processes at once, and report it as one run.

    python3 tools/gut_shards/gut_shards.py              # the whole suite
    python3 tools/gut_shards/gut_shards.py --jobs 6     # more processes
    python3 tools/gut_shards/gut_shards.py MapGen Hull  # only files whose name contains these

One Godot process is single-threaded, so the suite in one process leaves most cores idle. This
splits the test files into shards, runs each shard as its own `gut_cmdln.gd` process, and merges
their JUnit reports into one summary. Each process runs with `--fixed-fps 30`, which keeps every
seeded result identical (CLAUDE.md §Running and testing).

SHARDS ARE BALANCED BY TIME, not by file count: one map-generation file outweighs a hundred
small ones. Each run records every file's time in `.godot/gut_shards/timings.json`, and the next
run deals the files out longest first, each to the shard with the least time so far. A file
with no recorded time weighs the median of those that have one.

A FILE THAT REPORTS NOTHING IS A FAILURE. A shard that crashes, or a file GUT could not parse,
leaves files missing from the merged report; they are listed and the run exits non-zero, so a
silent skip can never read as green.

Logs and JUnit reports of the latest run stay in `.godot/gut_shards/` (git-ignored).

Within a shard, files run in name order, as they do in a single-process run. What differs is
which files share a process, so a test that leans on state another file left behind can pass
here and fail there, or the reverse.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[2]
TESTS_DIR: str = "tests"
TEST_GLOB: str = "test_*.gd"
OUTPUT_DIR: Path = REPO_ROOT / ".godot" / "gut_shards"
TIMINGS_FILE: str = "timings.json"

# Measured 2026-10-05 on an 11-core Mac: 3 shards 33 s, 4 shards 26 s, 6 shards 26 s. At four,
# the slowest shard is already the largest single file alone, which no shard count can split.
DEFAULT_JOBS: int = 4
# Weight of a file when NO file has a recorded time yet (a first run): all equal.
UNTIMED_SECONDS: float = 1.0

GUT_ARGS: tuple[str, ...] = (
    "--headless",
    "--fixed-fps",
    "30",
    "-s",
    "addons/gut/gut_cmdln.gd",
    "-gexit",
)
RES_PREFIX: str = "res://"


@dataclass(frozen=True)
class TestResult:
    """One testcase from a JUnit report. `status` is GUT's: pass, fail, pending or risky."""

    file: str
    name: str
    status: str
    seconds: float
    message: str


@dataclass(frozen=True)
class ShardOutcome:
    """What one shard's process left behind. `results` is empty when it wrote no report."""

    index: int
    files: tuple[str, ...]
    return_code: int
    wall_seconds: float
    log_path: Path
    results: tuple[TestResult, ...]


@dataclass(frozen=True)
class Summary:
    counts: dict[str, int] = field(default_factory=dict)
    failures: tuple[TestResult, ...] = ()
    missing_files: tuple[str, ...] = ()
    unreported_shards: tuple[int, ...] = ()

    def is_green(self) -> bool:
        return not (self.failures or self.missing_files or self.unreported_shards)


# --- pure core ----------------------------------------------------------------------------


def discover(repo_root: Path, patterns: Sequence[str]) -> list[str]:
    """Every test file as a res:// path, in name order; filtered by substring when given."""
    paths: list[Path] = sorted((repo_root / TESTS_DIR).rglob(TEST_GLOB))
    return [
        RES_PREFIX + path.relative_to(repo_root).as_posix()
        for path in paths
        if not patterns or any(pattern in path.name for pattern in patterns)
    ]


def weigh(files: Sequence[str], timings: dict[str, float]) -> dict[str, float]:
    """Each file's expected seconds: its recorded time, else the median recorded time."""
    known: list[float] = [timings[f] for f in files if f in timings]
    fallback: float = statistics.median(known) if known else UNTIMED_SECONDS
    return {f: timings.get(f, fallback) for f in files}


def balance(weights: dict[str, float], jobs: int) -> list[list[str]]:
    """Longest-first to the lightest shard; each shard's files then back in name order.

    Never more shards than files, and never an empty one."""
    shard_count: int = max(1, min(jobs, len(weights)))
    shards: list[list[str]] = [[] for _ in range(shard_count)]
    loads: list[float] = [0.0] * shard_count
    # Mutable buckets: dealing is inherently sequential (each choice depends on the loads so far).
    for file in sorted(weights, key=lambda f: (-weights[f], f)):
        lightest: int = loads.index(min(loads))
        shards[lightest].append(file)
        loads[lightest] += weights[file]
    return [sorted(shard) for shard in shards if shard]


def parse_junit(xml_text: str) -> list[TestResult]:
    """GUT's JUnit report as results. Suite names are repo-relative; they come back as res://."""
    root: ET.Element = ET.fromstring(xml_text)
    return [
        TestResult(
            file=RES_PREFIX + (suite.get("name") or ""),
            name=case.get("name") or "",
            status=case.get("status") or "",
            seconds=float(case.get("time") or 0.0),
            message=_case_message(case),
        )
        for suite in root.iter("testsuite")
        for case in suite.iter("testcase")
    ]


def _case_message(case: ET.Element) -> str:
    detail: ET.Element | None = case.find("failure")
    if detail is None:
        detail = case.find("skipped")
    return (detail.text or "").strip() if detail is not None else ""


def file_times(results: Sequence[TestResult]) -> dict[str, float]:
    """Seconds per file, summed over its tests."""
    totals: dict[str, float] = {}
    for result in results:  # an accumulator: a file's tests are scattered through the list
        totals[result.file] = totals.get(result.file, 0.0) + result.seconds
    return totals


def summarize(outcomes: Sequence[ShardOutcome]) -> Summary:
    results: list[TestResult] = [r for o in outcomes for r in o.results]
    reported: set[str] = {r.file for r in results}
    statuses: list[str] = [r.status for r in results]
    return Summary(
        counts={status: statuses.count(status) for status in sorted(set(statuses))},
        failures=tuple(r for r in results if r.status == "fail"),
        missing_files=tuple(f for o in outcomes for f in o.files if f not in reported),
        # A crash, or a shard of only unparseable files (which GUT itself calls a pass, exit 0).
        unreported_shards=tuple(o.index for o in outcomes if not o.results),
    )


def report(summary: Summary, outcomes: Sequence[ShardOutcome], wall_seconds: float) -> str:
    lines: list[str] = []
    for failure in summary.failures:
        lines.append(f"FAIL  {failure.file} :: {failure.name}")
        lines.extend("      " + line for line in failure.message.splitlines()[:5])
    for index in summary.unreported_shards:
        outcome: ShardOutcome = outcomes[index]
        lines.append(
            f"NO REPORT  shard {index} ran no tests (exit {outcome.return_code}): {outcome.log_path}"
        )
    for file in summary.missing_files:
        lines.append(f"MISSING  {file} reported no tests (parse error or crash)")
    total: int = sum(summary.counts.values())
    counts: str = ", ".join(f"{n} {status}" for status, n in summary.counts.items())
    slowest: float = max((o.wall_seconds for o in outcomes), default=0.0)
    lines.append(
        f"{total} tests in {sum(len(o.files) for o in outcomes)} files: {counts}. "
        f"{len(outcomes)} shards, {wall_seconds:.1f}s wall (slowest shard {slowest:.1f}s)."
    )
    lines.append("GREEN" if summary.is_green() else "RED")
    return "\n".join(lines)


# --- shell --------------------------------------------------------------------------------


def run_shard(
    index: int, files: Sequence[str], godot: str, output_dir: Path, on_done: Callable[[str], None]
) -> ShardOutcome:
    xml_path: Path = output_dir / f"shard_{index}.xml"
    log_path: Path = output_dir / f"shard_{index}.log"
    xml_path.unlink(missing_ok=True)
    command: list[str] = [
        godot,
        "--path",
        str(REPO_ROOT),
        *GUT_ARGS,
        "-gtest=" + ",".join(files),
        f"-gjunit_xml_file={xml_path}",
    ]
    started: float = time.monotonic()
    with log_path.open("w") as log:
        return_code: int = subprocess.run(
            # Not check=True: a failing test exits non-zero too, and the report says which.
            command,
            stdout=log,
            stderr=subprocess.STDOUT,
            cwd=REPO_ROOT,
            check=False,
        ).returncode
    wall: float = time.monotonic() - started
    results: list[TestResult] = parse_junit(xml_path.read_text()) if xml_path.exists() else []
    on_done(f"  shard {index}: {len(files)} files, {len(results)} tests, {wall:.1f}s")
    return ShardOutcome(index, tuple(files), return_code, wall, log_path, tuple(results))


def _load_timings(path: Path) -> dict[str, float]:
    try:
        return {str(k): float(v) for k, v in json.loads(path.read_text()).items()}
    except (OSError, ValueError, AttributeError):
        return {}  # no record yet, or an unreadable one: every file weighs the same


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("patterns", nargs="*", help="run only files whose name contains one")
    parser.add_argument("--jobs", type=int, default=DEFAULT_JOBS, help="processes at once")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="binary")
    args = parser.parse_args(argv)

    files: list[str] = discover(REPO_ROOT, args.patterns)
    if not files:
        print("no test files match", args.patterns, file=sys.stderr)
        return 1
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    timings_path: Path = OUTPUT_DIR / TIMINGS_FILE
    timings: dict[str, float] = _load_timings(timings_path)
    shards: list[list[str]] = balance(weigh(files, timings), args.jobs)
    print(f"{len(files)} files in {len(shards)} shards")

    started: float = time.monotonic()
    with ThreadPoolExecutor(max_workers=len(shards)) as pool:
        outcomes: list[ShardOutcome] = list(
            pool.map(
                lambda i: run_shard(i, shards[i], args.godot, OUTPUT_DIR, print),
                range(len(shards)),
            )
        )
    wall: float = time.monotonic() - started

    # Merge, so a filtered run refreshes its own files and keeps every other file's record;
    # a file since deleted drops out.
    measured: dict[str, float] = file_times([r for o in outcomes for r in o.results])
    existing: set[str] = set(discover(REPO_ROOT, []))
    kept: dict[str, float] = {f: t for f, t in {**timings, **measured}.items() if f in existing}
    timings_path.write_text(json.dumps(kept, indent=1, sort_keys=True))
    summary: Summary = summarize(outcomes)
    print(report(summary, outcomes, wall))
    return 0 if summary.is_green() else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
