class_name BotScheduler
extends Node

## THE ONE PLACE EVERY BOT'S THINKING IS PACED — a shared per-tick budget spent on whichever
## bot jobs are due. See gdd/systems/ai/think-scheduling.md.
##
## Each BotJob has its own period. Every physics tick the scheduler tops up a budget of work
## units and spends it on due jobs, earliest due first, then by job priority. A job that
## overspends leaves the budget in debt, and later ticks pay the debt off before anything else
## runs, so the budget holds on average even for a job that cannot stop part-way. A resumable
## sweep stops when its allowance runs out and resumes on the next tick.
##
## THE BUDGET IS COUNTED IN WORK UNITS, never in wall-clock time, so a given seed makes the
## same decisions on every machine. One work unit is calibrated to roughly a microsecond on the
## machine the costs were measured on (each manager names its per-operation costs); wall-clock
## time is recorded per job for reports and never read by a decision.
##
## One scheduler serves every bot in a session: BotBrain.register_jobs finds it or makes it.
## Sharing one budget is what stops two bots' work from landing on the same tick.

## The group the scheduler joins so a brain can find it.
const GROUP: StringName = &"bot_scheduler"

## Work units the AI may spend per physics tick, across every bot.
##
## TODO — the AI's share of a tick is Alex's decision (gdd/deferred.md 1.38). 2000 units is
## ~2 ms on the calibration machine, ~6% of a 33 ms tick, a provisional figure.
const WORK_UNITS_PER_TICK: int = 2000

## Every registered job, in registration order (which breaks the last tie, so the order jobs
## run in is fully determined by the session).
var _jobs: Array[BotJob] = []
## Physics ticks since the scheduler started — the clock job due times are read against.
var _tick: int = 0
## Work units available this tick; negative while paying off a job that overspent.
var _balance: int = 0


## The scheduler serving `a_node`'s scene tree, created as a child of `a_host` if there is
## none yet.
static func find_or_create(a_node: Node, a_host: Node) -> BotScheduler:
	var found: Node = (
		a_node.get_tree().get_first_node_in_group(GROUP) if a_node.is_inside_tree() else null
	)
	if found != null:
		return found as BotScheduler
	var scheduler := BotScheduler.new()
	scheduler.name = "BotScheduler"
	a_host.add_child.call_deferred(scheduler)
	# Joined now rather than on entering the tree, so a second brain registering in the same
	# frame finds this one instead of making another.
	scheduler.add_to_group(GROUP)
	return scheduler


## Add `a_job`, due at once.
func register(a_job: BotJob) -> void:
	a_job.due_tick = _tick
	_jobs.append(a_job)


## Every job of `a_brain`, in registration order.
func jobs_of(a_brain: BotBrain) -> Array[BotJob]:
	return _jobs.filter(func(j: BotJob) -> bool: return j.brain == a_brain)


func _physics_process(_a_delta: float) -> void:
	step()


## One tick of the schedule. Public so a test can drive the clock without a physics server.
func step() -> void:
	_tick += 1
	_jobs = _jobs.filter(func(j: BotJob) -> bool: return is_instance_valid(j.brain))
	_balance = mini(_balance + WORK_UNITS_PER_TICK, WORK_UNITS_PER_TICK)
	if _balance <= 0:
		return
	for job: BotJob in _due_jobs():
		if _balance <= 0:
			break
		var started: int = Time.get_ticks_usec()
		var spent: int = maxi(1, int(job.work.call(_balance)))
		job.last_usec = Time.get_ticks_usec() - started
		job.last_units = spent
		job.last_run_tick = _tick
		_balance -= spent
		# A sweep that stopped part-way stays due at its old tick, so it resumes first.
		if not job.has_pending_work():
			job.due_tick = _tick + job.period_ticks()


## The jobs due now, in the order they run: earliest due, then higher priority, then the
## order they were registered in.
func _due_jobs() -> Array[BotJob]:
	var due: Array[BotJob] = []
	for i: int in _jobs.size():
		var job: BotJob = _jobs[i]
		if job.due_tick <= _tick and job.brain.active:
			due.append(job)
	var order: Dictionary = {}
	for i: int in _jobs.size():
		order[_jobs[i]] = i
	due.sort_custom(
		func(a: BotJob, b: BotJob) -> bool:
			if a.due_tick != b.due_tick:
				return a.due_tick < b.due_tick
			if a.priority != b.priority:
				return a.priority > b.priority
			return order[a] < order[b]
	)
	return due


## Per job: name, the units and microseconds its last run cost, and when it is next due. For
## probes and the debug overlay.
func report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for job: BotJob in _jobs:
		(
			out
			. append(
				{
					"brain": job.brain.get_instance_id(),
					"name": job.name,
					"units": job.last_units,
					"usec": job.last_usec,
					"due_in": job.due_tick - _tick,
					"ran_this_tick": job.last_run_tick == _tick,
				}
			)
		)
	return out
