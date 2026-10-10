class_name AbilityCatalog
extends RefCounted

## WHAT AN ABILITY IS, read from resources/generated/abilities.json (one entry per
## `kind: AbilityDefinition` doc — see tools/spec_import).
##
## Three separate questions, and this class answers only the first:
##   * WHAT the ability is — its name, its copy, whether it is passive, what it
##     throws, whether it earns a HUD button. Here.
##   * WHO can use it and HOW OFTEN — the [Abilities] component on each piece,
##     which owns the charge pool. An ability may be granted by several kinds of
##     piece, on different charges.
##   * HOW IT IS ACQUIRED — dominion through the sanction grid ([SanctionGrid]),
##     free, or bought at a structure. `is_dominion_unlocked` is the whole of what
##     "sanction" now means, and it is deliberately not what decides the HUD.
##
## A PASSIVE ability is never emitted through a command: it is attached to the piece
## and present persistently (the Anarchists' Scavenge bounty). An ACTIVE one is
## ordered, spends a charge, and may throw an emission.
##
## Read-only authored data, so a plain static table rather than a per-commander copy.

const ABILITIES_JSON_PATH: String = "res://resources/generated/abilities.json"

## id -> its AbilityDefinition. Static because the file is authored data that cannot
## change during a run, and every consumer asks the same questions of it.
static var _definitions: Dictionary = _load()

## id -> the loaded emission scene. Memoized because a bombarding battery asks for
## its shell on every shot, and ResourceLoader would otherwise be on that path.
static var _emission_cache: Dictionary = {}


static func _load() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(ABILITIES_JSON_PATH)
	var parsed: Variant = JSON.parse_string(text)
	var definitions: Dictionary = {}
	if parsed is Dictionary:
		for id: Variant in parsed:
			var entry: Variant = parsed[id]
			definitions[str(id)] = AbilityDefinition.from_entry(
				StringName(id), entry if entry is Dictionary else {}
			)
	return definitions


## One ability's definition. An id nothing defines reads as an unauthored definition —
## every field at its default, so every reader below degrades instead of having to guard:
## an unknown ability is simply one nobody can use.
static func definition(id: StringName) -> AbilityDefinition:
	var found: Variant = _definitions.get(String(id))
	return found if found is AbilityDefinition else AbilityDefinition.from_entry(id, {})


static func has(id: StringName) -> bool:
	return _definitions.has(String(id))


## Every ability id, in the generated (alphabetical) order.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _definitions:
		out.append(StringName(id))
	return out


static func title_of(id: StringName) -> String:
	return definition(id).title


static func description_of(id: StringName) -> String:
	return definition(id).description


static func verbose_of(id: StringName) -> String:
	return definition(id).verbose


## How far from the target point the ability may be used, in world units.
##
## AUTHORED PER ABILITY, because reach is exactly the sort of thing that differs between
## them. It used to be one `const RANGE` on the Ability command — one number for every
## ability that would ever exist — and that is what forced the Bombard to be written as a
## SIBLING command class rather than an instance of Ability: its reach is not a distance at
## all, and there was no way to say so. See ~/.claude/CLAUDE.md §1.3.
##
## An ability whose reach is not a distance still authors nothing here; it overrides
## Ability.is_in_range instead (Bombard does).
static func range_of(id: StringName) -> float:
	return definition(id).range_metres


## range_of as `a_caster` reaches: the authored reach, raised by any upgrade the caster's
## commander owns that modifies this piece's use of this ability (UpgradeCatalog.range_for).
## Ask this rather than range_of wherever a caster is known, so an upgrade reaches every
## reader of the range at once.
static func range_for(id: StringName, a_caster: Entity) -> float:
	var base: float = range_of(id)
	# An out-of-tree piece (a build preview, a test fixture) never resolved its @onready
	# Ownership, so it has no commander to own an upgrade.
	if a_caster == null or not is_instance_valid(a_caster) or a_caster.ownership == null:
		return base
	return UpgradeCatalog.range_for(a_caster.commander, a_caster.id, id, base)


## HOW MANY SELECTED CASTERS FIRE THIS ABILITY when no modifier is held — `cast_by:` on the
## ability's doc, defaulting to SINGLE (control-matrices.md §Cast arity). An unknown or absent value
## reads as SINGLE rather than erroring: validation is the importer's job, and a catalog that
## refused to answer would take the HUD down over a typo.
static func cast_arity_of(id: StringName) -> MoveCommand.CastArity:
	return definition(id).cast_arity


## Is this GOOD or BAD for whoever carries it — the accent on its info card. See Valence.
static func valence_of(id: StringName) -> Valence.Kind:
	return definition(id).valence


## The REACH this ability's info card paints when the player hovers it, as an
## EntityRanges.Kind, or -1 for an ability with no shape to show — which is most of them.
##
## Named on the doc (`reveals:`) rather than derived, because a piece may carry several
## colliders and only the ability knows which one it acts through. The shape itself is the
## one the SIMULATION sweeps, so the ring and the rule cannot disagree — see
## gdd/systems/ux/ui/range-reveal.md.
static func reveals_of(id: StringName) -> int:
	return definition(id).reveals


## Never emitted through a command — a standing benefit attached to whoever owns it.
static func is_passive(id: StringName) -> bool:
	return definition(id).is_passive


## Whether this ability gets a button on the top-of-screen bar. AUTHORED, not derived:
## it used to follow from being dominion-unlocked, which conflated the HUD with the
## shop. The rule of thumb behind the flag is reach — an ability whose effective range
## is global wants a button, because the player cannot walk the map to find its caster.
static func has_hud_button(id: StringName) -> bool:
	return definition(id).has_hud_button


## Whether every commander is told who owns a caster of this ability and sees its charge
## count down (doc key `global_alert:`). gdd/systems/ux/ui/alerts.md §Global alerts.
static func has_global_alert(id: StringName) -> bool:
	return definition(id).has_global_alert


## Every ability that authors `global_alert: true`, in the generated (alphabetical) order.
static func global_alert_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ids():
		if has_global_alert(id):
			out.append(id)
	return out


## Whether the sanction grid is where this ability comes from — i.e. whether it is an
## SANCTION. Abilities that are free, or bought at a structure, are not.
static func is_dominion_unlocked(id: StringName) -> bool:
	return definition(id).is_dominion_unlocked


## The grid command this ability is armed as, or "" when it has none. A
## dominion-unlocked ability is armed as its own unlocked cell instead (see
## Sanction.command_name), which is why the two are alternatives in the schema.
static func command_of(id: StringName) -> String:
	return definition(id).command


## The ORDNANCE-card cell this ability's button occupies, or (-1, -1) when it has none. A
## LOCAL ability draws no ordnance button and authors no cell.
static func grid_of(id: StringName) -> Vector2i:
	return definition(id).grid


## The ability's SECOND cell, on the ACTIVE card, or (-1, -1) when it claims none. An
## ordnance is normally reached only from the commander's card; one that is also an order you
## give a selected piece says so here (the Bombard).
static func active_grid_of(id: StringName) -> Vector2i:
	return definition(id).active_grid


## The UI faction mask for this ability's button — what lets two factions' ordnances share a
## cell honestly (see ControlBinding.grid_collisions). An ability naming no faction applies
## to all of them, matching a plain verb.
static func faction_mask_of(id: StringName) -> int:
	var mask: int = 0
	for name: String in definition(id).faction_names:
		var key: String = str(name).to_upper()
		if ControlBinding.Faction.has(key):
			mask |= ControlBinding.Faction[key]
	return mask if mask != 0 else ControlBinding.FACTION_ANY


## EVERY grid command this ability can be armed as.
##
## Usually one, and for a dominion-unlocked ability one PER LEVEL: each unlock carries its own
## name ("Scan 1", "Scan 2") and is armed as its own command, so one ability is up to three
## command names sharing one cell — of which supersession keeps exactly one live, which is
## precisely the "alternatives in a cell" rule the grid already has.
##
## Derived through Sanction.command_name_for rather than from a generated string, so the
## button and the command it fires cannot come to disagree.
static func commands_of(id: StringName) -> Array[String]:
	var out: Array[String] = []
	for button: Dictionary in buttons_of(id):
		out.append(str(button["command"]))
	return out


## Every ORDNANCE button this ability produces, as
## {"command", "label", "description", "verbose"} — one per LEVEL for a dominion-unlocked
## ability, one for a free one, none for an ability with no cell.
##
## The COPY comes from the level, not from the ability: "Scan 2" reveals more ground than
## "Scan 1" and its button has to say so. An ability with no levels falls back to its own
## words, which is what those are for.
static func buttons_of(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var own: String = command_of(id)
	if not own.is_empty():
		(
			out
			. append(
				{
					"command": own,
					"label": title_of(id),
					"description": description_of(id),
					"verbose": verbose_of(id),
				}
			)
		)
	for level: Dictionary in definition(id).levels:
		var title: String = str(level.get("title", ""))
		var command: String = Sanction.command_name_for(title)
		if commands_carry(out, command):
			continue
		(
			out
			. append(
				{
					"command": command,
					"label": title,
					"description": str(level.get("description", "")),
					"verbose": str(level.get("verbose", "")),
				}
			)
		)
	return out


static func commands_carry(buttons: Array[Dictionary], command: String) -> bool:
	for button: Dictionary in buttons:
		if str(button["command"]) == command:
			return true
	return false


## The piece this ability throws on each use, or null when it throws nothing —
## most abilities deliver an event scene, and a passive delivers nothing at all.
static func emission_of(id: StringName) -> PackedScene:
	var path: String = definition(id).emission_path
	if path.is_empty():
		return null
	if not _emission_cache.has(path):
		_emission_cache[path] = load(path) as PackedScene
	return _emission_cache[path]


## id -> the XZ radius of the emission's blast, read once off an out-of-tree instance.
static var _blast_radius_cache: Dictionary = {}


## HOW MUCH GROUND THIS ABILITY'S PAYLOAD COVERS: the XZ radius of its emission's HitShape, or
## -1.0 for an ability that emits nothing, or whose emission lands on one piece (no blast).
## Read off the scene once — a payload's area is authored on the emission, nowhere else — so
## whoever aims the ability (the bot) measures the same ground the shell will.
static func blast_radius_of(id: StringName) -> float:
	if _blast_radius_cache.has(id):
		return _blast_radius_cache[id]
	var radius: float = -1.0
	var scene: PackedScene = emission_of(id)
	if scene != null:
		var instance: Node = scene.instantiate()
		var shape_node: CollisionShape3D = instance.get_node_or_null("HitShape") as CollisionShape3D
		if shape_node != null and shape_node.shape != null:
			radius = _xz_radius(shape_node.shape)
		instance.free()
	_blast_radius_cache[id] = radius
	return radius


static func _xz_radius(a_shape: Shape3D) -> float:
	if a_shape is CylinderShape3D:
		return (a_shape as CylinderShape3D).radius
	if a_shape is SphereShape3D:
		return (a_shape as SphereShape3D).radius
	if a_shape is CapsuleShape3D:
		return (a_shape as CapsuleShape3D).radius
	if a_shape is BoxShape3D:
		var size: Vector3 = (a_shape as BoxShape3D).size
		return maxf(size.x, size.z) / 2.0
	return -1.0
