@tool
class_name DamageOverTimeStatusEffect
extends StatusEffect

## Deals `damage_per_tick` × stacks damage to the host every `tick_rate` ticks, for
## `duration_ticks` ticks. Example (engulfed in flames): damage_per_tick = 10,
## tick_rate = 10, duration_ticks = 100 → 10 damage every 10 ticks, ten times (one
## stack). Under ReapplyMode.STACK the per-tick damage scales with the stack count.

@export var damage_per_tick: float = 10.0
## Period, in ticks, between damage applications. 1 = every tick.
@export var tick_rate: int = 10
## Damage flavour for future armor-multiplier wiring. NOTE: receive_damage() currently
## applies a raw amount (it takes no Damage.Type), so this mirrors Projectile.damage_type
## as metadata until the multiplier path (Damage.multiplier_patterns) is wired in.
@export var damage_type: Damage.Type = Damage.Type.FIRE

func _on_tick() -> void:
	if tick_rate <= 0:
		return
	if not (_entity is Commandable):
		return
	var victim: Commandable = _entity as Commandable
	if victim.defense == null:
		return
	# Fire on tick_rate boundaries counting from the first tick (so a 100-tick effect
	# at tick_rate 10 lands at ticks 10, 20, … 100 — never a free hit at tick 0, which
	# the projectile's own impact damage already covers).
	if (_elapsed + 1) % tick_rate == 0:
		var src: Commandable = source if (source != null and is_instance_valid(source)) else null
		victim.receive_damage(src, damage_per_tick * _stacks)
