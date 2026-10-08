class_name MinimapLayer
extends RefCounted

## The minimap's map layer: one colour per terrain cell, saying what stands there — ground,
## impassable ground (a ridge, a cliff, a blocked region), a pond shaded by richness with its rim
## and its impassable deep water darkened, an extraction site, a shelter, a neutral building,
## and a tinted square over each start area. PURE: it takes plain data and returns colours,
## so the conventions are testable without a scene. Minimap gathers the data and applies fog.
##
## TODO: the visual details are provisional — carried over from the map generator's review
## images as they were. See gdd/systems/ux/ui/hud-layout.md §The minimap.

#region Enums
## What kind of neutral fixture a cell holds.
enum Fixture { SITE, SHELTER, BUILDING }
#endregion

#region Constants
const OUT_OF_PLAY := Color(0, 0, 0)
const GROUND := Color(0.80, 0.74, 0.58)
const RIM := Color(0.62, 0.58, 0.46)
const POND_RICH := Color(0.20, 0.40, 0.85)
const POND_POOR := Color(0.55, 0.70, 0.90)
## Uncharged water, which no extractor can use.
const PLAIN_WATER := Color(0.30, 0.35, 0.45)
## Ground nothing can cross: steep or blocked cells.
const IMPASSABLE := Color(0.42, 0.36, 0.30)
## How much deep (impassable) water is darkened against its pond's shade, 0..1 — the pond keeps
## its richness colour, and the part no unit can wade reads as a barrier within it.
const DEEP_WATER_DARKEN: float = 0.35
const FIXTURE_COLORS: Dictionary = {
	Fixture.SITE: Color(0.95, 0.80, 0.15),
	Fixture.SHELTER: Color(0.25, 0.65, 0.30),
	Fixture.BUILDING: Color(0.45, 0.45, 0.50),
}
## Energy per cell at the poorest and richest pond shades — the ends of the map generator's
## richness factors, so a generated pond's shade is its richness category.
const POOR_ENERGY_PER_CELL: float = 60.0
const RICH_ENERGY_PER_CELL: float = 120.0
## How strongly a start area tints the cells under it.
const START_TINT: float = 0.35
## How much an explored-but-unseen cell is darkened, 0..1.
const EXPLORED_DARKEN: float = 0.55
#endregion


## A pond's shade from its full charge per covered cell; plain water for an uncharged body.
static func pond_color(full_charge: int, cell_count: int) -> Color:
	if full_charge <= 0 or cell_count <= 0:
		return PLAIN_WATER
	var richness: float = float(full_charge) / float(cell_count)
	return POND_POOR.lerp(
		POND_RICH,
		clampf(inverse_lerp(POOR_ENERGY_PER_CELL, RICH_ENERGY_PER_CELL, richness), 0.0, 1.0)
	)


## The layer for a `width` x `depth` cell grid, index z * width + x.
##
## `in_play` marks the cells inside the play area. `ponds` is [{cells: Array[Vector2i], color}],
## `fixtures` is [{cells: Array[Vector2i], kind: Fixture}], `starts` is
## [{center: Vector2 (cell space), half: float, color}]. `impassable` marks the cells no unit
## can cross — steep, blocked or deep water — or is empty for none. Later layers draw over
## earlier ones: impassable ground, rims, then water, then fixtures, then start tints.
static func build(
	width: int,
	depth: int,
	in_play: PackedByteArray,
	ponds: Array[Dictionary],
	fixtures: Array[Dictionary],
	starts: Array[Dictionary],
	impassable: PackedByteArray = PackedByteArray()
) -> PackedColorArray:
	var layer := PackedColorArray()
	layer.resize(width * depth)
	var has_impassable: bool = impassable.size() == layer.size()
	for i: int in layer.size():
		var is_impassable: bool = has_impassable and impassable[i] != 0
		layer[i] = (IMPASSABLE if is_impassable else GROUND) if in_play[i] != 0 else OUT_OF_PLAY
	for pond: Dictionary in ponds:
		for cell: Vector2i in pond.cells:
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					_paint(layer, width, depth, in_play, cell + Vector2i(dx, dz), RIM)
	for pond: Dictionary in ponds:
		for cell: Vector2i in pond.cells:
			var is_deep: bool = (
				has_impassable
				and _in_grid(width, depth, cell)
				and impassable[cell.y * width + cell.x] != 0
			)
			var color: Color = pond.color
			_paint(
				layer,
				width,
				depth,
				in_play,
				cell,
				color.darkened(DEEP_WATER_DARKEN) if is_deep else color
			)
	for fixture: Dictionary in fixtures:
		for cell: Vector2i in fixture.cells:
			_paint(layer, width, depth, in_play, cell, FIXTURE_COLORS[fixture.kind])
	for start: Dictionary in starts:
		_tint_square(layer, width, depth, in_play, start.center, start.half, start.color)
	return layer


## A layer colour as fog shows it: unchanged in sight, darkened when explored, black unseen.
static func fogged(color: Color, visibility: Fog.TerrainVisibility) -> Color:
	match visibility:
		Fog.TerrainVisibility.IN_SIGHT:
			return color
		Fog.TerrainVisibility.EXPLORED:
			return color.darkened(EXPLORED_DARKEN)
	return OUT_OF_PLAY


static func _paint(
	layer: PackedColorArray,
	width: int,
	depth: int,
	in_play: PackedByteArray,
	cell: Vector2i,
	color: Color
) -> void:
	if not _in_grid(width, depth, cell):
		return
	var i: int = cell.y * width + cell.x
	if in_play[i] != 0:
		layer[i] = color


static func _in_grid(width: int, depth: int, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth


static func _tint_square(
	layer: PackedColorArray,
	width: int,
	depth: int,
	in_play: PackedByteArray,
	center: Vector2,
	half: float,
	color: Color
) -> void:
	for z: int in range(floori(center.y - half), ceili(center.y + half)):
		for x: int in range(floori(center.x - half), ceili(center.x + half)):
			if x < 0 or z < 0 or x >= width or z >= depth:
				continue
			var i: int = z * width + x
			if in_play[i] != 0:
				layer[i] = layer[i].lerp(color, START_TINT)
