@tool
extends EditorPlugin

## Toolbar entry point for the spec importer (tools/spec_import): a "Spec
## Import" menu with full / incremental runs. Same pipeline as the CLI
## (`godot --headless -s res://tools/spec_import/import.gd`); the import
## summary and any validation errors land in the Output panel, and the
## filesystem is rescanned afterwards so changed scenes/resources reload.

const ImportPipeline := preload("res://tools/spec_import/import_pipeline.gd")

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
	var result: Dictionary = ImportPipeline.run(mode)
	for line in result["log"]:
		print(line)
	if result["ok"]:
		print_rich("[b]Spec Import[/b]: OK")
	else:
		push_error("Spec Import failed — see the Output panel for the validation errors.")
	EditorInterface.get_resource_filesystem().scan()
