extends GutTest

## Taking orders is the `Orders` component, which a doc omits with `commandable: false`. An Actor
## without it is still a piece — damageable, targetable — and every order to it is a no-op.
## gdd/systems/authoring/composition-rework.md §Commandability is a capability.


func _piece(a_options: Dictionary = {}) -> Actor:
	var piece: Actor = FakePieces.unit({"speed": 2.0}.merged(a_options))
	add_child_autofree(piece)
	return piece


func _move() -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, Vector3(4.0, 0.0, 4.0)))


func test_an_actor_with_orders_takes_them() -> void:
	var piece: Actor = _piece()
	assert_not_null(piece.orders)
	piece.update_commands(_move())
	assert_true(piece.has_command())
	assert_eq(piece.get_command_chain().size(), 1)


func test_an_actor_without_orders_ignores_them() -> void:
	var piece: Actor = _piece({"commandable": false})
	assert_null(piece.orders)
	assert_null(piece.command_receiver)
	piece.update_commands(_move())
	assert_false(piece.has_command(), "an order to it does nothing")
	assert_eq(piece.get_command_chain().size(), 0)
	assert_eq(piece.rally_chain().size(), 0)
	assert_null(piece.rally_destination())


func test_an_actor_without_orders_can_still_be_hurt() -> void:
	var piece: Actor = _piece({"commandable": false})
	var attacker: Actor = _piece({"weapon": {"ground": 6.0}})
	var hp_before: float = piece.defense.hp
	piece.receive_damage(Damage.new(10.0, Damage.Type.LEAD), attacker)
	assert_lt(piece.defense.hp, hp_before, "damage lands, and nothing tries to retaliate")
