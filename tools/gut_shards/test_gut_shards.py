"""Tests for the pure core of gut_shards: discovery, weighing, balancing, parsing, summarising.

python3 -m unittest discover -s tools/gut_shards
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from gut_shards import (
    ShardOutcome,
    TestResult,
    balance,
    discover,
    file_times,
    parse_junit,
    summarize,
    weigh,
)

JUNIT: str = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="1" tests="4" >
  <testsuite name="tests/test_A.gd" tests="3" failures="1" skipped="1" time="1.5" >
      <testcase name="test_ok" assertions="1" status="pass" classname="tests/test_A.gd" time="1.0" >
      </testcase>
      <testcase name="test_bad" assertions="1" status="fail" classname="tests/test_A.gd" time="0.25" >
      <failure message="failed"><![CDATA[[1] expected to equal [2]]]></failure></testcase>
      <testcase name="test_later" assertions="0" status="pending" classname="tests/test_A.gd" time="0.25" >
      <skipped message="pending"><![CDATA[not yet]]></skipped></testcase>
  </testsuite>
  <testsuite name="tests/sub/test_B.gd" tests="1" failures="0" skipped="0" time="0.5" >
      <testcase name="test_quiet" assertions="0" status="no asserts" classname="tests/sub/test_B.gd" time="0.5" >
      </testcase>
  </testsuite>
</testsuites>"""


def _outcome(index: int, files: tuple[str, ...], results: tuple[TestResult, ...]) -> ShardOutcome:
    return ShardOutcome(index, files, 0, 1.0, Path(f"shard_{index}.log"), results)


class DiscoverTest(unittest.TestCase):
    def test_finds_test_files_in_subdirectories_in_name_order(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            for name in ["tests/test_B.gd", "tests/test_A.gd", "tests/sub/test_C.gd"]:
                (Path(root) / name).parent.mkdir(parents=True, exist_ok=True)
                (Path(root) / name).write_text("")
            (Path(root) / "tests/_helper.gd").write_text("")
            self.assertEqual(
                discover(Path(root), []),
                ["res://tests/sub/test_C.gd", "res://tests/test_A.gd", "res://tests/test_B.gd"],
            )
            self.assertEqual(
                discover(Path(root), ["B", "C"]),
                ["res://tests/sub/test_C.gd", "res://tests/test_B.gd"],
            )


class WeighTest(unittest.TestCase):
    def test_an_untimed_file_weighs_the_median(self) -> None:
        weights = weigh(["a", "b", "c", "new"], {"a": 1.0, "b": 2.0, "c": 9.0, "gone": 50.0})
        self.assertEqual(weights, {"a": 1.0, "b": 2.0, "c": 9.0, "new": 2.0})

    def test_with_no_record_every_file_weighs_the_same(self) -> None:
        self.assertEqual(len(set(weigh(["a", "b"], {}).values())), 1)


class BalanceTest(unittest.TestCase):
    def test_the_heaviest_files_split_and_the_rest_even_out_the_load(self) -> None:
        weights = {"big1": 10.0, "big2": 9.0, "s1": 1.0, "s2": 1.0, "s3": 1.0}
        shards = balance(weights, 2)
        self.assertEqual(len([s for s in shards if "big1" in s or "big2" in s]), 2)
        self.assertEqual([sum(weights[f] for f in s) for s in shards], [11.0, 11.0])

    def test_every_file_runs_exactly_once_and_shards_are_in_name_order(self) -> None:
        weights = {f"f{i:02d}": float(i % 7) for i in range(30)}
        shards = balance(weights, 4)
        self.assertEqual(sorted(f for shard in shards for f in shard), sorted(weights))
        for shard in shards:
            self.assertEqual(shard, sorted(shard))

    def test_never_more_shards_than_files_nor_an_empty_one(self) -> None:
        self.assertEqual(balance({"a": 1.0, "b": 1.0}, 8), [["a"], ["b"]])
        self.assertEqual(balance({}, 4), [])


class ParseTest(unittest.TestCase):
    def test_reads_every_case_with_its_file_status_time_and_message(self) -> None:
        results = parse_junit(JUNIT)
        self.assertEqual(
            [(r.file, r.name, r.status) for r in results],
            [
                ("res://tests/test_A.gd", "test_ok", "pass"),
                ("res://tests/test_A.gd", "test_bad", "fail"),
                ("res://tests/test_A.gd", "test_later", "pending"),
                ("res://tests/sub/test_B.gd", "test_quiet", "no asserts"),
            ],
        )
        self.assertEqual(results[1].message, "[1] expected to equal [2]")
        self.assertEqual(results[2].message, "not yet")
        self.assertEqual(
            file_times(results), {"res://tests/test_A.gd": 1.5, "res://tests/sub/test_B.gd": 0.5}
        )


class SummarizeTest(unittest.TestCase):
    def test_counts_statuses_and_lists_failures(self) -> None:
        files = ("res://tests/test_A.gd", "res://tests/sub/test_B.gd")
        summary = summarize([_outcome(0, files, tuple(parse_junit(JUNIT)))])
        self.assertEqual(summary.counts, {"fail": 1, "no asserts": 1, "pass": 1, "pending": 1})
        self.assertEqual([f.name for f in summary.failures], ["test_bad"])
        self.assertFalse(summary.is_green())

    def test_a_file_that_reports_nothing_is_missing_and_not_green(self) -> None:
        ok = TestResult("res://tests/test_A.gd", "test_ok", "pass", 0.1, "")
        summary = summarize(
            [_outcome(0, ("res://tests/test_A.gd", "res://tests/test_X.gd"), (ok,))]
        )
        self.assertEqual(summary.missing_files, ("res://tests/test_X.gd",))
        self.assertEqual(summary.unreported_shards, ())
        self.assertFalse(summary.is_green())

    def test_a_shard_with_no_report_is_flagged(self) -> None:
        ok = TestResult("res://tests/test_A.gd", "test_ok", "pass", 0.1, "")
        summary = summarize(
            [
                _outcome(0, ("res://tests/test_A.gd",), (ok,)),
                _outcome(1, ("res://tests/test_B.gd",), ()),
            ]
        )
        self.assertEqual(summary.unreported_shards, (1,))
        self.assertEqual(summary.missing_files, ("res://tests/test_B.gd",))

    def test_passes_and_pendings_alone_are_green(self) -> None:
        results = (
            TestResult("res://tests/test_A.gd", "a", "pass", 0.1, ""),
            TestResult("res://tests/test_A.gd", "b", "pending", 0.1, "later"),
        )
        self.assertTrue(summarize([_outcome(0, ("res://tests/test_A.gd",), results)]).is_green())


if __name__ == "__main__":
    unittest.main()
