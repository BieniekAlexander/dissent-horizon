extends GutTest

## A piece's facing is Entity.yaw, held as script state and written through to its basis with
## DMath, because the engine re-derives `rotation.y` with the platform's atan2 whenever the
## transform is written — and the platforms round that differently.
## gdd/systems/authoring/native-code.md §Maths that rounds the same everywhere.

const SCALE: Vector3 = Vector3(1.5, 2.0, 0.5)


func _piece() -> Actor:
	var piece: Actor = FakePieces.unit()
	add_child_autofree(piece)
	return piece


func test_an_unturned_piece_faces_plus_z() -> void:
	assert_eq(_piece().yaw, 0.0)


func test_its_yaw_starts_as_the_yaw_of_the_basis_it_was_given() -> void:
	var piece: Actor = FakePieces.unit()
	piece.basis = Basis(Vector3.UP, 0.7)
	add_child_autofree(piece)
	assert_almost_eq(piece.yaw, 0.7, 1e-6)


func test_setting_it_turns_the_basis_with_dmath() -> void:
	var piece: Actor = _piece()
	piece.yaw = 1.1
	assert_eq(piece.basis, VU.yaw_basis(1.1))
	assert_almost_eq(piece.rotation.y, 1.1, 1e-6, "the model and shapes turn with it")


func test_setting_it_keeps_the_roots_scale() -> void:
	var piece: Actor = FakePieces.unit()
	piece.scale = SCALE
	add_child_autofree(piece)
	piece.yaw = 0.4
	assert_almost_eq(piece.basis.get_scale(), SCALE, Vector3.ONE * 1e-6)


## The case it exists for: a move writes the transform, and the yaw read back is still exactly
## the one set, not the engine's re-derivation of it.
func test_a_transform_write_leaves_it_exactly_as_set() -> void:
	var piece: Actor = _piece()
	var turned: float = 0.10471975511965977
	piece.yaw = turned
	piece.global_position = Vector3(3.0, 1.0, -2.0)
	piece.move_and_slide()
	assert_eq(piece.yaw, turned)


## The model's own turn (MeshVisual.attitude) is held the same way, so a turret under it is
## placed from DMath-built bases all the way down.
func test_a_models_attitude_starts_as_authored_and_keeps_its_scale() -> void:
	var model := MeshVisual.new()
	model.rotation = Vector3(0.0, 0.3, 0.0)
	model.scale = SCALE
	add_child_autofree(model)
	assert_almost_eq(model.attitude, Vector3(0.0, 0.3, 0.0), Vector3.ONE * 1e-6)
	model.attitude = Vector3(0.2, 0.3, -0.1)
	assert_eq(model.basis, VU.euler_basis(Vector3(0.2, 0.3, -0.1)) * Basis.from_scale(SCALE))
	assert_almost_eq(model.basis.get_scale(), SCALE, Vector3.ONE * 1e-5)
