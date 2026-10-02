class_name TerrainShading
extends RefCounted

## The per-map inputs both terrain shaders read (terrain_common.gdshaderinc), derived from a
## TerrainData and pushed in one place so the two renderers cannot drift apart. Everything
## here is derived and rebuilt on demand; nothing is saved.

#region Constants
## Corner heights are stored one float per texel; mipmaps give the shader a free local mean.
const HEIGHT_FORMAT: Image.Format = Image.FORMAT_RF
#endregion


#region Public API
## Push cell identity, the height field and its range into `a_material`. `a_center` is the
## world XZ the cell grid is centred on (the owning Map's position).
static func push_terrain_uniforms(
	material: ShaderMaterial, data: TerrainData, center: Vector2
) -> void:
	if material == null or data == null:
		return
	var span := Vector2(float(data.grid_width()), float(data.grid_depth())) * Map.CELL_SIZE
	var origin: Vector2 = center - span * 0.5
	material.set_shader_parameter("cell_data", data.cell_data_texture())
	material.set_shader_parameter("terrain_rect", Vector4(origin.x, origin.y, span.x, span.y))
	var heights: ImageTexture = height_texture(data)
	if heights == null:
		material.set_shader_parameter("has_heights", 0.0)
		return
	# A corner sits ON a cell boundary, and texel centres are at half-texel offsets, so the
	# rect is grown by half a cell on every side for a corner to land on its texel's centre.
	var corners := Vector2(float(data.map_width()), float(data.map_depth())) * Map.CELL_SIZE
	var half_cell: float = Map.CELL_SIZE * 0.5
	material.set_shader_parameter("height_texture", heights)
	material.set_shader_parameter(
		"height_rect", Vector4(origin.x - half_cell, origin.y - half_cell, corners.x, corners.y)
	)
	material.set_shader_parameter("height_range", height_range(data.heights))
	material.set_shader_parameter("has_heights", 1.0)


## Hand the terrain material the pass-7 ground paint (see MapDecoration.ground_overlay), or
## clear it with null.
static func push_ground_overlay(material: ShaderMaterial, overlay: Image) -> void:
	if material == null:
		return
	if overlay == null:
		material.set_shader_parameter("has_overlay", 0.0)
		return
	material.set_shader_parameter("ground_overlay", ImageTexture.create_from_image(overlay))
	material.set_shader_parameter("has_overlay", 1.0)


## The corner heights as a mipmapped float texture, or null for a malformed heights layer.
static func height_texture(data: TerrainData) -> ImageTexture:
	var w: int = data.map_width()
	var d: int = data.map_depth()
	if w <= 0 or d <= 0 or data.heights.size() != w * d:
		return null
	var image := Image.create_from_data(w, d, false, HEIGHT_FORMAT, data.heights.to_byte_array())
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## (lowest, highest) of `heights`; (0, 0) when empty. A flat map's range is degenerate, which
## the shader guards against rather than this.
static func height_range(heights: PackedFloat32Array) -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var lo: float = heights[0]
	var hi: float = heights[0]
	for h: float in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return Vector2(lo, hi)
#endregion
