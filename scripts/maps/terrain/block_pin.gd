@tool
class_name BlockPin
extends Sprite3D

## Editor-only gizmo: one pin per navigable cell (the analogue of HeightPin, which
## pins heightmap corners). Toggle its `blocked` checkbox in the inspector to mark
## the cell blocked/clear — the change writes straight through to the owning Map's
## blocked_cells list. Select several pins and toggle once to edit them all (the
## inspector applies a multi-selection edit to every selected pin).
##
## BlockPins are NOT the source of truth. They are owned by (and saved with) the
## edited scene — like HeightPins, to avoid an editor crash when adding thousands of
## un-owned nodes on large maps — but are regenerated from Map.blocked_cells by
## generate_editor_pins and delete themselves at runtime (see _ready). Map.blocked_cells
## (a saved @export) is the authoritative overlay.

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
		# not is_inside_tree(): the setter also fires while the scene is loading (Godot
		# sets saved property values before the node enters the tree). Writing then would
		# push each saved pin's stale `blocked` through to cell (0,0) — cell isn't restored
		# until _ready — so only write for a real in-tree edit (an inspector toggle).
		if _suppress_write or not Engine.is_editor_hint() or not is_inside_tree():
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
	_restore_cell_from_name()
	_refresh()


## Recover `cell` from the node name ("BlockPin_<x>_<z>"). `cell` is not exported, so a
## SAVED pin reloads with cell (0,0) — which would make editing it write through to the
## wrong Map.blocked_cells entry. The name IS saved and is set from (x, z) by the
## spawner, so parsing it restores the correct cell. No-op if the name doesn't match.
func _restore_cell_from_name() -> void:
	var parts: PackedStringArray = String(name).trim_prefix("BlockPin_").split("_")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		cell = Vector2i(int(parts[0]), int(parts[1]))


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
