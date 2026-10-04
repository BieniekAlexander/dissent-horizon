class_name SpecRegistry
extends RefCounted

## Scans gdd/**/*.md for spec docs and validates every cross-reference BEFORE
## anything is written. Validation failures are loud and total: callers must
## abort the import when `errors` is non-empty.
##
## DISCOVERY IS BY THE `kind` FRONTMATTER KEY: a markdown file is an importable
## spec if and only if its frontmatter names a `kind`. Nothing else — not the folder —
## decides spec-hood, so specs can live anywhere under gdd/. Its VALUE names the Godot
## class the spec loads as, spelled as the class is (KIND_FAMILIES); it never says what
## a piece IS — a piece's role is derived from the components its doc declares.
##
## THE FILE NAME IS THE ID: a spec's id is its basename (`an_commandCenter.md` ->
## `an_commandCenter`), which must start with a lowercase letter, contain only
## letters/digits/underscores, and be unique across the whole tree. Underscores
## separate `<faction>_<role>` components; each component is itself camelCase
## (see gdd/id-rename-proposal.md for the convention). There is no `id:`
## frontmatter key — one carried in a doc is a hard error, so
## the old form can never silently disagree with the filename. Renaming a doc
## therefore RE-KEYS the piece: the generated EntityIds const and the scene's own
## `id` property follow the new name, and the old scene is left behind carrying a
## stale id (rename its scene, or delete it, by hand).
##
## No fuzzy matching anywhere: ids resolve exactly or fail (per project policy —
## the user reconciles duplicates/renames by hand).

const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")
const SpecRules := preload("res://tools/spec_import/spec_rules.gd")
const SpecSchema := preload("res://tools/spec_import/schema.gd")
const EmissionPhases := preload("res://tools/spec_import/emission_phases.gd")
const VisualMeasure := preload("res://tools/spec_import/visual_measure.gd")
## The sound tables the voice ASSET rules read — see _asset_facts.
const VOICE_LINES_SCRIPT: String = "res://scripts/audio/control_feedback_sounds.gd"
const DEATH_BARKS_SCRIPT: String = "res://scripts/audio/entity_death_sounds.gd"
## Where a piece's HUD icon is looked for — see _asset_facts.
const PIECE_ICONS_SCRIPT: String = "res://scripts/interface/hud/piece_icons.gd"
## What decides a piece's charge dials and how many its card fits — see _warn_on_dial_overflow.
const CHARGE_DIAL_SCRIPT: String = "res://scripts/interface/hud/charge_dial.gd"
const COMMANDABLE_CARD_SCRIPT: String = "res://scripts/interface/hud/commandable_card.gd"

## `kind:` value -> the family of spec it loads, which picks the registry table and the
## validator. The key is the CLASS the spec loads as, so every game piece is `Entity`
## whatever it does, and an ability doc is the `AbilityDefinition` AbilityCatalog builds.
const KIND_FAMILIES: Dictionary = {
	"Entity": "piece",
	"StatusEffect": "status_effect",
	"Faction": "faction",
	"AbilityDefinition": "ability",
	"Upgrade": "upgrade",
}

## The ONE doc that holds the whole shape library: every reach, vision, detection and
## area-of-effect bucket as an entry of its `shapes:` mapping, so a designer reads and tunes
## them side by side in one file (gdd/shapes/shapes.md). Each entry registers as a shape spec
## of its own, keyed by the entry's id; the library doc itself is not a spec.
const SHAPE_LIBRARY_KIND: String = "ShapeLibrary"
## The top-level keys a ShapeLibrary doc may carry.
const SHAPE_LIBRARY_KEYS: Array = ["kind", "title", "shapes"]
## The classes an entry may load as. An entry that names none is a cylinder.
const SHAPE_CLASSES: Array = ["CylinderShape3D", "SphereShape3D"]

## The ONE doc that holds the speed ladder (gdd/movement/speed_classes.md): a `speeds:`
## mapping of class name to world units per second. It is the source of truth for every
## authored speed — a unit's `movement.speed`, an emission's `speed:` and a phase's
## `motion.speed` NAME a class, and _resolve_speed_classes swaps the name for the number
## before anything else reads it. Like the shape library, the doc itself is not a spec.
const SPEED_LIBRARY_KIND: String = "SpeedLibrary"
## The top-level keys a SpeedLibrary doc may carry.
const SPEED_LIBRARY_KEYS: Array = ["kind", "title", "speeds"]

const EMISSION_IS_AN_ENTITY: String = (
	"Entity — an emission is an Entity whose doc names emission keys " + "(phases:, damage:, …)"
)

const PIECE_ROLE_IS_DERIVED: String = (
	"Entity — whether a piece is a unit or a structure is derived from "
	+ "footprint: and movement:"
)

## A retired `kind:` value and what to say about it. Refused rather than aliased, like every
## other retired spelling: a doc still saying `unit` believes it is declaring a category,
## and under composition a category is something a piece's components decide.
const RETIRED_KINDS: Dictionary = {
	"sanction":
	(
		"AbilityDefinition — a sanction is a dominion UNLOCK ROUTE (`column:`/`levels:`) "
		+ "on an ability doc, not a kind of its own"
	),
	"ability": "AbilityDefinition",
	"CylinderShape3D": "ShapeLibrary — a shape is an entry of gdd/shapes/shapes.md",
	"SphereShape3D": "ShapeLibrary — a shape is an entry of gdd/shapes/shapes.md",
	"unit": PIECE_ROLE_IS_DERIVED,
	"structure": PIECE_ROLE_IS_DERIVED,
	"projectile": EMISSION_IS_AN_ENTITY,
	"Projectile": EMISSION_IS_AN_ENTITY,
	"status_effect": "StatusEffect",
	"faction": "Faction",
}

## What a piece costs and how long it takes when its doc prices neither — units and
## structures alike. A placeholder that is obviously a placeholder: cheap infantry money
## and a short build, so a newly authored piece is immediately buildable and roughly sane
## rather than free and instant.
##
## Applied at registration, so every Godot-side consumer — technology.json, the button
## tooltips, the Scavenge kill bounty — reads the same number, and none of them has to
## carry its own idea of "unpriced". A doc that names `cost:` or `build_time:` keeps
## exactly what it says; the default fills in only a key that is ABSENT, and a partial
## `cost: {infrastructure: 5}` counts as priced (that piece deliberately costs no energy).
##
## The consequence worth knowing: an absent `cost:` used to mean "not buildable", and now
## means "buildable at the placeholder price". Nothing becomes PURCHASABLE by that alone —
## a piece is only offered if it has a `ui:` grid button or sits in a producer's `trains:`
## list — so the neutral map furniture this affects (nt_extractionSite, nt_building_*, nt_shelter,
## nt_bioLight_terrestrial) is priced but unbuyable. What it does fix is the two Colonial defences
## (`cl_defense_antiStructure`, `cl_defense_antiAircraft`), which had grid buttons and were
## silently free.
const DEFAULT_PIECE_COST_ENERGY: int = 100
const DEFAULT_PIECE_BUILD_TIME_SECONDS: float = 10.0

## All specs by id (single shared namespace across kinds, so a projectile can
## never shadow a unit id). Each spec is the frontmatter Dictionary plus:
##   "id": the doc's basename — synthesized here, never authored
##   "_doc_path": res:// path of the markdown doc
##   "_kind": its kind (echo of data.kind for convenience)
var specs: Dictionary = {}
## scene path -> the id of the doc that names it, for the one-scene-one-doc check in _validate.
var _scene_owners: Dictionary = {}
## id -> spec, restricted per kind for iteration convenience.
var pieces: Dictionary = {}  # every kind: Entity doc
var projectiles: Dictionary = {}
var status_effects: Dictionary = {}
var factions: Dictionary = {}
## kind: AbilityDefinition docs, keyed by id — every ability in the game, however it is
## acquired. An ability that is unlocked with DOMINION also names the sanction grid
## column it occupies and the `levels` that are its cells, in chain order; one
## that is free, or bought at a structure, names neither.
var abilities: Dictionary = {}
## kind: Upgrade docs, keyed by id — one-time commander-wide research, bought at a structure
## that names it under `researches:` (gdd/systems/macroeconomics/upgrades.md).
var upgrades: Dictionary = {}
## Shape-library entries (the `shapes:` of the `kind: ShapeLibrary` doc), keyed by id. A weapon's
## `reach:` names one of
## these instead of carrying a radius of its own, so reaches come in a few shared buckets.
var shapes: Dictionary = {}
## The speed ladder: class name -> world units per second, from the `kind: SpeedLibrary` doc.
var speeds: Dictionary = {}
## The SpeedLibrary doc's path, or "" before one is registered — how a second one is caught.
var _speed_library_path: String = ""

var errors: Array = []
var warnings: Array = []
## Declared departures from a calibration norm: one entry per EXCEPTIONAL verdict, as
## `{id, rule, what, detail, reason}`. Printed by the importer as its own section — these
## are the pieces the roster has deliberately built against type, and the value of the
## mechanism is that the list is short enough to read.
var exceptional: Array = []
## Unfilled asset slots: one entry per INCOMPLETE verdict, as `{id, rule, what, detail,
## state}` with `state` a SpecRules.AssetState. Printed by the importer, never an error — a
## missing asset crashes nothing, and this list is the one place it is surfaced.
var incomplete: Array = []


## Scans a gdd root and builds+validates the registry. Returns self.
func scan(a_root: String = "res://gdd") -> RefCounted:
	var docs: Array = []
	var paths: Array = []
	_collect_markdown(a_root, paths)
	paths.sort()
	for path in paths:
		var result: Dictionary = SpecFrontmatter.parse_file(path)
		if not result["ok"]:
			# A malformed doc is only a hard error when it was TRYING to be a spec
			# (its frontmatter names a kind); otherwise it's just prose we skip, so
			# unrelated design notes with quirky frontmatter never break the import.
			if _raw_frontmatter_has_kind(path):
				errors.append("%s: %s" % [path, result["error"]])
			continue
		if not _names_a_kind(result["data"]):
			continue  # not a spec (discovery is by the `kind` key)
		docs.append({"path": path, "data": result["data"]})
	build(docs)
	return self


## Whether frontmatter names a kind at all. An EMPTY `kind:` names none, so it is not a spec —
## a stray Obsidian "Untitled" note is skipped rather than failing the whole import on its file
## name. A non-empty kind that is unknown is still a hard error (`_register`): that is a typo.
static func _names_a_kind(a_data: Dictionary) -> bool:
	var kind: Variant = a_data.get("kind")
	return kind != null and not str(kind).strip_edges().is_empty()


## Builds and validates from in-memory docs ({"path", "data"}) — the scan()
## backend, exposed for tests.
func build(a_docs: Array) -> void:
	for doc in a_docs:
		_register(doc["path"], doc["data"])
	# After EVERY doc is registered (the library may sort after the docs naming its classes)
	# and before any is validated, so every rule, generator and scene sync downstream reads a
	# plain number exactly as it did when the docs carried one.
	_resolve_speed_classes()
	# Before validation, for the same reason: a piece with `variants:` takes its footprint, hp,
	# cost, build time and infrastructure from its first variant, and every rule below must see
	# them as if the doc had authored them.
	_resolve_variants()
	for id in specs:
		_validate(specs[id])
	_review_training_buttons()
	_apply_calibration_rules()
	errors.sort()


## Cross-doc review of the PRODUCTION card, which no single doc can do for itself: a
## button is reachable only if some structure's `trains:` names its piece, and that fact
## lives in the producers, not in the piece.
##
## Both directions are warnings rather than errors — each describes a roster still being
## written, not a broken import — but both are invisible in game and expensive to notice
## by playing, which is what earns them a line in the log:
##   * a piece with a `ui:` block nothing trains has a button that is never drawn (the
##     grid collision review knows this too — see ControlBinding.is_orphaned);
##   * a piece something trains with no `ui:` block can only be produced by a scenario
##     event, never by the player.
func _review_training_buttons() -> void:
	var trained: Dictionary = {}
	for id in pieces:
		for trainee in pieces[id].get("trains", []):
			trained[str(trainee)] = str(id)
	var ids: Array = pieces.keys()
	ids.sort()
	for id in ids:
		var spec: Dictionary = pieces[id]
		if SpecSchema.is_fixture(spec):
			continue
		var has_button: bool = spec.has("ui") and spec["ui"] is Dictionary
		if has_button and not trained.has(str(id)):
			warnings.append(
				(
					(
						"%s [%s]: has a ui: block but no structure trains it — its "
						+ "command-grid button can never be drawn"
					)
					% [spec["_doc_path"], id]
				)
			)
		elif trained.has(str(id)) and not has_button:
			warnings.append(
				(
					"%s [%s]: trained by %s but has no ui: block — the player has no button for it"
					% [spec["_doc_path"], id, trained[str(id)]]
				)
			)


# --------------------------------------------------------------------------- #
# Registration
# --------------------------------------------------------------------------- #
## The doc's BASENAME is its id — never anything the doc says. Discovery
## guaranteed a `kind` key is present; its VALUE is checked here, so a typo'd
## kind fails loudly instead of quietly dropping the doc from the import.
func _register(a_path: String, a_data: Dictionary) -> void:
	var id: String = a_path.get_file().get_basename()
	if a_data.has("id"):
		errors.append(
			(
				"%s: remove the `id:` key — a spec's file name is its id (this doc is '%s')"
				% [a_path, id]
			)
		)
		return
	if not _valid_id(id):
		errors.append(
			(
				(
					"%s: invalid file name — it is the spec's id, so it must start "
					+ "with a lowercase letter and contain only letters, digits, and "
					+ "underscores: [a-z][a-zA-Z0-9_]*"
				)
				% a_path
			)
		)
		return
	var kind: String = str(a_data.get("kind", ""))
	if RETIRED_KINDS.has(kind):
		errors.append(
			(
				"%s [%s]: `kind: %s` is retired — use `kind: %s`"
				% [a_path, id, kind, RETIRED_KINDS[kind]]
			)
		)
		return
	if kind == SHAPE_LIBRARY_KIND:
		_register_shape_library(a_path, a_data)
		return
	if kind == SPEED_LIBRARY_KIND:
		_register_speed_library(a_path, a_data)
		return
	if not KIND_FAMILIES.has(kind):
		errors.append("%s [%s]: %s" % [a_path, id, _unknown_kind_message(kind)])
		return
	if specs.has(id):
		# Ids share one namespace across kinds and the whole tree, so basenames
		# must be globally unique — two docs with the same name in different
		# folders collide, however unrelated their directories look.
		errors.append(
			(
				"%s: duplicate id '%s' (a doc of that name also exists at %s)"
				% [a_path, id, specs[id]["_doc_path"]]
			)
		)
		return
	var spec: Dictionary = a_data.duplicate(true)
	spec["id"] = id
	spec["_doc_path"] = a_path
	spec["_kind"] = KIND_FAMILIES[kind]
	if spec["_kind"] == "piece" and SpecSchema.is_emission(a_data):
		if a_data.has("footprint") or a_data.has("movement"):
			errors.append(
				(
					(
						"%s [%s]: an emission moves by its phase list, so it cannot also"
						+ " declare footprint: or movement:"
					)
					% [a_path, id]
				)
			)
			return
		spec["_kind"] = "projectile"
	# The authored shape is nested (see SpecSchema); everything below this line reads the
	# flat internal names. Normalising HERE, once, is what let the nesting land without
	# touching the rules, the generators or the scene sync.
	for complaint: String in SpecSchema.normalize(spec):
		_err(spec, complaint)
	_normalize_removals(spec)
	specs[id] = spec
	match str(spec["_kind"]):
		"piece":
			_apply_piece_defaults(spec)
			pieces[id] = spec
			if spec.get("weapons") is Array:
				_hoist_inline_projectiles(spec)
		"projectile":
			projectiles[id] = spec
		"status_effect":
			status_effects[id] = spec
		"faction":
			factions[id] = spec
		"ability":
			abilities[id] = spec
		"upgrade":
			upgrades[id] = spec
		"shape":
			shapes[id] = spec


## Registers every entry of a ShapeLibrary doc as a shape spec: the entry's key is its id (in
## the same namespace as every other spec), its value the shape's keys, and `_doc_path` the
## library doc, so an error or a generated resource points a designer at the one file.
## `kind:` on an entry defaults to CylinderShape3D. The keys themselves are checked later, by
## _validate_shape, exactly as they were when each shape was a doc of its own.
func _register_shape_library(a_path: String, a_data: Dictionary) -> void:
	for key: Variant in a_data:
		if not SHAPE_LIBRARY_KEYS.has(str(key)):
			errors.append(
				(
					"%s: unknown ShapeLibrary key '%s' (expected one of %s)"
					% [a_path, key, SHAPE_LIBRARY_KEYS]
				)
			)
	var entries: Variant = a_data.get("shapes")
	if not (entries is Dictionary) or (entries as Dictionary).is_empty():
		errors.append(
			"%s: a ShapeLibrary needs shapes: — a mapping of shape id to its keys" % a_path
		)
		return
	for key: Variant in entries:
		var id: String = str(key)
		var entry: Variant = entries[key]
		if not _valid_id(id):
			errors.append(
				"%s: invalid shape id '%s' — it must match [a-z][a-zA-Z0-9_]*" % [a_path, id]
			)
			continue
		if specs.has(id):
			errors.append(
				"%s: duplicate id '%s' (also defined at %s)" % [a_path, id, specs[id]["_doc_path"]]
			)
			continue
		if not (entry is Dictionary):
			errors.append(
				"%s [%s]: a shape entry must be a mapping, e.g. {radius: 1}" % [a_path, id]
			)
			continue
		var spec: Dictionary = (entry as Dictionary).duplicate(true)
		var shape_kind: String = str(spec.get("kind", "CylinderShape3D"))
		if not SHAPE_CLASSES.has(shape_kind):
			errors.append(
				(
					"%s [%s]: a shape's kind must be one of %s, got '%s'"
					% [a_path, id, SHAPE_CLASSES, shape_kind]
				)
			)
			continue
		spec["kind"] = shape_kind
		spec["id"] = id
		spec["_doc_path"] = a_path
		spec["_kind"] = "shape"
		specs[id] = spec
		shapes[id] = spec


## Registers the speed ladder of the SpeedLibrary doc. Class names are UPPER_SNAKE (they read
## like the enum values they stand in for, and cannot be mistaken for a spec id); values are
## non-negative numbers of world units per second. There is exactly one ladder.
func _register_speed_library(a_path: String, a_data: Dictionary) -> void:
	if _speed_library_path != "":
		errors.append(
			(
				"%s: a second SpeedLibrary — the speed ladder already lives in %s"
				% [a_path, _speed_library_path]
			)
		)
		return
	_speed_library_path = a_path
	for key: Variant in a_data:
		if not SPEED_LIBRARY_KEYS.has(str(key)):
			errors.append(
				(
					"%s: unknown SpeedLibrary key '%s' (expected one of %s)"
					% [a_path, key, SPEED_LIBRARY_KEYS]
				)
			)
	var entries: Variant = a_data.get("speeds")
	if not (entries is Dictionary) or (entries as Dictionary).is_empty():
		errors.append(
			(
				"%s: a SpeedLibrary needs speeds: — a mapping of class name to world " % a_path
				+ "units per second"
			)
		)
		return
	var upper_snake := RegEx.create_from_string("^[A-Z][A-Z0-9_]*$")
	# The one rule on the values: listed slowest first, each strictly faster than the last, so
	# "one class up" always means faster. Spacing is free.
	var previous_name: String = ""
	var previous_value: float = -INF
	for key: Variant in entries:
		var name: String = str(key)
		var value: Variant = entries[key]
		if upper_snake.search(name) == null:
			errors.append(
				"%s: invalid speed class '%s' — it must be UPPER_SNAKE, e.g. BRISK" % [a_path, name]
			)
		elif not _is_number(value) or float(value) < 0.0:
			errors.append(
				(
					(
						"%s [%s]: a speed must be a non-negative number of world units per "
						% [a_path, name]
					)
					+ "second, got '%s'" % value
				)
			)
		else:
			if float(value) <= previous_value:
				errors.append(
					(
						(
							"%s [%s]: the ladder must be listed slowest first, each class faster "
							% [a_path, name]
						)
						+ (
							"than the one above it, but %s is not faster than %s (%s)"
							% [value, previous_name, previous_value]
						)
					)
				)
			previous_name = name
			previous_value = float(value)
			speeds[name] = float(value)


## Swaps every speed-class NAME in a piece or emission for its value from the SpeedLibrary:
## `movement.speed`, an emission's shorthand `speed:`, and each phase's `motion.speed`. A
## number where a name belongs is refused — the ladder is the source of truth, and a number
## would quietly step off it — as is a name the ladder does not have.
func _resolve_speed_classes() -> void:
	for id: Variant in pieces:
		var spec: Dictionary = pieces[id]
		var movement: Variant = spec.get("movement")
		if movement is Dictionary and (movement as Dictionary).has("speed"):
			movement["speed"] = _speed_of(spec, "movement.speed", movement["speed"])
	for id: Variant in projectiles:
		var spec: Dictionary = projectiles[id]
		if spec.has("speed"):
			spec["speed"] = _speed_of(spec, "speed", spec["speed"])
		if not (spec.get("phases") is Array):
			continue
		var phases: Array = spec["phases"]
		for i: int in phases.size():
			var phase: Variant = phases[i]
			if not (phase is Dictionary):
				continue
			var motion: Variant = (phase as Dictionary).get("motion")
			if motion is Dictionary and (motion as Dictionary).has("speed"):
				motion["speed"] = _speed_of(spec, "phases[%d].motion.speed" % i, motion["speed"])
			if motion is Dictionary and (motion as Dictionary).has("coast_speed"):
				motion["coast_speed"] = _speed_of(
					spec, "phases[%d].motion.coast_speed" % i, motion["coast_speed"]
				)


## The value of speed class `a_value`, or `a_value` itself (with an error recorded) when it
## is not a class the ladder has.
func _speed_of(a_spec: Dictionary, a_where: String, a_value: Variant) -> Variant:
	if a_value is String and speeds.has(a_value):
		return speeds[a_value]
	var known: String = ", ".join(PackedStringArray(speeds.keys()))
	if _is_number(a_value):
		_err(
			a_spec,
			(
				(
					"%s must NAME a speed class (one of %s), not a number — the values live in "
					% [a_where, known]
				)
				+ "the SpeedLibrary doc, gdd/movement/speed_classes.md"
			)
		)
	else:
		_err(a_spec, "%s '%s' is not a speed class (one of %s)" % [a_where, a_value, known])
	return a_value


## Why a `kind:` value was refused. A lowercase spelling of a class name gets the casing rule
## explained, since `PascalCase` is the one place the schema spells a value like a class — and
## it does so BECAUSE the value is a class; without the sentence it reads as a typo hunt.
func _unknown_kind_message(a_kind: String) -> String:
	for class_kind: String in KIND_FAMILIES:
		if class_kind.to_lower() == a_kind.to_lower().replace("_", ""):
			return (
				(
					"`kind: %s` names the class the spec loads as, so it is spelled as the "
					+ "class is: `kind: %s`"
				)
				% [a_kind, class_kind]
			)
	return (
		"unknown kind '%s' (expected one of %s)"
		% [a_kind, KIND_FAMILIES.keys() + [SHAPE_LIBRARY_KIND, SPEED_LIBRARY_KIND]]
	)


## Collection keys whose component an EMPTY LIST removes. Their components (Production,
## Builds, Loadout, EffectApplicator) are the ones the importer could create and needed a
## way to delete; see gdd/systems/authoring/composition-rework.md §Step 0.
##
## An empty list, because "trains nothing" and "is not a trainer" are the same claim about a
## piece: a component holding nothing states a distinction nobody can use. `false` was the
## spelling for a while and is refused now, as every retired spelling is.
const REMOVABLE_COLLECTION_KEYS: Array = ["trains", "builds", "weapons", "status_effects"]


## Records every removable collection the doc empties in the spec's `_remove` list, which is
## what SpecSceneSync reads to take the component away. A non-empty list is synced as usual,
## so re-adding entries later brings the component back.
func _normalize_removals(a_spec: Dictionary) -> void:
	var removed: Array = []
	for key: String in REMOVABLE_COLLECTION_KEYS:
		if not a_spec.has(key):
			continue
		if a_spec[key] is bool:
			_err(
				a_spec,
				(
					(
						"%s: %s is not a value — name the list, or write `%s: []` to remove "
						% [key, a_spec[key], key]
					)
					+ "the component"
				)
			)
			a_spec[key] = []
		if a_spec[key] is Array and (a_spec[key] as Array).is_empty():
			removed.append(key)
	a_spec["_remove"] = removed


## Fill in a piece's economy keys when its doc names none. See the constants above.
func _apply_piece_defaults(a_spec: Dictionary) -> void:
	if a_spec.has("variants"):
		return  # its price comes from the first variant (_resolve_variants), not a placeholder
	if not a_spec.has("cost"):
		a_spec["cost"] = {"energy": DEFAULT_PIECE_COST_ENERGY}
	if not a_spec.has("build_time"):
		a_spec["build_time"] = DEFAULT_PIECE_BUILD_TIME_SECONDS


## Replaces any inline `projectile: {...}` dict in a piece's weapons list with
## the resolved string id of a hoisted registry entry, so every later consumer
## (validation, scene sync) only ever sees a normal string id — same as a
## cross-doc reference.
func _hoist_inline_projectiles(a_spec: Dictionary) -> void:
	var weapons: Array = a_spec["weapons"]
	for i in weapons.size():
		var w: Variant = weapons[i]
		if not (w is Dictionary) or not (w.get("projectile") is Dictionary):
			continue
		var proj: Dictionary = w["projectile"]
		var wname: String = str(w.get("name", ""))
		var suffix: String = wname.to_snake_case() if wname != "" else str(i)
		var pid: String = str(proj["id"]) if proj.has("id") else "%s__%s" % [a_spec["id"], suffix]
		_register_inline_projectile(a_spec["_doc_path"], pid, proj)
		w["projectile"] = pid


## Registers a hoisted inline projectile exactly like a standalone spec doc
## (deep-duplicated, tagged with id/_doc_path/_kind) so it validates through
## the normal `_validate_projectile` pass and resolves normal cross-references.
## `_doc_path` is the OWNING unit/structure doc, for error messages — it has no
## markdown doc of its own. `_inline` marks it as having no frontmatter to
## persist a resolved scene path back into (see SpecSceneSync._ensure_projectile_scene).
func _register_inline_projectile(a_doc_path: String, a_id: String, a_data: Dictionary) -> void:
	if not _valid_id(a_id):
		errors.append(
			(
				(
					"%s: invalid inline projectile id '%s' (must start with a "
					+ "lowercase letter and contain only letters, digits, and "
					+ "underscores: [a-z][a-zA-Z0-9_]*)"
				)
				% [a_doc_path, a_id]
			)
		)
		return
	if specs.has(a_id):
		errors.append(
			(
				"%s: duplicate id '%s' (also defined in %s)"
				% [a_doc_path, a_id, specs[a_id]["_doc_path"]]
			)
		)
		return
	var spec: Dictionary = a_data.duplicate(true)
	spec["id"] = a_id
	spec["_doc_path"] = a_doc_path
	spec["_kind"] = "projectile"
	spec["_inline"] = true
	specs[a_id] = spec
	projectiles[a_id] = spec


## [a-z][a-zA-Z0-9_]* — lowercase-first, camelCase allowed within each
## underscore-separated `<faction>_<role>` component (an_commandCenter,
## cl_antiInfantry_lightBio). Plain snake_case (an_command_center) still
## matches this same pattern, so old-style ids remain valid too.
static func _valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	if not (id[0] >= "a" and id[0] <= "z"):
		return false
	for i in id.length():
		var c: String = id[i]
		if not (
			(c >= "a" and c <= "z")
			or (c >= "A" and c <= "Z")
			or (c >= "0" and c <= "9")
			or c == "_"
		):
			return false
	return true


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
func _validate(a_spec: Dictionary) -> void:
	var kind: String = a_spec["_kind"]
	if a_spec.has("scene"):
		var scene: String = str(a_spec["scene"])
		if not scene.begins_with("res://") or scene.get_extension() != "tscn":
			_err(a_spec, "scene must be a res://...tscn path, got '%s'" % scene)
		# One scene, one doc: two docs naming a scene each rewrite it on every run, the last one
		# winning, so the import never converges.
		elif _scene_owners.has(scene) and _scene_owners[scene] != a_spec["id"]:
			_err(
				a_spec,
				(
					"scene '%s' is already the scene of '%s' — every doc needs its own"
					% [scene, _scene_owners[scene]]
				)
			)
		else:
			_scene_owners[scene] = a_spec["id"]
		# A scene: naming a file that does not exist yet is NOT an error: every
		# kind is authored doc-first, and SpecSceneSync creates the skeleton at
		# the declared path (see its header). The cost of that is that a typo'd
		# path yields a stray new scene rather than a validation failure — the
		# importer log lists everything it created, so check that after a run.
	elif kind == "status_effect" or kind == "faction":
		_err(a_spec, "%s docs must have a scene: field" % kind)

	match kind:
		"piece":
			_validate_piece(a_spec)
		"projectile":
			_validate_projectile(a_spec)
		"faction":
			_validate_faction(a_spec)
		"ability":
			_validate_ability(a_spec)
		"upgrade":
			_validate_upgrade(a_spec)
		"shape":
			_validate_shape(a_spec)


func _validate_piece(a_spec: Dictionary) -> void:
	if not SpecSchema.has_discriminator(a_spec):
		_err(
			a_spec,
			(
				"declares no body and no sense — a piece needs footprint:, movement: "
				+ "or senses.vision:"
			)
		)
	# A scalar here (the old flat `cost: 1000` spelling, or a plain typo) is silently
	# read as "not a Dictionary" by every consumer (technology_json, _cost_phrase) and
	# priced as free — see CLAUDE.md §10, validation must fail loud rather than half-apply.
	if a_spec.has("cost") and not (a_spec["cost"] is Dictionary):
		_err(
			a_spec,
			(
				"%s must be a mapping of energy/infrastructure/dominion, got %s"
				% [SpecSchema.doc_key("cost"), a_spec["cost"]]
			)
		)
	_check_enum(a_spec, "armour", Defense.ArmourType)
	_check_enum(a_spec, "frame", Defense.FrameType)
	if a_spec.has("movement"):
		_validate_movement(a_spec, a_spec["movement"])
	if a_spec.has("aerial"):
		_validate_aerial(a_spec, a_spec["aerial"])
	if a_spec.has("docking"):
		_validate_docking(a_spec)
	_validate_family(a_spec)
	if a_spec.has("researches"):
		_validate_researches(a_spec)
	for key in ["requires", "trains", "builds"]:
		if not a_spec.has(key):
			continue
		if not (a_spec[key] is Array):
			_err(a_spec, "%s must be a list" % SpecSchema.doc_key(key))
			continue
		for ref in a_spec[key]:
			var rid: String = str(ref)
			if not pieces.has(rid):
				_err(a_spec, "%s references unknown piece '%s'" % [SpecSchema.doc_key(key), rid])
			elif key == "requires" and not SpecSchema.is_fixture(pieces[rid]):
				_err(a_spec, "build.requires must name structures; '%s' has no footprint:" % rid)
	# A capability with nothing to configure: `repairs: true` gives the piece a Repairs
	# component, anything else omits it. Spelled out as a bool rather than accepting a
	# truthy string so `repairs: yes` fails loudly instead of importing as "yes" == true.
	if a_spec.has("repairs") and not (a_spec["repairs"] is bool):
		_err(a_spec, "repairs must be true or false")
	# Same shape as `repairs:` — a capability with nothing to configure. A Stealth node
	# has no exports at all: the mechanic is entirely in the component's presence, its
	# three-state machine, and the DetectionRange volumes that reveal it.
	if a_spec.has("stealth") and not (a_spec["stealth"] is bool):
		_err(a_spec, "stealth must be true or false")
	# Identity components: presence only, their tuning is scene-authored (SpecSceneSync.
	# IDENTITY_COMPONENTS).
	for key: String in ["shelter", "extraction_site", "extractor"]:
		if a_spec.has(key) and not (a_spec[key] is bool):
			_err(a_spec, "%s must be true or false — its tuning lives in the scene" % key)
	if a_spec.has("garrison"):
		_validate_garrison(a_spec, a_spec["garrison"])
	if a_spec.has("deploys"):
		_validate_deploys(a_spec, a_spec["deploys"])
	# How much of a host's `capacity` this piece consumes when garrisoned. The other half
	# of the garrison mechanic: capacity is OCCUPANCY, not a head count, so a capacity-4
	# host takes four soldiers or two collectives.
	if a_spec.has("occupancy_size"):
		var os: Variant = a_spec["occupancy_size"]
		if not (os is int) or int(os) < 1 or int(os) > 16:
			_err(a_spec, "occupancy_size must be an int in 1..16")
	if a_spec.has("footprint"):
		var fp: Variant = a_spec["footprint"]
		if not (fp is Array and fp.size() == 2 and fp[0] is int and fp[1] is int):
			_err(a_spec, "footprint must be [width, length] ints")
	# Vision and detection name shape-library buckets; the physical bodies are still radii.
	# A sense may be removed (false / empty) — that is how a piece opts out of seeing — but
	# a body of radius 0 has no footprint to push through the world or be shot at.
	_resolve_shape_key(a_spec, "vision")
	_check_radius(a_spec, "vision", true)
	_check_radius(a_spec, "beacon_range", true)
	_validate_ability_groups(a_spec)
	# What this piece can SEE THROUGH stealth with. Zero-or-absent is the overwhelming
	# majority: a detector is a deliberate, rare capability, and the counterpart of the
	# `stealth:` flag above.
	_resolve_shape_key(a_spec, "detection")
	_check_radius(a_spec, "detection", true)
	_check_radius(a_spec, "movement_radius", false)
	_check_radius(a_spec, "hurtbox_radius", false)
	if a_spec.has("infrastructure") and not (a_spec["infrastructure"] is int):
		# One signed int: positive provides, negative consumes. Catches docs still on
		# the old {capacity: N} / {upkeep: N} mapping form.
		_err(a_spec, "infrastructure must be a single int (positive provides, negative consumes)")
	if a_spec.has("weapons"):
		if not (a_spec["weapons"] is Array):
			_err(a_spec, "weapons must be a list")
		else:
			var seen_names: Dictionary = {}
			for w in a_spec["weapons"]:
				if not (w is Dictionary):
					_err(a_spec, "each weapons entry must be a mapping")
					continue
				_validate_weapon(a_spec, w, seen_names)
			_validate_charged_can_rearm(a_spec)
	if a_spec.has("ui") and a_spec["ui"] is Dictionary:
		_validate_ui(a_spec, a_spec["ui"])


## Runs the calibration rules (SpecRules) over every piece, after per-key validation has
## finished. Ordered that way deliberately: a rule reasons about a piece's numbers as a
## whole, so it should not be handed a doc whose individual values are still known-bad — an
## `orbit_speed` on a ground unit would otherwise produce a turn-radius complaint as well as
## the real error, and the reader has to work out which one to fix.
##
## UNACCEPTED and STALE become errors, so a roster that breaks a norm without saying so
## cannot be imported. EXCEPTIONAL becomes an entry in `exceptional` and INCOMPLETE one in
## `incomplete` — never errors, and never silent either.
##
## Emissions run the rules too: none of the doc-only rules has anything to say about one, but
## an emission can waive `has_mesh_visual` like any piece.
func _apply_calibration_rules() -> void:
	var ruled: Dictionary = pieces.duplicate()
	ruled.merge(projectiles)
	var ids: Array = ruled.keys()
	ids.sort()
	for id in ids:
		var spec: Dictionary = ruled[id]
		for complaint: String in SpecRules.validate_exceptions_block(spec):
			_err(spec, complaint)
		var facts: Dictionary = _asset_facts(StringName(id), spec, pieces.has(id))
		if pieces.has(id) and SpecSchema.is_commandable(spec):
			_warn_on_dial_overflow(spec)
		for entry: Dictionary in SpecRules.evaluate(spec, facts):
			match int(entry["verdict"]):
				SpecRules.Verdict.UNACCEPTED:
					_err(
						spec,
						(
							"%s [%s]: %s. Fix the numbers%s"
							% [
								entry["id"],
								entry["severity"],
								entry["detail"],
								(
									""
									if str(entry["severity"]) == SpecRules.STRUCTURAL
									else (
										(
											", or declare the departure:\n      "
											+ "exceptions:\n        %s: <why this piece is "
											+ "built that way>"
										)
										% entry["id"]
									)
								)
							]
						)
					)
				SpecRules.Verdict.STALE:
					_err(
						spec,
						(
							(
								"exceptions declares '%s' but %s — delete the "
								+ "declaration (a waiver that outlives the value it waived "
								+ "reads as deliberate when it is not)"
							)
							% [entry["id"], entry["detail"]]
						)
					)
				SpecRules.Verdict.EXCEPTIONAL:
					(
						exceptional
						. append(
							{
								"id": str(id),
								"rule": str(entry["id"]),
								"what": str(entry["what"]),
								"detail": str(entry["detail"]),
								"reason": str(entry["reason"]),
							}
						)
					)
				SpecRules.Verdict.INCOMPLETE:
					(
						incomplete
						. append(
							{
								"id": str(id),
								"rule": str(entry["id"]),
								"what": str(entry["what"]),
								"detail": str(entry["detail"]),
								"state": entry["asset_state"],
							}
						)
					)


## The facts SpecRules' ASSET rules judge, gathered for every piece and emission: whether its
## scene holds authored art, and — for a piece — what its sound tables and HUD icon hold.
## Every scene is loaded to answer the first, which is the price of reporting every unfilled
## model rather than only the waived ones. A scene that does not exist yet has no art, which is
## the true answer for a doc-first piece. The sound tables report their own completeness; they
## are loaded, not preloaded, so the importer never depends on them compiling to validate
## anything else.
func _asset_facts(a_id: StringName, a_spec: Dictionary, a_is_piece: bool) -> Dictionary:
	var facts: Dictionary = {"has_authored_mesh": false}
	var path: String = str(a_spec.get("scene", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var instance: Node = (load(path) as PackedScene).instantiate()
		facts["has_authored_mesh"] = VisualMeasure.has_authored_mesh(instance)
		instance.free()
	if not a_is_piece:
		return facts
	var voice: Script = load(VOICE_LINES_SCRIPT)
	if voice != null:
		facts["missing_line_types"] = voice.missing_line_types(a_id)
	var death: Script = load(DEATH_BARKS_SCRIPT)
	if death != null:
		facts["has_death_clip"] = death.has_clip(a_id)
	var icons: Script = load(PIECE_ICONS_SCRIPT)
	if icons != null:
		facts["hud_icon"] = (
			SpecRules.HUD_ICON_MISSING
			if not icons.has_icon(a_id)
			else (
				SpecRules.HUD_ICON_PLACEHOLDER
				if icons.is_placeholder(a_id)
				else SpecRules.HUD_ICON_FINAL
			)
		)
	return facts


## A piece needing more charge dials than its HUD card fits — one per ability pool that is
## CAST, one per weapon slow or charged enough to plan around (ChargeDial). A WARNING, not an
## error: the game draws the first that fit and logs the rest, and no piece comes close today.
func _warn_on_dial_overflow(a_spec: Dictionary) -> void:
	var card_script: Script = load(COMMANDABLE_CARD_SCRIPT)
	if card_script == null:
		return
	var needed: int = charge_dials_needed(a_spec, abilities)
	var capacity: int = card_script.dial_capacity(card_script.CARD_SIZE.y)
	if needed > capacity:
		warnings.append(
			(
				"%s [%s]: needs %d charge dials but a HUD card fits %d — the rest will not be drawn"
				% [a_spec["_doc_path"], a_spec["id"], needed, capacity]
			)
		)


## How many charge dials `spec`'s card draws — its production queue, its cast pools, its slow
## weapons — given every ability doc by id (`ability_specs`) to tell a cast pool from a passive
## one. The doc-side twin of CommandableCard._build_dials.
static func charge_dials_needed(spec: Dictionary, ability_specs: Dictionary) -> int:
	var dial_script: Script = load(CHARGE_DIAL_SCRIPT)
	# A producer's queue is a dial of its own (ChargeDial.production_state).
	var needed: int = 1 if spec.has("trains") or spec.has("researches") else 0
	for pool: Variant in spec.get("abilities", []):
		var grants: Array = (pool as Dictionary).get("grants", []) if pool is Dictionary else []
		if grants.any(
			func(g: Variant) -> bool:
				return not bool((ability_specs.get(str(g), {}) as Dictionary).get("passive", false))
		):
			needed += 1
	for weapon: Variant in spec.get("weapons", []):
		if weapon is Dictionary and dial_script.wants_weapon_dial(
			float((weapon as Dictionary).get("reload_time", 0.0)),
			bool((weapon as Dictionary).get("charged", false))
		):
			needed += 1
	return needed


## The keys a piece with `variants:` must NOT author: each is taken from its first (default)
## variant, and an authored copy would be a second value that could disagree with it.
const VARIANT_DERIVED_KEYS: Array = ["footprint", "hp", "cost", "build_time", "infrastructure"]


## `variants:` — the underlying pieces a piece is built from (Anarchical `an_infrastructure` is
## built from a neutral building). Validates the list, then fills the piece's footprint, hp,
## cost, build time and infrastructure from the FIRST entry, the default variant, so the
## composed scene, the tool's tooltips and the technology price all describe a real piece.
## Which variant a given build actually uses is a runtime choice; these are the defaults.
##
## A variant must be a structure that belongs to a family: the family is what publishes the
## variant's template data (resources/generated/families.json) for the runtime to read.
func _resolve_variants() -> void:
	for id: Variant in pieces:
		var spec: Dictionary = pieces[id]
		if not spec.has("variants"):
			continue
		var variants: Variant = spec["variants"]
		if not (variants is Array) or (variants as Array).is_empty():
			_err(spec, "variants must be a non-empty list of structure piece ids")
			continue
		for key: String in VARIANT_DERIVED_KEYS:
			if spec.has(key):
				_err(
					spec,
					(
						"%s is taken from the first variant — remove it from the doc"
						% SpecSchema.doc_key(key)
					)
				)
		var first: Dictionary = {}
		for ref: Variant in variants as Array:
			var vid: String = str(ref)
			if not pieces.has(vid):
				_err(spec, "variants references unknown piece '%s'" % vid)
			elif not SpecSchema.is_fixture(pieces[vid]):
				_err(spec, "variants must name structures; '%s' has no footprint:" % vid)
			elif not pieces[vid].has("family"):
				_err(spec, "variants must name family members; '%s' has no family:" % vid)
			elif pieces[vid].has("variants"):
				_err(spec, "variant '%s' has variants of its own — a variant is a leaf" % vid)
			elif first.is_empty():
				first = pieces[vid]
		if first.is_empty():
			continue
		for key: String in VARIANT_DERIVED_KEYS:
			if first.has(key):
				var value: Variant = first[key]
				spec[key] = (
					value.duplicate(true) if value is Array or value is Dictionary else value
				)


## `family:` — membership of a named piece family (SpecSchema.FAMILIES). A member is a
## structure (the family is enumerated for placement and conversion targets).
func _validate_family(a_spec: Dictionary) -> void:
	if not a_spec.has("family"):
		return
	if not SpecSchema.FAMILIES.has(str(a_spec["family"])):
		_err(a_spec, "family '%s' is not one of %s" % [a_spec["family"], SpecSchema.FAMILIES])
	elif not SpecSchema.is_fixture(a_spec):
		_err(a_spec, "family members must be structures; this piece has no footprint:")


## The `movement:` block — the chassis. Every key is validated against MOVEMENT_KEYS, so an
## unknown one is a HARD ERROR rather than a silently-ignored line.
##
## That whitelist is not pedantry: it is the drift vector this schema was missing. Because
## an unrecognised sub-key was simply skipped, four real chassis knobs
## (`min_turn_speed_ratio`, `reverse_speed_ratio`, `orbit_radius`, `orbit_speed`) lived only
## in scenes, invisible to the docs that claim to govern the piece — and a doc that tries to
## set one and is ignored is worse than one that never tried, because it reads as authority
## it does not have. A typo in `turn_rate` has exactly the same shape.
const MOVEMENT_KEYS: Array = [
	"speed",
	"turn_rate",
	"max_acceleration",
	"max_deceleration",
	"crush_class",
	"min_turn_speed_ratio",
	"reverse_speed_ratio"
]

## `movement:` keys that moved to another component's key, and where. Named, not merely
## unknown, so a doc written before the move says what to write instead.
const MOVEMENT_KEYS_MOVED: Dictionary = {
	"mode":
	(
		"aerial.mode — a piece that flies names its mode under `aerial:`; one that does "
		+ "not names none"
	),
	"orbit_radius": "aerial.orbit_radius",
	"orbit_speed": "aerial.orbit_speed",
	"docks": "docking: true — a piece that docks says so; `docks: false` is simply no key",
}

## Sub-keys that are a FRACTION of a speed, so they are bounded at both ends. Authoring one
## above 1.0 says the unit travels faster while manoeuvring than while driving straight,
## which is not a stance any chassis has — `an_mechStrong_transport` carried 1.5 for exactly
## as long as nothing checked.
const MOVEMENT_RATIO_KEYS: Array = ["min_turn_speed_ratio", "reverse_speed_ratio"]


func _validate_movement(a_spec: Dictionary, a_m: Variant) -> void:
	if not (a_m is Dictionary):
		_err(a_spec, "movement must be a mapping (e.g. {mode: GROUNDED, speed: 1.5})")
		return
	var m: Dictionary = a_m
	for key in m:
		if MOVEMENT_KEYS_MOVED.has(str(key)):
			_err(a_spec, "movement.%s moved — use %s" % [key, MOVEMENT_KEYS_MOVED[str(key)]])
		elif not MOVEMENT_KEYS.has(str(key)):
			_err(a_spec, "unknown movement key '%s' (expected one of %s)" % [key, MOVEMENT_KEYS])
	if m.has("crush_class") and not Movement.CrushClass.has(str(m["crush_class"])):
		_err(a_spec, "movement.crush_class '%s' is not a Movement.CrushClass" % m["crush_class"])
	for key: String in ["speed", "turn_rate"]:
		if m.has(key) and (not _is_number(m[key]) or float(m[key]) < 0.0):
			_err(a_spec, "movement.%s must be a non-negative number" % key)
	if (
		m.has("max_acceleration")
		and (not _is_number(m["max_acceleration"]) or float(m["max_acceleration"]) <= 0.0)
	):
		_err(a_spec, "movement.max_acceleration must be a positive number of world-units/s^2")
	# Signed, and NEGATIVE — it is the floor on a rate of change, not a magnitude, and the
	# component compares against it directly (`-INF` is the unbounded default). A doc that
	# writes it positive has said "may not slow below +3 u/s^2", which stops the unit dead.
	if (
		m.has("max_deceleration")
		and (not _is_number(m["max_deceleration"]) or float(m["max_deceleration"]) >= 0.0)
	):
		_err(
			a_spec,
			"movement.max_deceleration must be NEGATIVE (it is a signed floor, not a magnitude)"
		)
	for key: String in MOVEMENT_RATIO_KEYS:
		if not m.has(key):
			continue
		if not _is_number(m[key]) or float(m[key]) < 0.0 or float(m[key]) > 1.0:
			_err(a_spec, "movement.%s must be a fraction in 0..1 (got %s)" % [key, m[key]])
	_validate_movement_modes(a_spec, m)


## Half the chassis knobs belong to ONE locomotion mode and are read nowhere else — the
## orbit is flown only by a fixed wing, reversing is a helicopter manoeuvre, and a nosewheel
## turn is a ground vehicle's. Setting one on the wrong chassis is INERT: it is written into
## the scene, shows in the inspector, reads as a tuned value, and changes nothing.
##
## That is worth an error rather than a shrug, because it is indistinguishable from a knob
## that IS doing something until you go and read which branch of `Movement._physics_process`
## consumes it. Two scenes were carrying five such values between them — a GROUNDED warlord
## with an orbit and a reverse ratio, a HOVERING technician with an orbit — none of which had
## ever been read.
const MOVEMENT_MODE_ONLY: Dictionary = {
	"min_turn_speed_ratio": ["GROUNDED"],
	"reverse_speed_ratio": ["HOVERING"],
	"aerial.orbit_radius": ["FLYING"],
	"aerial.orbit_speed": ["FLYING"],
}


func _validate_movement_modes(a_spec: Dictionary, a_m: Dictionary) -> void:
	var mode: String = _mode_of(a_spec)
	if not Movement.Mode.has(mode):
		return  # already reported; do not pile a second error on one typo
	for key: String in MOVEMENT_MODE_ONLY:
		var parts: PackedStringArray = key.split(".")
		var block: Variant = a_spec.get("aerial") if parts.size() > 1 else a_m
		if not (block is Dictionary and (block as Dictionary).has(parts[parts.size() - 1])):
			continue
		var modes: Array = MOVEMENT_MODE_ONLY[key]
		if not modes.has(mode):
			_err(
				a_spec,
				(
					"%s is read only in %s, and this piece is %s — the value would be inert"
					% [key if parts.size() > 1 else "movement." + key, " / ".join(modes), mode]
				)
			)


## The piece's locomotion mode: its `aerial.mode`, or GROUNDED for a piece that does not fly.
static func _mode_of(a_spec: Dictionary) -> String:
	var aerial: Variant = a_spec.get("aerial")
	return str(aerial.get("mode", "")) if aerial is Dictionary else "GROUNDED"


## The `aerial:` block — flight. Its presence makes the piece an aircraft; `mode` says which
## kind and is required, since GROUNDED is not a way of flying.
const AERIAL_KEYS: Array = ["mode", "orbit_radius", "orbit_speed"]
const AERIAL_MODES: Array = ["HOVERING", "FLYING"]


func _validate_aerial(a_spec: Dictionary, a_a: Variant) -> void:
	if not (a_a is Dictionary):
		_err(a_spec, "aerial must be a mapping (e.g. {mode: HOVERING})")
		return
	var a: Dictionary = a_a
	for key in a:
		if not AERIAL_KEYS.has(str(key)):
			_err(a_spec, "unknown aerial key '%s' (expected one of %s)" % [key, AERIAL_KEYS])
	if not AERIAL_MODES.has(str(a.get("mode", ""))):
		_err(a_spec, "aerial.mode must be one of %s (got '%s')" % [AERIAL_MODES, a.get("mode", "")])
	for key: String in ["orbit_radius", "orbit_speed"]:
		if a.has(key) and (not _is_number(a[key]) or float(a[key]) < 0.0):
			_err(a_spec, "aerial.%s must be a non-negative number" % key)
	if not a_spec.has("movement"):
		_validate_movement_modes(a_spec, {})


## `deploys: {time: 3, undeploy_time: 1, cancellable: false}` — a unit that can plant itself
## (Deployable). Every sub-key is required: the times are the commitment, and whether a
## deploy may be called off is a per-unit decision, never a default. `false` removes it.
## Only a piece that moves can deploy: planting is giving up locomotion.
func _validate_deploys(a_spec: Dictionary, a_value: Variant) -> void:
	if a_value is bool and a_value == false:
		return
	if not (a_value is Dictionary):
		_err(a_spec, "deploys must be {time, undeploy_time, cancellable} or false")
		return
	var deploys: Dictionary = a_value
	for key: String in ["time", "undeploy_time"]:
		var seconds: Variant = deploys.get(key)
		if not (seconds is int or seconds is float) or float(seconds) <= 0.0:
			_err(a_spec, "deploys.%s must be a positive number of seconds" % key)
	if not (deploys.get("cancellable") is bool):
		_err(a_spec, "deploys.cancellable must be true or false")
	for key: String in deploys:
		if not key in ["time", "undeploy_time", "cancellable"]:
			_err(a_spec, "deploys has an unknown key '%s'" % key)
	if not a_spec.has("movement"):
		_err(a_spec, "deploys needs movement: — only a piece that moves can plant itself")


## `docking:` — whether the piece docks at airfields. A presence bool, like `repairs:`.
func _validate_docking(a_spec: Dictionary) -> void:
	if not (a_spec["docking"] is bool):
		_err(a_spec, "docking must be true or false")
		return
	# TODO: a ground unit that docks is planned, and needs an arrival of its own — every dock
	# today is a deck an aircraft lands on. See docking.gd.
	if bool(a_spec["docking"]) and not a_spec.has("aerial"):
		_err(a_spec, "docking: true needs aerial: — docking without flight is not built yet")


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


## The `garrison:` block — what a host will hold. Two independent questions, and the schema
## keeps them apart exactly as [Garrison] does: WHO may enter (three enum lists, which
## become the occupancy bitmasks) and HOW MUCH the host has room for (`capacity`, which is
## OCCUPANCY rather than a head count — see each piece's `occupancy_size`).
##
## `closed: true` is the CLOSED HOLD (Garrison.is_closed): every mask cleared, so nothing
## can be ordered IN and the host fills only by capture, deposit or scenario authoring —
## the Colonial stock truck's cage. Getting OUT is a separate statement, `releasable:`,
## which defaults true even for a hold. It gets a named key rather
## than three empty lists because the domain already has the name, and because clearing the
## masks by hand is easy to get HALF right: two empty lists and one populated is not a
## closed hold, it is a garrison nothing happens to notice is broken. The stock truck's
## cage is one; the Compound is NOT — it admits Servants by order.
##
## `pieces:` is a fourth admission filter, and the only one that is an ALLOWLIST rather
## than an enumeration: naming it restricts entry to those piece ids, omitting it restricts
## nothing (see Garrison.occupiable_ids). `sentence_length:` is what makes a garrison a
## prison — a captive deposited here serves that many seconds before being consumed (see
## Garrison.can_intern) — replacing the old `interns:` conversion marker.
const GARRISON_KEYS: Array = [
	"capacity",
	"frames",
	"armours",
	"movements",
	"closed",
	"releasable",
	"bunker",
	"preserve_occupants",
	"range_bonus",
	"reach_by_piece",
	"pieces",
	"sentence_length"
]
const GARRISON_MASK_KEYS: Array = ["frames", "armours", "movements"]
const GARRISON_ENUMS: Dictionary = {
	"frames": ["BIO", "MECH"],
	"armours": ["LIGHT", "MEDIUM", "STRONG"],
	# The same spelling `aerial.mode` uses (GROUNDED for a piece that does not fly), so one
	# locomotion vocabulary serves both.
	"movements": ["GROUNDED", "HOVERING", "FLYING"],
}


func _validate_garrison(a_spec: Dictionary, a_g: Variant) -> void:
	# `false` removes the component outright, mirroring `repairs: false`. `true` is NOT
	# accepted: a garrison always has a capacity and a set of things it admits, so there is
	# no meaningful "on with nothing said" — write `{}` to take every default explicitly.
	if a_g is bool:
		if bool(a_g):
			_err(a_spec, "garrison: true says nothing — use a mapping ({} takes every default)")
		return
	if not (a_g is Dictionary):
		_err(a_spec, "garrison must be a mapping (e.g. {capacity: 4, frames: [BIO]}), or false")
		return
	var g: Dictionary = a_g
	for key in g:
		if not GARRISON_KEYS.has(str(key)):
			_err(a_spec, "unknown garrison key '%s' (expected one of %s)" % [key, GARRISON_KEYS])
	if g.has("capacity") and not (g["capacity"] is int and int(g["capacity"]) >= 0):
		_err(a_spec, "garrison.capacity must be a non-negative int")
	for flag in ["closed", "releasable", "bunker", "preserve_occupants"]:
		if g.has(flag) and not (g[flag] is bool):
			_err(a_spec, "garrison.%s must be true or false" % flag)
	if g.has("range_bonus"):
		_resolve_range_bonus(a_spec, g)
	for key: String in GARRISON_MASK_KEYS:
		if not g.has(key):
			continue
		if not (g[key] is Array):
			_err(a_spec, "garrison.%s must be a list of %s" % [key, GARRISON_ENUMS[key]])
			continue
		for v in g[key]:
			if not GARRISON_ENUMS[key].has(str(v)):
				_err(a_spec, "garrison.%s: '%s' is not one of %s" % [key, v, GARRISON_ENUMS[key]])
	# A closed hold IS "every mask cleared", so naming an occupancy list beside it states
	# two different things at once. Caught here rather than silently letting one win.
	if bool(g.get("closed", false)):
		for key: String in GARRISON_MASK_KEYS:
			if g.has(key):
				_err(
					a_spec,
					(
						(
							"garrison.closed is every mask cleared — remove `%s`, or "
							+ "drop `closed` and list what may enter"
						)
						% key
					)
				)
		# Same reasoning one step further out: an allowlist narrows what the masks admit, and
		# a closed hold admits nothing to narrow. The pair reads as "only Servants may enter,
		# and nobody may enter".
		if g.has("pieces"):
			_err(
				a_spec,
				"garrison.closed admits nobody, so `pieces` can never apply — drop one of them"
			)
	# An allowlist of piece ids. Validated against the registry like every other id
	# reference, so a renamed piece fails the import rather than silently shutting the
	# host's door.
	if g.has("pieces"):
		if not (g["pieces"] is Array):
			_err(a_spec, "garrison.pieces must be a list of piece ids")
		else:
			for ref in g["pieces"]:
				if not pieces.has(str(ref)):
					_err(a_spec, "garrison.pieces references unknown piece '%s'" % str(ref))
	# Per-occupant reach: piece id -> a reach bucket that REPLACES the occupant's own reach.
	# Ids are checked against the registry for the same reason `pieces` is.
	if g.has("reach_by_piece"):
		_resolve_reach_by_piece(a_spec, g)
	if (
		g.has("sentence_length")
		and not (
			(g["sentence_length"] is int or g["sentence_length"] is float)
			and float(g["sentence_length"]) > 0.0
		)
	):
		_err(a_spec, "garrison.sentence_length must be a positive number of seconds")


## `garrison.range_bonus:` names two reach buckets, `{from: …, to: …}`, and the bonus is the
## gap between their radii — so a bonus meant to lift one tier to another keeps doing so when
## the library is retuned. Never a number, for the same reason `reach:` is not. Resolved in
## place to that number, which is what the scene sync writes.
func _resolve_range_bonus(a_spec: Dictionary, a_g: Dictionary) -> void:
	var pair: Variant = a_g["range_bonus"]
	a_g.erase("range_bonus")
	var keys: Array = (pair as Dictionary).keys().map(str) if pair is Dictionary else []
	keys.sort()
	if keys != ["from", "to"]:
		_err(
			a_spec,
			(
				"garrison.range_bonus names two reach buckets, {from: <id>, to: <id>}; "
				+ "the bonus is the gap between them, got '%s'" % str(pair)
			)
		)
		return
	var radii: Array = ["from", "to"].map(
		func(k: String) -> float:
			return _library_radius(a_spec, "garrison.range_bonus.%s" % k, pair[k])
	)
	if radii.has(-1.0):
		return
	if radii[1] < radii[0]:
		_err(
			a_spec,
			(
				"garrison.range_bonus lifts from a shorter bucket to a longer one, "
				+ "but '%s' is shorter than '%s'" % [pair["to"], pair["from"]]
			)
		)
		return
	a_g["range_bonus"] = radii[1] - radii[0]


## `garrison.reach_by_piece:` maps an occupant piece id to the reach bucket it fires out of
## this garrison with, in place of its own. Resolved in place to {id: radius}.
func _resolve_reach_by_piece(a_spec: Dictionary, a_g: Dictionary) -> void:
	var by_piece: Variant = a_g["reach_by_piece"]
	a_g.erase("reach_by_piece")
	if not (by_piece is Dictionary):
		_err(a_spec, "garrison.reach_by_piece must be a mapping of piece id to reach bucket")
		return
	var radii: Dictionary = {}
	for ref in by_piece:
		if not pieces.has(str(ref)):
			_err(a_spec, "garrison.reach_by_piece references unknown piece '%s'" % str(ref))
		var radius: float = _library_radius(
			a_spec, "garrison.reach_by_piece.%s" % str(ref), by_piece[ref]
		)
		if radius >= 0.0:
			radii[str(ref)] = radius
	a_g["reach_by_piece"] = radii


## The radius of the library shape `a_shape_id` names, or -1.0 (with an error against
## `a_key`) when it names none.
func _library_radius(a_spec: Dictionary, a_key: String, a_shape_id: Variant) -> float:
	if not (a_shape_id is String) or not shapes.has(a_shape_id):
		_err(
			a_spec,
			(
				"%s must name a shape from the library (one of %s), got '%s'"
				% [a_key, _sorted_keys(shapes), a_shape_id]
			)
		)
		return -1.0
	return float(shapes[a_shape_id].get("radius", -1.0))


## A CHARGED weapon is one that never reloads in the field: it is refilled only by docking
## at an airfield (see Weapon.charged). So a piece that carries one and CANNOT dock fires
## its clip once and is then permanently unarmed, with nothing in the game able to fix it.
##
## That is a silent, total loss of a unit's purpose, and it is easy to author by accident
## in either direction — putting `charged` on a unit that does not dock, or dropping
## `docking:` from one that does. Caught here, where the doc is being read, rather than
## surfacing in play as "why has my aircraft stopped shooting". Nothing about a charged weapon
## makes sense without a way back to a pad.
func _validate_charged_can_rearm(a_spec: Dictionary) -> void:
	var has_charged: bool = false
	for w in a_spec["weapons"]:
		if w is Dictionary and bool(w.get("charged", false)):
			has_charged = true
			break
	if not has_charged:
		return
	if not bool(a_spec.get("docking", false)):
		_err(
			a_spec,
			(
				"has a charged weapon but no `docking: true` — it would fire its clip "
				+ "once and be unarmed for the rest of its life"
			)
		)


## The `ui:` block: what the piece looks like in the command grid.
##
## There is no `ui.label` key. The button's text is the doc's `title` — the one
## user-facing display name a piece has — so a second name here could only ever
## disagree with it (which is exactly what it had done: the grid read `label`, so
## docs whose label was still the raw id showed an id on the button while their
## title said "Stronghold"). A doc carrying one is a hard error, in the same spirit
## as the `id:` key: the old form can never silently win over the new one.
func _validate_ui(a_spec: Dictionary, a_ui: Dictionary) -> void:
	if a_ui.has("label"):
		_err(
			a_spec,
			(
				"remove `ui.label` — a grid button is titled by the doc's `title:` (this doc's is '%s')"
				% str(a_spec.get("title", ""))
			)
		)
	# `context_grid` is a PRODUCER's cell in row 0 of the PRODUCTION card — the radio button
	# that picks whose training the card is showing. A second cell rather than a reuse of
	# `grid`, because `grid` is already spoken for: it is where this piece's own BUILD button
	# sits on a builder's menu, which is a different button in a different list.
	#
	# `grid` is the button's home cell. `active_grid` is the SECOND cell an ability may claim
	# on the ACTIVE card as well — see the Bombard, which is both an order you give a selected
	# gun and a strike the commander calls in without selecting anything. A second cell rather
	# than one cell on two cards, because the two cards have different neighbours and a cell
	# that is free on one is spoken for on the other.
	for key: String in ["grid", "active_grid", "context_grid"]:
		if not a_ui.has(key):
			continue
		var g: Variant = a_ui[key]
		if not (g is Array and g.size() == 2 and g[0] is int and g[1] is int):
			_err(a_spec, "ui.%s must be [column, row] ints" % key)
		elif not ControlBinding.position_in_bounds(Vector2i(int(g[0]), int(g[1]))):
			_err(
				a_spec,
				(
					"ui.%s %s is outside the %dx%d command grid"
					% [key, g, ControlBinding.GRID_WIDTH, ControlBinding.GRID_HEIGHT]
				)
			)
	# Every faction name must have a ControlBinding.Faction member. Without this the name
	# silently fell through to FACTION_ANY, which made the piece collide with every other
	# piece in its cell — the grid review was drowning in 216 such reports before the four
	# missing members were added. Caught here rather than at load so the doc that carries
	# the typo is what gets named. (ControlBinding rather than the Tool registry, which is
	# the previous run's tools.json.)
	for fname in a_ui.get("factions", []):
		if not ControlBinding.Faction.has(str(fname).to_upper()):
			_err(
				a_spec,
				(
					"unknown ui faction '%s' — add it to ControlBinding.Faction (have: %s)"
					% [fname, ", ".join(ControlBinding.Faction.keys()).to_lower()]
				)
			)
	# A piece IN the grid is one the player reads off a button, so an unauthored title
	# leaves them looking at a raw id. A title that merely REPEATS the id is the same
	# thing spelled out, so both are reported. A warning, not an error: a placeholder
	# piece must still be placeable while its copy is being written.
	var title: String = str(a_spec.get("title", "")).strip_edges()
	if title.is_empty() or title == str(a_spec["id"]):
		warnings.append(
			(
				"%s [%s]: no display title — its grid button reads as the raw id"
				% [a_spec["_doc_path"], a_spec["id"]]
			)
		)


## Every key a `weapons:` entry may carry. Whitelisted for the same reason `movement:` is —
## an unrecognised key was silently skipped, so a doc could set one and be ignored while
## reading as authoritative. It is also what retires a key cleanly: `dive:` is gone (a dive
## is now derived from the weapon's reach, see Weapon.is_melee_ranged), and without this a
## doc still carrying it would quietly do nothing.
const WEAPON_KEYS: Array = [
	"name",
	"projectile",
	"melee_damage",
	"melee_damage_type",
	"split_time",
	"reload_time",
	"startup_time",
	"clip_size",
	"charged",
	"turret",
	"turret_turn_rate",
	"reach",
	"hits"
]


func _validate_weapon(a_spec: Dictionary, a_weapon: Dictionary, a_seen: Dictionary) -> void:
	for key in a_weapon:
		if not WEAPON_KEYS.has(str(key)):
			var hint: String = ""
			if str(key) == "dive":
				hint = (
					" — a dive is now DERIVED from the weapon's reach "
					+ "(Weapon.is_melee_ranged), so remove the key"
				)
			_err(
				a_spec, "unknown weapon key '%s' (expected one of %s)%s" % [key, WEAPON_KEYS, hint]
			)
	var wname: String = str(a_weapon.get("name", ""))
	if wname == "":
		_err(a_spec, "every weapon needs a name (it is the sync key)")
	elif a_seen.has(wname):
		_err(a_spec, "duplicate weapon name '%s'" % wname)
	a_seen[wname] = true
	if a_weapon.has("projectile"):
		var pid: String = str(a_weapon["projectile"])
		if not projectiles.has(pid):
			_err(a_spec, "weapon '%s' references unknown projectile '%s'" % [wname, pid])
	elif not a_weapon.has("melee_damage"):
		_err(a_spec, "weapon '%s' needs either projectile: or melee_damage:" % wname)
	if (
		a_weapon.has("melee_damage_type")
		and not Damage.Type.has(str(a_weapon["melee_damage_type"]))
	):
		_err(
			a_spec,
			(
				"weapon '%s' melee_damage_type '%s' is not a Damage.Type"
				% [wname, a_weapon["melee_damage_type"]]
			)
		)
	if a_weapon.has("hits"):
		for h in a_weapon["hits"]:
			if str(h) not in ["ground", "air"]:
				_err(a_spec, "weapon '%s' hits entries must be ground/air, got '%s'" % [wname, h])
	if a_weapon.has("reach"):
		a_weapon["_reach_radii"] = _resolve_reach(a_spec, wname, a_weapon["reach"])
	# A turn rate on a weapon that is not a turret would sit in the doc doing nothing, and
	# read as authoritative — the drift the key whitelist exists to stop.
	if a_weapon.has("turret_turn_rate"):
		if not bool(a_weapon.get("turret", false)):
			_err(a_spec, "weapon '%s' has turret_turn_rate but is not `turret: true`" % wname)
		elif (
			not (a_weapon["turret_turn_rate"] is float or a_weapon["turret_turn_rate"] is int)
			or float(a_weapon["turret_turn_rate"]) <= 0.0
		):
			_err(
				a_spec,
				(
					"weapon '%s' turret_turn_rate must be a positive number of degrees " % wname
					+ "per second, got '%s'" % a_weapon["turret_turn_rate"]
				)
			)


## A weapon's `reach:` resolved to {layer: radius}. It names shape-library ids — one id for
## every layer the weapon hits, or `{ground: id, air: id}` — and never a number, since a
## per-weapon radius is exactly what the library replaced. The radii are stashed on the
## weapon as `_reach_radii` for the calibration rules and tooltips; the ids stay in `reach`
## for the scene sync, which points the range node at the shape resource itself.
func _resolve_reach(a_spec: Dictionary, a_wname: String, a_reach: Variant) -> Dictionary:
	var by_layer: Dictionary = {}
	if a_reach is Dictionary:
		for k in a_reach:
			if str(k) not in ["ground", "air"]:
				_err(a_spec, "weapon '%s' reach keys must be ground/air, got '%s'" % [a_wname, k])
			else:
				by_layer[str(k)] = a_reach[k]
	else:
		by_layer = {"ground": a_reach, "air": a_reach}
	var radii: Dictionary = {}
	for layer: String in by_layer:
		var shape_id: Variant = by_layer[layer]
		if not (shape_id is String) or not shapes.has(shape_id):
			_err(
				a_spec,
				(
					(
						"weapon '%s' reach must name a shape from the range library "
						+ "(one of %s), got '%s'"
					)
					% [a_wname, _sorted_keys(shapes), shape_id]
				)
			)
			continue
		radii[layer] = float(shapes[shape_id].get("radius", -1.0))
	return radii


static func _sorted_keys(a_dict: Dictionary) -> Array:
	var keys: Array = a_dict.keys()
	keys.sort()
	return keys


## Every key a shape-library doc may carry. `height` is a cylinder's only, and optional.
const SHAPE_KEYS: Array = ["kind", "title", "radius", "height"]


## A shape-library entry is a radius, plus a height for a cylinder that wants one. An
## unstated height is SpecSceneSync.SHAPE_HEIGHT — far taller than the world, so a slope or
## a flier's cruise altitude never decides an overlap; ranges and senses all take it.
func _validate_shape(a_spec: Dictionary) -> void:
	for key in a_spec:
		if not str(key).begins_with("_") and str(key) != "id" and not SHAPE_KEYS.has(str(key)):
			_err(a_spec, "unknown shape key '%s' (expected one of %s)" % [key, SHAPE_KEYS])
	if not a_spec.has("radius"):
		_err(a_spec, "a shape needs radius: (in world units)")
	_check_radius(a_spec, "radius", false)
	if a_spec.has("height"):
		if str(a_spec.get("kind", "")) != "CylinderShape3D":
			_err(a_spec, "height: is a cylinder's — a sphere is only a radius")
		_check_radius(a_spec, "height", false)


## A doc key that names a shape-library id: its radius replaces the id in the spec, so the
## calibration rules and tooltips keep reading a number, and the id is kept under
## `_shape_ids` for the scene sync, which points the node at the library resource itself.
## A bare number is refused — a per-piece value is what the library replaced. `false` / an
## empty value are left for _check_radius, which reads them as removal where that is allowed.
func _resolve_shape_key(a_spec: Dictionary, a_key: String) -> void:
	if not a_spec.has(a_key):
		return
	var value: Variant = a_spec[a_key]
	if value == null or value is bool:
		return
	if not (value is String) or not shapes.has(value):
		_err(
			a_spec,
			(
				"%s must name a shape from the library (one of %s), got '%s'"
				% [SpecSchema.doc_key(a_key), _sorted_keys(shapes), value]
			)
		)
		a_spec.erase(a_key)
		return
	if not a_spec.has("_shape_ids"):
		a_spec["_shape_ids"] = {}
	a_spec["_shape_ids"][a_key] = value
	a_spec[a_key] = float(shapes[value].get("radius", -1.0))


func _validate_projectile(a_spec: Dictionary) -> void:
	_check_enum(a_spec, "damage_type", Damage.Type)
	# The phase grammar (and the flat shorthand's `trajectory:` preset) is owned by one module
	# so the doc rules and the scene writer cannot drift — see EmissionPhases.
	for message: String in EmissionPhases.errors_for(a_spec):
		_err(a_spec, message)
	for emitted: String in EmissionPhases.emitted_ids(a_spec):
		if not projectiles.has(emitted):
			_err(a_spec, "phases: emits unknown emission '%s'" % emitted)
	# `blast` is the world radius of the projectile's HitShape — the ONE number that
	# makes it an area weapon, governing damaged entities and status-effect recipients
	# alike (see SpecSceneSync._set_blast_shape). It names an aoe_* library shape.
	_resolve_shape_key(a_spec, "blast")
	_check_radius(a_spec, "blast", false)
	# A HITSCAN projectile resolves onto the single target it was fired at and never
	# consults its hit shape, so a blast on one is a number that silently does nothing
	# — and Payload.has_blast ignores the shape outright.
	if a_spec.has("blast") and a_spec.get("hitscan", false) == true:
		_err(a_spec, "blast: and hitscan: true are incompatible — a hitscan shot hits one target")
	if a_spec.get("bio_ground_aim", false) == true and a_spec.get("hitscan", false) == true:
		_err(
			a_spec,
			(
				"bio_ground_aim: and hitscan: true are incompatible — a hitscan shot lands "
				+ "on its target whatever it hits"
			)
		)
	if a_spec.has("status_effects"):
		for ref in a_spec["status_effects"]:
			if not status_effects.has(str(ref)):
				_err(a_spec, "status_effects references unknown status effect '%s'" % ref)


func _validate_faction(a_spec: Dictionary) -> void:
	if not a_spec.has("starts_with") or not (a_spec["starts_with"] is Array):
		_err(a_spec, "faction needs a starts_with: list")
		return
	# Units only: the command centre is dropped at the start of a match, not started with, and
	# which one a faction drops is Deployment's (COMMAND_CENTRE_SCENES).
	for ref in a_spec["starts_with"]:
		var rid: String = str(ref)
		if not pieces.has(rid):
			_err(a_spec, "starts_with references unknown piece '%s'" % rid)
		elif SpecSchema.is_fixture(pieces[rid]):
			_err(
				a_spec,
				(
					"starts_with names the structure '%s' — a faction starts with units " % rid
					+ "only; its command centre is dropped"
				)
			)
	# `sanctions:` is the faction's DOMINION SHOP: the abilities it sells through the
	# sanction grid. An ability doc with no `levels:` has no cells to draw, so naming one
	# here is an authoring mistake rather than an empty column.
	if a_spec.has("sanctions"):
		if not (a_spec["sanctions"] is Array):
			_err(a_spec, "sanctions must be a list of ability-doc ids")
		else:
			for o in a_spec["sanctions"]:
				var oid: String = str(o)
				if not _valid_id(oid):
					_err(a_spec, "sanction id '%s' must be snake_case" % oid)
				elif not abilities.has(oid):
					_err(
						a_spec,
						(
							(
								"sanctions references unknown ability doc '%s' (expected "
								+ "a kind: AbilityDefinition file of that name)"
							)
							% oid
						)
					)
				elif not abilities[oid].has("levels"):
					_err(
						a_spec,
						(
							(
								"sanctions names '%s', which authors no levels: — an "
								+ "ability with no dominion unlock route has no sanction "
								+ "grid cells to draw"
							)
							% oid
						)
					)


## An ABILITY: a thing a piece can do. What it IS lives at the doc's top level; how a
## commander COMES BY it is the optional dominion unlock route below.
##
## THE THREE THINGS THIS DOC DOES NOT SAY, and where each lives instead:
##   * WHO can use it — the piece, via `abilities:` (an ability may be granted by
##     several kinds of piece, on different charges);
##   * HOW OFTEN — the same key, since the pool belongs to the piece holding it;
##   * WHAT IT DOES — an event scene, or a command class, neither of which is a value
##     anyone can type into YAML.
##
## `passive:` and `hud_button:` sit HERE rather than on a level because both are facts
## about the ability itself: Scavenge 2 is not more passive than Scavenge 1, and an
## ability does not gain a HUD button by being upgraded.
func _validate_ability(a_spec: Dictionary) -> void:
	if a_spec.has("caster"):
		# WHO casts an ability is declared by the PIECE (`abilities:`), not here — an
		# ability may be usable by several kinds of piece, and a piece is what knows its own
		# charges. Naming it on the ability cannot express either.
		_err(a_spec, "remove `caster:` — a piece declares what it casts, via abilities:")
	for flag: String in ["passive", "hud_button"]:
		if a_spec.has(flag) and not (a_spec[flag] is bool):
			_err(a_spec, "%s must be true or false" % flag)
	_validate_ability_range(a_spec)
	_validate_ability_cast_by(a_spec)
	_validate_ability_reveals(a_spec)
	_validate_ability_valence(a_spec)
	_validate_ability_command(a_spec)
	_validate_ability_emission(a_spec)
	# An ability draws a button on the ORDNANCE card, so it authors its cell the same way a
	# tool does — one `ui:` vocabulary across every kind of doc that reaches the grid.
	if a_spec.has("ui") and a_spec["ui"] is Dictionary:
		_validate_ui(a_spec, a_spec["ui"])
	if (
		a_spec.has("ui")
		and bool(a_spec.get("hud_button", false))
		and not (a_spec["ui"] as Dictionary).has("grid")
	):
		_err(
			a_spec,
			"an ordnance (`hud_button: true`) needs `ui.grid` — it is drawn on the ORDNANCE card"
		)
	_check_piece_placeholders(a_spec, str(a_spec.get("description", "")), "flavor.description")
	_check_piece_placeholders(a_spec, str(a_spec.get("verbose", "")), "flavor.verbose")
	if a_spec.has("column") or a_spec.has("levels"):
		_validate_sanction_route(a_spec)


## Every key a `kind: Upgrade` doc may carry, as the internal (normalized) names. Whitelisted
## for the reason `weapons:` entries are: an unknown key would read as configuring something.
const UPGRADE_KEYS: Array = [
	"kind", "title", "description", "verbose", "cost", "build_time", "requires", "modifies", "ui"
]
## Every key a `modifies:` entry may carry. `range` is the only value an upgrade can change
## today; a new one is added here together with the reader that honours it.
const MODIFIER_KEYS: Array = ["piece", "ability", "range"]


## An UPGRADE: one-time commander-wide research. Priced and timed like a piece (`build:`),
## researched at every structure whose `researches:` names it, and doing what its `modifies:`
## entries say. Why: gdd/systems/macroeconomics/upgrades.md.
func _validate_upgrade(a_spec: Dictionary) -> void:
	for key: Variant in a_spec:
		var k: String = str(key)
		# `id` and the `_`-prefixed keys are the registry's own bookkeeping, never authored.
		if k == "id" or k.begins_with("_") or UPGRADE_KEYS.has(k):
			continue
		_err(
			a_spec,
			(
				"an upgrade may not carry `%s:` (expected one of %s)"
				% [SpecSchema.doc_key(k), UPGRADE_KEYS]
			)
		)
	if not (a_spec.get("cost") is Dictionary):
		_err(a_spec, "an upgrade needs build.cost: — a mapping of energy/dominion")
	if not _is_number(a_spec.get("build_time")) or float(a_spec.get("build_time", 0)) <= 0.0:
		_err(a_spec, "an upgrade needs a positive build.time: — how long the research takes")
	for ref: Variant in a_spec.get("requires", []):
		var rid: String = str(ref)
		if not pieces.has(rid):
			_err(a_spec, "build.requires references unknown piece '%s'" % rid)
		elif not SpecSchema.is_fixture(pieces[rid]):
			_err(a_spec, "build.requires must name structures; '%s' has no footprint:" % rid)
	if not (a_spec.get("modifies") is Array) or (a_spec["modifies"] as Array).is_empty():
		_err(
			a_spec,
			"an upgrade needs a modifies: list — an upgrade that changes nothing buys nothing"
		)
	else:
		for entry: Variant in a_spec["modifies"]:
			_validate_modifier(a_spec, entry)
	if not (a_spec.get("ui") is Dictionary) or not (a_spec["ui"] as Dictionary).has("grid"):
		_err(a_spec, "an upgrade needs ui.grid — it is drawn on its researching structure's card")
	else:
		_validate_ui(a_spec, a_spec["ui"])
	var researched_at: bool = false
	for id: Variant in pieces:
		if (pieces[id].get("researches", []) as Array).has(a_spec["id"]):
			researched_at = true
			break
	if not researched_at:
		warnings.append(
			(
				"%s [%s]: no structure researches it — its button can never be drawn"
				% [a_spec["_doc_path"], a_spec["id"]]
			)
		)


## One `modifies:` entry: {piece, ability, range}. The piece must exist and be granted the
## ability, or the modifier could never apply; `range` names a shape from the library and is
## resolved to its radius here, so the runtime reads a number.
func _validate_modifier(a_spec: Dictionary, a_entry: Variant) -> void:
	if not (a_entry is Dictionary):
		_err(a_spec, "each modifies: entry must be a mapping of %s" % [MODIFIER_KEYS])
		return
	var entry: Dictionary = a_entry
	for key: Variant in entry:
		if not MODIFIER_KEYS.has(str(key)):
			_err(
				a_spec,
				(
					"modifies: entry has an unknown key '%s' (expected one of %s)"
					% [key, MODIFIER_KEYS]
				)
			)
	var piece_id: String = str(entry.get("piece", ""))
	var ability_id: String = str(entry.get("ability", ""))
	if not pieces.has(piece_id):
		_err(a_spec, "modifies: names unknown piece '%s'" % piece_id)
		return
	if not abilities.has(ability_id):
		_err(a_spec, "modifies: names unknown ability '%s'" % ability_id)
		return
	if not _piece_grants(pieces[piece_id], ability_id):
		_err(
			a_spec,
			(
				"modifies: '%s' is not granted '%s' (its abilities: pools name no such grant)"
				% [piece_id, ability_id]
			)
		)
	if not entry.has("range"):
		_err(
			a_spec,
			"modifies: entry for %s.%s changes nothing — give it a range:" % [piece_id, ability_id]
		)
		return
	var radius: float = _library_radius(a_spec, "modifies.range", entry["range"])
	if radius > 0.0:
		entry["range_metres"] = radius


## Whether a piece's `abilities:` pools grant `a_ability`.
static func _piece_grants(a_piece: Dictionary, a_ability: String) -> bool:
	for pool: Variant in a_piece.get("ability_groups", []):
		if pool is Dictionary and ((pool as Dictionary).get("grants", []) as Array).has(a_ability):
			return true
	return false


## `researches:` on a structure — the upgrades researched there. Each must be an upgrade doc,
## and only a fixture can research: the job runs on the structure's Production component.
func _validate_researches(a_spec: Dictionary) -> void:
	if not (a_spec["researches"] is Array):
		_err(a_spec, "researches must be a list of upgrade ids")
		return
	if not SpecSchema.is_fixture(a_spec):
		_err(a_spec, "researches: needs a footprint: — only a structure researches")
	for ref: Variant in a_spec["researches"]:
		var rid: String = str(ref)
		if not upgrades.has(rid):
			_err(
				a_spec,
				(
					"researches references unknown upgrade '%s' (expected a kind: Upgrade doc of that name)"
					% rid
				)
			)


## `payloads:` — the CHOICES a level offers, when the sanction is one the player picks a
## cargo for rather than one that simply happens.
##
## Per LEVEL and not per ability, because that is what a level IS here: Drop 1 offers a squad,
## Drop 2 offers a bigger squad or a vehicle, Drop 3 adds a heavier one. Supersession then
## expresses an "upgrade" with no extra machinery — the level that replaces its parent carries
## the same piece at a higher count, and a column stays one sanction the player improves.
##
## `{piece: <id>, count: <int>}`. The piece is validated against the registry like every other
## id reference, so a rename fails the import rather than silently dropping nothing.
func _validate_payloads(a_spec: Dictionary, a_level: Dictionary, a_where: String) -> void:
	if not a_level.has("payloads"):
		return
	if not (a_level["payloads"] is Array) or (a_level["payloads"] as Array).is_empty():
		_err(a_spec, "%s.payloads must be a non-empty list of {piece, count}" % a_where)
		return
	var seen: Dictionary = {}
	for entry: Variant in a_level["payloads"]:
		if not (entry is Dictionary) or not entry.has("piece"):
			_err(a_spec, "%s.payloads entries are {piece: <id>, count: <int>}" % a_where)
			continue
		var piece: String = str(entry["piece"])
		if not pieces.has(piece):
			_err(a_spec, "%s.payloads names '%s', which is not a piece" % [a_where, piece])
		# One piece, one entry. Two would draw two buttons in the SAME cell (a payload button
		# is the piece's own train/build button — see the ui note), where the player could
		# only ever press one of them.
		if seen.has(piece):
			_err(a_spec, "%s.payloads names '%s' twice" % [a_where, piece])
		seen[piece] = true
		if entry.has("count") and not (entry["count"] is int and int(entry["count"]) >= 1):
			_err(a_spec, "%s.payloads count must be a positive int" % a_where)


## `range:` — how far from the target point the ability may be used, in world units.
##
## Optional: an ability naming none takes AbilityDefinition.DEFAULT_RANGE. An ability whose
## reach is NOT a distance (the Bombard, limited by spotting rather than by range) names
## nothing here either and overrides Ability.is_in_range instead — so a zero or negative
## `range:` is a typo rather than a way of saying "unlimited", and is refused.
func _validate_ability_range(a_spec: Dictionary) -> void:
	if not a_spec.has("range"):
		return
	if not (a_spec["range"] is float or a_spec["range"] is int) or float(a_spec["range"]) <= 0.0:
		_err(a_spec, "range must be a positive number of world units")


## `cast_by:` — how many of the SELECTED casters fire this ability when no modifier is held.
##
## SINGLE (the default, and what an absent key means) or ALL. Refused rather than guessed at
## for any other value: an ability that silently read as SINGLE because of a typo would spend
## one charge where the author meant every caster to fire, which is a balance change wearing
## a spelling mistake.
const CAST_BY_VALUES: Array = ["SINGLE", "ALL"]

## `reveals:` — the REACH this ability paints when the player hovers its card.
##
## Names an `EntityRanges.Kind`, which is a shape the piece already carries: a passive with
## an aura has a collider the simulation sweeps, and the card should paint THAT rather than a
## circle re-derived from a number (see gdd/systems/ux/ui/range-reveal.md).
##
## The value list is spelled here rather than read off EntityRanges, deliberately: that class
## lives in the interface layer and naming it from the importer would point a build tool at
## the HUD. A name added there and not here fails this check, which is the right failure —
## the schema is a promise about what a doc may say.
const REVEALS_VALUES: Array = [
	"VISION",
	"DETECTION",
	"AGGRO",
	"ATTACK",
	"LIBERATION",
	"DOMINION",
	"EFFECT",
]

## `valence:` — is this GOOD or BAD for the piece carrying it, which is what accents its
## info card. NEUTRAL when unsaid, and that is a real answer rather than a missing one: a
## condition can genuinely be neither.
const VALENCE_VALUES: Array = ["NEUTRAL", "BOON", "BANE"]


func _validate_ability_valence(a_spec: Dictionary) -> void:
	if not a_spec.has("valence"):
		return
	var value: String = str(a_spec["valence"])
	if not VALENCE_VALUES.has(value):
		_err(a_spec, "valence must be one of %s, got '%s'" % [VALENCE_VALUES, value])


func _validate_ability_reveals(a_spec: Dictionary) -> void:
	if not a_spec.has("reveals"):
		return
	var value: String = str(a_spec["reveals"])
	if not REVEALS_VALUES.has(value):
		_err(a_spec, "reveals must be one of %s, got '%s'" % [REVEALS_VALUES, value])


func _validate_ability_cast_by(a_spec: Dictionary) -> void:
	if not a_spec.has("cast_by"):
		return
	var value: String = str(a_spec["cast_by"])
	if not CAST_BY_VALUES.has(value):
		_err(a_spec, "cast_by must be one of %s, got '%s'" % [CAST_BY_VALUES, value])
	if bool(a_spec.get("passive", false)):
		# A passive is never cast at all, so saying who casts it is a contradiction rather
		# than a redundancy — and the doc reads as though the ability is active.
		_err(a_spec, "a passive ability names no cast_by: nothing casts it")


## `command:` — the grid command an ability is ARMED as when its HUD button is pressed.
## Only an ability the player aims through the ordinary command path needs one; a
## dominion-unlocked ability is armed as its own cell's `command_sanction_*` and says
## nothing here.
func _validate_ability_command(a_spec: Dictionary) -> void:
	if not a_spec.has("command"):
		return
	var name: String = str(a_spec["command"])
	if not name.begins_with("command_"):
		_err(a_spec, "command '%s' must be a command name (they all begin `command_`)" % name)
	elif a_spec.has("levels"):
		# The two are different arming paths, and an ability cannot take both: a cell is
		# armed as the sanction it unlocked, at the level the commander owns.
		_err(
			a_spec,
			"command: and levels: are alternatives — a dominion-unlocked ability is armed as its own cell"
		)


## `emits:` — the piece this ability throws on each use, named the way a weapon names
## what it fires. Optional: most abilities deliver an event scene instead, and one that
## does neither is a passive.
##
## A `res://` PATH is accepted alongside a piece id, and is a stopgap rather than a
## second spelling: the roster still holds hand-authored emission scenes with no doc of
## their own (the Bombard's shell is one), and giving one a `kind: projectile` doc means
## the importer starts governing numbers nobody has moved into the doc yet. The emission
## rework is what retires the path form.
func _validate_ability_emission(a_spec: Dictionary) -> void:
	if not a_spec.has("emits"):
		return
	var id: String = str(a_spec["emits"])
	if id.begins_with("res://"):
		if not ResourceLoader.exists(id):
			_err(a_spec, "emits names scene '%s', which does not exist" % id)
	elif not specs.has(id):
		_err(a_spec, "emits names unknown piece '%s'" % id)
	elif str(specs[id].get("scene", "")).is_empty():
		_err(a_spec, "emits names '%s', which has no scene: to instance" % id)


## The DOMINION UNLOCK ROUTE: one column of the sanction grid, whose `levels` are that
## column's cells in CHAIN order — level N+1 continues and supersedes level N.
##
## A family is not the same thing as a column: several unrelated abilities may share a
## column (the Colonials' Gunship sits under Scan 2 without continuing it), and those are
## separate docs carrying the same `column`. Sharing a column is layout; being a level is
## a dependency. Splitting them is exactly what the flat `prerequisites` list could not
## express — see CLAUDE.md §The sanction grid.
func _validate_sanction_route(a_spec: Dictionary) -> void:
	_check_grid_index(a_spec, "column", SanctionGrid.NUM_COLUMNS)
	if (
		not a_spec.has("levels")
		or not (a_spec["levels"] is Array)
		or (a_spec["levels"] as Array).is_empty()
	):
		_err(
			a_spec,
			(
				"column: is the dominion unlock route, so it needs a non-empty levels: "
				+ "list (one entry per grid cell)"
			)
		)
		return
	var previous_tier: int = -1
	for i in (a_spec["levels"] as Array).size():
		var level: Variant = a_spec["levels"][i]
		if not (level is Dictionary):
			_err(a_spec, "levels[%d] must be a mapping" % i)
			continue
		var where: String = "levels[%d]" % i
		if not level.has("title") or str(level["title"]).strip_edges() == "":
			_err(
				a_spec,
				"%s needs a title: — it is the cell's name in the scene and on its button" % where
			)
		_check_grid_index(a_spec, "tier", SanctionGrid.NUM_TIERS, level, where)
		_validate_payloads(a_spec, level, where)
		# A level continues the one above it, so it must sit strictly lower in the grid.
		# Equal or ascending tiers would author a parent at or below its child, which
		# SanctionGrid reports as a fault no commander could ever walk past.
		var tier: int = int(level.get("tier", -1))
		if i > 0 and tier <= previous_tier and tier >= 0:
			_err(
				a_spec,
				(
					(
						"%s is at tier %d, which is not below the level before it (tier "
						+ "%d) — a level continues the one above it"
					)
					% [where, tier, previous_tier]
				)
			)
		previous_tier = tier
		if level.has("cost") and not (level["cost"] is int or level["cost"] is float):
			_err(a_spec, "%s cost must be a number (dominion)" % where)
		if level.has("cooldown") and not (level["cooldown"] is int or level["cooldown"] is float):
			_err(a_spec, "%s cooldown must be a number (seconds)" % where)
		if level.has("passive"):
			# Passivity belongs to the ABILITY, not to one of its tiers: Scavenge 2 is not
			# more passive than Scavenge 1. Refused rather than read, so a doc cannot end up
			# saying it twice and disagreeing with itself.
			_err(
				a_spec,
				(
					"%s: `passive:` is a property of the ability — move it to the doc's top level"
					% where
				)
			)
		for flag: String in ["needs_vision", "needs_target"]:
			if level.has(flag) and not (level[flag] is bool):
				_err(a_spec, "%s %s must be true or false" % [where, flag])
		if level.has("kill_bounty"):
			var bounty: Variant = level["kill_bounty"]
			if not (bounty is int or bounty is float) or float(bounty) < 0.0 or float(bounty) > 1.0:
				_err(a_spec, "%s kill_bounty must be a fraction between 0 and 1" % where)
			elif not bool(a_spec.get("passive", false)):
				_err(
					a_spec,
					(
						(
							"%s names a kill_bounty but the ability is not passive: — a "
							+ "standing benefit needs a cell that is never deployed"
						)
						% where
					)
				)
		_check_piece_placeholders(
			a_spec, str(level.get("description", "")), "%s description" % where
		)
		_check_piece_placeholders(a_spec, str(level.get("verbose", "")), "%s verbose" % where)


## A 0-based grid index that must fall inside the sanction grid's fixed shape. Reads from
## `a_level` when given (a level's `tier`), otherwise from the spec itself (`column`).
func _check_grid_index(
	a_spec: Dictionary, a_key: String, a_limit: int, a_level: Variant = null, a_where: String = ""
) -> void:
	var source: Dictionary = a_level if a_level is Dictionary else a_spec
	var label: String = a_key if a_where == "" else "%s %s" % [a_where, a_key]
	if not source.has(a_key):
		_err(a_spec, "%s is required (0-based)" % label)
		return
	if not (source[a_key] is int):
		_err(a_spec, "%s must be a whole number (0-based)" % label)
		return
	var value: int = int(source[a_key])
	if value < 0 or value >= a_limit:
		_err(a_spec, "%s is %d, outside the sanction grid's 0..%d" % [label, value, a_limit - 1])


## `{{ piece_id }}` in sanction copy renders as that piece's title, resolved at IMPORT
## (see SpecSceneSync._render_placeholders) so the scene carries finished prose and the
## game does no lookup. An unknown id is a hard error rather than a literal `{{ … }}`
## shipped to the player — the same "loud, total, no fuzzy matching" rule the rest of the
## importer follows.
func _check_piece_placeholders(a_spec: Dictionary, a_text: String, a_where: String) -> void:
	if a_text == "":
		return
	var regex := RegEx.new()
	regex.compile("\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}")
	for m: RegExMatch in regex.search_all(a_text):
		var ref: String = m.get_string(1)
		if not specs.has(ref):
			_err(a_spec, "%s references unknown piece '{{ %s }}'" % [a_where, ref])


## `ability_groups:` — the pools of charges this piece's abilities draw on. Each entry is
## `{max_charges, initial_charges, cooldown, grants}`; abilities listed in one entry SHARE
## its charges. `max_charges` defaults to 1 and `initial_charges` to `max_charges`, so a
## plain cooldown is still `{cooldown, grants}`.
##
## Validated against the ABILITY registry, so a typo names an ability nothing defines and
## is caught here rather than becoming a button that never appears. Every kind: AbilityDefinition
## doc
## is eligible, however it is unlocked — a piece may be granted an ability it pays dominion
## for, one it gets free, and one it buys at a structure, and this key cannot tell them
## apart because the pool it describes does not care.
func _validate_ability_groups(a_spec: Dictionary) -> void:
	if not a_spec.has("ability_groups"):
		return
	if not (a_spec["ability_groups"] is Array):
		_err(a_spec, "abilities must be a list of pools")
		return
	var seen: Dictionary = {}
	for i in (a_spec["ability_groups"] as Array).size():
		var group: Variant = a_spec["ability_groups"][i]
		var where: String = "abilities[%d]" % i
		if not (group is Dictionary):
			_err(a_spec, "%s must be a mapping" % where)
			continue
		if group.has("charges"):
			# Superseded by the max_charges / initial_charges pair. Rejected rather than
			# aliased: silently reading it as one of the two would make a doc that still
			# says `charges:` mean something the author never wrote.
			_err(
				a_spec,
				"%s: `charges` is now `max_charges` (with optional `initial_charges`)" % where
			)
		if group.has("max_charges"):
			if not (group["max_charges"] is int) or int(group["max_charges"]) < 1:
				# There is no such thing as a zero-capacity ability: an ability that is
				# "just a cooldown" holds one charge. See the Abilities component.
				_err(a_spec, "%s max_charges must be a whole number of at least 1" % where)
		if group.has("initial_charges"):
			# Zero IS meaningful here, unlike capacity: a battery that must spin up before
			# its first shot starts empty and fills after one cooldown.
			var cap: int = maxi(1, int(group.get("max_charges", Abilities.DEFAULT_MAX_CHARGES)))
			if not (group["initial_charges"] is int) or int(group["initial_charges"]) < 0:
				_err(a_spec, "%s initial_charges must be a whole number of 0 or more" % where)
			elif int(group["initial_charges"]) > cap:
				_err(
					a_spec,
					(
						"%s initial_charges (%d) exceeds max_charges (%d)"
						% [where, int(group["initial_charges"]), cap]
					)
				)
		if not group.has("cooldown"):
			_err(a_spec, "%s needs a cooldown: (seconds)" % where)
		elif (
			not (group["cooldown"] is int or group["cooldown"] is float)
			or float(group["cooldown"]) <= 0.0
		):
			_err(a_spec, "%s cooldown must be a positive number of seconds" % where)
		if (
			not group.has("grants")
			or not (group["grants"] is Array)
			or (group["grants"] as Array).is_empty()
		):
			_err(a_spec, "%s needs a non-empty grants: list of ability ids" % where)
			continue
		for ability in group["grants"]:
			var id: String = str(ability)
			if not abilities.has(id):
				_err(a_spec, "%s grants unknown ability '%s'" % [where, id])
			elif seen.has(id):
				# Two pools granting one ability would make "which charges does it spend?"
				# ambiguous, and the answer would silently depend on list order.
				_err(a_spec, "%s grants '%s', which another pool already grants" % [where, id])
			else:
				seen[id] = true


## A cylinder-radius key: a number, never negative, and zero only where zero means
## "disabled" (`a_zero_disables`) rather than a collapsed shape.
func _check_radius(a_spec: Dictionary, a_key: String, a_zero_disables: bool) -> void:
	if not a_spec.has(a_key):
		return
	var r: Variant = a_spec[a_key]
	# `false` and an EMPTY value are both the same statement as 0 — "this piece has no such
	# volume". Empty matters because it is what an author actually types: deleting `8` from
	# `vision: 8` leaves `vision:`, and refusing that made the ordinary way of taking a volume
	# away an import error. Both normalise to 0 here so nothing downstream sees null.
	#
	# `true` is still refused, and an empty value is still refused where zero does NOT
	# disable (movement_radius, hurtbox_radius, blast): a radius has no default to take, and
	# those volumes are not optional.
	if (r == null or (r is bool and not bool(r))) and a_zero_disables:
		a_spec[a_key] = 0
	elif not (r is int or r is float):
		_err(
			a_spec,
			(
				"%s must be a number (cylinder radius in world units)%s"
				% [
					SpecSchema.doc_key(a_key),
					", or false / left empty to remove the volume" if a_zero_disables else ""
				]
			)
		)
	elif float(r) < 0.0 or (float(r) == 0.0 and not a_zero_disables):
		_err(
			a_spec,
			(
				"%s must be a %s radius in world units"
				% [SpecSchema.doc_key(a_key), "non-negative" if a_zero_disables else "positive"]
			)
		)


func _check_enum(a_spec: Dictionary, a_key: String, a_enum: Dictionary) -> void:
	if a_spec.has(a_key) and not a_enum.has(str(a_spec[a_key])):
		_err(
			a_spec,
			"%s '%s' is not one of %s" % [SpecSchema.doc_key(a_key), a_spec[a_key], a_enum.keys()]
		)


func _err(a_spec: Dictionary, a_message: String) -> void:
	errors.append("%s [%s]: %s" % [a_spec["_doc_path"], a_spec["id"], a_message])


# --------------------------------------------------------------------------- #
# Discovery
# --------------------------------------------------------------------------- #
## True if the file's leading frontmatter block contains a `kind:` line — a cheap
## raw scan used only to decide whether an UNPARSEABLE doc was meant to be a spec.
func _raw_frontmatter_has_kind(a_path: String) -> bool:
	var f: FileAccess = FileAccess.open(a_path, FileAccess.READ)
	if f == null:
		return false
	var in_fence: bool = false
	while not f.eof_reached():
		var line: String = f.get_line()
		var stripped: String = line.strip_edges()
		if not in_fence:
			if stripped == "---":
				in_fence = true
				continue
			break  # no opening fence -> no frontmatter
		if stripped == "---" or stripped == "...":
			break
		if stripped.begins_with("kind:"):
			f.close()
			return true
	f.close()
	return false


func _collect_markdown(a_dir: String, a_out: Array) -> void:
	var da: DirAccess = DirAccess.open(a_dir)
	if da == null:
		return
	da.list_dir_begin()
	var fn: String = da.get_next()
	while fn != "":
		var full: String = a_dir.path_join(fn)
		if da.current_is_dir():
			if not fn.begins_with("."):
				_collect_markdown(full, a_out)
		elif fn.get_extension() == "md":
			a_out.append(full)
		fn = da.get_next()
	da.list_dir_end()
