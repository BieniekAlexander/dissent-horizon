extends GutTest

## The netplay input buffer: turns by tick and commander, a tick confirmed once every
## commander's turn has arrived, and one application order on every peer.
## gdd/systems/commands/netplay.md §The model. Orders are plain data; no scenario is needed.

const A: int = 1
const B: int = 2


func _buffer(a_first_tick: int = 0) -> InputBuffer:
	return InputBuffer.new([B, A] as Array[int], a_first_tick)


func _order(a_commander: int, a_autocast: String) -> PlayerOrder:
	return PlayerOrder.new(PlayerOrder.Kind.AUTOCAST, a_commander, {"ability": a_autocast})


func _turn(a_tick: int, a_commander: int, a_orders: Array[PlayerOrder] = []) -> Turn:
	return Turn.new(a_tick, a_commander, a_orders)


func test_a_tick_is_confirmed_only_once_every_commander_sent_it() -> void:
	var buffer: InputBuffer = _buffer()
	buffer.add(_turn(0, A))
	assert_false(buffer.is_confirmed(0), "B's turn for tick 0 has not arrived")
	assert_eq(buffer.missing_for(0), [B] as Array[int])
	buffer.add(_turn(0, B))
	assert_true(buffer.is_confirmed(0))
	assert_eq(buffer.confirmed_tick(), 0)


func test_an_empty_turn_confirms_a_tick() -> void:
	var buffer: InputBuffer = _buffer()
	buffer.add(_turn(0, A))
	buffer.add(_turn(0, B))
	assert_true(buffer.is_confirmed(0))
	assert_eq(buffer.orders_for(0), [] as Array[PlayerOrder])


func test_a_gap_holds_confirmation_back_until_it_is_filled() -> void:
	var buffer: InputBuffer = _buffer()
	for t: int in [0, 2, 3]:
		buffer.add(_turn(t, A))
		buffer.add(_turn(t, B))
	assert_eq(buffer.confirmed_tick(), 0, "tick 1 is missing for both")
	buffer.add(_turn(1, A))
	assert_eq(buffer.confirmed_tick(), 0, "still missing for B")
	buffer.add(_turn(1, B))
	assert_eq(buffer.confirmed_tick(), 3)


func test_orders_come_out_by_commander_then_as_given() -> void:
	var buffer: InputBuffer = _buffer()
	var b_first: PlayerOrder = _order(B, "b1")
	var b_second: PlayerOrder = _order(B, "b2")
	var a_only: PlayerOrder = _order(A, "a1")
	# B's arrives first; A's still applies first, because the order must not depend on arrival.
	buffer.add(_turn(0, B, [b_first, b_second] as Array[PlayerOrder]))
	buffer.add(_turn(0, A, [a_only] as Array[PlayerOrder]))
	assert_eq(buffer.orders_for(0), [a_only, b_first, b_second] as Array[PlayerOrder])


func test_an_unconfirmed_tick_yields_no_orders() -> void:
	var buffer: InputBuffer = _buffer()
	buffer.add(_turn(0, A, [_order(A, "a1")] as Array[PlayerOrder]))
	assert_eq(buffer.orders_for(0), [] as Array[PlayerOrder])


func test_a_turn_stamps_its_orders_with_its_tick() -> void:
	var order: PlayerOrder = _order(A, "a1")
	_turn(7, A, [order] as Array[PlayerOrder])
	assert_eq(order.tick, 7)


func test_a_resent_turn_is_accepted_and_changes_nothing() -> void:
	var buffer: InputBuffer = _buffer()
	buffer.add(_turn(0, A, [_order(A, "a1")] as Array[PlayerOrder]))
	var again: InputBuffer.Refusal = buffer.add(
		_turn(0, A, [_order(A, "a1")] as Array[PlayerOrder])
	)
	assert_eq(again, InputBuffer.Refusal.NONE)
	assert_eq(buffer.turn(0, A).orders.size(), 1)


func test_a_contradicting_turn_is_refused() -> void:
	var buffer: InputBuffer = _buffer()
	buffer.add(_turn(0, A, [_order(A, "a1")] as Array[PlayerOrder]))
	var other: InputBuffer.Refusal = buffer.add(
		_turn(0, A, [_order(A, "different")] as Array[PlayerOrder])
	)
	assert_eq(other, InputBuffer.Refusal.CONTRADICTS)
	assert_eq(str(buffer.turn(0, A).orders[0].data["ability"]), "a1", "the first one stands")


func test_a_turn_for_another_slot_is_refused() -> void:
	assert_eq(_buffer().add(_turn(0, 9)), InputBuffer.Refusal.UNKNOWN_COMMANDER)


func test_nothing_before_the_first_tick_is_waited_for() -> void:
	var buffer: InputBuffer = _buffer(5)
	assert_eq(buffer.confirmed_tick(), 4)
	buffer.add(_turn(5, A))
	buffer.add(_turn(5, B))
	assert_eq(buffer.confirmed_tick(), 5)
	assert_eq(buffer.add(_turn(4, A)), InputBuffer.Refusal.TOO_OLD)


func test_discarded_ticks_are_refused_and_confirmation_holds() -> void:
	var buffer: InputBuffer = _buffer()
	for t: int in [0, 1]:
		buffer.add(_turn(t, A))
		buffer.add(_turn(t, B))
	buffer.discard_through(0)
	assert_null(buffer.turn(0, A))
	assert_eq(buffer.add(_turn(0, A)), InputBuffer.Refusal.TOO_OLD)
	assert_eq(buffer.confirmed_tick(), 1)
