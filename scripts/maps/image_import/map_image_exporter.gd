@tool
class_name MapImageExporter
extends RefCounted

## A map written back out as a palette-coded drawing the importer reads (map-from-image.md
## §Exporting a map to a drawing). The pure core of the Map Generator dock's export button: a
## map's terrain, water and imported structures in, the four layers and a report of what the
## palette could not carry out.
##
## **An export is a fresh starting drawing.** Importing it replaces the terrain, so sculpting
## does not survive: each cell is read as its nearest level and the import's smoothing rebuilds
## the slopes.
##
## The passes, in order: water (each body's basin, ponds by richness shade), chasms (recognised
## by shape), levels (the map's own terraces, lowest first, everything else taking its nearest
## flat ground's level), cliffs (where levels meet across steep ground), structures (only
## the ones an import placed), and a self-check — the drawing is imported, and the cliff pixels
## and structures that fail it are removed and listed, so **an export always imports cleanly**.

#region Constants
## A cell this level is flat ground: what a level reads off. Buildable ground stands well under
## the walkable slope, and the slopes a terrace step is graded into stand near it.
const FLAT_SPREAD: float = TerrainGrid.MAX_SLOPE_DIFF * 0.25
## Flat-ground heights are binned this finely to find the terraces: under any step the
## generator or the importer lays down, so two terraces never share a bin.
const TERRACE_BIN: float = 0.1
## A run of bins is a terrace when it holds this share of the map's flat dry ground. Smaller flats
## — a dry stretch of river bed, a sculptor's landing — are not levels, and take their level from
## the ground around them like a slope.
const MIN_TERRACE_SHARE: float = 0.02
## How far from a terrace's height a flat cell may sit and still read as it. Under half the
## smallest gap between terraces worth drawing, so no cell is near two.
const ON_TERRACE_HEIGHT: float = 0.2
## A steep dry cell is a chasm's floor when it sinks this share of the generator's chasm depth
## below the flat ground around it: the importer's own floor is the full depth down, and the ring
## of rim cells whose corners it pulls down stands only half of it below.
const CHASM_SINK_SHARE: float = 0.75
## Self-check rounds: each removes what the last import refused, so a drawing that has not
## imported in a few has a fault the removals cannot reach.
const CHECK_ROUNDS: int = 8
## Layer order in the file, topmost first, as stack.xml lists it.
const FILE_ORDER: Array[MapImagePalette.Layer] = [
	MapImagePalette.Layer.STRUCTURES,
	MapImagePalette.Layer.CLIFFS,
	MapImagePalette.Layer.WATER,
	MapImagePalette.Layer.TERRAIN,
]
const _FOUR_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
#endregion

#region Properties
## MapImagePalette.Layer -> Image (FORMAT_RGBA8), one pixel per cell.
var images: Dictionary = {}
## The canvas, in pixels: the map's square cell grid.
var size: Vector2i = Vector2i.ZERO
## What the palette could not carry, and what the self-check removed. The report.
var notes: PackedStringArray = PackedStringArray()
## The re-import's passability against the map's (MapImagePassability.compare): {lines,
## opened, closed}. Empty until the self-check has imported the drawing.
var passages: Dictionary = {}
## Why the export failed; non-empty means `images` must not be written.
var errors: PackedStringArray = PackedStringArray()

## One export's working state, cell-indexed, each pass reading what the last one wrote.
var _terrain: TerrainData
var _params: MapImageImportParams
var _side: int = 0
## Walkable cells on the map and on its re-import, for the readout.
var _walkable_before := PackedByteArray()
var _walkable_after := PackedByteArray()
## The map's own water bodies, as export_parts was given them, for comparing what is walkable.
var _original_waters: Array[Dictionary] = []
## Water meaning per cell (MapImagePalette.Meaning, NONE when dry).
var _water := PackedByteArray()
## Cells of each body, for the levels pass to set every cell of one body to its lowest bank.
var _bodies: Array[Array] = []
var _chasm := PackedByteArray()
## Level 1–6 per cell, 0 where none (out of play, chasm).
var _level := PackedByteArray()
#endregion


## Export the map `a_map` holds: its terrain, its water bodies, and the structures and start
## points an import tagged. Pieces placed by hand are left out — a re-import keeps them, so
## drawing them too would bring them back twice.
static func from_map(a_map: Map, a_params: MapImageImportParams) -> MapImageExporter:
	var waters: Array[Dictionary] = []
	var pieces: Array[Dictionary] = []
	var starts: Array[Vector2i] = []
	var left_out: int = 0
	var half := Vector2(a_map.terrain_data.grid_width(), a_map.terrain_data.grid_depth()) * 0.5
	for child: Node in a_map.get_children():
		if child is WaterBody:
			var body: WaterBody = child
			waters.append({seed_cell = body.seed_cell, level = body.level, energy = body.energy})
		elif child is StartPoint and MapImageReimport.is_imported(child):
			var at: Vector3 = (child as Node3D).position
			starts.append(Vector2i((Vector2(at.x, at.z) + half).floor()))
		elif child is Entity and child.has_node("Fixture"):
			if not MapImageReimport.is_imported(child):
				left_out += 1
				continue
			pieces.append(_piece_of(child as Entity, half))
		elif child is Entity:
			left_out += 1
	var out: MapImageExporter = export_parts(a_map.terrain_data, waters, pieces, starts, a_params)
	if left_out > 0:
		out.notes.append(
			(
				"%d pieces not exported: not placed by an import, or not a shelter or building"
				% left_out
			)
		)
	return out


## Export a map as its parts: `waters` as {seed_cell, level, energy}, a charged one a pond;
## `pieces` as {id: StringName, rect: Rect2i}; `starts` one cell each.
static func export_parts(
	terrain: TerrainData,
	waters: Array[Dictionary],
	pieces: Array[Dictionary],
	starts: Array[Vector2i],
	params: MapImageImportParams
) -> MapImageExporter:
	var out := MapImageExporter.new()
	out._terrain = terrain
	out._params = params
	out._side = terrain.grid_width()
	out.size = Vector2i(out._side, out._side)
	out._original_waters = waters
	out._read_water(waters)
	out._read_chasms()
	out._read_levels()
	out._paint_terrain_and_water()
	out._paint_cliffs()
	out._paint_structures(pieces, starts)
	out._self_check()
	return out


## Write the drawing as OpenRaster at `path`, the one format exported (map-from-image.md
## §Exporting a map to a drawing).
func write(path: String) -> Error:
	var named: Array[Dictionary] = []
	for layer: MapImagePalette.Layer in FILE_ORDER:
		named.append({name = MapImagePalette.LAYER_NAMES[layer], image = images[layer]})
	return OpenRaster.write(path, size, named)


func is_valid() -> bool:
	return errors.is_empty() and not images.is_empty()


## Where a unit can walk at `a_cell`, on the map and on the drawing's re-import, and whether a
## reported passage runs through it. Empty before a successful self-check.
func passability_at(a_cell: Vector2i) -> String:
	if (
		passages.is_empty()
		or a_cell.x < 0
		or a_cell.y < 0
		or a_cell.x >= _side
		or a_cell.y >= _side
	):
		return ""
	var at: int = _index(a_cell)
	var text: String = (
		"%s on the map, %s re-imported"
		% [
			"walkable" if _walkable_before[at] == 1 else "not walkable",
			"walkable" if _walkable_after[at] == 1 else "not walkable",
		]
	)
	if (passages.opened as Array).has(a_cell):
		text += " — in a passage the re-import OPENS"
	elif (passages.closed as Array).has(a_cell):
		text += " — in a passage the re-import CLOSES"
	return text


## Where a unit can walk on the map against on the drawing's re-import, with the passages the
## report names marked; null before a successful self-check.
func readout() -> Image:
	if passages.is_empty():
		return null
	return MapImagePassability.readout(
		_walkable_before, _walkable_after, _side, passages.opened, passages.closed
	)


## The drawing as the importer would read it.
func layers() -> MapImageLayers:
	var out := MapImageLayers.new()
	out.size = size
	for layer: int in images:
		out.images[layer] = images[layer]
	return out


static func _piece_of(a_piece: Entity, a_half: Vector2) -> Dictionary:
	var fixture: Fixture = a_piece.get_node("Fixture")
	var turns: int = Fixture.quarter_turns_of_yaw(a_piece.yaw)
	var dimensions: Vector2i = Fixture.oriented_dimensions(fixture.dimensions, turns)
	var center: Vector2 = Vector2(a_piece.position.x, a_piece.position.z) + a_half
	var origin := Vector2i((center - Vector2(dimensions) * 0.5).round())
	return {id = a_piece.id, rect = Rect2i(origin, dimensions)}


#region Passes
func _index(a_cell: Vector2i) -> int:
	return a_cell.y * _side + a_cell.x


func _has(a_cell: Vector2i) -> bool:
	return a_cell.x >= 0 and a_cell.y >= 0 and a_cell.x < _side and a_cell.y < _side


func _in_play(a_cell: Vector2i) -> bool:
	return _has(a_cell) and _terrain.is_cell_in_play(a_cell)


## Each body's basin as the game floods it: a pond in the richness shade its charge per cell is
## nearest to, other water deep or shallow by its depth.
func _read_water(a_waters: Array[Dictionary]) -> void:
	_water.resize(_side * _side)
	for water: Dictionary in a_waters:
		var basin: WaterBasin = WaterBasin.fill(_terrain, water.seed_cell, water.level)
		var cells: Array[Vector2i] = basin.covered_cells()
		if cells.is_empty():
			notes.append("water seeded at %s holds no water, not exported" % [water.seed_cell])
			continue
		_bodies.append(cells)
		var pond_shade: int = _pond_shade(water.get("energy", 0), cells.size(), water.seed_cell)
		for cell: Vector2i in cells:
			_water[_index(cell)] = (
				pond_shade
				if pond_shade != MapImagePalette.Meaning.NONE
				else (
					MapImagePalette.Meaning.SHALLOW
					if _is_wadeable(basin, cell)
					else MapImagePalette.Meaning.DEEP
				)
			)


## Shallow means a unit can walk it — wading depth over a bed no steeper than ground it could walk
## — because the import lays shallow water on a flat, wadeable bed. Water only wading-deep over a
## steep bed, as at the foot of a bank sculpted straight into a lake, cannot be walked; drawn
## shallow, it came back as a wadeable shelf all the way round its lake (Alex, 2026-10-23).
func _is_wadeable(a_basin: WaterBasin, a_cell: Vector2i) -> bool:
	return not a_basin.is_deep(a_cell) and not _is_steep(a_cell)


## The richness shade nearest a pond's charge per cell, or NONE for uncharged water. A pond whose
## charge would change on re-import is listed.
func _pond_shade(a_charge: int, a_cells: int, a_seed: Vector2i) -> int:
	if a_charge <= 0:
		return MapImagePalette.Meaning.NONE
	var factors: PackedInt32Array = _params.generation.pond_richness_factors
	var per_cell: float = float(a_charge) / a_cells
	var nearest: int = 0
	for i: int in factors.size():
		if absf(factors[i] - per_cell) < absf(factors[nearest] - per_cell):
			nearest = i
	var reimported: int = mini(a_cells * factors[nearest], _params.generation.pond_charge_max)
	if reimported != a_charge:
		notes.append(
			(
				"pond seeded at %s: charge %d comes back %d (%d cells at %d)"
				% [a_seed, a_charge, reimported, a_cells, factors[nearest]]
			)
		)
	return MapImagePalette.Meaning.LITHIUM_POOR + nearest


## Chasms, by shape: steep dry ground sunk well below the flat ground around it. Each patch of
## steep dry cells is measured against its lowest flat neighbour, and only the cells sunk far
## enough are its floor, so the ring of rim cells a floor pulls down stays rim.
func _read_chasms() -> void:
	_chasm.resize(_side * _side)
	var seen := PackedByteArray()
	seen.resize(_side * _side)
	var sink: float = _params.generation.chasm_depth * CHASM_SINK_SHARE
	for z: int in _side:
		for x: int in _side:
			var start := Vector2i(x, z)
			if seen[_index(start)] == 1 or not _is_steep_dry(start):
				continue
			var patch: Array[Vector2i] = []
			var rim_height: float = INF
			var frontier: Array[Vector2i] = [start]
			seen[_index(start)] = 1
			while not frontier.is_empty():
				var cell: Vector2i = frontier.pop_back()
				patch.append(cell)
				for step: Vector2i in _FOUR_NEIGHBOURS:
					var near: Vector2i = cell + step
					if not _in_play(near) or seen[_index(near)] == 1:
						continue
					if _is_steep_dry(near):
						seen[_index(near)] = 1
						frontier.append(near)
					elif _water[_index(near)] == MapImagePalette.Meaning.NONE:
						rim_height = minf(rim_height, _terrain.cell_mean_height(near))
			for cell: Vector2i in patch:
				if _terrain.cell_mean_height(cell) < rim_height - sink:
					_chasm[_index(cell)] = 1


func _is_beside_steep(a_cell: Vector2i) -> bool:
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var near: Vector2i = a_cell + Vector2i(dx, dz)
			if _in_play(near) and _is_steep(near):
				return true
	return false


func _is_steep(a_cell: Vector2i) -> bool:
	return _terrain.cell_height_spread(a_cell) > TerrainGrid.MAX_SLOPE_DIFF


func _is_steep_dry(a_cell: Vector2i) -> bool:
	return (
		_in_play(a_cell)
		and _water[_index(a_cell)] == MapImagePalette.Meaning.NONE
		and _terrain.cell_height_spread(a_cell) > TerrainGrid.MAX_SLOPE_DIFF
	)


## Levels, read off the map's own terraces (Alex, 2026-10-23): each height a large share of its
## flat dry ground stands at is a level, lowest first, so no step has to match the one the map was
## built with. Flat ground near a terrace reads as it, and every other cell takes the level of its
## nearest such ground, so a slope comes back as the two terraces it joined. Each body's cells
## then all take its lowest bank's level, which is what the importer floods a body to — one level
## under all of it, or it would read as a waterfall.
func _read_levels() -> void:
	_level.resize(_side * _side)
	var terraces: PackedFloat32Array = _terraces()
	if terraces.size() > MapImagePalette.LEVEL_COUNT:
		(
			notes
			. append(
				(
					"%d terraces, more than the %d levels: the top %d are exported as level %d"
					% [
						terraces.size(),
						MapImagePalette.LEVEL_COUNT,
						terraces.size() - MapImagePalette.LEVEL_COUNT + 1,
						MapImagePalette.LEVEL_COUNT,
					]
				)
			)
		)
	var frontier: Array[Vector2i] = []
	for z: int in _side:
		for x: int in _side:
			var cell := Vector2i(x, z)
			if not _is_flat_dry(cell):
				continue
			var height: float = _terrain.cell_mean_height(cell)
			for i: int in terraces.size():
				if absf(height - terraces[i]) <= ON_TERRACE_HEIGHT:
					_level[_index(cell)] = mini(i + 1, MapImagePalette.LEVEL_COUNT)
					frontier.append(cell)
					break
	if frontier.is_empty():
		errors.append("no flat dry ground to read the levels from")
		return
	# A wave at a time, so a cell reached from two levels at once — between a step's two sides —
	# takes the lower: the import's corner rule puts a step inside its lower cell, so that is the
	# cell the step's ground falls across, sheer or graded.
	while not frontier.is_empty():
		var reached: Dictionary = {}
		for cell: Vector2i in frontier:
			for near_step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + near_step
				if _in_play(near) and _level[_index(near)] == 0:
					var level: int = _level[_index(cell)]
					var span: Vector2i = reached.get(near, Vector2i(level, level))
					reached[near] = Vector2i(mini(span.x, level), maxi(span.y, level))
		frontier.clear()
		for near: Vector2i in reached:
			var span: Vector2i = reached[near]
			_level[_index(near)] = span.x
			frontier.append(near)
	for body: Array in _bodies:
		var bank: int = MapImagePalette.LEVEL_COUNT
		for cell: Vector2i in body:
			for near_step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + near_step
				if _in_play(near) and _water[_index(near)] == MapImagePalette.Meaning.NONE:
					bank = mini(bank, _level[_index(near)])
		for cell: Vector2i in body:
			_level[_index(cell)] = bank


## The heights the map's terraces stand at, lowest first: runs of TERRACE_BIN-wide bins of flat
## dry ground each holding MIN_TERRACE_SHARE of it, each at its cells' mean height.
func _terraces() -> PackedFloat32Array:
	var bins: Dictionary = {}
	var total: int = 0
	for z: int in _side:
		for x: int in _side:
			var cell := Vector2i(x, z)
			if not _is_flat_dry(cell):
				continue
			var height: float = _terrain.cell_mean_height(cell)
			var key: int = roundi(height / TERRACE_BIN)
			var bin: Vector2 = bins.get(key, Vector2.ZERO)
			bins[key] = bin + Vector2(height, 1.0)
			total += 1
	var needed: float = total * MIN_TERRACE_SHARE
	var keys: Array = bins.keys().filter(func(key: int) -> bool: return bins[key].y >= needed)
	keys.sort()
	var out := PackedFloat32Array()
	var run := Vector2.ZERO
	for i: int in keys.size():
		run += bins[keys[i]]
		if i == keys.size() - 1 or keys[i + 1] != keys[i] + 1:
			out.append(run.x / run.y)
			run = Vector2.ZERO
	return out


func _is_flat_dry(a_cell: Vector2i) -> bool:
	return (
		_in_play(a_cell)
		and _water[_index(a_cell)] == MapImagePalette.Meaning.NONE
		and _chasm[_index(a_cell)] == 0
		and _terrain.cell_height_spread(a_cell) <= FLAT_SPREAD
	)


func _paint_terrain_and_water() -> void:
	var terrain := Image.create_empty(_side, _side, false, Image.FORMAT_RGBA8)
	var water := Image.create_empty(_side, _side, false, Image.FORMAT_RGBA8)
	for z: int in _side:
		for x: int in _side:
			var cell := Vector2i(x, z)
			var at: int = _index(cell)
			var meaning: int = MapImagePalette.Meaning.OUT_OF_PLAY
			if _in_play(cell):
				meaning = (
					MapImagePalette.Meaning.CHASM
					if _chasm[at] == 1
					else MapImagePalette.Meaning.LEVEL_1 + _level[at] - 1
				)
			terrain.set_pixelv(cell, _color(meaning))
			if _water[at] != MapImagePalette.Meaning.NONE:
				water.set_pixelv(cell, _color(_water[at]))
	images[MapImagePalette.Layer.TERRAIN] = terrain
	images[MapImagePalette.Layer.WATER] = water


## A cliff wherever a step between levels falls across ground too steep to walk, as the map has
## it, on the cell at its foot — the lower one, where the levels put the step — so the import
## grades it across that cell again. A step the map grades into a walkable slope gets none.
##
## Every other steep cell of dry ground is drawn rough, the palette's unwalkable ground on any
## level (Alex, 2026-10-23): a ridge, a sculpted bank or the rest of a cliff's band, which drawn
## as level ground came back walkable and opened passages the map kept closed.
##
## A cell counts as a cliff's foot when it or a neighbour is steep: a rough slope a sculptor left
## steep all along still holds the odd walkable cell, and a cliff line broken at each one opened
## passages through a band the map kept closed (Alex, 2026-10-23).
func _paint_cliffs() -> void:
	var cliffs := Image.create_empty(_side, _side, false, Image.FORMAT_RGBA8)
	for z: int in _side:
		for x: int in _side:
			var cell := Vector2i(x, z)
			if not _is_land(cell):
				continue
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = cell + step
				if (
					_is_land(near)
					and _level[_index(near)] > _level[_index(cell)]
					and _is_beside_steep(cell)
				):
					cliffs.set_pixelv(cell, _color(MapImagePalette.Meaning.CLIFF))
					break
	var rough: Color = _color(MapImagePalette.Meaning.ROUGH)
	for z: int in _side:
		for x: int in _side:
			var cell := Vector2i(x, z)
			if _is_land(cell) and _is_steep(cell) and cliffs.get_pixelv(cell).a8 == 0:
				cliffs.set_pixelv(cell, rough)
	images[MapImagePalette.Layer.CLIFFS] = cliffs


func _is_land(a_cell: Vector2i) -> bool:
	return (
		_in_play(a_cell)
		and _water[_index(a_cell)] == MapImagePalette.Meaning.NONE
		and _chasm[_index(a_cell)] == 0
	)


func _paint_structures(a_pieces: Array[Dictionary], a_starts: Array[Vector2i]) -> void:
	var structures := Image.create_empty(_side, _side, false, Image.FORMAT_RGBA8)
	var shelter: StringName = _params.generation.shelter_piece.id
	for piece: Dictionary in a_pieces:
		var meaning: int = (
			MapImagePalette.Meaning.SHELTER
			if piece.id == shelter
			else MapImagePalette.Meaning.BUILDING
		)
		var rect: Rect2i = piece.rect
		structures.fill_rect(rect.intersection(Rect2i(Vector2i.ZERO, size)), _color(meaning))
	for start: Vector2i in a_starts:
		if _has(start):
			structures.set_pixelv(start, _color(MapImagePalette.Meaning.START))
	images[MapImagePalette.Layer.STRUCTURES] = structures


## Import the drawing; remove the cliff pixels and the structures the import refused, and try
## again. What is removed is listed. A drawing still refused after that is an export failure.
func _self_check() -> void:
	if not errors.is_empty():
		return
	var removed_cliffs: int = 0
	var removed_structures: int = 0
	for _round: int in CHECK_ROUNDS:
		var result: MapImageImporter = MapImageImporter.import_layers(layers(), _params)
		if result.is_valid():
			break
		var pixels: Array[Vector2i] = (
			result.cells.error_pixels if result.cells != null else [] as Array[Vector2i]
		)
		var cliffs: int = _clear_pixels(MapImagePalette.Layer.CLIFFS, pixels)
		var structures: int = _clear_structures(pixels)
		if cliffs + structures == 0:
			errors.append_array(result.errors)
			return
		removed_cliffs += cliffs
		removed_structures += structures
	if removed_cliffs > 0:
		notes.append("%d cliff pixels removed: the import refused them" % removed_cliffs)
	if removed_structures > 0:
		notes.append("%d structures removed: the import refused them" % removed_structures)
	var final: MapImageImporter = MapImageImporter.import_layers(layers(), _params)
	if not final.is_valid():
		errors.append_array(final.errors)
		return
	_walkable_before = MapImagePassability.walkable(_terrain, _original_waters)
	_walkable_after = MapImagePassability.walkable(
		final.map.terrain, MapImagePassability.waters_of(final.map)
	)
	passages = MapImagePassability.compare(_walkable_before, _walkable_after, _side)
	notes.append_array(passages.lines)


func _clear_pixels(a_layer: MapImagePalette.Layer, a_pixels: Array[Vector2i]) -> int:
	var image: Image = images[a_layer]
	var cleared: int = 0
	for pixel: Vector2i in a_pixels:
		if _has(pixel) and image.get_pixelv(pixel).a8 > 0:
			image.set_pixelv(pixel, Color(0, 0, 0, 0))
			cleared += 1
	return cleared


## Clear every structure — its whole drawn patch — that holds one of `a_pixels`. Returns how
## many were cleared.
func _clear_structures(a_pixels: Array[Vector2i]) -> int:
	var image: Image = images[MapImagePalette.Layer.STRUCTURES]
	var cleared: int = 0
	for pixel: Vector2i in a_pixels:
		if not _has(pixel) or image.get_pixelv(pixel).a8 == 0:
			continue
		var frontier: Array[Vector2i] = [pixel]
		image.set_pixelv(pixel, Color(0, 0, 0, 0))
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var near: Vector2i = cell + Vector2i(dx, dz)
					if _has(near) and image.get_pixelv(near).a8 > 0:
						image.set_pixelv(near, Color(0, 0, 0, 0))
						frontier.append(near)
		cleared += 1
	return cleared


static func _color(a_meaning: int) -> Color:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		if entry.meaning == a_meaning:
			return entry.color
	return Color(0, 0, 0, 0)
#endregion
