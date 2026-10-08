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
