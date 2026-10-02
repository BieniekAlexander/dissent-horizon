@tool
class_name SlowStatusEffect
extends StatusEffect

## Scales the host's Movement.speed by `slow_multiplier` per stack for `duration_ticks`
## ticks, then restores it. Example: slow_multiplier = 0.5 halves movement speed (one
## stack); two stacks → ×0.25.
##
## The change is applied/undone MULTIPLICATIVELY (slow_multiplier^count) so that
## stacks — and overlapping slows from several sources — compose correctly and restore
## in any order.

@export_range(0.0, 1.0, 0.01) var slow_multiplier: float = 0.5


func _on_apply() -> void:
	# Applied with the initial stack count (1 on a fresh apply).
	_apply_factor(_stacks)


func _on_stacks_changed(a_old_stacks: int, a_new_stacks: int) -> void:
	_apply_factor(a_new_stacks - a_old_stacks)


func _on_remove() -> void:
	# Undo every stack currently applied.
	_apply_factor(-_stacks)


## Multiply the host's speed by slow_multiplier^count. A negative count undoes that many
## stacks. No-op without a Movement, or for a non-positive multiplier (can't be undone).
func _apply_factor(a_count: int) -> void:
	if a_count == 0 or _entity == null or _entity.movement == null or slow_multiplier <= 0.0:
		return
	_entity.movement.speed *= pow(slow_multiplier, a_count)
