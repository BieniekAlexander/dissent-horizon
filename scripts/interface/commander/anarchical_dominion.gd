class_name AnarchicalDominion
extends Node

#region Properties
## Dominion awarded per veterancy level per tick cycle.
@export var dominion_per_unit: int = 5
static var TICK_RATE: int = 150
var frame: int = 0
@onready var commander: Commander = get_parent().get_parent()
#endregion

func _proc() -> void:
	var warlords: Array = commander.get_children().filter(
		func(n): return n is Commandable and n.type==Entity.Type.AN_UNIT_WARLORD
	)
	
	var procs: Array = []
	
	for warlord in warlords:
		var results = SU.query_shape_for_entities(
			warlord.get_world_3d(),
			warlord.get_node("DominionRegion").shape,
			warlord.global_transform,
			CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
		)
		results = results.filter(
			func(e: Entity) -> bool: return e.type!=Entity.Type.AN_UNIT_WARLORD and e.defense.frame_type==Defense.FrameType.BIOLOGICAL
		)
		
		for irregular: Commandable in results:
			if irregular not in procs:
				procs.append(irregular)
		
	commander.add_dominion(procs.size() * dominion_per_unit)

func _physics_process(delta: float) -> void:
	frame += 1
	if frame % TICK_RATE == 0:
		_proc()
