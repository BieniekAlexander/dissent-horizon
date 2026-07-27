@tool
class_name Structure
extends Node

## Makes its parent Entity a FIXTURE — a piece that claims terrain-grid cells — while it is
## active, and declares the footprint it claims. "Is this a fixture now" is
## Entity.structure_is_active(), which reads `is_active`; presence alone only says the piece
## CAN stand as one. See gdd/systems/authoring/piece-vocabulary.md.

#region Properties
## How many grid cells this entity blocks in each axis (width × depth).
## Footprint origin is the min-x/min-z corner (top-left in grid space).
@export var dimensions: Vector2i = Vector2i(1, 1)

## Determines whether a structure can be placed on uneven terrain
@export var allow_uneven: bool = false

## Whether this structure may stand in SHALLOW water — ground submerged by a WaterBody, but
## by no more than WaterBasin.WADE_DEPTH. It sits on the solid terrain underneath and is
## partly submerged; the water has no physics to interact with.
##
## THIS FLAG IS THE WHOLE "what may be built in water" RULE, and it is a flag rather than a
## list of piece ids on purpose: today only the extractor sets it — a lithium pond is worked
## the same way an extraction site is — and admitting a second piece is one checkbox in that
## piece's scene, not an edit here.
##
## It never grants DEEP water. Water past wading depth is impassable ground, and impassable
## ground holds nothing.
@export var allow_submerged: bool = false

## Whether the footprint's cells leave the navmesh while registered. False makes an
## OCCUPANT-only fixture: nothing else may be placed on its cells, and units walk across them.
## The extraction site is the case that needs it. See piece-vocabulary.md §Obstruction.
@export var is_obstruction: bool = true

## Whether the footprint is LIVE — the entity is a fixture now. Not exported: which form a
## piece stands in is decided by what spawned it, never by its scene or doc
## (gdd/systems/authoring/composition-rework.md §Which form a piece spawns in). Always true
## for a piece with no Movement; a transformer's is switched by Entity.set_deployed.
var is_active: bool = true
#endregion

#region Checks
## True iff every cell of the structure's footprint is in-bounds, unoccupied,
## and (when a_allow_uneven_terrain is false) perfectly flat. The clicked world
## position is treated as the footprint centre, matching how Map.add_structure
## places the building. Lives on Entity (not Commandable) so any grid-occupying
## entity — including non-commandable structures like ExtractionSite — can be placed.
static func valid_placement(
	command_message: CommandMessage,
	dimensions: Vector2i,
	allow_uneven_terrain: bool = false,
	allow_submerged_terrain: bool = false
) -> bool:
	var placement_map: Map = command_message.map
	if placement_map == null:
		return false
	# Use the same footprint resolution as add_structure so the preview matches where
	# the structure actually lands (parity-correct for even-sized footprints).
	var origin: Vector2i = placement_map.footprint_origin(command_message.xz_position, dimensions)
	for w in range(dimensions.x):
		for l in range(dimensions.y):
			if not cell_admits_structure(placement_map, Vector2i(origin.x + w, origin.y + l),
					allow_uneven_terrain, allow_submerged_terrain):
				return false
	return true


## Whether ONE cell could hold part of a structure: in bounds, unoccupied, flat unless uneven
## ground is allowed, and dry or shallow as the piece permits. valid_placement asks it of every
## footprint cell; the build preview asks it per cell to colour the grid.
static func cell_admits_structure(
	a_map: Map,
	a_cell: Vector2i,
	a_allow_uneven: bool = false,
	a_allow_submerged: bool = false
) -> bool:
	if not a_map.grid_coordinates_in_bounds(a_cell):
		return false
	if a_map.cell_grid[a_cell.x][a_cell.y] != null:
		return false
	if not a_allow_uneven and not a_map.terrain_grid.is_flat(a_cell):
		return false
	return cell_admits_submersion(a_map, a_cell, a_allow_submerged)


## Whether one cell's WATER state permits a structure. Dry ground always does; shallow water
## does only for a piece that declares allow_submerged; deep water never does, since it is
## impassable ground. Split out because the build preview, the placement check and the bot's
## site search all have to answer it the same way.
static func cell_admits_submersion(
	a_map: Map,
	a_cell: Vector2i,
	a_allow_submerged: bool
) -> bool:
	var body: WaterBody = a_map.water_body_at(a_cell)
	if body == null:
		return true
	return a_allow_submerged and body.is_shallow(a_cell)
#endregion
