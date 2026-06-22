class_name ControlBinding

## A command's presence in the command grid: the data the HUD grid and the
## collision review share across EVERY grid command — verb commands (move, stop,
## attack, …) and Tools (build/train) alike. A Tool is a ControlBinding that also
## references an entity to place/produce (see tool.gd).
##
## Verbs are plain ControlBinding instances (defined in command_grid.gd); tools are
## Tool instances (the Tool registry). The grid and grid_collisions() operate on
## this base type, so both kinds are placed and reviewed uniformly.

#region Constants
## Controller context(s) a binding appears under, as a bitmask. Verb commands are
## ACT; build/train tools are BUILD/TRAIN. RTSController.current_context() maps its
## modes onto these bits; command_context_parser.tools_for() and grid_collisions()
## filter on them.
enum ControlContext { ACT = 1 << 0, TRAIN = 1 << 1, BUILD = 1 << 2 }

## All-ones faction mask: a binding with no faction allegiance (every verb) applies
## to all factions, so faction can never be what separates it from a tool in the
## collision review. Only Tool narrows it (see Tool.faction_mask).
const FACTION_ANY: int = ~0

## Command-grid dimensions. Every grid_position must fit grid_width × grid_height;
## command_grid builds exactly this many cells and maps a 2D position into its flat
## cell array via cell_index().
const grid_width: int = 5
const grid_height: int = 3
#endregion

#region Properties
## HUD/command identifier, e.g. "command_stop" or "command_tool_dwelling". NOT an
## InputMap action — the string the HUD, controller and command pipeline pass around.
var command_name: String
## HUD button text, e.g. "Stop" / "Dwelling".
var label: String
## Cell this binding's button occupies. Validated against grid_width × grid_height.
var grid_position: Vector2i
## Bitmask of ControlContext values this binding appears under.
var control_context: int
#endregion

#region Lifecycle
func _init(
	a_command_name: String,
	a_label: String,
	a_grid_position: Vector2i,
	a_control_context: int
) -> void:
	command_name = a_command_name
	label = a_label
	grid_position = a_grid_position
	control_context = a_control_context
#endregion

#region Faction
## Faction bitmask this binding belongs to. Base = every faction (verbs are
## faction-agnostic); Tool overrides with its specific faction(s). Read by the
## collision review so it works uniformly on any binding — never a `.faction` field.
func faction_mask() -> int:
	return FACTION_ANY
#endregion

#region Grid placement + collision review
## Row-major mapping from a 2D grid cell to command_grid's flat cell array.
static func cell_index(a_position: Vector2i) -> int:
	return a_position.y * grid_width + a_position.x

static func position_in_bounds(a_position: Vector2i) -> bool:
	return a_position.x >= 0 and a_position.x < grid_width \
		and a_position.y >= 0 and a_position.y < grid_height

## Bindings whose grid_position falls outside grid_width × grid_height, as readable
## strings. Empty = all valid (a hard error to leave non-empty — the grid can't
## place an out-of-bounds button).
static func out_of_bounds(a_bindings: Array) -> Array:
	var bad: Array = []
	for b: ControlBinding in a_bindings:
		if not position_in_bounds(b.grid_position):
			bad.append("%s at %s (grid is %dx%d)" % [b.command_name, b.grid_position, grid_width, grid_height])
	return bad

## REVIEW AID: pairs of bindings that share a grid cell AND could plausibly be
## shown at the same time — control_context masks overlap AND faction_mask()s
## overlap. Bindings separated by context (e.g. an ACT verb vs a BUILD tool) or by
## faction never co-appear, so they are NOT reported. Returns readable, sorted
## strings; the designer reviews whether each reported overlap is acceptable.
static func grid_collisions(a_bindings: Array) -> Array:
	var out: Array = []
	for i in a_bindings.size():
		for j in range(i + 1, a_bindings.size()):
			var a: ControlBinding = a_bindings[i]
			var b: ControlBinding = a_bindings[j]
			if a.grid_position == b.grid_position \
					and (a.control_context & b.control_context) != 0 \
					and (a.faction_mask() & b.faction_mask()) != 0:
				var names: Array = [a.command_name, b.command_name]
				names.sort()
				out.append("%s + %s @ %s" % [names[0], names[1], a.grid_position])
	out.sort()
	return out
#endregion
