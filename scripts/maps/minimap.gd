class_name Minimap
extends TextureRect

## Minimap — renders a bird's-eye overview of the battlefield onto a small
## RGBA8 image that is refreshed every render frame.
##
## Each frame:
##   1. Image is cleared to opaque black.
##   2. Every commandable visible to the player is stamped in that
##      commandable's owner colour at the corresponding minimap position:
##        - structures (registered in map.structure_cell_map): 3×3 square
##        - units: filled circle of radius DOT_RADIUS
##
## Visibility rule (mirrors fog.gd):
##   - Player-owned commandables are always shown.
##   - All other commandables are shown only when in_sight_range is true
##     (fog pixel clear AND not actively stealthed).
##
## Add this node as a child of the Player's Controller CanvasLayer so that it
## renders over the 3D world.

#region Constants
## Image dimensions in pixels. 16:9 ratio, kept small so per-frame fills and
## pixel writes are cheap.
const WIDTH: int = 192
const HEIGHT: int = 108

## Radius (in minimap pixels) of each unit dot.
const DOT_RADIUS: int = 1

## Half-side of the structure square (side = 3 → half = 1, giving offsets -1..+1).
const STRUCTURE_HALF: int = 1

## Terrain colours by fog state.
const EXPLORED_COLOR: Color = Color(0.25, 0.25, 0.25, 1.0)  ## seen before, currently fogged
const IN_SIGHT_COLOR: Color = Color(0.55, 0.55, 0.55, 1.0)  ## inside a unit's vision this frame
#endregion

#region Properties
var _image: Image
var _map: Map
var _fog: Fog
var _camera: RTSCamera3D
var _world_half_w: float
var _world_half_d: float
## World-space XZ origin of the map (typically zero, but read from the Map node
## so the minimap stays correct if the scene is ever repositioned).
var _world_center: Vector2
## When the map has screen-aligned play bounds, the minimap frames THAT rectangle in the
## screen-aligned frame instead of the full axis-aligned grid — so the playspace fills the
## minimap the way it fills the screen (no rotated diamond, no wasted corners). Axes, taken
## from the default camera (RTSCamera3D at +X+Z looking at origin): screen-RIGHT = v = world
## +X-Z (→ minimap x); screen-UP = -u where u = world +X+Z (→ minimap y, +u pointing DOWN).
## _screen_half_u / _v are the play half-extents projected onto u / v.
var _screen_aligned: bool = false
var _screen_half_u: float
var _screen_half_v: float
const _INV_SQRT2: float = 0.7071067811865476
## Precomputed (dx, dy) offsets forming a filled circle of radius DOT_RADIUS.
var _dot_offsets: Array[Vector2i] = []
## Precomputed (dx, dy) offsets forming a filled STRUCTURE_HALF*2+1 square.
var _square_offsets: Array[Vector2i] = []
## True once _initialize_bounds() has resolved the Map node.
var _ready_to_draw: bool = false
## The player's RTSController (an ancestor of this node), resolved in
## _initialize_bounds. Null in spectator, where there is no human controller —
## right-click commands and drag-selection are then no-ops.
var _controller: RTSController

## Drag-selection state. While the left button is held over the minimap the player
## is defining a world-space selection box; on release we convert the two minimap
## pixels to world XZ and ask the controller to select the units inside.
var _drag_selecting: bool = false
var _drag_start_pixel: Vector2i = Vector2i.ZERO
var _drag_current_pixel: Vector2i = Vector2i.ZERO
## Outline colour of the on-minimap drag-selection rectangle.
const DRAG_RECT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
#endregion

#region Lifecycle
func _ready() -> void:
	_image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	_image.fill(Color.BLACK)
	texture = ImageTexture.create_from_image(_image)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Stop mouse events at this Control so they don't propagate up to
	# _unhandled_input and trigger RTSController's selection/command logic.
	# TextureRect defaults to MOUSE_FILTER_PASS, which is why clicks were
	# reaching the game even after accept_event() was called in _gui_input.
	mouse_filter = MOUSE_FILTER_STOP

	# Build the unit disc offset table.
	for dx: int in range(-DOT_RADIUS, DOT_RADIUS + 1):
		for dy: int in range(-DOT_RADIUS, DOT_RADIUS + 1):
			if dx * dx + dy * dy <= DOT_RADIUS * DOT_RADIUS:
				_dot_offsets.append(Vector2i(dx, dy))

	# Build the structure square offset table (3×3 filled square).
	for dx: int in range(-STRUCTURE_HALF, STRUCTURE_HALF + 1):
		for dy: int in range(-STRUCTURE_HALF, STRUCTURE_HALF + 1):
			_square_offsets.append(Vector2i(dx, dy))

	# Defer bounds init so the scene tree (Map, height_map) is fully loaded.
	call_deferred(&"_initialize_bounds")

func _initialize_bounds() -> void:
	_map = get_tree().current_scene.find_child("Map") as Map
	if _map == null:
		push_warning("Minimap: no Map node found — minimap will remain blank")
		return
	var hs: HeightMapShape3D = _map.height_map
	# HeightMapShape3D with map_width W spans local X in [-(W-1)/2, +(W-1)/2].
	# Multiply by CELL_SIZE (= Map's scale) to get world half-extents.
	_world_half_w = (hs.map_width - 1) * 0.5 * Map.CELL_SIZE
	_world_half_d = (hs.map_depth - 1) * 0.5 * Map.CELL_SIZE
	_world_center = VU.inXZ(_map.global_position)

	# If the map defines screen-aligned play bounds, frame that rectangle instead. One (s,t)
	# unit moves the cell by (0.5, 0.5), i.e. CELL_SIZE/sqrt(2) of world distance along its
	# screen axis, so the world half-extent along u/v is half_st * CELL_SIZE / sqrt(2).
	var td: TerrainData = _map.terrain_data
	var half_st: Vector2 = td.play_half_extents() if td != null else Vector2.ZERO
	if half_st != Vector2.ZERO:
		_screen_aligned = true
		_screen_half_u = half_st.x * Map.CELL_SIZE * _INV_SQRT2
		_screen_half_v = half_st.y * Map.CELL_SIZE * _INV_SQRT2
	_fog = get_tree().current_scene.find_child("Fog") as Fog
	_camera = get_tree().current_scene.find_child("Camera") as RTSCamera3D
	# The minimap lives inside the player's Controller CanvasLayer subtree; walk up
	# to find it so right-clicks / drags can drive the controller's command +
	# selection logic. Absent in spectator (no human controller).
	var ancestor: Node = get_parent()
	while ancestor != null and not (ancestor is RTSController):
		ancestor = ancestor.get_parent()
	_controller = ancestor as RTSController
	_ready_to_draw = true

func _gui_input(event: InputEvent) -> void:
	if not _ready_to_draw or _camera == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				# Middle click recentres the camera on the clicked world position
				# (was the left-click behaviour before the remap).
				if mb.pressed:
					_camera.center_on(_pixel_to_world(mb.position))
					accept_event()
			MOUSE_BUTTON_RIGHT:
				# Right click issues the controller's armed command at the clicked
				# world position (move / attack-move / ability / ...).
				if mb.pressed:
					if _controller != null:
						_controller.issue_command_at_world_position(_pixel_to_world(mb.position))
					accept_event()
			MOUSE_BUTTON_LEFT:
				# Left click-drag defines a world-space selection box.
				if mb.pressed:
					_drag_selecting = true
					_drag_start_pixel = _event_pixel(mb.position)
					_drag_current_pixel = _drag_start_pixel
				elif _drag_selecting:
					_drag_selecting = false
					_finish_drag_selection(_event_pixel(mb.position))
				accept_event()
	elif event is InputEventMouseMotion and _drag_selecting:
		_drag_current_pixel = _event_pixel((event as InputEventMouseMotion).position)
		accept_event()

func _process(_delta: float) -> void:
	if not _ready_to_draw:
		return

	# Re-resolve the active fog each frame so spectator fog-toggle takes effect immediately.
	var resolved_fog: Variant = Fog.get_active_fog()
	_fog = resolved_fog if resolved_fog is Fog else null

	_image.fill(Color.BLACK)

	# Pass 1: shade terrain by fog state.
	#   UNSEEN   → black (already filled above, no write needed)
	#   EXPLORED → dark grey (seen before, currently fogged)
	#   IN_SIGHT → light grey (inside the active commander's vision this frame)
	if _fog != null:
		for mpy: int in HEIGHT:
			for mpx: int in WIDTH:
				match _fog.terrain_visibility_at(minimap_to_world(Vector2i(mpx, mpy))):
					Fog.TerrainVisibility.EXPLORED:
						_image.set_pixel(mpx, mpy, EXPLORED_COLOR)
					Fog.TerrainVisibility.IN_SIGHT:
						_image.set_pixel(mpx, mpy, IN_SIGHT_COLOR)
	elif Fog.active_commander_id == -2:
		# Omniscient spectator: all terrain is visible.
		_image.fill(IN_SIGHT_COLOR)

	# Pass 2: draw commandable dots/squares on top of the terrain layer.
	for entity: Entity in get_tree().get_nodes_in_group("commandable"):
		if not entity is Commandable:
			continue
		var commandable: Commandable = entity as Commandable

		# Player's own units are always shown. Non-player entities are shown only
		# when in_sight_range is true — meaning the fog pixel is clear AND the
		# unit is not actively stealthed (see fog.gd for where this is written).
		var is_own: bool = commandable.commander_id == RTSController.PLAYER_COMMANDER_ID
		if not is_own and not commandable.in_sight_range:
			continue

		var minimap_pos: Vector2i = world_to_minimap(VU.inXZ(commandable.global_position))
		if minimap_pos.x == -1:
			continue

		var color: Color = Entity.TEAM_COLOR_MAP.get(commandable.commander_id, Color.WHITE)

		if _map.structure_cell_map.has(commandable):
			_draw_pixels(minimap_pos, _square_offsets, color)
		else:
			_draw_pixels(minimap_pos, _dot_offsets, color)

	# Pass 3: overlay the live drag-selection rectangle, if the player is dragging.
	if _drag_selecting:
		_draw_selection_rect()

	(texture as ImageTexture).update(_image)
#endregion

#region Public API
## Inverse of world_to_minimap: returns the world XZ at the centre of a
## minimap pixel. Used to sample the fog explored-bytes per minimap pixel.
func minimap_to_world(pixel: Vector2i) -> Vector2:
	var nx: float = (float(pixel.x) + 0.5) / float(WIDTH)
	var ny: float = (float(pixel.y) + 0.5) / float(HEIGHT)
	if _screen_aligned:
		# Un-normalise onto the screen axes (v = screen-right → x; u = screen-down → y), then
		# rotate the (u, v) offset back into world XZ: X = (u + v)/sqrt2, Z = (u - v)/sqrt2.
		var pv: float = nx * 2.0 * _screen_half_v - _screen_half_v
		var pu: float = ny * 2.0 * _screen_half_u - _screen_half_u
		return Vector2(
			(pu + pv) * _INV_SQRT2 + _world_center.x,
			(pu - pv) * _INV_SQRT2 + _world_center.y
		)
	return Vector2(
		nx * 2.0 * _world_half_w + _world_center.x - _world_half_w,
		ny * 2.0 * _world_half_d + _world_center.y - _world_half_d
	)

## Maps a world XZ coordinate to a minimap pixel.
## Returns Vector2i(-1, -1) when the position lies outside the mapped bounds.
func world_to_minimap(world_xz: Vector2) -> Vector2i:
	var nx: float
	var ny: float
	if _screen_aligned:
		# Project the world offset onto the screen axes u = (+X+Z)/sqrt2, v = (+X-Z)/sqrt2, then
		# map v (screen-right) → x and u (screen-down) → y, so top of minimap = screen-up (-u).
		var pc: Vector2 = world_xz - _world_center
		var pu: float = (pc.x + pc.y) * _INV_SQRT2
		var pv: float = (pc.x - pc.y) * _INV_SQRT2
		nx = (pv + _screen_half_v) / (2.0 * _screen_half_v)
		ny = (pu + _screen_half_u) / (2.0 * _screen_half_u)
	else:
		nx = (world_xz.x - _world_center.x + _world_half_w) / (2.0 * _world_half_w)
		ny = (world_xz.y - _world_center.y + _world_half_d) / (2.0 * _world_half_d)
	var px: int = int(nx * float(WIDTH))
	var py: int = int(ny * float(HEIGHT))
	if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(px, py)
#endregion

#region Private helpers
## The minimap pixel under a _gui_input event position. Normalised by the
## Control's actual rendered size so the mapping holds even if layout resizes the
## rect.
func _event_pixel(pos: Vector2) -> Vector2i:
	var uv: Vector2 = pos / size
	return Vector2i(int(uv.x * float(WIDTH)), int(uv.y * float(HEIGHT)))

## World XZ at the centre of the minimap pixel under a _gui_input event position.
func _pixel_to_world(pos: Vector2) -> Vector2:
	return minimap_to_world(_event_pixel(pos))

## Convert the drag's two minimap pixels to a world-space XZ rectangle and hand it
## to the controller to select the player units inside.
func _finish_drag_selection(end_pixel: Vector2i) -> void:
	if _controller == null:
		return
	var a: Vector2 = minimap_to_world(_drag_start_pixel)
	var b: Vector2 = minimap_to_world(end_pixel)
	var world_rect: Rect2 = Rect2(a, b - a).abs()
	_controller.select_units_in_world_rect(world_rect, _controller.next_command_additive)

## Draw the drag-selection rectangle outline (in minimap pixel space) so the
## player sees the box they're dragging. Called from _process while dragging.
func _draw_selection_rect() -> void:
	var x0: int = clampi(mini(_drag_start_pixel.x, _drag_current_pixel.x), 0, WIDTH - 1)
	var x1: int = clampi(maxi(_drag_start_pixel.x, _drag_current_pixel.x), 0, WIDTH - 1)
	var y0: int = clampi(mini(_drag_start_pixel.y, _drag_current_pixel.y), 0, HEIGHT - 1)
	var y1: int = clampi(maxi(_drag_start_pixel.y, _drag_current_pixel.y), 0, HEIGHT - 1)
	for x: int in range(x0, x1 + 1):
		_image.set_pixel(x, y0, DRAG_RECT_COLOR)
		_image.set_pixel(x, y1, DRAG_RECT_COLOR)
	for y: int in range(y0, y1 + 1):
		_image.set_pixel(x0, y, DRAG_RECT_COLOR)
		_image.set_pixel(x1, y, DRAG_RECT_COLOR)

func _draw_pixels(center: Vector2i, offsets: Array[Vector2i], color: Color) -> void:
	for offset: Vector2i in offsets:
		var px: int = center.x + offset.x
		var py: int = center.y + offset.y
		if px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
			_image.set_pixel(px, py, color)
#endregion
