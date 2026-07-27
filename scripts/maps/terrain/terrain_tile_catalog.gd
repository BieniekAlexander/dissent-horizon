@tool
class_name TerrainTileCatalog
extends Resource

## The "palette" of ground materials: an ordered list of TileType definitions where the list
## INDEX is the byte a cell stores in TerrainData.tile_types. Stored as its own standalone
## .tres (resources/terrain/tile_catalog.tres) so types can be added/tuned as data without
## code changes — the same split as Godot's TileMap (per-cell ids) + TileSet (definitions).
##
## Convention: index 0 is the default material, so a zero-filled tile_types array (or a cell
## out of range) reads as that.

## Byte index -> TileType. Index 0 is the default material.
@export var types: Array[TileType] = []

## The default material index used for unspecified / out-of-range cells.
const DEFAULT_INDEX: int = 0


func count() -> int:
	return types.size()


func _type_or_null(a_i: int) -> TileType:
	return types[a_i] if a_i >= 0 and a_i < types.size() else null


## The flat albedo for type `i` (see TileType.map_color). Unknown/out-of-range indices fall
## back to the shared default open-ground colour.
func map_color(a_i: int) -> Color:
	var t: TileType = _type_or_null(a_i)
	return t.map_color if t != null else TileType.DEFAULT_MAP_COLOR


## Every type's flat colour, indexed by tile index — the palette TerrainSurface hands the
## terrain shader as `tile_colors`. Padded to `size` so the shader's fixed-length array is
## fully defined; unfilled slots take the default open-ground colour rather than black, so an
## out-of-range index degrades to ground the same way map_color() does.
func map_color_array(a_size: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(a_size)
	for i: int in a_size:
		out[i] = map_color(i) if i < types.size() else TileType.DEFAULT_MAP_COLOR
	return out


## Per-type "has a real texture" flags, indexed by tile index, padded to `size`.
func texture_flag_array(a_size: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a_size)
	for i: int in a_size:
		var t: TileType = _type_or_null(i)
		out[i] = 1.0 if t != null and t.texture != null else 0.0
	return out


## Side length (px) every type texture is normalised to when packed into the Texture2DArray.
## All layers of a Texture2DArray must share size, format, and mipmap state.
const TILE_TEXTURE_SIZE: int = 256


## Pack every type's `texture` into a Texture2DArray whose LAYER index equals the tile-type
## index — so the terrain shader samples layer = the per-vertex index baked into COLOR.a.
## Types with no texture get an opaque-white placeholder layer (kept so indices stay aligned)
## and are reported as un-textured in `flags`, so the shader falls back to their map_color.
## Returns { "array": Texture2DArray | null, "flags": PackedFloat32Array } (parallel to
## `types`); a null array means "no textures at all — use flat colours everywhere".
func build_texture_array() -> Dictionary:
	var images: Array[Image] = []
	var flags := PackedFloat32Array()
	var any_texture: bool = false
	for t: TileType in types:
		if t != null and t.texture != null:
			images.append(_normalized_image(t.texture))
			flags.append(1.0)
			any_texture = true
		else:
			images.append(_blank_image())
			flags.append(0.0)
	if not any_texture:
		return {"array": null, "flags": flags}
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return {"array": arr, "flags": flags}


## A type texture converted to the common size / format / mipmap state the array requires.
func _normalized_image(a_tex: Texture2D) -> Image:
	var img: Image = a_tex.get_image()
	if img == null:
		return _blank_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != TILE_TEXTURE_SIZE or img.get_height() != TILE_TEXTURE_SIZE:
		img.resize(TILE_TEXTURE_SIZE, TILE_TEXTURE_SIZE)
	if img.has_mipmaps():
		img.clear_mipmaps()
	return img


## Opaque-white placeholder layer for a type with no texture (white so, if a shader ever
## multiplies texture * map_color, the colour passes through unchanged).
func _blank_image() -> Image:
	var img := Image.create_empty(TILE_TEXTURE_SIZE, TILE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return img
