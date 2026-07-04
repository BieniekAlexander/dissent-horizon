@tool
class_name BlockPin
extends Sprite3D

## Editor-only gizmo: one pin per navigable cell (the analogue of HeightPin, which
## pins heightmap corners). Toggle its `blocked` checkbox in the inspector to mark
## the cell blocked/clear — the change writes straight through to the owning Map's
## blocked_cells list. Select several pins and toggle once to edit them all (the
## inspector applies a multi-selection edit to every selected pin).
##
## BlockPins are NOT the source of truth and are NOT saved with the scene: they are
## regenerated from Map.blocked_cells by generate_editor_pins, and delete themselves
## at runtime. Map.blocked_cells (a saved @export) is the authoritative overlay.

## The navigable cell this pin marks (grid indices, Vector2i(x, z)). Set by the
## spawner; not exported (pins are transient).
var cell: Vector2i

var _blocked: bool = false

## When true, the pin is having its state set FROM the Map (spawn/refresh) and must
## not write back — otherwise reading the overlay would immediately re-write it.
var _suppress_write: bool = false

## Inspector checkbox. Toggling it (including across a multi-selection) blocks/clears
## this pin's cell in the owning Map's blocked_cells.
@export var blocked: bool = false:
	get:
		return _blocked
	set(value):
		_blocked = value
		_refresh()
		if _suppress_write or not Engine.is_editor_hint():
			return
		var map := _find_map()
		if map != null:
			map.set_cell_blocked(cell, _blocked)


func _ready() -> void:
	texture = load("res://assets/logo.png")
	scale = Vector3.ONE * 0.12
	if not Engine.is_editor_hint():
		queue_free()
		return
	_refresh()


## Set `blocked` to reflect external (Map) state without writing back to the Map.
func set_blocked_silently(value: bool) -> void:
	_suppress_write = true
	blocked = value
	_suppress_write = false


## Recolour to reflect `_blocked` (red = blocked, translucent grey = clear).
func _refresh() -> void:
	modulate = Color(1.0, 0.15, 0.15, 1.0) if _blocked else Color(0.55, 0.55, 0.55, 0.35)


## Walk up to the owning Map (pins live under Map/BlockPins).
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
