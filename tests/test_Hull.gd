extends GutTest

## EVERY PIECE-TO-PIECE RANGE IS THE GAP BETWEEN TWO FOOTPRINTS, SO IT READS THE SAME FROM
## BOTH ENDS.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Hull.gd -gexit
##
## The geometry is pinned on bare Hull values; the symmetry is pinned on two live pieces with
## the same reach and very different bodies — a round soldier and a rotated box — which must
## reach each other, and aggro onto each other, at exactly the same separations. Why:
## gdd/systems/combat/range-buckets.md §Ranges are measured between hulls.
##
## PATHS, not preloads (see CLAUDE.md). The scene is a HARNESS: the box body is set here.

const SOLDIER: Dictionary = FakePieces.SOLDIER
const EPSILON: float = 0.0001


#region Geometry
func test_two_circles_are_apart_by_their_centres_less_both_radii() -> void:
	assert_almost_eq(Hull.gap(Hull.circle(Vector2.ZERO, 1.0), Hull.circle(Vector2(5, 0), 1.5)),
		2.5, EPSILON)


func test_touching_or_overlapping_footprints_have_no_gap() -> void:
	assert_eq(Hull.gap(Hull.circle(Vector2.ZERO, 1.0), Hull.circle(Vector2(1.5, 0), 1.0)), 0.0)
	var box := Hull.rect(Vector2.ZERO, Vector2(2, 2), Vector2.RIGHT, Vector2.DOWN)
	assert_eq(Hull.gap(box, Hull.point(Vector2(1, 1))), 0.0, "a point inside")


func test_a_box_is_measured_to_its_nearest_edge_not_its_centre() -> void:
	var box := Hull.rect(Vector2.ZERO, Vector2(2, 1), Vector2.RIGHT, Vector2.DOWN)
	assert_almost_eq(box.distance_to_point(Vector2(5, 0)), 3.0, EPSILON, "off the long face")
	assert_almost_eq(box.distance_to_point(Vector2(0, 4)), 3.0, EPSILON, "off the short face")
	assert_almost_eq(box.distance_to_point(Vector2(5, 5)), Vector2(3, 4).length(), EPSILON,
		"off a corner")


func test_a_rotated_box_is_measured_in_its_own_frame() -> void:
	var diagonal := Vector2(1, 1).normalized()
	var box := Hull.rect(Vector2.ZERO, Vector2(1, 1), diagonal, diagonal.orthogonal())
	assert_almost_eq(box.distance_to_point(Vector2(3, 0)), 3.0 - sqrt(2.0), EPSILON,
		"a corner now points along +X")


func test_two_boxes_that_cross_without_a_corner_inside_still_overlap() -> void:
	var wide := Hull.rect(Vector2.ZERO, Vector2(3, 0.5), Vector2.RIGHT, Vector2.DOWN)
	var tall := Hull.rect(Vector2.ZERO, Vector2(0.5, 3), Vector2.RIGHT, Vector2.DOWN)
	assert_eq(Hull.gap(wide, tall), 0.0)


func test_two_separate_boxes_are_apart_by_their_nearest_corner_and_edge() -> void:
	var diagonal := Vector2(1, 1).normalized()
	var square := Hull.rect(Vector2.ZERO, Vector2(1, 1), Vector2.RIGHT, Vector2.DOWN)
	var diamond := Hull.rect(Vector2(5, 0), Vector2(1, 1), diagonal, diagonal.orthogonal())
	assert_almost_eq(Hull.gap(square, diamond), 4.0 - sqrt(2.0), EPSILON)


func test_the_gap_reads_the_same_from_either_end() -> void:
	var diagonal := Vector2(2, 1).normalized()
	var hulls: Array[Hull] = [
		Hull.point(Vector2(7, -2)),
		Hull.circle(Vector2(-3, 4), 0.75),
		Hull.rect(Vector2(1, 1), Vector2(2, 1), Vector2.RIGHT, Vector2.DOWN),
		Hull.rect(Vector2(9, 6), Vector2(1.5, 0.5), diagonal, diagonal.orthogonal()),
	]
	for a: Hull in hulls:
		for b: Hull in hulls:
			assert_almost_eq(Hull.gap(a, b), Hull.gap(b, a), EPSILON)


func test_extent_is_the_farthest_reach_from_the_centre() -> void:
	assert_eq(Hull.circle(Vector2.ZERO, 2.0).extent(), 2.0)
	assert_almost_eq(Hull.rect(Vector2.ZERO, Vector2(3, 4), Vector2.RIGHT, Vector2.DOWN).extent(),
		5.0, EPSILON)
#endregion


#region Two live pieces
func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _soldier(a_commander: Commander, a_at: Vector3) -> Commandable:
	var piece := FakePieces.make(SOLDIER) as Commandable
	add_child_autofree(piece)
	piece.ownership.commander = a_commander
	piece.global_position = a_at
	return piece


## The same soldier, but with a 4x4 box for a body, turned 30 degrees: as unlike the round
## one as a body gets, with the same weapon and so the same reach and aggro.
func _boxed(a_piece: Commandable) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(4, 2, 4)
	(a_piece.target_body.get_node("TargetShape") as CollisionShape3D).shape = box
	a_piece.rotation.y = deg_to_rad(30.0)


func test_a_round_body_and_a_box_reach_each_other_at_the_same_separations() -> void:
	Fog._fogs_by_commander.clear()
	var round_piece: Commandable = _soldier(_commander(1), Vector3.ZERO)
	var box_piece: Commandable = _soldier(_commander(2), Vector3(30, 0, 0))
	_boxed(box_piece)
	# Held, so the two never fight: the sweep measures, it does not want a casualty.
	round_piece.is_holding_fire = true
	box_piece.is_holding_fire = true
	var round_gun: Weapon = round_piece.weapon_inventory.get_weapons()[0]
	var box_gun: Weapon = box_piece.weapon_inventory.get_weapons()[0]
	var reach: float = round_gun.ground_reach()
	assert_eq(box_gun.ground_reach(), reach, "guards the fixture: one weapon, one reach")
	var both_reached: int = 0
	var neither_reached: int = 0
	for step: int in 40:
		for angle_deg: float in [0.0, 25.0, 45.0, 70.0]:
			var direction := Vector3(cos(deg_to_rad(angle_deg)), 0, sin(deg_to_rad(angle_deg)))
			box_piece.global_position = direction * (reach * 0.25 + step * 0.25)
			await wait_physics_frames(1)
			var one_way: bool = SU.is_in_attack_range(round_gun, round_piece, box_piece)
			var other_way: bool = SU.is_in_attack_range(box_gun, box_piece, round_piece)
			assert_eq(one_way, other_way, "reach at %s, %s deg" % [
				box_piece.global_position, angle_deg])
			var sees_one: bool = round_piece.hostiles_in_aggro().has(box_piece)
			var sees_other: bool = box_piece.hostiles_in_aggro().has(round_piece)
			assert_eq(sees_one, sees_other, "aggro at %s, %s deg" % [
				box_piece.global_position, angle_deg])
			both_reached += int(one_way and other_way)
			neither_reached += int(not one_way and not other_way)
	assert_gt(both_reached, 0, "guards the fixture: the sweep starts in range")
	assert_gt(neither_reached, 0, "guards the fixture: and ends out of it")
#endregion
