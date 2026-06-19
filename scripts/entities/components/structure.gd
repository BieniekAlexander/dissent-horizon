@tool
class_name Structure
extends Node

## Marks its parent Entity as a structure: a grid-occupying building (as opposed
## to a mobile unit). Presence of this component is the single discriminator for
## "is this a structure" — checked via has_node("Structure") rather than reading
## Entity.Type. Also declares the building's grid footprint.

#region Properties
## How many grid cells this entity blocks in each axis (width × depth).
## Footprint origin is the min-x/min-z corner (top-left in grid space).
@export var dimensions: Vector2i = Vector2i(1, 1)

## Determines whether a structure can be placed on uneven terrain
@export var allow_uneven: bool = false
#endregion

#region Checks
## True iff every cell of the structure's footprint is in-bounds, unoccupied,
## and (when a_allow_uneven_terrain is false) perfectly flat. The clicked world
## position is treated as the footprint centre, matching how Map.add_structure
## places the building. Lives on Entity (not Commandable) so any grid-occupying
## entity — including non-commandable structures like Deposit — can be placed.
static func valid_placement(
	a_command_message: CommandMessage,
	a_dimensions: Vector2i,
	a_allow_uneven_terrain: bool = false
) -> bool:
	var placement_map: Map = a_command_message.map
	if placement_map == null:
		return false
	# Use the same footprint resolution as add_structure so the preview matches where
	# the structure actually lands (parity-correct for even-sized footprints).
	var origin: Vector2i = placement_map.footprint_origin(a_command_message.xz_position, a_dimensions)
	for w in range(a_dimensions.x):
		for l in range(a_dimensions.y):
			var cell := Vector2i(origin.x + w, origin.y + l)
			if not placement_map.grid_coordinates_in_bounds(cell):
				return false
			if placement_map.cell_grid[cell.x][cell.y] != null:
				return false
			if not a_allow_uneven_terrain and not placement_map.terrain_grid.is_flat(cell):
				return false
	return true
#endregion
