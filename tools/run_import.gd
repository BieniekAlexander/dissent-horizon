extends Node

## Throwaway runner for the spec importer. The CLI form
## (`godot --headless -s res://tools/spec_import/import.gd`) cannot see the project's
## AUTOLOADS, so every script naming DamageTable / SceneManager fails to compile and the
## pipeline never runs. A scene boots the autoloads first, which is why this exists.
##
## Run with:
##   godot --headless res://tools/run_import.tscn

const ImportPipeline := preload("res://tools/spec_import/import_pipeline.gd")


func _ready() -> void:
	var result: Dictionary = ImportPipeline.run("full", "res://gdd", false)
	for line: Variant in result["log"]:
		print(line)
	for line: Variant in result.get("errors", []):
		print("ERROR: ", line)
	print("import ok: ", result["ok"])
	get_tree().quit(0 if result["ok"] else 1)
