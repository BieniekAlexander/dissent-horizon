extends GutTest

## Orders given to a GARRISON OCCUPANT, and when it acts on them.
##
## The rule mirrors a producer's rally exactly: a released occupant does its OWN orders if it
## has any, and the host's rally otherwise. An order does NOT imply evacuation — the unit is
## off the tree while garrisoned, so it processes nothing and simply carries the orders until
## something lets it out. A unit that never comes out never acts on them.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_OccupantOrders.gd -gexit


func _commanded(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## A live unit (a fake: tests/_fake_pieces.gd).
func _unit(a_commander: Commander) -> Actor:
	var unit: Actor = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(unit)
	unit.ownership.commander = a_commander
	return unit


func _order(a_xz: Vector2) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, VU.from_xz(a_xz)))


func _destinations(a_chain: Array) -> Array:
	var out: Array = []
	for command: MoveCommand in a_chain:
		out.append(VU.in_xz(command.message.position))
	return out


#region An order does not evacuate
## The occupant leaves the tree when it garrisons, so nothing drives its commands. Giving it
## one must not tip it out of the vehicle — the order waits.
func test_ordering_an_occupant_leaves_it_inside() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var garrison := Garrison.new()
	garrison.capacity = 4
	host.add_child(garrison)

	garrison.garrison(occupant)
	assert_eq(garrison.occupants().size(), 1, "it is inside")

	occupant.update_commands(_order(Vector2(9, 9)))
	assert_eq(garrison.occupants().size(), 1, "and giving it an order left it there")
	assert_false(
		occupant.is_inside_tree(),
		"a garrisoned unit is off the tree, which is why nothing acts on the order"
	)


#endregion


#region Held, not gone
## THE BUG THIS PINS: `RTSController._process` drops any selected node that is not
## `is_inside_tree()`, and a garrisoned unit is off the tree — so an occupant selected from
## its card was pruned on the very next frame. It looked like the card was not wired at all.
##
## A held unit is not a dead one, and `garrisoned_in` is what tells them apart. Nothing else
## could: off-the-tree is exactly what dying and boarding have in common.
func test_a_garrisoned_unit_knows_it_is_held() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var garrison := Garrison.new()
	garrison.name = "Garrison"
	garrison.capacity = 4
	host.add_child(garrison)

	assert_false(occupant.is_garrisoned(), "out in the world")
	garrison.garrison(occupant)
	assert_true(occupant.is_garrisoned(), "held — and off the tree, like a dead unit")
	assert_false(occupant.is_inside_tree(), "which is why is_inside_tree cannot tell them apart")


func test_releasing_clears_the_back_pointer() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var garrison := Garrison.new()
	garrison.name = "Garrison"
	garrison.capacity = 4
	host.add_child(garrison)
	garrison.garrison(occupant)

	garrison.evacuate(null)
	assert_false(occupant.is_garrisoned(), "out again, so the prune may drop it if it dies")


#endregion


#region Selecting an occupant
## THE BUG THIS PINS: `Selectable.select()` returns whether the state CHANGED, and every
## selection path treats false as "this cannot be selected". A unit that was SELECTED when it
## boarded kept that flag, so `select_only` asked it to select, got "no change", and silently
## refused — which is the usual case, since you select a squad and then order it aboard.
## Garrisoning now clears the flag on the way in, mirroring what release does on the way out.
func test_a_unit_selected_when_it_boards_can_still_be_selected_inside() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var garrison := Garrison.new()
	garrison.capacity = 4
	host.add_child(garrison)

	occupant.selectable.select()  # the player had it selected...
	garrison.garrison(occupant)  # ...and then ordered it aboard
	assert_false(
		occupant.selectable.is_selected(),
		"boarding clears the flag, or it can never be picked again"
	)

	var controller := autofree(RTSController.new()) as RTSController
	controller.select_only(occupant)
	assert_eq(controller.selection.size(), 1, "its card can select it")


func test_an_unselected_occupant_selects_too() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var garrison := Garrison.new()
	garrison.capacity = 4
	host.add_child(garrison)
	garrison.garrison(occupant)

	var controller := autofree(RTSController.new()) as RTSController
	controller.select_only(occupant)
	assert_eq(controller.selection.size(), 1)


#endregion


#region The release chain
## Its own orders win over the host's rally — the same precedence a trained unit gets between
## a player order and its producer's rally.
func test_its_own_orders_win_over_the_hosts_rally() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	host.update_commands(_order(Vector2(1, 1)))  # the host's rally
	occupant.update_commands(_order(Vector2(9, 9)))  # the occupant's own

	var chain: Array = Garrison._release_commands(occupant, host, null, Vector3(2, 0, 2))

	assert_eq(
		_destinations(chain),
		[Vector2(2, 2), Vector2(9, 9)],
		"the exit-point move first, then what the player told THIS unit"
	)


## And a unit nobody ordered still follows the host, which is what makes this additive rather
## than a replacement for the old behaviour.
func test_an_unordered_occupant_follows_the_host() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	host.update_commands(_order(Vector2(1, 1)))

	var chain: Array = Garrison._release_commands(occupant, host, null, Vector3(2, 0, 2))

	assert_eq(
		_destinations(chain),
		[Vector2(2, 2), Vector2(1, 1)],
		"the exit-point move, then the host's rally"
	)


func test_no_orders_anywhere_is_just_the_exit_move() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var chain: Array = Garrison._release_commands(occupant, host, null, Vector3(2, 0, 2))
	assert_eq(_destinations(chain), [Vector2(2, 2)], "it clears the host and stands there")


## The evacuee gets its OWN copies, so a group released together never shares instances —
## the rule that already held for the host's rally, extended to the occupant's own chain.
func test_the_released_chain_is_copies() -> void:
	var commander: Commander = _commanded(1)
	var host: Actor = _unit(commander)
	var occupant: Actor = _unit(commander)
	var mine: MoveCommand = _order(Vector2(9, 9))
	occupant.update_commands(mine)

	var chain: Array = Garrison._release_commands(occupant, host, null, Vector3(2, 0, 2))

	assert_ne(chain[1], mine, "a copy, not the instance the unit is holding")
	assert_eq(VU.in_xz(chain[1].message.position), Vector2(9, 9), "carrying the same order")
#endregion
