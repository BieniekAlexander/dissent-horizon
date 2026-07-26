extends SceneTree

## Spec importer CLI: gdd docs -> Godot. One-way (docs govern; the old
## Godot->YAML export direction is retired).
##
## Run:
##   godot --headless -s res://tools/spec_import/import.gd            # full
##   godot --headless -s res://tools/spec_import/import.gd -- --mode=incremental
##
## Pipeline: scan gdd/**/*.md -> validate EVERYTHING (abort loudly on any
## error, writing nothing) -> regenerate code/data artifacts -> sync scenes
## (Phase 5). Modes differ only in scene-sync collection handling:
##   full        — spec lists are authoritative; scene-only items are deleted
##   incremental — update/create only; scene-only items are preserved
##
## The editor plugin runs this same pipeline in-process (see ImportPipeline).

const ImportPipeline := preload("res://tools/spec_import/import_pipeline.gd")


func _initialize() -> void:
	var mode: String = "full"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
	if mode not in ["full", "incremental"]:
		push_error("import: unknown mode '%s' (full|incremental)" % mode)
		quit(1)
		return

	var result: Dictionary = ImportPipeline.run(mode)
	for line in result["log"]:
		print(line)
	if not result["ok"]:
		quit(1)
		return
	quit()
