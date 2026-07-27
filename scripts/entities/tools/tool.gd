class_name Tool
extends ControlBinding

## A ControlBinding whose action is to build or train an entity: it adds the
## entity reference (piece id + packed_scene) and a faction UI mask over the
## base binding's command_name / label / grid_position / control_context.
##
## Its BUTTON TEXT is the piece's doc `title` and its two tooltip tiers are
## synthesized from the same doc's stats — all three arrive through tools.json, so
## renaming or rebalancing a piece re-labels and re-describes its button with no code
## or scene edit (see SpecGenerators.tools_json).
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

#endregion

#region Properties
## The piece id (EntityIds StringName) this tool produces or places.
var type: StringName
var packed_scene: PackedScene
## Bitmask of Faction values; surfaced to the collision review via faction_mask().
var faction: int
## For a TRAIN tool, the ids of the structures whose `trains:` list names this piece —
## the only selections whose card can ever draw this button. Empty for BUILD tools, whose
## builders are declared in scenes (Builds.buildable_types) rather than in the docs.
## Surfaced to the collision review via actor_ids().
var producers: Array
## This PRODUCER's cell in row 0 of the PRODUCTION card — the radio button that picks whose
## training the card is showing — or (-1, -1) for a piece that is not a producer.
##
## A SECOND cell, not a reuse of `grid_position`: that one is where this piece's own BUILD
## button sits on a builder's menu, which is a different button in a different list. Authored
## (`ui.context_grid`) rather than packed per selection, because a cell must be a fixed
## property of a piece — a key that trains from a barracks in one selection and a war factory
## in another is exactly what positional hotkeys exist to prevent.
var context_grid: Vector2i = Vector2i(-1, -1)

## True when this piece carries a CHARGED weapon, so every one the commander fields wants
## a docking pad to rearm at. Derived by the importer from the doc's weapon list, and read
## by the HUD's capacity soft gate — which needs the answer every frame and must not
## instantiate the unit scene to get it.
var needs_docking: bool = false
#endregion

#region Lifecycle
## TODO: twelve parameters, all of them one piece's generated facts. The composition rework
## (gdd/systems/authoring/composition-rework.md) is what shortens this — a Tool built from
## the piece's own spec rather than from a positional argument list. `gdlint` reports it
## until then.
func _init(
	a_command_name: String,
	a_type: StringName,
	a_packed_scene: PackedScene,
	a_label: String,
	a_grid_position: Vector2i,
	a_control_context: int,
	a_faction: int,
	a_simple_tooltip: String = "",
	a_verbose_tooltip: String = "",
	a_producers: Array = [],
	a_needs_docking: bool = false,
	a_context_grid: Vector2i = Vector2i(-1, -1)
) -> void:
	# A tool's card follows from what it does, so it is never authored twice: placing a
	# structure is an order given to a UNIT and belongs beside that unit's other orders,
	# while training is what a producer does with energy. See ControlBinding.CommandFamily.
	var command_family: int = CommandFamily.PRODUCTION \
		if (a_control_context & ControlContext.TRAIN) != 0 else CommandFamily.ACTIVE
	super(a_command_name, a_label, a_grid_position, a_control_context,
		a_simple_tooltip, a_verbose_tooltip, command_family)
	type = a_type
	packed_scene = a_packed_scene
	faction = a_faction
	producers = a_producers
	needs_docking = a_needs_docking
	context_grid = a_context_grid

func faction_mask() -> int:
	return faction

func actor_ids() -> Array:
	return producers

## A train button no producer can offer. `producers` is DERIVED from every `trains:` list
## in the docs, so for a TRAIN tool it is complete by construction and an empty one is a
## fact rather than an omission. Never true of a BUILD tool: builders are declared in
## scenes (Builds.buildable_types), which this registry does not read.
func is_orphaned() -> bool:
	return (control_context & ControlContext.TRAIN) != 0 and producers.is_empty()
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
		out[String(command_name)] = from_entry(String(command_name), e, scene)
	return out

## One tools.json entry as a Tool. `scene` is passed in rather than loaded here so the spec
## importer can build its not-yet-written entries (with a null scene) to review the grid
## before it writes anything — see SpecGenerators.grid_collisions.
static func from_entry(command_name: String, e: Dictionary, scene: PackedScene) -> Tool:
	var mask: int = 0
	for fname in e.get("factions", []):
		var key: String = str(fname).to_upper()
		if Faction.has(key):
			mask |= Faction[key]
		else:
			# Loud, because the fallback below is the permissive one: an unrecognised name
			# widens the tool to every faction and so makes it collide with everything in its
			# cell. Add the member to Faction rather than living with the error.
			push_error("Tool: %s has unknown ui faction '%s' — add it to ControlBinding.Faction" \
				% [command_name, fname])
	if mask == 0:
		mask = ControlBinding.FACTION_ANY
	var producer_ids: Array = []
	for p in e.get("producers", []):
		producer_ids.append(StringName(str(p)))
	return Tool.new(
		command_name,
		StringName(str(e["id"])),
		scene,
		str(e["label"]),
		Vector2i(int(e["grid"][0]), int(e["grid"][1])),
		ControlContext.BUILD if str(e["context"]) == "BUILD" else ControlContext.TRAIN,
		mask,
		str(e.get("tooltip", "")),
		str(e.get("verbose", "")),
		producer_ids,
		bool(e.get("needs_docking", false)),
		_cell(e.get("context_grid", []))
	)

## A generated [x, y] pair as a cell, or (-1, -1) when the list is absent or malformed.
static func _cell(value: Variant) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1])) \
		if value is Array and value.size() == 2 else Vector2i(-1, -1)

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
static func for_name(command_name: String) -> Tool:
	return command_tool_map.get(command_name)

## The Tool that produces/places this piece id, or null.
static func for_id(id: StringName) -> Tool:
	return _by_id().get(id)

## Back-compat alias for for_id (the field is still named `type`).
static func for_type(id: StringName) -> Tool:
	return for_id(id)

## Tools (in registry order) whose control_context intersects the given context
## bitmask. The single context filter used by command_context_parser.tools_for().
static func tools_in_context(context: int) -> Array:
	var out: Array = []
	for t: Tool in command_tool_map.values():
		if (t.control_context & context) != 0:
			out.append(t)
	return out
#endregion
