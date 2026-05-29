class_name RTSController extends CanvasLayer

## GAME STATE
@onready var map: Map = get_tree().current_scene.find_child("Map")


## CAMERA
@onready var camera: RTSCamera3D = get_viewport().get_camera_3d()


## MOUSE
### VISUALS
const free_cursor: Resource = preload("res://assets/interface/cursor_free.png")
const selection_cursor: Resource = preload("res://assets/interface/cursor_selection.png")
const attack_cursor: Resource = preload("res://assets/interface/cursor_attack.png")
const unknown_cursor: Resource = preload("res://assets/interface/cursor_unknown.png")
const invalid_cursor: Resource = preload("res://assets/interface/cursor_invalid.png")

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

### GAMESTATE
var cursor_target: Variant = Vector3.ZERO
var mouse_position: Vector2 = Vector2.ZERO

func get_cursor_target(a_mouse_position: Vector2) -> Variant:
	var ray_origin: Vector3 = camera.project_ray_origin(a_mouse_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(a_mouse_position) * 1000.0

	var selection_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Layer.SELECTION)
	if selection_hit and selection_hit['collider'] is Selectable:
		return (selection_hit['collider'] as Selectable).get_entity()

	var terrain_hit = map.line_hit(ray_origin, ray_end, CollisionLayers.Layer.TERRAIN)
	if terrain_hit:
		return terrain_hit['position']

	return null


## CONTROL VARIABLES
# TODO: replace with a reference to the active player's Commander once
# multi-player / hot-seat support is needed. Hardcoded per user request.
const PLAYER_COMMANDER_ID: int = 1

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

## NODE
func _ready():
	Input.set_custom_mouse_cursor(free_cursor)
	upate_hud_buttons()
	
	selection_box.visible = false
	if !selection_box.is_inside_tree():
		add_child(selection_box)

func _process(delta: float) -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	## MOUSE MOVEMENT
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
	# UNIT SELECTION
	elif event.is_action_pressed("isometric_camera_select"):
		select_down_position = mouse_position
		selection_box.visible = true
		selection_box.set_size(Vector2.ZERO)
	elif event.is_action_released("isometric_camera_select"):
		selection_box.visible = false
		if !next_command_additive: deselect()
		set_selection(select_down_position, mouse_position)
	## QUEUING
	elif event.is_action_pressed("command_additive"):
		next_command_additive = true
	elif event.is_action_released("command_additive"):
		next_command_additive = false
	## COMMAND CONTEXT UPDATES
	elif get_action_names_by_prefix(event, "command_").size()>0:
		process_command(get_action_names_by_prefix(event, "command_")[0])
	# ISSUING COMMANDS
	elif event.is_action_pressed("move"):
		assign_command_to_units(
			current_command_type,
			command_message,
			next_command_additive
		)

## CONTEXT SETTING
func process_command(command_name: String) -> void:
	var lead: Entity = selection[0] if !selection.is_empty() else null
	# Both the tool-set branch and the hotkey branch require that the command
	# actually applies to the current selection. The parser is the single
	# source of truth — replaces the old CommandContext.command_available /
	# CommandContext.get_new_context dispatch.
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
		not CommandContextParser.command_available(command_name, lead)
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
##     Train; technician/vanguard special targets resolve to PickUp/DropOff/
##     Collect; hostile targets resolve to Attack; otherwise the basic move
##     Command.
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
			# Anima's Build sub-context.
			return Build
		"command_launch":
			return Launch
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

	# Unit-flavored special targets take priority over the generic attack.
	if a_actor.type == Entity.Type.UNIT_VANGUARD and target is Lab:
		return Collect
	if a_actor.type == Entity.Type.UNIT_TECHNICIAN:
		if target is Star:
			return PickUp
		if (
			target is Entity
			and (target as Entity).type == Entity.Type.STRUCTURE_OUTPOST
			and not a_actor.inventory.is_empty()
			and a_actor.inventory[0] is Star
		):
			return DropOff

	# Hostile, weapon-matched target → Attack. This must precede the structure
	# rally fallback below so a combatant structure (e.g. Turret) whose
	# Production component would otherwise swallow the click as a rally point
	# still resolves an explicit attack order. Non-combatant structures have
	# empty weapon patterns, so Pattern.eval returns null and they fall
	# through to rally unchanged.
	if (
		target != null
		and target is Commandable
		and (target as Commandable).commander_id != a_actor.commander_id
		and Pattern.eval(WeaponPatternsRegistry.for_type(a_actor.type), target) != null
	):
		return Attack

	# Producers fall back to rally; units to basic move — both plain Command.
	return Command

## Return all Selectable nodes whose projected screen position falls within screen_rect.
func query_box_collisions(screen_rect: Rect2) -> Array:
	return get_tree().get_nodes_in_group("selectables").filter(
		func(selectable: Selectable) -> bool:
			return screen_rect.has_point(camera.unproject_position(selectable.global_position))
	)

## SELECTION
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
			if (click_target as Entity).selectable.select():
				selection.append(click_target)
	else:
		for selectable: Selectable in query_box_collisions(Rect2(selection_start_position, selection_end_position - selection_start_position).abs()):
			var entity := selectable.get_entity()
			if entity != null and entity.commander_id == PLAYER_COMMANDER_ID:
				if selectable.select():
					selection.append(entity)

	available_commands = CommandContextParser.commands_for_selection(selection)

## SETTING COMMANDS
# TODO: unused function
#func cancel_command_for_units() -> void:
#	var selection = selection.filter(func(u): return is_instance_valid(u)) # TODO refactor so I dont have to do this smh
#
#	if selection.size()==0:
#		return
#
#	for c: Commandable in selection:
#		c.update_commands(
#			null,
#			false
#		)

func assign_command_to_units(
	a_command_type: Script,
	a_command_message: CommandMessage,
	add_to_queue: bool
) -> bool:
	# Returns whether or not the command was successfully assigned to any units
	selection = selection.filter(func(u): return is_instance_valid(u)) # TODO refactor so I dont have to do this smh
	
	if selection.size()==0:
		push_error("no selections")
		_reset_pending_state()
		return false

	if a_command_type==null:
		push_error("supplied a null command")
		_reset_pending_state()
		return false
	else:
		var check: Command.PreconditionFailureCause = a_command_type.meets_precondition(selection[0], a_command_message)

		if check!=Command.PreconditionFailureCause.NONE:
			_reset_pending_state()
			return false
		else:
			var new_command: Command = a_command_type.new(a_command_message)

			for c: Commandable in selection:
				c.update_commands(
					new_command,
					add_to_queue
				)

	if !add_to_queue:
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


## UTILS
static func get_action_names_by_prefix(event: InputEvent, event_prefix: String) -> Array:
	return InputMap.get_actions().filter(
		func(action_name: String): return event_prefix in action_name
	).filter(
		func(action_name: String): return event.is_action_pressed(action_name, true)
	)


## HUD
### HUD updates
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

### HUD signals
func _on_control_button_pressed(control_name: String) -> void:
	process_command(control_name)
