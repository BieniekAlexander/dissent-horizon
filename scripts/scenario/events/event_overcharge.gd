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
## The test is an EMP specifically (`EmpStatusEffect.is_emped`), not any stun: a unit a
## Colonial Freeze or a bio stun has disabled is just as helpless, but Overcharge is the EMP's
## follow-through and nothing else's. Decided 2026-10-05; it used to accept any stun.
##
## Flat damage rather than a fraction of max HP: the pairing already guarantees the
## target cannot escape, so scaling to the target's size would make the combination an
## unconditional kill on anything. A flat number lets the biggest machines survive it,
## which is what keeps EMP + Overcharge a strong play rather than the only play.

## Damage dealt to the disabled target. Applied straight to hit points, bypassing armour and
## any shield: the target is opened up.
@export var damage: float = 400.0


func _qualifies(a_candidate: Actor) -> bool:
	return (
		a_candidate.defense != null
		and a_candidate.defense.hp > 0
		and EmpStatusEffect.is_emped(a_candidate)
	)


func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Actor = _find_target_unit(a_manager)
	if target == null:
		return
	# Death itself is detected by Actor._update_state's hp <= 0 check, so the normal
	# teardown (garrison release, production refunds, grid removal) runs either way.
	target.defense.apply_damage(damage)
