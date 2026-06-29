@tool
class_name SuicideStatusEffect
extends StatusEffect

## Destroys the INFLICTING unit (this effect's `source`) instead of its host. Authored
## as a child of an EffectApplicator on a "detonating" projectile: when that projectile
## lands, every entity in the blast spawns a copy of this effect, and each copy kills the
## unit that fired the projectile (Projectile.from). The host entity (`_entity`, a blast
## victim) is deliberately left alone — the blast's own damage is the projectile's job;
## this effect's sole responsibility is making the firer die.
##
## Contrast with SlowStatusEffect / DamageOverTimeStatusEffect, which act on the host.
##
## RELIANCE WORTH KNOWING: EffectApplicator skips application entirely when the blast hits
## nothing, so this effect only fires when the blast has at least one recipient. A
## detonating projectile that spawns at the firer's position (pre_impact_lifespan = 0,
## big radius) and does NOT exclude the firer from its hit query keeps the firer in its
## own blast, so there is always a recipient. If that geometry changes, this effect can
## silently stop firing.

func _on_apply() -> void:
	# `source` (the firer) is assigned by apply_to() before this hook runs. We apply once
	# per blast recipient, so this can run several times against the same dying source —
	# is_instance_valid guards against acting on an already-freed firer, and a null source
	# (an unattributed hit, see Projectile._apply_hit) means there is nothing to kill.
	if source != null and is_instance_valid(source) and source.defense != null:
		# Drop the firer to 0 HP and let the normal death path (Commandable._update_state
		# -> _on_death) handle commander/grid teardown and queue_free, rather than tearing
		# the firer down from inside another entity's effect.
		source.defense.kill()

	# This effect has done its job; don't linger on the host victim doing nothing for
	# duration_ticks. remove() undoes nothing (no _on_remove override) and frees the node.
	remove()
