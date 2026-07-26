class_name RTSController extends CanvasLayer

#region Constants
const free_cursor: Resource = preload("res://assets/interface/cursor_free.png")
const selection_cursor: Resource = preload("res://assets/interface/cursor_selection.png")
const attack_cursor: Resource = preload("res://assets/interface/cursor_attack.png")
const unknown_cursor: Resource = preload("res://assets/interface/cursor_unknown.png")
const invalid_cursor: Resource = preload("res://assets/interface/cursor_invalid.png")

# The commander id the local human controls. Runtime-set by Scenario from its
# player_slots (the first non-bot slot), so the player can be any commander id —
# or absent entirely (spectator), in which case this is < 1 and
# no human rig (camera/HUD/fog) exists. Read by fog, minimap, and commandable to
# decide the local viewpoint. Was a const; now a static var so it can vary.
static var PLAYER_COMMANDER_ID: int = 1

# Full-panel HUD Controls in this group swallow world-selection clicks: a press or
# release whose cursor sits inside any of them is NOT interpreted as unit selection
# (see _pointer_over_blocking_ui). Add future HUD panels (MapSection, InfoSection,
# CommandsSection, …) to this group in the scene to have them ignored the same way.
const SELECTION_BLOCKING_UI_GROUP: StringName = &"selection_blocking_ui"

const BUILD_PREVIEW_ALPHA: float = 0.45
const BUILD_PREVIEW_VALID_TINT:   Color = Color(1.0, 1.0, 1.0, BUILD_PREVIEW_ALPHA)
const BUILD_PREVIEW_INVALID_TINT: Color = Color(1.0, 0.25, 0.25, BUILD_PREVIEW_ALPHA)

const _INDICATOR_POOL_SIZE: int = 16

## Command names for the SELECT-context grid buttons shown when nothing is
## selected. Dispatched via _select_command_handlers (built in _ready), bypassing
## the normal, selection-gated process_command pipeline. Referenced by
## command_grid.gd's SELECT bindings so the strings live in one place.
const CMD_SELECT_IDLE_COMBAT: String = "command_select_idle_combat"
const CMD_SELECT_ARMY_ON_SCREEN: String = "command_select_army_on_screen"
const CMD_SELECT_ARMY_ALL: String = "command_select_army_all"
const CMD_SELECT_IDLE_BUILDER: String = "command_select_idle_builder"
const CMD_SELECT_BUILDERS_ON_SCREEN: String = "command_select_builders_on_screen"
const CMD_SELECT_BUILDERS_ALL: String = "command_select_builders_all"
const CMD_SELECT_IDLE_PRODUCTION: String = "command_select_idle_production"
const CMD_SELECT_PRODUCTION_ON_SCREEN: String = "command_select_production_on_screen"
const CMD_SELECT_PRODUCTION_ALL: String = "command_select_production_all"

## Max gap between two clicks on the same unit for them to count as a double-click
## (which selects all on-screen units of that entity type).
const DOUBLE_CLICK_SECONDS: float = 0.3
#endregion

#region Signals
signal unit_selected(entity: Entity)
signal command_issued(entity: Entity, command_type: Script)
#endregion

#region Properties
@onready var map: Map = get_tree().current_scene.find_child("Map")
@onready var camera: RTSCamera3D = get_viewport().get_camera_3d()
@onready var _info_view: InfoView = $InfoSection

var cursor_target: Variant = Vector3.ZERO
var mouse_position: Vector2 = Vector2.ZERO

@export var selection_box: ColorRect = ColorRect.new()
@onready var command_message: CommandMessage = CommandMessage.new(map)
@onready var next_command_additive: bool = false
var selection: Array[Node] = []
var select_down_position: Vector2 = Vector2.ZERO
var current_command_type: Script = null

## SELECT-context grid command name -> the selection routine it invokes. Built in
## _ready (values are bound to this instance). Drives both the "nothing selected"
## button visibility and the button-press dispatch.
var _select_command_handlers: Dictionary = {}

## Double-click tracking: the player unit hit by the previous click and when
## (engine ms) it was clicked. A second click on the same unit within
## DOUBLE_CLICK_SECONDS selects all on-screen units of that type.
var _last_click_target: Entity = null
var _last_click_time_ms: int = -1

## The set of command names available given the current selection — recomputed
## (via CommandContextParser) whenever the selection changes. Used by the HUD
## visibility loop and the hotkey-input gate in process_command(). Replaces
## the merged CommandContext that the controller used to consult.
var _available_commands: Array = []
var available_commands: Array:
	get: return _available_commands
	set(value):
		_available_commands = value
		upate_hud_buttons()

## A hotkey like `command_attack_move` puts the controller into a "pending"
## sub-mode where the next right-click resolves to AttackMove (or Attack on a
## hostile target) instead of the default move/attack. Empty string = no
## pending hotkey; resolve generically based on the cursor target. Replaces
## the old state_maping-based sub-context machinery.
var pending_command_name: String = ""

## One WaypointIndicator node per active CommandMessage snapshot, pooled to
## avoid per-command allocations.  All indicator nodes live under the Map node.
var _active_indicators: Dictionary = {}  # CommandMessage -> WaypointIndicator
var _indicator_pool: Array = []          # idle WaypointIndicator nodes

## The local commander's ordnance arsenal — its DAG of unlockable ordnances and the
## per-match owned/cooldown state (see _setup_commander_ordnances).
var _arsenal: OrdnanceArsenal = null
## Ordnance armed by the player — the next right-click activates it at that position.
var _pending_ordnance: Ordnance = null
## Horizontal ordnance bar added to this CanvasLayer at runtime.
var _ordnance_bar: HBoxContainer = null

@onready var _event_manager: ScenarioTriggerManager = \
	get_tree().current_scene.find_child("ScenarioTriggerManager") as ScenarioTriggerManager

## While a Build command is armed with a chosen Tool, we show a translucent
## "ghost" of the structure under the cursor, snapped to the cell it would
## occupy — the standard RTS placement preview. The ghost is a Sprite3D
## duplicated out of the building's own scene (so it always matches the real
## building art) and lives in the 3D world under the Map, not on this
## CanvasLayer. We rebuild it only when the chosen structure changes.
var _build_preview: Node3D = null
var _build_preview_tool_type: Variant = null
#endregion

#region Lifecycle
func _ready():
	Input.set_custom_mouse_cursor(free_cursor)
	# Map each SELECT-context grid command to its selection routine. Must be built
	# before the first upate_hud_buttons() (below) since it drives which buttons
	# show while nothing is selected.
	_select_command_handlers = {
		CMD_SELECT_IDLE_COMBAT: select_least_recently_selected_idle_combat_unit,
		CMD_SELECT_ARMY_ON_SCREEN: select_army_units_on_screen,
		CMD_SELECT_ARMY_ALL: select_all_army_units,
		CMD_SELECT_IDLE_BUILDER: select_least_recently_selected_idle_builder_unit,
		CMD_SELECT_BUILDERS_ON_SCREEN: select_builders_on_screen,
		CMD_SELECT_BUILDERS_ALL: select_all_builders,
		CMD_SELECT_IDLE_PRODUCTION: select_least_recently_selected_idle_production_structure,
		CMD_SELECT_PRODUCTION_ON_SCREEN: select_production_structures_on_screen,
		CMD_SELECT_PRODUCTION_ALL: select_all_production_structures,
	}
	upate_hud_buttons()

	selection_box.visible = false
	if !selection_box.is_inside_tree():
		add_child(selection_box)

	# The info panel's summary cards drive selection changes (left click = select only,
	# shift+click = remove from selection).
	if _info_view != null:
		_info_view.select_only_requested.connect(select_only)
		_info_view.deselect_requested.connect(remove_from_selection)

	# Waypoint indicators live under Map; skip pooling when there is no Map
	# (e.g. running player.tscn standalone to preview the HUD).
	if map != null:
		for i in range(_INDICATOR_POOL_SIZE):
			_indicator_pool.append(_make_indicator())

	# Deferred: this controller is a child of its Commander, so child _ready() runs
	# BEFORE the parent's. The commander instances its Faction in its own _ready(),
	# so reading commander.faction now would see null. Deferring runs the setup after
	# the whole subtree's _ready() cascade, once the faction exists.
	_setup_commander_ordnances.call_deferred()

func _process(delta: float) -> void:
	_tick_ordnance_bar(delta)

	var cursor_result: Variant = get_cursor_target(mouse_position)
	cursor_target = cursor_result
	command_message.target = cursor_result if cursor_result is Entity else null
	command_message.world_position = cursor_result if cursor_result is Vector3 \
		else camera.get_mouse_world_position(mouse_position)

	var pruned: bool = false
	for i in range(selection.size()-1, -1, -1):
		var entity: Node = selection[i]
		if not is_instance_valid(entity) or not entity.is_inside_tree():
			if is_instance_valid(entity):
				entity.selectable.deselect()
			selection.remove_at(i)
			pruned = true
			continue
		# Drop an enemy/neutral unit as soon as it leaves the player's vision.
		var commandable: Commandable = entity as Commandable
		if commandable != null and not _is_player_owned(commandable) \
				and not commandable.is_visible_to(PLAYER_COMMANDER_ID):
			commandable.selectable.deselect()
			selection.remove_at(i)
			pruned = true
	if pruned:
		_refresh_available_commands()

	# Command resolution only applies to the player's own units; an enemy/neutral
	# selection is info-only, so no command is resolved (or later issued) for it.
	current_command_type = _resolve_command_class(
		pending_command_name,
		selection[0],
		command_message
	) if _selection_owned_by_player() else null

	var check: MoveCommand.PreconditionFailureCause =  (
		MoveCommand.PreconditionFailureCause.NONE
		if current_command_type==null
		else current_command_type.meets_precondition(selection[0] if !selection.is_empty() else null, command_message)
	)

	$CommandErrorMessage.text = MoveCommand.precondition_message_map[check]

	if check==MoveCommand.PreconditionFailureCause.NONE:
		Input.set_custom_mouse_cursor(cursor_evaluator(current_command_type, command_message))
	elif check==MoveCommand.PreconditionFailureCause.COMMAND_PENDING_TOOL:
		# Not a failure — the command is awaiting the player's tool selection, so
		# keep the default cursor rather than flagging an invalid placement.
		Input.set_custom_mouse_cursor(free_cursor)
	else:
		Input.set_custom_mouse_cursor(invalid_cursor)

	_update_build_preview(check == MoveCommand.PreconditionFailureCause.INVALID_PLACEMENT)
	_update_waypoint_display()
	_info_view.update(selection)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		if selection_box.visible == true:
			var selection_box_size = abs(mouse_position - select_down_position)
			selection_box.set_size(selection_box_size)
			if mouse_position.x > select_down_position.x && mouse_position.y > select_down_position.y:
				selection_box.position = select_down_position
			elif mouse_position.x < select_down_position.x && mouse_position.y < select_down_position.y:
				selection_box.position = mouse_position
			elif mouse_position.x > select_down_position.x:
				selection_box.position = Vector2(mouse_position.x - selection_box_size.x, mouse_position.y)
			else:
				selection_box.position = Vector2(mouse_position.x, mouse_position.y - selection_box_size.y)
	elif event.is_action_pressed("isometric_camera_select"):
		# A press that starts on a HUD panel isn't a world-selection drag — ignore it so
		# the panel's own controls (or nothing) handle the click.
		if _pointer_over_blocking_ui():
			return
		select_down_position = mouse_position
		selection_box.visible = true
		selection_box.set_size(Vector2.ZERO)
	elif event.is_action_released("isometric_camera_select"):
		selection_box.visible = false
		# Only resolve a selection when the release is over the world, not a HUD panel —
		# otherwise clicking a HUD element (e.g. an info-panel card) would also clear or
		# retarget the world selection on button-up.
		if not _pointer_over_blocking_ui():
			_handle_select_release()
	elif event.is_action_pressed("command_additive"):
		next_command_additive = true
	elif event.is_action_released("command_additive"):
		next_command_additive = false
	elif get_action_names_by_prefix(event, "command_").size()>0:
		_dispatch_command_hotkey(get_action_names_by_prefix(event, "command_"))
	elif event.is_action_pressed("move"):
		if _pending_ordnance != null:
			_activate_pending_ordnance()
		elif _selection_owned_by_player():
			# Only the player's own units take commands; an enemy/neutral
			# info-selection ignores the move/command click.
			assign_command_to_units(
				current_command_type,
				command_message,
				next_command_additive
			)
#endregion

#region Selection
## True when the LIVE cursor position lies inside any visible HUD panel in the
## SELECTION_BLOCKING_UI_GROUP. Clicks over those panels must not drive world selection.
## Grouping (rather than hard-coding the three sections) means any future full-panel UI
## added to that group is ignored automatically.
##
## Reads get_viewport().get_mouse_position() directly rather than the cached
## `mouse_position` field: that field only updates from MouseMotion events that reach
## _unhandled_input, and motion over a HUD panel is swallowed by the panel — so the
## cached value is stale (still a world point) exactly when we need to know we're over UI.
func _pointer_over_blocking_ui() -> bool:
	var screen_pos: Vector2 = get_viewport().get_mouse_position()
	for node: Node in get_tree().get_nodes_in_group(SELECTION_BLOCKING_UI_GROUP):
		var panel: Control = node as Control
		if panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen_pos):
			return true
	return false

## Return all Selectable nodes whose projected screen position falls within screen_rect.
func query_box_collisions(screen_rect: Rect2) -> Array:
	return get_tree().get_nodes_in_group("selectables").filter(
		func(selectable: Selectable) -> bool:
			return screen_rect.has_point(camera.unproject_position(selectable.global_position))
	)

func deselect():
	for c in selection:
		if is_instance_valid(c):
			c.selectable.deselect()
	selection = []
	pending_command_name = ""

## Make `commandable` the sole selection (used by the info panel's summary cards). Clears
## the current selection, selects just this one, and refreshes the HUD to match.
func select_only(commandable: Commandable) -> void:
	deselect()
	if is_instance_valid(commandable) and commandable.selectable.select():
		selection.append(commandable)
	_refresh_available_commands()
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)

## Drop `commandable` from the current selection (used by shift+click on a summary card),
## leaving the rest selected, then refresh the HUD.
func remove_from_selection(commandable: Commandable) -> void:
	if commandable in selection:
		if is_instance_valid(commandable):
			commandable.selectable.deselect()
		selection.erase(commandable)
	_refresh_available_commands()

func set_selection(selection_start_position: Vector2, selection_end_position: Vector2):
	var drag_distance = abs(selection_start_position - selection_end_position)
	if drag_distance < Vector2(10, 10):
		var click_target = get_cursor_target(selection_start_position)
		if click_target is Entity:
			var entity: Entity = click_target as Entity
			if _is_player_owned(entity):
				# Selecting your own unit never keeps an enemy info-selection around.
				if _has_enemy_selected():
					deselect()
				if next_command_additive and selection.has(entity):
					entity.selectable.deselect()
					selection.erase(entity)
				elif entity.selectable.select():
					selection.append(entity)
			elif not next_command_additive:
				# Enemy/neutral: single-select only (never additively). The
				# non-additive deselect in _handle_select_release already cleared
				# the prior selection, so this becomes the sole selected unit.
				if entity.selectable.select():
					selection.append(entity)
			# A shift-click on an enemy/neutral unit is ignored (falls through).
	else:
		var boxed: Array = query_box_collisions(
			Rect2(selection_start_position, selection_end_position - selection_start_position).abs()
		).filter(
			func(s: Selectable) -> bool:
				var e := s.get_entity()
				return e != null and e.commander_id == PLAYER_COMMANDER_ID
		)
		# A box that catches any unit skips structures, so dragging over a mixed group
		# selects only the mobile units (structures are picked individually). Consider
		# the current selection too, so an additive box behaves the same.
		var has_unit: bool = selection.any(func(e): return not e.has_node("Structure")) \
			or boxed.any(func(s: Selectable): return not s.get_entity().has_node("Structure"))
		for selectable: Selectable in boxed:
			var entity := selectable.get_entity()
			if has_unit and entity.has_node("Structure"):
				continue
			if selectable.select():
				selection.append(entity)

	_refresh_available_commands()
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)

## Select every player-owned unit whose world XZ falls inside `world_rect` (a
## rectangle in the XZ plane, world units). Mirrors the box branch of
## set_selection but tests each unit's world position directly instead of
## projecting it to screen — this is what the minimap's drag-select uses, since a
## minimap drag defines a region in world space, not on the viewport. `additive`
## keeps the current selection (shift-drag) instead of replacing it.
func select_units_in_world_rect(world_rect: Rect2, additive: bool) -> void:
	if not additive:
		deselect()
	var boxed: Array = get_tree().get_nodes_in_group("selectables").filter(
		func(s: Selectable) -> bool:
			var e: Entity = s.get_entity()
			return e != null and e.commander_id == PLAYER_COMMANDER_ID \
				and world_rect.has_point(VU.inXZ(e.global_position))
	)
	# A box that catches any unit skips structures, so a drag over a mixed group
	# selects only the mobile units (mirrors set_selection). Consider the current
	# selection too, so an additive drag behaves the same.
	var has_unit: bool = selection.any(func(e): return not e.has_node("Structure")) \
		or boxed.any(func(s: Selectable): return not s.get_entity().has_node("Structure"))
	for selectable: Selectable in boxed:
		var entity: Entity = selectable.get_entity()
		if has_unit and entity.has_node("Structure"):
			continue
		if not selection.has(entity) and selectable.select():
			selection.append(entity)
	_refresh_available_commands()
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)

## Whether `entity` belongs to the local player.
func _is_player_owned(entity: Entity) -> bool:
	return entity != null and entity.commander_id == PLAYER_COMMANDER_ID

## True when the current selection is the player's own — the only selection the
## player can issue commands to. Enemy/neutral selections are info-only.
func _selection_owned_by_player() -> bool:
	return not selection.is_empty() and _is_player_owned(selection[0] as Entity)

## True when the current selection is a single enemy/neutral (non-player) unit.
func _has_enemy_selected() -> bool:
	return not selection.is_empty() and not _is_player_owned(selection[0] as Entity)

## Recomputes the command set for the current selection, and refreshes HUD button
## visibility via the setter. Empty for an enemy selection — the player can look
## but not command it.
func _refresh_available_commands() -> void:
	available_commands = [] if _has_enemy_selected() \
		else CommandContextParser.commands_for_selection(selection)

## Resolves a left-click release into either a double-click (select all on-screen
## units of the clicked unit's type) or a normal single-click / box selection.
func _handle_select_release() -> void:
	# Only a click (not a drag) can be part of a double-click; identify the
	# player unit under the cursor, if any.
	var is_click: bool = abs(mouse_position - select_down_position) < Vector2(10, 10)
	# get_cursor_target returns an Entity, a Vector3 (terrain), or null — only keep
	# the Entity case (guard the cast so a Vector3 isn't cast to Entity).
	var hit: Variant = get_cursor_target(select_down_position) if is_click else null
	var target: Entity = hit as Entity if hit is Entity else null
	var is_player_unit: bool = target != null and target.commander_id == PLAYER_COMMANDER_ID

	if is_player_unit and _is_double_click(target):
		_select_on_screen_units_of_type(target.id)
		_last_click_target = null  # reset so a third quick click starts fresh
		return

	if !next_command_additive:
		deselect()
	set_selection(select_down_position, mouse_position)
	# Record this click so a matching follow-up click registers as a double-click.
	_last_click_target = target if is_player_unit else null
	_last_click_time_ms = Time.get_ticks_msec()

## True when `target` is the same unit clicked last, within DOUBLE_CLICK_SECONDS.
func _is_double_click(target: Entity) -> bool:
	return target == _last_click_target \
		and _last_click_time_ms >= 0 \
		and (Time.get_ticks_msec() - _last_click_time_ms) <= int(DOUBLE_CLICK_SECONDS * 1000.0)

## Replaces the selection (or adds, when additive) with every on-screen,
## player-owned commandable whose entity type matches `entity_type`.
func _select_on_screen_units_of_type(entity_type: StringName) -> void:
	if !next_command_additive:
		deselect()
	var candidates: Array = get_tree().get_nodes_in_group("commandable").filter(
		func(c: Variant) -> bool:
			return c is Entity \
				and (c as Entity).id == entity_type \
				and (c as Entity).commander_id == PLAYER_COMMANDER_ID
	)
	_select_units(commandables_on_screen(candidates))

# --- Category predicates (a Commandable satisfies the category) ---------------
## "Army" unit: a unit carrying at least one Weapon in its Loadout.
func _is_army_unit(c: Commandable) -> bool:
	var loadout: Loadout = c.get_node_or_null("Loadout") as Loadout
	return c.is_in_group("unit") and loadout != null and loadout.has_weapons()

## "Builder" unit: a unit with a Builds component.
func _is_builder_unit(c: Commandable) -> bool:
	return c.is_in_group("unit") and c.has_node("Builds")

## "Production structure": a structure that can train units (has Production).
func _is_producer_structure(c: Commandable) -> bool:
	return c.is_in_group("structure") and c.production != null

# --- Least-recently-selected (idle) cyclers -----------------------------------
## Idle army unit, least recently selected. Idle = no active command.
func select_least_recently_selected_idle_combat_unit() -> Commandable:
	return _select_least_recently_selected(
		func(c: Commandable) -> bool: return c._command == null and _is_army_unit(c)
	)

## Idle builder unit, least recently selected. Idle = no active command.
func select_least_recently_selected_idle_builder_unit() -> Commandable:
	return _select_least_recently_selected(
		func(c: Commandable) -> bool: return c._command == null and _is_builder_unit(c)
	)

## Idle production structure, least recently selected. Idle = can produce but its
## training queue is currently empty (not producing anything).
func select_least_recently_selected_idle_production_structure() -> Commandable:
	return _select_least_recently_selected(
		func(c: Commandable) -> bool: return _is_producer_structure(c) and c.production.training_queue.is_empty()
	)

# --- Bulk selection (on-screen / global) --------------------------------------
## Selects every on-screen player army unit.
func select_army_units_on_screen() -> void:
	_select_all(_is_army_unit, true)

## Selects every player army unit, on screen or not.
func select_all_army_units() -> void:
	_select_all(_is_army_unit, false)

## Selects every on-screen player builder.
func select_builders_on_screen() -> void:
	_select_all(_is_builder_unit, true)

## Selects every player builder, on screen or not.
func select_all_builders() -> void:
	_select_all(_is_builder_unit, false)

## Selects every on-screen player production structure.
func select_production_structures_on_screen() -> void:
	_select_all(_is_producer_structure, true)

## Selects every player production structure, on screen or not.
func select_all_production_structures() -> void:
	_select_all(_is_producer_structure, false)

# --- Shared selection machinery -----------------------------------------------
## Adds every player-owned commandable satisfying `predicate` to the selection
## (replacing it first unless additive). `on_screen_only` restricts to the ones
## currently visible in the camera's view.
func _select_all(predicate: Callable, on_screen_only: bool) -> void:
	if !next_command_additive:
		deselect()
	var candidates: Array = get_tree().get_nodes_in_group("commandable").filter(
		func(node: Variant) -> bool:
			var c: Commandable = node as Commandable
			return c != null and c.commander_id == PLAYER_COMMANDER_ID \
				and c.selectable != null and predicate.call(c)
	)
	if on_screen_only:
		candidates = commandables_on_screen(candidates)
	_select_units(candidates)

## Selects each commandable in `entities` (skipping already-selected ones) and
## refreshes the HUD / available-command state. Shared selection finalizer.
func _select_units(entities: Array) -> void:
	for entity: Node in entities:
		var cmd: Commandable = entity as Commandable
		if cmd == null or cmd.selectable == null or selection.has(cmd):
			continue
		if cmd.selectable.select():
			selection.append(cmd)
	available_commands = CommandContextParser.commands_for_selection(selection)
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)

## Shared machinery for the least-recently-selected cyclers. Scans the player's
## commandables for the one satisfying `predicate` that was selected longest ago,
## then makes it the sole selection and centers the camera on it. Returns that
## commandable, or null if none qualify. Selecting it bumps its
## Selectable.last_selected_time, so repeated calls cycle through the group.
func _select_least_recently_selected(predicate: Callable) -> Commandable:
	var best: Commandable = null
	for node: Node in get_tree().get_nodes_in_group("commandable"):
		var c: Commandable = node as Commandable
		if c == null or c.commander_id != PLAYER_COMMANDER_ID or c.selectable == null:
			continue
		if not predicate.call(c):
			continue
		if best == null or c.selectable.last_selected_time < best.selectable.last_selected_time:
			best = c

	if best == null:
		return null

	deselect()
	if best.selectable.select():
		selection.append(best)
	available_commands = CommandContextParser.commands_for_selection(selection)
	unit_selected.emit(best)
	if camera != null:
		camera.center_on(VU.inXZ(best.global_position))
	return best
#endregion

#region Screen queries
## Returns the subset of `commandables` that are currently on screen. A
## commandable is "on screen" when its selection shape is at all visible in the
## camera's orthographic view — i.e. the projected extent of its Selectable
## sphere overlaps the viewport rectangle (partially-visible units count).
func commandables_on_screen(commandables: Array) -> Array:
	if camera == null:
		return []
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return commandables.filter(
		func(c: Variant) -> bool:
			return c is Commandable and _selection_shape_in_view(c as Commandable, viewport_rect)
	)

## True when the commandable's selection shape projects onto `viewport_rect` at
## all (any overlap — a partially-visible shape still counts as on screen).
func _selection_shape_in_view(commandable: Commandable, viewport_rect: Rect2) -> bool:
	if commandable == null or commandable.selectable == null:
		return false
	var shape_node: CollisionShape3D = _selection_shape_node(commandable.selectable)
	if shape_node == null:
		return false
	var center: Vector3 = shape_node.global_position
	# unproject_position is meaningless for points behind the lens; a shape there
	# is not on screen. (An overhead ortho RTS camera never puts field units
	# behind it, but guard anyway.)
	if camera.is_position_behind(center):
		return false

	# World radius of the selection sphere, scaled by the shape's world scale.
	# Non-sphere shapes fall back to a point test (radius 0).
	var world_radius: float = 0.0
	if shape_node.shape is SphereShape3D:
		world_radius = (shape_node.shape as SphereShape3D).radius \
			* shape_node.global_transform.basis.x.length()

	# Screen-space radius: project a point one world-radius to the camera's right
	# and measure the pixel gap. This derives the on-screen size without assuming
	# the orthographic projection math directly.
	var center_screen: Vector2 = camera.unproject_position(center)
	var edge_screen: Vector2 = camera.unproject_position(
		center + camera.global_transform.basis.x.normalized() * world_radius
	)
	var screen_radius: float = center_screen.distance_to(edge_screen)

	var shape_rect: Rect2 = Rect2(
		center_screen - Vector2(screen_radius, screen_radius),
		Vector2(screen_radius, screen_radius) * 2.0
	)
	return viewport_rect.intersects(shape_rect)

## The CollisionShape3D defining a Selectable's selection area (its first
## CollisionShape3D child), or null.
func _selection_shape_node(selectable: Selectable) -> CollisionShape3D:
	for child: Node in selectable.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
#endregion

#region Command processing
## The control context(s) currently active for tool/command availability, as a
## ControlBinding.ControlContext bitmask: BUILD while the Build sub-menu is armed, otherwise
## the default ACT|TRAIN page. The single place that interprets the controller's
## mode (pending_command_name) as a ControlBinding.ControlContext — shared vocabulary with
## the Tool registry / command_context_parser.tools_for().
func current_context() -> int:
	if pending_command_name == "command_ability":
		return ControlBinding.ControlContext.BUILD
	return ControlBinding.ControlContext.ACT | ControlBinding.ControlContext.TRAIN

## Whether `command_name` is a unit command the current selection can act on right
## now — the gate shared by button visibility, the hotkey dispatcher, and
## process_command itself. False when nothing is selected, and false for
## SELECT-context commands (idle army, etc.), which the dispatcher routes
## separately and which are never gated by the selection.
##
## Gate on _available_commands (the union across the whole selection) rather than
## re-checking selection[0] alone, so a hotkey works whenever its button is shown.
## Build tools (command_tool_dwelling, ...) are the exception: they aren't part of
## a unit's base command set, so they only qualify once the Build sub-menu is armed
## (current_context() == BUILD) and only for structures this builder can place.
func _command_is_available(command_name: String) -> bool:
	if selection.is_empty():
		return false
	if _available_commands.has(command_name):
		return true
	return current_context() == ControlBinding.ControlContext.BUILD \
		and CommandContextParser.tools_for(selection[0], ControlBinding.ControlContext.BUILD).has(command_name)

## Resolves the set of "command_" input actions triggered by one key press to a
## single action to run. A currently-available unit command wins; failing that, a
## SELECT command (idle army, etc.) runs regardless of whether anything is
## selected. So a SELECT hotkey works at any time, yet yields its key to a
## selected unit's verb/tool when they share a binding.
func _dispatch_command_hotkey(command_actions: Array) -> void:
	for command_name: String in command_actions:
		if _command_is_available(command_name):
			process_command(command_name)
			return
	for command_name: String in command_actions:
		if _select_command_handlers.has(command_name):
			_select_command_handlers[command_name].call()
			return

func process_command(command_name: String) -> void:
	if not _command_is_available(command_name):
		return
	var lead: Entity = selection[0]

	var tool: Tool = Tool.for_name(command_name)
	if tool != null:
		command_message.tool = tool
	elif command_name.begins_with("command"):
		# Hotkey commands either fire immediately (no position needed, e.g.
		# command_stop) or arm a pending sub-mode that the next right-click
		# resolves (e.g. command_attack_move → Attack/AttackMove on click).
		pending_command_name = command_name
	else:
		push_error("trying to process unknown action type: %s" % command_name)
		return

	var command: Script = _resolve_command_class(pending_command_name, lead, command_message)

	if command != null and not command.requires_position():
		assign_command_to_units(
			command,
			command_message,
			next_command_additive
		)

	upate_hud_buttons()

## Picks the concrete Command Script class to instantiate given the controller
## state. Replaces CommandContext.evaluate_command and the per-type Pattern
## tables in the old registry. Resolution rules mirror the previous behavior:
##
##   - With `a_pending` set to a hotkey name, we're in a sub-mode armed by
##     that hotkey. Target-sensitive sub-modes (attack_move) still pick a
##     different class based on the cursor target.
##   - With `a_pending` empty (default right-click), we resolve based on
##     actor capability + target. Structures with a tool selected resolve to
##     Train; an interactor-equipped unit targeting an entity it has an
##     interaction for resolves to Interact; hostile targets resolve to Attack;
##     otherwise the basic MoveCommand.
##
## Anything not matched falls through to null, which the caller treats as
## "no valid command right now" (cursor goes invalid, no assignment fires).
static func _resolve_command_class(
	a_pending: String,
	a_actor: Entity,
	a_message: CommandMessage
) -> Variant:
	if a_actor == null:
		return null

	match a_pending:
		"command_stop":
			return Stop
		"command_patrol":
			return Patrol
		"command_defend":
			return Defend
		"command_attack_move":
			if a_message.target != null and a_message.target is Commandable:
				return Attack
			return AttackMove
		"command_ability":
			return Build
		"command_launch":
			# The launch hotkey fires the generic Ability command. The specific
			# ability is carried on the message so Ability can resolve the
			# payload/charges. (Map more hotkeys → Ability.Type here as abilities
			# are added.)
			a_message.ability_type = Ability.Type.RADIATION
			return Ability
		"command_evacuate":
			return Evacuate
		"command_land":
			return Land
		"":
			pass # fall through to default-target resolution below
		_:
			# command_tool_* and other hotkey aliases route through the
			# default resolution: a structure with a tool set picks Train,
			# everything else picks the basic MoveCommand.
			pass

	# Default resolution (no pending hotkey OR a tool-flavored alias).
	var target = a_message.target

	# A producer with a tool selected is deliberately training.
	if a_actor.has_node("Production") and a_message.tool != null:
		return Train

	# An interactor-equipped unit targeting an entity it has an interaction for
	# resolves to Interact. This generalises the former per-type special cases
	# (technician→Star PickUp, technician→Outpost DropOff, vanguard→Lab collect):
	# what a unit can interact with now lives in its Interactor's list, and the
	# Interact precondition gates on encampment availability.
	var actor_cmd := a_actor as Commandable
	if (
		actor_cmd != null
		and actor_cmd.interactor != null
		and target is Entity
		and actor_cmd.interactor.can_interact(actor_cmd, a_message)
	):
		return Interact

	# Builder targeting a friendly under-construction structure → resume
	# construction (Repair). Mirrors the Attack reinterpretation: the click is
	# unambiguous — same-commander, not-yet-built, actor can build that type —
	# so we short-circuit before the generic move/rally fallthrough.
	var target_cmd := target as Commandable
	if (
		target_cmd != null
		and target_cmd.commander_id == a_actor.commander_id
		and not target_cmd.is_built
		and a_actor.has_node("Builds")
		and (a_actor.get_node("Builds") as Builds).can_build(target.id)
	):
		return Repair

	# Garrison target → Occupy (GROUNDED_DIRECT movement units only). Units may
	# occupy a garrison of their own commander OR a commanderless (neutral) one.
	# Inserted before the Attack check so it takes priority over any edge case
	# where a structure could otherwise be attacked.
	if (
		target_cmd != null
		and (target_cmd.commander_id == a_actor.commander_id or target_cmd.commander_id == 0)
		and target_cmd.is_built
		and target.has_node("Garrison")
		and a_actor.has_node("Movement")
		and (a_actor.get_node("Movement") as Movement).mode == Movement.Mode.GROUNDED_DIRECT
	):
		return Occupy

	# Hostile, weapon-matched target → Attack. This must precede the structure
	# rally fallback below so a combatant structure (e.g. Turret) whose
	# can_rally() (Production or Garrison) would otherwise swallow the click as
	# a rally point still resolves an explicit attack order. Entities without a Loadout
	# (or whose weapons can't target this entity) fall through to rally unchanged.
	# A commanderless garrison is excluded: a default right-click on it must not
	# resolve to an attack (units can still attack it via the AttackMove context,
	# resolved above). It falls through to the move/rally fallback instead.
	if (
		target != null
		and target is Commandable
		and (target as Commandable).commander_id != a_actor.commander_id
		and not _is_commanderless_garrison(target)
		and a_actor.weapon_inventory != null
		and a_actor.weapon_inventory.weapon_for_target(target) != null
	):
		return Attack

	# can_rally() structures (producers, garrisons) fall back to rally; units
	# to basic move — both plain MoveCommand (see Commandable._process_commands).
	return MoveCommand

## True when `target` is a built garrison with no commander (neutral, id 0).
## Used to keep a default right-click from resolving to Attack against an
## unowned garrison — such garrisons can be occupied (or attacked explicitly
## via AttackMove), but never attacked by default.
static func _is_commanderless_garrison(target) -> bool:
	var target_cmd := target as Commandable
	return target_cmd != null \
		and target_cmd.commander_id == 0 \
		and target.has_node("Garrison")

func assign_command_to_units(
	a_command_type: Script,
	a_command_message: CommandMessage,
	add_to_queue: bool
) -> bool:
	# Returns whether or not the command was successfully assigned to any units
	selection = selection.filter(func(u): return is_instance_valid(u)) # TODO refactor so I dont have to do this smh

	if selection.size() == 0:
		push_error("no selections")
		_reset_pending_state()
		return false

	if a_command_type == null:
		push_error("supplied a null command")
		_reset_pending_state()
		return false

	# Check preconditions per-unit so that a mixed selection (e.g. Irregulars +
	# Technician) can still execute a command: capable units receive it and
	# incapable units are silently skipped.
	var capable: Array = selection.filter(
		func(c: Commandable) -> bool:
			return a_command_type.meets_precondition(c, a_command_message) == MoveCommand.PreconditionFailureCause.NONE
	)

	if capable.is_empty():
		_reset_pending_state()
		return false

	command_issued.emit(capable[0] as Entity, a_command_type)

	# Any multi-unit command caps every mobile unit's Movement.speed_cap to the
	# slowest one's speed, so a mixed-speed group doesn't stretch out over the trip.
	# Reset when each unit's command is destroyed — completed, cancelled, or replaced
	# (see MoveCommand._notification / CommandReceiver._process_commands).
	var apply_speed_cap: bool = capable.size() > 1
	var slowest: float = 0.0
	if apply_speed_cap:
		var movers: Array = capable.filter(func(c: Commandable) -> bool: return c.movement != null)
		apply_speed_cap = not movers.is_empty()
		if apply_speed_cap:
			slowest = movers.map(func(c: Commandable) -> float: return c.movement.speed).min()
			a_command_message.match_group_speed = true

	# Per-unit destination assignment: map each unit to its own spread-out point
	# so a group move fans the selection out around the click instead of stacking
	# everyone on a single position.
	var destination_to_unit: Dictionary = {}
	if a_command_type.requires_position() and capable.size() > 1:
		var representative := capable[0] as Entity
		var radius: float = representative.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
		var region_radius: float = maxf(5.0, radius * 2.5 * float(capable.size()))
		var destination_centroid: Vector2 = a_command_message.xz_position
		var destinations: Array[Vector2] = SU.get_nonoverlapping_points(
			map,
			destination_centroid,
			radius,
			map.get_world_3d(),
			CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
			region_radius,
			capable.size()
		)

		# Centroid of the current unit positions; used to sort units into the same
		# rotational frame as the destinations so the assignment preserves formation.
		var selection_centroid := Vector2.ZERO
		for c: Commandable in capable:
			selection_centroid += VU.inXZ((c as Entity).global_position)
		selection_centroid /= float(capable.size())

		# Sort destinations by angle around the click point, and units by angle
		# around the group's own centroid, then zip the two sorted sequences
		# together. Two sequences swept in the same rotational order can't cross,
		# so this guarantees non-crossing, formation-preserving paths by
		# construction — replacing the old O(N^2) greedy nearest-free-destination
		# search, which assigned in whatever order the BFS scatter happened to
		# return them and produced crossing paths.
		destinations.sort_custom(
			func(a: Vector2, b: Vector2) -> bool:
				return atan2(a.x - destination_centroid.x, a.y - destination_centroid.y) \
						< atan2(b.x - destination_centroid.x, b.y - destination_centroid.y)
		)
		var sorted_capable: Array = capable.duplicate()
		sorted_capable.sort_custom(
			func(a: Commandable, b: Commandable) -> bool:
				var a_xz: Vector2 = VU.inXZ((a as Entity).global_position)
				var b_xz: Vector2 = VU.inXZ((b as Entity).global_position)
				return atan2(a_xz.x - selection_centroid.x, a_xz.y - selection_centroid.y) \
						< atan2(b_xz.x - selection_centroid.x, b_xz.y - selection_centroid.y)
		)
		# If scatter found fewer points than units, only the first
		# min(destinations, units) get one; the rest fall back to the raw click
		# point via the unit_to_destination.has(c) check below.
		for i: int in mini(destinations.size(), sorted_capable.size()):
			destination_to_unit[destinations[i]] = sorted_capable[i]

	var unit_to_destination: Dictionary = {}
	for destination: Vector2 in destination_to_unit:
		unit_to_destination[destination_to_unit[destination]] = destination

	# For a Defend order, build ONE region collider — a hard copy of the group's widest
	# aggro shape, pinned at the target centre — that every defender scans against. A copy
	# (not a borrowed live unit shape) is required now that aggro is centred on the shape's
	# own position: a borrowed shape would drag the defended region around with its owner.
	# Its lifetime is leased to the issued Defend messages and it frees when the last one is
	# released (see _lease_region_shape).
	var defend_shape: CollisionShape3D = null
	if a_command_type == Defend:
		var center: Vector3 = a_command_message.world_position
		center.y = map.terrain_height_at(a_command_message.xz_position)
		defend_shape = _make_defend_region_shape(_largest_aggro_shape(capable), center)
		a_command_message.aggro_shape = defend_shape

	var defend_messages: Array[CommandMessage] = []
	for c: Commandable in capable:
		if apply_speed_cap and c.movement != null:
			c.movement.speed_cap = slowest
		var snapshot := CommandMessage.deep_copy(a_command_message)
		# Tag every per-unit snapshot with the shared, un-copied message this
		# batch was issued from, so MoveCommand's periodic swap check can find
		# sibling units by comparing origin identity (see CommandMessage.origin).
		snapshot.origin = a_command_message
		if a_command_type == Attack:
			snapshot.persist = true
		if unit_to_destination.has(c):
			var dest_xz: Vector2 = unit_to_destination[c]
			snapshot.world_position = VU.fromXZ(dest_xz)
		snapshot.world_position.y = map.terrain_height_at(snapshot.xz_position)
		if a_command_type.requires_position():
			_register_indicator(snapshot)
		var new_cmd: MoveCommand = Patrol.for_actor(c, snapshot) \
				if a_command_type == Patrol \
				else a_command_type.new(snapshot)
		c.update_commands(new_cmd, add_to_queue)
		if defend_shape != null:
			defend_messages.append(snapshot)

	if defend_shape != null:
		_lease_region_shape(defend_shape, defend_messages)

	if not add_to_queue:
		_reset_pending_state()
		command_message.clear()

	return true

## Issue the player's currently-armed right-click action at a world XZ position,
## as if they had right-clicked that point in the 3D world — but resolving a
## POSITION only, never an entity target. This is the minimap's right-click entry
## point: the minimap knows where on the map was clicked, not which unit sits
## there, so target is left null.
##
## Because target is null, _resolve_command_class only ever yields position-based
## commands (Move, AttackMove, Ability, ...); the target-requiring branches
## (Interact, Occupy, Repair, Attack-on-unit) all fall through to null or resolve
## to something that fails requires_position(). Either way we bail without
## touching the armed context, so a right-click over the minimap while an
## interact-style command is armed is simply ignored — exactly as specified.
func issue_command_at_world_position(world_xz: Vector2) -> void:
	if map == null:
		return
	# An armed ordnance targets a position — fire it at the clicked point, matching
	# the "move" right-click handler in _unhandled_input.
	if _pending_ordnance != null:
		command_message.world_position = _world_point(world_xz)
		_activate_pending_ordnance()
		return

	# Only the player's own units take commands; an enemy/neutral info-selection
	# (or an empty selection) ignores the click.
	if not _selection_owned_by_player():
		return

	var msg: CommandMessage = CommandMessage.new(map)
	msg.world_position = _world_point(world_xz)
	msg.tool = command_message.tool
	msg.ability_type = command_message.ability_type

	var command: Variant = _resolve_command_class(pending_command_name, selection[0], msg)
	# Drop anything that isn't a pure position command: null (nothing resolved),
	# or a command that needs a specific entity target (requires_position() == false,
	# e.g. Stop/Occupy/Interact). The armed context is preserved untouched.
	if command == null or not command.requires_position():
		return
	assign_command_to_units(command, msg, next_command_additive)

## World point at `world_xz`, lifted onto the terrain so waypoint indicators and
## any Y-sensitive consumers sit at the ground height rather than Y=0.
func _world_point(world_xz: Vector2) -> Vector3:
	var p: Vector3 = VU.fromXZ(world_xz)
	p.y = map.terrain_height_at(world_xz)
	return p

## After a command fires (or fails preconditions), drop the controller out of
## any armed sub-mode and refresh the available-commands snapshot. Mirrors
## the old "reset active_command_context to the default for the selection"
## bookkeeping that lived inline at every exit path.
func _reset_pending_state() -> void:
	pending_command_name = ""
	available_commands = CommandContextParser.commands_for_selection(selection)
#endregion

#region HUD
func upate_hud_buttons() -> void:
	# TODO definitely gonna refactor
	var visible_names: Array = _visible_command_names()
	for child: BoxContainer in $CommandsSection/CommandsBorder/CommandsView.get_children():
		for subchild: Button in child.get_children():
			subchild.visible = visible_names.has(subchild.name)

## The command names whose HUD buttons should be visible for the current state.
## Normally the selection's available commands, but once the player arms "Build"
## (command_ability) we drill into the builder's buildable-structure tools so
## they can pick what to place. Issuing or re-selecting clears pending_command_name
## (via _reset_pending_state / deselect), which drops the menu back to the flat
## command set.
func _visible_command_names() -> Array:
	if selection.is_empty():
		# Nothing selected: offer the SELECT-context selectors.
		return _select_command_handlers.keys()
	if current_context() == ControlBinding.ControlContext.BUILD:
		return CommandContextParser.tools_for(selection[0], ControlBinding.ControlContext.BUILD)
	return _available_commands

func _on_control_button_pressed(control_name: String) -> void:
	# The SELECT-context buttons don't act on the current selection — they change
	# it — so they bypass the selection-gated process_command pipeline.
	if _select_command_handlers.has(control_name):
		_select_command_handlers[control_name].call()
		return
	process_command(control_name)
#endregion

#region Private helpers
static func cursor_evaluator(a_command_type: Script, a_command_message: CommandMessage) -> Resource:
	if a_command_type==null or a_command_type==MoveCommand:
		if (a_command_message.target!=null):
			if a_command_message.target.commander.id==PLAYER_COMMANDER_ID:
				return selection_cursor
			else:
				return attack_cursor
		else:
			return free_cursor
	elif a_command_type==Attack or a_command_type==AttackMove:
		return attack_cursor
	else:
		return unknown_cursor

## True when the player can currently perceive `entity` — so the cursor may target
## it. Own units are always known; a fog-tracked Commandable is perceptible only
## while it's in sight (in_sight_range is fog.gd's per-tick "fog pixel clear AND not
## stealthed" flag, so this subsumes both fog and stealth). A fogged enemy — or a
## fogged structure's remembered snapshot, which has no SELECTION collider at all —
## is not detected, so a right-click over it resolves to a Move on the terrain
## beneath. Non-Commandable map features (e.g. neutral Shelters) aren't fog-managed,
## so fall back to their render state (always drawn → still targetable to liberate).
static func _is_perceptible(entity: Entity) -> bool:
	if entity.commander_id == PLAYER_COMMANDER_ID:
		return true
	if entity is Commandable:
		return (entity as Commandable).in_sight_range
	return entity.visible

func get_cursor_target(a_mouse_position: Vector2) -> Variant:
	# Cursor picking raycasts against the Map; with no Map (e.g. running
	# player.tscn standalone to preview the HUD) there is nothing to hit.
	if map == null:
		return null
	var ray_origin: Vector3 = camera.project_ray_origin(a_mouse_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(a_mouse_position) * 1000.0

	var selection_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Mask.SELECTION)
	if selection_hit and selection_hit['collider'] is Selectable:
		var entity := (selection_hit['collider'] as Selectable).get_entity()
		# Only detect entities the player can actually see. Fogged/stealthed enemies
		# are ignored — fall through to the terrain hit so a right-click resolves to a
		# move instead of an attack against something the player can't perceive.
		if entity != null and _is_perceptible(entity):
			return entity

	var terrain_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Mask.TERRAIN)
	if terrain_hit:
		return terrain_hit['position']

	return null

## Show / refresh / hide the translucent build-placement ghost. Called every
## frame from _process. The ghost is visible only while the armed command is
## Build and the player has chosen a Tool; it snaps to the same cell the
## structure would be placed in, so the preview matches the real placement.
func _update_build_preview(is_invalid_placement: bool) -> void:
	var should_show: bool = (
		current_command_type == Build
		and command_message.tool != null
	)
	if not should_show:
		if _build_preview != null and is_instance_valid(_build_preview):
			_build_preview.visible = false
		return

	# (Re)build the ghost sprite when the chosen structure changes.
	if _build_preview == null or not is_instance_valid(_build_preview) \
			or command_message.tool.type != _build_preview_tool_type:
		_rebuild_build_preview(command_message.tool)

	# Snap to the cell the structure would occupy; hide if off-map so we never
	# index the heightmap out of bounds (grid_to_world reads map_data directly).
	var cell: Vector2i = map.world_to_grid(command_message.xz_position)
	if not map.grid_coordinates_in_bounds(cell):
		_build_preview.visible = false
		return

	# Position at the footprint centroid, matching the arithmetic in
	# Map.add_structure, so multi-cell buildings (e.g. 3×3) don't appear
	# offset from where they actually land.
	var lead: Entity = (selection[0] as Entity) if not selection.is_empty() else null
	var commander: Commander = lead.commander if lead != null else null
	var source: Node = commander.get_build_preview_instance(command_message.tool) if commander != null else null
	var obs := source.get_node_or_null("Structure") as Structure if source != null else null
	var dims := obs.dimensions if obs != null else Vector2i.ONE
	var origin := cell - Vector2i((dims.x - 1) / 2, (dims.y - 1) / 2)

	# The centre cell alone can be in-bounds while the rest of a multi-cell
	# footprint spills off the map near an edge — check every cell the
	# structure would occupy, not just its centre, before touching grid_to_world.
	var centroid := Vector3.ZERO
	for w in range(dims.x):
		for l in range(dims.y):
			var footprint_cell := Vector2i(origin.x + w, origin.y + l)
			if not map.grid_coordinates_in_bounds(footprint_cell):
				_build_preview.visible = false
				return
			centroid += map.grid_to_world(footprint_cell)
	_build_preview.global_position = centroid / (dims.x * dims.y)

	# Apply tint: red when placement is invalid, neutral otherwise.
	var tint: Color = Entity.TEAM_COLOR_MAP[commander.id] * (
		BUILD_PREVIEW_INVALID_TINT \
		if is_invalid_placement \
		else BUILD_PREVIEW_VALID_TINT
	)
	for child in _build_preview.get_children():
		if child is Sprite3D:
			child.modulate = tint

	_build_preview.visible = true

## Rebuild the ghost's sprite from the structure's own scene so the preview
## always matches the real building art — including the player's team tint. The
## source is the builder's Commander's live, team-tinted preview instance (kept
## out of the tree, see Commander.get_build_preview_instance), so we don't
## re-instantiate the scene here and the ghost inherits the per-commander
## `modulate` color. We duplicate that Sprite and knock its alpha down to make
## the placement preview translucent.
func _rebuild_build_preview(a_tool: Tool) -> void:
	if _build_preview == null or not is_instance_valid(_build_preview):
		_build_preview = Node3D.new()
		_build_preview.name = "BuildPreview"
		_build_preview.visible = false
		map.get_parent().add_child(_build_preview)

	for child in _build_preview.get_children():
		child.free()
	_build_preview_tool_type = a_tool.type

	var lead: Entity = (selection[0] as Entity) if not selection.is_empty() else null
	var commander: Commander = lead.commander if lead != null else null
	var source: Node = commander.get_build_preview_instance(a_tool) if commander != null else null
	if source == null:
		return
	var sprite := source.get_node_or_null("Sprite") as Sprite3D
	if sprite != null:
		var ghost := sprite.duplicate() as Sprite3D
		ghost.modulate.a = BUILD_PREVIEW_ALPHA
		_build_preview.add_child(ghost)

func _make_indicator() -> WaypointIndicator:
	var ind := WaypointIndicator.new()
	map.add_child(ind)
	ind.visible = false
	return ind

func _register_indicator(msg: CommandMessage) -> void:
	if map == null:
		return
	if _indicator_pool.is_empty():
		_indicator_pool.append(_make_indicator())
	var ind: WaypointIndicator = _indicator_pool.pop_back()
	_active_indicators[msg] = ind
	msg.unreferenced.connect(_on_message_unreferenced.bind(msg), CONNECT_ONE_SHOT)

func _on_message_unreferenced(msg: CommandMessage) -> void:
	var ind = _active_indicators.get(msg)
	if ind == null:
		return
	ind.visible = false
	_active_indicators.erase(msg)
	_indicator_pool.append(ind)

## Show waypoint indicators for the current selection.  Called every frame so
## the line from a moving unit to its first waypoint stays accurate.
func _update_waypoint_display() -> void:
	for ind in _active_indicators.values():
		(ind as WaypointIndicator).visible = false

	if selection.is_empty() or _active_indicators.is_empty():
		return

	# Walk every selected unit's chain so the union of all their active
	# indicators is shown, not just the first representative's.
	var configured: Dictionary = {}  # CommandMessage -> true, prevents double-configure
	for entity in selection:
		if not (entity is Commandable):
			continue
		var unit := entity as Commandable
		var chain := unit.get_command_chain()
		var prev_pos: Vector3 = unit.global_position
		for cmd in chain:
			var msg: CommandMessage = cmd.message
			if _active_indicators.has(msg) and not configured.has(msg):
				var ind: WaypointIndicator = _active_indicators[msg]
				ind.configure(msg.position, prev_pos)
				ind.visible = true
				configured[msg] = true
			prev_pos = msg.position

static func get_action_names_by_prefix(event: InputEvent, event_prefix: String) -> Array:
	return InputMap.get_actions().filter(
		func(action_name: String): return event_prefix in action_name
	).filter(
		func(action_name: String): return event.is_action_pressed(action_name, true)
	)

## Returns the CollisionShape3D with the largest aggro radius among `a_units`.
## Used so a group Defend order scans with the widest aggro coverage available.
static func _largest_aggro_shape(a_units: Array) -> CollisionShape3D:
	var best: CollisionShape3D = null
	var best_radius: float = 0.0
	for c: Commandable in a_units:
		var shape: CollisionShape3D = c.aggro_range_shape
		if shape == null or shape.shape == null:
			continue
		var radius: float = _aggro_shape_radius(shape)
		if radius > best_radius:
			best_radius = radius
			best = shape
	return best

static func _aggro_shape_radius(shape: CollisionShape3D) -> float:
	var s: Shape3D = shape.shape
	if s is SphereShape3D:
		return (s as SphereShape3D).radius
	if s is BoxShape3D:
		return (s as BoxShape3D).size.length()
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).radius
	return 0.0

## Builds a standalone defended-region collider from `template` (the widest group aggro
## shape), pinned at `center`. The geometry is hard-copied so it's independent of the unit
## it came from, and it's added to the tree before positioning because an out-of-tree
## Node3D reports an identity global_transform. Returns null when there's no usable shape.
func _make_defend_region_shape(template: CollisionShape3D, center: Vector3) -> CollisionShape3D:
	if template == null or template.shape == null or map == null:
		return null
	var region: CollisionShape3D = CollisionShape3D.new()
	region.shape = template.shape.duplicate()
	map.add_child(region)
	region.global_transform = Transform3D(Basis.IDENTITY, center)
	return region

## Ties the region collider's lifetime to the Defend messages that reference it: once every
## one has been released (its owning command replaced, the unit reassigned or destroyed),
## nothing is defending the region, so the collider frees. Uses the same per-message
## `unreferenced` signal the waypoint indicators ride. `remaining` is a one-element array so
## the closures share one mutable counter (Arrays are reference types in GDScript).
static func _lease_region_shape(region: CollisionShape3D, messages: Array[CommandMessage]) -> void:
	if messages.is_empty():
		if is_instance_valid(region):
			region.queue_free()
		return
	var remaining: Array[int] = [messages.size()]
	for m: CommandMessage in messages:
		m.unreferenced.connect(func() -> void:
			remaining[0] -= 1
			if remaining[0] <= 0 and is_instance_valid(region):
				region.queue_free()
		, CONNECT_ONE_SHOT)
#endregion

#region Commander ordnances
## Source the ordnance arsenal from the local commander, so what the player sees and
## can unlock/deploy is faction-driven. The controller is a child of its Commander
## node (see player.tscn). One button per DAG node: a locked node is unlocked (for
## dominion) on click; an owned one is armed for targeting.
func _setup_commander_ordnances() -> void:
	var commander: Commander = get_parent() as Commander
	if commander != null:
		_arsenal = commander.ordnance_arsenal
	_setup_ordnance_bar()

func _setup_ordnance_bar() -> void:
	_ordnance_bar = HBoxContainer.new()
	_ordnance_bar.name = "OrdnanceBar"
	_ordnance_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ordnance_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_ordnance_bar.add_theme_constant_override("separation", 8)
	# Offset from the top edge so it doesn't overlap with other UI anchored there
	_ordnance_bar.position = Vector2(0.0, 8.0)
	add_child(_ordnance_bar)

	if _arsenal == null:
		return
	for entry: OrdnanceArsenal.Entry in _arsenal.entries:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140.0, 32.0)
		btn.pressed.connect(_on_ordnance_button_pressed.bind(entry))
		_ordnance_bar.add_child(btn)

func _tick_ordnance_bar(delta: float) -> void:
	if _ordnance_bar == null or _arsenal == null:
		return
	for i: int in _arsenal.entries.size():
		var entry: OrdnanceArsenal.Entry = _arsenal.entries[i]
		entry.ordnance.tick(delta)
		var btn: Button = _ordnance_bar.get_child(i) as Button
		if btn != null:
			_paint_ordnance_button(btn, entry)

## Repaint one ordnance button from its entry's state: locked nodes show their
## unlock cost (enabled only when available + affordable); owned nodes behave like
## the old bar (arm / cooldown / armed).
func _paint_ordnance_button(btn: Button, entry: OrdnanceArsenal.Entry) -> void:
	var ordnance: Ordnance = entry.ordnance
	if not entry.owned:
		if _arsenal.is_available(entry):
			btn.text = "Unlock %s (%d dom)" % [ordnance.ordnance_name, entry.unlock.dominion_cost]
			btn.disabled = not _arsenal.can_afford(entry)
		else:
			btn.text = "%s [locked]" % ordnance.ordnance_name
			btn.disabled = true
	elif _pending_ordnance == ordnance:
		btn.text = "%s [click target]" % ordnance.ordnance_name
		btn.disabled = false
	elif not ordnance.is_ready():
		btn.text = "%s (%.0fs)" % [ordnance.ordnance_name, ordnance.cooldown_remaining()]
		btn.disabled = true
	else:
		btn.text = ordnance.ordnance_name
		btn.disabled = false

## Click handling depends on state: a locked-but-available entry is purchased; an
## owned, ready entry is armed/cancelled for targeting.
func _on_ordnance_button_pressed(entry: OrdnanceArsenal.Entry) -> void:
	if not entry.owned:
		_arsenal.try_unlock(entry)
		return
	if not entry.ordnance.is_ready():
		return
	# Toggle: clicking again cancels.
	_pending_ordnance = entry.ordnance if _pending_ordnance != entry.ordnance else null

func _activate_pending_ordnance() -> void:
	if _pending_ordnance == null or _event_manager == null:
		_pending_ordnance = null
		return
	# Activate on behalf of the local human commander so the event spawns/affects
	# things for the player, not commander 0.
	_pending_ordnance.activate(command_message.world_position, _event_manager, PLAYER_COMMANDER_ID)
	_pending_ordnance = null
#endregion
