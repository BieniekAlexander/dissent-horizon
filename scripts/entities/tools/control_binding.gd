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
## ACT; build/train tools are BUILD/TRAIN; SELECT is the "nothing selected" page
## (e.g. the idle-unit selectors). RTSController.current_context() maps its modes
## onto these bits; command_context_parser.tools_for() and grid_collisions()
## filter on them.
enum ControlContext { ACT = 1 << 0, TRAIN = 1 << 1, BUILD = 1 << 2, SELECT = 1 << 3 }

## Which CARD a binding belongs to. The command grid holds two pages and shows exactly
## one at a time (RTSController.command_family, toggled with `card_toggle_family`), so a
## family is the coarsest thing that decides whether a button is on screen at all.
##
## It is a property of the COMMAND, not of the entity that offers it — which is the whole
## reason this is `CommandFamily` and not a unit/structure flag. A structure that both
## shoots and trains (a Warcraft-III-style ancient) offers commands in both families, and
## the toggle reaches its attacks and its training in turn; classifying by entity kind
## would leave one of the two with nowhere to be drawn.
##
##   ACTIVE     — what an existing commandable DOES: the verbs (attack-move, stop, defend,
##                land, …), its abilities, and Build with the structure list it drills into.
##                Named ACTIVE rather than COMBAT because the set was never only fighting —
##                a Servant's Build and a transport's Evacuate are neither combat nor
##                production, and a stationary gun that shoots but never moves is on this
##                card too. Placing a structure is "production" in the economic sense and is
##                deliberately kept here: it is issued by a UNIT, mid-fight, alongside that
##                unit's other orders.
##   PRODUCTION — training and (later) upgrades: what a producer commits energy to.
##   ORDNANCE   — the COMMANDER's reach: abilities you cannot walk a unit to, so the player
##                must be able to invoke one without first finding a caster. Alone among the
##                three it is COMMANDER-OWNED rather than selection-owned — it is reachable
##                with nothing selected at all, and pressing one of its buttons selects the
##                casters for you.
##
## ACTIVE and PRODUCTION are both about the SELECTION and Tab flips between them; ORDNANCE is
## about the commander and has its own key. That is why the keys are two and the families are
## three, and why the hierarchy lives in the key handlers rather than in this enum: every
## consumer here (grid_collisions, binding.family, available_families) wants a flat mask, and
## a tree would be a second representation of one fact.
##
## Per-row idioms within each card are documented on CommandGrid.
enum CommandFamily { ACTIVE = 1 << 0, PRODUCTION = 1 << 1, ORDNANCE = 1 << 2 }

## UI-layout faction grouping, as a bitmask (Tool narrows faction_mask() to it; a plain
## verb binding stays FACTION_ANY). This is BUTTON-GRID metadata for the collision review
## — two tools may share a grid cell only if their faction masks are disjoint. It is NOT a
## gameplay gate: piece availability is technology (structures owned), never a faction tag.
## Names mirror the doc `ui.factions` strings, uppercased.
##
## THERE MUST BE A MEMBER FOR EVERY FACTION THAT HAS PIECES. A name with no member here
## fell through to FACTION_ANY, which quietly made that piece collide with every other
## piece in its cell — and that is not a theoretical hazard: `colonial`, `libertarian`,
## `marxist` and `theocratic` were all missing, and the grid review was reporting 216
## unreviewed collisions because of it. The importer now rejects an unknown name
## (SpecRegistry._validate_ui) so the enum can never silently fall behind the docs again.
##
## It lives on the BASE class, not on Tool, so the importer can validate against it without
## going through Tool. The importer may BUILD Tools (Tool.from_entry, for its grid review) but
## must never READ the Tool registry: that is the previous run's tools.json, which this
## import is about to replace.
enum Faction {
	NEUTRAL     = 1 << 0,
	TECHNOCRACY = 1 << 1,
	ANARCHISTS  = 1 << 2,
	COLONIAL    = 1 << 3,
	LIBERTARIAN = 1 << 4,
	MARXIST     = 1 << 5,
	THEOCRATIC  = 1 << 6,
}

## All-ones faction mask: a binding with no faction allegiance (every verb) applies
## to all factions, so faction can never be what separates it from a tool in the
## collision review. Only Tool narrows it (see Tool.faction_mask).
const FACTION_ANY: int = ~0

## Command-grid dimensions. Every grid_position must fit GRID_WIDTH × GRID_HEIGHT;
## command_grid builds exactly this many cells and maps a 2D position into its flat
## cell array via cell_index().
const GRID_WIDTH: int = 6
const GRID_HEIGHT: int = 3

## Hotkeys are POSITIONAL: the InputMap action a grid cell answers to is named after the
## cell, not after the command that happens to be drawn in it. Pressing it runs whatever
## button that cell is currently showing (RTSController.visible_command_in_cell), so the
## key and the button can never disagree and the card's family gating comes for free —
## a training key simply isn't a training key while the ACTIVE card is up.
##
## The defaults follow the left hand: cell (x, y) takes the key at that position in
## `QWERTY / ASDFGH / ZXCVBN`. They are only defaults — the naming scheme is what a
## rebinding screen would rewrite, and nothing outside project.godot names a letter.
const CELL_ACTION_PREFIX: String = "command_cell_"
#endregion

#region Properties
## HUD/command identifier, e.g. "command_stop" or "command_tool_dwelling". NOT an
## InputMap action — the string the HUD, controller and command pipeline pass around.
var command_name: String
## HUD button text, e.g. "Stop" / "Dwelling".
var label: String
## Cell this binding's button occupies. Validated against GRID_WIDTH × GRID_HEIGHT.
var grid_position: Vector2i
## Bitmask of ControlContext values this binding appears under.
var control_context: int
## Which card this binding is drawn on (see CommandFamily). Verbs are ACTIVE; Tool
## derives it from the tool's context, so it is never authored twice.
var family: int
## HUD button tooltip shown normally.
var simple_tooltip: String
## HUD button tooltip shown while the "ui_verbose" action (/) is held.
var verbose_tooltip: String
#endregion

#region Lifecycle
func _init(
	a_command_name: String,
	a_label: String,
	a_grid_position: Vector2i,
	a_control_context: int,
	a_simple_tooltip: String = "",
	a_verbose_tooltip: String = "",
	a_family: int = CommandFamily.ACTIVE
) -> void:
	command_name = a_command_name
	label = a_label
	grid_position = a_grid_position
	control_context = a_control_context
	simple_tooltip = a_simple_tooltip
	verbose_tooltip = a_verbose_tooltip
	family = a_family
#endregion

#region Faction
## Faction bitmask this binding belongs to. Base = every faction (verbs are
## faction-agnostic); Tool overrides with its specific faction(s). Read by the
## collision review so it works uniformly on any binding — never a `.faction` field.
func faction_mask() -> int:
	return FACTION_ANY
#endregion

#region Actors
## The piece ids of the entities that can OFFER this binding, or empty for "any".
##
## This is what lets two buttons share a cell honestly. Faction and context separate
## bindings that belong to different players or different pages; this separates ones that
## belong to different SELECTIONS — a barracks' recruits and an airfield's aircraft can
## both sit at (0, 1) because no single structure is ever asked to draw both. Tool fills it
## in for train tools from the producers' `trains:` lists; everything else leaves it empty,
## which the review reads as "could appear beside anything".
func actor_ids() -> Array:
	return []

## A tag two bindings share when at most ONE of them can ever be live, or &"" for "no such
## relationship" — a fifth separator for the collision review, beside family, context, faction
## and actor_ids. Deliberately GENERIC rather than an ability-id check.
## What it exists for: gdd/systems/ux/ui/command-card-and-hotkeys.md §What is in the grid.
func exclusion_group() -> StringName:
	return &""

## Whether this binding ALWAYS WINS its cell — it is drawn wherever it applies, and anything
## else claiming that cell is hidden under it rather than competing for it.
##
## Such a binding cannot be AMBIGUOUS with its neighbours, so the review skips it. Cancel is
## the case: while an order is armed it shares the card with that order's own menu, but it is
## placed before every tool (see CommandGrid.bindings) and so takes (5, 2) whatever else
## wants it. Nothing does today — no tool is laid out in column 5 at all — which is why the
## exemption costs nothing to keep.
##
## Deploy and Undeploy are another case: one button in two states, placed ahead of Land,
## because a unit's stance outranks an aircraft's landing when one selection offers both.
## Of the two, Deploy is placed first, so it is the one drawn when both apply. Plant, ahead of
## Detonate, is the third (RTSController.selection_commands says when it steps aside).
##
## False by default; a binding claims it by being named here rather than by a flag, because
## "what outranks the rest of the card" is a HUD decision.
func wins_its_cell() -> bool:
	return command_name in [RTSController.CANCEL_COMMAND, "command_deploy", "command_undeploy",
		"command_plant"]


## Whether NO selection can offer this binding, so its button is never drawn at all.
##
## Distinct from an empty actor_ids(), which means "not declared" and so has to be read
## permissively. This one is a positive statement — a train button for a piece that no
## structure's `trains:` list names — and an unreachable button cannot collide with
## anything, however many neighbours want its cell. The spec importer warns about the
## pieces in this state; it is a roster gap, not a layout one.
func is_orphaned() -> bool:
	return false
#endregion

#region Grid placement + collision review
## Row-major mapping from a 2D grid cell to command_grid's flat cell array.
static func cell_index(position: Vector2i) -> int:
	return position.y * GRID_WIDTH + position.x

## The InputMap action that fires the button in `a_position` (see CELL_ACTION_PREFIX).
static func cell_action(position: Vector2i) -> StringName:
	return StringName("%s%d_%d" % [CELL_ACTION_PREFIX, position.x, position.y])

## The grid cell `a_action` fires, or (-1, -1) if it isn't a cell action at all. The
## inverse of cell_action(), used by the hotkey dispatcher to turn a key press into a
## position before it ever asks what command lives there.
static func position_from_action(action: String) -> Vector2i:
	if not action.begins_with(CELL_ACTION_PREFIX):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = action.substr(CELL_ACTION_PREFIX.length()).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	var position := Vector2i(int(parts[0]), int(parts[1]))
	return position if position_in_bounds(position) else Vector2i(-1, -1)

## Every cell action the grid expects to exist, in row-major order. The list a rebinding
## screen would enumerate, and what test_ControlBinding checks project.godot against.
static func cell_actions() -> Array:
	var out: Array = []
	for y in GRID_HEIGHT:
		for x in GRID_WIDTH:
			out.append(cell_action(Vector2i(x, y)))
	return out

static func position_in_bounds(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < GRID_WIDTH \
		and position.y >= 0 and position.y < GRID_HEIGHT

## Bindings whose grid_position falls outside GRID_WIDTH × GRID_HEIGHT, as readable
## strings. Empty = all valid (a hard error to leave non-empty — the grid can't
## place an out-of-bounds button).
static func out_of_bounds(bindings: Array) -> Array:
	var bad: Array = []
	for b: ControlBinding in bindings:
		if not position_in_bounds(b.grid_position):
			bad.append("%s at %s (grid is %dx%d)" % [b.command_name, b.grid_position, GRID_WIDTH, GRID_HEIGHT])
	return bad

## REVIEW AID: pairs of bindings that share a grid cell AND could plausibly be shown at
## the same time. Four things separate two bindings, and any ONE of them is enough that
## they can never be on screen together:
##
##   family          — different cards; the toggle shows one at a time
##   control_context — an ACT verb vs a BUILD tool (the build list is drilled into)
##   faction         — no commander fields both
##   actor_ids       — both name their offering pieces and the sets are disjoint, so no
##                     one selection ever draws both (see actor_ids)
##   exclusion_group — they are variants of one thing and only one is ever held at a time,
##                     which is what levels of a sanction are (see exclusion_group)
##   wins its cell   — a binding drawn ahead of everything else that claims its cell is never
##                     ambiguous with them, whatever else wants it (see wins_its_cell)
##
## Everything left over is reported as a readable, sorted string for the designer to
## review and either move or acknowledge.
static func grid_collisions(bindings: Array) -> Array:
	var out: Array = []
	for i in bindings.size():
		for j in range(i + 1, bindings.size()):
			var a: ControlBinding = bindings[i]
			var b: ControlBinding = bindings[j]
			if a.grid_position == b.grid_position and _can_co_appear(a, b):
				var names: Array = [a.command_name, b.command_name]
				names.sort()
				out.append("%s + %s @ %s" % [names[0], names[1], a.grid_position])
	out.sort()
	return out

static func _can_co_appear(a: ControlBinding, b: ControlBinding) -> bool:
	if a.is_orphaned() or b.is_orphaned():
		return false
	if a.wins_its_cell() or b.wins_its_cell():
		return false
	var group: StringName = a.exclusion_group()
	if group != &"" and group == b.exclusion_group():
		return false
	if (a.family & b.family) == 0:
		return false
	if (a.control_context & b.control_context) == 0:
		return false
	if (a.faction_mask() & b.faction_mask()) == 0:
		return false
	return _actors_overlap(a, b)

## Whether the two bindings could be offered by one and the same selection. An empty
## actor list means "unknown", which has to read as "yes" — a binding that doesn't declare
## its offerers must not be able to hide a real collision by staying silent.
static func _actors_overlap(a: ControlBinding, b: ControlBinding) -> bool:
	var a_actors: Array = a.actor_ids()
	var b_actors: Array = b.actor_ids()
	if a_actors.is_empty() or b_actors.is_empty():
		return true
	for actor in a_actors:
		if b_actors.has(actor):
			return true
	return false
#endregion
