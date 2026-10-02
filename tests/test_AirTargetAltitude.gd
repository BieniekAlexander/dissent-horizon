extends GutTest

## ALTITUDE, not locomotion mode, decides whether a piece is an AIR target or a GROUND one
## — see gdd/systems/combat/target-acquisition.md.
##
## The rule these pin down is that ONE predicate (Entity.is_air_target) drives both halves of
## "can this weapon reach it": the TARGETABLE_AIR / TARGETABLE_GROUND bit on the TargetBody,
## and the air-vs-ground reach Weapon.get_range_for_target picks. Every case below is one the
## old Movement.mode test got wrong.

## Loaded INSIDE the tests, never preloaded at file scope: a file-scope preload of an entity
## scene runs at parse time and fires Tool's static registry initialiser before the registry
## exists, which makes Tool.for_name return null for every test after it (see CLAUDE.md).
const CLIPPER: Dictionary = FakePieces.AIRCRAFT
const RECRUIT: Dictionary = FakePieces.SOLDIER
const AIRFIELD: Dictionary = FakePieces.BUILDING


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


## A live entity owned by `a_commander`. Ownership is assigned directly rather than through
## initialize() so no Map is needed — the shortcut test_DockingBay and test_Garrison take.
func _entity(a_options: Dictionary, a_commander: Commander) -> Commandable:
	var e := FakePieces.make(a_options) as Commandable
	add_child_autofree(e)
	e.ownership.commander = a_commander
	return e


func _is_air_layer(a_entity: Entity) -> bool:
	return (a_entity.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) != 0


func _is_ground_layer(a_entity: Entity) -> bool:
	return (a_entity.targetable_layers() & CollisionLayers.Mask.TARGETABLE_GROUND) != 0


#region The threshold
func test_the_threshold_is_derived_from_cruise_altitude() -> void:
	# Derived, not typed: raising cruise altitude must not leave every aircraft below the
	# line. Pinned because the whole point of deriving it is that it cannot drift.
	assert_eq(
		Aerial.AIR_TARGET_ALTITUDE,
		Aerial.AERIAL_HEIGHT / 2.0,
		"the air-target line is half of cruise altitude, derived from it"
	)
	assert_gt(Aerial.AIR_TARGET_ALTITUDE, 0.0, "and is a real height off the ground")


#endregion


#region A ground unit
func test_a_ground_unit_is_a_ground_target() -> void:
	var infantry: Commandable = _entity(RECRUIT, _commander(1))
	assert_false(infantry.is_air_target(), "it stands on the ground")
	assert_true(_is_ground_layer(infantry), "and is filed on the ground layer")
	assert_false(_is_air_layer(infantry), "and only that layer")


#endregion


#region An aircraft
func test_an_aircraft_at_cruise_is_an_air_target() -> void:
	var plane: Commandable = _entity(CLIPPER, _commander(1))
	assert_true(plane.is_air_target(), "it spawns at cruise altitude")
	assert_true(_is_air_layer(plane), "so it is filed on the air layer")
	assert_false(_is_ground_layer(plane), "and only that layer")


func test_a_parked_aircraft_is_a_ground_target() -> void:
	# The case that motivated the change: a jet on its pad used to keep TARGETABLE_AIR, so
	# no ground-only weapon could lock it at all — a hangar was immune to the infantry
	# standing next to it.
	var plane: Commandable = _entity(CLIPPER, _commander(1))
	plane.aerial.land_permanently()
	assert_ne(
		_tick_until(plane.aerial, func() -> bool: return plane.aerial.height_offset() <= 0.01),
		-1,
		"it reaches the ground"
	)
	assert_false(plane.is_air_target(), "so it is not an air target")
	plane.refresh_targetable_altitude()
	assert_true(_is_ground_layer(plane), "it is filed on the ground layer")
	assert_false(_is_air_layer(plane), "and off the air one")


func test_an_aircraft_on_final_approach_is_still_an_air_target() -> void:
	# is_airborne() goes false the INSTANT a descent begins, while the aircraft is still at
	# cruise altitude — which is why it cannot be the targeting test. A jet on final is a
	# hundred feet up and squarely an anti-air problem; only altitude says so.
	var plane: Commandable = _entity(CLIPPER, _commander(1))
	plane.aerial.land_permanently()
	plane.aerial._physics_process(1.0 / Engine.physics_ticks_per_second)
	assert_false(plane.aerial.is_airborne(), "no longer AIRBORNE — the descent has begun")
	assert_gt(
		plane.aerial.height_offset(),
		Aerial.AIR_TARGET_ALTITUDE,
		"but still well above the line (the fixture this needs)"
	)
	assert_true(plane.is_air_target(), "so it is still an air target")


#endregion


#region A parachuting unit
func test_a_unit_under_a_canopy_is_an_air_target() -> void:
	# A GROUNDED unit CAN be in the air. Its mode never changes, which is exactly why
	# the mode cannot answer this question.
	var infantry: Commandable = _entity(RECRUIT, _commander(1))
	infantry.movement.begin_parachute_descent(Aerial.AERIAL_HEIGHT, Callable())
	assert_eq(
		infantry.movement.mode, Movement.Mode.GROUNDED, "the mode is untouched by the descent"
	)
	assert_true(infantry.is_air_target(), "but it is high enough to be an air target")


func test_a_parachutist_becomes_a_ground_target_before_it_lands() -> void:
	# It crosses the line halfway down rather than on touchdown, which is the accepted
	# consequence of one shared threshold.
	var infantry: Commandable = _entity(RECRUIT, _commander(1))
	infantry.movement.begin_parachute_descent(Aerial.AIR_TARGET_ALTITUDE * 0.5, Callable())
	assert_true(infantry.movement.is_parachuting(), "still falling (the fixture this needs)")
	assert_false(infantry.is_air_target(), "but already below the line")


#endregion


#region The layer follows altitude without being re-applied by hand
func test_the_layer_is_refiled_when_the_threshold_is_crossed() -> void:
	var infantry: Commandable = _entity(RECRUIT, _commander(1))
	assert_true(_is_ground_layer(infantry), "on the ground to start with")
	infantry.movement.begin_parachute_descent(Aerial.AERIAL_HEIGHT, Callable())
	infantry.refresh_targetable_altitude()
	assert_true(_is_air_layer(infantry), "lifting it re-files it onto the air layer")
	assert_false(_is_ground_layer(infantry), "and off the ground one")


func test_refiling_is_a_no_op_while_the_answer_holds() -> void:
	# The per-tick call must be free when nothing has changed — it runs on every commandable
	# every tick, so a write per frame is the thing to avoid.
	var plane: Commandable = _entity(CLIPPER, _commander(1))
	var before: int = plane.target_body.collision_layer
	plane.refresh_targetable_altitude()
	plane.refresh_targetable_altitude()
	assert_eq(plane.target_body.collision_layer, before, "unchanged while it stays at cruise")


#endregion


#region Structures are not asked
func test_a_structure_is_a_ground_target_regardless() -> void:
	# A structure takes the Structure branch and never consults altitude — it is a ground
	# target by being a structure, and it also blocks line of fire.
	var field: Commandable = _entity(AIRFIELD, _commander(1))
	field.build_progress = 1.0
	assert_false(field.is_air_target(), "no Movement, so no altitude to have")
	assert_true(_is_ground_layer(field))
	assert_true((field.targetable_layers() & CollisionLayers.Mask.TARGETABLE_AIR) == 0)


func test_refiling_leaves_a_structure_alone() -> void:
	var field: Commandable = _entity(AIRFIELD, _commander(1))
	field.build_progress = 1.0
	var before: int = field.target_body.collision_layer
	field.refresh_targetable_altitude()
	assert_eq(field.target_body.collision_layer, before, "a structure is never re-filed")


#endregion


#region Weapon reach reads the same predicate
func test_a_weapon_picks_its_reach_from_the_same_predicate() -> void:
	# The second half of the rule: "what can shoot it" and "at what range" must be one
	# answer. A parachuting soldier used to sit on the air layer and be shot at ground range.
	var cmd: Commander = _commander(1)
	var shooter: Commandable = _entity(CLIPPER, cmd)
	var weapon: Weapon = shooter.weapon_inventory.get_child(0) as Weapon
	if weapon == null:
		pending("the fixture aircraft carries no Weapon to ask")
		return
	var infantry: Commandable = _entity(RECRUIT, cmd)
	var grounded: CollisionShape3D = weapon.get_range_for_target(infantry)
	infantry.movement.begin_parachute_descent(Aerial.AERIAL_HEIGHT, Callable())
	assert_true(infantry.is_air_target(), "now an air target (the fixture this needs)")
	assert_ne(
		weapon.get_range_for_target(infantry),
		grounded,
		"the same unit is reached with the AIR shape once it is in the air"
	)


#endregion


## Step `a_node` until `a_predicate` holds, up to a generous cap. Returns the ticks taken, or
## -1 if it never did — mirroring test_AerialDocking's helper of the same shape.
func _tick_until(a_node: Node, a_predicate: Callable, a_max: int = 600) -> int:
	for i in a_max:
		if a_predicate.call():
			return i
		a_node._physics_process(1.0 / Engine.physics_ticks_per_second)
	return -1
