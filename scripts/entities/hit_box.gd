class_name HitBox
extends Entity

@export var lifespan: int = 15*Engine.physics_ticks_per_second

func _physics_process(delta: float) -> void:
	for e: Entity in map.get_nearby_entities(global_position, 2.):
		if e is Commandable:
			e.hp -= 1
	
	lifespan -= 1
	
	if lifespan<=0:
		_on_death()
