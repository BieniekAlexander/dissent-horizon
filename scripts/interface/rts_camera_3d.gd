## A camera angled at 45 degrees from above
class_name RTSCamera3D extends Camera3D

#region Constants
## The camera's downward pitch — rotation about the global X axis, in degrees —
## baked into the player camera in player.tscn. Flat sprites are authored to look
## correct from this view, so it's the canonical record of the game's viewing
## angle. Drives initial_position() below.
const CAMERA_ANGLE_DEGREES: float = -135.0

## How far the camera sits from the origin along the CAMERA_ANGLE_DEGREES
## elevation. Only affects how zoomed-out the framing is, not the angle.
const INITIAL_DISTANCE: float = 30.0

## The camera's yaw — rotation about the global Y axis, in degrees. At 0° the
## camera looks straight down a world axis, so the axis-aligned terrain grid
## renders as screen-aligned squares. At 45° it looks down the grid's diagonal,
## so cells render as diamonds (the AoE2/StarCraft-style isometric look) while
## the grid itself stays axis-aligned with Godot. Flip the sign to face the
## opposite diagonal.
const CAMERA_YAW_DEGREES: float = 45.0
#endregion

#region Public API
## The camera's canonical starting position: INITIAL_DISTANCE from the origin
## along the elevation implied by CAMERA_ANGLE_DEGREES, so that looking at the
## origin reproduces the game's viewing angle. (At -135° this is the +Y/+Z
## "pulled back and raised" vantage the player camera uses.) The
## editor-camera-angle plugin sits the editor viewport camera here and looks at
## the origin while composing scenes (see addons/editor_camera_angle).
static func initial_position() -> Vector3:
	var pitch: float = deg_to_rad(CAMERA_ANGLE_DEGREES)
	var elevated: Vector3 = Vector3(0.0, -sin(pitch), -cos(pitch)) * INITIAL_DISTANCE
	return Basis(Vector3.UP, deg_to_rad(CAMERA_YAW_DEGREES)) * elevated
#endregion

#region Properties
@export_category("Movement")
@export var movement_speed: float = 1
@export var movement_friction: float = 1.5
@export var rotation_speed: float = 0.66
var dragging_camera: bool = false
var move_reference_position: Vector2

@export var rotate_left_action: String = "isometric_camera_rotate_left"
@export var rotate_right_action: String = "isometric_camera_rotate_right"
#endregion

#region Zoom
@export_category("Zoom")
@export var zoom_speed: float = 20.0
@export var zoom_in_action: String = "isometric_camera_zoom_in"
@export var zoom_out_action: String = "isometric_camera_zoom_out"
var zoom_velocity: Vector3 = Vector3.ZERO

func zoom_in_orthogonal(delta: float, zoom_speed: float) -> void:
	size /= (100+zoom_speed)/100

func zoom_out_orthogonal(delta: float, zoom_speed: float) -> void:
	size *= (100+zoom_speed)/100

func zoom_in_perspective(delta: float, zoom_speed: float) -> void:
	zoom_velocity = -global_transform.basis.z * zoom_speed * delta
	zoom_velocity = lerp(zoom_velocity, Vector3.ZERO, (zoom_speed / 2) * delta)
	position += zoom_velocity

func zoom_out_perspective(delta: float, zoom_speed: float) -> void:
	zoom_velocity = global_transform.basis.z * zoom_speed * delta
	zoom_velocity = lerp(zoom_velocity, Vector3.ZERO, (zoom_speed / 2) * delta)
	position += zoom_velocity

## Conditional control function reference
var zoom_in: Callable
var zoom_out: Callable
#endregion

#region Public API
## Move the camera (translation only, orientation preserved) so its forward ray
## meets the ground plane (Y = 0) at `world_xz`. For a camera at height y with
## forward f, the ground hit is P + (−y / f.y)·f, so placing that hit at world_xz
## means offsetting P.xz by (y / f.y)·f.xz. This holds for any yaw/pitch; at yaw 0,
## pitch −45° it reduces to the old (wx, y, wz + y).
func center_on(world_xz: Vector2) -> void:
	var f: Vector3 = -global_transform.basis.z
	if is_zero_approx(f.y):
		return
	var y: float = global_position.y
	var k: float = y / f.y
	global_position = Vector3(world_xz.x + k * f.x, y, world_xz.y + k * f.z)

func get_screen_position_normalized(screen_position_raw: Vector2) -> Vector2:
	return (screen_position_raw*2/get_viewport().get_visible_rect().size)-Vector2.ONE

## Raycast the cursor against the horizontal plane at `height`. Works for any
## camera orientation and projection (orthographic or perspective), so it no
## longer bakes in the old pitch-45°/no-yaw assumption.
func get_mouse_world_position(screen_position: Vector2, height: float = 0) -> Vector3:
	var ray_origin: Vector3 = project_ray_origin(screen_position)
	var ray_dir: Vector3 = project_ray_normal(screen_position)
	if is_zero_approx(ray_dir.y):
		return project_position(screen_position, 0.0)
	var t: float = (height - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t
#endregion

#region Lifecycle
func _init():
	if projection == PROJECTION_PERSPECTIVE:
		zoom_in = zoom_in_perspective
		zoom_out = zoom_out_perspective
	elif projection == PROJECTION_ORTHOGONAL:
		zoom_in = zoom_in_orthogonal
		zoom_out = zoom_out_orthogonal
	else:
		push_error("Cannot set zoom functionality, unsupported Camera3D projection setting: %s" % projection)

func _ready() -> void:
	# Establish the canonical viewing angle (pitch + yaw) from the constants so the
	# game's camera angle lives in exactly one place and matches the editor plugin.
	# Only the orientation is anchored here; Scenario start-framing and the minimap
	# re-center translation via center_on(), which preserves this orientation.
	global_position = initial_position()
	look_at(Vector3.ZERO, Vector3.UP)

## Unit XZ (ground-plane) right/forward vectors for the current yaw, so panning is
## relative to what's on screen rather than to world axes. At yaw 0 these are the
## world +X / -Z axes, reproducing the original world-axis panning exactly.
func _ground_right() -> Vector3:
	return Vector3(global_transform.basis.x.x, 0.0, global_transform.basis.x.z).normalized()

func _ground_forward() -> Vector3:
	return Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()

func _input(event: InputEvent):
	if event.is_action_pressed("isometric_camera_drag"):
		move_reference_position = get_screen_position_normalized(event.position)
		dragging_camera = true
	elif event.is_action_released("isometric_camera_drag"):
		dragging_camera = false
	elif event is InputEventMouseMotion:
		if dragging_camera:
			var new_mouse_pos: Vector2 = get_screen_position_normalized(event.position)
			var d: Vector2 = new_mouse_pos - move_reference_position
			global_position += (
				-_ground_right() * d.x + _ground_forward() * d.y
			) * size * movement_speed
			move_reference_position = new_mouse_pos

	if event.is_action_pressed("isometric_camera_left", true):
		global_position += -_ground_right()*.5
	if event.is_action_pressed("isometric_camera_right", true):
		global_position += _ground_right()*.5
	if event.is_action_pressed("isometric_camera_up", true):
		global_position += _ground_forward()*.5
	if event.is_action_pressed("isometric_camera_down", true):
		global_position += -_ground_forward()*.5

func _process(delta: float) -> void:
	if Input.is_action_pressed(rotate_left_action):
		rotation.y += rotation_speed * delta
	if Input.is_action_pressed(rotate_right_action):
		rotation.y -= rotation_speed * delta

	if Input.is_action_just_pressed(zoom_in_action):
		zoom_in.call(delta, zoom_speed)
	elif Input.is_action_just_pressed(zoom_out_action):
		zoom_out.call(delta, zoom_speed)
#endregion
