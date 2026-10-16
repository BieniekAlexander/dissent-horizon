extends GutTest

## ObstructionMeasure against synthetic blocks: how much of an infantry figure behind a
## structure the structure hides from the game camera.

const RADIUS: float = 0.2
const HEIGHT: float = 1.05
const ELEVATION: float = deg_to_rad(40.0)
const YAWS: int = 8
const FOOTPRINT: Vector2 = Vector2(2.0, 2.0)


func _block(height: float, half: Vector2 = FOOTPRINT * 0.5) -> PackedVector3Array:
	return MeshPrimitives.box(Vector3(-half.x, 0.0, -half.y), Vector3(half.x, height, half.y))


func _worst(triangles: PackedVector3Array) -> float:
	var worst: Dictionary = ObstructionMeasure.worst_case(
		triangles, FOOTPRINT, RADIUS, HEIGHT, ELEVATION, YAWS
	)
	return worst["fraction"]


func test_a_block_far_taller_than_a_figure_hides_one_entirely() -> void:
	assert_almost_eq(_worst(_block(4.0)), 1.0, 0.01)


func test_a_ground_slab_hides_almost_nothing() -> void:
	assert_lt(_worst(_block(0.05)), 0.1)


func test_a_taller_block_hides_more() -> void:
	assert_lt(_worst(_block(0.4)), _worst(_block(0.9)))


func test_a_thin_pole_hides_less_than_half_however_tall() -> void:
	var pole: PackedVector3Array = MeshPrimitives.beam(Vector3.ZERO, Vector3(0.0, 5.0, 0.0), 0.05)
	assert_lt(_worst(pole), 0.5)


func test_a_mass_set_back_from_the_edge_hides_less_than_the_same_mass_at_it() -> void:
	var at_edge: PackedVector3Array = _block(1.2)
	var set_back: PackedVector3Array = _block(1.2, Vector2(0.3, 0.3))
	assert_lt(_worst(set_back), _worst(at_edge))


func test_a_figure_on_the_cameras_side_is_never_hidden() -> void:
	var view: Basis = ObstructionMeasure.view_basis(0.0, ELEVATION)
	var projection: Dictionary = ObstructionMeasure.project(_block(4.0), view)
	# At yaw 0 the camera is out along +Z, so +Z is the near side.
	var in_front: Vector2 = Vector2(0.0, FOOTPRINT.y * 0.5 + RADIUS + 0.1)
	assert_eq(ObstructionMeasure.hidden_fraction(projection, view, in_front, RADIUS, HEIGHT), 0.0)


func test_a_figure_right_behind_a_tall_block_is_hidden() -> void:
	var view: Basis = ObstructionMeasure.view_basis(0.0, ELEVATION)
	var projection: Dictionary = ObstructionMeasure.project(_block(4.0), view)
	var behind: Vector2 = Vector2(0.0, -FOOTPRINT.y * 0.5 - RADIUS - 0.1)
	assert_almost_eq(
		ObstructionMeasure.hidden_fraction(projection, view, behind, RADIUS, HEIGHT), 1.0, 0.01
	)


func test_the_view_matches_the_game_camera() -> void:
	var camera: Vector3 = RTSCamera3D.initial_position().normalized()
	var elevation: float = asin(camera.y)
	var view: Basis = ObstructionMeasure.view_basis(
		deg_to_rad(RTSCamera3D.CAMERA_YAW_DEGREES), elevation
	)
	assert_almost_eq(view.z, -camera, Vector3.ONE * 0.0001)
	assert_almost_eq(view.x.y, 0.0, 0.0001, "screen right stays level")
	assert_gt(view.y.y, 0.0, "screen up points up")
