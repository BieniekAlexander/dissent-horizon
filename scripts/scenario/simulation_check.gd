class_name SimulationCheck
extends RefCounted

## One leaf of a [SimulationScenario]'s expectations at RUNTIME: a predicate, plus the
## temporal fold that turns its per-tick truth into a single verdict.
##
## A temporal mode is an OPERATOR and a WINDOW, and all three are the same mechanism:
##
##   AT_END    sample, at the final tick
##   LIVENESS  `or`,   from the start until true, else until the deadline
##   SAFETY    `and`,  every tick of the run
##
## So a safety check accumulates `verdict = verdict and predicate.call()` from `true`, and a
## liveness check is that shape with `or` from `false` and an early exit. A new mode is a new
## (operator, window) pair rather than a new branch — see
## gdd/systems/scenario-scripting/simulation-tests.md §A leaf carries the temporal mode.
##
## THE FOLD IS PER LEAF. Every leaf is therefore determinate by the end of a run, which is
## what lets [SimulationExpectNode] evaluate a boolean tree ONCE, at the end, over verdicts —
## including a tree that mixes an at-end leaf with a safety leaf under one `any`.
##
## The predicate is a [Callable] so the two authoring routes produce the same object: an
## editor-authored [SimulationExpectation] wraps its [Condition], and a parsed spec wraps a
## check from SimCheckLibrary. Neither route is privileged.

enum Mode {
	AT_END,    ## sampled once, when the window elapses
	LIVENESS,  ## must become true at or before `deadline_ticks`
	SAFETY,    ## must never be false
}

#region Properties
## What this leaf claims, for the run report.
var description: String = ""

var mode: Mode = Mode.AT_END

## LIVENESS only: the tick by which the predicate must have been true. 0 means "no deadline
## of its own" — the run window is the deadline.
var deadline_ticks: int = 0

## The physics tick the fold settled on: for LIVENESS the tick it first held, for SAFETY the
## tick it was first violated, and -1 while it has not settled (or for AT_END, which settles
## only at the end).
var met_tick: int = -1

## `() -> bool`. Never called after the check resolves.
var _predicate: Callable

var _verdict: bool = false
var _resolved: bool = false
#endregion


func _init(a_description: String, a_predicate: Callable, a_mode: Mode = Mode.AT_END,
		a_deadline_ticks: int = 0) -> void:
	description = a_description
	_predicate = a_predicate
	mode = a_mode
	deadline_ticks = a_deadline_ticks
	# SAFETY folds with `and`, so it starts from the identity of `and`; the other two fold
	# with `or` or a final sample, and start from false.
	_verdict = mode == Mode.SAFETY


## Fold one physics tick into the verdict. Cheap and idempotent once resolved.
func advance(a_tick: int) -> void:
	if _resolved:
		return
	match mode:
		Mode.LIVENESS:
			if _predicate.call():
				_verdict = true
				met_tick = a_tick
				_resolved = true
			elif deadline_ticks > 0 and a_tick >= deadline_ticks:
				_verdict = false
				_resolved = true
		Mode.SAFETY:
			if not _predicate.call():
				_verdict = false
				met_tick = a_tick
				_resolved = true
		_:
			pass  # AT_END is sampled by finish(), not folded


## Settle whatever the window did not. An unresolved LIVENESS check ran out of window and
## fails; an unviolated SAFETY check holds; an AT_END check is sampled here and only here.
func finish(a_tick: int) -> void:
	if _resolved:
		return
	if mode == Mode.AT_END:
		_verdict = _predicate.call()
		met_tick = a_tick if _verdict else -1
	_resolved = true


## True once nothing further can change this check's verdict. A run may stop early only when
## every check says so AND none of them is a mode whose window is the whole run — see
## SimulationScenario._may_finish_early.
func is_resolved() -> bool:
	return _resolved


func passed() -> bool:
	return _verdict


## Whether this check's meaning depends on the run playing out its full window. An at-end
## check is defined by the final tick and a safety check by every tick, so neither can be
## short-circuited; a liveness check is finished the moment it holds.
func needs_full_window() -> bool:
	return mode != Mode.LIVENESS


## One line for the run report.
func report_line() -> String:
	if not _resolved:
		return "[????] %s (never settled)" % description
	var detail: String = ""
	match mode:
		Mode.LIVENESS:
			detail = "met at tick %d" % met_tick if _verdict else "deadline elapsed"
		Mode.SAFETY:
			detail = "held throughout" if _verdict else "violated at tick %d" % met_tick
		_:
			detail = "true at end" if _verdict else "false at end"
	return "[%s] %s (%s)" % ["PASS" if _verdict else "FAIL", description, detail]
