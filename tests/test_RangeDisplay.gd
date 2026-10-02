extends GutTest

## WHAT REACHES PAST A PIECE, and when the HUD draws it.
##
## Three separable things, kept apart on purpose:
##   * EntityRanges — which shape a range kind resolves to, and the rule that a piece
##     without one reports NOTHING rather than a zero. Pure; no HUD.
##   * The BANDS the controller composes — hover plus armed ability — which is the decision
##     the world painter merely renders.
##   * The armed-ability caster choice, which is the one part of the aiming preview that has
##     a rule rather than a lookup.
##
## Nothing here asserts pixels. The mesh says nothing readable, so what is pinned is the
## band list; whether it LOOKS right is a render pass (see CLAUDE.md §Seeing the HUD).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_RangeDisplay.gd -gexit

## Fake pieces (tests/_fake_pieces.gd) holding only the reach a test is about.
## A gun that reaches the air alone, and sees.
const TURRET: Dictionary = {"vision": 10.0, "weapon": {"air": 8.0}}
## An UNARMED piece: no Loadout at all, which is the state the "not applicable is not drawn"
## rule is about.
const WORKER: Dictionary = {"vision": 6.0}
## A gun that hits both layers, with a separate ground and air shape.
const BOTH_LAYERS: Dictionary = {"vision": 6.0, "weapon": {"ground": 12.0, "air": 18.0}}
## A ground-only gun with one plain AttackRange.
const GROUND_ONLY: Dictionary = {"vision": 6.0, "weapon": {"ground": 9.0}}


func _piece(a_options: Dictionary) -> Commandable:
	var piece: Commandable = FakePieces.unit(a_options)
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	return piece


# --- Which shape a kind resolves to -------------------------------------------------


func test_a_turret_reports_its_weapon_and_vision_reach() -> void:
	var turret := _piece(TURRET)
	assert_gt(
		EntityRanges.radius_of(turret, EntityRanges.Kind.ATTACK_AIR),
		0.0,
		"a SAM has a reach against aircraft"
	)
	assert_eq(
		EntityRanges.radius_of(turret, EntityRanges.Kind.ATTACK),
		-1.0,
		"and none against the ground, so no ground ring"
	)
	assert_gt(EntityRanges.radius_of(turret, EntityRanges.Kind.VISION), 0.0)


# --- Ground and air reach --------------------------------------------------------------


func _attack_bands(a_piece: Entity) -> Array[RangeIndicator.Band]:
	return RangeIndicator.bands_for_entity(
		a_piece, [EntityRanges.Kind.ATTACK, EntityRanges.Kind.ATTACK_AIR]
	)


func test_a_ground_only_gun_draws_no_air_ring() -> void:
	var piece := _piece(GROUND_ONLY)
	assert_gt(EntityRanges.radius_of(piece, EntityRanges.Kind.ATTACK), 0.0)
	assert_eq(EntityRanges.radius_of(piece, EntityRanges.Kind.ATTACK_AIR), -1.0)
	assert_eq(_attack_bands(piece).size(), 1)


func test_different_ground_and_air_reach_draw_two_rings_in_two_colours() -> void:
	var piece := _piece(BOTH_LAYERS)
	var ground: CollisionShape3D = piece.find_child("AttackRangeGround", true, false)
	var air: CollisionShape3D = piece.find_child("AttackRangeAir", true, false)
	ground.shape = ground.shape.duplicate()
	air.shape = air.shape.duplicate()
	(ground.shape as CylinderShape3D).radius = 12.0
	(air.shape as CylinderShape3D).radius = 18.0
	var bands := _attack_bands(piece)
	assert_eq(bands.size(), 2)
	assert_ne(bands[0].color, bands[1].color, "air reach has its own colour")
	for band: RangeIndicator.Band in bands:
		assert_false(band.is_alternating)


func test_equal_ground_and_air_reach_draw_one_alternating_ring() -> void:
	var piece := _piece(BOTH_LAYERS)
	var ground: CollisionShape3D = piece.find_child("AttackRangeGround", true, false)
	var air: CollisionShape3D = piece.find_child("AttackRangeAir", true, false)
	ground.shape = ground.shape.duplicate()
	air.shape = air.shape.duplicate()
	(ground.shape as CylinderShape3D).radius = 14.0
	(air.shape as CylinderShape3D).radius = 14.0
	var bands := _attack_bands(piece)
	assert_eq(bands.size(), 1, "one ring, not two drawn on top of each other")
	assert_true(bands[0].is_alternating)
	assert_eq(bands[0].color, EntityRanges.color_of(EntityRanges.Kind.ATTACK))
	assert_eq(bands[0].alternate_color, EntityRanges.color_of(EntityRanges.Kind.ATTACK_AIR))


func test_the_two_alternating_dash_patterns_cover_the_line_between_them() -> void:
	var line: Array[Vector2] = [Vector2.ZERO, Vector2(10.0, 0.0)]
	var total: float = 0.0
	for pieces: Array in [
		RangeIndicator.dash(line, 1.0, 1.0), RangeIndicator.dash(line, 1.0, 1.0, 1.0)
	]:
		for piece: Array in pieces:
			total += (piece[0] as Vector2).distance_to(piece[1])
	assert_almost_eq(total, 10.0, 0.01)


func test_a_piece_without_a_range_reports_nothing_rather_than_zero() -> void:
	# The distinction the whole "not applicable is not drawn" rule turns on: a worker has no
	# gun, which is different from a gun that reaches nowhere.
	var worker := _piece(WORKER)
	assert_null(EntityRanges.shape_for(worker, EntityRanges.Kind.ATTACK))
	assert_eq(EntityRanges.radius_of(worker, EntityRanges.Kind.ATTACK), -1.0)


func test_shapes_for_drops_the_kinds_a_piece_lacks() -> void:
	# A piece with sight but no gun: the vision ring is offered and every gun ring is dropped, so
	# the result is not empty merely because the piece has nothing at all.
	var worker := _piece(WORKER)
	var kinds: Array = []
	for pair: Array in EntityRanges.shapes_for(
		worker, EntityRanges.WEAPON_KINDS + EntityRanges.VISION_KINDS
	):
		kinds.append(pair[0])
	assert_does_not_have(
		kinds, EntityRanges.Kind.ATTACK, "an unarmed piece contributes no attack ring"
	)
	assert_does_not_have(kinds, EntityRanges.Kind.ATTACK_AIR)
	assert_has(kinds, EntityRanges.Kind.VISION, "while the reach it does have is still offered")


func test_an_effect_with_no_reach_draws_no_ring() -> void:
	# Every effect shipped today acts on its host alone, so this is the state the reveal is
	# normally in — and it must draw nothing rather than a ring of radius zero.
	var worker := _piece(WORKER)
	var effect := SlowStatusEffect.new()
	worker.add_child(effect)
	assert_null(EntityRanges.shape_for(worker, EntityRanges.Kind.EFFECT))


func test_an_effect_that_reaches_draws_a_ring_at_its_host() -> void:
	var worker := _piece(WORKER)
	worker.global_position = Vector3(7.0, 0.0, -3.0)
	var effect := SlowStatusEffect.new()
	effect.effect_radius = 4.5
	worker.add_child(effect)
	effect.apply_to(worker)
	var shape: HighlightShape = EntityRanges.shape_for(worker, EntityRanges.Kind.EFFECT)
	assert_not_null(shape)
	assert_almost_eq(shape.radius, 4.5, 0.001)
	assert_almost_eq(shape.center, Vector2(7.0, -3.0), Vector2(0.001, 0.001))


# --- The bands the controller composes -----------------------------------------------


func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


func test_nothing_hovered_and_nothing_armed_draws_nothing() -> void:
	assert_eq(_controller().range_bands().size(), 0)


func test_hovering_a_widget_draws_one_band_per_kind_the_piece_has() -> void:
	var controller: RTSController = _controller()
	var turret := _piece(TURRET)
	controller._on_ranges_hovered(turret, EntityRanges.WEAPON_KINDS)
	var bands: Array[RangeIndicator.Band] = controller.range_bands()
	assert_eq(bands.size(), EntityRanges.shapes_for(turret, EntityRanges.WEAPON_KINDS).size())
	for band: RangeIndicator.Band in bands:
		assert_false(band.filled, "a REACH is an outline; only an area of effect is washed in")


func test_leaving_the_widget_puts_the_bands_away() -> void:
	var controller: RTSController = _controller()
	controller._on_ranges_hovered(_piece(TURRET), EntityRanges.WEAPON_KINDS)
	controller._on_ranges_unhovered()
	assert_eq(controller.range_bands().size(), 0)


func test_a_freed_hover_target_draws_nothing_rather_than_crashing() -> void:
	# The hovered piece can die under the pointer; the bands are recomposed every frame and
	# must survive the frame that happens on.
	var controller: RTSController = _controller()
	var turret: Commandable = FakePieces.unit(TURRET)
	add_child(turret)
	controller._on_ranges_hovered(turret, EntityRanges.WEAPON_KINDS)
	turret.free()
	assert_eq(controller.range_bands().size(), 0)


# --- The armed ability ---------------------------------------------------------------


func test_nothing_armed_names_no_ability() -> void:
	assert_eq(_controller().armed_ability_id(), &"")


func test_an_armed_launch_names_its_ability() -> void:
	# `command_launch` carries its id on the MESSAGE rather than in the hotkey table, so it
	# is the one route that would be missed by a table lookup alone.
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_launch"
	assert_eq(controller.armed_ability_id(), RTSController.LAUNCH_ABILITY)


func test_a_sanction_reach_is_global_and_draws_no_ring() -> void:
	# UseSanction measures no distance at all, so a ring around the caster would assert a
	# limit that does not exist.
	var controller: RTSController = _controller()
	controller._pending_sanction = autofree(Sanction.new()) as Sanction
	assert_false(controller._armed_reach_is_a_distance())


func test_a_bombards_reach_is_not_a_distance_either() -> void:
	# Its reach is SPOTTED GROUND. No ring describes that, and drawing one would tell the
	# player the wrong thing about why a shot is refused.
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_bombard"
	assert_false(controller._armed_reach_is_a_distance())


func test_an_ordinary_ability_reach_is_a_distance() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_launch"
	assert_true(controller._armed_reach_is_a_distance())


# --- Pending rings -------------------------------------------------------------------


## A pending piece's ring is dashed: on for the dash, off for the gap, measured along the line.
func test_a_dash_alternates_along_the_line() -> void:
	var line: Array[Vector2] = [Vector2.ZERO, Vector2(5.0, 0.0)]
	var pieces: Array = RangeIndicator.dash(line, 1.0, 1.0)
	assert_eq(pieces.size(), 3, "on at 0–1, 2–3 and 4–5")
	assert_almost_eq((pieces[1][0] as Vector2).x, 2.0, 0.001)
	assert_almost_eq((pieces[1][1] as Vector2).x, 3.0, 0.001)


## The phase carries across vertices, so a circle tessellated into short edges dashes evenly.
func test_a_dash_carries_its_phase_across_short_edges() -> void:
	var line: Array[Vector2] = [
		Vector2.ZERO, Vector2(0.5, 0.0), Vector2(1.0, 0.0), Vector2(1.5, 0.0), Vector2(2.0, 0.0)
	]
	var drawn: float = 0.0
	for piece: Array in RangeIndicator.dash(line, 1.0, 1.0):
		drawn += (piece[0] as Vector2).distance_to(piece[1])
	assert_almost_eq(drawn, 1.0, 0.001, "one dash's worth over two metres, not one per edge")
