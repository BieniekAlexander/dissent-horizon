class_name OrderStream
extends Node

## Where players' orders enter the simulation: queued as they are given, applied at the START of
## the next tick, live and replayed alike. Live play gains up to one tick of latency, and in
## exchange a replay cannot differ from the match it recorded.
## gdd/systems/commands/recording-and-replay.md §The order stream.
##
## In playback the stream ignores anything submitted and applies the recorded orders instead,
## each on the tick it was applied on when recorded.
##
## In a networked match (join_lockstep) an order is handed to the Lockstep session instead, which
## stamps it for a later tick and exchanges it with every peer; a tick runs only once every
## peer's orders for it are in, and the world is held (REASON_NETWORK_WAIT) until then.
## gdd/systems/commands/netplay.md §The model.

## An order was applied this tick. `results` is what the giver's interface acts on afterwards
## (OrderDispatcher.apply): waypoint messages for a command, the landed pieces for a drop.
signal order_applied(order: PlayerOrder, results: Array)

## Ahead of every entity, bot and system in the tick, so an order is part of the tick's input
## rather than something that lands partway through it.
const START_OF_TICK_PRIORITY: int = -1000

var _scenario: Scenario
## Orders given since the last tick, oldest first.
var _pending: Array[PlayerOrder] = []
## In playback: the recorded orders still to apply, by tick. Empty in live play.
var _playback: Array[PlayerOrder] = []
var _is_playback: bool = false
## The networked match this stream belongs to, or null in a single-machine session.
var _lockstep: Lockstep = null
## In a networked match, the newest tick whose orders have been applied: a tick is applied once
## however many frames the world stays held on it.
var _applied_through: int = -1
## This stream holds the world for a late turn. Its own flag, not the clock's count: NetMatch
## holds by the same reason (the start barrier, a desync), and those holds are not this one's.
var _is_holding_for_turns: bool = false


func _init(a_scenario: Scenario = null) -> void:
	_scenario = a_scenario
	name = "OrderStream"
	process_physics_priority = START_OF_TICK_PRIORITY
	# Runs through a pause, to apply the one order that ends one: a dialog's. Everything else
	# waits for the world to resume, as an order given during a scripted beat always has.
	process_mode = Node.PROCESS_MODE_ALWAYS


## The stream of the scenario `a_node` is in, or null outside one (a bare controller or HUD
## piece in a test) — where an order is applied at once instead.
static func of(node: Node) -> OrderStream:
	var scenario: Scenario = Scenario.of(node) if node.is_inside_tree() else null
	return scenario.order_stream if scenario != null else null


## Queue `a_order` for the start of the next tick. Ignored in playback: a replay's orders are
## the recording's.
func submit(order: PlayerOrder) -> void:
	if _is_playback:
		return
	if _lockstep != null:
		_lockstep.submit(order)
	else:
		_pending.append(order)


## Take part in a networked match through `a_lockstep`, from the next tick on. Orders given
## after this go through the session.
func join_lockstep(a_lockstep: Lockstep) -> void:
	_lockstep = a_lockstep
	# Orders given before the match started (the world was held) go out in its first turn.
	for order: PlayerOrder in _pending:
		_lockstep.submit(order)
	_pending.clear()
	_applied_through = (_scenario.tick if _scenario != null else 0) - 1


func is_networked() -> bool:
	return _lockstep != null


## Switch to playback: apply `a_orders` (each stamped with the tick it was applied on), and
## nothing submitted from now on.
func play_back(orders: Array[PlayerOrder]) -> void:
	_is_playback = true
	_pending.clear()
	_playback = orders.duplicate()
	_playback.sort_custom(func(a: PlayerOrder, b: PlayerOrder) -> bool: return a.tick < b.tick)


func is_playback() -> bool:
	return _is_playback


func _physics_process(_a_delta: float) -> void:
	if _scenario == null:
		return
	# The tick being simulated, read before Scenario counts it: what an order is stamped with
	# live and what playback matches on, so the two agree by construction.
	var now: int = _scenario.tick
	var is_paused: bool = is_inside_tree() and get_tree().paused
	if _is_playback:
		var waiting: Array[PlayerOrder] = []
		while not _playback.is_empty() and _playback[0].tick <= now:
			var next: PlayerOrder = _playback.pop_front()
			if _applies_now(next, is_paused):
				_apply(next, now)
			else:
				waiting.append(next)
		_playback = waiting + _playback
		return
	if _lockstep != null:
		_run_lockstep(now)
		return
	var due: Array[PlayerOrder] = _pending
	_pending = []
	for order: PlayerOrder in due:
		if _applies_now(order, is_paused):
			_apply(order, now)
		else:
			_pending.append(order)


## While the world is paused only a dialog's order applies: it is what resumes it.
static func _applies_now(order: PlayerOrder, is_paused: bool) -> bool:
	return not is_paused or order.kind == PlayerOrder.Kind.DIALOG


## One physics frame of a networked match: seal and exchange turns, then either hold the world on
## `a_now` until every peer's turn for it is in, or apply its orders. Runs first in the frame, so
## a hold taken here stops every simulation node for the whole frame, and a release runs them.
func _run_lockstep(a_now: int) -> void:
	_lockstep.seal(a_now)
	_lockstep.pump()
	var clock: SimulationClock = _clock()
	var is_waiting: bool = not _lockstep.can_run(a_now)
	if clock != null and is_waiting != _is_holding_for_turns:
		_is_holding_for_turns = is_waiting
		if is_waiting:
			clock.hold(SimulationClock.REASON_NETWORK_WAIT)
		else:
			clock.release(SimulationClock.REASON_NETWORK_WAIT)
	if is_waiting or a_now <= _applied_through or (clock != null and clock.is_paused()):
		return
	_applied_through = a_now
	for order: PlayerOrder in _lockstep.take(a_now):
		_apply(order, a_now)


## The scenario's clock, or null outside one (a bare stream in a test, where nothing is held).
func _clock() -> SimulationClock:
	var manager: ScenarioTriggerManager = _scenario.trigger_manager() if _scenario != null else null
	return manager.simulation_clock if manager != null else null


func _apply(order: PlayerOrder, now: int) -> void:
	order.tick = now
	order_applied.emit(order, OrderDispatcher.apply(order, _scenario))
