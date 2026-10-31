extends GutTest

## BotScheduler — one per-tick budget of work units, spent on whichever bot jobs are due. These
## tests drive the clock by hand (BotScheduler.step) with synthetic jobs, so nothing here
## depends on a bot, a map or real time.

var _scheduler: BotScheduler
var _brain: BotBrain
## Names of the jobs in the order they ran.
var _ran: Array[StringName] = []


func before_each() -> void:
	_scheduler = autofree(BotScheduler.new()) as BotScheduler
	_brain = autofree(BotBrain.new()) as BotBrain
	_ran = []


## A job that records itself and reports `a_units`.
func _job(
	a_name: StringName,
	a_period_ticks: int,
	a_priority: int = 0,
	a_units: int = 1,
	a_brain: BotBrain = null
) -> BotJob:
	var seconds: float = float(a_period_ticks) / TimeUtils.ticks_per_second()
	var job := BotJob.new(
		a_name,
		a_brain if a_brain != null else _brain,
		func() -> float: return seconds,
		a_priority,
		func(_allowance: int) -> int:
			_ran.append(a_name)
			return a_units
	)
	_scheduler.register(job)
	return job


func _steps(a_count: int) -> void:
	for _i: int in a_count:
		_scheduler.step()


func test_a_job_runs_once_per_period() -> void:
	_job(&"a", 3)
	_steps(10)  # ticks 1..10: due at 1, then every 3
	assert_eq(_ran, [&"a", &"a", &"a", &"a"])


func test_jobs_due_together_run_by_priority_then_registration() -> void:
	_job(&"low", 5, 1)
	_job(&"high", 5, 9)
	_job(&"also_low", 5, 1)
	_steps(1)
	assert_eq(_ran, [&"high", &"low", &"also_low"])


func test_a_live_priority_orders_a_job_by_what_it_says_now() -> void:
	var climbing := _job(&"climbing", 5, 1)
	_job(&"fixed", 5, 5)
	var state: Dictionary = {"high": true}  # a lambda captures a value, so the flag is boxed
	climbing.priority_now = func() -> int: return 9 if state["high"] else 1
	_steps(1)
	assert_eq(_ran, [&"climbing", &"fixed"], "it climbs while its callable says so")
	state["high"] = false
	_ran = []
	_steps(5)
	assert_eq(_ran, [&"fixed", &"climbing"], "and drops back when it stops")


func test_an_earlier_due_job_runs_first_whatever_its_priority() -> void:
	_job(&"urgent", 1, 9, BotScheduler.WORK_UNITS_PER_TICK)  # spends the whole tick, every tick
	var patient := _job(&"patient", 1, 0)
	_steps(1)
	assert_eq(_ran, [&"urgent"], "the patient job waits once the budget is spent")
	patient.due_tick = 0  # now the most overdue
	_ran = []
	_steps(1)
	assert_eq(_ran[0], &"patient", "the oldest due runs first")


func test_an_overspend_is_paid_off_before_anything_else_runs() -> void:
	var expensive := _job(&"expensive", 100, 0, BotScheduler.WORK_UNITS_PER_TICK * 3)
	_job(&"cheap", 1, 0)
	_steps(1)
	assert_eq(_ran, [&"expensive"])
	_ran = []
	_steps(2)
	assert_eq(_ran, [], "two ticks pay off the debt of three budgets")
	_steps(1)
	assert_eq(_ran, [&"cheap"])
	assert_gt(expensive.due_tick, 1, "and the expensive job is not due again yet")


func test_a_pending_sweep_resumes_next_tick_and_only_then_waits_its_period() -> void:
	var remaining: Array[int] = [3]  # three slices of work
	var job := BotJob.new(
		&"sweep",
		_brain,
		func() -> float: return 1.0,
		0,
		func(_allowance: int) -> int:
			remaining[0] -= 1
			_ran.append(&"sweep")
			return 1,
		func() -> bool: return remaining[0] > 0
	)
	_scheduler.register(job)
	_steps(3)
	assert_eq(_ran.size(), 3, "it stays due while part-way through")
	_steps(5)
	assert_eq(_ran.size(), 3, "and waits its full period once finished")


func test_an_inactive_brain_does_not_think() -> void:
	_brain.active = false
	_job(&"a", 1)
	_steps(3)
	assert_eq(_ran, [])


func test_two_bots_share_one_budget() -> void:
	var other: BotBrain = autofree(BotBrain.new()) as BotBrain
	_job(&"first_bot", 1, 0, BotScheduler.WORK_UNITS_PER_TICK)
	_job(&"second_bot", 1, 0, 1, other)
	_steps(1)
	assert_eq(_ran, [&"first_bot"], "the second bot's job waits for budget rather than stacking")
	_steps(1)
	assert_true(_ran.has(&"second_bot"))


## Every brain in a session shares one scheduler, and so one budget — even brains that register
## in the same frame, before the first scheduler has been added to the tree.
func test_brains_registering_in_one_frame_share_one_scheduler() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var first_brain := Node.new()
	var second_brain := Node.new()
	host.add_child(first_brain)
	host.add_child(second_brain)
	var first: BotScheduler = BotScheduler.find_or_create(first_brain, host)
	var second: BotScheduler = BotScheduler.find_or_create(second_brain, host)
	assert_same(second, first)
	await wait_physics_frames(1)
	var schedulers: Array = host.get_children().filter(
		func(n: Node) -> bool: return n is BotScheduler
	)
	assert_eq(schedulers.size(), 1, "one scheduler in the tree")
	assert_same(BotScheduler.find_or_create(first_brain, host), first, "and found once it is in")
