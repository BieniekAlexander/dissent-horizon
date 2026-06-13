@tool
extends EditorPlugin

## Opt-in, modifier-gated terrain snapping for the 3D editor viewport.
##
## Finish moving a node (release the left mouse button after a drag) while holding:
##   - Option (Alt)          → snap the selection's Y to the terrain heightmap
##                             height at its current XZ (continuous, follows slopes).
##   - Option (Alt) + Shift  → snap the selection to the terrain GRID: XZ + Y to the
##                             centre of its footprint (a structure with an
##                             Obstruction uses its full size, so a 2×2 lands on a
##                             grid corner; everything else is a single cell). This
##                             matches how Map.add_structure places it at runtime.
##
## Nothing happens on a normal drag — you only snap when the modifier is held, so a
## unit intentionally placed high above the terrain (e.g. a flier) is left alone.
## Snaps every selected Node3D and is registered as a single undoable action.
##
## Requires a Map node (scripts/maps/map.gd) somewhere in the edited scene with its
## height_map assigned. To rebind the keys, change the modifier checks in
## _forward_3d_gui_input.

# True between a left-button press and its release inside the viewport.
var _drag_active: bool = false
# True once the mouse actually moved while the button was held (a real transform,
# not just a selection click).
var _drag_moved: bool = false


func _handles(object: Object) -> bool:
	# Activates viewport input forwarding whenever a Node3D is selected. With a
	# MULTI-selection the editor's edited object is a MultiNodeEdit (not a Node3D),
	# so also return true when the current selection contains any Node3D — otherwise
	# forwarding (and thus snapping) silently stops for multi-selection drags.
	if object is Node3D:
		return true
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if node is Node3D:
			return true
	return false


func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_moved = false
		else:
			if _drag_active and _drag_moved and event.alt_pressed:
				_snap_selection(event.shift_pressed)
			_drag_active = false
			_drag_moved = false
	elif event is InputEventMouseMotion and _drag_active:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag_moved = true

	# Always let the built-in move gizmo handle the event too.
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Snap every selected Node3D. When `to_grid` is true, snap XZ+Y to the grid cell;
## otherwise snap only Y to the continuous terrain height.
func _snap_selection(to_grid: bool) -> void:
	var map := _find_map()
	if map == null:
		push_warning("Terrain Snap: no Map with a height_map found in the edited scene.")
		return
	if map.height_map == null:
		push_warning("Terrain Snap: the Map node has no height_map assigned.")
		return

	var spatials: Array[Node3D] = []
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if node is Node3D:
			spatials.append(node)
	if spatials.is_empty():
		return

	var ur := get_undo_redo()
	ur.create_action("Snap to terrain grid cell" if to_grid else "Snap to terrain height")
	for node: Node3D in spatials:
		var before: Vector3 = node.global_position
		var after: Vector3 = _snapped_position(map, node, before, to_grid)
		ur.add_do_property(node, "global_position", after)
		ur.add_undo_property(node, "global_position", before)
	ur.commit_action()


func _snapped_position(map: Map, node: Node3D, pos: Vector3, to_grid: bool) -> Vector3:
	var xz := Vector2(pos.x, pos.z)
	if not to_grid:
		# terrain_height_at clamps out-of-bounds XZ internally.
		return Vector3(pos.x, map.terrain_height_at(xz), pos.z)

	# Footprint-aware grid snap: a structure with an Obstruction centres on its
	# whole footprint (even sizes land on a grid corner, odd on a cell); anything
	# else is treated as 1×1 (a single cell). Computed from the HEIGHTMAP dims, not
	# cell_grid (which is empty in the editor).
	var dims := _dimensions(node)
	var hm := map.height_map
	var local: Vector3 = map.global_transform.affine_inverse() * Vector3(pos.x, 0.0, pos.z)
	var cx: float = local.x + (hm.map_width - 1) * 0.5
	var cz: float = local.z + (hm.map_depth - 1) * 0.5
	var origin := Vector2i(roundi(cx - dims.x * 0.5), roundi(cz - dims.y * 0.5))
	origin.x = clampi(origin.x, 0, hm.map_width - 1 - dims.x)
	origin.y = clampi(origin.y, 0, hm.map_depth - 1 - dims.y)
	var centroid := Vector3.ZERO
	for w in range(dims.x):
		for l in range(dims.y):
			centroid += map.grid_to_world(origin + Vector2i(w, l))
	return centroid / float(dims.x * dims.y)


## Footprint size from the node's Obstruction component (via get() so it works on
## the editor's placeholder instance of the non-@tool node), or 1×1 if none.
func _dimensions(node: Node) -> Vector2i:
	var obs := node.get_node_or_null("Obstruction")
	if obs == null:
		return Vector2i.ONE
	var d: Variant = obs.get("dimensions")
	return d if d is Vector2i else Vector2i.ONE


## Find the Map in the edited scene: the root itself, a child named "Map", or the
## first Map-typed descendant.
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
