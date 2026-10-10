class_name ImportPipeline
extends RefCounted

## The shared import pipeline behind both the CLI (import.gd) and the editor
## plugin. Validate -> generate -> sync scenes. Nothing at all is written when
## validation fails.

## Where the fight generator lives; its DEFAULT_PREFIXES says which factions the combat model
## can learn (see combat_model_lines).
const FIGHT_GENERATOR_PATH: String = "res://tools/combat_model/generate_fights.gd"
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SpecSceneSync := preload("res://tools/spec_import/scene_sync.gd")
const SpecRules := preload("res://tools/spec_import/spec_rules.gd")


## The importer's own scripts that did not compile, by file name; empty when all did. A
## preloaded const whose script failed to compile is a bare GDScript with none of its
## functions, so without this check the run gets part-way — after the shape library is
## written — and dies on "Nonexistent function" with nothing to say why.
static func broken_stages() -> Array:
	var broken: Array = []
	# By path rather than through the consts above: a const naming a script is resolved as
	# that CLASS, and can_instantiate() is not static, so calling it on the const is a parse
	# error. load() returns the same cached script as a plain GDScript value.
	for file: String in ["spec_registry.gd", "generators.gd", "scene_sync.gd", "spec_rules.gd"]:
		if not compiled(load("res://tools/spec_import/" + file)):
			broken.append(file)
	return broken


## Whether `a_script` compiled. NOT `can_instantiate()`: inside the EDITOR that is false for
## every script without `@tool` — which is every script in this importer — so a check built on
## it refuses every in-editor run while the CLI, where it is true, sails through. A script
## that failed to compile has no methods at all, and each of these has several.
static func compiled(a_script: GDScript) -> bool:
	return a_script != null and not a_script.get_script_method_list().is_empty()


## Runs the full pipeline. Returns {"ok": bool, "log": Array[String]}.
##
## `a_rebake_visuals` is the one-off migration switch for the generated visual defaults: it
## regenerates the selection shapes and HP bars this importer does not own, i.e. ones that
## predate the pass. Off by default — the standing rule is that a value already in a scene
## belongs to whoever put it there.
static func run(
	mode: String, gdd_root: String = "res://gdd", rebake_visuals: bool = false
) -> Dictionary:
	var log: Array = []
	var broken: Array = broken_stages()
	if not broken.is_empty():
		(
			log
			. append(
				(
					"import: ABORTED before reading anything — these importer scripts failed to"
					+ " compile: %s. The cause is the FIRST script error printed above this line (often"
					+ " in a game script they depend on). In the editor a dependency that failed once can"
					+ (
						" stay failed after it is fixed: Project > Reload Current Project clears it."
						% ", ".join(broken)
					)
				)
			)
		)
		return {"ok": false, "log": log}
	var registry: RefCounted = SpecRegistry.new().scan(gdd_root)

	for w in registry.warnings:
		log.append("WARN: %s" % w)
	if not registry.errors.is_empty():
		log.append(
			"import: validation FAILED (%d errors) — nothing was written:" % registry.errors.size()
		)
		for e in registry.errors:
			log.append("  ERROR: %s" % e)
		return {"ok": false, "log": log}

	# Two buttons in one cell show as ONE: the HUD draws the first and hides the other, so a
	# piece becomes unbuildable with nothing to say why. A fact about the docs alone, so it is
	# refused here, before anything is written, rather than found by playing.
	var collisions: Array = SpecGenerators.grid_collisions(registry)
	if not collisions.is_empty():
		log.append(
			(
				"import: grid review FAILED (%d buttons share a cell) — nothing was written:"
				% collisions.size()
			)
		)
		for c in collisions:
			log.append("  ERROR: %s" % c)
		return {"ok": false, "log": log}

	log.append(
		(
			(
				"import: %d pieces, %d projectiles, %d status effects, %d factions, "
				+ "%d shapes (mode=%s)"
			)
			% [
				registry.pieces.size(),
				registry.projectiles.size(),
				registry.status_effects.size(),
				registry.factions.size(),
				registry.shapes.size(),
				mode
			]
		)
	)

	# Every declared departure from a calibration norm, in one place. Printed on a SUCCESSFUL
	# run rather than buried among warnings, because that is what the mechanism is for: a
	# waiver is only worth requiring if somebody reads the resulting list, and the list is
	# the roster's answer to "which pieces are built against type, and why".
	if not registry.exceptional.is_empty():
		log.append(
			(
				"import: %d declared exception(s) to the calibration norms:"
				% registry.exceptional.size()
			)
		)
		for e: Dictionary in registry.exceptional:
			log.append("  ~ %s breaks `%s` (%s)" % [e["id"], e["rule"], e["what"]])
			log.append("      %s" % e["detail"])
			log.append("      because: %s" % e["reason"])

	log.append_array(incomplete_asset_lines(registry.incomplete))

	# The shape library is the one generated artifact scenes REFERENCE, so it is written
	# before the scene sync that points range nodes at it.
	var shape_report: Dictionary = SpecGenerators.generate_shapes(registry)
	for path in shape_report["written"]:
		log.append("  generated %s" % path)
	for path in shape_report["removed"]:
		log.append(
			(
				"import: removed %s — its doc is gone; a hand-authored scene still naming it" % path
				+ " will not load"
			)
		)

	# Scene sync runs BEFORE the other generators: skeleton creation can add scene:
	# fields the generated tools.json needs.
	if rebake_visuals:
		log.append(
			(
				"import: REBAKING visual defaults the importer does not own — "
				+ "selection shapes and HP bars that predate the pass will be replaced"
			)
		)
	var sync_report: Dictionary = SpecSceneSync.sync_all(registry, mode, rebake_visuals)
	for w in sync_report["warnings"]:
		log.append("WARN: %s" % w)
	if not sync_report["errors"].is_empty():
		log.append("import: scene sync FAILED (%d errors):" % sync_report["errors"].size())
		for e in sync_report["errors"]:
			log.append("  ERROR: %s" % e)
		return {"ok": false, "log": log}
	for path in sync_report["created"]:
		log.append("  created %s" % path)
	for path in sync_report["changed"]:
		log.append("  changed %s" % path)

	# WHAT THIS RUN TAKES AWAY, said before it is taken. The id files are rebuilt wholesale
	# from the registry, so a piece whose doc is gone stops being emitted on its own — the
	# removal behaviour the docs promise, and completely silent. A dropped const is a PARSE
	# error in every file still naming it, and an unparseable test file leaves the GUT run
	# without being counted (CLAUDE.md §A skipped test file is invisible), so a removal that
	# says nothing is a removal nobody finds until something else goes wrong.
	# Read BEFORE generate_all, which overwrites the file this is diffed against.
	var removals: Array = SpecGenerators.pending_removals(registry)

	for path in SpecGenerators.generate_all(registry):
		log.append("  generated %s" % path)
	for removal: Dictionary in removals:
		log.append(
			(
				"import: %s drops %d id(s) no longer in the docs: %s"
				% [removal["scope"], removal["consts"].size(), ", ".join(removal["consts"])]
			)
		)
		log.append(
			(
				"    a file still naming one of those does not PARSE — and an unparseable"
				+ " test file leaves the suite silently. Grep for them."
			)
		)

	# The learned combat model is fitted on the pieces as they were when its fights were
	# generated, so a piece added, armed or retuned since is content the model does not know —
	# reported here, where the pieces are fixed, never at runtime (CLAUDE.md §5.4).
	log.append_array(
		combat_model_lines(
			armed_unit_ids(registry), _read_combat_model(), _fight_generator_prefixes()
		)
	)

	log.append("import: done")
	return {"ok": true, "log": log}


## WHAT THE COMBAT MODEL DOES NOT KNOW: the armed units it was never fitted on, grouped by
## faction prefix, and the types it knows that are no longer armed units. An unknown unit is not
## local to itself — the learned valuation needs the model to know every candidate a producer
## trains, so one unknown unit drops that whole producer onto the demand map
## (Bot.purchase_values_per_energy). A faction the fight generator does not pool at all
## (`pooled_prefixes`, its DEFAULT_PREFIXES) is said to be so, since regenerating will not
## teach the model those. Never an error: the bot plays on by the demand map meanwhile.
static func combat_model_lines(
	armed_ids: Array, model: Dictionary, pooled_prefixes: Array = []
) -> Array[String]:
	var lines: Array[String] = []
	if model.is_empty():
		lines.append(
			(
				(
					"import: no combat model at %s — the bot values by the demand map;"
					+ " regenerate: tools/combat_model/regenerate.sh"
				)
				% CombatModel.PATH
			)
		)
		return lines
	var known: Array = model.get("types", [])
	var unknown: Array = armed_ids.filter(func(id: String) -> bool: return not known.has(id))
	var stale: Array = known.filter(func(id: String) -> bool: return not armed_ids.has(id))
	var trained: String = str(model.get("trained", "?"))
	if not unknown.is_empty():
		lines.append(
			(
				(
					"import: combat model (trained %s) does not know %d armed unit(s) — every"
					+ " producer that trains one falls back to the demand map:"
				)
				% [trained, unknown.size()]
			)
		)
		for prefix: String in _prefixes_of(unknown):
			var ids: Array = unknown.filter(func(id: String) -> bool: return id.begins_with(prefix))
			ids.sort()
			var pooled: bool = pooled_prefixes.is_empty() or pooled_prefixes.has(prefix)
			lines.append(
				(
					"      %s ×%d — %s%s"
					% [
						prefix,
						ids.size(),
						", ".join(ids),
						(
							"\n          regenerate: tools/combat_model/regenerate.sh"
							if pooled
							else "\n          not in the fight generator's pool (DEFAULT_PREFIXES)"
						)
					]
				)
			)
	if not stale.is_empty():
		stale.sort()
		(
			lines
			. append(
				(
					"import: combat model (trained %s) knows %d type(s) that are no longer armed units: %s"
					% [trained, stale.size(), ", ".join(stale)]
				)
			)
		)
	return lines


## The distinct faction prefixes of `ids` — up to and including the first underscore — sorted.
static func _prefixes_of(ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		var prefix: String = id.substr(0, id.find("_") + 1)
		if not out.has(prefix):
			out.append(prefix)
	out.sort()
	return out


## The ids the fight generator would pool: pieces that move, carry a weapon and cost energy
## (tools/combat_model/generate_fights.gd reads the same three facts off the scenes).
static func armed_unit_ids(registry: RefCounted) -> Array:
	var out: Array = []
	for id: Variant in registry.specs:
		var spec: Dictionary = registry.specs[id]
		if not spec.has("movement"):
			continue
		var weapons: Variant = spec.get("weapons", [])
		if not (weapons is Array) or (weapons as Array).is_empty():
			continue
		var cost: Variant = spec.get("cost", {})
		if cost is Dictionary and int((cost as Dictionary).get("energy", 0)) > 0:
			out.append(str(id))
	out.sort()
	return out


## The faction prefixes the fight generator pools by default, read off the generator itself so
## the two cannot drift; empty if the generator is not there (every faction then reads as pooled).
static func _fight_generator_prefixes() -> Array:
	var generator: Variant = load(FIGHT_GENERATOR_PATH)
	if generator == null:
		return []
	return Array(str(generator.DEFAULT_PREFIXES).split(","))


## The shipped model's export, or {} when none is trained or it does not parse.
static func _read_combat_model() -> Dictionary:
	if not FileAccess.file_exists(CombatModel.PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CombatModel.PATH))
	return parsed if parsed is Dictionary else {}


## The unfilled asset slots, one line per rule and state rather than per piece: with most of
## the roster still on stand-ins, a line per piece would bury every other part of the summary.
## Never an error — see SpecRules §ASSET RULES ARE REPORTED, NEVER FAILED.
static func incomplete_asset_lines(incomplete: Array) -> Array[String]:
	var lines: Array[String] = []
	if incomplete.is_empty():
		return lines
	var groups: Dictionary = {}
	for e: Dictionary in incomplete:
		var key: String = "%s (%s)" % [e["rule"], SpecRules.AssetState.find_key(int(e["state"]))]
		if not groups.has(key):
			groups[key] = {"what": e["what"], "ids": []}
		(groups[key]["ids"] as Array).append(e["id"])
	lines.append("import: %d unfilled asset slot(s) — reported, not errors:" % incomplete.size())
	var keys: Array = groups.keys()
	keys.sort()
	for key: String in keys:
		var ids: Array = groups[key]["ids"]
		lines.append("  ? %s ×%d — %s" % [key, ids.size(), groups[key]["what"]])
		lines.append("      %s" % ", ".join(ids))
	return lines
