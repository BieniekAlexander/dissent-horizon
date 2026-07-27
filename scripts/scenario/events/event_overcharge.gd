@tool
class_name EventOvercharge extends EventTargetUnit

## Overcharge sanction (Anarchical tier 3): dumps a large flat amount of damage into a
## unit that is ALREADY disabled — "can only target an EMPed unit"
## (gdd/factions/anarchical/anarchical.md).
##
## The prerequisite is the design: Overcharge is the second half of a two-sanction
## combination, worth nothing on its own and decisive after Global EMP. So being EMPed
## is an admission test on the CANDIDATE, not a damage bonus — a click that finds no
## disabled unit does nothing at all rather than dealing reduced damage to whatever was
## nearest.
##
## `Commandable.is_stunned()` is the test, which means a unit disabled by any hard stun
## qualifies, including a Colonial FreezeStatusEffect (it extends StunStatusEffect). That
## cross-faction interaction is accepted rather than special-cased: a frozen unit is
## exactly as helpless as an EMPed one, and a rule that read "disabled, but only by our
## own EMP" would be arbitrary from the target's point of view.
##
## Flat damage rather than a fraction of max HP: the pairing already guarantees the
## target cannot escape, so scaling to the target's size would make the combination an
## unconditional kill on anything. A flat number lets the biggest machines survive it,
## which is what keeps EMP + Overcharge a strong play rather than the only play.

## Damage dealt to the disabled target. Applied straight to Defense, bypassing armour:
## the target is opened up, and the armour step a Freeze just added must not blunt it.
@export var damage: float = 400.0

func _qualifies(a_candidate: Commandable) -> bool:
	return a_candidate.defense != null and a_candidate.defense.hp > 0 and a_candidate.is_stunned()

func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Commandable = _find_target_unit(a_manager)
	if target == null:
		return
	# Death itself is detected by Commandable._update_state's hp <= 0 check, so the normal
	# teardown (garrison release, production refunds, grid removal) runs either way.
	target.defense.apply_damage(damage)
