@tool
class_name TerrainSurface
extends MeshInstance3D

## Draws Map.terrain_source_mesh as the terrain — the AUTHORED surface itself, rather than the
## quad-per-cell mesh HeightmapMeshGenerator derives from the heightfield.
##
## The two are alternatives, not layers, and which one a map uses follows from how its terrain
## was authored:
##
##   * brush-sculpted heights  -> HeightmapMeshGenerator (there is no other surface to draw)
##   * a modelled source mesh  -> this (the heightfield is a derived gameplay artifact, and
##                                drawing it would throw away the geometry it was baked from)
##
## Nothing arbitrates between them: a scene carries whichever node it needs. Keeping them as
## separate nodes rather than one node with a mode is what leaves every existing brush-authored
## scene untouched.
##
## WHAT THIS FIXES. The heightfield is the gameplay resolution — one cell, one quad, one flat
## normal — so drawing it renders a curve as a staircase and a modelled cliff as a flight of
## steps. The surface mesh is the geometry that was actually authored, so a dome is round and a
## vertical wall is vertical. The grid is unaffected: it still decides passability, placement
## and navigation at cell resolution, which is where a grid belongs.
##
## Tile identity, play bounds and cliff shading are the three things a source mesh cannot carry
## in its own vertices; terrain_surface.gdshader explains how each is recovered.

#region Constants
## Length of the shader's fixed-size per-tile-type arrays (a tile index is one byte).
const MAX_TILE_TYPES: int = 256
#endregion

#region Properties
## Explicit TerrainData. Normally left null: under a Map, that Map's terrain_data is used.
@export var terrain_data_override: TerrainData

## Explicit surface mesh. Normally left null: under a Map, that Map's terrain_source_mesh is
## drawn. Same override idiom as terrain_data_override, for building standalone.
@export var source_mesh_override: Mesh

## The terrain material. Expected to be a ShaderMaterial running terrain_surface.gdshader;
## anything else is applied unchanged and simply receives no parameters.
@export var material: Material:
	set(v):
		material = v
		if is_node_ready():
			refresh()

## Inspector trigger: re-read the terrain and push everything to the material.
@export var rebuild: bool:
	set(_v): refresh()
#endregion

#region Lifecycle
func _ready() -> void:
	refresh()
#endregion

#region Public API
## Adopt the terrain's source mesh and push every shader parameter derived from the terrain.
func refresh() -> void:
	var data: TerrainData = _terrain_data()
	if data == null:
		return
	var surface: Mesh = _source_mesh()
	if surface == null:
		push_warning("TerrainSurface: no surface mesh — set the Map's terrain_source_mesh")
		return
	mesh = surface
	material_override = material
	_push_parameters(data)


## The mesh to draw: the explicit override if set, else the owning Map's terrain_source_mesh.
func _source_mesh() -> Mesh:
	if source_mesh_override != null:
		return source_mesh_override
	var map: Map = _find_map()
	return map.terrain_source_mesh if map != null else null


## Point the shader's fog uniforms at a Fog driver's texture. Mirrors what the generated-mesh
## path does; separated so a scene with no fog simply never calls it.
func set_fog(a_texture: Texture2D, a_rect: Vector4) -> void:
	var sm := material as ShaderMaterial
	if sm == null:
		return
	sm.set_shader_parameter("fog_texture", a_texture)
	sm.set_shader_parameter("fog_rect", a_rect)
	sm.set_shader_parameter("fog_enabled", 1.0 if a_texture != null else 0.0)
#endregion

#region Private helpers
func _push_parameters(a_data: TerrainData) -> void:
	var sm := material as ShaderMaterial
	if sm == null:
		return

	sm.set_shader_parameter("cell_data", a_data.cell_data_texture())

	# World-XZ rectangle the cell grid covers, so the shader can turn a world position into a
	# cell lookup. Derived the same way Map.world_bounds does: a W-corner grid spans W-1 cells.
	var map: Map = _find_map()
	var center: Vector2 = VU.inXZ(map.global_position) if map != null else Vector2.ZERO
	var span := Vector2(float(a_data.grid_width()), float(a_data.grid_depth())) * Map.CELL_SIZE
	sm.set_shader_parameter("terrain_rect",
		Vector4(center.x - span.x * 0.5, center.y - span.y * 0.5, span.x, span.y))

	var catalog: TerrainTileCatalog = a_data.catalog
	if catalog != null:
		sm.set_shader_parameter("tile_colors", catalog.map_color_array(MAX_TILE_TYPES))
		sm.set_shader_parameter("tile_has_texture", catalog.texture_flag_array(MAX_TILE_TYPES))
		var built: Dictionary = catalog.build_texture_array()
		var array: Texture2DArray = built["array"]
		sm.set_shader_parameter("tile_textures", array)
		sm.set_shader_parameter("tile_count", catalog.count() if array != null else 0)
	else:
		sm.set_shader_parameter("tile_colors",
			TerrainTileCatalog.new().map_color_array(MAX_TILE_TYPES))
		sm.set_shader_parameter("tile_count", 0)

	_push_play_bounds(a_data, center)


## The play rectangle in its own frame. Handed over as centre + axes + half-extents rather than
## as a Rect2 because it is a 45-degree rotated rectangle in world XZ — the same reason
## PlayArea exists — and the shader can then test it with two dot products.
func _push_play_bounds(a_data: TerrainData, a_center: Vector2) -> void:
	var sm := material as ShaderMaterial
	var half_st: Vector2 = a_data.play_half_extents()
	if half_st == Vector2.ZERO:
		sm.set_shader_parameter("play_bounds_enabled", 0.0)
		return
	var area: PlayArea = PlayArea.screen_aligned(a_center, half_st, Map.CELL_SIZE)
	sm.set_shader_parameter("play_center", area.center)
	sm.set_shader_parameter("play_axis_a", area.axis_a)
	sm.set_shader_parameter("play_axis_b", area.axis_b)
	sm.set_shader_parameter("play_half", area.half)
	sm.set_shader_parameter("play_bounds_enabled", 1.0)


func _terrain_data() -> TerrainData:
	if terrain_data_override != null:
		return terrain_data_override
	var map: Map = _find_map()
	return map.terrain_data if map != null else null


func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
#endregion
