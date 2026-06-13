## Editor-only component that snaps a structure's position to the terrain grid
## whenever it is moved in the Godot editor.
##
## Add as a child of any structure scene.  At runtime the node frees itself
## immediately in _ready, so it has zero gameplay overhead.
##
## Snapping logic: find the Map in the edited scene, convert the parent's world
## XZ to a grid cell via Map.world_to_grid, then set global_position to
## Map.grid_to_world of that cell.  This mirrors how add_structure places
## buildings at runtime.
@tool
class_name StructureSnap
extends Node

## When false (the default), the structure may only be placed on perfectly flat
## cells.  Set to true for structures that should be placeable on steep terrain
## — for example, terrain-blocking obstacles.
@export var allow_uneven_terrain: bool = false

var _last_snapped_pos: Vector3 = Vector3.INF


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var structure := get_parent() as Node3D
	if structure == null:
		return
	# Skip if the position hasn't changed since our last snap.
	if structure.global_position.is_equal_approx(_last_snapped_pos):
		return
	var map := _find_map()
	if map == null:
		return
	var xz := Vector2(structure.global_position.x, structure.global_position.z)
	var cell := map.world_to_grid(xz)
	var snapped := map.grid_to_world(cell)
	structure.global_position = snapped
	_last_snapped_pos = snapped


## Walk up to the scene owner (the edited scene root) and find the Map node.
## Returns null if not editing inside a scene that contains a Map.
func _find_map() -> Map:
	var root: Node = owner
	if root == null:
		return null
	return root.find_child("Map", true, false) as Map
