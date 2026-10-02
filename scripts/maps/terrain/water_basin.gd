class_name WaterBasin
extends RefCounted

## The contiguous flooded region one water level carves out of a terrain surface.
##
## PURE: takes a TerrainData and returns cells and depths. No Map, no scene tree, no
## engine — so the rule that decides which ground a lake covers, and how deep, can be
## exercised headlessly. WaterBody is the scene-side object that owns a basin, draws it
## and publishes its deep cells to the terrain grid.
##
## WATER IS A HEIGHT AND A PLANE, not a kind of ground: a body of water is a depression in
## the terrain plus a level, and passability falls out of how far the ground sits under that
## level rather than out of anything painted on the cell. See
## gdd/systems/terrain-and-navigation/water-bodies.md.

#region Constants
## How deep a cell may be submerged and still be walked through. Deeper than this and the
## cell is impassable — the chasm a lake is. One project-wide number: every water body
## shares it, and only the LEVEL is per-body.
const WADE_DEPTH: float = 0.5

## 4-connected, matching how the navmesh stitches adjacent cells and how TerrainGrid labels
## its passable components. Water that only meets at a corner is two bodies.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
#endregion

#region Properties
## Cell -> submersion depth in world units (level minus the cell's mean corner height).
## The seed cell is present at whatever depth it has, INCLUDING zero or less — see fill().
var depth_by_cell: Dictionary = {}

## The water surface height every cell in this basin is measured against.
var level: float = 0.0

## The deepest the water gets, in world units. A pond far shallower than the terrain's own
## step relief is drawn but cannot be SEEN from the game's oblique camera — the steps around
## it hide the plane completely — so this is the number that says whether a body will read.
var max_depth: float = 0.0

## Covered cells with a corner at or above the water level: the terrain breaks the surface
## there. Counted per CORNER rather than per cell mean, because a corner is what pokes through
## and occludes the flat water plane from a low viewing angle.
var cells_pierced_by_terrain: int = 0

## True when the fill ran out of terrain rather than out of water: some cell of the basin
## touches the play-area boundary. Not a failure — the edge of the map holds water like a
## wall does — but it is what separates an enclosed pond from a flooded lowland, and the
## authoring tool says which one the author is about to make.
var reaches_play_edge: bool = false
#endregion


#region Construction
## Flood `a_terrain` from `a_seed_cell` at water level `a_level`.
##
## The fill spreads to every 4-connected in-play cell whose mean corner height is BELOW the
## level, and stops at cells that are not — dry ground and the play-area boundary are the
## same kind of wall. The SEED cell is admitted unconditionally (when it is in play at all),
## because the level an author picks is the height of the point they are pointing at: the
## cell under the cursor is submerged by approximately zero and would otherwise refuse to
## start its own fill. is_valid() is what rejects a click that floods nothing.
static func fill(a_terrain: TerrainData, a_seed_cell: Vector2i, a_level: float) -> WaterBasin:
	var basin := WaterBasin.new()
	basin.level = a_level
	if (
		a_terrain == null
		or not a_terrain.is_cell_in_bounds(a_seed_cell)
		or not a_terrain.is_cell_in_play(a_seed_cell)
	):
		return basin

	var stack: Array[Vector2i] = [a_seed_cell]
	basin.depth_by_cell[a_seed_cell] = a_level - a_terrain.cell_mean_height(a_seed_cell)
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for step: Vector2i in _NEIGHBOURS:
			var neighbour: Vector2i = cell + step
			if basin.depth_by_cell.has(neighbour):
				continue
			if (
				not a_terrain.is_cell_in_bounds(neighbour)
				or not a_terrain.is_cell_in_play(neighbour)
			):
				basin.reaches_play_edge = true
				continue
			var depth: float = a_level - a_terrain.cell_mean_height(neighbour)
			if depth <= 0.0:
				continue
			basin.depth_by_cell[neighbour] = depth
			stack.append(neighbour)
	basin._measure_relief(a_terrain)
	return basin


## Fill in max_depth and cells_pierced_by_terrain once the cell set is final. Separate from the
## flood so the flood stays a plain reachability walk.
func _measure_relief(a_terrain: TerrainData) -> void:
	for cell: Vector2i in depth_by_cell:
		var depth: float = depth_by_cell[cell]
		if depth <= 0.0:
			continue
		max_depth = maxf(max_depth, depth)
		for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			if a_terrain.corner_height(cell + step) >= level:
				cells_pierced_by_terrain += 1
				break


#endregion


#region Queries
## Whether this basin holds water at all. A click on a hilltop, on the floor of a bowl, or
## anywhere the chosen level does not actually cover ground floods nothing, and that is the
## one thing the authoring tool refuses.
func is_valid() -> bool:
	for cell: Vector2i in depth_by_cell:
		if depth_by_cell[cell] > 0.0:
			return true
	return false


## Submersion depth at a cell, or 0.0 for a cell this basin does not cover. Never negative:
## the seed cell's own above-water reading is reported as dry rather than as a negative depth,
## so callers can treat the number as "how much water is here" without a sign check.
func depth_at(a_cell: Vector2i) -> float:
	return maxf(0.0, depth_by_cell.get(a_cell, 0.0))


## Whether the water covers this cell at any depth.
func covers_cell(a_cell: Vector2i) -> bool:
	return depth_at(a_cell) > 0.0


## Whether a cell is submerged past wading depth — the cells that leave the navmesh.
func is_deep(a_cell: Vector2i) -> bool:
	return depth_at(a_cell) > WADE_DEPTH


## Whether a cell is under water a unit can walk through: submerged, but not past WADE_DEPTH.
func is_shallow(a_cell: Vector2i) -> bool:
	var depth: float = depth_at(a_cell)
	return depth > 0.0 and depth <= WADE_DEPTH


## Every cell the water covers, deep and shallow alike. Dry seed cells are excluded, so this
## is the basin's drawn and gameplay footprint rather than the raw fill.
func covered_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in depth_by_cell:
		if depth_by_cell[cell] > 0.0:
			result.append(cell)
	return result


## The cells this basin takes out of the navmesh.
func deep_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in depth_by_cell:
		if depth_by_cell[cell] > WADE_DEPTH:
			result.append(cell)
	return result
#endregion
