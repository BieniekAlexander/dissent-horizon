@tool
class_name AsepriteFile
extends RefCounted

## Reads an `.aseprite` file's first frame into layers, with no Aseprite install: its cels are
## zlib-compressed pixel runs, which Godot's DEFLATE mode inflates (it is zlib-wrapped). The map
## importer converts a drawing to an OpenRaster file beside it and reads that, since Aseprite
## cannot export `.ora` itself (map-from-image.md §Layers and formats).
##
## The format, as Aseprite documents it (docs/ase-file-specs.md in its repository): a 128-byte
## header, then frames of chunks. Read here: layer chunks (0x2004), cel chunks (0x2005) and the
## palette (0x2019, or the old 0x0004) for indexed sprites. Group layers are skipped, so a layer
## nested in one is read by its own name; a tilemap layer fails the read.

#region Constants
const HEADER_MAGIC: int = 0xA5E0
const FRAME_MAGIC: int = 0xF1FA
const HEADER_BYTES: int = 128
const FRAME_HEADER_BYTES: int = 16
const CHUNK_HEADER_BYTES: int = 6
## Bytes of a cel chunk before its type-specific data.
const CEL_HEADER_BYTES: int = 16
const CHUNK_OLD_PALETTE: int = 0x0004
const CHUNK_LAYER: int = 0x2004
const CHUNK_CEL: int = 0x2005
const CHUNK_PALETTE: int = 0x2019
const LAYER_TYPE_IMAGE: int = 0
const LAYER_TYPE_TILEMAP: int = 2
const LAYER_FLAG_BACKGROUND: int = 8
const HEADER_FLAG_LAYER_UUID: int = 4
const UUID_BYTES: int = 16
const CEL_RAW: int = 0
const CEL_LINKED: int = 1
const CEL_COMPRESSED: int = 2
const PALETTE_ENTRY_HAS_NAME: int = 1
const DEPTH_RGBA: int = 32
const DEPTH_GRAYSCALE: int = 16
const DEPTH_INDEXED: int = 8
## The old palette chunk's colour count byte: 0 means a full 256.
const OLD_PALETTE_FULL: int = 256
## Offsets into the header of the fields read (the rest is skipped).
const HEADER_FLAGS_AT: int = 12
const HEADER_TRANSPARENT_AT: int = 28
#endregion


## Convert the Aseprite file at `source` to an OpenRaster file at `target`. Returns the reason it
## could not, or "".
static func convert_to_ora(source: String, target: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		return "%s: cannot be read" % source
	var decoded: Dictionary = decode(bytes)
	if not String(decoded.error).is_empty():
		return "%s: %s" % [source, decoded.error]
	var named: Array[Dictionary] = []
	named.assign(decoded.layers)
	# Aseprite lists layers bottom first; OpenRaster's stack is topmost first.
	named.reverse()
	if OpenRaster.write(target, decoded.size, named) != OK:
		return "%s: cannot be written" % target
	return ""


## The first frame of an Aseprite file: {size: Vector2i, layers: Array of {name, image}, error}.
## `error` is "" when the file was read; each image is canvas-sized RGBA8.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var out: Dictionary = {size = Vector2i.ZERO, layers = [], error = ""}
	if bytes.size() < HEADER_BYTES:
		out.error = "too short to be an Aseprite file"
		return out
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.seek(4)
	if stream.get_u16() != HEADER_MAGIC:
		out.error = "not an Aseprite file (bad magic number)"
		return out
	var frames: int = stream.get_u16()
	var size := Vector2i(stream.get_u16(), stream.get_u16())
	var depth: int = stream.get_u16()
	stream.seek(HEADER_FLAGS_AT)
	var header_flags: int = stream.get_u32()
	stream.seek(HEADER_TRANSPARENT_AT)
	var transparent_index: int = stream.get_u8()
	out.size = size
	if frames < 1:
		out.error = "has no frames"
		return out
	if depth not in [DEPTH_RGBA, DEPTH_GRAYSCALE, DEPTH_INDEXED]:
		out.error = "colour depth %d is not one Aseprite writes" % depth
		return out

	stream.seek(HEADER_BYTES)
	var frame_start: int = stream.get_position()
	var frame_bytes: int = stream.get_u32()
	if stream.get_u16() != FRAME_MAGIC:
		out.error = "first frame is corrupt (bad magic number)"
		return out
	var old_chunks: int = stream.get_u16()
	stream.get_u16()  # duration
	stream.get_u16()  # reserved
	var new_chunks: int = stream.get_u32()
	var chunk_count: int = new_chunks if new_chunks != 0 else old_chunks

	## Every layer in chunk order, which is what a cel's layer index counts: {name, kind, flags}.
	var layers: Array[Dictionary] = []
	var cels: Array[Dictionary] = []
	var palette: PackedColorArray = PackedColorArray()
	stream.seek(frame_start + FRAME_HEADER_BYTES)
	for _chunk: int in chunk_count:
		var chunk_start: int = stream.get_position()
		var chunk_size: int = stream.get_u32()
		var chunk_type: int = stream.get_u16()
		if chunk_size < CHUNK_HEADER_BYTES or chunk_start + chunk_size > frame_start + frame_bytes:
			out.error = "a chunk runs past its frame"
			return out
		match chunk_type:
			CHUNK_LAYER:
				layers.append(_read_layer(stream, header_flags))
			CHUNK_CEL:
				var cel: Dictionary = _read_cel(stream, chunk_start + chunk_size, depth, bytes)
				if not String(cel.get("error", "")).is_empty():
					out.error = cel.error
					return out
				cels.append(cel)
			CHUNK_PALETTE:
				palette = _read_palette(stream, palette)
			CHUNK_OLD_PALETTE:
				if palette.is_empty():
					palette = _read_old_palette(stream)
		stream.seek(chunk_start + chunk_size)

	var images: Dictionary = {}
	for cel: Dictionary in cels:
		var layer_index: int = cel.layer
		if layer_index < 0 or layer_index >= layers.size():
			out.error = "a cel names layer %d, which does not exist" % layer_index
			return out
		var layer: Dictionary = layers[layer_index]
		if layer.kind == LAYER_TYPE_TILEMAP:
			out.error = (
				'layer "%s" is a tilemap layer, which the importer does not read' % layer.name
			)
			return out
		var is_background: bool = layer.flags & LAYER_FLAG_BACKGROUND != 0
		var cel_image: Image = _to_rgba(
			cel.pixels, cel.size, depth, palette, -1 if is_background else transparent_index
		)
		var canvas := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(cel_image, Rect2i(Vector2i.ZERO, cel.size), cel.position)
		images[layer_index] = canvas
	for index: int in layers.size():
		if layers[index].kind != LAYER_TYPE_IMAGE:
			continue
		# A layer with no cel in the first frame is empty, not absent.
		var image: Image = images.get(
			index, Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		)
		out.layers.append({name = layers[index].name, image = image})
	return out


static func _read_layer(stream: StreamPeerBuffer, header_flags: int) -> Dictionary:
	var flags: int = stream.get_u16()
	var kind: int = stream.get_u16()
	stream.get_u16()  # child level
	stream.get_u16()  # default width
	stream.get_u16()  # default height
	stream.get_u16()  # blend mode
	stream.get_u8()  # opacity
	stream.get_data(3)
	var name: String = _read_string(stream)
	if header_flags & HEADER_FLAG_LAYER_UUID != 0:
		stream.get_data(UUID_BYTES)
	return {name = name, kind = kind, flags = flags}


static func _read_cel(
	stream: StreamPeerBuffer, chunk_end: int, depth: int, bytes: PackedByteArray
) -> Dictionary:
	var layer: int = stream.get_u16()
	var position := Vector2i(stream.get_16(), stream.get_16())
	stream.get_u8()  # opacity: a view setting, ignored like the layer's
	var cel_type: int = stream.get_u16()
	stream.get_16()  # z-index
	stream.get_data(5)
	if cel_type == CEL_LINKED:
		return {error = "a cel in the first frame is linked; unlink it in Aseprite"}
	if cel_type != CEL_RAW and cel_type != CEL_COMPRESSED:
		return {error = "a cel of type %d is not an image (tilemap cels are not read)" % cel_type}
	var size := Vector2i(stream.get_u16(), stream.get_u16())
	var expected: int = size.x * size.y * (depth / 8)
	var data: PackedByteArray = bytes.slice(stream.get_position(), chunk_end)
	if cel_type == CEL_COMPRESSED:
		data = data.decompress(expected, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != expected:
		return {error = "a cel of layer %d holds %d bytes, not %d" % [layer, data.size(), expected]}
	return {layer = layer, position = position, size = size, pixels = data}


## The 0x2019 palette chunk, applied over what was read before it.
static func _read_palette(stream: StreamPeerBuffer, palette: PackedColorArray) -> PackedColorArray:
	var total: int = stream.get_u32()
	var first: int = stream.get_u32()
	var last: int = stream.get_u32()
	stream.get_data(8)
	var out := palette.duplicate()
	if out.size() < total:
		out.resize(total)
	for index: int in range(first, last + 1):
		var entry_flags: int = stream.get_u16()
		var color := Color8(stream.get_u8(), stream.get_u8(), stream.get_u8(), stream.get_u8())
		if entry_flags & PALETTE_ENTRY_HAS_NAME != 0:
			_read_string(stream)
		if index < out.size():
			out[index] = color
	return out


static func _read_old_palette(stream: StreamPeerBuffer) -> PackedColorArray:
	var out := PackedColorArray()
	var packets: int = stream.get_u16()
	var index: int = 0
	for _packet: int in packets:
		index += stream.get_u8()
		var count: int = stream.get_u8()
		if count == 0:
			count = OLD_PALETTE_FULL
		for _i: int in count:
			if out.size() <= index:
				out.resize(index + 1)
			out[index] = Color8(stream.get_u8(), stream.get_u8(), stream.get_u8())
			index += 1
	return out


static func _read_string(stream: StreamPeerBuffer) -> String:
	var length: int = stream.get_u16()
	return stream.get_data(length)[1].get_string_from_utf8() if length > 0 else ""


## A cel's pixels as RGBA8. `transparent_index` is the indexed sprite's see-through entry, or -1
## on a background layer, where it is an ordinary colour.
static func _to_rgba(
	pixels: PackedByteArray,
	size: Vector2i,
	depth: int,
	palette: PackedColorArray,
	transparent_index: int
) -> Image:
	if depth == DEPTH_RGBA:
		return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, pixels)
	var rgba := PackedByteArray()
	rgba.resize(size.x * size.y * 4)
	for i: int in size.x * size.y:
		var color: Color
		if depth == DEPTH_GRAYSCALE:
			var value: int = pixels[i * 2]
			color = Color8(value, value, value, pixels[i * 2 + 1])
		elif pixels[i] == transparent_index:
			color = Color(0, 0, 0, 0)
		else:
			color = palette[pixels[i]] if pixels[i] < palette.size() else Color(0, 0, 0, 0)
		rgba[i * 4] = color.r8
		rgba[i * 4 + 1] = color.g8
		rgba[i * 4 + 2] = color.b8
		rgba[i * 4 + 3] = color.a8
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, rgba)
