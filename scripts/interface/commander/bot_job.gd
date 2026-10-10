class_name BotJob
extends RefCounted

## One piece of a bot's thinking that runs on its own period — a manager's tick, or one half
## of a manager that works on two timescales. BotScheduler decides when it runs.
##
## `work` is called with the work units still available this tick and returns the units it
## spent. A job that sweeps can stop early and pick up where it left off: it then reports
## `is_pending` true, stays due, and resumes on the next tick with budget. Every other job
## runs to completion each time and simply reports what it cost.

## An allowance no work runs out of: what a job's work is handed when it is run outside the
## scheduler (BotBrain.think, and a manager ticked directly by a test).
const UNLIMITED_WORK_UNITS: int = 1 << 62

## For reports and debugging only; never compared by code.
var name: StringName
## The brain whose job this is. Its `active` flag switches the job off.
var brain: BotBrain
## Seconds between one completed run and the next being due — read through a Callable so a
## difficulty change (BotBrain.set_config) takes effect without re-registering.
var period_seconds: Callable
## Which of several jobs due on the same tick goes first. Higher runs first.
var priority: int
## (allowance: int) -> int work units spent.
var work: Callable
## () -> bool: true while a resumable sweep is part-way through. Empty for jobs that always
## finish in one call.
var is_pending: Callable

## The scheduler tick at which the job is next due.
var due_tick: int = 0
## What the last run cost, for reporting (BotScheduler.report).
var last_units: int = 0
var last_usec: int = 0
## What every run so far has cost, summed, and how many runs there were — the profile of a
## match (the self-play harness samples them per slot). Never read by a decision.
var total_units: int = 0
var total_usec: int = 0
var runs: int = 0
## The scheduler tick the job last ran on; -1 before its first run.
var last_run_tick: int = -1


func _init(
	a_name: StringName,
	a_brain: BotBrain,
	a_period_seconds: Callable,
	a_priority: int,
	a_work: Callable,
	a_is_pending: Callable = Callable()
) -> void:
	name = a_name
	brain = a_brain
	period_seconds = a_period_seconds
	priority = a_priority
	work = a_work
	is_pending = a_is_pending


## Whether the job stopped part-way through its last run and must resume before counting as
## done.
func has_pending_work() -> bool:
	return is_pending.is_valid() and bool(is_pending.call())


## The period in physics ticks: the seconds converted once, here, at the boundary.
func period_ticks() -> int:
	return maxi(1, roundi(float(period_seconds.call()) * TimeUtils.ticks_per_second()))
