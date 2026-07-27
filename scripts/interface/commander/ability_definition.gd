class_name AbilityDefinition
extends RefCounted

## WHAT ONE ABILITY IS — the class a `kind: AbilityDefinition` doc loads as. The importer
## writes each doc to resources/generated/abilities.json, and AbilityCatalog builds one of
## these per entry; everything the game asks about an ability reads a field here.
##
## Every field has the value an unauthored ability behaves as, so a doc names only what it
## changes — and an unknown id reads as a definition nobody can use rather than an error.
## Parsing is lenient on purpose: validation is the importer's job, and a catalog that refused
## a malformed entry would take the HUD down over a typo.

## The reach of an ability whose doc names no `range:` — the one value every ability had
## back when the Ability command carried a single constant for all of them.
const DEFAULT_RANGE: float = 5.0
## An unauthored cell.
const NO_CELL: Vector2i = Vector2i(-1, -1)

var id: StringName
var title: String
var description: String = ""
var verbose: String = ""
## Never emitted through a command — a standing benefit attached to whoever owns it.
var is_passive: bool = false
## Whether it gets a button on the top-of-screen bar. Authored, not derived.
var has_hud_button: bool = false
## The grid command it is armed as, or "" — a dominion-unlocked one is armed per level.
var command: String = ""
## How far from the target point it may be used, in world units.
var range_metres: float = DEFAULT_RANGE
var cast_arity: MoveCommand.CastArity = MoveCommand.CastArity.SINGLE
## The EntityRanges.Kind its info card paints on hover, or -1 for none.
var reveals: int = -1
var valence: Valence.Kind
## The emission scene it throws per use, or "" when it throws none.
var emission_path: String = ""
## Whether the sanction grid is where it comes from.
var is_dominion_unlocked: bool = false
var grid: Vector2i = NO_CELL
var active_grid: Vector2i = NO_CELL
var faction_names: Array[String] = []
## Its dominion levels as generated: {title, description, verbose}. Empty for a free one.
var levels: Array[Dictionary] = []


static func from_entry(ability_id: StringName, entry: Dictionary) -> AbilityDefinition:
	var definition: AbilityDefinition = AbilityDefinition.new()
	definition.id = ability_id
	definition.title = str(entry.get("title", String(ability_id)))
	definition.description = str(entry.get("description", ""))
	definition.verbose = str(entry.get("verbose", ""))
	definition.is_passive = bool(entry.get("passive", false))
	definition.has_hud_button = bool(entry.get("hud_button", false))
	definition.command = str(entry.get("command", ""))
	definition.range_metres = float(entry.get("range", DEFAULT_RANGE))
	definition.cast_arity = MoveCommand.CastArity.ALL \
		if str(entry.get("cast_by", "")).to_upper() == "ALL" else MoveCommand.CastArity.SINGLE
	var reveals_name: String = str(entry.get("reveals", ""))
	definition.reveals = int(EntityRanges.Kind[reveals_name]) \
		if EntityRanges.Kind.has(reveals_name) else -1
	definition.valence = Valence.from_name(str(entry.get("valence", "")))
	definition.emission_path = str(entry.get("emits", ""))
	definition.is_dominion_unlocked = bool(entry.get("dominion", false))
	definition.grid = _cell(entry.get("grid", []))
	definition.active_grid = _cell(entry.get("active_grid", []))
	for faction: Variant in entry.get("factions", []):
		definition.faction_names.append(str(faction))
	for level: Variant in entry.get("levels", []):
		if level is Dictionary:
			definition.levels.append(level)
	return definition


static func _cell(value: Variant) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1])) if value is Array and value.size() == 2 \
		else NO_CELL
