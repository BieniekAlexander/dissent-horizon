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
## Precomputed (dx, dy) offsets forming a filled circle of radius DOT_RADIUS.
var _dot_offsets: Array[Vector2i] = []
## Precomputed (dx, dy) offsets forming a filled STRUCTURE_HALF*2+1 square.
var _square_offsets: Array[Vector2i] = []
## True once _initialize_bounds() has resolved the Map node.
var _ready_to_draw: bool = false
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
	_fog = get_tree().current_scene.find_child("Fog") as Fog
	_camera = get_tree().current_scene.find_child("Camera") as RTSCamera3D
	_ready_to_draw = true

func _gui_input(event: InputEvent) -> void:
	if not _ready_to_draw or _camera == null:
		return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		# Normalise the click position by the Control's actual rendered size so
		# the mapping is correct even if layout ever changes the rect dimensions.
		var uv: Vector2 = event.position / size
		var world_xz: Vector2 = minimap_to_world(
			Vector2i(int(uv.x * float(WIDTH)), int(uv.y * float(HEIGHT)))
		)
		_camera.center_on(world_xz)
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

	(texture as ImageTexture).update(_image)
#endregion

#region Public API
## Inverse of world_to_minimap: returns the world XZ at the centre of a
## minimap pixel. Used to sample the fog explored-bytes per minimap pixel.
func minimap_to_world(pixel: Vector2i) -> Vector2:
	var nx: float = (float(pixel.x) + 0.5) / float(WIDTH)
	var ny: float = (float(pixel.y) + 0.5) / float(HEIGHT)
	return Vector2(
		nx * 2.0 * _world_half_w + _world_center.x - _world_half_w,
		ny * 2.0 * _world_half_d + _world_center.y - _world_half_d
	)

## Maps a world XZ coordinate to a minimap pixel.
## Returns Vector2i(-1, -1) when the position lies outside the mapped bounds.
func world_to_minimap(world_xz: Vector2) -> Vector2i:
	var nx: float = (world_xz.x - _world_center.x + _world_half_w) / (2.0 * _world_half_w)
	var ny: float = (world_xz.y - _world_center.y + _world_half_d) / (2.0 * _world_half_d)
	var px: int = int(nx * float(WIDTH))
	var py: int = int(ny * float(HEIGHT))
	if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(px, py)
#endregion

#region Private helpers
func _draw_pixels(center: Vector2i, offsets: Array[Vector2i], color: Color) -> void:
	for offset: Vector2i in offsets:
		var px: int = center.x + offset.x
		var py: int = center.y + offset.y
		if px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
			_image.set_pixel(px, py, color)
#endregion
