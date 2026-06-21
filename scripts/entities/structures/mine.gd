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
## Link this mine to its deposit (both directions). The mine OVERLAYS the deposit and
## becomes the interactive entity at that cell — it must stay selectable (cursor /
## right-click) and targetable (attack / aggro). The deposit underneath is hidden: its
## own Selectable + TargetBody are suppressed so clicks and target queries resolve to the
## mine (an enemy structure) rather than the neutral deposit. Restored on mine death (see
## _on_death). The deposit remains the sole GRID occupant throughout (unchanged).
func bind_deposit(a_deposit: Deposit) -> void:
	deposit = a_deposit
	if a_deposit != null:
		a_deposit.mine = self
		_set_deposit_interaction_disabled(true)
#endregion

#region Deposit overlay
## Deposit Selectable/TargetBody shapes we disabled on bind, remembered so restoration
## re-enables exactly those (and not any disabled for another reason).
var _deposit_disabled_shapes: Array[CollisionShape3D] = []

## Suppress (or restore) the host deposit's interaction colliders — the CollisionShape3Ds
## under its Selectable (SELECTION layer) and TargetBody (TARGETABLE layer) — so the
## overlaying mine is the sole click/attack target. The deposit's grid/movement presence
## is left untouched; only its selection + targetability are toggled. Editor-inert.
func _set_deposit_interaction_disabled(a_disabled: bool) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(deposit):
		return
	if a_disabled:
		for shape in _deposit_interaction_shapes():
			if not shape.disabled:
				shape.disabled = true
				_deposit_disabled_shapes.append(shape)
	else:
		for shape in _deposit_disabled_shapes:
			if is_instance_valid(shape):
				shape.disabled = false
		_deposit_disabled_shapes.clear()

## The deposit's SELECTION + TARGETABLE CollisionShape3Ds (under its Selectable and
## TargetBody). Empty entries are skipped if the deposit lacks either component.
func _deposit_interaction_shapes() -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	for host: Node in [deposit.selectable, deposit.target_body]:
		if host != null:
			for node in host.find_children("*", "CollisionShape3D", true, false):
				if node is CollisionShape3D:
					result.append(node as CollisionShape3D)
	return result
#endregion

#region Lifecycle
func _on_death() -> void:
	# The deposit is never removed from the grid; just release it so it can be mined
	# again, and restore the interaction colliders we suppressed while overlaying it.
	# super() handles the rest of the structure teardown.
	if is_instance_valid(deposit):
		_set_deposit_interaction_disabled(false)
		deposit.mine = null
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
