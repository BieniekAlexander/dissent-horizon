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

## How close to a screen edge the cursor must get before the camera starts panning that way.
##
## PIXELS, not world units or a fraction of the screen. This is a a screen-space affordance:
## the player is aiming at the physical edge of their monitor, so the band has to be a fixed
## physical size. A fraction of the viewport would make the band grow on a big display (where
## it is proportionally harder to hit the edge by accident) and shrink on a small one — the
## opposite of what you want — and world units are meaningless here, since the same screen
## band covers more ground the further out you zoom.
const EDGE_PAN_MARGIN_PX: float = 16.0

## How far out the player may zoom, as a multiple of the `size` the camera was authored with.
## Captured from the scene rather than fixed in world units so each camera keeps its own
## framing as the baseline. Orthographic only — `size` is the zoom for an ortho camera, and
## the FOV for a perspective one.
const MAX_ZOOM_OUT_FACTOR: float = 2.0

## How far in the player may zoom, as a multiple of the authored `size`. Same reasoning as
## the ceiling: measured against the camera's own framing rather than a fixed world size.
const MIN_ZOOM_IN_FACTOR: float = 0.5

## How far past the edge of the terrain the view may be pushed, as a fraction of the visible
## half-extent — so it scales with zoom rather than being a fixed world distance.
##
## This exists because the HUD covers the bottom of the screen. Clamped exactly at the map
## edge, the southern strip of terrain would sit permanently behind the command panels with
## no way to bring it into the clear. At the authored zoom the visible half-extent along the
## ground is about 10.6 units, so 0.35 of that is ~3.7 — a little more than the ~18% of screen
## height the HUD occupies, which is what it takes to lift the map's edge out from under it.
const EDGE_OVERSCROLL_RATIO: float = 0.35

## Extra pan headroom on the SCREEN-UP side of the play area, as a multiple of the ground
## distance a cruising aerial unit is displaced by.
##
## Flying units cruise at Aerial.AERIAL_HEIGHT above the terrain and the camera looks down
## at an angle, so an aerial unit is DRAWN further toward the top of the screen than the
## ground beneath it — by height / tan(elevation) of ground distance, which at this camera's
## 45° elevation is the height itself. Without this, a flier holding station over the far
## edge of the play area is clipped off the top of the screen with no way to pan to it, even
## though the ground under it is perfectly reachable.
##
## Expressed as a WORLD distance (see altitude_headroom) rather than a fraction of the view
## like EDGE_OVERSCROLL_RATIO, and the difference is not an oversight: that margin exists
## because the HUD covers a fixed FRACTION of the screen, so it must scale with zoom, while
## this one compensates for a fixed WORLD offset and must NOT shrink as you zoom in.
##
## The slack above 1.0 keeps the unit clear of the very edge rather than flush against it.
const ALTITUDE_HEADROOM_SLACK: float = 1.25
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

## Multipliers on DRAG-pan distance while a modifier is held: narrow for fine placement,
## broaden for a fast sweep across the map. The same direction those two carry in every other
## key space — narrow restricts, broaden widens (see ui/control-matrices.md §The axes).
##
## Exported so they can become an options-menu sensitivity setting later without moving the
## rule; nothing wires them to one today.
@export var precise_pan_factor: float = 0.5
@export var fast_pan_factor: float = 2.0

## Edge-pan rate, in world units per second per unit of the camera's orthographic `size`.
## Scaled by `size` for the same reason drag panning is: zoomed out, a screen-edge nudge
## should cover proportionally more ground, or panning feels glacial at low zoom.
@export var edge_pan_speed: float = 0.6
## Turn edge panning off entirely (a scenario that wants the camera locked, an options
## toggle later on).
@export var edge_pan_enabled: bool = true

## Keep the view on (or near) the terrain. Off lets the camera roam freely — for a cutscene
## camera, or a scene with no Map to bound against.
@export var clamp_to_map_bounds: bool = true
#endregion

#region Zoom
@export_category("Zoom")
@export var zoom_speed: float = 20.0
@export var zoom_in_action: String = "isometric_camera_zoom_in"
@export var zoom_out_action: String = "isometric_camera_zoom_out"
var zoom_velocity: Vector3 = Vector3.ZERO

## The zoom range, both ends captured from the authored value in _ready.
var _max_size: float = 0.0
var _min_size: float = 0.0

## The scenario's Map, cached by _resolve_map. Null in scenes without one, where the camera
## simply isn't bounded.
var _map: Map = null


func zoom_in_orthogonal(_a_delta: float, a_zoom_speed: float) -> void:
	size /= (100 + a_zoom_speed) / 100


func zoom_out_orthogonal(_a_delta: float, a_zoom_speed: float) -> void:
	size *= (100 + a_zoom_speed) / 100


func zoom_in_perspective(a_delta: float, a_zoom_speed: float) -> void:
	zoom_velocity = -global_transform.basis.z * a_zoom_speed * a_delta
	zoom_velocity = lerp(zoom_velocity, Vector3.ZERO, (a_zoom_speed / 2) * a_delta)
	position += zoom_velocity


func zoom_out_perspective(a_delta: float, a_zoom_speed: float) -> void:
	zoom_velocity = global_transform.basis.z * a_zoom_speed * a_delta
	zoom_velocity = lerp(zoom_velocity, Vector3.ZERO, (a_zoom_speed / 2) * a_delta)
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
func center_on(a_world_xz: Vector2) -> void:
	var f: Vector3 = -global_transform.basis.z
	if is_zero_approx(f.y):
		return
	var y: float = global_position.y
	var k: float = y / f.y
	global_position = Vector3(a_world_xz.x + k * f.x, y, a_world_xz.y + k * f.z)


func get_screen_position_normalized(a_screen_position_raw: Vector2) -> Vector2:
	return (a_screen_position_raw * 2 / get_viewport().get_visible_rect().size) - Vector2.ONE


## Raycast the cursor against the horizontal plane at `height`. Works for any
## camera orientation and projection (orthographic or perspective), so it no
## longer bakes in the old pitch-45°/no-yaw assumption.
func get_mouse_world_position(a_screen_position: Vector2, a_height: float = 0) -> Vector3:
	var ray_origin: Vector3 = project_ray_origin(a_screen_position)
	var ray_dir: Vector3 = project_ray_normal(a_screen_position)
	if is_zero_approx(ray_dir.y):
		return project_position(a_screen_position, 0.0)
	var t: float = (a_height - ray_origin.y) / ray_dir.y
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
		push_error(
			(
				"Cannot set zoom functionality, unsupported Camera3D projection setting: %s"
				% projection
			)
		)


func _ready() -> void:
	# Pan / zoom / rotate keep working while a SimulationClock hold pauses the world: a
	# scripted beat that says "look at the ridge to the east" is unusable if the player can't
	# move the camera to see it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The authored framing is the reference both zoom limits are measured against.
	_max_size = size * MAX_ZOOM_OUT_FACTOR
	_min_size = size * MIN_ZOOM_IN_FACTOR
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


func _input(a_event: InputEvent):
	if a_event.is_action_pressed("isometric_camera_drag"):
		move_reference_position = get_screen_position_normalized(a_event.position)
		dragging_camera = true
	elif a_event.is_action_released("isometric_camera_drag"):
		dragging_camera = false
	elif a_event is InputEventMouseMotion:
		if dragging_camera:
			var new_mouse_pos: Vector2 = get_screen_position_normalized(a_event.position)
			var d: Vector2 = new_mouse_pos - move_reference_position
			global_position += (
				(-_ground_right() * d.x + _ground_forward() * d.y)
				* size
				* movement_speed
				* drag_pan_factor()
			)
			move_reference_position = new_mouse_pos

	if a_event.is_action_pressed("isometric_camera_left", true):
		global_position += -_ground_right() * 10
	if a_event.is_action_pressed("isometric_camera_right", true):
		global_position += _ground_right() * 10
	if a_event.is_action_pressed("isometric_camera_up", true):
		global_position += _ground_forward() * 10
	if a_event.is_action_pressed("isometric_camera_down", true):
		global_position += -_ground_forward() * 10

	_handle_zoom_input(a_event)


## How far this drag pans, per unit of mouse travel — 1.0 unmodified.
##
## The two factors MULTIPLY, so holding both cancels back to 1.0. That is the honest
## arithmetic for two opposite scalars, and it is why this needs no precedence rule where the
## control-group table needs one: there, narrow and broaden name opposite WRITES and exactly
## one of them has to happen, so one must win. A scalar can simply be 1.
##
## POLLED rather than read off the event, for the reason every other modifier here is polled:
## a modifier keydown that lands while a HUD Control has focus never reaches the input
## handlers, so a latch would miss it (see ui/control-matrices.md §The axes).
func drag_pan_factor() -> float:
	var factor: float = 1.0
	if Input.is_action_pressed(RTSController.MODIFIER_NARROW):
		factor *= precise_pan_factor
	if Input.is_action_pressed(RTSController.MODIFIER_BROADEN):
		factor *= fast_pan_factor
	return factor


func _process(a_delta: float) -> void:
	if Input.is_action_pressed(rotate_left_action):
		rotation.y += rotation_speed * a_delta
	if Input.is_action_pressed(rotate_right_action):
		rotation.y -= rotation_speed * a_delta

	# Zoom is handled in _input (see _handle_zoom_input) rather than polled here, because the
	# wheel and the +/- keys need different rules and polling cannot tell them apart.

	# Order matters: the zoom ceiling first, because how far the camera may travel depends on
	# how much ground is visible; then the pan; then the limits, so every way the camera can
	# have moved this frame — drag and arrow keys from _input, edge pan, an outside center_on —
	# is caught by one check.
	_clamp_zoom()
	_apply_edge_pan(a_delta)
	_clamp_to_map_bounds()


#endregion


#region Zoom input
## Apply a zoom step for `event`, if it is a zoom binding and the guard below allows it.
##
## Event-driven rather than polled in _process because this action has TWO bindings that
## deserve different treatment: a wheel notch is AIMED at whatever sits under the cursor, so
## it must do nothing over the HUD or an open dialog, while the +/- keys are aimed at nothing
## and must keep working wherever the mouse happens to be resting — including over a panel
## the player just clicked. Input.is_action_just_pressed reports only that the action fired,
## not which binding fired it, so the split has to happen where the event is still in hand.
##
## Deliberately _input and not _unhandled_input: _input sees the event before any Control
## does, so the decision is made HERE by an explicit test, rather than falling out of whichever
## mouse_filter a panel happens to carry. A HUD panel set to MOUSE_FILTER_PASS would otherwise
## let the wheel through and silently zoom the world behind it.
func _handle_zoom_input(a_event: InputEvent) -> void:
	var zoom_in_pressed: bool = a_event.is_action_pressed(zoom_in_action)
	var zoom_out_pressed: bool = a_event.is_action_pressed(zoom_out_action)
	if not zoom_in_pressed and not zoom_out_pressed:
		return
	if not zoom_allowed(a_event, _pointer_over_ui()):
		return

	var delta: float = get_process_delta_time()
	if zoom_in_pressed:
		zoom_in.call(delta, zoom_speed)
	else:
		zoom_out.call(delta, zoom_speed)
	# _process clamps every frame anyway; doing it here as well keeps several wheel notches
	# arriving in one frame from driving `size` past the limit part-way through that frame.
	_clamp_zoom()


## Whether a zoom triggered by `event` should apply, given whether the pointer is over UI.
##
## Split out as a static, pure decision the same way edge_pan_direction is: gathering the
## live value needs a viewport and a HUD, deciding does not — so the rule is testable
## headlessly while the live lookup stays in _handle_zoom_input.
static func zoom_allowed(event: InputEvent, pointer_over_ui: bool) -> bool:
	if event is InputEventMouseButton:
		return not pointer_over_ui
	return true  # keyboard zoom isn't aimed at anything the cursor is resting on


## True when the cursor sits over a HUD panel or an open dialog. Routes through
## RTSController so "the cursor is over UI" keeps exactly one definition across selection,
## edge panning and zoom.
func _pointer_over_ui() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	return RTSController.pointer_over_blocking_ui(get_tree(), viewport.get_mouse_position())


#endregion


#region Zoom limits
## Hold the zoom inside the authored framing scaled by MIN_ZOOM_IN_FACTOR..MAX_ZOOM_OUT_FACTOR.
##
## Applied to the resulting `size` rather than inside the zoom callables, so it holds however
## the zoom was driven — the action handlers here, a future slider, a scripted framing.
func _clamp_zoom() -> void:
	if projection != PROJECTION_ORTHOGONAL or _max_size <= 0.0:
		return
	size = clampf(size, _min_size, _max_size)


#endregion


#region Map bounds
## Keep the view on the play area, give or take EDGE_OVERSCROLL_RATIO.
##
## Clamps where the camera is LOOKING (its ground focus), not where it is: at a 45° pitch the
## camera body sits well behind and above what's on screen, so bounding the position itself
## would leave the view wandering off by a zoom-dependent offset.
##
## The rule is that the visible ground rectangle stays inside the play area grown by the
## overscroll margin. Because the margin and the view size both scale with zoom, this holds
## its feel across the whole zoom range: pulled back you may sit further out, pushed in you
## are held closer.
func _clamp_to_map_bounds() -> void:
	if not clamp_to_map_bounds:
		return
	var map: Map = _resolve_map()
	if map == null:
		return
	var area: PlayArea = map.play_area()
	if area == null or not area.is_valid():
		return

	var half_view: Vector2 = visible_half_extents_in(area)
	if half_view == Vector2.ZERO:
		return
	var focus: Vector2 = ground_focus()
	# Which way "up the screen" runs across the ground, in the play area's frame — the side the
	# altitude headroom is added to. Taken from the live basis rather than assumed, so a yawed
	# camera still gets the extra room on the side fliers are actually drawn toward.
	var look_local: Vector2 = area.to_local_direction(VU.in_xz(_ground_forward()))
	var target: Vector2 = clamped_focus(focus, area, half_view, look_local)
	if not target.is_equal_approx(focus):
		center_on(target)


## Where the camera may look, given the play area and how much ground is on screen.
##
## Split from _clamp_to_map_bounds so the rule can be exercised against a made-up play area
## and zoom level: gathering the live values needs a Map and a viewport, deciding does not.
##
## Done entirely in the play area's OWN frame, where the rectangle is just ±half and the
## clamp is one line per axis. That frame is usually rotated 45° from the world (TerrainData
## authors play bounds in screen-aligned s/t), and its two axes are independent — a play area
## may be rectangular, not only square — so bounding per-axis in the world frame would both
## admit the dead corners outside the rotated rectangle and ignore the authored aspect.
##
## `half_view` must already be measured along the same axes; see visible_half_extents_in.
## `look_local` is the direction the camera looks, in the area's frame and unit length — the
## way "up the screen" points across the ground. The altitude headroom is added on THAT side
## only, so it follows the camera's yaw instead of assuming the default orientation. Passing
## Vector2.ZERO (the default) gives the plain symmetric margin.
func clamped_focus(
	a_focus: Vector2, a_area: PlayArea, a_half_view: Vector2, a_look_local: Vector2 = Vector2.ZERO
) -> Vector2:
	var margin: Vector2 = a_half_view * EDGE_OVERSCROLL_RATIO
	var limit: Vector2 = a_area.half + margin - a_half_view
	# Signed per axis: the component of the look direction along each axis decides which end of
	# that axis the headroom extends, and by how much of it.
	var headroom: Vector2 = a_look_local * altitude_headroom()
	var local: Vector2 = a_area.to_local(a_focus)
	return a_area.to_world(
		Vector2(
			_clamp_with_headroom(local.x, limit.x, headroom.x),
			_clamp_with_headroom(local.y, limit.y, headroom.y)
		)
	)


## Ground distance an aerial unit at cruise altitude appears displaced toward the top of the
## screen, times the slack. Derived from the authored camera angle rather than hard-coded, so
## changing CAMERA_ANGLE_DEGREES keeps the headroom honest: a shallower camera lifts fliers
## further up the screen and needs more of it.
static func altitude_headroom() -> float:
	var pitch: float = deg_to_rad(CAMERA_ANGLE_DEGREES)
	var up: float = -sin(pitch)  # how much of the camera offset is elevation
	var back: float = -cos(pitch)  # …and how much is ground distance
	if is_zero_approx(up):
		return 0.0  # a horizontal camera has no vertical foreshortening to correct
	return Aerial.AERIAL_HEIGHT * absf(back / up) * ALTITUDE_HEADROOM_SLACK


## clampf into ±limit, widened by `headroom` on whichever side the headroom points, except
## that a non-positive limit means the view already covers that whole axis of the play area —
## zoomed out past a small map. Centring is the only stable answer there; clamping would jam
## the view against whichever end was tested last.
static func _clamp_with_headroom(value: float, limit: float, headroom: float) -> float:
	if limit <= 0.0:
		return 0.0
	return clampf(value, -limit + minf(headroom, 0.0), limit + maxf(headroom, 0.0))


## The XZ point the camera's forward ray meets the ground plane — the inverse of center_on,
## and what "where the camera is looking" means for bounding purposes.
func ground_focus() -> Vector2:
	var f: Vector3 = -global_transform.basis.z
	if is_zero_approx(f.y):
		return VU.in_xz(global_position)
	var k: float = global_position.y / f.y
	return Vector2(global_position.x - k * f.x, global_position.z - k * f.z)


## Half the ground area currently on screen, measured along `area`'s axes.
##
## Measured by projecting the four screen corners onto the ground rather than derived from
## `size` and the pitch, so it stays correct through zoom, yaw, rotation, aspect changes and
## either projection — the same raycast the cursor already uses.
##
## Measured in the PLAY AREA's frame rather than the world's, which matters at the default
## camera: the view is a diamond in world XZ but axis-aligned in the screen-aligned frame the
## play bounds are authored in, so its world-XZ bounding box is ~√2 too large. Measuring here
## is both correct and tighter. Rotating the camera tilts the view relative to that frame
## again, and this then reports the box around it — bounding slightly early, which is the
## conservative direction.
func visible_half_extents_in(a_area: PlayArea) -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var rect_size: Vector2 = viewport.get_visible_rect().size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return Vector2.ZERO
	var focus: Vector2 = a_area.to_local(ground_focus())
	var half := Vector2.ZERO
	for corner: Vector2 in [
		Vector2.ZERO, Vector2(rect_size.x, 0.0), Vector2(0.0, rect_size.y), rect_size
	]:
		var ground: Vector3 = get_mouse_world_position(corner)
		var local: Vector2 = a_area.to_local(VU.in_xz(ground))
		half.x = maxf(half.x, absf(local.x - focus.x))
		half.y = maxf(half.y, absf(local.y - focus.y))
	return half


## The scenario's Map, resolved once. Same lookup RTSController and Minimap use.
func _resolve_map() -> Map:
	if _map != null and is_instance_valid(_map):
		return _map
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	_map = scene.find_child("Map") as Map
	return _map


#endregion


#region Edge panning
## Pan while the cursor rests within EDGE_PAN_MARGIN_PX of a screen edge, in the direction
## from the middle of the screen toward it — push against the right edge and the view slides
## right; sit in a corner and it slides diagonally.
##
## Called from _process (not _input) because this is a HELD state, not an event: the camera
## must keep moving while the cursor stays put, and a stationary mouse produces no motion
## events at all.
func _apply_edge_pan(a_delta: float) -> void:
	if not edge_pan_enabled:
		return
	# Drag panning is already steering the camera from the same mouse; two controllers fighting
	# over one position is worse than either alone, and a drag routinely ends up near an edge.
	if dragging_camera:
		return
	# Alt-tabbed with the cursor left sitting over the window: nothing is asking for a pan, and
	# a camera that slid away while the player was elsewhere would be baffling.
	var window: Window = get_window()
	if window != null and not window.has_focus():
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var rect_size: Vector2 = viewport.get_visible_rect().size
	var cursor: Vector2 = viewport.get_mouse_position()
	# Outside the window the coordinates just keep going, which reads as a permanent request to
	# pan that way — the camera would run off on its own the moment the mouse left the frame.
	if cursor.x < 0.0 or cursor.y < 0.0 or cursor.x > rect_size.x or cursor.y > rect_size.y:
		return
	# The HUD lines the bottom of the screen, so its panels and the edge band are the same
	# pixels. Reaching for the minimap must not drag the view out from under the cursor.
	if RTSController.pointer_over_blocking_ui(get_tree(), cursor):
		return

	var direction: Vector3 = edge_pan_direction(cursor, rect_size)
	if direction == Vector3.ZERO:
		return
	global_position += edge_pan_step(direction, a_delta)


## The world-space offset one frame of edge panning applies for `direction`.
##
## Split out so the scaling rule is stated once and can be checked without a window: reading
## the live cursor needs a real viewport, this arithmetic doesn't.
func edge_pan_step(a_direction: Vector3, a_delta: float) -> Vector3:
	return a_direction * edge_pan_speed * size * a_delta


## The ground-plane direction a cursor at `cursor` asks for, in a viewport of `rect_size`;
## Vector3.ZERO when it isn't in any edge band.
##
## Which BANDS the cursor is in decides the heading, not where it sits relative to the middle
## of the screen: a vertical edge pans horizontally, a horizontal edge pans vertically, and a
## corner — both bands at once — pans diagonally. So anywhere along the left edge pans due
## left, whether the cursor is high, low, or halfway up it.
##
## Normalized, so a corner travels at the same speed as an edge rather than the √2 a raw
## (±1, ±1) would give. Speed is edge_pan_speed's job alone.
##
## Screen Y grows downward while _ground_forward() points up the screen, hence the flipped
## sign on the vertical — without it the vertical axis is inverted.
##
## Pure — no input, no viewport, no clock — so the geometry can be exercised directly. The
## live guards (focus, drag, HUD, cursor outside the window) live in _apply_edge_pan.
func edge_pan_direction(a_cursor: Vector2, a_rect_size: Vector2) -> Vector3:
	if a_rect_size.x <= 0.0 or a_rect_size.y <= 0.0:
		return Vector3.ZERO

	var horizontal: float = 0.0
	if a_cursor.x <= EDGE_PAN_MARGIN_PX:
		horizontal = -1.0
	elif a_cursor.x >= a_rect_size.x - EDGE_PAN_MARGIN_PX:
		horizontal = 1.0

	var vertical: float = 0.0
	if a_cursor.y <= EDGE_PAN_MARGIN_PX:
		vertical = 1.0
	elif a_cursor.y >= a_rect_size.y - EDGE_PAN_MARGIN_PX:
		vertical = -1.0

	if is_zero_approx(horizontal) and is_zero_approx(vertical):
		return Vector3.ZERO
	return (_ground_right() * horizontal + _ground_forward() * vertical).normalized()
#endregion
