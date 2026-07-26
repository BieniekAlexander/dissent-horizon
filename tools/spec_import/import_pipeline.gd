class_name ImportPipeline
extends RefCounted

## The shared import pipeline behind both the CLI (import.gd) and the editor
## plugin. Validate -> generate -> sync scenes. Nothing at all is written when
## validation fails.

const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")
const SpecGenerators := preload("res://tools/spec_import/generators.gd")
const SpecSceneSync := preload("res://tools/spec_import/scene_sync.gd")


## Runs the full pipeline. Returns {"ok": bool, "log": Array[String]}.
static func run(a_mode: String, a_gdd_root: String = "res://gdd") -> Dictionary:
	var log: Array = []
	var registry: RefCounted = SpecRegistry.new().scan(a_gdd_root)

	for w in registry.warnings:
		log.append("WARN: %s" % w)
	if not registry.errors.is_empty():
		log.append("import: validation FAILED (%d errors) — nothing was written:" % registry.errors.size())
		for e in registry.errors:
			log.append("  ERROR: %s" % e)
		return {"ok": false, "log": log}

	log.append("import: %d pieces, %d projectiles, %d status effects, %d factions (mode=%s)" % [
		registry.pieces.size(), registry.projectiles.size(),
		registry.status_effects.size(), registry.factions.size(), a_mode])

	# Scene sync runs BEFORE the generators: skeleton creation can add scene:
	# fields the generated tools.json needs.
	var sync_report: Dictionary = SpecSceneSync.sync_all(registry, a_mode)
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

	for path in SpecGenerators.generate_all(registry):
		log.append("  generated %s" % path)

	log.append("import: done")
	return {"ok": true, "log": log}
