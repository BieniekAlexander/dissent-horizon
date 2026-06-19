class_name CommanderAbilityIrradiate extends CommanderAbility

func _init() -> void:
	ability_name = "Irradiate"

func _make_event() -> AbstractEvent:
	return EventAbilityIrradiate.new()
