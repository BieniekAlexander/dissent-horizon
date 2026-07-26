class_name Tool
extends ControlBinding

## A ControlBinding whose action is to build or train an entity: it adds the
## entity reference (piece id + packed_scene) and a faction UI mask over the
## base binding's command_name / label / grid_position / control_context.
##
## command_tool_map is BUILT FROM GENERATED DATA: resources/generated/tools.json,
## which the spec importer derives from each piece doc's `ui:` frontmatter (see
## tools/spec_import). To add a buildable/trainable thing, give its gdd doc a
## `ui:` key and re-run the importer — no code edit. Other systems read the
## registry through the typed lookups below:
##   - command_context_parser.gd   -> tools_in_context(context) (via tools_for)
##   - command_grid.gd             -> the registry feeds the grid alongside verbs
##   - build.gd / rts_controller.gd-> for_name(name) / ControlContext
##   - bot.gd / bot_actuator.gd / bot_economy.gd -> for_id(id)

#region Constants
const TOOLS_JSON_PATH: String = "res://resources/generated/tools.json"

## UI-layout faction grouping, as a bitmask (overrides ControlBinding's
## all-factions default via faction_mask()). This is BUTTON-GRID metadata for
## the collision review — two tools may share a grid cell only if their faction
## masks are disjoint. It is NOT a gameplay gate: piece availability is
## technology (structures owned), never a faction tag. Names mirror the doc
## `ui.factions` strings, uppercased.
enum Faction {
	NEUTRAL     = 1 << 0,
	TECHNOCRACY = 1 << 1,
	ANARCHISTS  = 1 << 2,
	COLLECTIVE  = 1 << 3,
	FACTION_E   = 1 << 4,
	FACTION_F   = 1 << 5,
	FACTION_G   = 1 << 6,
	FACTION_H   = 1 << 7,
}
#endregion

#region Properties
## The piece id (EntityIds StringName) this tool produces or places.
var type: StringName
var packed_scene: PackedScene
## Bitmask of Faction values; surfaced to the collision review via faction_mask().
var faction: int
#endregion

#region Lifecycle
func _init(
	a_command_name: String,
	a_type: StringName,
	a_packed_scene: PackedScene,
	a_label: String,
	a_grid_position: Vector2i,
	a_control_context: int,
	a_faction: int
) -> void:
	super(a_command_name, a_label, a_grid_position, a_control_context)
	type = a_type
	packed_scene = a_packed_scene
	faction = a_faction

func faction_mask() -> int:
	return faction
#endregion

#region Registry
## SINGLE SOURCE OF TRUTH (name -> Tool), loaded from the generated tools.json
## on first access. Godot dicts keep insertion order; entries are alphabetical
## by command name (the generator's order).
static var command_tool_map: Dictionary = _load_registry()

static func _load_registry() -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(TOOLS_JSON_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Tool: cannot load %s — run the spec importer" % TOOLS_JSON_PATH)
		return out
	for command_name in parsed:
		var e: Dictionary = parsed[command_name]
		var scene: PackedScene = load(str(e["scene"]))
		if scene == null:
			push_error("Tool: %s scene missing: %s" % [command_name, e["scene"]])
			continue
		var mask: int = 0
		for fname in e.get("factions", []):
			var key: String = str(fname).to_upper()
			if Faction.has(key):
				mask |= Faction[key]
			else:
				push_error("Tool: %s has unknown ui faction '%s'" % [command_name, fname])
		if mask == 0:
			mask = ControlBinding.FACTION_ANY
		out[String(command_name)] = Tool.new(
			String(command_name),
			StringName(str(e["id"])),
			scene,
			str(e["label"]),
			Vector2i(int(e["grid"][0]), int(e["grid"][1])),
			ControlContext.BUILD if str(e["context"]) == "BUILD" else ControlContext.TRAIN,
			mask
		)
	return out

## piece id -> Tool. Lazily built; cached after first use.
static var _by_id_cache: Dictionary = {}

static func _by_id() -> Dictionary:
	if _by_id_cache.is_empty():
		for t: Tool in command_tool_map.values():
			_by_id_cache[t.type] = t
	return _by_id_cache
#endregion

#region Lookups
## The Tool with this command name, or null.
static func for_name(a_command_name: String) -> Tool:
	return command_tool_map.get(a_command_name)

## The Tool that produces/places this piece id, or null.
static func for_id(a_id: StringName) -> Tool:
	return _by_id().get(a_id)

## Back-compat alias for for_id (the field is still named `type`).
static func for_type(a_id: StringName) -> Tool:
	return for_id(a_id)

## Tools (in registry order) whose control_context intersects the given context
## bitmask. The single context filter used by command_context_parser.tools_for().
static func tools_in_context(a_context: int) -> Array:
	var out: Array = []
	for t: Tool in command_tool_map.values():
		if (t.control_context & a_context) != 0:
			out.append(t)
	return out
#endregion
