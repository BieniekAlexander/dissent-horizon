class_name HitBox
extends Entity

#region Properties
@export var lifespan: int = 15*Engine.physics_ticks_per_second
#endregion

#region Lifecycle
func _physics_process(delta: float) -> void:
	for e: Entity in SU.get_nearby_entities(get_world_3d(), global_position, 2., CollisionLayers.Mask.TARGETABLE):
		if e is Commandable and e.defense != null:
			e.defense.hp -= 1

	lifespan -= 1

	if lifespan<=0:
		_on_death()
#endregion
