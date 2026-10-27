@tool
class_name MapImagePassability
extends RefCounted

## What a round trip through a drawing changed about where a unit can walk (map-from-image.md
## §Exporting a map to a drawing). An export loses detail on purpose — slopes, sculpted banks,
## the exact shape of a cliff band — and most of it moves the edge of walkable ground by a cell or
## two, which changes nothing about the map. What matters is TOPOLOGY: ground the map kept apart
## that the re-import joins, and ground it joined that the re-import splits. Those are reported,
## each at the patch of cells that made the difference, for the author to fix in the drawing.
##
## Walkable is the game's own test, read off the terrain alone: in play, no steeper than
## TerrainGrid.MAX_SLOPE_DIFF, and not deeper than WaterBasin.WADE_DEPTH under any water body.

#region Constants
## A region of walkable ground smaller than this, in cells, is a sliver — a cell or two trapped
## by a cliff's ragged edge — and joining or cutting one off is noise, not a change to the map.
## The generator leaves pockets this small unreachable for the same reason.
const MIN_REGION_CELLS: int = 25
## Patches named in the report; the rest are counted.
const MAX_LISTED: int = 8
## The readout's colours: what stayed walkable and what stayed blocked recede, an edge that only
## moved is a pale tint, and a passage opened or closed stands out.
const WALKABLE_COLOR := Color8(199, 204, 189)
const BLOCKED_COLOR := Color8(51, 51, 61)
const EDGE_OPENED_COLOR := Color8(242, 179, 179)
const EDGE_CLOSED_COLOR := Color8(153, 179, 242)
const PASSAGE_OPENED_COLOR := Color8(230, 26, 26)
const PASSAGE_CLOSED_COLOR := Color8(26, 77, 255)
const _FOUR_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
#endregion


## 1 per walkable cell of `terrain`, over its square grid, with `waters` as {seed_cell, level}.
static func walkable(terrain: TerrainData, waters: Array[Dictionary]) -> PackedByteArray:
	var side: int = terrain.grid_width()
	var deep: Dictionary = {}
	for water: Dictionary in waters:
		var basin: WaterBasin = WaterBasin.fill(terrain, water.seed_cell, water.level)
		for cell: Vector2i in basin.deep_cells():
			deep[cell] = true
	var out := PackedByteArray()
	out.resize(side * side)
	for z: int in side:
		for x: int in side:
			var cell := Vector2i(x, z)
			out[z * side + x] = (
				1
				if (
					terrain.is_cell_in_play(cell)
					and terrain.cell_height_spread(cell) <= TerrainGrid.MAX_SLOPE_DIFF
					and not deep.has(cell)
				)
				else 0
			)
	return out


## Every water body an imported map writes — uncharged water and ponds — as {seed_cell, level}.
static func waters_of(map: GeneratedMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for water: Dictionary in map.waters:
		out.append({seed_cell = water.seed_cell, level = water.level})
	for feature: MapFeature in map.features:
		if feature.kind == MapFeature.Kind.POND:
			out.append({seed_cell = feature.pond_seed_cell, level = feature.pond_level})
	return out


## The report lines: each passage the re-import opened between ground the map kept apart, and
## each it closed between ground the map joined. Empty when the topology survived.
static func changes(
	before: PackedByteArray, after: PackedByteArray, side: int
) -> PackedStringArray:
	return compare(before, after, side).lines


## The comparison: {lines: PackedStringArray, opened: Array[Vector2i], closed: Array[Vector2i]},
## `opened` and `closed` being the cells of every passage reported.
static func compare(before: PackedByteArray, after: PackedByteArray, side: int) -> Dictionary:
	var lines := PackedStringArray()
	var opened: Array[Vector2i] = []
	var closed: Array[Vector2i] = []
	for bridge: Dictionary in _bridges(before, after, side):
		opened.append_array(bridge.pixels)
		lines.append(
			(
				"PASSAGE OPENED: %d cells now walkable at %s join ground the map kept apart"
				% [bridge.cells, _describe(bridge.pixels)]
			)
		)
	for bridge: Dictionary in _bridges(after, before, side):
		closed.append_array(bridge.pixels)
		lines.append(
			(
				"PASSAGE CLOSED: %d cells no longer walkable at %s split ground the map joined"
				% [bridge.cells, _describe(bridge.pixels)]
			)
		)
	if lines.size() > MAX_LISTED:
		var more: int = lines.size() - MAX_LISTED
		lines = lines.slice(0, MAX_LISTED)
		lines.append("… and %d more passage changes" % more)
	return {lines = lines, opened = opened, closed = closed}


## A top-down picture of the comparison, a pixel per cell: ground walkable in both, the cells
## that only moved an edge, and the passages reported, in colours of their own.
static func readout(
	before: PackedByteArray,
	after: PackedByteArray,
	side: int,
	opened: Array[Vector2i],
	closed: Array[Vector2i]
) -> Image:
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for at: int in before.size():
		var color: Color = BLOCKED_COLOR
		if before[at] == 1 and after[at] == 1:
			color = WALKABLE_COLOR
		elif after[at] == 1:
			color = EDGE_OPENED_COLOR
		elif before[at] == 1:
			color = EDGE_CLOSED_COLOR
		image.set_pixel(at % side, at / side, color)
	for cell: Vector2i in opened:
		image.set_pixelv(cell, PASSAGE_OPENED_COLOR)
	for cell: Vector2i in closed:
		image.set_pixelv(cell, PASSAGE_CLOSED_COLOR)
	return image


## Patches of ground walkable in `a_to` but not in `a_from` that each touch two or more of
## `a_from`'s regions: a patch like that is a passage `a_from` did not have. Measured patch by
## patch, so it names where the passage is, not just that two regions met.
static func _bridges(
	a_from: PackedByteArray, a_to: PackedByteArray, a_side: int
) -> Array[Dictionary]:
	var region: PackedInt32Array = _regions(a_from, a_side)
	var seen := PackedByteArray()
	seen.resize(a_from.size())
	var out: Array[Dictionary] = []
	for start: int in a_from.size():
		if seen[start] == 1 or a_to[start] == 0 or a_from[start] == 1:
			continue
		var patch: Array[Vector2i] = []
		var touched: Dictionary = {}
		var frontier: Array[int] = [start]
		seen[start] = 1
		while not frontier.is_empty():
			var at: int = frontier.pop_back()
			var cell := Vector2i(at % a_side, at / a_side)
			patch.append(cell)
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + step
				if near.x < 0 or near.y < 0 or near.x >= a_side or near.y >= a_side:
					continue
				var near_at: int = near.y * a_side + near.x
				if region[near_at] >= 0:
					touched[region[near_at]] = true
				elif seen[near_at] == 0 and a_to[near_at] == 1 and a_from[near_at] == 0:
					seen[near_at] = 1
					frontier.append(near_at)
		if touched.size() >= 2:
			out.append({cells = patch.size(), pixels = patch})
	return out


## Each walkable cell's region index, -1 for a cell that is not walkable or lies in a sliver
## under MIN_REGION_CELLS.
static func _regions(a_walkable: PackedByteArray, a_side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(a_walkable.size())
	out.fill(-1)
	var next: int = 0
	for start: int in a_walkable.size():
		if a_walkable[start] == 0 or out[start] != -1:
			continue
		var members: Array[int] = [start]
		out[start] = next
		var k: int = 0
		while k < members.size():
			var at: int = members[k]
			k += 1
			var cell := Vector2i(at % a_side, at / a_side)
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + step
				if near.x < 0 or near.y < 0 or near.x >= a_side or near.y >= a_side:
					continue
				var near_at: int = near.y * a_side + near.x
				if a_walkable[near_at] == 1 and out[near_at] == -1:
					out[near_at] = next
					members.append(near_at)
		if members.size() < MIN_REGION_CELLS:
			# Marked out of every region, but kept off -1's "unvisited" by a value no region has.
			for at: int in members:
				out[at] = -2
		else:
			next += 1
	for at: int in out.size():
		if out[at] == -2:
			out[at] = -1
	return out


## The patch by its bounding box, in drawing pixels (pixel = cell on an export's canvas).
static func _describe(a_pixels: Array[Vector2i]) -> String:
	var box := Rect2i(a_pixels[0], Vector2i.ZERO)
	for pixel: Vector2i in a_pixels:
		box = box.expand(pixel)
	return (
		"px (%d, %d)" % [box.position.x, box.position.y]
		if box.size == Vector2i.ZERO
		else "px (%d, %d) to (%d, %d)" % [box.position.x, box.position.y, box.end.x, box.end.y]
	)
