@tool
class_name Mine
extends Commandable

## A Mine is built "on top of" a Deposit. It does NOT occupy the terrain grid
## itself — the Deposit stays the sole grid occupant; the Mine overlays it and the
## two hold mutual references (see Map.add_structure routing and Deposit). The
## Mine's OreExtractor child does the actual ore collection (generic, unchanged).

#region Properties
## The deposit this mine sits on. Set by the build path at runtime (Map.add_structure)
## or authored in a scene (and auto-created by the editor convenience below).
@export var deposit: Deposit
#endregion

#region Public API
## Link this mine to its deposit (both directions). While the mine overlays the
## deposit the deposit stays the sole grid/collision occupant, so the mine's own
## colliders are disabled to avoid duplicating it; they're restored when the mine
## is released from the deposit (see _on_death).
func bind_deposit(a_deposit: Deposit) -> void:
	deposit = a_deposit
	if a_deposit != null:
		a_deposit.mine = self
		_set_colliders_disabled(true)
#endregion

#region Colliders
## CollisionShape3Ds we disabled on bind, remembered so restoration re-enables
## exactly those (and not any that were already disabled for another reason).
var _overlay_disabled_shapes: Array[CollisionShape3D] = []

## Disable (or restore) every collider under the mine. Called when the mine
## starts / stops overlaying a deposit. Editor-inert so the in-editor preview
## keeps its colliders.
func _set_colliders_disabled(a_disabled: bool) -> void:
	if Engine.is_editor_hint():
		return
	if a_disabled:
		for node in find_children("*", "CollisionShape3D", true, false):
			var shape := node as CollisionShape3D
			if shape != null and not shape.disabled:
				shape.disabled = true
				_overlay_disabled_shapes.append(shape)
	else:
		for shape in _overlay_disabled_shapes:
			if is_instance_valid(shape):
				shape.disabled = false
		_overlay_disabled_shapes.clear()
#endregion

#region Lifecycle
func _on_death() -> void:
	# The deposit is never removed from the grid; just release it so it can be
	# mined again, and restore the colliders disabled while overlaying it.
	# super() handles the rest of the structure teardown.
	if deposit != null and is_instance_valid(deposit):
		deposit.mine = null
	_set_colliders_disabled(false)
	super()


func _ready() -> void:
	if Engine.is_editor_hint():
		# Defer so the node's owner/parent are settled before we add a sibling.
		call_deferred(&"_ensure_editor_deposit")
		return
	super()
#endregion

#region Editor helpers
## When a Mine is authored into a scene without a deposit, auto-create a linked
## Deposit sibling at the same spot so the mine is valid. Guarded on deposit==null
## so it runs once and never fights the user (deleting the deposit clears the link,
## which correctly recreates one — a mine without a deposit is invalid anyway).
func _ensure_editor_deposit() -> void:
	if not Engine.is_editor_hint() or deposit != null:
		return
	# owner==null means this Mine is itself the scene being edited (opened directly),
	# not an instance placed inside another scene — nothing to attach to.
	var scene_owner := owner
	var parent := get_parent()
	if scene_owner == null or parent == null:
		return
	var d: Deposit = load("res://scenes/structures/deposit.tscn").instantiate()
	parent.add_child(d)
	d.owner = scene_owner
	d.global_transform = global_transform
	d.name = name + "Deposit"
	deposit = d
#endregion
