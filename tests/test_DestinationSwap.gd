extends GutTest

## MoveCommand.is_same_order — the gate on destination swapping.
##
## Units in a multi-unit move periodically trade destinations when that shortens both
## their paths (MoveCommand.swap_trades). That is only ever legitimate
## between units the player commanded TOGETHER.
##
## Regression guard: the gate compares `CommandMessage.origin` by identity, and
## RTSController used to tag every snapshot with its own long-lived `command_message`
## member — one object reused for every click of the session. Every order therefore
## shared an identity and units swapped destinations with units running completely
## unrelated commands. The token is now minted fresh per order.


func _order() -> CommandMessage:
	# Stands in for the per-order token assign_command_to_units mints.
	return CommandMessage.new(null)


func _snapshot(a_origin: CommandMessage) -> CommandMessage:
	var msg: CommandMessage = CommandMessage.new(null)
	msg.origin = a_origin
	return msg


func test_units_from_the_same_order_are_siblings() -> void:
	var order: CommandMessage = _order()
	assert_true(MoveCommand.is_same_order(_snapshot(order), _snapshot(order)))


func test_units_from_different_orders_are_not_siblings() -> void:
	assert_false(
		MoveCommand.is_same_order(_snapshot(_order()), _snapshot(_order())),
		"two separate player orders must never swap destinations"
	)


func test_identical_looking_orders_are_still_separate() -> void:
	# The exact shape of the bug: two orders whose messages carry the same values.
	# Only the token's identity may decide this, never its contents.
	var first: CommandMessage = _order()
	var second: CommandMessage = _order()
	first.world_position = Vector3(5, 0, 5)
	second.world_position = Vector3(5, 0, 5)
	assert_false(MoveCommand.is_same_order(_snapshot(first), _snapshot(second)))


func test_untagged_commands_never_swap() -> void:
	# Single-unit and script-issued commands carry no token.
	assert_false(
		MoveCommand.is_same_order(_snapshot(null), _snapshot(null)),
		"a null origin is nobody's sibling, not even another null"
	)
	assert_false(MoveCommand.is_same_order(_snapshot(null), _snapshot(_order())))
	assert_false(MoveCommand.is_same_order(_snapshot(_order()), _snapshot(null)))


func test_deep_copy_keeps_units_in_their_order() -> void:
	# Snapshots are deep-copied on the way to each unit; dropping origin there would
	# silently disable swapping altogether.
	var order: CommandMessage = _order()
	var copy: CommandMessage = CommandMessage.deep_copy(_snapshot(order))
	assert_true(MoveCommand.is_same_order(copy, _snapshot(order)))


# --- The trades themselves (MoveCommand.swap_trades) ---------------------------------------


func test_crossed_paths_trade() -> void:
	# I stand left heading right; my sibling stands right heading left.
	var trades: Array = MoveCommand.swap_trades(
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		[Vector3(10, 0, 1)] as Array[Vector3],
		[Vector3(0, 0, 1)] as Array[Vector3]
	)
	assert_eq(trades.size(), 1)
	assert_eq(trades[0], [0, Vector3(10, 0, 0), Vector3(0, 0, 1)])


func test_parallel_paths_do_not_trade() -> void:
	var trades: Array = MoveCommand.swap_trades(
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		[Vector3(0, 0, 1)] as Array[Vector3],
		[Vector3(10, 0, 1)] as Array[Vector3]
	)
	assert_eq(trades, [])


## After one trade the unit heads for what it traded for, and later comparisons use that — so
## no destination is ever handed to two units.
func test_a_second_trade_starts_from_what_the_first_gave() -> void:
	# The first sibling crosses me; the second stands on what I win from the first, heading
	# behind me — so I trade the first's destination on to the second.
	var trades: Array = MoveCommand.swap_trades(
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		[Vector3(10, 0, 1), Vector3(0, 0, 1)] as Array[Vector3],
		[Vector3(0, 0, 1), Vector3(0, 0, -3)] as Array[Vector3]
	)
	assert_eq(trades.size(), 2)
	assert_eq(trades[1], [1, Vector3(0, 0, 1), Vector3(0, 0, -3)], "it gives away its prize")
	var given: Array = trades.map(func(t: Array) -> Vector3: return t[1])
	assert_eq(given.count(Vector3(10, 0, 0)), 1, "no destination goes to two units")
