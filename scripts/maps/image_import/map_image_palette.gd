@tool
class_name MapImagePalette
extends RefCounted

## The colours a map drawing may use, layer by layer, and what each means — THE one definition:
## the importer classifies pixels from ENTRIES, and the dock's palette view is drawn from it, so
## the two cannot disagree (map-from-image.md §The palette).
##
## Colours are exact. A pixel whose colour is not its layer's is not "nearest to" anything: it
## fails the import (MapImageImporter).

#region Enums
enum Layer { TERRAIN, WATER, CLIFFS, STRUCTURES }

## What a pixel says. NONE is an empty pixel on a layer that may have gaps; the terrain layer
## has none — out of play is a colour of its own.
enum Meaning {
	NONE,
	LEVEL_1,
	LEVEL_2,
	LEVEL_3,
	LEVEL_4,
	LEVEL_5,
	LEVEL_6,
	CHASM,
	OUT_OF_PLAY,
	DEEP,
	SHALLOW,
	LITHIUM_POOR,
	LITHIUM_STANDARD,
	LITHIUM_RICH,
	CLIFF,
	RAMP,
	SHELTER,
	BUILDING,
	START,
	ROUGH,
}
#endregion

#region Constants
## The fixed layer names a drawing's layers are read by, lower case.
const LAYER_NAMES: Dictionary = {
	Layer.TERRAIN: "terrain",
	Layer.WATER: "water",
	Layer.CLIFFS: "cliffs",
	Layer.STRUCTURES: "structures",
}
const OPAQUE: int = 255
## The cliffs layer's ramp alpha. Exact, like the colours: a painter's half is 128.
const HALF_ALPHA: int = 128
const LEVEL_COUNT: int = 6

## Every colour, in the order the palette view lists them. `alpha` is the exact alpha the pixel
## must carry; every other layer colour is opaque.
const ENTRIES: Array[Dictionary] = [
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_1, color = Color8(0xAF, 0xCE, 0x8C)},
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_2, color = Color8(0xC8, 0xCE, 0x8C)},
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_3, color = Color8(0xCE, 0xBB, 0x8C)},
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_4, color = Color8(0xCE, 0xA4, 0x8C)},
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_5, color = Color8(0xCE, 0x97, 0x8C)},
	{layer = Layer.TERRAIN, meaning = Meaning.LEVEL_6, color = Color8(0xB4, 0x85, 0x7A)},
	{layer = Layer.TERRAIN, meaning = Meaning.CHASM, color = Color8(0x00, 0x00, 0x00)},
	{layer = Layer.TERRAIN, meaning = Meaning.OUT_OF_PLAY, color = Color8(0x3C, 0x3C, 0x46)},
	{layer = Layer.WATER, meaning = Meaning.DEEP, color = Color8(0x7C, 0x8B, 0xC8)},
	{layer = Layer.WATER, meaning = Meaning.SHALLOW, color = Color8(0xA4, 0xCD, 0xDF)},
	{layer = Layer.WATER, meaning = Meaning.LITHIUM_POOR, color = Color8(0xE8, 0xC0, 0x8A)},
	{layer = Layer.WATER, meaning = Meaning.LITHIUM_STANDARD, color = Color8(0xD5, 0x8A, 0x3A)},
	{layer = Layer.WATER, meaning = Meaning.LITHIUM_RICH, color = Color8(0xA8, 0x5A, 0x1E)},
	{layer = Layer.CLIFFS, meaning = Meaning.CLIFF, color = Color8(0x00, 0x00, 0x00)},
	{
		layer = Layer.CLIFFS,
		meaning = Meaning.RAMP,
		color = Color8(0x00, 0x00, 0x00, HALF_ALPHA),
	},
	{layer = Layer.CLIFFS, meaning = Meaning.ROUGH, color = Color8(0x8C, 0x2D, 0x19)},
	{layer = Layer.STRUCTURES, meaning = Meaning.SHELTER, color = Color8(0xFF, 0x00, 0xFF)},
	{layer = Layer.STRUCTURES, meaning = Meaning.BUILDING, color = Color8(0xFF, 0xFF, 0xFF)},
	{layer = Layer.STRUCTURES, meaning = Meaning.START, color = Color8(0x00, 0xA0, 0xFF)},
]

## What each meaning is called in the palette view and the report.
const LABELS: Dictionary = {
	Meaning.LEVEL_1: "level 1 (lowest)",
	Meaning.LEVEL_2: "level 2",
	Meaning.LEVEL_3: "level 3",
	Meaning.LEVEL_4: "level 4",
	Meaning.LEVEL_5: "level 5",
	Meaning.LEVEL_6: "level 6 (highest)",
	Meaning.CHASM: "chasm: dry, broken floor nothing stands on",
	Meaning.OUT_OF_PLAY: "out of play: beyond the map's edge",
	Meaning.DEEP: "deep water",
	Meaning.SHALLOW: "shallow water",
	Meaning.LITHIUM_POOR: "lithium pond, poor",
	Meaning.LITHIUM_STANDARD: "lithium pond, standard",
	Meaning.LITHIUM_RICH: "lithium pond, rich",
	Meaning.CLIFF: "cliff (full alpha): a sheer face",
	Meaning.RAMP: "ramp (half alpha): graded linearly",
	Meaning.ROUGH: "rough: broken ground nothing walks, on any level",
	Meaning.SHELTER: "neutral shelter, at its exact footprint",
	Meaning.BUILDING: "neutral building, its footprint picks the piece",
	Meaning.START: "start point, one pixel",
}
#endregion

#region Properties
## Layer -> {packed RGBA -> Meaning}. Built once from ENTRIES on first use: classification
## looks a colour up for every pixel of every layer, and a scan of ENTRIES per pixel would be
## the whole cost of reading a large drawing.
static var _by_color: Dictionary = {}
#endregion


## The meaning of an RGBA8 pixel on `layer`: NONE for an empty pixel on a layer that may have
## gaps, or -1 for a colour the layer does not use.
static func meaning_of(layer: Layer, r: int, g: int, b: int, a: int) -> int:
	if a == 0 and layer != Layer.TERRAIN:
		return Meaning.NONE
	return _lookup().get(layer, {}).get(pack(r, g, b, a), -1)


static func pack(r: int, g: int, b: int, a: int) -> int:
	return (r << 24) | (g << 16) | (b << 8) | a


static func entries_of(layer: Layer) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(ENTRIES.filter(func(e: Dictionary) -> bool: return e.layer == layer))
	return out


## The layer a drawing's layer `name` is, or -1 for a name the importer does not read.
static func layer_named(name: String) -> int:
	for layer: int in LAYER_NAMES:
		if LAYER_NAMES[layer] == name.strip_edges().to_lower():
			return layer
	return -1


## `#RRGGBB`, with the alpha appended when it is not opaque — how the palette view and the
## report write a colour.
static func hex(color: Color) -> String:
	var text: String = "#" + color.to_html(false).to_upper()
	return text if color.a8 == OPAQUE else "%s at alpha %d" % [text, color.a8]


static func hex_of_pixel(r: int, g: int, b: int, a: int) -> String:
	return hex(Color8(r, g, b, a))


## The terrain level 1–6 a meaning names, or 0 when it names none.
static func level_of(meaning: int) -> int:
	if meaning >= Meaning.LEVEL_1 and meaning <= Meaning.LEVEL_6:
		return meaning - Meaning.LEVEL_1 + 1
	return 0


static func _lookup() -> Dictionary:
	if _by_color.is_empty():
		for entry: Dictionary in ENTRIES:
			var color: Color = entry.color
			if not _by_color.has(entry.layer):
				_by_color[entry.layer] = {}
			_by_color[entry.layer][pack(color.r8, color.g8, color.b8, color.a8)] = entry.meaning
	return _by_color
