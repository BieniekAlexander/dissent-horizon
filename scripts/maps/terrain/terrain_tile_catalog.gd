@tool
class_name TerrainTileCatalog
extends Resource

## The "palette" of tile types: an ordered list of TileType definitions where the list
## INDEX is the byte a cell stores in TerrainData.tile_types. Stored as its own standalone
## .tres (resources/terrain/tile_catalog.tres) so types can be added/tuned as data without
## code changes — the same split as Godot's TileMap (per-cell ids) + TileSet (definitions).
##
## Convention: index 0 is the default passable "Open" type, so a zero-filled tile_types
## array (or a cell out of range) reads as open ground.

## Byte index -> TileType. Index 0 should be the default "Open" type.
@export var types: Array[TileType] = []

## The default (Open) index used for unspecified / out-of-range cells.
const DEFAULT_INDEX: int = 0


func count() -> int:
	return types.size()


## Index of the first impassable type (used as the "NoGo" target when an editor toggle
## blocks a cell), or -1 if every type is passable.
func first_impassable_index() -> int:
	for i: int in types.size():
		if not types[i].passable:
			return i
	return -1


func _type_or_null(i: int) -> TileType:
	return types[i] if i >= 0 and i < types.size() else null


## Whether a cell of type `i` is traversable. Unknown/out-of-range indices fall back
## to the default (open) behaviour so a malformed map degrades to passable rather than
## walling everything off.
func passable(i: int) -> bool:
	var t: TileType = _type_or_null(i)
	return t.passable if t != null else true


## Whether a cell of type `i` permits structures (before the flat-ground check).
func buildable(i: int) -> bool:
	var t: TileType = _type_or_null(i)
	return t.buildable if t != null else true


## Whether a cell of type `i` contributes surface geometry to the visual mesh (see
## TileType.renders_surface). Unknown/out-of-range indices fall back to `true` (rendered),
## matching passable()'s "degrade to normal ground" convention.
func renders_surface(i: int) -> bool:
	var t: TileType = _type_or_null(i)
	return t.renders_surface if t != null else true


## The flat albedo for type `i` (see TileType.map_color). Unknown/out-of-range indices fall
## back to the shared default open-ground colour.
func map_color(i: int) -> Color:
	var t: TileType = _type_or_null(i)
	return t.map_color if t != null else TileType.DEFAULT_MAP_COLOR


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
func _normalized_image(tex: Texture2D) -> Image:
	var img: Image = tex.get_image()
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
