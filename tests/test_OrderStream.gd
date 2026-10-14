extends GutTest

## Orders enter the simulation through the scenario's OrderStream: queued as given, applied at
## the start of the next tick, and in playback taken from the recording alone.
## gdd/systems/commands/recording-and-replay.md §The order stream. Every piece is a fake.

var _scenario: Scenario
var _stream: OrderStream
var _piece: Actor


func before_each() -> void:
	_scenario = Scenario.new()
	_scenario.commanders = [Commander.new(), Commander.new()]
	_piece = FakePieces.unit({"weapon": {"ground": 4.0}}) as Actor
	add_child_autofree(_piece)
	_piece.spawn_serial = _scenario.register_piece(_piece)
	_stream = OrderStream.new(_scenario)


func after_each() -> void:
	for commander: Commander in _scenario.commanders:
		commander.free()
	_stream.free()
	_scenario.free()


func _hold_fire_order() -> PlayerOrder:
	return PlayerOrder.new(PlayerOrder.Kind.HOLD_FIRE, 1, {"actors": [_piece.spawn_serial]})


func test_an_order_waits_for_the_start_of_the_next_tick() -> void:
	_stream.submit(_hold_fire_order())
	assert_false(_piece.is_holding_fire, "not applied as it is given")
	_stream._physics_process(0.0)
	assert_true(_piece.is_holding_fire, "applied at the start of the tick")


func test_an_applied_order_is_stamped_with_its_tick() -> void:
	var order: PlayerOrder = _hold_fire_order()
	_scenario.tick = 41
	_stream.submit(order)
	watch_signals(_stream)
	_stream._physics_process(0.0)
	assert_eq(order.tick, 41)
	assert_signal_emitted(_stream, "order_applied")


func test_playback_applies_the_recording_on_its_ticks_and_nothing_else() -> void:
	var recorded: PlayerOrder = _hold_fire_order()
	recorded.tick = 5
	var orders: Array[PlayerOrder] = [recorded]
	_stream.play_back(orders)
	_stream.submit(_hold_fire_order())
	_scenario.tick = 4
	_stream._physics_process(0.0)
	assert_false(_piece.is_holding_fire, "neither the recorded order early nor a live one")
	_scenario.tick = 5
	_stream._physics_process(0.0)
	assert_true(_piece.is_holding_fire)


func test_an_order_round_trips_through_json() -> void:
	var message := CommandMessage.new(null, _piece, null, Vector3(1.0, 2.0, 3.0))
	message.quarter_turns = 3
	var order: PlayerOrder = PlayerOrder.command(1, Attack, [_piece], message, {"queue": true})
	order.tick = 12
	var back: PlayerOrder = PlayerOrder.from_dict(
		JSON.parse_string(JSON.stringify(order.to_dict()))
	)
	assert_eq(back.kind, PlayerOrder.Kind.COMMAND)
	assert_eq(back.tick, 12)
	assert_eq(back.command_type(), Attack)
	var restored: CommandMessage = PlayerOrder.message_from_dict(
		back.data["message"], null, _scenario, null
	)
	assert_same(restored.target, _piece, "the target comes back by its serial")
	assert_eq(restored.world_position, Vector3(1.0, 2.0, 3.0))
	assert_eq(restored.quarter_turns, 3)
	assert_eq(PlayerOrder.pieces_of(back.data["actors"], _scenario), [_piece])


## A dialog is what pauses the world, so its order must apply during the pause — and only it:
## every other order waits for the world to resume, as one given in a scripted beat always has.
func test_while_paused_only_a_dialog_order_applies() -> void:
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	_scenario.add_child(manager)
	var dialog := ScenarioDialog.new()
	manager.raise_dialog(dialog)
	_stream.submit(_hold_fire_order())
	_stream.submit(PlayerOrder.new(PlayerOrder.Kind.DIALOG, 1, {"dialog": dialog.serial}))
	add_child(_stream)
	get_tree().paused = true
	_stream._physics_process(0.0)
	get_tree().paused = false
	assert_true(dialog.is_acknowledged(), "the dialog is resolved during the pause")
	assert_false(_piece.is_holding_fire, "the other order waits")
	_stream._physics_process(0.0)
	assert_true(_piece.is_holding_fire, "and lands once the world runs")
	remove_child(_stream)


func test_a_purchase_is_cancelled_by_its_id() -> void:
	var commander: Commander = _scenario.commanders[1]
	commander.id = 1
	commander.production_queue = ProductionQueue.new(commander)
	var transaction := PurchaseTransaction.new()
	transaction.id = 77
	commander.production_queue.entries.append(transaction)
	_stream.submit(
		PlayerOrder.new(PlayerOrder.Kind.CANCEL_PURCHASE, 1, {"owner": 1, "purchases": [77]})
	)
	_stream._physics_process(0.0)
	assert_null(commander.production_queue.find_by_id(77))


#region Lockstep
## Counts its polls, so a test can see whether the poller ran.
class CountingCondition:
	extends Condition
	var polls: int = 0

	func poll(_a_manager: ScenarioTriggerManager) -> void:
		polls += 1


## A trigger host with a clock, kept out of the tree: an in-tree clock would pause GUT itself.
func _give_scenario_a_clock() -> SimulationClock:
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	manager.simulation_clock = SimulationClock.new()
	_scenario.add_child(manager)
	autofree(manager.simulation_clock)
	return manager.simulation_clock


## A session for commander 1 on `a_network`, with peer 2 commanding commander 2 when `a_with_peer`.
func _lockstep(a_network: LoopbackNetwork, a_delay_ticks: int, a_with_peer: bool) -> Lockstep:
	var others: Dictionary = {2: 2} if a_with_peer else {}
	if a_with_peer:
		a_network.endpoint(2)
	return Lockstep.new(
		a_network.endpoint(1), 1, others, TimeUtils.seconds_from_ticks(a_delay_ticks)
	)


func test_networked_alone_with_no_delay_an_order_applies_as_before() -> void:
	_stream.join_lockstep(_lockstep(LoopbackNetwork.new(), 0, false))
	_stream.submit(_hold_fire_order())
	_stream._physics_process(0.0)
	assert_true(_piece.is_holding_fire, "applied at the start of the next tick")


func test_networked_an_order_applies_after_the_input_delay() -> void:
	_stream.join_lockstep(_lockstep(LoopbackNetwork.new(), 2, false))
	var order: PlayerOrder = _hold_fire_order()
	_stream.submit(order)
	for t: int in 2:
		_scenario.tick = t
		_stream._physics_process(0.0)
		assert_false(_piece.is_holding_fire, "not on tick %d" % t)
	_scenario.tick = 2
	watch_signals(_stream)
	_stream._physics_process(0.0)
	assert_true(_piece.is_holding_fire)
	var applied: PlayerOrder = get_signal_parameters(_stream, "order_applied")[0]
	assert_eq(applied.tick, 2, "stamped with the tick it applied on")


func test_networked_the_world_is_held_until_every_peer_has_sent_the_tick() -> void:
	var clock: SimulationClock = _give_scenario_a_clock()
	var network := LoopbackNetwork.new()
	var lockstep: Lockstep = _lockstep(network, 0, true)
	_stream.join_lockstep(lockstep)
	_stream.submit(_hold_fire_order())
	_stream._physics_process(0.0)
	assert_true(clock.is_held_by(SimulationClock.REASON_NETWORK_WAIT), "peer 2 has not sent tick 0")
	assert_false(_piece.is_holding_fire)
	var remote := Turn.new(0, 2, [] as Array[PlayerOrder])
	network.endpoint(2).send(1, TurnPacket.new(2, -1, [remote] as Array[Turn]).encode())
	network.step()
	_stream._physics_process(0.0)
	assert_false(clock.is_paused(), "released once the tick is confirmed")
	assert_true(_piece.is_holding_fire, "and its orders applied in the same frame")


func test_networked_a_held_tick_is_applied_once() -> void:
	var clock: SimulationClock = _give_scenario_a_clock()
	_stream.join_lockstep(_lockstep(LoopbackNetwork.new(), 0, false))
	_stream.submit(_hold_fire_order())
	clock.hold(SimulationClock.REASON_DIALOG)
	_stream._physics_process(0.0)
	assert_false(_piece.is_holding_fire, "another hold keeps the tick from running")
	clock.release(SimulationClock.REASON_DIALOG)
	watch_signals(_stream)
	_stream._physics_process(0.0)
	_stream._physics_process(0.0)
	assert_signal_emit_count(_stream, "order_applied", 1, "the tick did not advance; once only")


func test_conditions_are_not_polled_through_a_network_wait() -> void:
	var clock := SimulationClock.new()
	var manager := ScenarioTriggerManager.new()
	manager.simulation_clock = clock
	var poller := ConditionPoller.new()
	poller.manager = manager
	var condition := CountingCondition.new()
	poller.add(condition)
	clock.hold(SimulationClock.REASON_NETWORK_WAIT)
	poller._physics_process(0.0)
	assert_eq(condition.polls, 0, "how long a stall lasts differs per machine")
	clock.release(SimulationClock.REASON_NETWORK_WAIT)
	clock.hold(SimulationClock.REASON_DIALOG)
	poller._physics_process(0.0)
	assert_eq(condition.polls, 1, "a dialog's hold is still polled through")
	for node: Node in [clock, manager, poller]:
		node.free()
#endregion
