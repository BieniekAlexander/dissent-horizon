@tool
class_name EventFreeze extends EventTargetUnit

## Freeze sanction (Colonial column 2): encases a clicked unit in cryo — it can take no
## action at all, and its armour class rises one step while it stands there. The rules,
## and why they are the effect's rather than this event's, are in FreezeStatusEffect.
##
## The two tiers differ ONLY in `scope`, which is authored on the sanction scene:
##   Freeze 1 — Scope.OWN, a save for a unit about to die
##   Freeze 2 — Scope.ANY, so it also takes an enemy out of the fight
## Freezing your OWN unit is a real use, not a misclick: it is the "strengthening" half
## of the faction's cryogenics, and trading a unit's actions for a step of armour is how
## you keep something alive through a barrage.
##
## Ineligible units (STRONG armour, structures) are excluded as CANDIDATES, not merely
## refused on apply, so a click near a mixed group finds a unit that can actually be
## frozen instead of picking the nearest one and doing nothing.

## The one authored definition of what a freeze IS — the cryo-blue host tint and the
## snowflake badge, alongside the rules the script itself enforces. Instanced rather than
## newed up here for the same reason EventGlobalEmp instances emp.tscn: an effect that two
## code paths construct separately is an effect that will eventually look like two.
const FREEZE_EFFECT: PackedScene = preload("res://scenes/entities/status_effects/freeze.tscn")

## How long the freeze lasts, in physics ticks (30/second). Authored per tier.
@export var duration_ticks: int = FreezeStatusEffect.DEFAULT_FREEZE_TICKS

func _qualifies(a_candidate: Commandable) -> bool:
	return FreezeStatusEffect.can_freeze(a_candidate)

func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Commandable = _find_target_unit(a_manager)
	if target == null:
		return
	var effect := FREEZE_EFFECT.instantiate() as FreezeStatusEffect
	effect.duration_ticks = duration_ticks
	effect.apply_to(target)
