@tool
class_name Lab
extends Commandable

### RESOURCES
static var TICK_RATE := 5*Engine.physics_ticks_per_second
@onready var frame: int = 0
@onready var dominion_rate := 10
var build_up: int = 0
var build_up_max: int = 10

### NODE
func _physics_process(delta: float) -> void:
	super(delta)
	frame += 1
	
	if frame==TICK_RATE:
		commander.dominion += dominion_rate
		frame = 0
		build_up += 1

func _on_death() -> void:
	var projectile: HitBox = preload("res://scenes/projectiles/radiation.tscn").instantiate()
	map.add_entity(projectile, xz_position, commander)
	super()
