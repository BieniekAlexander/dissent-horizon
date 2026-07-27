@tool
extends EditorPlugin

## Adds the map-generation dock (map_generator_dock.gd). The generator itself is
## scripts/maps/generation/; see gdd/systems/terrain-and-navigation/map-generation.md.

const MapGeneratorDock := preload("res://addons/map_generator/map_generator_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = MapGeneratorDock.new()
	_dock.name = "Map Generator"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()
