@tool
class_name MapImageStructures
extends RefCounted

## The structures layer read into placements: neutral shelters, neutral buildings and start
## points (map-from-image.md §Structures).
##
## **Each connected patch is one structure**, connected diagonally too, which is why two may not
## touch: they would read as one shape and match nothing. A patch must be a solid rectangle the
## size of a footprint — the shelter's, or one of the neutral building family's, its orientation
## told by which way round it is drawn. A start point is one pixel.

#region Properties
## {piece: MapPiece, origin: Vector2i, quarter_turns: int, kind: MapFeature.Kind, level: int},
## as MapFeature.placements holds them, plus the terrain level the footprint stands on.
var placements: Array[Dictionary] = []
## Start points, in cell space, in reading order of the drawing (rows, then columns).
var starts: Array[Vector2i] = []
#endregion

#region Constants
const _EIGHT_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
#endregion


## Read `cells`' structures layer, matching footprints against `shelter` and `buildings`.
## Every failure is added to `cells.errors`.
static func read(
	cells: MapImageCells, shelter: MapPiece, buildings: Array[MapPiece]
) -> MapImageStructures:
	var out := MapImageStructures.new()
	var seen := PackedByteArray()
	seen.resize(cells.cell_count())
	for i: int in cells.cell_count():
		var meaning: int = cells.structures[i]
		if meaning == MapImagePalette.Meaning.NONE or seen[i] == 1:
			continue
		var patch: Array[Vector2i] = _patch(cells, cells.cell_of(i), meaning, seen)
		out._read_patch(cells, patch, meaning, shelter, buildings)
	return out


## Every cell any placement stands on, as footprint rectangles.
func footprints() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for placement: Dictionary in placements:
		rects.append(MapFeature.placement_rect(placement))
	return rects


func _read_patch(
	a_cells: MapImageCells,
	a_patch: Array[Vector2i],
	a_meaning: int,
	a_shelter: MapPiece,
	a_buildings: Array[MapPiece]
) -> void:
	var pixels: Array[Vector2i] = []
	pixels.assign(a_patch.map(func(cell: Vector2i) -> Vector2i: return a_cells.pixel_of(cell)))
	var touching: Array[Vector2i] = _touching_other(a_cells, a_patch, a_meaning)
	if not touching.is_empty():
		a_cells.add_error(
			(
				"structures: a %s touches another structure; leave a gap between them: %s"
				% [_name(a_meaning), MapImageCells.describe_pixels(touching)]
			),
			touching
		)
		return
	if a_meaning == MapImagePalette.Meaning.START:
		if a_patch.size() != 1:
			a_cells.add_error(
				(
					"structures: a start point is one pixel, not %d: %s"
					% [a_patch.size(), MapImageCells.describe_pixels(pixels)]
				),
				pixels
			)
			return
		if a_cells.level_at(a_patch[0]) == 0 or a_cells.water[a_cells.index_of(a_patch[0])] != 0:
			a_cells.add_error(
				(
					"structures: a start point must be on dry ground: %s"
					% MapImageCells.describe_pixels(pixels)
				),
				pixels
			)
			return
		starts.append(a_patch[0])
		return
	var rect := Rect2i(a_patch[0], Vector2i.ONE)
	for cell: Vector2i in a_patch:
		rect = rect.expand(cell).expand(cell + Vector2i.ONE)
	if a_patch.size() != rect.get_area():
		a_cells.add_error(
			(
				"structures: a %s is drawn %s, not as a solid rectangle: %s"
				% [_name(a_meaning), rect.size, MapImageCells.describe_pixels(pixels)]
			),
			pixels
		)
		return
	var candidates: Array[MapPiece] = [a_shelter]
	if a_meaning == MapImagePalette.Meaning.BUILDING:
		candidates = a_buildings
	var matches: Array[Dictionary] = []
	for piece: MapPiece in candidates:
		for turns: int in [0, 1]:
			if Fixture.oriented_dimensions(piece.footprint, turns) == rect.size:
				matches.append({piece = piece, quarter_turns = turns})
				break
	if matches.size() != 1:
		var known: PackedStringArray = PackedStringArray()
		for piece: MapPiece in candidates:
			known.append("%s %dx%d" % [piece.id, piece.footprint.x, piece.footprint.y])
		var why: String = (
			"matches no piece" if matches.is_empty() else "matches more than one piece"
		)
		(
			a_cells
			. add_error(
				(
					"structures: a %s drawn %dx%d %s (%s): %s"
					% [
						_name(a_meaning),
						rect.size.x,
						rect.size.y,
						why,
						", ".join(known),
						MapImageCells.describe_pixels(pixels),
					]
				),
				pixels
			)
		)
		return
	var level: int = _footprint_level(a_cells, a_patch, pixels, a_meaning)
	if level == 0:
		return
	(
		placements
		. append(
			{
				piece = matches[0].piece,
				origin = rect.position,
				quarter_turns = matches[0].quarter_turns,
				kind =
				(
					MapFeature.Kind.SHELTER
					if a_meaning == MapImagePalette.Meaning.SHELTER
					else MapFeature.Kind.BUILDING_CLUSTER
				),
				level = level,
			}
		)
	)


## The one terrain level a footprint stands on, or 0 (with the error added) when it is not on
## one dry, level, unsloped stretch of ground: a structure needs its ground flat.
func _footprint_level(
	a_cells: MapImageCells, a_patch: Array[Vector2i], a_pixels: Array[Vector2i], a_meaning: int
) -> int:
	var levels: Dictionary = {}
	var is_wet: bool = false
	var is_sloped: bool = false
	for cell: Vector2i in a_patch:
		var index: int = a_cells.index_of(cell)
		levels[a_cells.level_at(cell)] = true
		is_wet = is_wet or a_cells.water[index] != MapImagePalette.Meaning.NONE
		is_sloped = is_sloped or a_cells.cliffs[index] != MapImagePalette.Meaning.NONE
	var why: String = ""
	if is_wet:
		why = "stands in water"
	elif is_sloped:
		why = "stands on a cliff or ramp"
	elif levels.size() != 1:
		why = "straddles terrain levels %s" % [levels.keys()]
	if why.is_empty():
		return levels.keys()[0]
	a_cells.add_error(
		(
			"structures: a %s %s; a structure needs one flat level: %s"
			% [_name(a_meaning), why, MapImageCells.describe_pixels(a_pixels)]
		),
		a_pixels
	)
	return 0


## Cells of a different structure meaning diagonally or orthogonally next to the patch.
static func _touching_other(
	cells: MapImageCells, patch: Array[Vector2i], meaning: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in patch:
		for step: Vector2i in _EIGHT_NEIGHBOURS:
			var near: Vector2i = cell + step
			if not cells.has_cell(near):
				continue
			var other: int = cells.structures[cells.index_of(near)]
			if other != MapImagePalette.Meaning.NONE and other != meaning:
				out.append(cells.pixel_of(cell))
				break
	return out


## The 8-connected patch of `meaning` containing `start`, marking it seen.
static func _patch(
	cells: MapImageCells, start: Vector2i, meaning: int, seen: PackedByteArray
) -> Array[Vector2i]:
	var patch: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [start]
	seen[cells.index_of(start)] = 1
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		patch.append(cell)
		for step: Vector2i in _EIGHT_NEIGHBOURS:
			var near: Vector2i = cell + step
			if not cells.has_cell(near):
				continue
			var index: int = cells.index_of(near)
			if seen[index] == 0 and cells.structures[index] == meaning:
				seen[index] = 1
				frontier.append(near)
	return patch


static func _name(meaning: int) -> String:
	match meaning:
		MapImagePalette.Meaning.SHELTER:
			return "shelter"
		MapImagePalette.Meaning.BUILDING:
			return "building"
	return "start point"
