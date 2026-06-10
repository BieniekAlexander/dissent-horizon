## A camera angled at 45 degrees from above
class_name RTSCamera3D extends Camera3D

### MOVEMENT
@export_category("Movement")
@export var movement_speed: float = 1
@export var movement_friction: float = 1.5
@export var rotation_speed: float = 0.66
var dragging_camera: bool = false
var move_reference_position: Vector2

@export var rotate_left_action: String = "isometric_camera_rotate_left"
@export var rotate_right_action: String = "isometric_camera_rotate_right"

## Move the camera so that it looks at `world_xz` on the ground plane (Y = 0).
## Because the camera points at 45° downward, a camera at height Y and XZ
## position (cx, cz) looks at ground point (cx, 0, cz − Y). Inverting:
##   cx = wx,  cz = wz + Y
func center_on(world_xz: Vector2) -> void:
	global_position = Vector3(world_xz.x, global_position.y, world_xz.y + global_position.y)

### ZOOM
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

func get_screen_position_normalized(screen_position_raw: Vector2) -> Vector2:
	return (screen_position_raw*2/get_viewport().get_visible_rect().size)-Vector2.ONE

func _init():
	if projection == PROJECTION_PERSPECTIVE:
		zoom_in = zoom_in_perspective
		zoom_out = zoom_out_perspective
	if projection == PROJECTION_ORTHOGONAL:
		zoom_in = zoom_in_orthogonal
		zoom_out = zoom_out_orthogonal
	else:
		push_error("Cannot set zoom functionality, unsupported Camera3D projection setting: %s" % projection)

func _input(event: InputEvent):
	## CONTROL STATE
	if event.is_action_pressed("isometric_camera_drag"):
		move_reference_position = get_screen_position_normalized(event.position)
		dragging_camera = true
	elif event.is_action_released("isometric_camera_drag"):
		dragging_camera = false
	## MOUSE MOVEMENT
	elif event is InputEventMouseMotion:
		if dragging_camera:
			var new_mouse_pos: Vector2 = get_screen_position_normalized(event.position)
			global_position += -VU.fromXZ(
				new_mouse_pos - move_reference_position
			) * size * movement_speed
			move_reference_position = new_mouse_pos
	
	if event.is_action_pressed("isometric_camera_left", true):
		global_position += Vector3.LEFT*.5
	if event.is_action_pressed("isometric_camera_right", true):
		global_position += Vector3.RIGHT*.5
	if event.is_action_pressed("isometric_camera_up", true):
		global_position += Vector3.FORWARD*.5
	if event.is_action_pressed("isometric_camera_down", true):
		global_position += Vector3.BACK*.5
		

# TODO organize
func get_mouse_world_position(screen_position: Vector2, height: float = 0) -> Vector3:
	var screen_pos_normalized: Vector2 = (screen_position*2/get_viewport().get_visible_rect().size)-Vector2.ONE
	var camera_point_alt: float = (
		global_position.y 
		- screen_pos_normalized.y*(size/2)/sqrt(2)
	)
	
	var depth = (camera_point_alt - height) * sqrt(2)
	return project_position(screen_position, depth)


### NODE
func _process(delta: float) -> void:
	#if direction == Vector3.ZERO:
		#velocity.x = move_toward(velocity.x, 0, movement_friction * delta)
		#velocity.z = move_toward(velocity.z, 0, movement_friction * delta)
	#else:
		#velocity.x = lerp(velocity.x, direction.x, movement_speed * delta)
		#velocity.z = lerp(velocity.z, direction.z, movement_speed * delta)
	
	if Input.is_action_pressed(rotate_left_action):
		rotation.y += rotation_speed * delta
	if Input.is_action_pressed(rotate_right_action):
		rotation.y -= rotation_speed * delta
	
	if Input.is_action_just_pressed(zoom_in_action):
		zoom_in.call(delta, zoom_speed)
	elif Input.is_action_just_pressed(zoom_out_action):
		zoom_out.call(delta, zoom_speed)
