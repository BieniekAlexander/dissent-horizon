extends GutTest

## A piece that watches and cannot be ordered: still a target, never a selection.
##
## The properties, on a fake piece (tests/_fake_pieces.gd): attackable, on the anti-air layer by
## hovering, refuses selection by the player — and, the bug this pins, still findable by the
## cursor so it can be ATTACKED. What any shipped scout is authored to be is content and is
## not asserted here.


func _watcher() -> Commandable:
	var piece: Commandable = FakePieces.unit({"aerial": true, "vision": 8.0, "selectable": false})
	add_child_autofree(piece)
	return piece


# --- Attackable ------------------------------------------------------------------


func test_it_is_attackable() -> void:
	# Aggro and Attack both ask Entity.is_attackable: a target layer and a Defense.
	var drone := _watcher()
	assert_true(drone.is_attackable())
	assert_not_null(drone.defense, "it has something to lose")


func test_it_is_air_targetable() -> void:
	# HOVERING is not about travel — it is what puts a piece on the anti-air layer.
	var drone := _watcher()
	assert_not_null(drone.movement)
	assert_eq(drone.movement.mode, Movement.Mode.HOVERING)


# --- Not selectable, but still pickable ------------------------------------------


func test_it_cannot_be_selected() -> void:
	var drone := _watcher()
	assert_not_null(drone.selectable, "the component is there, switched off by a flag")
	assert_false(drone.selectable.selectable_by_player)
	assert_false(drone.selectable.select(), "and refuses to be selected")


func test_it_is_still_pickable_so_it_can_be_ATTACKED() -> void:
	# The bug this pins: "unselectable" was first done by clearing the Selectable's
	# collision_layer, but that layer is what the CURSOR picks against
	# (RTSController.get_cursor_target) — so the piece became impossible to right-click
	# and could not be attacked at all. It has to stay on the layer.
	var drone := _watcher()
	assert_ne(drone.selectable.collision_layer, 0, "the cursor must still be able to find it")


func test_refusing_selection_does_not_depend_on_the_collision_layer() -> void:
	# Box-select reads the "selectables" GROUP rather than the layer, so clearing the
	# layer never actually prevented selection either — a drag still caught it. Both paths
	# go through select(), which is where the refusal lives.
	var drone := _watcher()
	assert_true(drone.selectable.is_in_group("selectables"), "a box drag does find it...")
	assert_false(drone.selectable.select(), "...and is refused here")
