class_name EventSpawnEmission extends AbstractEvent

## Puts an emission into the world where this event stands, aimed at that same spot — so it
## lands where it appears. What an emission phase's `emits:` becomes: a trail of clouds left
## behind something in flight is this event, run on the phase's cadence.

@export var emission_scene: PackedScene

## Commander the emission belongs to. Set by whatever runs the event, before execute.
var commander_id: int = 0


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	if emission_scene == null or commander == null or a_manager.map == null:
		return
	var emission: Entity = emission_scene.instantiate() as Entity
	emission.initialize(a_manager.map, commander)
	emission.global_position = global_position
	Emitter.launch(emission, null, global_position)
