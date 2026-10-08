@tool
class_name EventFreeze extends EventTargetUnit

## Freeze sanction (Colonial column 2): encases a clicked piece in cryo — it can take no
## action at all, and a STRONG shield of ice takes damage before it does. The rules, and why
## they are the effect's rather than this event's, are in FreezeStatusEffect.
##
## The two tiers differ ONLY in `scope`, which is authored on the sanction scene:
##   Freeze 1 — Scope.OWN, a save for a piece about to die
##   Freeze 2 — Scope.ANY, so it also takes an enemy out of the fight
##
## Structures may be named as well as units. STRONG pieces are excluded as CANDIDATES, not
## merely refused on apply, so the cursor never highlights a piece the cast would not freeze.

## The one authored definition of what a freeze IS — the cryo-blue host tint and the
## snowflake badge, alongside the rules the script itself enforces. Instanced rather than
## newed up here for the same reason EventGlobalEmp instances emp.tscn: an effect that two
## code paths construct separately is an effect that will eventually look like two.
const FREEZE_EFFECT: PackedScene = preload("res://scenes/entities/status_effects/freeze.tscn")


func _admits_structures() -> bool:
	return true


func _qualifies(a_candidate: Actor) -> bool:
	return FreezeStatusEffect.can_freeze(a_candidate)


func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Actor = _find_target_unit(a_manager)
	if target == null:
		return
	var effect := FREEZE_EFFECT.instantiate() as FreezeStatusEffect
	effect.apply_to(target)
