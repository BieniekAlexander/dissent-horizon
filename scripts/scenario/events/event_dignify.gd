class_name EventDignify extends EventTargetUnit

## Dignify ordnance: promotes a clicked Irregular into a Warlord for its commander,
## preserving the Irregular's veterancy rank. The Irregular is removed and a Warlord
## spawned in its place at the same position.

const _WARLORD_SCENE: PackedScene = preload("res://scenes/entities/units/an/warlord.tscn")

func _required_type() -> Variant:
	return EntityIds.IRREGULAR

func execute(manager: ScenarioTriggerManager) -> void:
	var commander: Commander = manager.get_commander(commander_id)
	var map: Map = manager.map
	if commander == null or map == null:
		return
	var target: Commandable = _find_target_unit(manager)
	if target == null:
		return

	var rank: Veterancy.Level = target.veterancy.level
	var spawn_xz: Vector2 = VU.inXZ(target.global_position)

	var warlord := _WARLORD_SCENE.instantiate() as Commandable
	if warlord == null:
		return
	map.add_entity(warlord, spawn_xz, commander)
	warlord.veterancy.set_level(rank)

	# Silent removal (queue_free, not a death): the Irregular is transformed, not
	# killed, so no death occurrence fires. Units carry no vigor upkeep, so this
	# leaves the commander's economy balanced.
	target.queue_free()
