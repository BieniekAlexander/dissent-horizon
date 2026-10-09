extends GutTest

## The minimap's per-pixel draw through the fog (MinimapCompositor): each pixel shows its cell's
## layer colour as the fog shows it, and a pixel with no cell under it, or one the fog has not
## revealed, shows OUT_OF_PLAY.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MinimapCompositor.gd -gexit

const LAYER_COLOR := Color(0.2, 0.6, 0.4)
## A 4x4 fog, one pixel per world unit, centred on the origin.
const FOG_SIZE: int = 4
const FOG_HALF: float = 2.0
## Three minimap pixels: over cell 0 at world (0, 0), over cell 0 at world (1, 1), and over no cell.
const CELLS: Array[int] = [0, 0, -1]
const WORLDS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 0.0)]

var _compositor: MinimapCompositor


func before_each() -> void:
	_compositor = MinimapCompositor.new()
	_compositor.set_palette(MinimapLayer.OUT_OF_PLAY, MinimapLayer.EXPLORED_DARKEN)
	_compositor.set_pixels(PackedInt32Array(CELLS), PackedVector2Array(WORLDS))
	_compositor.set_layer(PackedColorArray([LAYER_COLOR]))


func _pixel(a_bytes: PackedByteArray, a_index: int) -> Color:
	var at: int = a_index * 4
	return Color8(a_bytes[at], a_bytes[at + 1], a_bytes[at + 2], a_bytes[at + 3])


func _rgba8(a_color: Color) -> Color:
	return Color8(a_color.r8, a_color.g8, a_color.b8, 255)


## A fog with world (0, 0) in sight and world (1, 1) explored but out of sight.
func _fog() -> FogRaster:
	var raster := FogRaster.new()
	raster.configure(FOG_SIZE, FOG_SIZE, Vector2.ZERO, FOG_HALF, FOG_HALF, 1.0)
	raster.reveal_region(Vector2(1.0, 1.0), 0.5)
	raster.reveal_region(Vector2.ZERO, 0.5)
	var bytes: PackedByteArray = raster.fog_bytes()
	var centre: Vector2i = raster.world_to_pixel(Vector2.ZERO)
	bytes[centre.y * FOG_SIZE + centre.x] = 0
	raster.set_fog_bytes(bytes)
	return raster


func test_with_no_fog_nothing_is_seen() -> void:
	var bytes: PackedByteArray = _compositor.compose(null, false)
	assert_eq(bytes.size(), CELLS.size() * 4, "four bytes per pixel")
	for i: int in CELLS.size():
		assert_eq(_pixel(bytes, i), _rgba8(MinimapLayer.OUT_OF_PLAY))


func test_revealing_all_shows_every_cell_unchanged() -> void:
	var bytes: PackedByteArray = _compositor.compose(null, true)
	assert_eq(_pixel(bytes, 0), _rgba8(LAYER_COLOR))
	assert_eq(_pixel(bytes, 1), _rgba8(LAYER_COLOR))
	assert_eq(_pixel(bytes, 2), _rgba8(MinimapLayer.OUT_OF_PLAY), "no cell is never drawn")


func test_the_fog_decides_each_pixel() -> void:
	var bytes: PackedByteArray = _compositor.compose(_fog(), false)
	assert_eq(_pixel(bytes, 0), _rgba8(LAYER_COLOR), "in sight: unchanged")
	assert_eq(
		_pixel(bytes, 1),
		_rgba8(LAYER_COLOR.darkened(MinimapLayer.EXPLORED_DARKEN)),
		"explored: darkened"
	)
	assert_eq(_pixel(bytes, 2), _rgba8(MinimapLayer.OUT_OF_PLAY))


func test_an_unconfigured_fog_has_seen_nothing() -> void:
	var bytes: PackedByteArray = _compositor.compose(FogRaster.new(), false)
	assert_eq(_pixel(bytes, 0), _rgba8(MinimapLayer.OUT_OF_PLAY))
