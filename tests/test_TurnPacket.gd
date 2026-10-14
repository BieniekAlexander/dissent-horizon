extends GutTest

## The netplay wire format: a sender's unacknowledged turns and its acknowledgement, round-tripped
## through bytes, and anything malformed refused. gdd/systems/commands/netplay.md §What lockstep
## builds that rollback keeps.


func _command_order() -> PlayerOrder:
	return PlayerOrder.new(PlayerOrder.Kind.HOLD_FIRE, 3, {"actors": [12, 15], "queue": true})


func test_a_packet_round_trips_through_bytes() -> void:
	var turns: Array[Turn] = [
		Turn.new(10, 3, [_command_order()] as Array[PlayerOrder]),
		Turn.new(11, 3),
	]
	var decoded: TurnPacket = TurnPacket.decode(TurnPacket.new(3, 8, turns).encode())
	assert_not_null(decoded)
	assert_eq(decoded.sender_id, 3)
	assert_eq(decoded.ack, 8)
	assert_eq(decoded.turns.size(), 2)
	assert_true(decoded.turns[0].same_as(turns[0]))
	assert_true(decoded.turns[1].is_empty())


func test_decoded_orders_keep_their_data_and_tick() -> void:
	var sent := Turn.new(10, 3, [_command_order()] as Array[PlayerOrder])
	var decoded: TurnPacket = TurnPacket.decode(TurnPacket.new(3, 0, [sent]).encode())
	var order: PlayerOrder = decoded.turns[0].orders[0]
	assert_eq(order.kind, PlayerOrder.Kind.HOLD_FIRE)
	assert_eq(order.commander_id, 3)
	assert_eq(order.tick, 10)
	assert_eq(int(order.data["actors"][1]), 15)


func test_garbage_is_refused() -> void:
	assert_null(TurnPacket.decode("not json".to_utf8_buffer()))
	assert_null(TurnPacket.decode(PackedByteArray()))


func test_another_wire_version_is_refused() -> void:
	var body: Dictionary = {"v": TurnPacket.WIRE_VERSION + 1, "from": 3, "ack": 0, "turns": []}
	assert_null(TurnPacket.decode(JSON.stringify(body).to_utf8_buffer()))


func test_a_turn_that_is_not_the_senders_is_refused() -> void:
	var body: Dictionary = {
		"v": TurnPacket.WIRE_VERSION,
		"from": 3,
		"ack": 0,
		"turns": [Turn.new(1, 4).to_dict()],
	}
	assert_null(TurnPacket.decode(JSON.stringify(body).to_utf8_buffer()))


func test_an_order_of_another_commander_inside_a_turn_is_refused() -> void:
	var foreign: Dictionary = Turn.new(1, 3).to_dict()
	foreign["orders"] = [PlayerOrder.new(PlayerOrder.Kind.AUTOCAST, 4, {}).to_dict()]
	var body: Dictionary = {"v": TurnPacket.WIRE_VERSION, "from": 3, "ack": 0, "turns": [foreign]}
	assert_null(TurnPacket.decode(JSON.stringify(body).to_utf8_buffer()))
