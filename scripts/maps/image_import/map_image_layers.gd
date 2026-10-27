@tool
class_name MapImageLayers
extends RefCounted

## A map drawing's layers, read from disk: one RGBA8 image per MapImagePalette.Layer, all the
## canvas size. What MapImageImporter classifies.
##
## Three formats (map-from-image.md §Layers and formats): `.ora` read directly (OpenRaster);
## `.aseprite` converted to an `.ora` beside it first (AsepriteFile); and flat PNGs, one per
## layer, named by suffix — `map.terrain.png`, `map.water.png` — any one of which names the set.
##
## A layer's own opacity, blend mode and visibility are view settings and are ignored: pixels
## are read as stored.

#region Constants
const PNG_SUFFIX: String = ".png"
#endregion

#region Properties
## Canvas size in pixels.
var size: Vector2i = Vector2i.ZERO
## MapImagePalette.Layer -> Image (FORMAT_RGBA8, `size`). A layer the drawing omits is absent.
var images: Dictionary = {}
## Why the drawing could not be read; non-empty means `images` must not be used.
var errors: PackedStringArray = PackedStringArray()
## Where an `.aseprite` source was converted to, or empty.
var converted_to: String = ""
#endregion


## Read the drawing at `path`, by its extension.
static func load_path(path: String) -> MapImageLayers:
	var extension: String = path.get_extension().to_lower()
	if extension == "ora":
		return OpenRaster.read(path)
	if extension == "aseprite" or extension == "ase":
		var ora_path: String = path.get_basename() + ".ora"
		var error: String = AsepriteFile.convert_to_ora(path, ora_path)
		if not error.is_empty():
			return failed(error)
		var layers: MapImageLayers = OpenRaster.read(ora_path)
		layers.converted_to = ora_path
		return layers
	if extension == "png":
		return _read_pngs(path)
	return failed("%s: not a drawing the importer reads (.ora, .aseprite or .png)" % path)


static func failed(message: String) -> MapImageLayers:
	var layers := MapImageLayers.new()
	layers.errors.append(message)
	return layers


## Add `image`, read as layer `name`, at `offset` on the canvas. A name the importer does not
## read fails the drawing rather than being skipped: a misnamed "Terrain 2" silently ignored
## would import a map without the author's terrain.
func add_named(name: String, image: Image, offset: Vector2i = Vector2i.ZERO) -> void:
	var layer: int = MapImagePalette.layer_named(name)
	if layer < 0:
		errors.append(
			(
				'layer "%s": not a layer the importer reads (%s); rename or delete it'
				% [name, ", ".join(MapImagePalette.LAYER_NAMES.values())]
			)
		)
		return
	if images.has(layer):
		errors.append('layer "%s" appears twice' % name)
		return
	image.convert(Image.FORMAT_RGBA8)
	if offset == Vector2i.ZERO and image.get_size() == size:
		images[layer] = image
		return
	var canvas := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
	images[layer] = canvas


func has_layer(layer: MapImagePalette.Layer) -> bool:
	return images.has(layer)


func is_valid() -> bool:
	return errors.is_empty() and images.has(MapImagePalette.Layer.TERRAIN)


## `map.terrain.png` and its siblings: every `<base>.<layer>.png` beside it.
static func _read_pngs(path: String) -> MapImageLayers:
	var file_name: String = path.get_file()
	var base: String = ""
	for layer_name: String in MapImagePalette.LAYER_NAMES.values():
		var suffix: String = "." + layer_name + PNG_SUFFIX
		if file_name.to_lower().ends_with(suffix):
			base = path.substr(0, path.length() - suffix.length())
	if base.is_empty():
		return failed(
			"%s: a flat PNG is named by its layer, as map.terrain.png, map.water.png …" % path
		)
	var layers := MapImageLayers.new()
	for layer_name: String in MapImagePalette.LAYER_NAMES.values():
		var layer_path: String = base + "." + layer_name + PNG_SUFFIX
		if not FileAccess.file_exists(layer_path):
			continue
		var image: Image = Image.load_from_file(layer_path)
		if image == null:
			layers.errors.append("%s: cannot be read as a PNG" % layer_path)
			continue
		if layers.size == Vector2i.ZERO:
			layers.size = image.get_size()
		elif image.get_size() != layers.size:
			layers.errors.append(
				"%s is %s, the other layers %s" % [layer_path, image.get_size(), layers.size]
			)
			continue
		layers.add_named(layer_name, image)
	if not layers.images.has(MapImagePalette.Layer.TERRAIN) and layers.errors.is_empty():
		layers.errors.append("%s.terrain.png: the terrain layer is required" % base)
	return layers
