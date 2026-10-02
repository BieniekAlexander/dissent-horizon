extends GutTest

## Selecting a unit that does not exist yet, and giving it orders.
##
## The rule Alex settled: a pending selection carries AGENCY. Orders aimed at a phantom are
## stored on its purchase and replayed the moment the unit spawns; nothing acts on them in
## the meantime, and the requisition system already carries the intent.
##
## `PurchaseTransaction.player_commands` is where such an order lives. It is the ONLY thing a
## purchase carries about where its unit goes: a producer's rally is deliberately not captured
## on the transaction at all, but read off the structure when the unit spawns
## (`Production._spawn_unit`). So the precedence between the two needs no merging rule — a
## purchase either names a destination or it does not, and the rally answers when it does not.
## The rally half is `tests/test_ProductionQueue.gd`; this file is the player-order half.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_PendingUnitOrders.gd -gexit

var _commander: Commander


func before_each() -> void:
	_commander = Commander.new()
	_commander.energy = 100000
	add_child_autofree(_commander)


func _transaction() -> PurchaseTransaction:
	var transaction := PurchaseTransaction.new()
	transaction.commander = _commander
	transaction.type = &"test_piece"
	return transaction


func _order(a_xz: Vector2) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, VU.from_xz(a_xz)))


func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


#region The orderable window
## THE WINDOW RUNS UNTIL THE UNIT APPEARS, not until the purchase is dispatched. A player
## watching a progress bar reaches for the unit being built, and stopping at FUNDED made that
## the one thing on screen that could not be ordered.
func test_a_purchase_takes_orders_at_every_stage_before_its_unit_exists() -> void:
	for state: int in [
		PurchaseTransaction.State.PENDING,
		PurchaseTransaction.State.FUNDED,
		PurchaseTransaction.State.CONSUMED
	]:
		var transaction: PurchaseTransaction = _transaction()
		transaction.state = state
		assert_true(transaction.awaits_its_unit(), "state %d is still waiting" % state)
		assert_true(
			transaction.queue_player_command(_order(Vector2(5, 5)), true),
			"state %d takes orders" % state
		)


## CONSUMED is the one that matters: the purchase has left the production queue and is on a
## producer's bench, reachable only through the info panel's job card.
func test_a_unit_being_trained_still_takes_orders() -> void:
	var transaction: PurchaseTransaction = _transaction()
	transaction.state = PurchaseTransaction.State.CONSUMED
	assert_true(transaction.queue_player_command(_order(Vector2(5, 5)), true))
	assert_eq(transaction.player_commands.size(), 1)


## Nothing is coming, or it has already arrived and is a unit you order in the world.
func test_a_finished_or_cancelled_purchase_refuses_orders() -> void:
	for state: int in [PurchaseTransaction.State.CANCELLED, PurchaseTransaction.State.COMPLETED]:
		var transaction: PurchaseTransaction = _transaction()
		transaction.state = state
		assert_false(transaction.awaits_its_unit(), "state %d is over" % state)
		assert_false(transaction.queue_player_command(_order(Vector2(5, 5)), true))
		assert_true(transaction.player_commands.is_empty())


#endregion


#region Replace versus append
## A plain right-click REPLACES, the additive modifier APPENDS — the same reading those two
## carry for a live unit.
func test_a_plain_order_replaces_what_was_queued() -> void:
	var transaction: PurchaseTransaction = _transaction()
	transaction.queue_player_command(_order(Vector2(1, 1)), true)
	transaction.queue_player_command(_order(Vector2(9, 9)), true)
	assert_eq(transaction.player_commands.size(), 1, "the second order replaced the first")


func test_an_additive_order_appends() -> void:
	var transaction: PurchaseTransaction = _transaction()
	transaction.queue_player_command(_order(Vector2(1, 1)), true)
	transaction.queue_player_command(_order(Vector2(9, 9)), false)
	assert_eq(
		transaction.player_commands.size(), 2, "a phantom can be given a chain before it exists"
	)


#endregion


#region What a purchase carries
## A purchase carries the player's order and NOTHING else — no captured rally. An empty
## `player_commands` is what tells the spawn path to read the producer's rally as it stands.
func test_a_purchase_nobody_ordered_carries_nothing() -> void:
	var transaction: PurchaseTransaction = _transaction()
	assert_true(
		transaction.player_commands.is_empty(),
		"no rally is snapshot here; the structure answers for that at spawn"
	)


func test_an_ordered_purchase_carries_exactly_that_order() -> void:
	var transaction: PurchaseTransaction = _transaction()
	var mine: MoveCommand = _order(Vector2(50, 50))
	transaction.queue_player_command(mine, true)
	assert_eq(transaction.player_commands, [mine] as Array[MoveCommand])


## A standing template keeps re-issuing the orders the player aimed at it, so a clone shares
## them rather than dropping them.
func test_a_standing_clone_keeps_the_players_orders() -> void:
	var transaction: PurchaseTransaction = _transaction()
	transaction.standing = true
	transaction.queue_player_command(_order(Vector2(4, 4)), true)
	var clone: PurchaseTransaction = transaction.clone()
	assert_eq(clone.player_commands.size(), 1)


#endregion


#region The selection channel
func test_selecting_a_phantom_holds_it() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	assert_true(controller.is_pending_selected(transaction))


## A purchase past its orderable window is not selectable — a card the panel has not yet
## rebuilt must not select a phantom whose unit has arrived or been cancelled.
func test_a_finished_purchase_cannot_be_selected() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	transaction.state = PurchaseTransaction.State.COMPLETED
	controller.select_pending([transaction], false)
	assert_false(controller.is_pending_selected(transaction))


## But one being TRAINED is, which is the case the info panel's job cards exist to reach.
func test_a_unit_being_trained_can_be_selected() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	transaction.state = PurchaseTransaction.State.CONSUMED
	controller.select_pending([transaction], false)
	assert_true(controller.is_pending_selected(transaction))


func test_a_plain_selection_replaces_and_an_additive_one_adds() -> void:
	var controller: RTSController = _controller()
	var first: PurchaseTransaction = _transaction()
	var second: PurchaseTransaction = _transaction()
	controller.select_pending([first], false)
	controller.select_pending([second], false)
	assert_false(controller.is_pending_selected(first), "the second press replaced the first")
	controller.select_pending([first], true)
	assert_true(controller.is_pending_selected(first))
	assert_true(controller.is_pending_selected(second), "and kept what was already held")


func test_selecting_the_same_phantom_twice_holds_it_once() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	controller.select_pending([transaction], true)
	assert_eq(controller.pending_selection.size(), 1)


#endregion


#region The two channels
## THE BUG THIS PINS: selecting a phantom used to clear the live selection, and a phantom is
## reached through a card that is ONLY drawn while its producer (or garrison host) is
## selected. So the click destroyed the card it came from, emptied the panel, and left no sign
## anything had happened — indistinguishable from a dead button.
func test_selecting_a_phantom_keeps_the_live_selection() -> void:
	var controller: RTSController = _controller()
	# A live unit: the selection paths ask each member for its Selectable.
	var unit := add_child_autofree(FakePieces.unit(FakePieces.PLAIN)) as Commandable
	controller.selection = [unit] as Array[Node]
	controller.select_pending([_transaction()], false)
	assert_eq(
		controller.selection,
		[unit] as Array[Node],
		"the producer stays selected, so its card — and the phantom's — stay on screen"
	)


## They can both be held because the command path is not ambiguous about them: a right-click
## goes to the phantoms whenever any are selected, which is what clicking their card asked for.
func test_both_channels_can_be_held_at_once() -> void:
	var controller: RTSController = _controller()
	var unit := add_child_autofree(FakePieces.unit(FakePieces.PLAIN)) as Commandable
	controller.selection = [unit] as Array[Node]
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	assert_true(controller.is_pending_selected(transaction))
	assert_false(controller.selection.is_empty())


func test_selecting_live_units_drops_the_phantoms() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	controller.clear_pending_selection()
	assert_false(controller.is_pending_selected(transaction))
	assert_true(controller.pending_selection.is_empty())


#endregion


#region Issuing the order
func test_a_command_reaches_every_selected_phantom() -> void:
	var controller: RTSController = _controller()
	var first: PurchaseTransaction = _transaction()
	var second: PurchaseTransaction = _transaction()
	controller.select_pending([first, second], false)

	var message := CommandMessage.new(null, null, null, VU.from_xz(Vector2(7, 7)))
	assert_true(controller.assign_command_to_pending(MoveCommand, message, false))

	assert_eq(first.player_commands.size(), 1)
	assert_eq(second.player_commands.size(), 1)


## One command instance per transaction, each with its own message — the rule live orders
## follow, and for the same reason: two units sharing a command trade destinations through it.
func test_each_phantom_gets_its_own_command_instance() -> void:
	var controller: RTSController = _controller()
	var first: PurchaseTransaction = _transaction()
	var second: PurchaseTransaction = _transaction()
	controller.select_pending([first, second], false)
	controller.assign_command_to_pending(
		MoveCommand, CommandMessage.new(null, null, null, VU.from_xz(Vector2(7, 7))), false
	)
	assert_ne(first.player_commands[0], second.player_commands[0])
	assert_ne(first.player_commands[0].message, second.player_commands[0].message)


func test_a_null_command_type_falls_back_to_a_plain_move() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	controller.assign_command_to_pending(
		null, CommandMessage.new(null, null, null, VU.from_xz(Vector2(2, 2))), false
	)
	assert_eq(transaction.player_commands.size(), 1)
	assert_true(transaction.player_commands[0] is MoveCommand)


## A phantom that stopped being orderable between the click and the assignment is dropped
## rather than silently swallowing the order.
func test_an_unorderable_phantom_is_dropped_from_the_selection() -> void:
	var controller: RTSController = _controller()
	var transaction: PurchaseTransaction = _transaction()
	controller.select_pending([transaction], false)
	transaction.state = PurchaseTransaction.State.COMPLETED
	assert_false(
		controller.assign_command_to_pending(
			MoveCommand, CommandMessage.new(null, null, null, Vector3.ZERO), false
		)
	)
	assert_false(controller.is_pending_selected(transaction))
#endregion
