extends GutTest

## Tests for the pre-issued command queue a producing/garrisoning structure holds for the
## units it turns out (Actor.rally_commands and friends).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_RallyQueue.gd -gexit
##
## The structures here are out-of-tree Commandables with a Production component wired
## directly to the `production` field (the @onready never resolves outside the tree) and
## an explicit CommandReceiver, which is all `update_commands` touches on a stationary
## host. `movement` stays null, which is what makes a Actor "stationary" and so
## eligible to absorb move orders as rally rather than walking them.


func _make_structure() -> Actor:
	var structure := autofree(Actor.new()) as Actor
	var production := Production.new()
	production.producible_types = [&"fake_trainee_a"]
	structure.add_child(production)
	structure.production = production
	structure.command_receiver = CommandReceiver.new()
	structure.command_receiver.initialize(structure)
	return structure


func _move_to(a_x: float, a_z: float) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, Vector3(a_x, 0.0, a_z)))


func _destinations(a_commands: Array) -> Array:
	var out: Array = []
	for command: MoveCommand in a_commands:
		out.append(command.message.position)
	return out


## --- absorbing move orders ----------------------------------------------------


func test_a_move_order_becomes_the_rally_queue() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	assert_eq(_destinations(structure.rally_commands), [Vector3(5, 0, 5)])
	assert_null(
		structure.current_command(),
		"the structure takes no command of its own — it can't walk anywhere"
	)


func test_a_second_move_order_replaces_the_queue() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	structure.update_commands(_move_to(9, 1))
	assert_eq(
		_destinations(structure.rally_commands),
		[Vector3(9, 0, 1)],
		"a plain right-click overwrites the whole queue"
	)


func test_an_additive_move_order_appends() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	structure.update_commands(_move_to(9, 1), true)
	structure.update_commands(_move_to(2, 7), true)
	assert_eq(
		_destinations(structure.rally_commands),
		[Vector3(5, 0, 5), Vector3(9, 0, 1), Vector3(2, 0, 7)],
		"shift right-clicks stack up in order"
	)


func test_a_plain_order_after_additive_ones_clears_them() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	structure.update_commands(_move_to(9, 1), true)
	structure.update_commands(_move_to(0, 0))
	assert_eq(_destinations(structure.rally_commands), [Vector3(0, 0, 0)])


func test_an_array_of_moves_is_absorbed_whole() -> void:
	var structure := _make_structure()
	structure.update_commands([_move_to(1, 1), _move_to(2, 2)] as Array[MoveCommand])
	assert_eq(_destinations(structure.rally_commands), [Vector3(1, 0, 1), Vector3(2, 0, 2)])


## Only bare moves are rally material: a real order aimed at the structure itself (an
## Attack from its own turret, say) has to reach the command receiver.
func test_a_non_move_command_is_not_absorbed() -> void:
	var structure := _make_structure()
	var attack := Attack.new(CommandMessage.new(null, null, null, Vector3(3, 0, 3)))
	structure.update_commands(attack)
	assert_true(structure.rally_commands.is_empty(), "not a rally order")
	assert_eq(structure.current_command(), attack, "it stays a command for the structure")


## --- handing the queue to a unit ----------------------------------------------


func test_rally_chain_hands_out_copies_not_the_templates() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	structure.update_commands(_move_to(9, 1), true)

	var first: Array[MoveCommand] = structure.rally_chain()
	var second: Array[MoveCommand] = structure.rally_chain()
	assert_eq(_destinations(first), [Vector3(5, 0, 5), Vector3(9, 0, 1)], "same orders")
	assert_eq(_destinations(second), _destinations(first))
	for i in first.size():
		assert_false(
			is_same(first[i], second[i]),
			"two units off one rally must not share a command instance"
		)
		assert_false(
			is_same(first[i].message, second[i].message),
			"nor a message — each unit owns its own destination"
		)
		assert_false(
			is_same(first[i], structure.rally_commands[i]),
			"and neither of them is the structure's template"
		)


func test_rally_chain_drops_the_order_identity_token() -> void:
	var structure := _make_structure()
	var order := _move_to(5, 5)
	order.message.origin = CommandMessage.new(null)
	structure.update_commands(order)
	var chain: Array[MoveCommand] = structure.rally_chain()
	assert_null(
		chain[0].message.origin,
		"a unit that merely inherited a rally isn't a sibling of the order that set it"
	)


func test_rally_destination_is_the_first_leg() -> void:
	var structure := _make_structure()
	structure.update_commands(_move_to(5, 5))
	structure.update_commands(_move_to(9, 1), true)
	assert_eq(
		structure.rally_destination().message.position,
		Vector3(5, 0, 5),
		"the spawn-side bias follows the first leg of the chain"
	)


func test_no_rally_yields_an_empty_chain() -> void:
	var structure := _make_structure()
	assert_true(structure.rally_chain().is_empty())
	assert_null(structure.rally_destination())
