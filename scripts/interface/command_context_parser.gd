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
##   - command_name: String. The conventional name of a command that can be
##     issued; matches the input-action and HUD button names already used by
##     the controller (e.g. "command_attack_move", "command_tool_irregular").
##     Non-hotkey commands (Attack, Train, PickUp, ...) are also listed here
##     under "command_<verb>" names so the parser is the single source of
##     truth for the command set a unit supports.
##
## Example entry shape:
##   [func(e: Entity): return e.has_node("Movement"), "command_attack_move"]

#region Constants
## Every unit any producer could ever train. Filtered per-entity by
## train_tools_for(), which consults the entity's Production component. Kept as a
## flat list (rather than rule-table entries) so the capability lives entirely in
## Production: this is just the name↔Tool bridge the HUD needs.
const TRAIN_TOOL_NAMES: Array = [
	"command_tool_technician",
	"command_tool_irregular",
	"command_tool_vanguard",
]

## Every structure a builder could ever place. Filtered per-entity by
## build_tools_for(). Kept separate from the rules table because build tools are
## NOT part of a unit's base command set — structures surface their *train*
## tools directly in the flat HUD, whereas these live behind the controller's
## "Build" (command_ability) sub-menu and are queried on demand.
const BUILD_TOOL_NAMES: Array = [
	"command_tool_outpost",
	"command_tool_dwelling",
	"command_tool_mine",
	"command_tool_lab",
	"command_tool_compound",
	"command_tool_armory",
	"command_tool_turret",
]
#endregion

#region Private helpers
## Built lazily on first lookup to match the lazy pattern the old
## CommandContextRegistry used (script-class resolution order is fragile at
## static-var init time). Note that the structures' *train tools* are no longer
## in this table — they're sourced per-entity from the Production component via
## train_tools_for(), folded into commands_for() below.
static var _rules: Array

static func _build_rules() -> Array:
	return [
		[func(e: Entity): return e.has_node("Movement"), "command_move"],
		[func(e: Entity): return e.has_node("Movement") or e.has_node("Loadout"), "command_stop"],
		[func(e: Entity): return e.has_node("Loadout"), "command_attack"],
		[func(e: Entity): return e.has_node("Loadout"), "command_attack_move"],

		[func(e: Entity): return e.has_node("Production"), "command_train"],
		[func(e: Entity): return e.has_node("Production"), "command_move"], # rally

		[func(e: Entity): return e.has_node("Builds"), "command_ability"],
		[func(e: Entity): return e.has_node("Builds"), "command_build"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_pick_up"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_drop_off"],

		[func(e: Entity): return e.has_node("Inventory") \
				and (e.get_node("Inventory") as Inventory).has_ability(Ability.Type.RADIATION),
			"command_launch"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_VANGUARD, "command_collect"],

		# Garrison applies only to entities with GROUNDED_DIRECT-mode Movement (see _can_garrison).
		[CommandContextParser._can_garrison, "command_garrison"],
		# Commandables that own a Shelter can order an evacuation.
		[func(e: Entity): return e.has_node("Shelter"), "command_evacuate"],
	]

## Garrison applies only to entities that actually have a Movement component
## whose mode is GROUNDED_DIRECT. Pulled out of the rules table as a named predicate so
## the Movement requirement is explicit and the mode read is null-safe: a
## non-Movement node (or none) makes the cast null and the predicate false,
## rather than crashing on a blind `.mode` access.
static func _can_garrison(e: Entity) -> bool:
	var movement := e.get_node_or_null("Movement") as Movement
	return movement != null and movement.mode == Movement.Mode.GROUNDED_DIRECT

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
	for tool_name in train_tools_for(a_entity):
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

## The train-tool command names the given entity can produce, in menu order.
## Source of truth is the entity's Production component (producible_types), so the
## menu can only ever advertise units that structure can actually train. Returns
## empty for entities without a Production node (e.g. units, neutral structures).
static func train_tools_for(a_entity: Entity) -> Array:
	var result: Array = []
	if a_entity == null or not is_instance_valid(a_entity):
		return result
	var production := a_entity.get_node_or_null("Production") as Production
	if production == null:
		return result
	for tool_name in TRAIN_TOOL_NAMES:
		var tool: Tool = Tool.command_tool_map.get(tool_name)
		if tool != null and production.can_produce(tool.type):
			result.append(tool_name)
	return result

## The build-tool command names the given entity can construct, in menu order.
## Drives the controller's Build sub-menu and gates build-tool clicks. Source of
## truth is the entity's Builds component, so the menu can never advertise a
## structure the command would reject.
static func build_tools_for(a_entity: Entity) -> Array:
	var result: Array = []
	if a_entity == null or not is_instance_valid(a_entity):
		return result
	for tool_name in BUILD_TOOL_NAMES:
		if Build.tool_applies_to(tool_name, a_entity):
			result.append(tool_name)
	return result
#endregion
