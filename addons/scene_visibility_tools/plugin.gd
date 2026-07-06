@tool
extends EditorPlugin

## A small 3D-viewport toolbar that shows/hides authoring layers of the edited
## scenario — height pins, block pins, game entities, and scenario triggers — so the
## viewport can be decluttered while editing. There is exactly one Map per edited
## scene, so a single shared toolbar fits better than per-node inspector toggles.
##
## Each button flips its layer coherently by reading LIVE node state (a group with any
## node visible is hidden; a fully-hidden group is shown), so there is no stored toggle
## state to keep in sync when switching scenes.
##
## The "Shapes" dropdown is AUTO-DISCOVERED: any node tagged with a group named
## "debug_shape_<kind>" (e.g. debug_shape_attack_range) becomes one checkable toggle,
## rebuilt each time the menu opens. Add a new class of debug visualizer by tagging its
## node with a new debug_shape_* group — no change to this plugin is needed. Discovery
## and toggling both reach into instanced sub-scenes, so a unit instance's own shapes
## (attack ranges, etc.) are covered.
##
## SELECTION-SCOPED: when nodes are selected in the editor, the Shapes dropdown only
## discovers and toggles shapes under those nodes (and their children); with nothing
## selected it acts on the whole scene. The load-time hide + recolor always cover the
## whole scene regardless of selection.

## UNIQUE / RARE SHAPES intentionally left OUT of the debug_shape_* auto-discovery for
## now (there may eventually be many one-off cases; add one to the dropdown later simply
## by tagging its node with a debug_shape_* group):
##   - HealAOE (field hospital) — an Area3D heal region; notably the ONLY "range" built
##     as a real monitoring Area3D rather than a bare on-demand query shape.
##   - DominionRegion (warlord) — dominion influence area.
##   - HitShape (projectiles) — projectile collision volume. Projectiles are spawned at
##     runtime, so they don't exist in an authored/edited scene anyway.

## Groups whose Node3D members count as "entities" — mirrors Map._collect_game_entities.
const _ENTITY_GROUPS: Array[String] = ["commandable", "structure", "start_position"]

## Prefix that marks a node as a toggleable debug visualizer shape.
const _SHAPE_GROUP_PREFIX: String = "debug_shape_"

var _toolbar: HBoxContainer
var _shapes_menu: MenuButton
## popup item id -> debug_shape group name, rebuilt whenever the popup opens.
var _shape_menu_groups: Dictionary = {}


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	var label := Label.new()
	label.text = "Show:"
	_toolbar.add_child(label)
	_add_button("Height Pins", _toggle_height_pins)
	_add_button("Block Pins", _toggle_block_pins)
	_add_button("Entities", _toggle_entities)
	_add_button("Triggers", _toggle_triggers)
	_add_shapes_menu()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	scene_changed.connect(_on_scene_changed)
	_refresh_toolbar_visibility()
	# Hide + recolor debug shapes for the already-open scene when the plugin (re)loads.
	# Deferred so the edited scene tree is settled before we walk it.
	_hide_all_debug_shapes.call_deferred()
	_apply_debug_colors.call_deferred()


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	_toolbar = null
	_shapes_menu = null


func _add_button(text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.tooltip_text = "Toggle %s visibility in the edited scene" % text
	button.pressed.connect(on_pressed)
	_toolbar.add_child(button)


## A dropdown of checkable toggles, one per discovered debug_shape_* group.
func _add_shapes_menu() -> void:
	_shapes_menu = MenuButton.new()
	_shapes_menu.text = "Shapes"
	_shapes_menu.flat = true
	_shapes_menu.tooltip_text = "Toggle debug visualizer shapes (attack ranges, bodies, …)"
	var popup := _shapes_menu.get_popup()
	popup.hide_on_checkable_item_selection = false  # keep open while toggling several
	popup.about_to_popup.connect(_populate_shapes_menu)
	popup.id_pressed.connect(_on_shape_menu_id)
	_toolbar.add_child(_shapes_menu)


## Rebuild the dropdown from the debug_shape_* groups currently in the edited scene, so
## newly-added visualizer classes appear automatically. Check state reflects live
## visibility (checked = at least one shape of that kind is visible).
func _populate_shapes_menu() -> void:
	var popup := _shapes_menu.get_popup()
	popup.clear()
	_shape_menu_groups.clear()
	# The LIST is always every shape class in the whole scene, so it's stable regardless
	# of selection (with nothing selected you can still toggle e.g. all attack ranges).
	# The check state and the toggle are SCOPED to the selection (or the whole scene when
	# nothing is selected) — so a class absent from the current selection still appears,
	# but toggling it simply no-ops.
	var scope := _scope_roots()
	for group: String in _discover_shape_groups(_full_roots()):
		var id: int = popup.item_count
		popup.add_check_item(group.trim_prefix(_SHAPE_GROUP_PREFIX).capitalize(), id)
		popup.set_item_checked(id, _group_any_visible(group, scope))
		_shape_menu_groups[id] = group
	if popup.item_count == 0:
		popup.add_item("(no debug shapes in scene)")
		popup.set_item_disabled(0, true)


func _on_shape_menu_id(id: int) -> void:
	var group: String = _shape_menu_groups.get(id, "")
	if group.is_empty():
		return
	# Recompute the scope at toggle time; opening the dropdown doesn't change selection,
	# so this matches what _populate_shapes_menu showed.
	var roots := _scope_roots()
	_flip(_nodes_in_group(group, roots))
	_shapes_menu.get_popup().set_item_checked(id, _group_any_visible(group, roots))


func _on_scene_changed(_scene_root: Node) -> void:
	_refresh_toolbar_visibility()
	# Debug shapes start hidden on every scene open so the viewport isn't cluttered by
	# collision-shape gizmos; the "Shapes" dropdown turns the ones you want back on.
	_hide_all_debug_shapes()
	# Enforce per-class debug colors from the central map, so every shape of a class
	# reads the same color regardless of what any scene stored.
	_apply_debug_colors()


## Hide every debug_shape_* node in the edited scene. Editor-only (this is an
## EditorPlugin); a direct visible-set does not route through undo/redo, so it doesn't
## mark the scene modified.
func _hide_all_debug_shapes() -> void:
	var roots := _full_roots()  # load-time: whole scene, never the selection
	for group: String in _discover_shape_groups(roots):
		for node: Node3D in _nodes_in_group(group, roots):
			node.visible = false


## Recolor each debug_shape CollisionShape3D from DebugShapeColors.GROUP_COLOR — the
## single source of truth — so classes stay consistent without per-scene debug_color
## values. Groups absent from the map (e.g. the non-shape footprint) are left alone.
func _apply_debug_colors() -> void:
	var roots := _full_roots()  # load-time: whole scene, never the selection
	for group: String in DebugShapeColors.GROUP_COLOR:
		var color: Color = DebugShapeColors.GROUP_COLOR[group]
		for node: Node3D in _nodes_in_group(group, roots):
			if node is CollisionShape3D:
				(node as CollisionShape3D).debug_color = color


## Show the toolbar for scenes that contain a Map OR any debug_shape_* shapes (so it's
## available both in scenarios and when editing an entity scene directly).
func _refresh_toolbar_visibility() -> void:
	if _toolbar != null:
		_toolbar.visible = _current_map() != null or not _discover_shape_groups(_full_roots()).is_empty()


#region Toggles
func _toggle_height_pins() -> void:
	var map := _current_map()
	if map != null:
		_flip([map.get_node_or_null("HeightPins")])


func _toggle_block_pins() -> void:
	var map := _current_map()
	if map != null:
		_flip([map.get_node_or_null("BlockPins")])


func _toggle_entities() -> void:
	_flip(_entities())


func _toggle_triggers() -> void:
	_flip(_triggers())
#endregion


#region Scene lookups
## The Map in the currently edited scene, or null. There is at most one.
func _current_map() -> Map:
	return _find_map(EditorInterface.get_edited_scene_root())


func _find_map(node: Node) -> Map:
	if node == null:
		return null
	if node is Map:
		return node as Map
	for child in node.get_children():
		var found := _find_map(child)
		if found != null:
			return found
	return null


## Authored game entities under the edited scene (units, structures, deposits, start
## markers). Scoped to the edited scene via is_ancestor_of and de-duplicated.
func _entities() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return result
	var seen: Dictionary = {}
	for group: String in _ENTITY_GROUPS:
		for node: Node in root.get_tree().get_nodes_in_group(group):
			if node is Node3D and not seen.has(node) and root.is_ancestor_of(node):
				seen[node] = true
				result.append(node as Node3D)
	return result


## Scenario trigger roots. ScenarioTriggerManager is a plain Node with no visibility,
## so its Node3D children (each a trigger subtree) are what we flip.
func _triggers() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return result
	var manager := root.get_node_or_null("ScenarioTriggerManager")
	if manager == null:
		return result
	for child in manager.get_children():
		if child is Node3D:
			result.append(child as Node3D)
	return result


## Traversal scope for the Shapes toggles: the current editor selection when anything is
## selected (so discovery + toggling are limited to those nodes and their children),
## otherwise the whole edited scene.
## Returns a plain Array (not Array[Node]): get_selected_nodes() is untyped and array
## literals are untyped, so a typed return would raise a runtime conversion error.
func _scope_roots() -> Array:
	var selected: Array = EditorInterface.get_selection().get_selected_nodes()
	return selected if not selected.is_empty() else _full_roots()


## The whole edited scene — used for load-time hide/recolor and toolbar visibility, which
## must ignore the current selection.
func _full_roots() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	return [root] if root != null else []


## True when `node` is one of `roots` or a descendant of one.
func _in_roots(node: Node, roots: Array) -> bool:
	for r: Node in roots:
		if node == r or r.is_ancestor_of(node):
			return true
	return false


## Distinct debug_shape_* group names under `roots`, sorted. Recurses into instanced
## sub-scenes (a node reports its groups even when they were defined in a base/instanced
## scene), so a unit's own shape groups are discovered.
func _discover_shape_groups(roots: Array) -> Array[String]:
	var seen: Dictionary = {}
	for r: Node in roots:
		_collect_shape_groups(r, seen)
	var result: Array[String] = []
	for group: String in seen:
		result.append(group)
	result.sort()
	return result


func _collect_shape_groups(node: Node, seen: Dictionary) -> void:
	for g: StringName in node.get_groups():
		var s := String(g)
		if s.begins_with(_SHAPE_GROUP_PREFIX):
			seen[s] = true
	for child: Node in node.get_children():
		_collect_shape_groups(child, seen)


## Node3D members of `group` that live within `roots` (one of them, or a descendant).
func _nodes_in_group(group: String, roots: Array) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if roots.is_empty():
		return result
	for node: Node in roots[0].get_tree().get_nodes_in_group(group):
		if node is Node3D and _in_roots(node, roots):
			result.append(node as Node3D)
	return result


func _group_any_visible(group: String, roots: Array) -> bool:
	for node: Node3D in _nodes_in_group(group, roots):
		if node.visible:
			return true
	return false
#endregion


## Flip a set of nodes to one coherent visibility: if ANY is visible, hide all; if all
## are hidden, show all. Null / non-Node3D entries are skipped.
func _flip(nodes: Array) -> void:
	var targets: Array[Node3D] = []
	for n: Variant in nodes:
		if n is Node3D:
			targets.append(n as Node3D)
	if targets.is_empty():
		return
	var any_visible: bool = targets.any(func(t: Node3D) -> bool: return t.visible)
	for t: Node3D in targets:
		t.visible = not any_visible
