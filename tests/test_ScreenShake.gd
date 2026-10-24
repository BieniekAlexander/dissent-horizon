extends GutTest

## Screen shake: the envelope a ScreenShake describes, how RTSCamera3D plays several at once,
## the gate on what the player can see (the camera's view and the fog on screen), and the
## emission phase that raises one on entering. All against a camera and pieces built here —
## nothing about any shipped shake's numbers. Rules: gdd/systems/ux/screen-shake.md
##
## Run with:
##   godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScreenShake.gd -gexit

## The commander whose fog is on screen in these tests. Set outright rather than left to the
## defaults, which other files in the run change.
const VIEWER: int = 5

var _camera: RTSCamera3D
var _saved_view: int
var _saved_debug: Array


func before_each() -> void:
	Fog._fogs_by_commander.clear()
	Fog.set_view_lifted(false)
	_saved_view = Fog.active_commander_id
	Fog.active_commander_id = VIEWER
	_saved_debug = [DebugMode._is_allowed, DebugMode._is_shown]
	DebugMode.configure(false)
	_camera = RTSCamera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 15.0
	# The cursor sits wherever the headless window puts it; an edge pan would carry the view
	# away from the pieces under test.
	_camera.edge_pan_enabled = false
	_camera.clamp_to_map_bounds = false
	add_child_autofree(_camera)
	_camera.make_current()


func after_each() -> void:
	Fog._fogs_by_commander.clear()
	Fog.set_view_lifted(false)
	Fog.active_commander_id = _saved_view
	DebugMode._is_allowed = _saved_debug[0]
	DebugMode._is_shown = _saved_debug[1]


func _shake(a_magnitude: float, a_seconds: float, a_hz: float = 20.0) -> ScreenShake:
	var shake := ScreenShake.new()
	shake.magnitude = a_magnitude
	shake.duration_seconds = a_seconds
	shake.frequency_hz = a_hz
	return shake


## A plain node at `a_at`, in the tree.
func _marker(a_at: Vector3) -> Node3D:
	var marker := Node3D.new()
	add_child_autofree(marker)
	marker.global_position = a_at
	return marker


## A fog for the viewer that has revealed nothing: everything is under it.
func _blind_player() -> void:
	var fog := Fog.new()
	fog.watching_commander_id = VIEWER
	add_child_autofree(fog)


#region The envelope
func test_the_throw_starts_at_the_magnitude_and_fades_to_nothing() -> void:
	var shake: ScreenShake = _shake(0.04, 1.0)
	assert_almost_eq(shake.amplitude_at(0.0), 0.04, 0.0001)
	assert_almost_eq(shake.amplitude_at(0.5), 0.01, 0.0001, "quadratic: half way is a quarter")
	assert_eq(shake.amplitude_at(1.0), 0.0, "over at its duration")
	assert_eq(shake.amplitude_at(3.0), 0.0, "and stays over")


func test_a_shake_with_no_duration_is_none() -> void:
	assert_eq(_shake(0.04, 0.0).amplitude_at(0.0), 0.0)


#endregion


#region The camera
func test_a_shake_moves_the_lens_and_settles_back() -> void:
	_camera.shake(_shake(0.05, 0.3))
	assert_true(_camera.is_shaking())
	_camera._apply_shake(0.1)
	assert_ne(Vector2(_camera.h_offset, _camera.v_offset), Vector2.ZERO, "the picture moved")
	_camera._apply_shake(0.3)
	assert_false(_camera.is_shaking(), "finished")
	assert_eq(Vector2(_camera.h_offset, _camera.v_offset), Vector2.ZERO, "and back at rest")


func test_a_shake_never_moves_where_the_camera_looks() -> void:
	var focus: Vector2 = _camera.ground_focus()
	_camera.shake(_shake(0.1, 1.0))
	_camera._apply_shake(0.1)
	assert_eq(_camera.ground_focus(), focus, "the lens moves; the camera does not")


func test_the_throw_scales_with_the_view() -> void:
	_camera.shake(_shake(0.1, 1.0))
	_camera._apply_shake(0.2)
	var throw: float = Vector2(_camera.h_offset, _camera.v_offset).length()
	assert_lte(
		throw, _camera.shake_amplitude() * _camera.size + 0.0001, "a fraction of the view height"
	)
	assert_gt(throw, 0.0)


func test_a_shake_scale_of_zero_turns_shaking_off() -> void:
	_camera.shake_scale = 0.0
	_camera.shake(_shake(0.1, 1.0))
	_camera._apply_shake(0.1)
	assert_eq(Vector2(_camera.h_offset, _camera.v_offset), Vector2.ZERO)


func test_overlapping_shakes_show_the_strongest_not_the_sum() -> void:
	_camera.shake(_shake(0.02, 1.0))
	_camera.shake(_shake(0.05, 1.0))
	_camera.shake(_shake(0.03, 1.0))
	assert_almost_eq(_camera.shake_amplitude(), 0.05, 0.0001)


func test_a_weak_shake_outlives_a_strong_short_one() -> void:
	_camera.shake(_shake(0.1, 0.2))
	_camera.shake(_shake(0.01, 1.0))
	_camera._apply_shake(0.5)
	assert_true(_camera.is_shaking(), "the long one is still running")
	assert_almost_eq(_camera.shake_amplitude(), _shake(0.01, 1.0).amplitude_at(0.5), 0.0001)


#endregion


#region What the player can see
func test_a_source_in_view_and_in_sight_shakes() -> void:
	assert_true(ScreenShake.play(_shake(0.05, 1.0), _marker(Vector3.ZERO)))
	assert_true(_camera.is_shaking())


func test_a_source_off_screen_does_not_shake() -> void:
	assert_false(ScreenShake.play(_shake(0.05, 1.0), _marker(Vector3(500.0, 0.0, 500.0))))
	assert_false(_camera.is_shaking())


func test_a_source_under_the_fog_does_not_shake() -> void:
	_blind_player()
	assert_false(ScreenShake.play(_shake(0.05, 1.0), _marker(Vector3.ZERO)))
	assert_false(_camera.is_shaking())


func test_a_piece_under_the_fog_does_not_shake() -> void:
	_blind_player()
	var piece: Actor = FakePieces.unit()
	add_child_autofree(piece)
	assert_false(ScreenShake.is_in_sight(piece), "judged by the player's fog")


func test_lifted_fog_hides_nothing() -> void:
	_blind_player()
	Fog.set_view_lifted(true)
	assert_true(ScreenShake.play(_shake(0.05, 1.0), _marker(Vector3.ZERO)))


func test_no_shake_or_no_camera_is_no_shake() -> void:
	assert_false(ScreenShake.play(null, _marker(Vector3.ZERO)))
	_camera.clear_current(false)
	var plain := Camera3D.new()
	add_child_autofree(plain)
	plain.make_current()
	assert_false(
		ScreenShake.play(_shake(0.05, 1.0), _marker(Vector3.ZERO)), "not the player's camera"
	)


#endregion


#region An emission phase
func test_an_emission_shakes_as_it_enters_a_phase_that_names_a_shake() -> void:
	var shell: Entity = FakePieces.emission()
	(shell.get_node("Impact") as EmissionPhase).screen_shake = _shake(0.05, 5.0)
	add_child_autofree(shell)
	shell.global_position = Vector3(0.0, 4.0, 0.0)
	var locomotion := shell.get_node("Locomotion") as PhasedLocomotion
	Emitter.launch(shell, null, Vector3(1.0, 0.0, 1.0))
	assert_false(_camera.is_shaking(), "the flight names no shake")
	var ticks: int = 0
	while is_instance_valid(shell) and locomotion.phase_index() < 1 and ticks < 300:
		await get_tree().physics_frame
		ticks += 1
	assert_eq(locomotion.phase_index(), 1, "guards the fixture: the shell struck")
	assert_true(_camera.is_shaking(), "the burst shook the screen")
#endregion
