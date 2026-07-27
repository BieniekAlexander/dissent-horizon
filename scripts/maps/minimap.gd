class_name Minimap
extends TextureRect

## Minimap — renders a bird's-eye overview of the battlefield onto a small
## RGBA8 image that is refreshed every render frame.
##
## Each frame:
##   1. The map layer (MinimapLayer: ground, ponds, neutral fixtures, start areas — one colour
##      per cell) is drawn through the fog: unchanged in sight, darkened when explored, black
##      unseen. The layer is rebuilt only when the terrain grid's cells change.
##   2. Every commandable visible to the player is stamped in that
##      commandable's owner colour at the corresponding minimap position:
##        - structures (registered in map.structure_cell_map): 3×3 square
##        - units: filled circle of radius DOT_RADIUS
##      Neutral fixtures are skipped: the map layer already draws them.
##
## Visibility rule (mirrors fog.gd):
##   - Player-owned commandables are always shown.
##   - All other commandables are shown only when in_sight_range is true
##     (fog pixel clear AND not actively stealthed).
##   - While the debug view is up (DebugMode), everything is shown.
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

const _BYTES_PER_PIXEL: int = 4
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
## Per minimap pixel: the index (z * width + x) of the terrain cell under its centre, or -1
## outside the play area; and the world XZ of that centre, for the fog lookup. Both fixed once
## the framing is known.
var _pixel_cells := PackedInt32Array()
var _pixel_worlds := PackedVector2Array()
## The map layer, one colour per terrain cell; rebuilt when _layer_dirty.
var _layer := PackedColorArray()
var _layer_dirty: bool = true
## The neutral fixtures the layer draws, so the entity pass does not draw them again.
var _layer_fixtures: Dictionary = {}
var _pixel_bytes := PackedByteArray()
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

## Radius (in minimap pixels) of the hollow ring stamped around an entity an objective is
## about. Hollow, and larger than DOT_RADIUS, so the unit's own team colour still shows
## through the middle — the marker says "this one matters", not "this one is green".
const OBJECTIVE_RING_RADIUS: int = 3
## Precomputed ring offsets, built in _ready.
var _objective_ring_offsets: Array[Vector2i] = []
## World units covered by one minimap pixel, resolved in _initialize_bounds. Objective
## footprints are sampled at half this, so their outlines land on every pixel they cross
## rather than dotting.
var _world_units_per_pixel: float = 1.0
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

	# Build the objective ring: the annulus one pixel thick at OBJECTIVE_RING_RADIUS.
	var outer_sq: int = OBJECTIVE_RING_RADIUS * OBJECTIVE_RING_RADIUS
	var inner_sq: int = (OBJECTIVE_RING_RADIUS - 1) * (OBJECTIVE_RING_RADIUS - 1)
	for dx: int in range(-OBJECTIVE_RING_RADIUS, OBJECTIVE_RING_RADIUS + 1):
		for dy: int in range(-OBJECTIVE_RING_RADIUS, OBJECTIVE_RING_RADIUS + 1):
			var d_sq: int = dx * dx + dy * dy
			if d_sq <= outer_sq and d_sq > inner_sq:
				_objective_ring_offsets.append(Vector2i(dx, dy))

	# Defer bounds init so the scene tree (Map, height_map) is fully loaded.
	call_deferred(&"_initialize_bounds")

func _initialize_bounds() -> void:
	# Deferred from _ready, so anything that has already supplied framing (a test injecting
	# bounds, a second call) owns it — re-resolving would only overwrite it, and re-warn.
	if _ready_to_draw:
		return
	# The scenario this minimap belongs to, rather than the running scene: they differ when a
	# scenario is instanced under something else (a test, a probe).
	var scenario: Scenario = Scenario.of(self)
	var root: Node = scenario if scenario != null else get_tree().current_scene
	_map = root.find_child("Map") as Map
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
	# World span of one minimap pixel, on whichever axis the framing actually uses.
	var world_span: float = 2.0 * (_screen_half_v if _screen_aligned else _world_half_w)
	_world_units_per_pixel = world_span / float(WIDTH)

	_fog = root.find_child("Fog") as Fog
	_camera = root.find_child("Camera") as RTSCamera3D
	# The minimap lives inside the player's Controller CanvasLayer subtree; walk up
	# to find it so right-clicks / drags can drive the controller's command +
	# selection logic. Absent in spectator (no human controller).
	var ancestor: Node = get_parent()
	while ancestor != null and not (ancestor is RTSController):
		ancestor = ancestor.get_parent()
	_controller = ancestor as RTSController
	_index_pixels()
	if _map.terrain_grid != null:
		_map.terrain_grid.cells_changed.connect(func(_cells: Array) -> void: _layer_dirty = true)
	_ready_to_draw = true

func _gui_input(a_event: InputEvent) -> void:
	if not _ready_to_draw or _camera == null:
		return
	if a_event is InputEventMouseButton:
		var mb: InputEventMouseButton = a_event as InputEventMouseButton
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
	elif a_event is InputEventMouseMotion and _drag_selecting:
		_drag_current_pixel = _event_pixel((a_event as InputEventMouseMotion).position)
		accept_event()

func _process(_a_delta: float) -> void:
	if not _ready_to_draw:
		return

	# Re-resolve the active fog each frame so spectator fog-toggle takes effect immediately.
	var resolved_fog: Variant = Fog.get_active_fog()
	_fog = resolved_fog if resolved_fog is Fog else null

	var reveal_all: bool = DebugMode.is_active()

	# Pass 1: the map layer through the fog. The debug reveal and the omniscient spectator see
	# every cell in sight; with no fog to ask otherwise, terrain stays unseen.
	if _layer_dirty:
		_rebuild_layer()
	_draw_layer(reveal_all or Fog.active_commander_id == -2)

	# Pass 2: draw commandable dots/squares on top of the terrain layer.
	for entity: Entity in get_tree().get_nodes_in_group("piece"):
		if not entity is Commandable:
			continue
		var commandable: Commandable = entity as Commandable

		# Player's own units are always shown. Non-player entities are shown only
		# when in_sight_range is true — meaning the fog pixel is clear AND the
		# unit is not actively stealthed (see fog.gd for where this is written).
		if _layer_fixtures.has(commandable):
			continue
		var is_own: bool = commandable.commander_id == RTSController.PLAYER_COMMANDER_ID
		if not is_own and not commandable.in_sight_range and not reveal_all:
			continue
		# A planted charge is the exception among the player's own: fog.gd draws it only in
		# their vision, and the minimap follows the world.
		if is_own and PlantedCharge.of(commandable) != null and not commandable.visible \
				and not reveal_all:
			continue

		var minimap_pos: Vector2i = world_to_minimap(VU.inXZ(commandable.global_position))
		if minimap_pos.x == -1:
			continue

		var color: Color = Entity.TEAM_COLOR_MAP.get(commandable.commander_id, Color.WHITE)

		if _map.structure_cell_map.has(commandable):
			_draw_pixels(minimap_pos, _square_offsets, color)
		else:
			_draw_pixels(minimap_pos, _dot_offsets, color)

	# Pass 3: overlay objective markers, so what the world highlights point at is also
	# findable on the map. Drawn after the entity pass so a ring is never buried under a dot.
	_draw_objective_markers()

	# Pass 4: overlay the live drag-selection rectangle, if the player is dragging.
	if _drag_selecting:
		_draw_selection_rect()

	(texture as ImageTexture).update(_image)
#endregion

#region Public API
## Inverse of world_to_minimap: returns the world XZ at the centre of a
## minimap pixel. Used to sample the fog explored-bytes per minimap pixel.
func minimap_to_world(a_pixel: Vector2i) -> Vector2:
	var nx: float = (float(a_pixel.x) + 0.5) / float(WIDTH)
	var ny: float = (float(a_pixel.y) + 0.5) / float(HEIGHT)
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
func world_to_minimap(a_world_xz: Vector2) -> Vector2i:
	var nx: float
	var ny: float
	if _screen_aligned:
		# Project the world offset onto the screen axes u = (+X+Z)/sqrt2, v = (+X-Z)/sqrt2, then
		# map v (screen-right) → x and u (screen-down) → y, so top of minimap = screen-up (-u).
		var pc: Vector2 = a_world_xz - _world_center
		var pu: float = (pc.x + pc.y) * _INV_SQRT2
		var pv: float = (pc.x - pc.y) * _INV_SQRT2
		nx = (pv + _screen_half_v) / (2.0 * _screen_half_v)
		ny = (pu + _screen_half_u) / (2.0 * _screen_half_u)
	else:
		nx = (a_world_xz.x - _world_center.x + _world_half_w) / (2.0 * _world_half_w)
		ny = (a_world_xz.y - _world_center.y + _world_half_d) / (2.0 * _world_half_d)
	var px: int = int(nx * float(WIDTH))
	var py: int = int(ny * float(HEIGHT))
	if px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(px, py)
#endregion

#region Map layer
## Fix each pixel's cell and world point for the current framing.
func _index_pixels() -> void:
	var terrain: TerrainData = _map.terrain_data
	_pixel_cells.resize(WIDTH * HEIGHT)
	_pixel_worlds.resize(WIDTH * HEIGHT)
	_pixel_bytes.resize(WIDTH * HEIGHT * _BYTES_PER_PIXEL)
	for y: int in HEIGHT:
		for x: int in WIDTH:
			var i: int = y * WIDTH + x
			var world: Vector2 = minimap_to_world(Vector2i(x, y))
			_pixel_worlds[i] = world
			var cell: Vector2i = _map.world_to_grid(world)
			var in_play: bool = terrain != null and terrain.is_cell_in_bounds(cell) \
				and terrain.is_cell_in_play(cell)
			_pixel_cells[i] = cell.y * terrain.grid_width() + cell.x if in_play else -1


## Gather ponds, neutral fixtures and start areas from the scene into a fresh layer.
func _rebuild_layer() -> void:
	_layer_dirty = false
	var terrain: TerrainData = _map.terrain_data
	if terrain == null:
		return
	var width: int = terrain.grid_width()
	var depth: int = terrain.grid_depth()
	var in_play := PackedByteArray()
	in_play.resize(width * depth)
	for z: int in depth:
		for x: int in width:
			in_play[z * width + x] = 1 if terrain.is_cell_in_play(Vector2i(x, z)) else 0

	var ponds: Array[Dictionary] = []
	for body: WaterBody in _map.water_bodies:
		if not is_instance_valid(body):
			continue
		var cells: Array[Vector2i] = body.basin.covered_cells()
		ponds.append({cells = cells, color = MinimapLayer.pond_color(body.full_charge(), cells.size())})

	_layer_fixtures.clear()
	var fixtures: Array[Dictionary] = []
	for entity: Entity in _map.structure_cell_map:
		if not is_instance_valid(entity) or entity.commander_id != 0:
			continue
		_layer_fixtures[entity] = true
		fixtures.append({cells = _map.structure_cell_map[entity], kind = _fixture_kind(entity)})

	var starts: Array[Dictionary] = []
	var half: float = MapGenerationParams.new().start_clear_radius_cells
	var markers: Array[Node] = get_tree().get_nodes_in_group(Skirmish.START_POINT_GROUP)
	# Sorted by name, as Skirmish matches start points to slots: slot i is commander i + 1.
	markers.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for i: int in markers.size():
		var marker := markers[i] as Node3D
		if marker == null:
			continue
		var cell: Vector2i = _map.world_to_grid(VU.inXZ(marker.global_position))
		starts.append({
			center = Vector2(cell) + Vector2(0.5, 0.5), half = half,
			color = Entity.TEAM_COLOR_MAP.get(i + 1, Color.WHITE)})

	_layer = MinimapLayer.build(width, depth, in_play, ponds, fixtures, starts)


## What a neutral fixture is, for its colour: by the facet it carries, never by its id.
static func _fixture_kind(entity: Entity) -> MinimapLayer.Fixture:
	if ExtractionSite.of(entity) != null:
		return MinimapLayer.Fixture.SITE
	if entity.has_node("Shelter"):
		return MinimapLayer.Fixture.SHELTER
	return MinimapLayer.Fixture.BUILDING


## Write the layer into the image through the fog, one byte array rather than per-pixel calls.
func _draw_layer(a_reveal_all: bool) -> void:
	for i: int in _pixel_cells.size():
		var cell: int = _pixel_cells[i]
		var color: Color = MinimapLayer.OUT_OF_PLAY
		if cell >= 0 and cell < _layer.size():
			var visibility: Fog.TerrainVisibility = Fog.TerrainVisibility.UNSEEN
			if a_reveal_all:
				visibility = Fog.TerrainVisibility.IN_SIGHT
			elif _fog != null:
				visibility = _fog.terrain_visibility_at(_pixel_worlds[i])
			color = MinimapLayer.fogged(_layer[cell], visibility)
		var at: int = i * _BYTES_PER_PIXEL
		_pixel_bytes[at] = color.r8
		_pixel_bytes[at + 1] = color.g8
		_pixel_bytes[at + 2] = color.b8
		_pixel_bytes[at + 3] = 255
	_image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, _pixel_bytes)
#endregion


#region Private helpers
## The minimap pixel under a _gui_input event position. Normalised by the
## Control's actual rendered size so the mapping holds even if layout resizes the
## rect.
func _event_pixel(a_pos: Vector2) -> Vector2i:
	var uv: Vector2 = a_pos / size
	return Vector2i(int(uv.x * float(WIDTH)), int(uv.y * float(HEIGHT)))

## World XZ at the centre of the minimap pixel under a _gui_input event position.
func _pixel_to_world(a_pos: Vector2) -> Vector2:
	return minimap_to_world(_event_pixel(a_pos))

## Convert the drag's two minimap pixels to a world-space XZ rectangle and hand it
## to the controller to select the player units inside.
func _finish_drag_selection(a_end_pixel: Vector2i) -> void:
	if _controller == null:
		return
	var a: Vector2 = minimap_to_world(_drag_start_pixel)
	var b: Vector2 = minimap_to_world(a_end_pixel)
	var world_rect: Rect2 = Rect2(a, b - a).abs()
	# The additive read is POLLED, not latched: this drag is a Control's _gui_input, and the
	# modifier keypress before it went to the focused Control rather than to the controller's
	# _unhandled_input. See RTSController.additive_modifier_held.
	_controller.select_units_in_world_rect(world_rect, _controller.additive_modifier_held())

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

## Stamp every live ScenarioHighlight's targets onto the minimap: a hollow ring around each
## marked entity, and the outline of each marked region.
##
## Sourced from the ScenarioHighlight group rather than from the trigger system, so the
## minimap needs to know nothing about objectives, conditions, or triggers — only that
## something in the world is currently highlighted, and what colour it chose. A highlight and
## its minimap markers therefore can never disagree about either targets or colour.
##
## Deliberately NOT fog-gated. The world painter already rings these targets through terrain,
## so hiding them here would only make the minimap disagree with what is on screen; and an
## objective naming a target the player cannot find is not an objective.
func _draw_objective_markers() -> void:
	for node: Node in get_tree().get_nodes_in_group(ScenarioHighlight.GROUP):
		var highlight := node as ScenarioHighlight
		if highlight == null:
			continue
		var color: Color = highlight.color
		color.a = 1.0

		for entity: Entity in highlight.marked_entities():
			if not is_instance_valid(entity) or not entity.is_inside_tree():
				continue
			var pixel: Vector2i = world_to_minimap(VU.inXZ(entity.global_position))
			if pixel.x != -1:
				_draw_pixels(pixel, _objective_ring_offsets, color)

		for shape: HighlightShape in highlight.marked_shapes():
			_draw_shape_outline(shape, color)


## Trace a footprint's perimeter onto the minimap. Sampled at half a pixel's worth of world
## distance so the outline is continuous rather than a dotted line.
func _draw_shape_outline(a_shape: HighlightShape, a_color: Color) -> void:
	for point: Vector2 in a_shape.perimeter_points(_world_units_per_pixel * 0.5):
		var pixel: Vector2i = world_to_minimap(point)
		if pixel.x != -1:
			_image.set_pixel(pixel.x, pixel.y, a_color)


func _draw_pixels(a_center: Vector2i, a_offsets: Array[Vector2i], a_color: Color) -> void:
	for offset: Vector2i in a_offsets:
		var px: int = a_center.x + offset.x
		var py: int = a_center.y + offset.y
		if px >= 0 and px < WIDTH and py >= 0 and py < HEIGHT:
			_image.set_pixel(px, py, a_color)
#endregion
