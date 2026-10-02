@tool
class_name EventDignify extends EventTargetUnit

## Dignify sanction: promotes a clicked Irregular into a Warlord for its commander,
## preserving the Irregular's veterancy rank. The Irregular is removed and a Warlord
## spawned in its place at the same position.

const _WARLORD_SCENE: PackedScene = preload(
	"res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn"
)


func _qualifies(a_candidate: Commandable) -> bool:
	return a_candidate.id == EntityIds.AN_BIO_LIGHT_BUILDER


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return
	var target: Commandable = _find_target_unit(a_manager)
	if target == null:
		return

	var rank: Veterancy.Level = target.veterancy.level
	var spawn_xz: Vector2 = VU.inXZ(target.global_position)

	var warlord := _WARLORD_SCENE.instantiate() as Commandable
	if warlord == null:
		return
	# Asked BEFORE the Irregular is freed, and answered against the not-yet-in-tree Warlord
	# — CommandContextParser reads components off the node, which the instantiated scene
	# already carries. A transformation is the same unit continuing, so the player's
	# standing orders come with it, as far as the new piece can carry them (see
	# CommandReceiver.portable_chain_for for why the chain truncates rather than filters).
	var orders: Array[MoveCommand] = target.command_receiver.portable_chain_for(warlord)

	map.add_entity(warlord, spawn_xz, commander)
	warlord.veterancy.set_level(rank)
	if not orders.is_empty():
		warlord.update_commands(orders)

	# Silent removal (queue_free, not a death): the Irregular is transformed, not
	# killed, so no death occurrence fires. Units carry no infrastructure upkeep, so this
	# leaves the commander's economy balanced.
	target.queue_free()
