@tool
class_name MapImageWater
extends RefCounted

## The water layer read into bodies (map-from-image.md §Water): each 4-connected patch of deep
## and shallow water is one uncharged WaterBody, each patch of lithium one charged pond — 4-
## connected because that is how a basin floods, so an arm joined only across a corner would
## take no water from the other's seed.
##
## Two halves around the height pass. `plan` reads the patches, sets each body's level — its
## lowest DRAWN bank's level height minus WATER_OFFSET, the one rule that never floods past a
## bank — and the beds the relief must dig below it; `finish`, once the heights are final, seeds
## each body at its lowest cell and keeps it if the game's own fill finds water there.
##
## The level is read from the drawing, not from the smoothed terrain, and the beds are measured
## down from it: smoothed banks beside a deep bed sag, and a level read off them once left every
## shallow ford beside a deep lake above the water.

#region Enums
enum Kind { WATER, POND }
#endregion

#region Constants
## How far a body's surface stands below its lowest bank.
const WATER_OFFSET: float = 0.1
## Water depth over a bed, below the body's level: deep well past wading depth, shallow within
## it. The relief holds beds out of the smoothing, so these are the depths a cell away from shore.
const DEEP_DEPTH: float = WaterBasin.WADE_DEPTH * 2.5
const SHALLOW_DEPTH: float = WaterBasin.WADE_DEPTH * 0.5
## A pond's pan, as the generator sinks one — just under a slope step below its bank, so its rim
## is walkable — less the offset its level stands below that bank.
const POND_DEPTH: float = FeaturePlacer.POND_SINK - WATER_OFFSET
const _FOUR_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
#endregion

#region Properties
## One per patch: {cells: Array[Vector2i], kind: Kind, richness: int (0 poor … 2 rich, ponds
## only), banks: Array[Vector2i], base_level: int, level: float (set by plan), is_waterfall: bool}.
var bodies: Array[Dictionary] = []
## Cell index -> the bed's target height, for every water cell of a body that is not a
## waterfall. The relief digs these.
var beds: Dictionary = {}
## Cell index -> its body's water level, over the same cells: the relief keeps the shore below it.
var surfaces: Dictionary = {}
## Uncharged bodies to write: {seed_cell, level}, as GeneratedMap.waters holds them.
var waters: Array[Dictionary] = []
var ponds: Array[MapFeature] = []
## Cell -> submersion depth, over every body written.
var depth_by_cell: Dictionary = {}
## What the report lists: waterfalls skipped, bodies that hold no water, painted water left dry.
var notes: PackedStringArray = PackedStringArray()
#endregion


static func plan(cells: MapImageCells, params: MapImageImportParams) -> MapImageWater:
	var out := MapImageWater.new()
	var seen := PackedByteArray()
	seen.resize(cells.cell_count())
	for i: int in cells.cell_count():
		if seen[i] == 1 or cells.water[i] == MapImagePalette.Meaning.NONE:
			continue
		var kind: Kind = _kind_of(cells.water[i])
		var patch: Array[Vector2i] = _patch(cells, cells.cell_of(i), kind, seen)
		var body: Dictionary = out._read_body(cells, patch, kind)
		if body.is_empty():
			continue
		out.bodies.append(body)
		if body.is_waterfall:
			continue
		body.level = params.level_height(body.base_level) - WATER_OFFSET
		for cell: Vector2i in patch:
			var index: int = cells.index_of(cell)
			out.beds[index] = body.level - _depth(cells.water[index])
			out.surfaces[index] = body.level
	return out


## Seed each body in the finished `terrain`, and keep it only when the game's own fill finds
## water there.
func finish(cells: MapImageCells, terrain: TerrainData, params: MapImageImportParams) -> void:
	for body: Dictionary in bodies:
		var at: Vector2i = cells.pixel_of(body.cells[0])
		if body.is_waterfall:
			(
				notes
				. append(
					(
						"waterfall at px (%d, %d): water drawn across terrain levels %s is built as dry ground"
						% [at.x, at.y, body.under_levels]
					)
				)
			)
			continue
		var level: float = body.level
		var seed: Vector2i = body.cells[0]
		for cell: Vector2i in body.cells:
			if terrain.cell_mean_height(cell) < terrain.cell_mean_height(seed):
				seed = cell
		var basin: WaterBasin = WaterBasin.fill(terrain, seed, level)
		if not basin.is_valid():
			notes.append(
				(
					"%s at px (%d, %d) holds no water once smoothed (%d cells); it is left out"
					% [_title(body), at.x, at.y, body.cells.size()]
				)
			)
			continue
		_note_depths(cells, body, basin, at)
		for cell: Vector2i in basin.depth_by_cell:
			if basin.depth_by_cell[cell] > 0.0:
				depth_by_cell[cell] = basin.depth_by_cell[cell]
		if body.kind == Kind.WATER:
			waters.append({seed_cell = seed, level = level})
			continue
		ponds.append(_pond(body, basin, seed, level, params))


func _read_body(a_cells: MapImageCells, a_patch: Array[Vector2i], a_kind: Kind) -> Dictionary:
	var shades: Dictionary = {}
	var under: Dictionary = {}
	for cell: Vector2i in a_patch:
		shades[a_cells.water[a_cells.index_of(cell)]] = true
		under[a_cells.level_at(cell)] = true
	if a_kind == Kind.POND and shades.size() > 1:
		var pixels: Array[Vector2i] = []
		pixels.assign(a_patch.map(func(cell: Vector2i) -> Vector2i: return a_cells.pixel_of(cell)))
		a_cells.add_error(
			(
				"water: a lithium pond is drawn in more than one richness; a pond has one: %s"
				% MapImageCells.describe_pixels(pixels)
			),
			pixels
		)
		return {}
	var banks: Array[Vector2i] = []
	var bank_level: int = 0
	var in_patch: Dictionary = {}
	for cell: Vector2i in a_patch:
		in_patch[cell] = true
	for cell: Vector2i in a_patch:
		for step: Vector2i in _FOUR_NEIGHBOURS:
			var near: Vector2i = cell + step
			if in_patch.has(near) or not a_cells.is_in_play(near):
				continue
			var near_level: int = a_cells.level_at(near)
			if near_level == 0 or a_cells.water[a_cells.index_of(near)] != 0:
				continue
			if not banks.has(near):
				banks.append(near)
			bank_level = near_level if bank_level == 0 else mini(bank_level, near_level)
	var under_levels: Array = under.keys()
	under_levels.sort()
	return {
		cells = a_patch,
		kind = a_kind,
		richness =
		int(shades.keys()[0]) - MapImagePalette.Meaning.LITHIUM_POOR if a_kind == Kind.POND else 0,
		banks = banks,
		base_level = bank_level if bank_level > 0 else under_levels[0],
		under_levels = under_levels,
		is_waterfall = under_levels.size() > 1,
	}


## Report where the water came out other than drawn: deep water a unit could wade, shallow water
## too deep to, or drawn water the terrain left dry.
func _note_depths(
	a_cells: MapImageCells, a_body: Dictionary, a_basin: WaterBasin, a_at: Vector2i
) -> void:
	var dry: int = 0
	var wadeable_deep: int = 0
	var deep_shallow: int = 0
	for cell: Vector2i in a_body.cells:
		var depth: float = a_basin.depth_by_cell.get(cell, 0.0)
		var meaning: int = a_cells.water[a_cells.index_of(cell)]
		if depth <= 0.0:
			dry += 1
		elif meaning == MapImagePalette.Meaning.DEEP and depth <= WaterBasin.WADE_DEPTH:
			wadeable_deep += 1
		elif meaning == MapImagePalette.Meaning.SHALLOW and depth > WaterBasin.WADE_DEPTH:
			deep_shallow += 1
	var parts: PackedStringArray = PackedStringArray()
	if dry > 0:
		parts.append("%d drawn cells left dry" % dry)
	if wadeable_deep > 0:
		parts.append("%d deep cells shallow enough to wade" % wadeable_deep)
	if deep_shallow > 0:
		parts.append("%d shallow cells too deep to wade" % deep_shallow)
	if not parts.is_empty():
		notes.append("%s at px (%d, %d): %s" % [_title(a_body), a_at.x, a_at.y, ", ".join(parts)])


## A pond's charge is its drawn size times its richness, capped as the generator caps one
## (map-generation.md §3).
func _pond(
	a_body: Dictionary,
	a_basin: WaterBasin,
	a_seed: Vector2i,
	a_level: float,
	a_params: MapImageImportParams
) -> MapFeature:
	var feature := MapFeature.new()
	feature.kind = MapFeature.Kind.POND
	var generation: MapGenerationParams = a_params.generation
	feature.pond_richness = generation.pond_richness_factors[a_body.richness]
	feature.pond_charge = mini(
		a_body.cells.size() * feature.pond_richness, generation.pond_charge_max
	)
	feature.pond_seed_cell = a_seed
	feature.pond_level = a_level
	var centre := Vector2.ZERO
	for cell: Vector2i in a_basin.depth_by_cell:
		feature.pond_cells.append(cell)
		centre += Vector2(cell) + Vector2.ONE * 0.5
	feature.center = centre / maxf(feature.pond_cells.size(), 1.0)
	feature.value = feature.pond_charge
	return feature


static func _title(body: Dictionary) -> String:
	return "a lithium pond" if body.kind == Kind.POND else "water"


static func _kind_of(meaning: int) -> Kind:
	return (
		Kind.WATER
		if meaning == MapImagePalette.Meaning.DEEP or meaning == MapImagePalette.Meaning.SHALLOW
		else Kind.POND
	)


static func _depth(meaning: int) -> float:
	match meaning:
		MapImagePalette.Meaning.DEEP:
			return DEEP_DEPTH
		MapImagePalette.Meaning.SHALLOW:
			return SHALLOW_DEPTH
	return POND_DEPTH


static func _patch(
	cells: MapImageCells, start: Vector2i, kind: Kind, seen: PackedByteArray
) -> Array[Vector2i]:
	var patch: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [start]
	seen[cells.index_of(start)] = 1
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		patch.append(cell)
		for step: Vector2i in _FOUR_NEIGHBOURS:
			var near: Vector2i = cell + step
			if not cells.has_cell(near):
				continue
			var index: int = cells.index_of(near)
			var meaning: int = cells.water[index]
			if seen[index] == 0 and meaning != MapImagePalette.Meaning.NONE:
				if _kind_of(meaning) == kind:
					seen[index] = 1
					frontier.append(near)
	return patch
