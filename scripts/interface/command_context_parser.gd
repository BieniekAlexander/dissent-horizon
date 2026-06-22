class_name CommandContextParser

## Maps boolean-valued predicates over Entity to the names of commands that
## may be issued to entities matching the predicate. Replaces the previous
## CommandContextRegistry (which keyed pre-built CommandContexts by
## Entity.Type) and CommandContextProvider (whose only job was to look up
## that registry from a component node).
##
## Each rule is a 2-tuple of [predicate, command_name]:
##   - predicate: Callable taking a single Entity and returning bool. The
##     predicate decides whether `command_name` is applicable to that entity.
##     Predicates are intentionally free-form about *what* they inspect — type
##     enum, has_node(...) for a component, group membership, inventory, etc.
##     The contract is just "given an Entity, return a bool", which keeps the
##     table easy to refactor later if we standardize on one signal.
##   - command_name: String. The command's conventional name. Verb commands
##     (e.g. "command_attack_move") match the controller's input actions; tool
##     names (e.g. "command_tool_irregular") are HUD/registry ids defined in Tool
##     and are NOT input actions. Non-hotkey commands (Attack, Train, Interact,
##     ...) are also listed under "command_<verb>" names so the parser is the
##     single source of truth for the command set a unit supports.
##
## Example entry shape:
##   [func(e: Entity): return e.has_node("Movement"), "command_attack_move"]

## Tool names come from the Tool registry, filtered per control context +
## per-entity capability by tools_for(entity, context) below (ControlBinding.ControlContext
## is the single build/train/act vocabulary, shared with RTSController). They used
## to be hardcoded here as two name lists; the registry is the source of truth.

#region Private helpers
## Built lazily on first lookup to match the lazy pattern the old
## CommandContextRegistry used (script-class resolution order is fragile at
## static-var init time). Note that the structures' *train tools* are no longer
## in this table — they're sourced per-entity from the Production component via
## tools_for(entity, ControlContext.TRAIN), folded into commands_for() below.
static var _rules: Array

static func _build_rules() -> Array:
	return [
		[func(e: Entity): return e.has_node("Movement"), "command_move"],
		[func(e: Entity): return e.has_node("Movement") or e.has_node("Loadout"), "command_stop"],
		[func(e: Entity): return e.has_node("Loadout"), "command_attack"],
		[func(e: Entity): return e.has_node("Loadout"), "command_attack_move"],
		[func(e: Entity): return e.has_node("Movement"), "command_patrol"],
		[func(e: Entity): return e.has_node("Movement") and e.has_node("Loadout"), "command_defend"],

		[func(e: Entity): return e.has_node("Production"), "command_train"],
		[func(e: Entity): return e.has_node("Production"), "command_move"], # rally

		[func(e: Entity): return e.has_node("Builds"), "command_ability"],
		[func(e: Entity): return e.has_node("Builds"), "command_build"],

		[func(e: Entity): return e.has_node("Inventory") \
				and (e.get_node("Inventory") as Inventory).has_ability(Ability.Type.RADIATION),
			"command_launch"],
		# Any unit with an Interactor advertises the generalised interact command;
		# the specific targets it applies to come from the interactor's list
		# (replaces the former per-type pick_up / drop_off / collect rules).
		[func(e: Entity): return e.has_node("Interactor"), "command_interact"],

		# Occupy applies only to entities with GROUNDED_DIRECT-mode Movement (see _can_occupy).
		[CommandContextParser._can_occupy, "command_occupy"],
		# Commandables that own a Garrison can order an evacuation.
		[func(e: Entity): return e.has_node("Garrison"), "command_evacuate"],
		# HOVERING units that are not already permanently grounded can land.
		[CommandContextParser._can_land, "command_land"],
	]

## Occupy applies only to entities that actually have a Movement component
## whose mode is GROUNDED_DIRECT. Pulled out of the rules table as a named predicate so
## the Movement requirement is explicit and the mode read is null-safe: a
## non-Movement node (or none) makes the cast null and the predicate false,
## rather than crashing on a blind `.mode` access.
static func _can_occupy(e: Entity) -> bool:
	var movement := e.get_node_or_null("Movement") as Movement
	return movement != null and movement.mode == Movement.Mode.GROUNDED_DIRECT

static func _can_land(e: Entity) -> bool:
	var movement := e.get_node_or_null("Movement") as Movement
	return movement != null and movement.mode == Movement.Mode.HOVERING \
		and not movement.is_permanently_grounded()

static func _rules_table() -> Array:
	if _rules == null or _rules.is_empty():
		_rules = _build_rules()
	return _rules
#endregion

#region Public API
## Returns the deduplicated list of command names applicable to a single
## entity, preserving the order they appear in the rules table. Returns an
## empty array for a null / invalid entity rather than erroring — callers
## (the HUD, the controller's hotkey gate) treat "no entity → no commands"
## as the non-selection state.
static func commands_for(a_entity: Entity) -> Array:
	var result: Array = []
	if a_entity == null or not is_instance_valid(a_entity):
		return result
	for rule in _rules_table():
		var predicate: Callable = rule[0]
		var command_name: String = rule[1]
		if not result.has(command_name) and predicate.call(a_entity):
			result.append(command_name)
	# The train tools a producer offers come from its Production component, not a
	# static type table — so a structure advertises exactly what it can build.
	for tool_name in tools_for(a_entity, ControlBinding.ControlContext.TRAIN):
		if not result.has(tool_name):
			result.append(tool_name)
	return result

## Union of `commands_for` across a selection. A command is available to the
## selection if *any* member can issue it — matches the original
## CommandContext.merge behavior, which OR'd evaluators across selected
## types.
static func commands_for_selection(a_entities: Array) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for e in a_entities:
		if not (e is Entity) or not is_instance_valid(e):
			continue
		for command_name in commands_for(e):
			if not seen.has(command_name):
				seen[command_name] = true
				result.append(command_name)
	return result

## Convenience predicate the controller calls for the HUD-button visibility
## check and the "is this hotkey allowed right now" gate inside
## process_command(). Equivalent to `command_name in commands_for(entity)`
## but written out for readability at call sites.
static func command_available(a_command_name: String, a_entity: Entity) -> bool:
	return commands_for(a_entity).has(a_command_name)

## The tool command names available to `a_entity` in the given control context(s),
## in menu order. Single context-filtered query that replaces the former
## build_tools_for / train_tools_for split:
##   - candidate tools are those whose control_context intersects `a_context`
##     (Tool.tools_in_context);
##   - each is then gated by the component that owns that capability — BUILD tools
##     by the entity's Builds (via Build.tool_applies_to), TRAIN tools by its
##     Production (can_produce) — so the menu can never advertise a tool the
##     command would reject.
## The gate DISPATCH lives here; the gate logic itself stays in Build / Production.
## Returns empty for a null/invalid entity, or one lacking the relevant component.
static func tools_for(a_entity: Entity, a_context: int) -> Array:
	var result: Array = []
	if a_entity == null or not is_instance_valid(a_entity):
		return result
	var production := a_entity.get_node_or_null("Production") as Production
	for tool: Tool in Tool.tools_in_context(a_context):
		if (tool.control_context & ControlBinding.ControlContext.BUILD) != 0:
			if Build.tool_applies_to(tool.command_name, a_entity):
				result.append(tool.command_name)
		elif (tool.control_context & ControlBinding.ControlContext.TRAIN) != 0:
			if production != null and production.can_produce(tool.type):
				result.append(tool.command_name)
	return result
#endregion
