@tool
extends EditorPlugin

## Paint terrain TILE TYPES directly in the 3D viewport (Stage 3 of gdd/systems/terrain-and-navigation/tile-types.md).
##
## Toggle "Terrain Brush" in the spatial-editor toolbar, pick a Mode, a footprint Shape
## (Circle/Square), a radius, and (per mode) a tile type or a target height, then
## left-click-drag over a Map's terrain:
##   * Paint  — writes the chosen ground material into Map.terrain_data.tile_types (per cell);
##              the mesh colours update live. A material never changes passability.
##   * Set     — flatten the per-corner heights under the brush to the target-height value
##              (clamped to [MIN_HEIGHT, MAX_HEIGHT]); the terrain mesh reshapes live.
##   * Region  — drag out a rectangle, then Copy (C) or Move (X) it and click to stamp it
##              somewhere else. See "Region mode" below.
##   * Water   — hover the terrain to preview the body of water a click would create there,
##              and click to create it. See "Water mode" below.
## Each stroke is one undo action. Resolves the Map from the edited scene like the
## Terrain Snap plugin. Editing is disabled unless the brush toggle is on, so normal
## selection/navigation is unaffected when you're not painting.
##
## Toggling the brush on auto-selects the scene's Map (viewport input is only forwarded to us
## while a node we _handle is the edited object). Viewport hotkeys (while the brush is active):
##   M            cycle Mode (Paint / Set / Region)
##   B            cycle brush Shape (Circle / Square)
##   L            cycle Stroke (Free / Line)
##   T / Shift+T  cycle the Paint tile type forward / backward
##   [ / ]        decrement / increment the brush radius
##   - / =        decrement / increment the Set target height
##   C / X        (Region) arm a Copy / a Move of the selected rectangle
##   Escape       (Region) disarm, keeping the selection
##
## Region mode (see docs/terrain-translate.md):
##   Drag a rectangle over the terrain to select it, then press C (copy) or X (move) to arm
##   it and left-click to stamp it, centred on the cursor. Both heights and tile types travel
##   unless a layer checkbox is unticked, and Flip H / Flip V mirror the region as it lands.
##
##   The clipboard is the SOURCE RECTANGLE, not an extracted buffer — a move is therefore
##   non-destructive until it is actually placed (Escape leaves the terrain untouched), and a
##   copy re-reads live data so it can be stamped repeatedly. Cross-map stamps would need a
##   real extracted buffer; that is deliberately not built.
##
##   Pasting re-seats every entity onto the new surface and DELETES the ones the new ground
##   cannot support — undoing the paste brings them back (Map.revert_terrain_region_paste).
##
## Water mode (see gdd/systems/terrain-and-navigation/water-bodies.md):
##   The water LEVEL is the height of the point under the cursor, and the body is everything
##   the terrain lets that level reach — so you pick a level by pointing at it, and raising
##   the pond means hovering further up its bank. The preview is the actual surface mesh the
##   body would draw, so what you see before clicking is what you get; the toolbar says how
##   many cells it covers, how much of that is too deep to walk, and whether the water runs
##   out to the edge of the play area (which holds it, like a wall).
##
##   A click makes a WaterBody node under the Map. It is authored by three values — a seed
##   cell, a level and an energy charge — and everything else about it is derived at load,
##   so re-sculpting the terrain under a body re-floods it rather than stranding it.

const _RING_SEGMENTS: int = 48

## Height bounds for the sculpt modes: every corner height edit is clamped to
## [MIN_HEIGHT, MAX_HEIGHT]. Heights are NOT quantized — see HEIGHT_STEP.
const MIN_HEIGHT: float = 0.0
const MAX_HEIGHT: float = 32.0
## SpinBox granularity only. Heights are CONTINUOUS — the old snapping to this step was a relic
## of the era when terrain was a heightmap of even-length cells, and it is gone from the apply
## path: a mesh-baked field has no reason to quantize, and a feathered brush needs the values
## in between to make a slope at all.
const HEIGHT_STEP: float = 0.05

## Brush modes: PAINT edits the per-cell tile-type layer; SET flattens the per-corner
## heights layer under the brush to a chosen target height; REGION selects a rectangle and
## stamps it elsewhere (no brush footprint involved — Shape/Stroke/radius don't apply).
enum Mode { PAINT, SET, RAMP, REGION, WATER }

## What an armed region stamp does to the place it came from: COPY leaves it, MOVE clears it
## as part of the same paste. Nothing is destroyed until the paste actually lands, so
## disarming a MOVE costs nothing.
enum Clip { NONE, COPY, MOVE }

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
var _feather_spin: SpinBox
var _toolbar: HBoxContainer
## Region-mode controls, hidden in the brush modes (see _on_mode_changed).
var _region_controls: Array[Control] = []
var _copy_button: Button
var _move_button: Button
var _flip_x_check: CheckBox
var _flip_z_check: CheckBox
var _layer_heights_check: CheckBox
var _layer_tiles_check: CheckBox
## Water-mode controls, hidden in every other mode (see _on_mode_changed).
var _water_controls: Array[Control] = []
var _water_energy_spin: SpinBox
var _water_status: Label
#endregion

#region Region state
## The selected rectangle in CELL space; zero-sized means nothing is selected.
var _region_rect: Rect2i = Rect2i()
var _region_dragging: bool = false
var _region_anchor: Vector2i = Vector2i.ZERO
## What the armed stamp is (NONE = not armed) and the rectangle it reads from. The clipboard
## is the SOURCE RECT rather than extracted data — see the Region mode notes up top.
var _clip_mode: Clip = Clip.NONE
var _clip_rect: Rect2i = Rect2i()
var _region_preview: MeshInstance3D  # selection rectangle + armed paste destination
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
var _preview_cell: Vector2i = Vector2i(-1, -1)  # last hovered cell, so hotkeys can refresh the ring
var _bounds_preview: MeshInstance3D  # outline of the screen-aligned play bounds
#endregion

#region Water state
## The body of water the cursor is currently proposing, and the mesh showing it. Held so a
## click can commit exactly what was previewed rather than re-deriving it from a cursor that
## may have moved a pixel in between.
var _water_basin: WaterBasin = null
var _water_level: float = 0.0
var _water_seed: Vector2i = Vector2i(-1, -1)
var _water_preview: MeshInstance3D
## How far terrain_data has drifted from terrain_source_mesh, measured when Water mode is
## entered. > 0 means every flood is computed against ground that is not what the viewport
## draws, so placement is REFUSED until it is re-baked. -1 = nothing to compare.
var _water_bake_residual: float = 0.0
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
	_mode_option.tooltip_text = "Brush mode: Paint tile types, Set corner heights, Ramp between " \
		+ "two levels, Region stamping, or Water bodies. (M to cycle)"
	_mode_option.add_item("Paint", Mode.PAINT)
	_mode_option.add_item("Set", Mode.SET)
	_mode_option.add_item("Ramp", Mode.RAMP)
	_mode_option.add_item("Region", Mode.REGION)
	_mode_option.add_item("Water", Mode.WATER)
	_mode_option.item_selected.connect(_on_mode_changed)
	_toolbar.add_child(_mode_option)

	_shape_option = OptionButton.new()
	_shape_option.tooltip_text = "Brush footprint shape. (B to cycle)"
	_shape_option.add_item("Circle", Shape.CIRCLE)
	_shape_option.add_item("Square", Shape.SQUARE)
	_toolbar.add_child(_shape_option)

	_stroke_option = OptionButton.new()
	_stroke_option.tooltip_text = "Stroke: Free drags freely; Line rubber-bands a straight line (press = anchor, drag to aim, release to commit). (L to cycle)"
	_stroke_option.add_item("Free", Stroke.FREE)
	_stroke_option.add_item("Line", Stroke.LINE)
	_toolbar.add_child(_stroke_option)

	_tile_option = OptionButton.new()
	_tile_option.tooltip_text = "Tile type to paint (Paint mode). (T / Shift+T to cycle)"
	_toolbar.add_child(_tile_option)

	var radius_label := Label.new()
	radius_label.text = "  r "
	_toolbar.add_child(radius_label)

	_radius_spin = SpinBox.new()
	_radius_spin.min_value = 0
	_radius_spin.max_value = 40
	_radius_spin.value = 3
	_radius_spin.tooltip_text = "Brush radius in cells (0 = single cell). ([ / ] to adjust)"
	_toolbar.add_child(_radius_spin)

	var feather_label := Label.new()
	feather_label.text = "  ~ "
	_toolbar.add_child(feather_label)

	_feather_spin = SpinBox.new()
	_feather_spin.min_value = 0
	_feather_spin.max_value = 40
	_feather_spin.step = 0.5
	_feather_spin.value = 0
	_feather_spin.tooltip_text = "Feather width in cells beyond the radius: the ring over which " \
		+ "the set height falls off to the existing terrain. 0 = hard edge (plateau walls)."
	_toolbar.add_child(_feather_spin)

	var set_label := Label.new()
	set_label.text = "  = "
	_toolbar.add_child(set_label)

	_set_height_spin = SpinBox.new()
	_set_height_spin.min_value = MIN_HEIGHT
	_set_height_spin.max_value = MAX_HEIGHT
	_set_height_spin.step = HEIGHT_STEP
	_set_height_spin.value = 0.0
	_set_height_spin.editable = false  # only relevant in Set mode
	_set_height_spin.tooltip_text = "Target height for Set mode, in world units. (- / = to adjust)"
	_toolbar.add_child(_set_height_spin)

	_build_region_controls()
	_build_water_controls()

	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.visible = false  # shown only while a Map is in the edited scene


## Build the Region-mode strip of the toolbar. Collected into _region_controls so
## _on_mode_changed can hide the whole set at once — these are meaningless in the brush modes
## and would just crowd an already-long toolbar.
func _build_region_controls() -> void:
	var separator := VSeparator.new()
	_toolbar.add_child(separator)
	_region_controls.append(separator)

	_copy_button = Button.new()
	_copy_button.text = "Copy"
	_copy_button.tooltip_text = "Arm a COPY of the selected rectangle; click the terrain to stamp it. (C)"
	_copy_button.pressed.connect(func() -> void: _arm_clip(Clip.COPY))
	_toolbar.add_child(_copy_button)
	_region_controls.append(_copy_button)

	_move_button = Button.new()
	_move_button.text = "Move"
	_move_button.tooltip_text = "Arm a MOVE of the selected rectangle — the source is cleared as part of the paste, so nothing is lost until you place it. (X)"
	_move_button.pressed.connect(func() -> void: _arm_clip(Clip.MOVE))
	_toolbar.add_child(_move_button)
	_region_controls.append(_move_button)

	_flip_x_check = CheckBox.new()
	_flip_x_check.text = "Flip X"
	_flip_x_check.tooltip_text = "Mirror the region across X as it lands."
	_toolbar.add_child(_flip_x_check)
	_region_controls.append(_flip_x_check)

	_flip_z_check = CheckBox.new()
	_flip_z_check.text = "Flip Z"
	_flip_z_check.tooltip_text = "Mirror the region across Z as it lands."
	_toolbar.add_child(_flip_z_check)
	_region_controls.append(_flip_z_check)

	_layer_heights_check = CheckBox.new()
	_layer_heights_check.text = "H"
	_layer_heights_check.button_pressed = true
	_layer_heights_check.tooltip_text = "Include the HEIGHTS layer in the stamp."
	_toolbar.add_child(_layer_heights_check)
	_region_controls.append(_layer_heights_check)

	_layer_tiles_check = CheckBox.new()
	_layer_tiles_check.text = "T"
	_layer_tiles_check.button_pressed = true
	_layer_tiles_check.tooltip_text = "Include the TILE TYPES layer in the stamp."
	_toolbar.add_child(_layer_tiles_check)
	_region_controls.append(_layer_tiles_check)

	for control: Control in _region_controls:
		control.visible = false  # Paint is the default mode


## Build the Water-mode strip: the charge a new body is created with, and a live readout of
## what the cursor is currently proposing. The readout is the mode's whole feedback channel —
## the preview mesh says WHERE the water goes, and this says how big it is, how much of it is
## too deep to walk, and why a click would be refused.
func _build_water_controls() -> void:
	var separator := VSeparator.new()
	_toolbar.add_child(separator)
	_water_controls.append(separator)

	var energy_label := Label.new()
	energy_label.text = "  energy "
	_toolbar.add_child(energy_label)
	_water_controls.append(energy_label)

	_water_energy_spin = SpinBox.new()
	_water_energy_spin.min_value = 0
	_water_energy_spin.max_value = 1000000
	_water_energy_spin.step = 500
	_water_energy_spin.value = 0
	_water_energy_spin.tooltip_text = "Energy the new body of water is charged with. 0 is " \
		+ "plain water; a lithium pond is a body you charge — %d is the nominal figure." \
			% WaterBody.NOMINAL_ENERGY
	_toolbar.add_child(_water_energy_spin)
	_water_controls.append(_water_energy_spin)

	_water_status = Label.new()
	_water_status.text = ""
	_toolbar.add_child(_water_status)
	_water_controls.append(_water_status)

	for control: Control in _water_controls:
		control.visible = false  # Paint is the default mode


func _exit_tree() -> void:
	_clear_preview()
	_clear_bounds_preview()
	_clear_region_preview()
	_clear_water_preview()
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
		_select_map()  # viewport input only forwards while a node we _handle is edited
		_refresh_tile_options()
		_update_bounds_overlay(_find_map())  # show bounds immediately, before the first motion
	else:
		_painting = false
		_region_dragging = false
		_disarm_clip()
		_clear_preview()
		_clear_bounds_preview()
		_clear_region_preview()
		_clear_water_preview()


## Select the scene's Map so the editor forwards 3D viewport input (and our hotkeys) to us —
## _forward_3d_gui_input only fires while a node this plugin _handles is the edited object.
## There is only ever one Map in the scene, so grab the first one.
func _select_map() -> void:
	var map := _find_map()
	if map == null:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(map)
	EditorInterface.edit_node(map)


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
## strength for the height modes) so the UI reads clearly. Region and Water each swap the
## brush controls out for their own strip — footprint shape, stroke and radius mean nothing
## to either of them.
func _on_mode_changed(_index: int) -> void:
	var mode: int = _current_mode()
	var region: bool = mode == Mode.REGION
	var water: bool = mode == Mode.WATER
	# Region and Water both replace the brush footprint entirely rather than refining it: one
	# works on a rectangle, the other on whatever the terrain floods, and neither has anything
	# to say about a radius or a stroke.
	var brush: bool = not region and not water
	if _tile_option != null:
		_tile_option.disabled = mode != Mode.PAINT
	if _set_height_spin != null:
		_set_height_spin.editable = mode == Mode.SET
	for control: Control in _region_controls:
		control.visible = region
	for control: Control in _water_controls:
		control.visible = water
	# Ramp is inherently a drag from one level to the other, so the stroke selector and the
	# footprint shape have nothing to say about it — its cross-section is always a rectangle.
	if _shape_option != null:
		_shape_option.visible = brush and mode != Mode.RAMP
	if _stroke_option != null:
		_stroke_option.visible = brush and mode != Mode.RAMP
	if _radius_spin != null:
		_radius_spin.visible = brush
	if not region:
		# Leaving Region mode drops the armed stamp: the brush modes give no way to place or
		# cancel it, so a stamp left armed would silently fire on the next visit.
		_disarm_clip()
		_clear_region_preview()
	if not water:
		_clear_water_preview()
	else:
		_warn_if_terrain_data_is_stale(_find_map())
#endregion


#region Hotkeys
## Viewport hotkeys while the brush is active: toggle each setting (one key per setting) or
## nudge the numeric spinboxes. Consumes handled keys (via the STOP return in the caller) so
## they don't leak to editor shortcuts. Returns whether the key was handled.
func _handle_key(event: InputEventKey, map: Map) -> bool:
	match event.keycode:
		KEY_M:
			_cycle_mode(1)
		KEY_B:
			_cycle_option(_shape_option, 1)
		KEY_L:
			_cycle_option(_stroke_option, 1)
		KEY_T:
			_cycle_option(_tile_option, -1 if event.shift_pressed else 1)
		KEY_BRACKETRIGHT:
			_adjust_spin(_radius_spin, 1)
		KEY_BRACKETLEFT:
			_adjust_spin(_radius_spin, -1)
		KEY_EQUAL:
			_adjust_spin(_set_height_spin, 1)
		KEY_MINUS:
			_adjust_spin(_set_height_spin, -1)
		KEY_C:
			if _current_mode() != Mode.REGION:
				return false
			_arm_clip(Clip.COPY)
		KEY_X:
			if _current_mode() != Mode.REGION:
				return false
			_arm_clip(Clip.MOVE)
		KEY_ESCAPE:
			# Only claim Escape while something is actually armed, so it keeps its normal
			# editor meaning the rest of the time.
			if _current_mode() != Mode.REGION or _clip_mode == Clip.NONE:
				return false
			_disarm_clip()
			_update_region_preview(map)
		_:
			return false
	# Refresh the brush ring so shape/size changes show without needing to move the mouse.
	# Region and Water have no footprint ring — refreshing it there would pop a stray circle
	# onto the terrain until the next mouse move.
	var mode: int = _current_mode()
	if _preview_cell.x != -1 and mode != Mode.REGION and mode != Mode.WATER:
		_update_preview(map, _preview_cell)
	return true


## Cycle the Mode dropdown by `delta` and re-run the mode-changed side effects (enable/disable
## the tile + height controls), since OptionButton.select() doesn't emit item_selected.
func _cycle_mode(delta: int) -> void:
	if _mode_option == null or _mode_option.item_count == 0:
		return
	_mode_option.select(wrapi(_mode_option.selected + delta, 0, _mode_option.item_count))
	_on_mode_changed(_mode_option.selected)


## Cycle an OptionButton's selection by `delta`, wrapping around the item list.
func _cycle_option(option: OptionButton, delta: int) -> void:
	if option == null or option.item_count == 0:
		return
	option.select(wrapi(option.selected + delta, 0, option.item_count))


## Nudge a SpinBox by `steps` of its own step size, clamped to its range.
func _adjust_spin(spin: SpinBox, steps: int) -> void:
	if spin == null:
		return
	spin.value = clampf(spin.value + steps * spin.step, spin.min_value, spin.max_value)
#endregion


#region Viewport input
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _active:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	var map := _find_map()
	if map == null or map.terrain_data == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey:
		if event.pressed and not event.echo and _handle_key(event, map):
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if _current_mode() == Mode.REGION:
		return _forward_region_input(camera, event, map)

	if _current_mode() == Mode.WATER:
		return _forward_water_input(camera, event, map)

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
	if _current_mode() == Mode.RAMP:
		# A ramp is always anchor-to-cursor; the stroke selector doesn't apply to it.
		_apply_ramp(map, _line_anchor, center)
	elif _current_stroke() == Stroke.LINE:
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
		var target: float = _clamp_height(_set_height_spin.value)
		var r: float = maxf(0.5, float(_radius_spin.value))
		var feather: float = float(_feather_spin.value)
		for c: Vector2i in cells:
			_stamp_heights(td, heights, c, target, r, feather, circle)
		td.heights = heights
		map.apply_terrain_heights_live()


## Lay a RAMP from the press cell to the cursor cell: a straight, constant-width slope whose
## ends match the ground already there, so it grafts one level onto another without a step at
## either end.
##
## Endpoint heights are SAMPLED from the pre-stroke terrain rather than typed in. That is what
## makes the tool mean "connect these two levels" — drag from the low ground to the plateau top
## and the slope between them follows, exactly as World Builder's Ramp tool does. It also means
## re-dragging never accumulates: every re-apply starts from the same snapshot.
##
## `_radius_spin` is the ramp's HALF-WIDTH here and the feather softens its long sides; the
## ends are left hard, because at t=0 and t=1 the ramp is already at the terrain's own height
## and there is nothing to blend into.
func _apply_ramp(map: Map, a: Vector2i, b: Vector2i) -> void:
	if b == _last_cell:
		return
	_last_cell = b
	var td: TerrainData = map.terrain_data
	var heights: PackedFloat32Array = _stroke_before_heights.duplicate()
	if heights.size() != td.map_width() * td.map_depth():
		return
	_stamp_ramp(td, heights, a, b,
			maxf(0.5, float(_radius_spin.value)), float(_feather_spin.value))
	td.heights = heights
	map.apply_terrain_heights_live()


## Stamp the ramp into `heights` (which must start as the pre-stroke snapshot, since the side
## feather blends against it). Mutates `heights`; the caller pushes it live.
static func _stamp_ramp(td: TerrainData, heights: PackedFloat32Array, a: Vector2i, b: Vector2i, half_width: float, feather: float) -> void:
	var w: int = td.map_width()
	var d: int = td.map_depth()
	# Corner-space endpoints = the picked cells' centres, matching _stamp_heights.
	var pa := Vector2(a.x + 0.5, a.y + 0.5)
	var pb := Vector2(b.x + 0.5, b.y + 0.5)
	var axis: Vector2 = pb - pa
	var span: float = axis.length()
	if span < 0.001:
		return
	var dir: Vector2 = axis / span
	var ha: float = _cell_height(td, heights, a)
	var hb: float = _cell_height(td, heights, b)

	var outer: float = half_width + maxf(feather, 0.0)
	var x0: int = maxi(0, int(floor(minf(pa.x, pb.x) - outer)))
	var x1: int = mini(w - 1, int(ceil(maxf(pa.x, pb.x) + outer)))
	var z0: int = maxi(0, int(floor(minf(pa.y, pb.y) - outer)))
	var z1: int = mini(d - 1, int(ceil(maxf(pa.y, pb.y) + outer)))

	for cz: int in range(z0, z1 + 1):
		for cx: int in range(x0, x1 + 1):
			var rel := Vector2(cx, cz) - pa
			var along: float = rel.dot(dir)
			# Rectangle, not a capsule: rounded ends would splay the ramp sideways where it
			# meets each level instead of finishing square against it.
			if along < 0.0 or along > span:
				continue
			var perp: float = absf(rel.cross(dir))
			if perp > outer:
				continue
			var at: int = cz * w + cx
			var target: float = lerpf(ha, hb, along / span)
			if perp <= half_width or feather <= 0.0:
				heights[at] = target
			else:
				heights[at] = lerpf(target, heights[at],
						smoothstep(0.0, 1.0, (perp - half_width) / feather))


## Height of a CELL, averaged over its four corners — the ground level a ramp end should meet.
static func _cell_height(td: TerrainData, heights: PackedFloat32Array, cell: Vector2i) -> float:
	var w: int = td.map_width()
	var x: int = clampi(cell.x, 0, w - 2)
	var z: int = clampi(cell.y, 0, td.map_depth() - 2)
	return (heights[z * w + x] + heights[z * w + x + 1]
		+ heights[(z + 1) * w + x] + heights[(z + 1) * w + x + 1]) * 0.25


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

	_stamp_heights(td, heights, center, _clamp_height(_set_height_spin.value),
			maxf(0.5, float(_radius_spin.value)), float(_feather_spin.value),
			_current_shape() == Shape.CIRCLE)
	td.heights = heights
	map.apply_terrain_heights_live()


## Stamp the brush footprint at `center` into the per-corner `heights` array, hard-setting each
## covered corner to `target`. Mutates `heights`; no rebuild (the caller pushes it live).
static func _stamp_heights(td: TerrainData, heights: PackedFloat32Array, center: Vector2i, target: float, r: float, feather: float, circle: bool) -> void:
	var w: int = td.map_width()
	var d: int = td.map_depth()
	# Corner-space centre = the picked cell's centre (cells sit between corners).
	var ccx: float = center.x + 0.5
	var ccz: float = center.y + 0.5
	var outer: float = r + maxf(feather, 0.0)
	var x0: int = maxi(0, int(floor(ccx - outer)))
	var x1: int = mini(w - 1, int(ceil(ccx + outer)))
	var z0: int = maxi(0, int(floor(ccz - outer)))
	var z1: int = mini(d - 1, int(ceil(ccz + outer)))
	for cz: int in range(z0, z1 + 1):
		for cx: int in range(x0, x1 + 1):
			var dx: float = absf(cx - ccx)
			var dz: float = absf(cz - ccz)
			# Circle measures Euclidean, square measures Chebyshev, so the feather ring takes
			# the brush's own shape instead of always being round.
			var dist: float = sqrt(dx * dx + dz * dz) if circle else maxf(dx, dz)
			if dist > outer:
				continue
			var at: int = cz * w + cx
			if dist <= r or feather <= 0.0:
				heights[at] = target
			else:
				# Ease from the target out to whatever was already there, so a feathered stroke
				# blends into the surrounding ground rather than ending on a step.
				heights[at] = lerpf(target, heights[at], smoothstep(0.0, 1.0, (dist - r) / feather))


## Clamp a height into the authored range. No snapping — see HEIGHT_STEP.
func _clamp_height(h: float) -> float:
	return clampf(h, MIN_HEIGHT, MAX_HEIGHT)


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


#region Region select / stamp
## Viewport input for REGION mode. Two states: nothing armed (left-drag selects a rectangle)
## and armed (left-click stamps it, right-click or Escape cancels).
func _forward_region_input(camera: Camera3D, event: InputEvent, map: Map) -> int:
	if event is InputEventMouseMotion:
		_update_bounds_overlay(map)
		_preview_cell = _cell_under_cursor(camera, event.position, map)
		if _preview != null:
			_preview.visible = false  # the brush ring means nothing in this mode
		if _region_dragging and _preview_cell.x != -1:
			_region_rect = _rect_from_cells(_region_anchor, _preview_cell)
		_update_region_preview(map)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if _region_dragging else EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _clip_mode == Clip.NONE:
			return EditorPlugin.AFTER_GUI_INPUT_PASS  # leave the editor's own right-click alone
		_disarm_clip()
		_update_region_preview(map)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _cell_under_cursor(camera, event.position, map)
			if cell.x == -1:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			if _clip_mode != Clip.NONE:
				_commit_stamp(map, cell)
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			_region_dragging = true
			_region_anchor = cell
			_region_rect = _rect_from_cells(cell, cell)
			_update_region_preview(map)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _region_dragging:
			_region_dragging = false
			_update_region_preview(map)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Inclusive cell rectangle spanned by two corners, in either drag direction.
static func _rect_from_cells(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _has_selection() -> bool:
	return _region_rect.size.x > 0 and _region_rect.size.y > 0


## Arm a copy/move of the current selection. Nothing is written to the terrain here — the
## rectangle is only remembered, so disarming costs nothing even for a MOVE.
func _arm_clip(mode: Clip) -> void:
	if not _has_selection():
		push_warning("Terrain Brush: drag out a rectangle before arming a Copy or Move.")
		return
	_clip_mode = mode
	_clip_rect = _region_rect
	_update_region_preview(_find_map())


func _disarm_clip() -> void:
	_clip_mode = Clip.NONE
	_clip_rect = Rect2i()


## Top-left cell of a stamp centred on the hovered cell — a stamp reads better centred under
## the cursor than hung off its bottom-right.
func _stamp_origin(hovered: Vector2i) -> Vector2i:
	return hovered - Vector2i(_clip_rect.size.x / 2, _clip_rect.size.y / 2)


func _selected_layers() -> int:
	var layers: int = 0
	if _layer_heights_check == null or _layer_heights_check.button_pressed:
		layers |= TerrainData.LAYER_HEIGHTS
	if _layer_tiles_check == null or _layer_tiles_check.button_pressed:
		layers |= TerrainData.LAYER_TILE_TYPES
	return layers


func _selected_transform() -> TerrainData.RegionTransform:
	var fx: bool = _flip_x_check != null and _flip_x_check.button_pressed
	var fz: bool = _flip_z_check != null and _flip_z_check.button_pressed
	if fx and fz:
		return TerrainData.RegionTransform.FLIP_BOTH
	if fx:
		return TerrainData.RegionTransform.FLIP_X
	if fz:
		return TerrainData.RegionTransform.FLIP_Z
	return TerrainData.RegionTransform.NONE


## Place the armed region at `hovered` as ONE undo action covering both terrain layers and
## any entities the new ground can no longer support.
func _commit_stamp(map: Map, hovered: Vector2i) -> void:
	var td: TerrainData = map.terrain_data
	var layers: int = _selected_layers()
	if layers == 0:
		push_warning("Terrain Brush: both layer checkboxes are unticked — nothing to stamp.")
		return

	var dest_origin: Vector2i = _stamp_origin(hovered)
	var is_move: bool = _clip_mode == Clip.MOVE
	var before_heights: PackedFloat32Array = td.heights.duplicate()
	var before_types: PackedByteArray = td.tile_types.duplicate()

	var out: Dictionary = td.translate_region(
		_clip_rect, dest_origin, layers, _selected_transform(), is_move
	)
	var after_heights: PackedFloat32Array = out["heights"]
	var after_types: PackedByteArray = out["tile_types"]
	if after_heights == before_heights and after_types == before_types:
		return  # stamped onto terrain identical to the source — no action worth recording

	# Only entities standing on cells this stamp actually wrote need their support re-checked.
	var region_cells: Dictionary = _stamp_cells(dest_origin, is_move)

	# Apply live FIRST, then register the already-applied result — the same shape _end_stroke
	# uses, and what lets the entity cull run before the undo action is built.
	var culled: Array = map.apply_terrain_region_paste(after_heights, after_types, region_cells)

	var ur := get_undo_redo()
	ur.create_action("Stamp terrain region", UndoRedo.MERGE_DISABLE, map)
	# Registered before the entity references below so that on undo — which replays the undo
	# list in reverse — the terrain restore runs LAST, after the culled entities are back in
	# the tree, letting its re-seat pass drop them onto the restored surface.
	ur.add_do_method(map, "apply_terrain_region_paste", after_heights, after_types, region_cells)
	ur.add_undo_method(map, "revert_terrain_region_paste", before_heights, before_types, culled)
	for record: Dictionary in culled:
		var node: Node = record.get("node") as Node
		if node != null:
			# The cull ORPHANED these; without a reference held by the action they would be
			# leaked on redo and gone forever on undo.
			ur.add_undo_reference(node)
	ur.commit_action(false)  # already applied live — register only, don't re-execute

	if is_move:
		# The content now lives at the destination; follow it there so a second Move chains
		# naturally instead of re-reading the emptied source.
		var moved_size: Vector2i = _clip_rect.size
		_disarm_clip()
		_region_rect = Rect2i(dest_origin, moved_size)
	_update_region_preview(map)


## The cell set a stamp touches: its destination, plus the vacated source for a MOVE.
func _stamp_cells(dest_origin: Vector2i, include_source: bool) -> Dictionary:
	var cells: Dictionary = {}
	for j: int in _clip_rect.size.y:
		for i: int in _clip_rect.size.x:
			cells[dest_origin + Vector2i(i, j)] = true
			if include_source:
				cells[_clip_rect.position + Vector2i(i, j)] = true
	return cells
#endregion


#region Water mode
## Water floods against `terrain_data`, while the viewport draws `terrain_source_mesh`. If the
## two have drifted the tool floods ground the author cannot see — which is exactly how three
## ponds came to be authored into solid rock, invisible at runtime and holding no water at all.
##
## Checked ONCE on entering the mode: it is a whole re-bake, far too heavy per mouse move.
func _warn_if_terrain_data_is_stale(map: Map) -> void:
	_water_bake_residual = 0.0 if map == null else map.source_mesh_bake_residual()
	if _water_bake_residual <= 0.001:
		return
	push_warning("Terrain Brush (Water): " + _stale_bake_message()
		+ ". Flooding against stale heights puts water under ground you can see, so placement "
		+ "is refused until the terrain is re-baked.")
	_set_water_status(_stale_bake_message())


func _stale_bake_message() -> String:
	return "STALE TERRAIN: terrain_data is %.3f out from terrain_source_mesh — press Bake Terrain From Mesh" % _water_bake_residual


## Whether the bake is trustworthy enough to flood against at all.
func _bake_is_current() -> bool:
	return _water_bake_residual <= 0.001



## Viewport input for WATER mode. Motion re-derives the body the cursor is proposing; a left
## click commits it. There is no drag: a body of water is one click, and the level it gets is
## the height of the point clicked.
func _forward_water_input(camera: Camera3D, event: InputEvent, map: Map) -> int:
	if event is InputEventMouseMotion:
		_update_bounds_overlay(map)
		if _preview != null:
			_preview.visible = false  # the brush ring means nothing in this mode
		_update_water_preview(camera, event.position, map)
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_update_water_preview(camera, event.position, map)
		if not _water_proposal_is_placeable(map):
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_commit_water_body(map)
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Re-derive the proposed body from the cursor, draw it, and say what it is in the toolbar.
## The preview is built with the SAME mesh builder the finished body uses, so the shape shown
## before the click is the shape that lands — there is no second approximation to drift.
func _update_water_preview(camera: Camera3D, mouse_pos: Vector2, map: Map) -> void:
	var hit: Variant = _terrain_point_under_cursor(camera, mouse_pos, map)
	_water_basin = null
	if not (hit is Vector3):
		_water_seed = Vector2i(-1, -1)
		_set_water_preview_mesh(map, null)
		_set_water_status("off terrain")
		return

	var point: Vector3 = hit
	_water_level = point.y
	_water_seed = map.world_to_grid(Vector2(point.x, point.z))
	_water_basin = WaterBasin.fill(map.terrain_data, _water_seed, _water_level)
	_set_water_preview_mesh(
		map,
		WaterSurfaceMesh.build(_water_basin, map.terrain_data) if _bake_is_current() else null
	)
	_set_water_status(_water_proposal_summary(map))


## Whether a click here would actually create something: the basin has to hold water, and it
## must not overlap a body that already exists — two bodies claiming one cell is incoherent,
## and the map indexes cells to bodies one-to-one.
func _water_proposal_is_placeable(map: Map) -> bool:
	if not _bake_is_current():
		return false
	if _water_basin == null or not _water_basin.is_valid():
		return false
	for cell: Vector2i in _water_basin.covered_cells():
		if map.water_body_at(cell) != null:
			return false
	return true


## One line of feedback for the proposal under the cursor — the whole reason Water mode does
## not need a separate validity marker: an author reads the count and the refusal here.
func _water_proposal_summary(map: Map) -> String:
	# Said on EVERY motion, not once on entry: this is the state that silently produces ponds
	# which do not exist, and the author is looking at the terrain, not the Output panel.
	if not _bake_is_current():
		return _stale_bake_message()
	if _water_basin == null or not _water_basin.is_valid():
		return "no basin at this level"
	var covered: int = _water_basin.covered_cells().size()
	var deep: int = _water_basin.deep_cells().size()
	for cell: Vector2i in _water_basin.covered_cells():
		if map.water_body_at(cell) != null:
			return "overlaps an existing body (%d cells)" % covered
	var edge: String = ", runs to the play edge" if _water_basin.reaches_play_edge else ""
	# DEPTH, not just area. A pond shallower than the terrain's own step relief is drawn and
	# still cannot be seen from the game's oblique camera: the steps around it hide the flat
	# plane entirely. `pierced` is how many of its cells the terrain already breaks through, and
	# a high count is the warning that this body will read as invisible in game.
	var pierced: int = _water_basin.cells_pierced_by_terrain
	var warn: String = "  <- TOO SHALLOW TO SEE" if pierced * 2 >= covered else ""
	return "level %.2f — %d cells, %d deep, max %.2f deep, %d pierced%s%s" % [
		_water_level, covered, deep, _water_basin.max_depth, pierced, edge, warn]


func _set_water_status(text: String) -> void:
	if _water_status != null:
		_water_status.text = "  " + text


## Create the previewed body as a real node under the Map, as one undoable action. Only the
## three authored values are written; the basin, the surface and the submerged cells all
## re-derive from them (WaterBody.initialize).
func _commit_water_body(map: Map) -> void:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		push_warning("Terrain Brush: no edited scene to add a water body to.")
		return

	var body := WaterBody.new()
	body.name = "WaterBody"
	body.seed_cell = _water_seed
	body.level = _water_level
	body.energy = int(_water_energy_spin.value)
	# Picked once, here, and stored on the body: a pond that re-rolled its colour every load
	# would make the same map look different every time it opened.
	body.charge_color = WaterBody.CHARGE_COLORS.pick_random()

	var ur := get_undo_redo()
	ur.create_action("Create water body", UndoRedo.MERGE_DISABLE, map)
	ur.add_do_method(map, "add_child", body)
	ur.add_do_method(body, "set_owner", scene_root)
	ur.add_do_reference(body)
	ur.add_undo_method(map, "remove_child", body)
	ur.commit_action()
	_clear_water_preview()


## Swap the preview mesh, creating the instance under the Map as an INTERNAL child so it is
## neither saved nor shown in the scene dock — the same trick the brush ring uses.
func _set_water_preview_mesh(map: Map, mesh: ArrayMesh) -> void:
	if _water_preview == null or not is_instance_valid(_water_preview):
		_water_preview = MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.3, 0.7, 1.0, 0.45)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_water_preview.material_override = material
		map.add_child(_water_preview, false, Node.INTERNAL_MODE_BACK)
	_water_preview.mesh = mesh
	_water_preview.visible = mesh != null
	# The mesh is built in the heightmap's frame, which is the Map's — not this node's.
	_water_preview.global_transform = map.global_transform


func _clear_water_preview() -> void:
	if _water_preview != null and is_instance_valid(_water_preview):
		_water_preview.queue_free()
	_water_preview = null
	_water_basin = null
	_set_water_status("")
#endregion


#region Region preview
## Colours for the two rectangles: the selection, and the armed stamp's destination.
const _REGION_SELECT_COLOR: Color = Color(1.0, 0.85, 0.2)
const _REGION_STAMP_COLOR: Color = Color(0.3, 1.0, 0.45)


## Draw the selection rectangle and, while a stamp is armed, where it would land. Both hug
## the terrain, so the outline reads on sloped ground.
##
## This is an OUTLINE, not a translucent preview of the region's contents — building the
## latter would mean generating a second terrain mesh every time the cursor moves a cell.
func _update_region_preview(map: Map) -> void:
	if not _active or map == null or map.terrain_data == null or _current_mode() != Mode.REGION:
		_clear_region_preview()
		return
	var armed: bool = _clip_mode != Clip.NONE and _preview_cell.x != -1
	if not _has_selection() and not armed:
		_clear_region_preview()
		return

	_ensure_region_preview(map)
	var im := ImmediateMesh.new()
	if _has_selection():
		_add_rect_outline(im, map, _region_rect, _REGION_SELECT_COLOR)
	if armed:
		_add_rect_outline(im, map, Rect2i(_stamp_origin(_preview_cell), _clip_rect.size),
				_REGION_STAMP_COLOR)
	_region_preview.mesh = im
	_region_preview.visible = true


## Append one terrain-hugging rectangle outline. Edges are subdivided per cell so the line
## tracks the surface along its length rather than cutting through hills.
func _add_rect_outline(im: ImmediateMesh, map: Map, rect: Rect2i, color: Color) -> void:
	var x0: int = rect.position.x
	var z0: int = rect.position.y
	var x1: int = rect.position.x + rect.size.x
	var z1: int = rect.position.y + rect.size.y
	var corners: Array[Vector2i] = [
		Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x1, z1), Vector2i(x0, z1), Vector2i(x0, z0)
	]
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_set_color(color)
	for i: int in range(corners.size() - 1):
		var a: Vector2i = corners[i]
		var b: Vector2i = corners[i + 1]
		var steps: int = maxi(1, absi(b.x - a.x) + absi(b.y - a.y))
		for s: int in range(steps):
			var t: float = float(s) / float(steps)
			im.surface_add_vertex(_region_vertex(map, lerpf(a.x, b.x, t), lerpf(a.y, b.y, t)))
	im.surface_add_vertex(_region_vertex(map, corners[0].x, corners[0].y))
	im.surface_end()


## World position of a continuous CORNER-space point, lifted just above the terrain. Unlike
## _bounds_vertex there is no +0.5 here: a cell rectangle's outline runs along cell
## boundaries (corners), not through cell centres.
func _region_vertex(map: Map, cx: float, cz: float) -> Vector3:
	var hw: float = (map.height_map.map_width - 1) * 0.5
	var hd: float = (map.height_map.map_depth - 1) * 0.5
	var world: Vector3 = map.global_transform * Vector3(cx - hw, 0.0, cz - hd)
	world.y = map.terrain_height_at(Vector2(world.x, world.z)) + 0.06
	return world


func _ensure_region_preview(map: Map) -> void:
	if _region_preview != null and is_instance_valid(_region_preview) and _region_preview.get_parent() == map:
		return
	_clear_region_preview()
	_region_preview = MeshInstance3D.new()
	_region_preview.top_level = true  # vertices are already world-space
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true  # one mesh, two differently-coloured rectangles
	mat.no_depth_test = true
	_region_preview.material_override = mat
	map.add_child(_region_preview, false, Node.INTERNAL_MODE_BACK)


func _clear_region_preview() -> void:
	if _region_preview != null and is_instance_valid(_region_preview):
		_region_preview.queue_free()
	_region_preview = null
#endregion


#region Picking + preview
## The terrain cell under the cursor, or Vector2i(-1, -1) when the ray misses the terrain
## or lands off-map.
func _cell_under_cursor(camera: Camera3D, mouse_pos: Vector2, map: Map) -> Vector2i:
	var hit: Variant = _terrain_point_under_cursor(camera, mouse_pos, map)
	if not (hit is Vector3):
		return Vector2i(-1, -1)
	var cell: Vector2i = map.world_to_grid(Vector2((hit as Vector3).x, (hit as Vector3).z))
	var td: TerrainData = map.terrain_data
	if cell.x >= 0 and cell.x < td.grid_width() and cell.y >= 0 and cell.y < td.grid_depth():
		return cell
	return Vector2i(-1, -1)


## The world-space point where the editor camera ray meets the terrain SURFACE, or null when
## it misses. Marches the ray (works on sloped terrain, unlike a flat-plane intersection).
##
## Water mode needs the point and not just the cell: the LEVEL a click creates is the height
## of the exact spot pointed at, which is what makes "aim further up the bank for a deeper
## pond" the authoring gesture.
func _terrain_point_under_cursor(camera: Camera3D, mouse_pos: Vector2, map: Map) -> Variant:
	if camera == null:
		return null
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
			return prev.lerp(p, f)
		prev = p
		prev_diff = diff
	return null


## Draw a flat brush-radius ring centred on `center`'s world position (hidden when the
## cursor is off-terrain). Re-parented under the active Map as an internal child so it is
## neither saved nor shown in the scene dock.
func _update_preview(map: Map, center: Vector2i) -> void:
	_preview_cell = center
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
## so the author can see the region the corners are chopped to. Hidden when the brush is off
## or there is no map/terrain_data. Cheap enough to rebuild live.
func _update_bounds_overlay(map: Map) -> void:
	if not _active or map == null or map.terrain_data == null:
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
