@tool
extends EditorPlugin

## Toolbar entry point for the spec importer (tools/spec_import): a "Spec
## Import" menu with full / incremental runs. Same pipeline as the CLI
## (`godot --headless -s res://tools/spec_import/import.gd`); the import
## summary and any validation errors land in the Output panel, and the
## filesystem is rescanned afterwards so changed scenes/resources reload.

## Loaded when a run is asked for, not preloaded. As a const the script is resolved as the
## CLASS ImportPipeline, so `has_method()` below would be a parse error ("non-static
## function on the class") and the whole plugin would fail to load. Loaded, it is a plain
## GDScript value whose compile state can be checked.
const IMPORT_PIPELINE_PATH: String = "res://tools/spec_import/import_pipeline.gd"

const _ITEM_FULL: int = 0
const _ITEM_INCREMENTAL: int = 1

var _menu: MenuButton


func _enter_tree() -> void:
	_menu = MenuButton.new()
	_menu.text = "Spec Import"
	_menu.tooltip_text = "Import gdd/ spec docs into scenes + generated data.\nFull: spec collections are authoritative (scene-only items removed).\nIncremental: update/create only (scene-only items preserved)."
	_menu.get_popup().add_item("Import (full)", _ITEM_FULL)
	_menu.get_popup().add_item("Import (incremental)", _ITEM_INCREMENTAL)
	_menu.get_popup().id_pressed.connect(_on_item_pressed)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _menu)


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _menu)
	_menu.queue_free()


func _on_item_pressed(a_id: int) -> void:
	var mode: String = "full" if a_id == _ITEM_FULL else "incremental"
	print_rich("[b]Spec Import[/b] (%s mode) …" % mode)
	# The pipeline itself failed to compile: `run` does not exist, and calling it would die
	# on "Nonexistent function" and then on an empty result. Say why instead.
	var pipeline: GDScript = load(IMPORT_PIPELINE_PATH)
	# NOT can_instantiate(): in the editor that is false for any script without @tool, which
	# refused every run. A script that failed to compile has no methods; this one has `run`.
	if pipeline == null or not pipeline.has_method("run"):
		push_error("Spec Import: import_pipeline.gd failed to compile — see the first script"
			+ " error above. If it has since been fixed, Project > Reload Current Project.")
		return
	var result: Dictionary = pipeline.run(mode)
	for line in result["log"]:
		print(line)
	if result["ok"]:
		print_rich("[b]Spec Import[/b]: OK")
	else:
		push_error("Spec Import failed — see the Output panel for the validation errors.")
	EditorInterface.get_resource_filesystem().scan()
