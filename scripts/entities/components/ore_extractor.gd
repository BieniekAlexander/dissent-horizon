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

#region Checks
## A mine may only be placed on a Deposit that has no mine yet. The mine binds to
## (and overlays) the whole deposit object, so it's enough that the clicked cell
## belongs to a free deposit — any cell of a multi-cell deposit works. This forbids
## building on bare ground, on other structures, and stacking a second mine on one
## deposit. (a_dimensions is unused: the mine doesn't occupy the grid itself.)
static func valid_placement(
	a_command_message: CommandMessage,
	_a_dimensions: Vector2i,
	_a_allow_uneven_terrain: bool = false
) -> bool:
	var map: Map = a_command_message.map
	if map == null:
		return false
	var cell: Vector2i = map.world_to_grid(a_command_message.xz_position)
	if not map.grid_coordinates_in_bounds(cell):
		return false
	var occupant = map.cell_grid[cell.x][cell.y]
	return occupant is Deposit and (occupant as Deposit).mine == null
#endregion
