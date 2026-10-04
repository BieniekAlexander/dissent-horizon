class_name PieceField
extends RefCounted

## One value a piece's doc configures, declared once for both of its readers: the HUD readout,
## which shows the running game's value, and the debug tuning editor, which edits the doc's.
## The catalogue of them is PieceFields; the tiers are gdd/systems/ux/ui/piece-readouts.md.
##
## A field reads and writes its RAW runtime value — the number, resource or bitmask a
## component actually holds — and its `kind` says how that converts to what a person reads
## and to what the doc writes (PieceFields.display / to_doc / from_doc).

## How deep in the readout the field is shown.
enum Tier { FACE, POPUP, VERBOSE }

## What the value is, which decides how it converts and which editor it gets.
enum Kind {
	NUMBER,  ## a float in human units
	INTEGER,
	BOOL,
	ENUM,  ## raw int, doc member name; `options` is the enum
	FLAGS,  ## raw bitmask, doc list of names; `options` is {name: bit}
	SPEED_CLASS,  ## raw world units per second, doc a speed-ladder class name
	SHAPE,  ## raw Shape3D (null for none), doc a shape-library id
	SHAPE_PAIR,  ## raw float gap, doc {from: id, to: id} — a garrison's range bonus
	CADENCE,  ## raw seconds between applications (INF once, null none), doc `once` / seconds
	ID_LIST,  ## raw and doc a list of ids; `options` is every id that may be listed
	TEXT,
}

## Whose node the field is on, and what its doc path is relative to.
enum Scope {
	PIECE,  ## the piece root; the doc root
	WEAPON,  ## a Loadout weapon; one `weapons:` item
	EMISSION,  ## an emission root; the emission's doc (inline under `emits:`, or its own)
	PHASE,  ## an EmissionPhase; one `phases:` item
	POOL,  ## one Abilities pool; one `abilities:` item
}

## The readout widget it is drawn under (InfoWidgetRow keys: hp, speed, sight, hold, weapon,
## name).
var widget: StringName
var scope: Scope
var label: String
## Where the doc authors it, relative to the scope's doc root.
var doc_path: Array
var kind: Kind
var tier: Tier
## Shown after a figure, e.g. "s" or "°/s". Empty for unitless values.
var unit: String = ""
## ENUM: the enum Dictionary. FLAGS: {name: bit}. SHAPE / SHAPE_PAIR: the bucket-id prefix the
## editor offers ("vision_"), as `options[0]`.
var options: Variant = null
## Whether a SHAPE may be empty (`none`), switching its volume off.
var is_optional: bool = false
## A raw value stored in physics TICKS that the doc authors in seconds.
var is_ticks: bool = false
## False for a value the importer alone can apply (a body radius decides the navigation size
## class); the editor saves it and says nothing changes until a re-import.
var is_live: bool = true
## (ctx: Dictionary) -> Variant: the raw value, from ctx["node"] (and ctx["index"] for a pool).
## Null for a value the running game no longer holds (a phase's preset name).
var read: Callable
## (ctx: Dictionary, raw_old: Variant, raw_new: Variant) -> void. Null where the field is
## applied wholesale instead (an emission is rebuilt from its doc, see TuningSession).
var write: Callable
## (ctx: Dictionary) -> bool: whether the field means anything for this piece. Null = always.
var applies: Callable
## (ctx: Dictionary) -> CollisionShape3D: the volume this field sizes, drawn while it is edited
## (debug-tuning.md §Where the editor is). Null for a field that sizes none.
var shape_node: Callable


func is_applicable(a_ctx: Dictionary) -> bool:
	return not applies.is_valid() or bool(applies.call(a_ctx))


func read_raw(a_ctx: Dictionary) -> Variant:
	return read.call(a_ctx) if read.is_valid() else null
