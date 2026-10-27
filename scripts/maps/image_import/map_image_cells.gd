@tool
class_name MapImageCells
extends RefCounted

## A drawing classified onto the cell grid: every layer's pixels turned into palette meanings,
## and the painted play area fitted to the play rectangle TerrainData derives its grid from.
##
## **Pixels are cells** (map-from-image.md §The image's frame): the drawing is turned 45° so
## each pixel is one cell, with no resampling. The play area is the painted extent — everything
## not drawn in the out-of-play colour — and must be EXACTLY the diamond that
## `TerrainData.play_size` produces, or the classification fails and lists where it leaves it.
##
## Pixel and cell differ only by `offset`: pixel = cell + offset. Error positions are given as
## pixels, which is where the author looks.

#region Constants
const _MAX_LISTED: int = 6
#endregion

#region Properties
## The play rectangle, in diamonds, and the square cell grid it derives (side `side`).
var play_size: Vector2i = Vector2i.ONE
var side: int = 0
var offset: Vector2i = Vector2i.ZERO
## One MapImagePalette.Meaning per cell, index z * side + x, per layer. A cell beyond the image
## reads OUT_OF_PLAY on the terrain layer and NONE on the rest.
var terrain := PackedByteArray()
var water := PackedByteArray()
var cliffs := PackedByteArray()
var structures := PackedByteArray()
## TerrainData.in_play_mask for `play_size`: 1 where the cell is in play.
var in_play := PackedByteArray()
## Why the drawing does not classify; non-empty means nothing above may be used.
var errors: PackedStringArray = PackedStringArray()
## Pixels the errors are about, for the readout.
var error_pixels: Array[Vector2i] = []
## Each error with the pixels it is about, in the order the errors were raised: {message,
## pixels}. What MapImageIssues marks, one colour per issue.
var issues: Array[Dictionary] = []
#endregion


static func classify(layers: MapImageLayers) -> MapImageCells:
	var cells := MapImageCells.new()
	var meanings: Dictionary = {}
	for layer: int in layers.images:
		meanings[layer] = cells._meanings_of(layer, layers.images[layer], layers.size)
	if not cells.errors.is_empty():
		return cells
	cells._fit_frame(meanings[MapImagePalette.Layer.TERRAIN], layers.size)
	if not cells.errors.is_empty():
		return cells
	cells._resample(meanings, layers.size)
	cells._check_outside_play()
	return cells


func cell_count() -> int:
	return side * side


func index_of(cell: Vector2i) -> int:
	return cell.y * side + cell.x


func cell_of(index: int) -> Vector2i:
	return Vector2i(index % side, index / side)


func pixel_of(cell: Vector2i) -> Vector2i:
	return cell + offset


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < side and cell.y < side


func is_in_play(cell: Vector2i) -> bool:
	return has_cell(cell) and in_play[index_of(cell)] == 1


## The terrain level 1–6 of a cell, or 0 for a chasm or a cell out of play.
func level_at(cell: Vector2i) -> int:
	return MapImagePalette.level_of(terrain[index_of(cell)]) if has_cell(cell) else 0


func is_chasm(cell: Vector2i) -> bool:
	return has_cell(cell) and terrain[index_of(cell)] == MapImagePalette.Meaning.CHASM


func add_error(message: String, pixels: Array[Vector2i] = []) -> void:
	errors.append(message)
	error_pixels.append_array(pixels)
	issues.append({message = message, pixels = pixels})


## A list of pixels for a message: the first few, and how many more.
static func describe_pixels(pixels: Array[Vector2i]) -> String:
	var shown: PackedStringArray = PackedStringArray()
	for pixel: Vector2i in pixels.slice(0, _MAX_LISTED):
		shown.append("(%d, %d)" % [pixel.x, pixel.y])
	var more: String = (
		" and %d more" % (pixels.size() - _MAX_LISTED) if pixels.size() > _MAX_LISTED else ""
	)
	return "px " + ", ".join(shown) + more


#region Classification
## One Meaning per pixel of `a_image`, with every colour the layer does not use reported once,
## at the pixels it was found.
func _meanings_of(a_layer: int, a_image: Image, a_size: Vector2i) -> PackedByteArray:
	var data: PackedByteArray = a_image.get_data()
	var out := PackedByteArray()
	out.resize(a_size.x * a_size.y)
	var unknown: Dictionary = {}
	var transparent: Array[Vector2i] = []
	for i: int in out.size():
		var r: int = data[i * 4]
		var g: int = data[i * 4 + 1]
		var b: int = data[i * 4 + 2]
		var a: int = data[i * 4 + 3]
		var meaning: int = MapImagePalette.meaning_of(a_layer, r, g, b, a)
		if meaning >= 0:
			out[i] = meaning
			continue
		var pixel := Vector2i(i % a_size.x, i / a_size.x)
		if a == 0:
			transparent.append(pixel)
			continue
		var key: int = MapImagePalette.pack(r, g, b, a)
		if not unknown.has(key):
			unknown[key] = [] as Array[Vector2i]
		unknown[key].append(pixel)
	var layer_name: String = MapImagePalette.LAYER_NAMES[a_layer]
	if not transparent.is_empty():
		add_error(
			(
				"terrain: %d unpainted pixels — every pixel is a level, a chasm or out of play: %s"
				% [transparent.size(), describe_pixels(transparent)]
			),
			transparent
		)
	for key: int in unknown:
		var pixels: Array[Vector2i] = unknown[key]
		add_error(
			(
				"%s: %s is not in the palette (%d pixels): %s"
				% [
					layer_name,
					MapImagePalette.hex_of_pixel(
						(key >> 24) & 0xFF, (key >> 16) & 0xFF, (key >> 8) & 0xFF, key & 0xFF
					),
					pixels.size(),
					describe_pixels(pixels),
				]
			),
			pixels
		)
	return out


## Derive play_size and the pixel offset from the painted extent, then require the painted
## pixels to be exactly the play diamond of that size.
##
## In screen coordinates s = x + z, t = x − z the play area is a rectangle (StaggeredGrid), so
## the painted extent's s and t ranges give play_size directly: a diamond `play_size` wide spans
## 2 × play_size of s (and of t).
func _fit_frame(a_terrain: PackedByteArray, a_size: Vector2i) -> void:
	var painted: Array[Vector2i] = []
	for i: int in a_terrain.size():
		if a_terrain[i] != MapImagePalette.Meaning.OUT_OF_PLAY:
			painted.append(Vector2i(i % a_size.x, i / a_size.x))
	if painted.is_empty():
		add_error("terrain: nothing is in play — the whole layer is the out-of-play colour")
		return
	var s_range := Vector2i(painted[0].x + painted[0].y, painted[0].x + painted[0].y)
	var t_range := Vector2i(painted[0].x - painted[0].y, painted[0].x - painted[0].y)
	for pixel: Vector2i in painted:
		s_range = Vector2i(mini(s_range.x, pixel.x + pixel.y), maxi(s_range.y, pixel.x + pixel.y))
		t_range = Vector2i(mini(t_range.x, pixel.x - pixel.y), maxi(t_range.y, pixel.x - pixel.y))
	# Rounded down: an odd extent is a diamond's edge drawn a pixel off, which the comparison
	# below then lists.
	play_size = Vector2i(maxi((s_range.y - s_range.x) / 2, 1), maxi((t_range.y - t_range.x) / 2, 1))
	side = TerrainData.derive_dimensions(play_size).x - 1
	# In the grid the diamond's least s is play_size.y and least t is −play_size.y (the grid is
	# centred on the rectangle); a shift by (ox, oz) moves s by ox + oz and t by ox − oz.
	var shift_s: int = s_range.x - play_size.y
	var shift_t: int = t_range.x + play_size.y
	offset = Vector2i(floori((shift_s + shift_t) / 2.0), floori((shift_s - shift_t) / 2.0))
	var probe := TerrainData.new()
	probe.play_size = play_size
	in_play = probe.in_play_mask()
	var is_painted := PackedByteArray()
	is_painted.resize(a_size.x * a_size.y)
	for pixel: Vector2i in painted:
		is_painted[pixel.y * a_size.x + pixel.x] = 1
	var stray: Array[Vector2i] = []
	for pixel: Vector2i in painted:
		if not is_in_play(pixel - offset):
			stray.append(pixel)
	var missing: Array[Vector2i] = []
	for i: int in in_play.size():
		if in_play[i] == 0:
			continue
		var pixel: Vector2i = cell_of(i) + offset
		var inside: bool = (
			pixel.x >= 0 and pixel.y >= 0 and pixel.x < a_size.x and pixel.y < a_size.y
		)
		if not inside or is_painted[pixel.y * a_size.x + pixel.x] == 0:
			missing.append(pixel)
	if stray.is_empty() and missing.is_empty():
		return
	var message: String = (
		"terrain: the painted play area is not exactly a play diamond; the nearest is play_size %s"
		% play_size
	)
	if not stray.is_empty():
		message += (
			"; %d pixels painted beyond its edge: %s" % [stray.size(), describe_pixels(stray)]
		)
	if not missing.is_empty():
		message += (
			"; %d pixels inside it drawn out of play: %s"
			% [missing.size(), describe_pixels(missing)]
		)
	add_error(message, stray + missing)


func _resample(a_meanings: Dictionary, a_size: Vector2i) -> void:
	for layer: int in MapImagePalette.LAYER_NAMES:
		var out := PackedByteArray()
		out.resize(cell_count())
		var empty: int = (
			MapImagePalette.Meaning.OUT_OF_PLAY
			if layer == MapImagePalette.Layer.TERRAIN
			else MapImagePalette.Meaning.NONE
		)
		out.fill(empty)
		var source: PackedByteArray = a_meanings.get(layer, PackedByteArray())
		if not source.is_empty():
			for i: int in out.size():
				var pixel: Vector2i = cell_of(i) + offset
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < a_size.x and pixel.y < a_size.y:
					out[i] = source[pixel.y * a_size.x + pixel.x]
		match layer:
			MapImagePalette.Layer.TERRAIN:
				terrain = out
			MapImagePalette.Layer.WATER:
				water = out
			MapImagePalette.Layer.CLIFFS:
				cliffs = out
			MapImagePalette.Layer.STRUCTURES:
				structures = out


## Water, cliffs and structures may only be drawn in play, over ground: on the out-of-play
## colour they would describe something beyond the map, and water over a chasm would be a body
## with no bank to take its level from.
func _check_outside_play() -> void:
	var stray: Dictionary = {}
	for i: int in cell_count():
		var off_ground: bool = in_play[i] == 0 or terrain[i] == MapImagePalette.Meaning.CHASM
		for layer_name: String in ["water", "cliffs", "structures"]:
			var values: PackedByteArray = get(layer_name)
			if values[i] == MapImagePalette.Meaning.NONE:
				continue
			if in_play[i] == 0 or (layer_name != "cliffs" and off_ground):
				if not stray.has(layer_name):
					stray[layer_name] = [] as Array[Vector2i]
				stray[layer_name].append(pixel_of(cell_of(i)))
	for layer_name: String in stray:
		var pixels: Array[Vector2i] = stray[layer_name]
		add_error(
			(
				"%s: %d pixels drawn out of play or over a chasm: %s"
				% [layer_name, pixels.size(), describe_pixels(pixels)]
			),
			pixels
		)
#endregion
