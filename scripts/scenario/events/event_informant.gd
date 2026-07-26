class_name EventInformant extends EventTargetUnit

## Informant ordnance: grants a clicked Irregular stealth by attaching a Stealth
## component at runtime. The Irregular scene ships without one (its Stealth node was
## removed), so this adds it and wires the entity's `stealth` reference so
## Commandable ticks it and the sprite fades. No-op if it is already stealthed.

func _required_type() -> Variant:
	return EntityIds.IRREGULAR

func execute(manager: ScenarioTriggerManager) -> void:
	var target: Commandable = _find_target_unit(manager)
	if target == null or target.stealth != null:
		return

	var stealth := Stealth.new()
	stealth.name = "Stealth"
	# add_child runs Stealth._ready, which registers the entity on the STEALTH
	# collision layer; refresh_movement_collision preserves that bit.
	target.add_child(stealth)
	# Entity.stealth is a plain (get_node_or_null-seeded) field resolved at _ready,
	# so it stays null for a component added later — set it so every reader (tick,
	# sprite alpha, detection) sees the new component.
	target.stealth = stealth
