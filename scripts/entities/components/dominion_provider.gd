class_name AnarchicalDominion
extends Node3D

## Provides dominion to the owning commander at a fixed tick rate, scaled by
## the unit's veterancy level. Attach as a child of a Commandable that has a
## Veterancy component.

#region Properties
## Dominion awarded per veterancy level per tick cycle.
@export var dominion_per_unit: int = 10
@onready var dominion_region: CollisionShape3D = $DominionRegion
static var TICK_RATE: int = 150
var frame: int = 0
#endregion

func _proc() -> void:
	var results = SU.query_shape_for_entities(
		get_world_3d(),
		dominion_region.shape,
		global_transform,
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
	)
	results = results.filter(
		func(e: Entity) -> bool: return e.type == Entity.Type.AN_UNIT_IRREGULAR
	)
	
	get_parent().commander.add_dominion(results.size() * dominion_per_unit)

#region Public API
func _physics_process(_delta: float) -> void:
	frame += 1
	if frame % TICK_RATE == 0:
		_proc()
#endregion
