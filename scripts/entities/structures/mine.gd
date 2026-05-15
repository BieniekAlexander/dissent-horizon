@tool
class_name Mine
extends Commandable

### RESOURCES
static var TICK_RATE := 5*Engine.physics_ticks_per_second
@onready var frame: int = 0
@onready var ore_rate := 25

static func valid_placement(a_command_message: CommandMessage, a_dimensions: Vector2i) -> bool:
	push_error("TODO")
	return true

### NODE
func _physics_process(delta: float) -> void:
	super(delta)
	frame += 1
	
	if frame==TICK_RATE:
		var cell = map_cells.get_values()[0]
		if cell.ore>0:
			commander.ore += ore_rate
			cell.ore -= ore_rate
			frame = 0
			
			if cell.ore <= 0:
				cell.set_shallow()
