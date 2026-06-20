@tool
class_name StatusEffect
extends Node

## A live, self-contained status effect attached as a CHILD of the Entity it acts on.
##
## Lifecycle (all measured in physics ticks; the game runs at 30 ticks/second):
##   apply_to(entity)  — reparents this node under `entity`, then _on_apply() enacts it.
##   _physics_process  — each tick calls _on_tick(); after `duration_ticks` ticks the
##                       effect ends: _on_remove() undoes it and the node frees itself.
##   remove()          — external cancellation (a relevant event forces it to finish).
##
## Subclasses override the hooks. Authored as a node, a StatusEffect doubles as a
## TEMPLATE: while it sits unattached under an EffectApplicator (no _entity), its
## _physics_process is inert. EffectApplicator duplicate()s the template and calls
## apply_to() per recipient, so the template is never consumed.
##
## REAPPLICATION — when a kind of effect already on the host is applied again (matched
## by script, i.e. "the same status effect"), `reapply_mode` decides what happens
## instead of adding a second node:
##   REFRESH — reset the existing effect's timer (no second instance, no extra potency).
##   STACK   — increment the existing effect's stack count up to `max_stacks`, scaling
##             its potency (stacks-as-data: one node, one timer). Subclasses read
##             `stacks` (DoT) or react to _on_stacks_changed() (Slow) to scale.
## Either way the timer is refreshed on reapply.

#region Properties
enum ReapplyMode {
	REFRESH = 0,
	STACK = 1,
}

## Lifespan in physics ticks. <= 0 means the effect persists until remove() is called
## externally (e.g. an aura that lasts while a unit stays in a region).
@export var duration_ticks: int = 90

## What happens when this kind of effect is reapplied to a host that already has it.
@export var reapply_mode: ReapplyMode = ReapplyMode.REFRESH

## Maximum number of stacks under ReapplyMode.STACK. Forced to 1 and made read-only in
## any other mode (a non-stacking effect is always a single instance).
@export var max_stacks: int = 1

## The entity that inflicted this effect, for damage attribution (may be null / freed).
var source: Commandable = null

## Current stack count (>= 1 once applied). Read-only to the outside; subclasses scale
## their potency off it. Always 1 unless reapply_mode == STACK.
var stacks: int:
	get: return _stacks

## The entity this effect is acting on. null while this node is an unapplied template.
var _entity: Entity = null
var _elapsed: int = 0
var _stacks: int = 1
#endregion

#region Tool
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"reapply_mode":
			# Editing the mode re-runs validation so max_stacks' read-only state updates.
			property.usage |= PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED
		"max_stacks":
			if reapply_mode != ReapplyMode.STACK:
				max_stacks = 1
				property.usage |= PROPERTY_USAGE_READ_ONLY
			else:
				property.usage &= ~PROPERTY_USAGE_READ_ONLY
#endregion

#region Public API
## Attach this effect to `a_entity` (reparenting under it) and enact it. `a_source` is
## the inflictor, used for damage attribution by damage-dealing effects.
##
## If the host already carries this kind of effect, the existing instance is reapplied
## per `reapply_mode` and THIS node is discarded (it was a redundant duplicate).
func apply_to(a_entity: Entity, a_source: Commandable = null) -> void:
	var existing: StatusEffect = _find_matching(a_entity)
	if existing != null and existing != self:
		existing._reapply(a_source)
		queue_free()
		return

	_entity = a_entity
	source = a_source
	_stacks = 1
	if get_parent() != _entity:
		if get_parent() != null:
			get_parent().remove_child(self)
		_entity.add_child(self)
	_on_apply()


## End the effect early: undo it and free this node. Idempotent / no-op on a template.
func remove() -> void:
	if _entity == null:
		return
	_on_remove()
	_entity = null
	queue_free()


## True while this effect is attached and acting on a host. False for an unapplied
## template and for an effect that has been removed (its queue_free may still be pending).
func is_active() -> bool:
	return _entity != null
#endregion

#region Lifecycle
func _physics_process(_delta: float) -> void:
	# Inert while a template (no entity) or in the editor.
	if Engine.is_editor_hint() or _entity == null:
		return
	# The host died out from under us — drop silently (its teardown frees us anyway,
	# but guard the tick that runs before the free is processed).
	if not is_instance_valid(_entity):
		_entity = null
		queue_free()
		return
	_on_tick()
	_elapsed += 1
	if duration_ticks > 0 and _elapsed >= duration_ticks:
		remove()
#endregion

#region Reapplication
## Re-enact an already-active effect of this kind. Refreshes the timer in both modes
## and, under STACK, adds a stack (capped at max_stacks). Re-attributes to the latest
## inflictor so the most recent source gets credit for any damage.
func _reapply(a_source: Commandable) -> void:
	source = a_source
	_elapsed = 0
	if reapply_mode == ReapplyMode.STACK and _stacks < max_stacks:
		var old: int = _stacks
		_stacks += 1
		_on_stacks_changed(old, _stacks)


## The active effect of the SAME kind (matched by script) already on `a_entity`, or
## null. "Same kind" = same StatusEffect subclass; distinct potencies of one subclass
## are treated as one effect (the existing instance's parameters win).
func _find_matching(a_entity: Entity) -> StatusEffect:
	for child: Node in a_entity.get_children():
		# Skip an effect that has already been removed this frame (queue_free pending)
		# so we don't refresh/stack onto a dying instance.
		if child is StatusEffect and child.get_script() == get_script() \
				and (child as StatusEffect).is_active():
			return child as StatusEffect
	return null
#endregion

#region Overridable hooks
## Enact the effect when first attached (e.g. apply a slow multiplier for one stack).
func _on_apply() -> void:
	pass


## Per-tick behaviour while active (e.g. periodic damage). `_elapsed` ticks have
## elapsed so far; this call is tick number `_elapsed`.
func _on_tick() -> void:
	pass


## Undo the effect when it ends — whether by elapsing or external removal. Should undo
## ALL current stacks (read `_stacks`).
func _on_remove() -> void:
	pass


## React to a stack-count change under ReapplyMode.STACK (e.g. apply the slow factor
## for the (new - old) additional stacks). Effects whose _on_tick reads `stacks`
## directly (like DoT) don't need this. Default: no-op.
func _on_stacks_changed(_old_stacks: int, _new_stacks: int) -> void:
	pass
#endregion
