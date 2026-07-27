extends GutTest

## The Scan sanction's observation drone — what it is now that it is a real piece.
##
## It used to have no Defense and no TargetBody, which made it UNKILLABLE, and a permanent
## Scan 3 eye was an unanswerable, cost-free reveal. It is an attackable token now, and the
## things that had to stay true while that changed are what this file pins.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ReconDrone.gd -gexit

const SCOUT: PackedScene = preload("res://scenes/entities/nt_aircraftLight_recon.tscn")


func _drone() -> Commandable:
	var scout: Commandable = SCOUT.instantiate()
	add_child_autofree(scout)
	return scout


# --- Attackable ------------------------------------------------------------------

func test_it_is_attackable() -> void:
	# Aggro and Attack both ask Entity.is_attackable: a target layer and a Defense.
	var drone := _drone()
	assert_true(drone.is_attackable())
	assert_not_null(drone.defense, "it has something to lose")


func test_the_authored_durability() -> void:
	var drone := _drone()
	assert_eq(drone.defense.hp_max, 50.0)
	assert_eq(drone.defense.armour_type, Defense.ArmourType.LIGHT)
	assert_eq(drone.defense.frame_type, Defense.FrameType.MECH)


func test_it_is_air_targetable() -> void:
	# HOVERING is not about travel — it is what puts the drone on the anti-air layer.
	var drone := _drone()
	assert_not_null(drone.movement)
	assert_eq(drone.movement.mode, Movement.Mode.HOVERING)


# --- Still not commandable, still not mobile --------------------------------------

func test_it_cannot_be_selected() -> void:
	# Godot cannot remove a node inherited from a base scene, so the Selectable is still
	# there — switched off by a flag instead.
	var drone := _drone()
	assert_not_null(drone.selectable, "the inherited component is unavoidable")
	assert_false(drone.selectable.selectable_by_player)
	assert_false(drone.selectable.select(), "and refuses to be selected")


func test_it_is_still_pickable_so_it_can_be_ATTACKED() -> void:
	# The bug this pins: "unselectable" was first done by clearing the Selectable's
	# collision_layer, but that layer is what the CURSOR picks against
	# (RTSController.get_cursor_target) — so the drone became impossible to right-click
	# and could not be attacked at all. It has to stay on the layer.
	var drone := _drone()
	assert_ne(drone.selectable.collision_layer, 0,
		"the cursor must still be able to find it")


func test_refusing_selection_does_not_depend_on_the_collision_layer() -> void:
	# Box-select reads the "selectables" GROUP rather than the layer, so clearing the
	# layer never actually prevented selection either — a drag still caught it. Both paths
	# go through select(), which is where the refusal lives.
	var drone := _drone()
	assert_true(drone.selectable.is_in_group("selectables"),
		"a box drag does find it...")
	assert_false(drone.selectable.select(), "...and is refused here")


func test_it_cannot_move() -> void:
	var drone := _drone()
	assert_eq(drone.movement.speed, 0.0, "it holds where the sanction put it")


func test_it_has_no_weapon_and_no_aggro() -> void:
	var drone := _drone()
	assert_null(drone.get_node_or_null("Loadout"), "it watches and nothing else")


# --- Lifespan ---------------------------------------------------------------------

func test_the_scene_itself_is_permanent() -> void:
	# Scan 3's standing eye: how long a drone lasts is the placing event's Lifespan, so the
	# bare scene carries none and never expires.
	assert_null(_drone().get_node_or_null("Lifespan"))
