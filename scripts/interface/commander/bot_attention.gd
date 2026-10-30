class_name BotAttention
extends RefCounted

## BotAttention — how much a bot can ATTEND TO per second, as a budget of orders.
##
## A human player has one pair of hands: every order is a click, and a player busy with a
## fight is not placing buildings or queueing units. This is that limit as a number. The
## brain refills the balance at `orders_per_second` and a deciding job runs only while the
## balance is positive; every actuator action the job then issues is paid for afterwards, so a
## job that issues a burst drives the balance into DEBT and the bot waits, paying it off,
## before it decides anything else. Perception never pays — looking is free. That is the
## spend latency and the limited concurrency of a human in one mechanism, and the tiers ramp
## it (BotDifficulty.attention_orders_per_second).
##
## THE TURN IS FAIR. A job refused for want of attention joins a queue, and the next positive
## balance goes to the job that has waited longest, whatever is due that tick. Without the
## queue the jobs on the combat cadence — due three times as often as the economy and
## production — took every refill, and a throttled bot stood with every producer idle and
## thirty thousand energy banked for the whole of a match while its army fought (2026-10-30,
## maps 7105 and 7106 of `exec_e`). A human in a fight neglects the base for seconds, not for
## ten minutes; the queue is that.
##
## It is NOT the scheduler's work-unit budget (BotScheduler.WORK_UNITS_PER_TICK): that bounds
## what the AI may cost the machine, the same at every tier; this bounds what the bot may DO,
## and is a handicap. Counted in simulated seconds, so a seed replays the same.
## See gdd/systems/ai/bot-roadmap.md §Difficulty first.

## Seconds of orders the balance may bank. A human cannot store attention, but a small bank
## absorbs the bursts a tick-paced bot makes (one military tick orders every squad at once)
## without turning every quiet second into a lost one.
const BANK_SECONDS: float = 3.0

## Orders per simulated second; -1 (any negative) is unlimited, the play the bot had before
## this class existed. Set through BotBrain._apply_config from the tier.
var orders_per_second: float = -1.0

## Orders in hand; negative while in debt.
var _balance: float = 0.0
## The clock reading at the last refill; -1 until the first, which fills the bank.
var _refilled_at: float = -1.0
## The jobs refused a turn, longest-waiting first. A job appears at most once.
var _waiting: Array[StringName] = []


func is_unlimited() -> bool:
	return orders_per_second < 0.0


## Bring the balance up to `a_now` (simulated seconds): the first call fills the bank, so the
## opening is not a dead stop; later calls add what accrued and cap at the bank.
func refill(a_now: float) -> void:
	if is_unlimited():
		return
	var bank: float = orders_per_second * BANK_SECONDS
	if _refilled_at < 0.0:
		_balance = bank
	else:
		_balance = minf(bank, _balance + orders_per_second * maxf(0.0, a_now - _refilled_at))
	_refilled_at = a_now


## Whether there is attention in hand at all, whoever's turn it is.
func is_available() -> bool:
	return is_unlimited() or _balance > 0.0


## Whether `a_job` may decide now: attention in hand, and no job that was refused earlier
## still waiting for its turn. A refusal queues the job; a grant removes it from the queue.
func claim(a_job: StringName) -> bool:
	if is_unlimited():
		return true
	if is_available() and (_waiting.is_empty() or _waiting[0] == a_job):
		_waiting.erase(a_job)
		return true
	if not _waiting.has(a_job):
		_waiting.append(a_job)
	return false


## Whether `a_job` was refused and is still owed a turn.
func is_waiting(a_job: StringName) -> bool:
	return _waiting.has(a_job)


## Pay for `a_orders` actions just issued. The balance may go negative: a decision already made
## is not unmade, it is paid off in waiting.
func spend(a_orders: int) -> void:
	if is_unlimited() or a_orders <= 0:
		return
	_balance -= float(a_orders)


## Orders in hand (negative in debt); INF when unlimited. For the debug overlay and samples.
func balance() -> float:
	return INF if is_unlimited() else _balance


## How long the bot must wait before it may decide again, in seconds; 0 when it may now.
func wait_seconds() -> float:
	if is_available():
		return 0.0
	return -_balance / orders_per_second
