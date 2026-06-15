class_name CommanderAbilityIrradiate extends CommanderAbility

func _init() -> void:
	ability_name = "Irradiate"

func _make_event() -> ScenarioEvent:
	return EventAbilityIrradiate.new()
