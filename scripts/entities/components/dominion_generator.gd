class_name DominionGenerator
extends Node

## Generates dominion for the owning commander at a fixed tick rate. Attach as
## a child of a Commandable that should contribute dominion over time.

@export var dominion_rate: int = 10
static var TICK_RATE := 5 * Engine.physics_ticks_per_second
var frame: int = 0
var build_up: int = 0
var build_up_max: int = 10

func tick() -> void:
	frame += 1
	if frame == TICK_RATE:
		var commandable := get_parent() as Commandable
		commandable.commander.dominion += dominion_rate
		frame = 0
		build_up += 1
