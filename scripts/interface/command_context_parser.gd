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
##     the controller (e.g. "command_attack_move", "command_tool_sentry").
##     Non-hotkey commands (Attack, Train, PickUp, ...) are also listed here
##     under "command_<verb>" names so the parser is the single source of
##     truth for the command set a unit supports.
##
## Example entry shape:
##   [func(e: Entity): return e.has_node("Movement"), "command_attack_move"]

## Built lazily on first lookup — the predicates reference Command subclasses
## (Train.tool_applies_to in particular) whose script classes resolve in load
## order, so building the table at static-var init time is fragile. This
## matches the lazy pattern the old CommandContextRegistry used for the same
## reason.
static var _rules: Array

static func _build_rules() -> Array:
	return [
		# --- Movement-bearing entities (units): nav-flavored commands.
		[func(e: Entity): return e.has_node("Movement"), "command_move"],
		[func(e: Entity): return e.has_node("Movement") or e.has_node("AttackRange"), "command_stop"],
		[func(e: Entity): return e.has_node("AttackRange"), "command_attack"],
		[func(e: Entity): return e.has_node("AttackRange"), "command_attack_move"],

		# --- Production-bearing entities (structures): training + rally.
		[func(e: Entity): return e.has_node("Production"), "command_train"],
		[func(e: Entity): return e.has_node("Production"), "command_move"], # rally
		[func(e: Entity): return Train.tool_applies_to("command_tool_outpost", e.type), "command_tool_outpost"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_dwelling", e.type), "command_tool_dwelling"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_mine", e.type), "command_tool_mine"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_lab", e.type), "command_tool_lab"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_compound", e.type), "command_tool_compound"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_armory", e.type), "command_tool_armory"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_technician", e.type), "command_tool_technician"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_sentry", e.type), "command_tool_sentry"],
		[func(e: Entity): return Train.tool_applies_to("command_tool_vanguard", e.type), "command_tool_vanguard"],

		# --- Technician (Anima): Star pickup/dropoff and the Build ability.
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_ability"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_build"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_pick_up"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_TECHNICIAN, "command_drop_off"],

		# --- Vanguard: Lab-targeted Collect and the Launch ability.
		[func(e: Entity): return e.type == Entity.Type.UNIT_VANGUARD, "command_launch"],
		[func(e: Entity): return e.type == Entity.Type.UNIT_VANGUARD, "command_collect"],
	]

static func _rules_table() -> Array:
	if _rules == null or _rules.is_empty():
		_rules = _build_rules()
	return _rules

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
]

## The build-tool command names the given entity can construct, in menu order.
## Drives the controller's Build sub-menu and gates build-tool clicks. Source of
## truth is Build.tool_applies_to (the same table Build itself consults), so the
## menu can never advertise a structure the command would reject.
static func build_tools_for(a_entity: Entity) -> Array:
	var result: Array = []
	if a_entity == null or not is_instance_valid(a_entity):
		return result
	for tool_name in BUILD_TOOL_NAMES:
		if Build.tool_applies_to(tool_name, a_entity.type):
			result.append(tool_name)
	return result
