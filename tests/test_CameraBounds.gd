extends GutTest

## Tests for RTSCamera3D's zoom ceiling and pan limits.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CameraBounds.gd -gexit
##
## The limit rule is exercised through clamped_focus(), which takes bounds and a view size as
## arguments — gathering those live needs a Map and a viewport, deciding does not.

## Roughly what the authored zoom shows on the ground, along the play area's axes.
const HALF_VIEW: Vector2 = Vector2(12.0, 12.0)

## A square play area, and a deliberately RECTANGULAR one — play_size's two axes are
## independent, so the limits must respect each separately.
var _square: PlayArea
var _oblong: PlayArea

var _camera: RTSCamera3D


func before_each() -> void:
	_square = PlayArea.axis_aligned(Vector2.ZERO, Vector2(100.0, 100.0))
	_oblong = PlayArea.axis_aligned(Vector2.ZERO, Vector2(140.0, 60.0))
	_camera = RTSCamera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 15.0
	# _init() binds the zoom callables from `projection`, and it has already run by the time
	# new() returns — so a camera built in code gets the PERSPECTIVE pair unless it rebinds.
	# Scenario._setup_spectator_camera does exactly this for the same reason. A camera coming
	# from a .tscn is fine: the scene applies `projection` before attaching the script.
	_camera.zoom_in = _camera.zoom_in_orthogonal
	_camera.zoom_out = _camera.zoom_out_orthogonal
	add_child_autofree(_camera)


## How far the camera may look from the middle, along each of the play area's axes.
func _limit(a_area: PlayArea = _square, a_half_view: Vector2 = HALF_VIEW) -> Vector2:
	var far_off: Vector2 = a_area.to_world(Vector2(9999.0, 9999.0))
	return a_area.to_local(_camera.clamped_focus(far_off, a_area, a_half_view))


## How far past the edge of the play area the view reaches at that limit.
func _overscroll(a_half_view: Vector2 = HALF_VIEW) -> Vector2:
	return (_limit(_square, a_half_view) + a_half_view) - _square.half


# --- Zoom ceiling ---------------------------------------------------------------


func test_zoom_out_stops_at_twice_the_authored_framing() -> void:
	assert_eq(_camera._max_size, 30.0, "the ceiling is measured from the scene's own size")
	for i: int in 40:
		_camera.zoom_out.call(0.016, _camera.zoom_speed)
	_camera._clamp_zoom()
	assert_eq(_camera.size, 30.0, "however hard you push, it stops there")


func test_zoom_in_stops_at_half_the_authored_framing() -> void:
	assert_eq(_camera._min_size, 7.5, "the floor is measured from the scene's own size too")
	for i: int in 40:
		_camera.zoom_in.call(0.016, _camera.zoom_speed)
	_camera._clamp_zoom()
	assert_eq(_camera.size, 7.5)


func test_a_zoom_within_range_is_untouched() -> void:
	_camera.zoom_in.call(0.016, _camera.zoom_speed)
	var zoomed: float = _camera.size
	_camera._clamp_zoom()
	assert_eq(_camera.size, zoomed, "only the ends of the range are enforced")


func test_the_ceiling_is_per_camera_not_a_fixed_world_size() -> void:
	# A camera authored at a different framing keeps its own baseline.
	var wide := RTSCamera3D.new()
	wide.projection = Camera3D.PROJECTION_ORTHOGONAL
	wide.size = 40.0
	add_child_autofree(wide)
	assert_eq(wide._max_size, 80.0)
	assert_eq(wide._min_size, 20.0)


# --- Pan limits -----------------------------------------------------------------


func test_a_focus_well_inside_the_play_area_is_left_alone() -> void:
	var focus := Vector2(10.0, -20.0)
	assert_eq(_camera.clamped_focus(focus, _square, HALF_VIEW), focus)


func test_a_focus_outside_the_play_area_is_pulled_back() -> void:
	var limit: Vector2 = _limit()
	assert_lt(limit.x, _square.half.x, "the view can't wander off into nothing")
	assert_lt(limit.y, _square.half.y)


func test_the_limit_is_symmetric() -> void:
	var high: Vector2 = _limit()
	var low: Vector2 = _square.to_local(
		_camera.clamped_focus(Vector2(-9999.0, -9999.0), _square, HALF_VIEW)
	)
	assert_almost_eq(high.x, -low.x, 0.001)
	assert_almost_eq(high.y, -low.y, 0.001)


func test_a_rectangular_play_area_is_bounded_per_axis() -> void:
	# play_size's two axes are independent, so a long thin map must allow long thin panning
	# rather than collapsing to whichever extent is smaller.
	var limit: Vector2 = _limit(_oblong)
	assert_almost_eq(
		limit.x, _oblong.half.x - HALF_VIEW.x * (1.0 - RTSCamera3D.EDGE_OVERSCROLL_RATIO), 0.001
	)
	assert_almost_eq(
		limit.y, _oblong.half.y - HALF_VIEW.y * (1.0 - RTSCamera3D.EDGE_OVERSCROLL_RATIO), 0.001
	)
	assert_gt(limit.x, limit.y, "the long axis really does allow more travel")


func test_a_rotated_play_area_is_bounded_in_its_own_frame() -> void:
	# The authored play area is a rectangle in screen-aligned (s, t) — 45° from the world. A
	# world-axis clamp would admit the dead corners outside it.
	var rotated := PlayArea.screen_aligned(Vector2.ZERO, Vector2(100.0, 100.0), 1.0)
	var clamped: Vector2 = _camera.clamped_focus(
		rotated.to_world(Vector2(9999.0, 0.0)), rotated, HALF_VIEW
	)
	var local: Vector2 = rotated.to_local(clamped)
	assert_lt(local.x, rotated.half.x, "held inside along the rectangle's own axis")
	assert_almost_eq(local.y, 0.0, 0.001, "and not nudged off it")


func test_the_view_may_reach_past_the_edge_of_the_play_area() -> void:
	# The reason the margin exists: the HUD covers the bottom of the screen, so a view stopped
	# exactly at the edge would leave that strip of terrain permanently behind it.
	assert_gt(_overscroll().x, 0.0, "the view is allowed past the edge")
	assert_almost_eq(
		_overscroll().x,
		HALF_VIEW.x * RTSCamera3D.EDGE_OVERSCROLL_RATIO,
		0.001,
		"by exactly the overscroll margin"
	)


func test_the_overscroll_grows_with_zoom() -> void:
	# The margin is a fraction of what's on screen, so pulled back you may sit further out —
	# a fixed world margin would feel generous up close and negligible zoomed out.
	assert_almost_eq(_overscroll(HALF_VIEW * 2.0).x, _overscroll(HALF_VIEW).x * 2.0, 0.001)


func test_zooming_out_tightens_where_the_camera_may_sit() -> void:
	# More ground on screen means the centre of that ground must stay nearer the middle.
	assert_lt(_limit(_square, HALF_VIEW * 2.0).x, _limit().x, "further out, less roaming")


func test_a_view_larger_than_the_play_area_settles_in_the_middle() -> void:
	# Zoomed out past the whole map there is nowhere meaningful to pan.
	var huge := Vector2(500.0, 500.0)
	var clamped: Vector2 = _camera.clamped_focus(Vector2(9999.0, -9999.0), _square, huge)
	assert_eq(clamped, _square.center)


func test_one_axis_can_be_covered_while_the_other_still_pans() -> void:
	# A long thin map zoomed out: nothing to pan across the short axis, plenty along the long.
	var half_view := Vector2(20.0, 200.0)
	var limit: Vector2 = _limit(_oblong, half_view)
	assert_gt(limit.x, 0.0, "the long axis still pans")
	assert_almost_eq(limit.y, 0.0, 0.001, "the covered axis is centred")


func test_an_off_centre_map_is_bounded_about_its_own_centre() -> void:
	var offset := PlayArea.axis_aligned(Vector2(160.0, 160.0), Vector2(100.0, 100.0))
	var clamped: Vector2 = _camera.clamped_focus(Vector2(-9999.0, -9999.0), offset, HALF_VIEW)
	assert_almost_eq(
		offset.to_local(clamped).x,
		-_limit().x,
		0.001,
		"the limit is measured from the map's middle, not the world origin"
	)


# --- Geometry the limits are built on --------------------------------------------


func test_ground_focus_inverts_center_on() -> void:
	# The limits bound where the camera LOOKS, not where it is: at a 45° pitch the body sits
	# well behind and above the view, so bounding the position would leave the view adrift.
	_camera.global_position = RTSCamera3D.initial_position()
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	for target: Vector2 in [Vector2.ZERO, Vector2(25.0, -40.0), Vector2(-7.5, 12.25)]:
		_camera.center_on(target)
		assert_almost_eq(_camera.ground_focus().x, target.x, 0.001)
		assert_almost_eq(_camera.ground_focus().y, target.y, 0.001)


func test_the_visible_ground_area_grows_with_zoom() -> void:
	_camera.global_position = RTSCamera3D.initial_position()
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.size = 15.0
	var close_in: Vector2 = _camera.visible_half_extents_in(_square)
	_camera.size = 30.0
	var pulled_back: Vector2 = _camera.visible_half_extents_in(_square)
	assert_gt(close_in.x, 0.0, "a real area is measured")
	assert_almost_eq(pulled_back.x, close_in.x * 2.0, 0.5, "doubling the zoom doubles the view")


# --- Escape hatch ----------------------------------------------------------------


func test_bounding_can_be_turned_off() -> void:
	_camera.clamp_to_map_bounds = false
	_camera.global_position = Vector3(9999.0, 20.0, 9999.0)
	_camera._clamp_to_map_bounds()
	assert_eq(_camera.global_position.x, 9999.0, "an unbounded camera roams freely")


# --- Altitude headroom on the screen-up side ------------------------------------


## A play area in the SCREEN-ALIGNED frame the game actually uses (TerrainData authors play
## bounds as s = x+z / t = x-z). The _square fixture above is axis-aligned, which is fine for
## the symmetric limits but would report the look direction in the wrong frame.
func _screen_area() -> PlayArea:
	return PlayArea.screen_aligned(Vector2.ZERO, Vector2(100.0, 100.0), 1.0)


## The direction the camera looks, in `area`'s frame — where fliers are drawn toward.
func _look_in(a_area: PlayArea) -> Vector2:
	return a_area.to_local_direction(VU.in_xz(_camera._ground_forward()))


func test_the_default_camera_looks_along_the_negative_s_axis() -> void:
	# The whole feature hangs on this: in the screen-aligned frame the play bounds are
	# authored in, "up the screen" is the -s direction and carries no t component.
	var look: Vector2 = _look_in(_screen_area())
	assert_almost_eq(look.x, -1.0, 0.01, "screen-up is the -s direction")
	assert_almost_eq(look.y, 0.0, 0.01, "and carries no t component")


func test_headroom_is_the_flier_displacement_at_this_camera_angle() -> void:
	# At 45 degrees of elevation a unit at height h is drawn h of ground distance further up
	# the screen, so the headroom is the cruise altitude times the slack.
	assert_almost_eq(
		RTSCamera3D.altitude_headroom(),
		Aerial.AERIAL_HEIGHT * RTSCamera3D.ALTITUDE_HEADROOM_SLACK,
		0.01
	)


func test_the_view_may_push_further_up_than_down() -> void:
	var area: PlayArea = _screen_area()
	var look: Vector2 = _look_in(area)
	var up_limit: float = (
		area
		. to_local(
			_camera.clamped_focus(area.to_world(Vector2(-9999.0, 0.0)), area, HALF_VIEW, look)
		)
		. x
	)
	var down_limit: float = (
		area
		. to_local(
			_camera.clamped_focus(area.to_world(Vector2(9999.0, 0.0)), area, HALF_VIEW, look)
		)
		. x
	)

	assert_lt(up_limit, -down_limit, "the screen-up side reaches further out")
	assert_almost_eq(
		absf(up_limit) - down_limit,
		RTSCamera3D.altitude_headroom(),
		0.01,
		"and by exactly the headroom"
	)


func test_the_far_side_is_unchanged_by_the_headroom() -> void:
	# Only the top gains room; the bottom keeps the HUD-driven margin it already had.
	var area: PlayArea = _screen_area()
	var far_down: Vector2 = area.to_world(Vector2(9999.0, 0.0))
	var without: Vector2 = _camera.clamped_focus(far_down, area, HALF_VIEW)
	var with_headroom: Vector2 = _camera.clamped_focus(far_down, area, HALF_VIEW, _look_in(area))
	assert_almost_eq(area.to_local(with_headroom).x, area.to_local(without).x, 0.01)


func test_the_cross_axis_is_unchanged_at_the_default_camera() -> void:
	# The look direction has no t component, so the left/right limits must not move.
	var area: PlayArea = _screen_area()
	var far_t: Vector2 = area.to_world(Vector2(0.0, 9999.0))
	var without: Vector2 = _camera.clamped_focus(far_t, area, HALF_VIEW)
	var with_headroom: Vector2 = _camera.clamped_focus(far_t, area, HALF_VIEW, _look_in(area))
	assert_almost_eq(area.to_local(with_headroom).y, area.to_local(without).y, 0.01)


## How lopsided an axis's limits are: the two ends sum to the signed headroom on that axis,
## and to zero when it has none. Sign-agnostic, so it doesn't care WHICH way a yaw turned.
func _asymmetry(a_area: PlayArea, a_look: Vector2, a_axis: int) -> float:
	var far: Vector2 = Vector2(9999.0, 0.0) if a_axis == 0 else Vector2(0.0, 9999.0)
	var plus: Vector2 = a_area.to_local(
		_camera.clamped_focus(a_area.to_world(far), a_area, HALF_VIEW, a_look)
	)
	var minus: Vector2 = a_area.to_local(
		_camera.clamped_focus(a_area.to_world(-far), a_area, HALF_VIEW, a_look)
	)
	return absf((plus + minus)[a_axis])


func test_the_headroom_follows_a_yawed_camera() -> void:
	# Rotating the view must carry the extra room with it rather than leave it pointing north.
	var area: PlayArea = _screen_area()
	var headroom: float = RTSCamera3D.altitude_headroom()

	assert_almost_eq(
		_asymmetry(area, _look_in(area), 0), headroom, 0.01, "unyawed: all the headroom is on s"
	)
	assert_almost_eq(_asymmetry(area, _look_in(area), 1), 0.0, 0.01, "unyawed: none of it is on t")

	_camera.rotation.y += deg_to_rad(90.0)
	var look: Vector2 = _look_in(area)
	assert_almost_eq(absf(look.y), 1.0, 0.05, "the look direction now runs along t")
	assert_almost_eq(_asymmetry(area, look, 1), headroom, 0.01, "yawed: the headroom moved to t")
	assert_almost_eq(_asymmetry(area, look, 0), 0.0, 0.01, "yawed: and left s symmetric")


func test_no_look_direction_leaves_the_old_symmetric_behaviour() -> void:
	var far_off: Vector2 = _square.to_world(Vector2(9999.0, 9999.0))
	var limit: Vector2 = _square.to_local(_camera.clamped_focus(far_off, _square, HALF_VIEW))
	var mirrored: Vector2 = _square.to_local(_camera.clamped_focus(-far_off, _square, HALF_VIEW))
	assert_almost_eq(limit.x, -mirrored.x, 0.01, "symmetric without a look direction")
