extends GutTest

## Tests for RTSCamera3D's edge panning: the cursor resting near a screen edge slides the
## view that way.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CameraEdgePan.gd -gexit
##
## These drive edge_pan_direction() directly, which is pure geometry — no cursor, no window,
## no clock. The live guards it sits behind (window focus, an in-progress drag, the cursor
## outside the window, the cursor over HUD) need a real viewport and are exercised by hand.

## A 1600x900 viewport, so the numbers below read as plain screen coordinates.
const RECT: Vector2 = Vector2(1600.0, 900.0)

var _camera: RTSCamera3D


func before_each() -> void:
	_camera = RTSCamera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child_autofree(_camera)


## Where the camera's own screen-right / screen-up axes point in world space, so the
## assertions below don't hard-code the 45° yaw.
func _screen_right() -> Vector3:
	return _camera._ground_right()


func _screen_up() -> Vector3:
	return _camera._ground_forward()


## How much of `axis` a direction carries.
func _along(a_direction: Vector3, a_axis: Vector3) -> float:
	return a_direction.dot(a_axis)


# --- Not near an edge ----------------------------------------------------------


func test_the_middle_of_the_screen_asks_for_nothing() -> void:
	assert_eq(_camera.edge_pan_direction(RECT * 0.5, RECT), Vector3.ZERO)


func test_just_inside_the_margin_asks_for_nothing() -> void:
	var just_inside: float = RTSCamera3D.EDGE_PAN_MARGIN_PX + 1.0
	assert_eq(
		_camera.edge_pan_direction(Vector2(just_inside, RECT.y * 0.5), RECT),
		Vector3.ZERO,
		"a pixel beyond the band is still the playfield"
	)


func test_a_degenerate_viewport_asks_for_nothing() -> void:
	# A zero-sized viewport happens for a frame during startup/resize; every pixel would
	# otherwise count as "on an edge".
	assert_eq(_camera.edge_pan_direction(Vector2.ZERO, Vector2.ZERO), Vector3.ZERO)


# --- The four edges -------------------------------------------------------------


func test_the_right_edge_pans_right() -> void:
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, RECT.y * 0.5), RECT)
	assert_almost_eq(_along(direction, _screen_right()), 1.0, 0.001, "fully screen-right")


func test_the_left_edge_pans_left() -> void:
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(1.0, RECT.y * 0.5), RECT)
	assert_almost_eq(_along(direction, _screen_right()), -1.0, 0.001, "fully screen-left")


func test_the_top_edge_pans_up_the_screen() -> void:
	# Screen Y grows downward; a cursor at the TOP must move the view UP the screen, not down.
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x * 0.5, 1.0), RECT)
	assert_almost_eq(_along(direction, _screen_up()), 1.0, 0.001, "fully screen-up")


func test_the_bottom_edge_pans_down_the_screen() -> void:
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x * 0.5, RECT.y - 1.0), RECT)
	assert_almost_eq(_along(direction, _screen_up()), -1.0, 0.001, "fully screen-down")


func test_a_corner_pans_evenly_diagonally() -> void:
	# Both bands at once. Equal parts of each axis — the corner is a true 45°, not a heading
	# skewed by how far the cursor happens to sit from the middle of the screen.
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, 1.0), RECT)
	assert_almost_eq(_along(direction, _screen_right()), sqrt(0.5), 0.001, "rightward")
	assert_almost_eq(_along(direction, _screen_up()), sqrt(0.5), 0.001, "and equally upward")


func test_a_vertical_edge_pans_purely_horizontally() -> void:
	# The band decides the heading, not the cursor's position relative to the centre. Anywhere
	# along the left edge pans due left — high, low, or halfway up it — except in the corners,
	# where the horizontal band overlaps a vertical one.
	for y: float in [RECT.y * 0.25, RECT.y * 0.5, RECT.y * 0.75]:
		var direction: Vector3 = _camera.edge_pan_direction(Vector2(1.0, y), RECT)
		assert_almost_eq(
			_along(direction, _screen_up()), 0.0, 0.001, "y=%s pans purely horizontally" % y
		)
		assert_almost_eq(_along(direction, _screen_right()), -1.0, 0.001, "and fully left")


func test_a_horizontal_edge_pans_purely_vertically() -> void:
	for x: float in [RECT.x * 0.25, RECT.x * 0.5, RECT.x * 0.75]:
		var direction: Vector3 = _camera.edge_pan_direction(Vector2(x, 1.0), RECT)
		assert_almost_eq(
			_along(direction, _screen_right()), 0.0, 0.001, "x=%s pans purely vertically" % x
		)
		assert_almost_eq(_along(direction, _screen_up()), 1.0, 0.001, "and fully up")


# --- Shape of the result --------------------------------------------------------


func test_the_direction_is_always_unit_length() -> void:
	# Speed belongs to edge_pan_speed. An un-normalized centre-to-cursor vector would make a
	# corner pan far faster than an edge midpoint, and every speed resolution-dependent.
	for cursor: Vector2 in [
		Vector2(1.0, RECT.y * 0.5),  # left edge
		Vector2(1.0, 1.0),  # corner
		Vector2(RECT.x - 1.0, RECT.y - 1.0),  # opposite corner
		Vector2(RECT.x * 0.5, 1.0),  # top edge
		Vector2(RECT.x * 0.9, RECT.y - 1.0),  # bottom edge, off-centre
	]:
		assert_almost_eq(
			_camera.edge_pan_direction(cursor, RECT).length(),
			1.0,
			0.001,
			"unit length at %s" % cursor
		)


func test_the_direction_stays_on_the_ground_plane() -> void:
	# Panning must not fly the camera up or bury it; only its XZ position should change.
	for cursor: Vector2 in [Vector2(1.0, 1.0), Vector2(RECT.x - 1.0, RECT.y * 0.5)]:
		assert_almost_eq(
			_camera.edge_pan_direction(cursor, RECT).y, 0.0, 0.001, "no vertical component"
		)


func test_opposite_edges_give_opposite_directions() -> void:
	var left: Vector3 = _camera.edge_pan_direction(Vector2(1.0, RECT.y * 0.5), RECT)
	var right: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, RECT.y * 0.5), RECT)
	assert_almost_eq(left.dot(right), -1.0, 0.001)


func test_the_direction_follows_the_cameras_yaw() -> void:
	# Panning is screen-relative, so rotating the camera must rotate what "right" means.
	var before: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, RECT.y * 0.5), RECT)
	_camera.rotation.y += PI * 0.5
	var after: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, RECT.y * 0.5), RECT)
	assert_lt(before.dot(after), 0.5, "a quarter turn changes where the view slides")
	assert_almost_eq(after.length(), 1.0, 0.001, "and it is still a unit heading")


# --- Guards ---------------------------------------------------------------------


func test_an_in_progress_drag_suppresses_edge_panning() -> void:
	# Both steer from the same mouse, and a drag routinely ends near an edge.
	_camera.global_position = Vector3.ZERO
	_camera.dragging_camera = true
	_camera._apply_edge_pan(0.1)
	assert_eq(_camera.global_position, Vector3.ZERO, "the drag keeps sole control")


func test_disabling_edge_pan_stops_it() -> void:
	_camera.global_position = Vector3.ZERO
	_camera.edge_pan_enabled = false
	_camera._apply_edge_pan(0.1)
	assert_eq(_camera.global_position, Vector3.ZERO)


# --- How far it moves -----------------------------------------------------------


func test_the_pan_step_scales_with_zoom_and_frame_time() -> void:
	# Scaled by `size` for the same reason drag panning is: zoomed out, a screen-edge nudge
	# covers proportionally more ground, or panning feels glacial at low zoom. Scaled by delta
	# so the pan rate doesn't depend on frame rate.
	_camera.edge_pan_speed = 0.6
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(RECT.x - 1.0, RECT.y * 0.5), RECT)

	_camera.size = 15.0
	var near_step: Vector3 = _camera.edge_pan_step(direction, 0.1)
	assert_almost_eq(near_step.length(), 0.6 * 15.0 * 0.1, 0.0001)

	_camera.size = 30.0
	var far_step: Vector3 = _camera.edge_pan_step(direction, 0.1)
	assert_almost_eq(far_step.length(), near_step.length() * 2.0, 0.0001, "twice as zoomed out")

	var double_frame: Vector3 = _camera.edge_pan_step(direction, 0.2)
	assert_almost_eq(double_frame.length(), far_step.length() * 2.0, 0.0001, "twice the frame")


func test_the_pan_step_keeps_the_direction() -> void:
	_camera.size = 15.0
	var direction: Vector3 = _camera.edge_pan_direction(Vector2(1.0, RECT.y * 0.5), RECT)
	var step: Vector3 = _camera.edge_pan_step(direction, 0.1)
	assert_almost_eq(step.normalized().dot(direction), 1.0, 0.001, "same heading, scaled")
	assert_almost_eq(step.y, 0.0, 0.001, "and still flat")
