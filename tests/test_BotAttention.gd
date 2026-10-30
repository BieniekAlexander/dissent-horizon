extends GutTest

## BotAttention — the orders-per-second budget a bot's deciding jobs draw on. Pure: a clock
## reading in, a yes/no out. The gate itself (BotBrain._attentive) is tested through a brain
## below with a stub actuator count, since what it charges is the actuator's action count.


func _attention(a_rate: float) -> BotAttention:
	var attention := BotAttention.new()
	attention.orders_per_second = a_rate
	return attention


func test_unlimited_is_always_available_and_never_charged() -> void:
	var attention: BotAttention = _attention(-1.0)
	attention.refill(0.0)
	attention.spend(100)
	assert_true(attention.is_available())
	assert_eq(attention.balance(), INF)
	assert_eq(attention.wait_seconds(), 0.0)


func test_the_first_refill_fills_the_bank() -> void:
	var attention: BotAttention = _attention(2.0)
	attention.refill(50.0)
	assert_almost_eq(attention.balance(), 2.0 * BotAttention.BANK_SECONDS, 1e-9)
	assert_true(attention.is_available())


func test_spending_past_the_balance_is_debt_that_time_pays_off() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(0.0)  # 3 in hand
	attention.spend(5)  # -2
	assert_false(attention.is_available())
	assert_almost_eq(attention.wait_seconds(), 2.0, 1e-9)
	attention.refill(1.0)
	assert_false(attention.is_available(), "one second pays half the debt")
	attention.refill(2.5)
	assert_true(attention.is_available(), "and the rest clears it")
	assert_almost_eq(attention.balance(), 0.5, 1e-9)


func test_the_balance_never_banks_more_than_the_bank() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(0.0)
	attention.refill(1000.0)
	assert_almost_eq(attention.balance(), BotAttention.BANK_SECONDS, 1e-9)


func test_a_clock_that_does_not_advance_adds_nothing() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(10.0)
	attention.spend(3)
	attention.refill(10.0)
	attention.refill(9.0)
	assert_almost_eq(attention.balance(), 0.0, 1e-9)
	assert_false(attention.is_available())


func test_nothing_issued_costs_nothing() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(0.0)
	attention.spend(0)
	attention.spend(-4)
	assert_almost_eq(attention.balance(), BotAttention.BANK_SECONDS, 1e-9)


# ─── THE GATE ────────────────────────────────────────────────────────────────


## A Bot whose clock is set by hand; the brain's gate reads nothing else of it.
class StubBot:
	extends Bot
	var now: float = 0.0

	func seconds_elapsed() -> float:
		return now


var _bot: StubBot
var _brain: BotBrain
var _runs: int = 0


func before_each() -> void:
	_bot = StubBot.new()
	add_child_autofree(_bot)
	_brain = BotBrain.new()
	_bot.add_child(_brain)
	_brain.bot = _bot
	_brain._actuator = BotActuator.new(null)
	_runs = 0


## A job's work that counts its runs and issues `a_actions` through the actuator's counter.
func _work(a_actions: int) -> Callable:
	return func(_allowance: int) -> int:
		_runs += 1
		_brain._actuator.actions_issued += a_actions
		return 10


func test_an_unlimited_brain_runs_every_time() -> void:
	var gated: Callable = _brain._attentive(&"a", _work(50))
	for _i: int in 5:
		gated.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 5)


func test_a_job_that_issues_nothing_is_never_starved() -> void:
	_brain.attention.orders_per_second = 0.1
	var gated: Callable = _brain._attentive(&"a", _work(0))
	for _i: int in 20:
		gated.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 20)


func test_a_burst_of_orders_idles_the_job_until_the_debt_is_paid() -> void:
	_brain.attention.orders_per_second = 1.0
	var gated: Callable = _brain._attentive(&"a", _work(9))  # bank 3, so 6 in debt
	assert_eq(gated.call(BotJob.UNLIMITED_WORK_UNITS), 10, "the first run goes ahead")
	assert_eq(_runs, 1)
	_bot.now = 5.0
	assert_eq(
		gated.call(BotJob.UNLIMITED_WORK_UNITS),
		BotBrain.IDLE_JOB_WORK_UNITS,
		"five seconds in it is still a second in debt, and idles"
	)
	assert_eq(_runs, 1)
	_bot.now = 6.5
	gated.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 2, "once the balance is positive it runs again")


func test_two_jobs_share_one_balance() -> void:
	_brain.attention.orders_per_second = 1.0
	var first: Callable = _brain._attentive(&"first", _work(3))
	var second: Callable = _brain._attentive(&"second", _work(1))
	first.call(BotJob.UNLIMITED_WORK_UNITS)  # bank 3 → 0
	second.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 1, "the second job finds nothing in hand")


# ─── THE TURN IS FAIR ─────────────────────────────────────────────────────────
# Jobs on the combat cadence are due three times as often as the economy and production, so
# without a queue they took every refill and a throttled bot never trained again once its army
# was fighting (2026-10-30, exec_e maps 7105/7106: every producer idle, 32k energy banked).


func test_a_refused_job_is_owed_the_next_turn() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(0.0)  # 3 in hand
	assert_true(attention.claim(&"military"))
	attention.spend(3)  # 0 in hand
	assert_false(attention.claim(&"production"), "nothing in hand")
	assert_true(attention.is_waiting(&"production"))
	attention.refill(1.0)  # 1 in hand
	assert_false(attention.claim(&"military"), "the refill is production's, it waited")
	assert_true(attention.is_waiting(&"military"), "and military now queues behind it")
	assert_true(attention.claim(&"production"))
	assert_false(attention.is_waiting(&"production"))
	attention.spend(1)
	attention.refill(2.0)
	assert_true(attention.claim(&"military"), "then military's turn comes")


func test_a_job_queues_once_however_often_it_is_refused() -> void:
	var attention: BotAttention = _attention(1.0)
	attention.refill(0.0)
	attention.spend(3)
	for _i: int in 5:
		attention.claim(&"economy")
	attention.claim(&"scout")
	attention.refill(1.0)
	assert_true(attention.claim(&"economy"))
	attention.refill(2.0)
	assert_true(attention.claim(&"scout"), "second in the queue, not sixth")


func test_unlimited_attention_has_no_queue() -> void:
	var attention: BotAttention = _attention(-1.0)
	assert_true(attention.claim(&"a"))
	assert_true(attention.claim(&"b"))
	assert_false(attention.is_waiting(&"a"))


func test_the_gate_marks_a_refused_job_pending_so_it_retries_next_tick() -> void:
	_brain.attention.orders_per_second = 1.0
	var military: Callable = _brain._attentive(&"military", _work(9))
	var production: Callable = _brain._attentive(&"production", _work(1))
	var pending: Callable = _brain._attention_pending(&"production")
	military.call(BotJob.UNLIMITED_WORK_UNITS)  # 6 in debt
	assert_false(pending.call(), "not yet refused")
	assert_eq(production.call(BotJob.UNLIMITED_WORK_UNITS), BotBrain.IDLE_JOB_WORK_UNITS)
	assert_true(pending.call(), "refused: the scheduler keeps it due")
	_bot.now = 7.0  # 1 in hand
	military.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 1, "military does not jump the queue")
	production.call(BotJob.UNLIMITED_WORK_UNITS)
	assert_eq(_runs, 2)
	assert_false(pending.call())
	assert_eq(_brain.attention_spent_by_job, {&"military": 9, &"production": 1})


func test_the_pending_test_also_carries_the_jobs_own_sweep() -> void:
	# A lambda captures a local BY VALUE, so the sweep flag lives in a dictionary it reads.
	var sweep: Dictionary = {"pending": true}
	var pending: Callable = _brain._attention_pending(
		&"economy", func() -> bool: return bool(sweep["pending"])
	)
	assert_true(pending.call())
	sweep["pending"] = false
	assert_false(pending.call())
