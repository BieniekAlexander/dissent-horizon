extends GutTest

## Aggro is DERIVED from reach, per target layer (RangeShapes), never authored. Pinned here:
## the rule itself, that the ground and air volumes follow their own layer's reach, the cap
## for a piece that cannot move, and a bunker taking its occupants' reach.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_AggroFromReach.gd -gdir=res://tests/none -gexit

## A unit scene used only as a HARNESS: every reach it is tested with is set here.
# a gun with no reach yet
const HARNESS_PATH: Dictionary = {"speed": 2.0, "vision": 8.0, "weapon": {}}
const GROUND: int = CollisionLayers.Mask.TARGETABLE_GROUND
const AIR: int = CollisionLayers.Mask.TARGETABLE_AIR


#region The rule
func test_reach_under_the_floor_aggros_at_the_floor() -> void:
	assert_eq(RangeShapes.aggro_radius_for_reach(0.5, true), RangeShapes.AGGRO_MIN_RADIUS)
	assert_eq(RangeShapes.aggro_radius_for_reach(2.5, true), RangeShapes.AGGRO_MIN_RADIUS)


func test_reach_in_the_band_aggros_one_past_it() -> void:
	assert_eq(RangeShapes.aggro_radius_for_reach(5.0, true), 6.0)
	assert_eq(RangeShapes.aggro_radius_for_reach(8.0, true), 9.0)


func test_reach_at_or_over_the_ceiling_aggros_at_the_ceiling() -> void:
	# 10 exactly caps too: 10 -> 11 would be a jump no neighbouring reach makes.
	assert_eq(RangeShapes.aggro_radius_for_reach(10.0, true), RangeShapes.AGGRO_MAX_RADIUS)
	assert_eq(RangeShapes.aggro_radius_for_reach(12.0, true), RangeShapes.AGGRO_MAX_RADIUS)


func test_a_piece_that_cannot_move_never_aggros_past_its_reach() -> void:
	assert_eq(RangeShapes.aggro_radius_for_reach(2.5, false), 2.5)
	assert_eq(RangeShapes.aggro_radius_for_reach(12.0, false), RangeShapes.AGGRO_MAX_RADIUS)


func test_no_reach_is_no_aggro() -> void:
	assert_eq(RangeShapes.aggro_radius_for_reach(-1.0, true), -1.0)
	assert_null(RangeShapes.aggro_shape_for_reach(-1.0, true))


func test_one_radius_is_one_shared_shape() -> void:
	var a: CylinderShape3D = RangeShapes.aggro_shape_for_reach(8.0, true)
	var b: CylinderShape3D = RangeShapes.aggro_shape_for_reach(8.0, true)
	assert_same(a, b, "a shared library shape, so nothing may mutate it in place")
	assert_eq(a.height, RangeShapes.SHAPE_HEIGHT)


#endregion


#region Derivation on a piece
func _cylinder_node(a_radius: float) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = a_radius
	node.shape = shape
	return node


## The harness with one weapon reaching `a_ground` on the ground and `a_air` in the air
## (a negative value: cannot hit that layer).
func _piece(a_ground: float, a_air: float) -> Actor:
	var piece: Actor = FakePieces.make(HARNESS_PATH) as Actor
	add_child_autofree(piece)
	var weapon: Weapon = piece.weapon_inventory.get_weapons()[0]
	weapon.target_mask = (GROUND if a_ground >= 0.0 else 0) | (AIR if a_air >= 0.0 else 0)
	if a_ground >= 0.0:
		weapon.attack_range_shape_ground = _cylinder_node(a_ground)
		weapon.add_child(weapon.attack_range_shape_ground)
	if a_air >= 0.0:
		weapon.attack_range_shape_air = _cylinder_node(a_air)
		weapon.add_child(weapon.attack_range_shape_air)
	piece.refresh_aggro_shapes()
	return piece


func test_each_layer_follows_its_own_reach() -> void:
	var piece: Actor = _piece(8.0, 3.0)
	assert_eq(RangeShapes.xz_radius(piece.aggro_shape_ground), 9.0)
	assert_eq(RangeShapes.xz_radius(piece.aggro_shape_air), RangeShapes.AGGRO_MIN_RADIUS)


func test_a_layer_it_cannot_hit_has_no_volume() -> void:
	var piece: Actor = _piece(5.0, -1.0)
	assert_null(piece.aggro_shape_air.shape, "a ground-only gun picks no fights with aircraft")
	assert_eq(piece.aggro_shapes(), [piece.aggro_shape_ground])


func test_the_wider_volume_is_the_piece_aggro_radius() -> void:
	assert_eq(_piece(2.5, 6.0).aggro_radius(), 7.0)


func test_losing_movement_caps_aggro_at_reach() -> void:
	var piece: Actor = _piece(2.5, -1.0)
	piece.movement = null
	piece.refresh_aggro_shapes()
	assert_eq(RangeShapes.xz_radius(piece.aggro_shape_ground), 2.5)


#endregion


#region A bunker aggros with its occupants' reach
func test_a_bunker_takes_its_occupants_reach_plus_its_bonus() -> void:
	var host: Actor = _piece(-1.0, -1.0)
	var garrison := Garrison.new()
	garrison.bunker = true
	host.add_child(garrison)
	var occupant: Actor = _piece(5.0, -1.0)
	garrison._garrisoned.append(occupant)

	# No hull term: reach is measured from the host's footprint, like every range.
	assert_almost_eq(garrison.occupant_reach_on_layer(GROUND), 5.0 + garrison.range_bonus, 0.001)
	assert_eq(garrison.occupant_reach_on_layer(AIR), -1.0)


func test_a_hold_that_does_not_fire_lends_nothing() -> void:
	var host: Actor = _piece(-1.0, -1.0)
	var garrison := Garrison.new()
	garrison.bunker = false
	host.add_child(garrison)
	garrison._garrisoned.append(_piece(5.0, -1.0))
	assert_eq(
		garrison.occupant_reach_on_layer(GROUND),
		-1.0,
		"a stock truck full of prisoners does not pick fights at their range"
	)
#endregion
