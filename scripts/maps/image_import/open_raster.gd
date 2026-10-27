@tool
class_name OpenRaster
extends RefCounted

## OpenRaster (`.ora`): a zip holding `mimetype`, a `stack.xml` listing the layers and one PNG
## per layer. Read for the map importer, and written when an `.aseprite` drawing is converted,
## since Aseprite cannot export one itself (map-from-image.md §Layers and formats).
##
## Only what a map drawing needs: a flat stack of raster layers, each at an offset. Nested
## stacks are read through; a layer's opacity, visibility and composite op are ignored.

#region Constants
const MIMETYPE: String = "image/openraster"
const STACK_FILE: String = "stack.xml"
const MIMETYPE_FILE: String = "mimetype"
const LAYER_DIR: String = "data/"
#endregion


static func read(path: String) -> MapImageLayers:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return MapImageLayers.failed("%s: cannot be opened as an OpenRaster zip" % path)
	var layers := MapImageLayers.new()
	if not zip.file_exists(STACK_FILE):
		zip.close()
		return MapImageLayers.failed("%s: no %s, so not an OpenRaster file" % [path, STACK_FILE])
	var parser := XMLParser.new()
	parser.open_buffer(zip.read_file(STACK_FILE))
	var listed: Array[Dictionary] = []
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var element: String = parser.get_node_name()
		if element == "image":
			layers.size = Vector2i(
				int(parser.get_named_attribute_value_safe("w")),
				int(parser.get_named_attribute_value_safe("h"))
			)
		elif element == "layer":
			(
				listed
				. append(
					{
						name = parser.get_named_attribute_value_safe("name"),
						src = parser.get_named_attribute_value_safe("src"),
						offset =
						Vector2i(
							int(parser.get_named_attribute_value_safe("x")),
							int(parser.get_named_attribute_value_safe("y"))
						),
					}
				)
			)
	for entry: Dictionary in listed:
		if not zip.file_exists(entry.src):
			layers.errors.append(
				'%s: layer "%s" names a missing %s' % [path, entry.name, entry.src]
			)
			continue
		var image := Image.new()
		if image.load_png_from_buffer(zip.read_file(entry.src)) != OK:
			layers.errors.append('%s: layer "%s" is not a readable PNG' % [path, entry.name])
			continue
		if layers.size == Vector2i.ZERO:
			layers.size = image.get_size()
		layers.add_named(entry.name, image, entry.offset)
	zip.close()
	if layers.errors.is_empty() and not layers.has_layer(MapImagePalette.Layer.TERRAIN):
		layers.errors.append('%s: no layer named "terrain", which every map needs' % path)
	return layers


## Write `named_layers` — {name: String, image: Image} each, canvas-sized, topmost first as
## stack.xml lists them — as an OpenRaster file at `path`.
static func write(path: String, canvas: Vector2i, named_layers: Array[Dictionary]) -> Error:
	var zip := ZIPPacker.new()
	var error: Error = zip.open(path)
	if error != OK:
		return error
	# The spec wants `mimetype` first and stored, so a reader can sniff the type unzipped.
	zip.compression_level = ZIPPacker.COMPRESSION_NONE
	zip.start_file(MIMETYPE_FILE)
	zip.write_file(MIMETYPE.to_ascii_buffer())
	zip.close_file()
	zip.compression_level = ZIPPacker.COMPRESSION_DEFAULT
	var stack: String = (
		'<?xml version="1.0" encoding="UTF-8"?>\n<image version="0.0.3" w="%d" h="%d">\n<stack>\n'
		% [canvas.x, canvas.y]
	)
	for i: int in named_layers.size():
		var src: String = LAYER_DIR + "layer%d.png" % i
		stack += (
			'<layer name="%s" src="%s" x="0" y="0" opacity="1.0" visibility="visible"/>\n'
			% [String(named_layers[i].name).xml_escape(true), src]
		)
		zip.start_file(src)
		zip.write_file((named_layers[i].image as Image).save_png_to_buffer())
		zip.close_file()
	stack += "</stack>\n</image>\n"
	zip.start_file(STACK_FILE)
	zip.write_file(stack.to_utf8_buffer())
	zip.close_file()
	return zip.close()
