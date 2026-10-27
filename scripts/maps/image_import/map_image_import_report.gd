@tool
class_name MapImageImportReport
extends RefCounted

## What an image import tells its author (map-from-image.md §The report): a summary, what
## failed or was flagged, and a top-down readout of the cell grid — levels, steep cells, deep
## and shallow water, ponds, structures, and every pixel an error or flag is about.

#region Constants
## A smoothed cell within this share of a step of its level's height still stands on it.
const EATEN_SHARE_OF_STEP: float = 0.5
const _MAX_LISTED: int = 8
const _FOUR_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
## The readout's colours. Levels shade from dark to light by height.
const OUT_COLOR := Color(0.1, 0.1, 0.12)
const LEVEL_DARK := Color(0.25, 0.3, 0.2)
const LEVEL_LIGHT := Color(0.85, 0.85, 0.7)
const STEEP_COLOR := Color(0.55, 0.3, 0.25)
const DEEP_COLOR := Color(0.12, 0.2, 0.55)
const SHALLOW_COLOR := Color(0.4, 0.65, 0.85)
const POND_COLOR := Color(0.85, 0.55, 0.2)
const SHELTER_COLOR := Color(1.0, 0.0, 1.0)
const BUILDING_COLOR := Color(1.0, 1.0, 1.0)
const START_COLOR := Color(0.0, 0.63, 1.0)
const FLAG_COLOR := Color(1.0, 0.85, 0.0)
#endregion


## The listed, non-failing findings: features smoothing ate and walkable ground cut off.
static func listings(result: MapImageImporter, params: MapImageImportParams) -> PackedStringArray:
	var terrain := TerrainData.new()
	terrain.play_size = result.cells.play_size
	terrain.heights = result.relief.heights
	var out := PackedStringArray()
	out.append_array(_eaten(result, terrain, params))
	out.append_array(_unreachable(result, terrain))
	return out


## The report's text, for the dock.
static func lines(result: MapImageImporter, title: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not result.is_valid():
		out.append("## %s — import FAILED; nothing in the Scenario was changed" % title)
		out.append("")
		# An error with pixels is numbered, and named by the colour its pixels are marked in on the
		# drawing's marked copy (MapImageIssues).
		var marked: Dictionary = {}
		var issues: Array[Dictionary] = MapImageIssues.of(result)
		for i: int in issues.size():
			marked[issues[i].message] = i
		for error: String in result.errors:
			out.append(
				(
					"- FAILED %s" % MapImageIssues.line(marked[error], error)
					if marked.has(error)
					else "- FAILED: %s" % error
				)
			)
		return out
	var map: GeneratedMap = result.map
	var steep: int = 0
	for cell: int in map.terrain.grid_width() * map.terrain.grid_depth():
		var at := Vector2i(cell % map.terrain.grid_width(), cell / map.terrain.grid_width())
		if (
			map.terrain.is_cell_in_play(at)
			and map.terrain.cell_height_spread(at) > TerrainGrid.MAX_SLOPE_DIFF
		):
			steep += 1
	var cliffs: int = 0
	var ramps: int = 0
	for region: Dictionary in result.relief.regions:
		if region.kind == MapImagePalette.Meaning.CLIFF:
			cliffs += 1
		else:
			ramps += 1
	out.append(
		"## %s — play size %s, %d cells in play" % [title, map.play_size, map.play_cell_count]
	)
	out.append("")
	out.append(
		(
			"%d steep cells; %d cliffs, %d ramps; %d water bodies, %d lithium ponds (charges %s)"
			% [
				steep,
				cliffs,
				ramps,
				map.waters.size(),
				map.features_of(MapFeature.Kind.POND).size(),
				map.features_of(MapFeature.Kind.POND).map(
					func(f: MapFeature) -> int: return f.pond_charge
				),
			]
		)
	)
	(
		out
		. append(
			(
				"%d shelters, %d buildings, %d start points"
				% [
					map.features_of(MapFeature.Kind.SHELTER).size(),
					map.features_of(MapFeature.Kind.BUILDING_CLUSTER).size(),
					map.starts.size(),
				]
			)
		)
	)
	if not result.notes.is_empty():
		out.append("")
		for note: String in result.notes:
			out.append("- %s" % note)
	return out


## The top-down readout, one pixel per cell in the drawing's own frame. `flagged` adds cells
## the shell flagged (hand-placed pieces the new terrain breaks).
static func readout(
	result: MapImageImporter, params: MapImageImportParams, flagged: Array[Vector2i] = []
) -> Image:
	var cells: MapImageCells = result.cells
	if cells == null:
		return null
	if cells.side == 0:
		return _drawing_readout(result)
	var image := Image.create_empty(cells.side, cells.side, false, Image.FORMAT_RGBA8)
	var terrain: TerrainData = null
	if result.relief != null:
		terrain = TerrainData.new()
		terrain.play_size = cells.play_size
		terrain.heights = result.relief.heights
	var low: float = params.level_height(1)
	var high: float = params.level_height(MapImagePalette.LEVEL_COUNT)
	for i: int in cells.cell_count():
		var cell: Vector2i = cells.cell_of(i)
		var color: Color = OUT_COLOR
		if cells.in_play[i] == 1:
			var height: float = params.level_height(maxi(cells.level_at(cell), 1))
			if terrain != null:
				height = terrain.cell_mean_height(cell)
			color = LEVEL_DARK.lerp(LEVEL_LIGHT, clampf((height - low) / (high - low), 0.0, 1.0))
			if terrain != null and terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF:
				color = STEEP_COLOR
			color = _water_color(result, cell, color)
			color = _structure_color(cells.structures[i], color)
		image.set_pixelv(cell, color)
	# Each issue in the colour the report and the marked copy name it by.
	var issues: Array[Dictionary] = MapImageIssues.of(result)
	for i: int in issues.size():
		for pixel: Vector2i in issues[i].pixels:
			_mark(
				image, pixel - cells.offset, MapImageIssues.COLORS[i % MapImageIssues.COLORS.size()]
			)
	for cell: Vector2i in flagged:
		_mark(image, cell, FLAG_COLOR)
	return image


## The readout of a drawing refused before it was fitted to the grid: its terrain layer as drawn,
## the other layers over it, and each issue's pixels in its colour, one pixel a drawing pixel.
static func _drawing_readout(result: MapImageImporter) -> Image:
	var layers: MapImageLayers = result.layers
	if layers == null or not layers.images.has(MapImagePalette.Layer.TERRAIN):
		return null
	var image: Image = (layers.images[MapImagePalette.Layer.TERRAIN] as Image).duplicate()
	for layer: int in [
		MapImagePalette.Layer.WATER, MapImagePalette.Layer.CLIFFS, MapImagePalette.Layer.STRUCTURES
	]:
		if layers.images.has(layer):
			image.blend_rect(
				layers.images[layer], Rect2i(Vector2i.ZERO, layers.size), Vector2i.ZERO
			)
	var issues: Array[Dictionary] = MapImageIssues.of(result)
	for i: int in issues.size():
		for pixel: Vector2i in issues[i].pixels:
			_mark(image, pixel, MapImageIssues.COLORS[i % MapImageIssues.COLORS.size()])
	return image


static func _water_color(result: MapImageImporter, cell: Vector2i, ground: Color) -> Color:
	if result.water == null or not result.water.depth_by_cell.has(cell):
		return ground
	var meaning: int = result.cells.water[result.cells.index_of(cell)]
	if meaning >= MapImagePalette.Meaning.LITHIUM_POOR:
		return POND_COLOR
	return DEEP_COLOR if result.water.depth_by_cell[cell] > WaterBasin.WADE_DEPTH else SHALLOW_COLOR


static func _structure_color(meaning: int, ground: Color) -> Color:
	match meaning:
		MapImagePalette.Meaning.SHELTER:
			return SHELTER_COLOR
		MapImagePalette.Meaning.BUILDING:
			return BUILDING_COLOR
		MapImagePalette.Meaning.START:
			return START_COLOR
	return ground


static func _mark(image: Image, cell: Vector2i, color: Color) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < image.get_width() and cell.y < image.get_height():
		image.set_pixelv(cell, color)


## Level features smoothing ate: patches of ground drawn at one level, none of whose cells came
## within half a step of that level's height once smoothed — a feature narrower than the blur.
static func _eaten(
	result: MapImageImporter, terrain: TerrainData, params: MapImageImportParams
) -> PackedStringArray:
	var cells: MapImageCells = result.cells
	var tolerance: float = params.level_step * EATEN_SHARE_OF_STEP
	var levels := PackedByteArray()
	levels.resize(cells.cell_count())
	for i: int in cells.cell_count():
		var is_ground: bool = (
			cells.in_play[i] == 1
			and not result.water.beds.has(i)
			and cells.cliffs[i] == MapImagePalette.Meaning.NONE
		)
		levels[i] = cells.level_at(cells.cell_of(i)) if is_ground else 0
	var eaten: Array = []
	for patch: Array in _patches(cells, levels):
		var level: int = levels[cells.index_of(patch[0])]
		var is_kept: bool = patch.any(
			func(cell: Vector2i) -> bool:
				return (
					absf(terrain.cell_mean_height(cell) - params.level_height(level)) <= tolerance
				)
		)
		if not is_kept:
			eaten.append(patch)
	var out := PackedStringArray()
	for patch: Array in eaten.slice(0, _MAX_LISTED):
		var at: Vector2i = cells.pixel_of(patch[0])
		var level: int = levels[cells.index_of(patch[0])]
		out.append(
			(
				"smoothing ate a level-%d feature at px (%d, %d), %d cells: none kept its height"
				% [level, at.x, at.y, patch.size()]
			)
		)
	if eaten.size() > _MAX_LISTED:
		out.append("… and %d more features smoothing ate" % (eaten.size() - _MAX_LISTED))
	return out


## Walkable ground — in play, not too steep, not deep water, not under a structure — in
## components other than the largest.
static func _unreachable(result: MapImageImporter, terrain: TerrainData) -> PackedStringArray:
	var cells: MapImageCells = result.cells
	var walkable := PackedByteArray()
	walkable.resize(cells.cell_count())
	var built: Dictionary = {}
	for rect: Rect2i in result.structures.footprints():
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				built[Vector2i(x, z)] = true
	for i: int in cells.cell_count():
		var cell: Vector2i = cells.cell_of(i)
		walkable[i] = (
			1
			if (
				terrain.cell_supports_entity(cell)
				and result.water.depth_by_cell.get(cell, 0.0) <= WaterBasin.WADE_DEPTH
				and not built.has(cell)
			)
			else 0
		)
	var patches: Array = _patches(cells, walkable)
	if patches.size() <= 1:
		return PackedStringArray()
	patches.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var out := PackedStringArray()
	for patch: Array in patches.slice(1, _MAX_LISTED + 1):
		var at: Vector2i = cells.pixel_of(patch[0])
		out.append(
			"unreachable walkable ground at px (%d, %d): %d cells" % [at.x, at.y, patch.size()]
		)
	if patches.size() > _MAX_LISTED + 1:
		out.append("… and %d more unreachable patches" % (patches.size() - _MAX_LISTED - 1))
	return out


## 4-connected patches of cells sharing one non-zero label, each an Array of Vector2i.
static func _patches(cells: MapImageCells, marked: PackedByteArray) -> Array:
	var seen := PackedByteArray()
	seen.resize(marked.size())
	var out: Array = []
	for i: int in marked.size():
		if marked[i] == 0 or seen[i] == 1:
			continue
		var patch: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [cells.cell_of(i)]
		seen[i] = 1
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			patch.append(cell)
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + step
				if not cells.has_cell(near):
					continue
				var index: int = cells.index_of(near)
				if marked[index] == marked[i] and seen[index] == 0:
					seen[index] = 1
					frontier.append(near)
		out.append(patch)
	return out
