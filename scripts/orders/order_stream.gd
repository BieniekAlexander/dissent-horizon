class_name OrderStream
extends Node

## Where players' orders enter the simulation: queued as they are given, applied at the START of
## the next tick, live and replayed alike. Live play gains up to one tick of latency, and in
## exchange a replay cannot differ from the match it recorded.
## gdd/systems/commands/recording-and-replay.md §The order stream.
##
## In playback the stream ignores anything submitted and applies the recorded orders instead,
## each on the tick it was applied on when recorded.

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
	if not _is_playback:
		_pending.append(order)


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


func _apply(order: PlayerOrder, now: int) -> void:
	order.tick = now
	order_applied.emit(order, OrderDispatcher.apply(order, _scenario))
