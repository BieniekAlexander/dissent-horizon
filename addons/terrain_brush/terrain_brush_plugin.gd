@tool
extends EditorPlugin

## Paint terrain TILE TYPES directly in the 3D viewport (Stage 3 of terrain-tile-types.md).
##
## Toggle "Terrain Brush" in the spatial-editor toolbar, pick a Mode, a footprint Shape
## (Circle/Square), a radius, and (per mode) a tile type or a target height, then
## left-click-drag over a Map's terrain:
##   * Paint  — writes the chosen tile type into Map.terrain_data.tile_types (per cell); the
##              mesh (impassable cells = holes) updates live, the BlockPin tri-state overlay
##              refreshes on release.
##   * Set     — flatten the per-corner heights under the brush to the target-height value
##              (clamped to [0, 5], snapped to 0.5); the terrain mesh reshapes live.
## Each stroke is one undo action. Resolves the Map from the edited scene like the
## Terrain Snap plugin. Editing is disabled unless the brush toggle is on, so normal
## selection/navigation is unaffected when you're not painting.

const _RING_SEGMENTS: int = 48

## Height bounds + quantization for the sculpt modes: every corner height edit is clamped
## to [MIN_HEIGHT, MAX_HEIGHT] and snapped to a multiple of HEIGHT_STEP.
const MIN_HEIGHT: float = 0.0
const MAX_HEIGHT: float = 5.0
const HEIGHT_STEP: float = 0.5

## Brush modes: PAINT edits the per-cell tile-type layer; SET flattens the per-corner
## heights layer under the brush to a chosen target height.
enum Mode { PAINT, SET }

## Brush footprint: CIRCLE covers a disc of radius r; SQUARE covers the full (2r+1)-wide
## axis-aligned block. Orthogonal to Mode — applies to both Paint and Set.
enum Shape { CIRCLE, SQUARE }

## Stroke shape: FREE smears the footprint along wherever the cursor drags (accumulating);
## LINE rubber-bands a straight line — press sets the anchor, dragging re-interpolates the
## line to the cursor live (re-applied from the pre-stroke state each move), release commits.
## Orthogonal to Mode — a LINE stroke works for both Paint and Set.
enum Stroke { FREE, LINE }

#region Toolbar
var _toggle: Button
var _mode_option: OptionButton
var _shape_option: OptionButton
var _stroke_option: OptionButton
var _tile_option: OptionButton
var _radius_spin: SpinBox
var _set_height_spin: SpinBox
var _toolbar: HBoxContainer
#endregion

#region State
var _active: bool = false
var _painting: bool = false
var _last_cell: Vector2i = Vector2i(-9999, -9999)
var _line_anchor: Vector2i = Vector2i.ZERO  # first cell of a LINE stroke (set on press)
var _stroke_heights: bool = false  # which layer this stroke edits (heights vs tile types)
var _stroke_before_types: PackedByteArray = PackedByteArray()
var _stroke_before_heights: PackedFloat32Array = PackedFloat32Array()
var _preview: MeshInstance3D
var _preview_map: Map = null
var _bounds_preview: MeshInstance3D  # outline of the screen-aligned play bounds
#endregion

## Subdivisions per play-bounds edge, so the outline follows terrain height along its length.
const _BOUNDS_EDGE_SEGMENTS: int = 24


#region Lifecycle
func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()

	_toggle = Button.new()
	_toggle.toggle_mode = true
	_toggle.text = "Terrain Brush"
	_toggle.tooltip_text = "Paint terrain tile types by click-dragging over a Map's terrain."
	_toggle.toggled.connect(_on_toggled)
	_toolbar.add_child(_toggle)

	_mode_option = OptionButton.new()
	_mode_option.tooltip_text = "Brush mode: Paint tile types, or Set corner heights."
	_mode_option.add_item("Paint", Mode.PAINT)
	_mode_option.add_item("Set", Mode.SET)
	_mode_option.item_selected.connect(_on_mode_changed)
	_toolbar.add_child(_mode_option)

	_shape_option = OptionButton.new()
	_shape_option.tooltip_text = "Brush footprint shape."
	_shape_option.add_item("Circle", Shape.CIRCLE)
	_shape_option.add_item("Square", Shape.SQUARE)
	_toolbar.add_child(_shape_option)

	_stroke_option = OptionButton.new()
	_stroke_option.tooltip_text = "Stroke: Free drags freely; Line rubber-bands a straight line (press = anchor, drag to aim, release to commit)."
	_stroke_option.add_item("Free", Stroke.FREE)
	_stroke_option.add_item("Line", Stroke.LINE)
	_toolbar.add_child(_stroke_option)

	_tile_option = OptionButton.new()
	_tile_option.tooltip_text = "Tile type to paint (Paint mode)."
	_toolbar.add_child(_tile_option)

	var radius_label := Label.new()
	radius_label.text = "  r "
	_toolbar.add_child(radius_label)

	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 0
	_radius_spin.max_value = 40
	_radius_spin.value = 3
	_radius_spin.tooltip_text = "Brush radius in cells (0 = single cell)."
	_toolbar.add_child(_radius_spin)

	var set_label := Label.new()
	set_label.text = "  = "
	_toolbar.add_child(set_label)

	_set_height_spin = SpinBox.new()
	_set_height_spin.min_value = MIN_HEIGHT
	_set_height_spin.max_value = MAX_HEIGHT
	_set_height_spin.step = HEIGHT_STEP
	_set_height_spin.value = 0.0
	_set_height_spin.editable = false  # only relevant in Set mode
	_set_height_spin.tooltip_text = "Target height for Set mode (0..5, 0.5 steps)."
	_toolbar.add_child(_set_height_spin)

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.visible = false  # shown only while a Map is in the edited scene


func _exit_tree() -> void:
	_clear_preview()
	_clear_bounds_preview()
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
		_toolbar = null


## Keep viewport-input forwarding + the toolbar tied to the presence of a Map, regardless
## of what is selected (painting shouldn't require selecting the Map first).
func _handles(_object: Object) -> bool:
	var has_map: bool = _find_map() != null
	if _toolbar != null:
		_toolbar.visible = has_map
	return has_map
#endregion


#region Toolbar handlers
func _on_toggled(pressed: bool) -> void:
	_active = pressed
	if _active:
		_refresh_tile_options()
		_update_bounds_overlay(_find_map())  # show bounds immediately, before the first motion
	else:
		_painting = false
		_clear_preview()
		_clear_bounds_preview()


## Populate the tile-type dropdown from the edited Map's catalog (names + catalog index
## as the item id). No-op when there is no catalog yet.
func _refresh_tile_options() -> void:
	var map := _find_map()
	if map == null or map.terrain_data == null or map.terrain_data.catalog == null:
		return
	var catalog: TerrainTileCatalog = map.terrain_data.catalog
	var prev_id: int = _tile_option.get_selected_id() if _tile_option.item_count > 0 else 0
	_tile_option.clear()
	for i: int in catalog.count():
		var t: TileType = catalog.types[i]
		_tile_option.add_item(t.name if t != null else "?", i)
	# Restore the previous selection when still valid.
	for idx: int in _tile_option.item_count:
		if _tile_option.get_item_id(idx) == prev_id:
			_tile_option.select(idx)
			break


func _selected_type() -> int:
	if _tile_option == null or _tile_option.item_count == 0:
		return 0
	return _tile_option.get_selected_id()


func _current_mode() -> int:
	if _mode_option == null or _mode_option.item_count == 0:
		return Mode.PAINT
	return _mode_option.get_selected_id()


func _current_shape() -> int:
	if _shape_option == null or _shape_option.item_count == 0:
		return Shape.CIRCLE
	return _shape_option.get_selected_id()


func _current_stroke() -> int:
	if _stroke_option == null or _stroke_option.item_count == 0:
		return Stroke.FREE
	return _stroke_option.get_selected_id()


## Enable only the control that applies to the chosen mode (tile dropdown for Paint,
## strength for the height modes) so the UI reads clearly.
func _on_mode_changed(_index: int) -> void:
	var mode: int = _current_mode()
	if _tile_option != null:
		_tile_option.disabled = mode != Mode.PAINT
	if _set_height_spin != null:
		_set_height_spin.editable = mode == Mode.SET
#endregion


#region Viewport input
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var map := _find_map()
	if map == null or map.terrain_data == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		_update_bounds_overlay(map)  # refresh here too, so inspector edits to the bounds show live
		var cell := _cell_under_cursor(camera, event.position, map)
		_update_preview(map, cell)
		if _painting and cell.x != -1:
			_apply(map, cell)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _cell_under_cursor(camera, event.position, map)
			if cell.x == -1:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_begin_stroke(map)
			_line_anchor = cell  # LINE strokes interpolate from here to the cursor
			_apply(map, cell)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _painting:
			_end_stroke(map)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS
#endregion


#region Painting
func _begin_stroke(map: Map) -> void:
	_painting = true
	_last_cell = Vector2i(-9999, -9999)
	_stroke_heights = _current_mode() != Mode.PAINT
	if _stroke_heights:
		_stroke_before_heights = map.terrain_data.heights.duplicate()
	else:
		_stroke_before_types = map.terrain_data.tile_types.duplicate()


## Apply the brush for the current cursor cell. FREE smears the footprint at `center`; LINE
## re-applies the whole anchor→cursor line from the pre-stroke snapshot (so the line follows
## the cursor and never accumulates). Dispatches by Mode (Paint vs Set) underneath.
func _apply(map: Map, center: Vector2i) -> void:
	if _current_stroke() == Stroke.LINE:
		_apply_line(map, _line_anchor, center)
	elif _current_mode() == Mode.PAINT:
		_paint_tiles(map, center)
	else:
		_sculpt_height(map, center)


## Re-apply a LINE stroke: reset the edited layer to the pre-stroke snapshot, then stamp the
## brush footprint at every cell on the Bresenham line from `a` to `b`, and rebuild once. Skips
## when the cursor cell is unchanged (the line is identical), so it's one rebuild per cell moved.
func _apply_line(map: Map, a: Vector2i, b: Vector2i) -> void:
	if b == _last_cell:
		return
	_last_cell = b
	var td: TerrainData = map.terrain_data
	var cells: Array[Vector2i] = _line_cells(a, b)
	var circle: bool = _current_shape() == Shape.CIRCLE

	if _current_mode() == Mode.PAINT:
		var gw: int = td.grid_width()
		var gd: int = td.grid_depth()
		var types: PackedByteArray = _stroke_before_types.duplicate()
		if types.size() != gw * gd:
			types = PackedByteArray()
			types.resize(gw * gd)
		var type: int = _selected_type()
		var r: int = int(_radius_spin.value)
		for c: Vector2i in cells:
			_stamp_tiles(td, types, c, type, r, circle)
		td.tile_types = types
		map.rebuild_terrain_mesh()
	else:
		var w: int = td.map_width()
		var d: int = td.map_depth()
		var heights: PackedFloat32Array = _stroke_before_heights.duplicate()
		if heights.size() != w * d:
			return
		var target: float = _snap_height(_set_height_spin.value)
		var r: float = maxf(0.5, float(_radius_spin.value))
		for c: Vector2i in cells:
			_stamp_heights(td, heights, c, target, r, circle)
		td.heights = heights
		map.apply_terrain_heights_live()


## Cells on the integer grid line from `a` to `b` (Bresenham). Stamping the brush footprint at
## each gives a straight thick stroke; a zero-length line is just the anchor cell.
static func _line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var dx: int = absi(b.x - x0)
	var dy: int = -absi(b.y - y0)
	var sx: int = 1 if x0 < b.x else -1
	var sy: int = 1 if y0 < b.y else -1
	var err: int = dx + dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == b.x and y0 == b.y:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return cells


## Paint every CELL within the brush footprint (circle disc or square block, per the shape
## selector) to the selected type, then rebuild just the mesh (holes update live). Skips work
## when the centre cell is unchanged since the last motion, so mesh rebuilds are bounded to
## one per cell crossed.
func _paint_tiles(map: Map, center: Vector2i) -> void:
	if center == _last_cell:
		return
	_last_cell = center

	var td: TerrainData = map.terrain_data
	var gw: int = td.grid_width()
	var gd: int = td.grid_depth()
	var types: PackedByteArray = td.tile_types
	if types.size() != gw * gd:
		types = PackedByteArray()
		types.resize(gw * gd)  # materialize an all-Open array if it was empty

	if _stamp_tiles(td, types, center, _selected_type(), int(_radius_spin.value), _current_shape() == Shape.CIRCLE):
		td.tile_types = types
		map.rebuild_terrain_mesh()


## Stamp the brush footprint (circle disc or square block of radius r) at `center` into `types`,
## painting each in-bounds, in-play cell to `type`. Mutates `types`; returns whether anything
## changed. No rebuild — the caller decides when to push to the mesh.
static func _stamp_tiles(td: TerrainData, types: PackedByteArray, center: Vector2i, type: int, r: int, circle: bool) -> bool:
	var gw: int = td.grid_width()
	var gd: int = td.grid_depth()
	var r2: int = r * r
	var changed: bool = false
	for dz: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if circle and dx * dx + dz * dz > r2:
				continue
			var x: int = center.x + dx
			var z: int = center.y + dz
			if x < 0 or x >= gw or z < 0 or z >= gd:
				continue
			# Don't paint cells outside the screen-aligned play bounds — they're masked to
			# holes, so writing their tile type is dead data (and muddies the authored region).
			if not td.is_cell_in_play(Vector2i(x, z)):
				continue
			var idx: int = z * gw + x
			if types[idx] != type:
				types[idx] = type
				changed = true
	return changed


## Set the per-CORNER heights within the brush footprint (circle disc or square block, per
## the shape selector) to the target height (clamped to [MIN_HEIGHT, MAX_HEIGHT] and snapped
## to HEIGHT_STEP), centred on the picked cell's centre, then push to the live mesh. A hard
## set (no falloff), so it stamps flat plateaus/pits.
func _sculpt_height(map: Map, center: Vector2i) -> void:
	var td: TerrainData = map.terrain_data
	var w: int = td.map_width()
	var d: int = td.map_depth()
	var heights: PackedFloat32Array = td.heights
	if heights.size() != w * d:
		return

	_stamp_heights(td, heights, center, _snap_height(_set_height_spin.value),
			maxf(0.5, float(_radius_spin.value)), _current_shape() == Shape.CIRCLE)
	td.heights = heights
	map.apply_terrain_heights_live()


## Stamp the brush footprint at `center` into the per-corner `heights` array, hard-setting each
## covered corner to `target`. Mutates `heights`; no rebuild (the caller pushes it live).
static func _stamp_heights(td: TerrainData, heights: PackedFloat32Array, center: Vector2i, target: float, r: float, circle: bool) -> void:
	var w: int = td.map_width()
	var d: int = td.map_depth()
	# Corner-space centre = the picked cell's centre (cells sit between corners).
	var ccx: float = center.x + 0.5
	var ccz: float = center.y + 0.5
	var x0: int = maxi(0, int(floor(ccx - r)))
	var x1: int = mini(w - 1, int(ceil(ccx + r)))
	var z0: int = maxi(0, int(floor(ccz - r)))
	var z1: int = mini(d - 1, int(ceil(ccz + r)))
	for cz: int in range(z0, z1 + 1):
		for cx: int in range(x0, x1 + 1):
			if circle and sqrt(pow(cx - ccx, 2.0) + pow(cz - ccz, 2.0)) > r:
				continue
			heights[cz * w + cx] = target


## Clamp a height into [MIN_HEIGHT, MAX_HEIGHT] and snap it to the nearest HEIGHT_STEP.
func _snap_height(h: float) -> float:
	return clampf(snappedf(h, HEIGHT_STEP), MIN_HEIGHT, MAX_HEIGHT)


## Commit the stroke: full visual refresh + one undo action swapping the edited layer
## (tile types or heights) between the pre-stroke snapshot and the result. Both do/undo ops
## are METHOD calls on `map` (a scene node), with `map` as the action's custom_context, so
## the whole action lives in one undo history — avoids the "history mismatch" error you get
## when an action mixes the terrain_data Resource and the Map Node.
func _end_stroke(map: Map) -> void:
	_painting = false
	var td: TerrainData = map.terrain_data
	var ur := get_undo_redo()
	if _stroke_heights:
		map.rebuild_terrain_visuals(true)
		var after: PackedFloat32Array = td.heights.duplicate()
		if after == _stroke_before_heights:
			return
		ur.create_action("Set terrain height", UndoRedo.MERGE_DISABLE, map)
		ur.add_do_method(map, "set_terrain_heights", after)
		ur.add_undo_method(map, "set_terrain_heights", _stroke_before_heights)
		ur.commit_action(false)  # already applied live — register only, don't re-execute
	else:
		map.rebuild_terrain_visuals(false)
		var after: PackedByteArray = td.tile_types.duplicate()
		if after == _stroke_before_types:
			return
		ur.create_action("Paint terrain tiles", UndoRedo.MERGE_DISABLE, map)
		ur.add_do_method(map, "set_terrain_tile_types", after)
		ur.add_undo_method(map, "set_terrain_tile_types", _stroke_before_types)
		ur.commit_action(false)
#endregion


#region Picking + preview
## The terrain cell under the cursor, or Vector2i(-1, -1) when the ray misses the terrain
## or lands off-map. Marches the editor camera ray against the terrain surface (works on
## sloped terrain, unlike a flat-plane intersection).
func _cell_under_cursor(camera: Camera3D, mouse_pos: Vector2, map: Map) -> Vector2i:
	if camera == null:
		return Vector2i(-1, -1)
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var step: float = 0.5
	var max_t: float = 5000.0
	var t: float = 0.0
	var prev: Vector3 = origin
	var prev_diff: float = origin.y - map.terrain_height_at(Vector2(origin.x, origin.z))
	while t < max_t:
		t += step
		var p: Vector3 = origin + dir * t
		var diff: float = p.y - map.terrain_height_at(Vector2(p.x, p.z))
		if prev_diff > 0.0 and diff <= 0.0:
			var f: float = prev_diff / (prev_diff - diff)
			var hit: Vector3 = prev.lerp(p, f)
			var cell: Vector2i = map.world_to_grid(Vector2(hit.x, hit.z))
			var td: TerrainData = map.terrain_data
			if cell.x >= 0 and cell.x < td.grid_width() and cell.y >= 0 and cell.y < td.grid_depth():
				return cell
			return Vector2i(-1, -1)
		prev = p
		prev_diff = diff
	return Vector2i(-1, -1)


## Draw a flat brush-radius ring centred on `center`'s world position (hidden when the
## cursor is off-terrain). Re-parented under the active Map as an internal child so it is
## neither saved nor shown in the scene dock.
func _update_preview(map: Map, center: Vector2i) -> void:
	if not _active or center.x == -1:
		if _preview != null:
			_preview.visible = false
		return
	_ensure_preview(map)
	_preview.visible = true

	var world: Vector3 = map.grid_to_world(center)
	if world == Vector3.INF:
		_preview.visible = false
		return
	var r: float = maxf(0.5, float(_radius_spin.value) + 0.5) * Map.CELL_SIZE

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	if _current_shape() == Shape.SQUARE:
		# Axis-aligned (grid-space) square outline; reads as a diamond under the yawed camera.
		for corner: Vector2 in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r), Vector2(-r, -r)]:
			im.surface_add_vertex(Vector3(corner.x, 0.05, corner.y))
	else:
		for i: int in _RING_SEGMENTS + 1:
			var a: float = TAU * float(i) / float(_RING_SEGMENTS)
			im.surface_add_vertex(Vector3(cos(a) * r, 0.05, sin(a) * r))
	im.surface_end()
	_preview.mesh = im
	_preview.global_position = Vector3(world.x, world.y, world.z)


func _ensure_preview(map: Map) -> void:
	if _preview != null and _preview_map == map and is_instance_valid(_preview):
		return
	_clear_preview()
	_preview = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.no_depth_test = true
	_preview.material_override = mat
	map.add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	_preview_map = map


func _clear_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_preview_map = null


## Draw the screen-aligned play-bounds outline (the play diamond) as a terrain-hugging loop,
## so the author can see the region the corners are chopped to. Hidden when the brush is off,
## there is no map/terrain_data, or play bounds are disabled. Cheap enough to rebuild live.
func _update_bounds_overlay(map: Map) -> void:
	if not _active or map == null or map.terrain_data == null or not map.terrain_data.play_bounds_enabled:
		_clear_bounds_preview()
		return
	var corners: PackedVector2Array = map.terrain_data.play_bounds_grid_corners()
	if corners.size() != 4:
		_clear_bounds_preview()
		return

	_ensure_bounds_preview(map)
	_bounds_preview.visible = true

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i: int in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		# Subdivide each edge so its Y tracks the terrain surface underneath.
		for step: int in _BOUNDS_EDGE_SEGMENTS:
			var p: Vector2 = a.lerp(b, float(step) / float(_BOUNDS_EDGE_SEGMENTS))
			im.surface_add_vertex(_bounds_vertex(map, p.x, p.y))
	im.surface_add_vertex(_bounds_vertex(map, corners[0].x, corners[0].y))  # close the loop
	im.surface_end()
	_bounds_preview.mesh = im


## World position of a continuous (x, z) cell-space point, lifted just above the terrain
## surface. Mirrors Map.grid_to_world's centring (using the derived height_map extent) but for
## fractional coords, so the outline sits on the ground rather than at a flat Y.
func _bounds_vertex(map: Map, fx: float, fz: float) -> Vector3:
	var hw: float = (map.height_map.map_width - 1) * 0.5
	var hd: float = (map.height_map.map_depth - 1) * 0.5
	var world: Vector3 = map.global_transform * Vector3(fx + 0.5 - hw, 0.0, fz + 0.5 - hd)
	world.y = map.terrain_height_at(Vector2(world.x, world.z)) + 0.06
	return world


func _ensure_bounds_preview(map: Map) -> void:
	if _bounds_preview != null and is_instance_valid(_bounds_preview) and _bounds_preview.get_parent() == map:
		return
	_clear_bounds_preview()
	_bounds_preview = MeshInstance3D.new()
	_bounds_preview.top_level = true  # vertices are already world-space
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.85, 1.0)  # cyan — distinct from the yellow brush ring
	mat.no_depth_test = true
	_bounds_preview.material_override = mat
	map.add_child(_bounds_preview, false, Node.INTERNAL_MODE_BACK)


func _clear_bounds_preview() -> void:
	if _bounds_preview != null and is_instance_valid(_bounds_preview):
		_bounds_preview.queue_free()
	_bounds_preview = null
#endregion


#region Map resolution (same strategy as the Terrain Snap plugin)
func _find_map() -> Map:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if root is Map:
		return root as Map
	var named := root.find_child("Map", true, false)
	if named is Map:
		return named as Map
	return _first_map_descendant(root)


func _first_map_descendant(node: Node) -> Map:
	for child: Node in node.get_children():
		if child is Map:
			return child as Map
		var found := _first_map_descendant(child)
		if found != null:
			return found
	return null
#endregion
