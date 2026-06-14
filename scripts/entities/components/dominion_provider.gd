class_name DominionProvider
extends Node

## Provides dominion to the owning commander at a fixed tick rate, scaled by
## the unit's veterancy level. Attach as a child of a Commandable that has a
## Veterancy component.

#region Properties
## Dominion awarded per veterancy level per tick cycle.
## At NONE(0)=0, VETERAN(1)=10, ELITE(2)=20, HEROIC(3)=30.
@export var dominion_per_level: int = 10
static var TICK_RATE: int = 150
var frame: int = 0
#endregion

#region Public API
func tick() -> void:
	frame += 1
	if frame % TICK_RATE == 0:
		var commandable := get_parent() as Commandable
		if commandable == null or commandable.commander == null:
			return
		var level: int = int(commandable.veterancy.level) if commandable.veterancy != null else 0
		commandable.commander.dominion += dominion_per_level * level
#endregion
