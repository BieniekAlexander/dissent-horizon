class_name TestExpectation
extends Resource

## One check against a running [TestScenario]: a [Condition] that must become true before a
## deadline. Authored in the editor as an element of TestScenario.expectations.
##
## Semantics are LIVENESS ("eventually, by a deadline"): the expectation PASSES the first
## physics tick its condition reports true, as long as that happens at or before
## [member deadline_ticks]; it FAILS the tick the deadline elapses still untrue. A
## condition that becomes true and later flips back still counts as passed — it was
## satisfied in time. This matches checks like "before 300 ticks the drone should have an
## Attack command" or "before 3000 ticks every scout point should have been seen".
##
## Conditions reuse the scenario Condition module, so any existing Condition works and new
## checks are just new Condition subclasses (e.g. ConditionUnitHasCommand,
## ConditionScoutCoverage).

## Human-readable label shown in the test report.
@export var description: String = ""

## The check to satisfy. Any Condition subclass.
@export var condition: Condition

## Physics-tick budget: the condition must be met at or before this many ticks after the
## scenario starts. 0 means "no deadline" — it's only required to be true by the scenario's
## max_ticks ceiling.
@export var deadline_ticks: int = 0
