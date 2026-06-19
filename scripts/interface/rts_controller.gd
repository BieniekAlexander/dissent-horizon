class_name RTSController extends CanvasLayer

#region Constants
const free_cursor: Resource = preload("res://assets/interface/cursor_free.png")
const selection_cursor: Resource = preload("res://assets/interface/cursor_selection.png")
const attack_cursor: Resource = preload("res://assets/interface/cursor_attack.png")
const unknown_cursor: Resource = preload("res://assets/interface/cursor_unknown.png")
const invalid_cursor: Resource = preload("res://assets/interface/cursor_invalid.png")

# TODO: replace with a reference to the active player's Commander once
# multi-player / hot-seat support is needed. Hardcoded per user request.
const PLAYER_COMMANDER_ID: int = 1

const BUILD_PREVIEW_ALPHA: float = 0.45
const BUILD_PREVIEW_VALID_TINT:   Color = Color(1.0, 1.0, 1.0, BUILD_PREVIEW_ALPHA)
const BUILD_PREVIEW_INVALID_TINT: Color = Color(1.0, 0.25, 0.25, BUILD_PREVIEW_ALPHA)

const _INDICATOR_POOL_SIZE: int = 16
#endregion

#region Signals
signal unit_selected(entity: Entity)
signal command_issued(entity: Entity, command_type: Script)
#endregion

#region Properties
@onready var map: Map = get_tree().current_scene.find_child("Map")
@onready var camera: RTSCamera3D = get_viewport().get_camera_3d()

var cursor_target: Variant = Vector3.ZERO
var mouse_position: Vector2 = Vector2.ZERO

@export var selection_box: ColorRect = ColorRect.new()
@onready var command_message: CommandMessage = CommandMessage.new(map)
@onready var next_command_additive: bool = false
var selection: Array[Node] = []
var select_down_position: Vector2 = Vector2.ZERO
var current_command_type: Script = null

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

## Commander-level abilities available to the player.
var _commander_abilities: Array[CommanderAbility] = []
## Ability armed by the player — the next right-click activates it at that position.
var _pending_ability: CommanderAbility = null
## Horizontal ability bar added to this CanvasLayer at runtime.
var _ability_bar: HBoxContainer = null

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
	upate_hud_buttons()

	selection_box.visible = false
	if !selection_box.is_inside_tree():
		add_child(selection_box)

	for i in range(_INDICATOR_POOL_SIZE):
		_indicator_pool.append(_make_indicator())

	_setup_commander_abilities()

func _process(delta: float) -> void:
	_tick_ability_bar(delta)

	var cursor_result: Variant = get_cursor_target(mouse_position)
	cursor_target = cursor_result
	command_message.target = cursor_result if cursor_result is Entity else null
	command_message.world_position = cursor_result if cursor_result is Vector3 \
		else camera.get_mouse_world_position(mouse_position)

	for i in range(selection.size()-1, -1, -1):
		if not is_instance_valid(selection[i]):
			selection.remove_at(i)

	current_command_type = _resolve_command_class(
		pending_command_name,
		selection[0],
		command_message
	) if !selection.is_empty() else null

	var check: Command.PreconditionFailureCause =  (
		Command.PreconditionFailureCause.NONE
		if current_command_type==null
		else current_command_type.meets_precondition(selection[0] if !selection.is_empty() else null, command_message)
	)

	$CommandErrorMessage.text = Command.precondition_message_map[check]

	if check==Command.PreconditionFailureCause.NONE:
		Input.set_custom_mouse_cursor(cursor_evaluator(current_command_type, command_message))
	elif check==Command.PreconditionFailureCause.COMMAND_PENDING_TOOL:
		# Not a failure — the command is awaiting the player's tool selection, so
		# keep the default cursor rather than flagging an invalid placement.
		Input.set_custom_mouse_cursor(free_cursor)
	else:
		Input.set_custom_mouse_cursor(invalid_cursor)

	_update_build_preview(check == Command.PreconditionFailureCause.INVALID_PLACEMENT)
	_update_waypoint_display()

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
		select_down_position = mouse_position
		selection_box.visible = true
		selection_box.set_size(Vector2.ZERO)
	elif event.is_action_released("isometric_camera_select"):
		selection_box.visible = false
		if !next_command_additive: deselect()
		set_selection(select_down_position, mouse_position)
	elif event.is_action_pressed("command_additive"):
		next_command_additive = true
	elif event.is_action_released("command_additive"):
		next_command_additive = false
	elif get_action_names_by_prefix(event, "command_").size()>0:
		process_command(get_action_names_by_prefix(event, "command_")[0])
	elif event.is_action_pressed("move"):
		if _pending_ability != null:
			_activate_pending_ability()
		else:
			assign_command_to_units(
				current_command_type,
				command_message,
				next_command_additive
			)
#endregion

#region Selection
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

func set_selection(selection_start_position: Vector2, selection_end_position: Vector2):
	var drag_distance = abs(selection_start_position - selection_end_position)
	if drag_distance < Vector2(10, 10):
		var click_target = get_cursor_target(selection_start_position)
		if click_target is Entity and (click_target as Entity).commander_id == PLAYER_COMMANDER_ID:
			if next_command_additive and selection.has(click_target):
				(click_target as Entity).selectable.deselect()
				selection.erase(click_target)
			elif (click_target as Entity).selectable.select():
				selection.append(click_target)
	else:
		for selectable: Selectable in query_box_collisions(Rect2(selection_start_position, selection_end_position - selection_start_position).abs()):
			var entity := selectable.get_entity()
			if entity != null and entity.commander_id == PLAYER_COMMANDER_ID:
				if selectable.select():
					selection.append(entity)

	available_commands = CommandContextParser.commands_for_selection(selection)
	if not selection.is_empty():
		unit_selected.emit(selection[0] as Entity)
#endregion

#region Command processing
func process_command(command_name: String) -> void:
	var lead: Entity = selection[0] if !selection.is_empty() else null
	# Gate on _available_commands (the union across the whole selection) rather
	# than re-checking against selection[0] alone. This keeps the hotkey gate
	# consistent with button visibility: if the button is shown, the hotkey works,
	# regardless of which unit happens to be first in the selection.
	#
	# Build tools (command_tool_outpost, ...) are the exception: they aren't part
	# of a unit's base command set, so they only become selectable once the
	# player has armed the Build sub-menu (pending_command_name == "command_ability")
	# and only for structures this builder can actually place.
	var is_build_tool: bool = (
		pending_command_name == "command_ability"
		and CommandContextParser.build_tools_for(lead).has(command_name)
	)
	if lead == null or (
		not _available_commands.has(command_name)
		and not is_build_tool
	):
		return

	if command_name.contains("tool"):
		command_message.tool = Tool.command_tool_map[command_name]
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
##     otherwise the basic move Command.
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
		"":
			pass # fall through to default-target resolution below
		_:
			# command_tool_* and other hotkey aliases route through the
			# default resolution: a structure with a tool set picks Train,
			# everything else picks the basic Command.
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
		and (a_actor.get_node("Builds") as Builds).can_build(target.type)
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
	# Production component would otherwise swallow the click as a rally point
	# still resolves an explicit attack order. Entities without a Loadout
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

	# Producers fall back to rally; units to basic move — both plain Command.
	return Command

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
			return a_command_type.meets_precondition(c, a_command_message) == Command.PreconditionFailureCause.NONE
	)

	if capable.is_empty():
		_reset_pending_state()
		return false

	command_issued.emit(capable[0] as Entity, a_command_type)

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

		# Centroid of the current unit positions; used to translate destinations
		# back into the selection's frame so the assignment preserves formation.
		var selection_centroid := Vector2.ZERO
		for c: Commandable in capable:
			selection_centroid += VU.inXZ((c as Entity).global_position)
		selection_centroid /= float(capable.size())

		# Greedily assign each destination to the nearest not-yet-assigned unit,
		# comparing against the destination shifted into the selection's frame.
		var unassigned: Array = capable.duplicate()
		for destination: Vector2 in destinations:
			if unassigned.is_empty():
				break
			var formation_anchor: Vector2 = destination - destination_centroid + selection_centroid
			var best_index := 0
			var best_dist := INF
			for i: int in unassigned.size():
				var unit_xz := VU.inXZ((unassigned[i] as Entity).global_position)
				var dist: float = unit_xz.distance_squared_to(formation_anchor)
				if dist < best_dist:
					best_dist = dist
					best_index = i
			destination_to_unit[destination] = unassigned[best_index]
			unassigned.remove_at(best_index)

	var unit_to_destination: Dictionary = {}
	for destination: Vector2 in destination_to_unit:
		unit_to_destination[destination_to_unit[destination]] = destination

	for c: Commandable in capable:
		var snapshot := CommandMessage.deep_copy(a_command_message)
		if unit_to_destination.has(c):
			var dest_xz: Vector2 = unit_to_destination[c]
			snapshot.world_position = VU.fromXZ(dest_xz)
		snapshot.world_position.y = map.terrain_height_at(snapshot.xz_position)
		if a_command_type.requires_position():
			_register_indicator(snapshot)
		c.update_commands(a_command_type.new(snapshot), add_to_queue)

	if not add_to_queue:
		_reset_pending_state()
		command_message.clear()

	return true

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
	for child: BoxContainer in $CommandsView.get_children():
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
		return []
	if pending_command_name == "command_ability":
		return CommandContextParser.build_tools_for(selection[0])
	return _available_commands

func _on_control_button_pressed(control_name: String) -> void:
	process_command(control_name)
#endregion

#region Private helpers
static func cursor_evaluator(a_command_type: Script, a_command_message: CommandMessage) -> Resource:
	if a_command_type==null or a_command_type==Command:
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

## True when `entity` is an enemy unit currently hidden by stealth. These are the
## STEALTHED units Commandable._process renders fully transparent for enemies, so
## the cursor treats them as not-there. Once a detector sees them (REVEALED) or
## combat forces them out (UNSTEALTHED) they become partially/fully visible and
## thus clickable and targetable again.
static func _is_hidden_enemy(entity: Entity) -> bool:
	return entity.stealth != null \
		and entity.stealth.state == Stealth.State.STEALTHED \
		and entity.commander_id != PLAYER_COMMANDER_ID

func get_cursor_target(a_mouse_position: Vector2) -> Variant:
	var ray_origin: Vector3 = camera.project_ray_origin(a_mouse_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(a_mouse_position) * 1000.0

	var selection_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Mask.SELECTION)
	if selection_hit and selection_hit['collider'] is Selectable:
		var entity := (selection_hit['collider'] as Selectable).get_entity()
		# Stealthed enemy units are rendered invisible to the player, so the cursor
		# must ignore them for both selection and targeting — fall through to the
		# terrain hit so a right-click resolves to a move instead of an attack.
		if entity != null and not _is_hidden_enemy(entity):
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
	var centroid := Vector3.ZERO
	for w in range(dims.x):
		for l in range(dims.y):
			centroid += map.grid_to_world(Vector2i(origin.x + w, origin.y + l))
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
#endregion

#region Commander abilities
func _setup_commander_abilities() -> void:
	_commander_abilities = [
		CommanderAbilityAmbush.new(),
		CommanderAbilityIrradiate.new(),
	]
	_setup_ability_bar()

func _setup_ability_bar() -> void:
	_ability_bar = HBoxContainer.new()
	_ability_bar.name = "AbilityBar"
	_ability_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ability_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_bar.add_theme_constant_override("separation", 8)
	# Offset from the top edge so it doesn't overlap with other UI anchored there
	_ability_bar.position = Vector2(0.0, 8.0)
	add_child(_ability_bar)

	for ab: CommanderAbility in _commander_abilities:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120.0, 32.0)
		btn.pressed.connect(_on_ability_button_pressed.bind(ab))
		_ability_bar.add_child(btn)

func _tick_ability_bar(delta: float) -> void:
	if _ability_bar == null:
		return
	for i: int in _commander_abilities.size():
		var ab: CommanderAbility = _commander_abilities[i]
		ab.tick(delta)
		var btn: Button = _ability_bar.get_child(i) as Button
		if btn == null:
			continue
		if _pending_ability == ab:
			btn.text = "%s [click target]" % ab.ability_name
			btn.disabled = false
		elif not ab.is_ready():
			btn.text = "%s (%.0fs)" % [ab.ability_name, ab.cooldown_remaining()]
			btn.disabled = true
		else:
			btn.text = ab.ability_name
			btn.disabled = false

func _on_ability_button_pressed(ab: CommanderAbility) -> void:
	if not ab.is_ready():
		return
	# Toggle: clicking again cancels.
	_pending_ability = ab if _pending_ability != ab else null

func _activate_pending_ability() -> void:
	if _pending_ability == null or _event_manager == null:
		_pending_ability = null
		return
	_pending_ability.activate(command_message.world_position, _event_manager)
	_pending_ability = null
#endregion
