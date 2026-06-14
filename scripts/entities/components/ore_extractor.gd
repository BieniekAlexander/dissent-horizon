class_name OreExtractor
extends Node

## Extracts ore from the map cell under the structure each tick and deposits
## it into the owning commander's ore pool. Attach as a child of a Commandable
## that sits on an ore-bearing cell.

#region Properties
@export var ore_rate: int = 25
static var TICK_RATE := 5 * Engine.physics_ticks_per_second
var frame: int = 0
#endregion

#region Public API
func tick() -> void:
	frame += 1
	if frame%TICK_RATE==0:
		var commandable := get_parent() as Commandable
		commandable.commander.ore += ore_rate
#endregion
