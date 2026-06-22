class_name Tool

## A buildable/trainable entity as it appears in the HUD + command pipeline.
##
## The `command_tool_map` below is the SINGLE SOURCE OF TRUTH for these: to add a
## new unit/structure to the HUD, add one entry here (plus its scene and the
## per-entity Builds/Production gate). Every other system reads it through the
## typed lookups in this file rather than re-listing tool names or hand-rolling
## type→tool scans:
##   - command_context_parser.gd     -> build_tool_names() / train_tool_names()
##   - command_grid.gd (ButtonSpec)  -> label_for(name)
##   - build.gd / rts_controller.gd  -> for_name(name)
##   - bot.gd / bot_actuator.gd / bot_economy.gd -> for_type(type)

#region Constants
## How a tool surfaces in the HUD. BUILD tools (structures) sit behind the
## controller's "Build" sub-menu; TRAIN tools (units) appear in a producer's flat
## command set. This is the build/train split command_context_parser used to keep
## as two hardcoded name lists.
enum Category { BUILD, TRAIN }

## Controller context(s) a tool can appear under, as a bitmask. Used by the grid
## collision review (grid_collisions): two tools sharing a cell only actually clash
## if their contexts overlap. TODO consolidate with rts_controller.gd (its
## pending_command_name / build-vs-act-vs-train modes are the same concept).
enum ControlContext { ACT = 1 << 0, TRAIN = 1 << 1, BUILD = 1 << 2 }

## Which faction(s) a tool belongs to, as a bitmask. Used by the grid collision
## review: two tools sharing a cell only clash if a single player (one faction)
## could have both. 8 placeholder bits — names are arbitrary for now (first four
## mirror the Entity.Type prefixes NT_/TC_/AN_/CL_).
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

## HUD command-grid dimensions. Each Tool.grid_position must fit inside
## grid_width × grid_height; command_grid.gd builds exactly this many cells and
## maps a Tool's 2D position into its flat cell array via cell_index(). Kept here
## (with the positions they validate) for now; may move to the HUD layer later.
const grid_width: int = 5
const grid_height: int = 3
#endregion

#region Properties
## Internal HUD/command identifier, e.g. "command_tool_dwelling". NOT an InputMap
## action — purely the string the HUD, controller and command pipeline pass around.
var command_name: String
## The Entity.Type this tool produces or places.
var type: Variant
var packed_scene: PackedScene
## HUD button text, e.g. "Dwelling".
var label: String
var category: Category
## Cell this tool's button occupies in the command grid. Validated against
## grid_width × grid_height; mapped to the grid's flat array via cell_index().
var grid_position: Vector2i
## Bitmask of ControlContext values this tool can appear under.
var control_context: int
## Bitmask of Faction values this tool belongs to.
var faction: int
#endregion

#region Lifecycle
func _init(
	a_command_name: String,
	a_type: Variant,
	a_packed_scene: PackedScene,
	a_label: String,
	a_category: Category,
	a_grid_position: Vector2i,
	a_control_context: int,
	a_faction: int
) -> void:
	command_name = a_command_name
	type = a_type
	packed_scene = a_packed_scene
	label = a_label
	category = a_category
	grid_position = a_grid_position
	control_context = a_control_context
	faction = a_faction
#endregion

#region Registry
## SINGLE SOURCE OF TRUTH (name -> Tool). Ordered (Godot dicts keep insertion
## order), so the derived lookups and HUD menus stay in this order. Prefer the
## typed accessors below (for_name / for_type / ...) at call sites; this dict is
## the backing index. Declared as a plain literal — NOT computed from another
## static var — because a static var that calls a method touching another static
## var sees it still empty at init time (the same fragility command_context_parser
## dodges by building lazily). Derived indexes below are built lazily on first use.
## _init args: command_name, type, scene, label, category, grid_position,
## control_context, faction.
static var command_tool_map: Dictionary = {
	# Build tools (Technician → structures).
	"command_tool_dwelling": Tool.new("command_tool_dwelling", Entity.Type.TC_STRUCTURE_DWELLING, load("res://scenes/structures/dwelling.tscn"), "Dwelling", Category.BUILD, Vector2i(1, 0), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_mine": Tool.new("command_tool_mine", Entity.Type.NT_STRUCTURE_MINE, load("res://scenes/structures/n_mine.tscn"), "Mine", Category.BUILD, Vector2i(2, 0), ControlContext.BUILD, Faction.NEUTRAL),
	"command_tool_redoubt": Tool.new("command_tool_redoubt", Entity.Type.AN_STRUCTURE_REDOUBT, load("res://scenes/structures/b_redoubt.tscn"), "Redoubt", Category.BUILD, Vector2i(4, 0), ControlContext.BUILD, Faction.ANARCHISTS),
	"command_tool_lab": Tool.new("command_tool_lab", Entity.Type.TC_STRUCTURE_LAB, load("res://scenes/structures/lab.tscn"), "Lab", Category.BUILD, Vector2i(3, 0), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_compound": Tool.new("command_tool_compound", Entity.Type.TC_STRUCTURE_COMPOUND, load("res://scenes/structures/compound.tscn"), "Compound", Category.BUILD, Vector2i(0, 1), ControlContext.BUILD, Faction.TECHNOCRACY),
	"command_tool_armory": Tool.new("command_tool_armory", Entity.Type.TC_STRUCTURE_ARMORY, load("res://scenes/structures/armory.tscn"), "Armory", Category.BUILD, Vector2i(1, 1), ControlContext.BUILD, Faction.TECHNOCRACY),
	# Train tools (structures → units).
	"command_tool_technician": Tool.new("command_tool_technician", Entity.Type.AN_UNIT_TECHNICIAN, load("res://scenes/units/technician.tscn"), "Techie", Category.TRAIN, Vector2i(1, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_irregular": Tool.new("command_tool_irregular", Entity.Type.AN_UNIT_IRREGULAR, load("res://scenes/units/b_irregular.tscn"), "Irregular", Category.TRAIN, Vector2i(2, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_warlord": Tool.new("command_tool_warlord", Entity.Type.AN_UNIT_WARLORD, load("res://scenes/units/warlord.tscn"), "Warlord", Category.TRAIN, Vector2i(1, 2), ControlContext.TRAIN, Faction.ANARCHISTS),
	"command_tool_vanguard": Tool.new("command_tool_vanguard", Entity.Type.TC_UNIT_VANGUARD, load("res://scenes/units/vanguard.tscn"), "Vanguard", Category.TRAIN, Vector2i(3, 2), ControlContext.TRAIN, Faction.TECHNOCRACY),
}

## Entity.Type -> Tool. Lazily built (see note above); cached after first use.
static var _by_type_cache: Dictionary = {}

static func _by_type() -> Dictionary:
	if _by_type_cache.is_empty():
		for t: Tool in command_tool_map.values():
			_by_type_cache[t.type] = t
	return _by_type_cache
#endregion

#region Lookups
## The Tool with this command name, or null.
static func for_name(a_command_name: String) -> Tool:
	return command_tool_map.get(a_command_name)

## The Tool that produces/places this Entity.Type, or null. Replaces the
## hand-rolled type→tool scans in bot.gd / bot_actuator.gd.
static func for_type(a_type: Variant) -> Tool:
	return _by_type().get(a_type)

## HUD button text for a command name, or "" if unknown.
static func label_for(a_command_name: String) -> String:
	var t: Tool = command_tool_map.get(a_command_name)
	return t.label if t != null else ""

## Command names, in registry order, whose category is BUILD / TRAIN.
static func build_tool_names() -> Array:
	return _names_in_category(Category.BUILD)

static func train_tool_names() -> Array:
	return _names_in_category(Category.TRAIN)

static func _names_in_category(a_category: Category) -> Array:
	var out: Array = []
	for t: Tool in command_tool_map.values():
		if t.category == a_category:
			out.append(t.command_name)
	return out
#endregion

#region HUD grid placement + collision review
## Row-major mapping from a 2D grid cell to command_grid's flat cell array.
## (grid_containers is 1D; this is the agreed 2D→1D bridge.)
static func cell_index(a_position: Vector2i) -> int:
	return a_position.y * grid_width + a_position.x

static func position_in_bounds(a_position: Vector2i) -> bool:
	return a_position.x >= 0 and a_position.x < grid_width \
		and a_position.y >= 0 and a_position.y < grid_height

## Tools whose grid_position falls outside grid_width × grid_height, as readable
## strings. Empty = all valid. A hard error to leave non-empty (the grid can't
## place an out-of-bounds button) — see tests/test_Tool.gd.
static func out_of_bounds_positions() -> Array:
	var bad: Array = []
	for t: Tool in command_tool_map.values():
		if not position_in_bounds(t.grid_position):
			bad.append("%s at %s (grid is %dx%d)" % [t.command_name, t.grid_position, grid_width, grid_height])
	return bad

## REVIEW AID: pairs of tools that share a grid cell AND could plausibly be shown
## at the same time — i.e. their control_context masks overlap AND their faction
## masks overlap. Two tools sharing a cell but separated by context (one BUILD,
## one TRAIN) or by faction (no common faction) can never co-appear, so they are
## NOT reported. Returns readable, sorted strings so the set is stable/diffable;
## the player/designer reviews whether each reported overlap is acceptable.
static func grid_collisions() -> Array:
	var tools: Array = command_tool_map.values()
	var out: Array = []
	for i in tools.size():
		for j in range(i + 1, tools.size()):
			var a: Tool = tools[i]
			var b: Tool = tools[j]
			if a.grid_position == b.grid_position \
					and (a.control_context & b.control_context) != 0 \
					and (a.faction & b.faction) != 0:
				var names: Array = [a.command_name, b.command_name]
				names.sort()
				out.append("%s + %s @ %s" % [names[0], names[1], a.grid_position])
	out.sort()
	return out
#endregion
