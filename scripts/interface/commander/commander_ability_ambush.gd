class_name CommanderAbilityAmbush extends CommanderAbility

func _init() -> void:
	ability_name = "Ambush"

func _make_event() -> AbstractEvent:
	return EventAbilityAmbush.new()
