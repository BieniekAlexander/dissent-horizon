@tool
class_name HeightmapMeshGenerator
extends Node3D

## Generates a triangulated ArrayMesh from a HeightMapShape3D and attaches it
## as a MeshInstance3D child named "GeneratedMesh".
##
## Vertex positions are in HeightMapShape3D local space — one unit per corner —
## so this node must be placed under the same StaticBody3D as the collision
## shape to inherit its scale and get correct world-space sizing.
##
## Workflow:
##   1. Assign `shape` in the inspector.
##   2. Click "Build Mesh" to generate.
##   3. Right-click the `mesh` property → Save to write it to a .tres file.

#region Constants
## Mirrors TerrainGrid.MAX_SLOPE_DIFF — cells steeper than this are impassable.
const MAX_SLOPE_DIFF: float = 0.5
#endregion

#region Properties
@export var shape: HeightMapShape3D:
	set(v):
		shape = v
		if is_node_ready():
			build()

@export var material: Material:
	set(v):
		material = v
		_apply_to_instance()

## The generated mesh.  Populated by clicking "Build Mesh".
## Right-click this property in the inspector to save it as a .tres resource.
@export var mesh: ArrayMesh:
	set(v):
		mesh = v
		_apply_to_instance()

## Click to rebuild the mesh from the current `shape`.
@export var run_build: bool:
	set(value):
		build()

## Optional explicit TerrainData. When set, it is used instead of walking up to the owning
## Map — so the generator can build standalone (editor tools, previews, tests) with no Map
## ancestor. Normally left null: under a Map it reads that Map's terrain_data.
@export var terrain_data_override: TerrainData
#endregion


#region Lifecycle
func _ready() -> void:
	if shape != null:
		build()
	else:
		_apply_to_instance()


#endregion


#region Public API
## Build the mesh from the current `shape` and store it in `mesh`.
func build() -> void:
	if shape == null:
		push_warning("HeightmapMeshGenerator: no shape assigned")
		return
	mesh = _build_mesh()
	if material != null:
		mesh.surface_set_material(0, material)
	_sync_shader_params()


#endregion

#region Private helpers
## Cache for the packed tile Texture2DArray so a live brush rebuild (which re-runs build()
## every mouse motion) doesn't re-decode/resize every type texture each time. Keyed on the
## catalog instance — painting tile types never changes the catalog or its textures, so the
## cache stays valid across a stroke; a different catalog (or first build) refills it.
var _tex_source_catalog: TerrainTileCatalog = null
var _tex_array: Texture2DArray = null
var _tex_flags: PackedFloat32Array = PackedFloat32Array()


## Push the terrain shader's parameters: the tile Texture2DArray + per-layer "has texture"
## flags (so the shader samples a real texture where one exists and falls back to the baked
## flat map_color elsewhere) and, for back-compat, the heightmap cell counts. No-op when the
## material isn't a ShaderMaterial; parameters the shader doesn't declare are simply ignored.
func _sync_shader_params() -> void:
	var sm := material as ShaderMaterial
	if sm == null:
		return
	if shape != null:
		sm.set_shader_parameter("grid_width", shape.map_width - 1)
		sm.set_shader_parameter("grid_depth", shape.map_depth - 1)

	var td: TerrainData = _terrain_data()
	if td != null:
		TerrainShading.push_terrain_uniforms(sm, td, _grid_center())
	var cat := _catalog()
	if cat == null:
		sm.set_shader_parameter("tile_count", 0)
		return
	if cat != _tex_source_catalog or _tex_array == null:
		var built: Dictionary = cat.build_texture_array()
		_tex_array = built["array"]
		_tex_flags = built["flags"]
		_tex_source_catalog = cat
	sm.set_shader_parameter("tile_colors", cat.map_color_array(TerrainSurface.MAX_TILE_TYPES))
	if _tex_array == null:
		# Catalog present but no type has a texture yet — stay on flat colours.
		sm.set_shader_parameter("tile_count", 0)
		return
	sm.set_shader_parameter("tile_colors", cat.map_color_array(TerrainSurface.MAX_TILE_TYPES))
	sm.set_shader_parameter("tile_textures", _tex_array)
	sm.set_shader_parameter("tile_has_texture", _tex_flags)
	sm.set_shader_parameter("tile_count", cat.count())


## World XZ the cell grid is centred on: this node's position (it sits at the terrain body's
## origin, which is the Map's), or the origin while out of the tree.
func _grid_center() -> Vector2:
	return VU.inXZ(global_position) if is_inside_tree() else Vector2.ZERO


## The active tile catalog (from the override or the owning Map), or null when neither.
func _catalog() -> TerrainTileCatalog:
	var td := _terrain_data()
	return td.catalog if td != null else null


## The TerrainData driving this build: the explicit override if set, else the owning Map's.
func _terrain_data() -> TerrainData:
	if terrain_data_override != null:
		return terrain_data_override
	var map := _find_map()
	return map.terrain_data if map != null else null


func _apply_to_instance() -> void:
	var mi: MeshInstance3D = get_node_or_null("GeneratedMesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "GeneratedMesh"
		add_child(mi)
	mi.mesh = mesh
	mi.material_override = material
	_sync_shader_params()


## One quad per cell, with its own four vertices — no sharing, so tile boundaries are hard
## and every cell carries its own per-vertex data. What the three cell fates are (gap, black
## obstacle, ordinary surface) and what the four vertex channels mean:
## gdd/systems/terrain-and-navigation/tile-types.md §How a cell reaches the shader.
func _build_mesh() -> ArrayMesh:
	var w: int = shape.map_width
	var d: int = shape.map_depth
	var hw: float = (w - 1) * 0.5
	var hd: float = (d - 1) * 0.5
	var gw: int = w - 1
	var gd: int = d - 1
	var data: PackedFloat32Array = shape.map_data
	var td: TerrainData = _terrain_data()

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for z in gd:
		for x in gw:
			var cell := Vector2i(x, z)
			# Out-of-play cells (void included) stay gaps, so the play-area edge reads against
			# the background rather than being framed in black.
			if td != null and not td.is_cell_in_play(cell):
				continue
			var h00: float = data[z * w + x]
			var h10: float = data[z * w + x + 1]
			var h11: float = data[(z + 1) * w + x + 1]
			var h01: float = data[(z + 1) * w + x]
			var col: Color = _cell_color(td, cell, _corner_spread(h00, h10, h11, h01))
			var base: int = verts.size()

			verts.append(Vector3(x - hw, h00, z - hd))
			verts.append(Vector3(x + 1 - hw, h10, z - hd))
			verts.append(Vector3(x + 1 - hw, h11, z + 1 - hd))
			verts.append(Vector3(x - hw, h01, z + 1 - hd))

			# Per-cell UVs: each cell spans the full 0..1 texture space.
			uvs.append(Vector2(0.0, 0.0))
			uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(1.0, 1.0))
			uvs.append(Vector2(0.0, 1.0))

			# Global UVs preserved in UV2 for whole-map overlays.
			uv2s.append(Vector2(float(x) / gw, float(z) / gd))
			uv2s.append(Vector2(float(x + 1) / gw, float(z) / gd))
			uv2s.append(Vector2(float(x + 1) / gw, float(z + 1) / gd))
			uv2s.append(Vector2(float(x) / gw, float(z + 1) / gd))

			colors.append(col)
			colors.append(col)
			colors.append(col)
			colors.append(col)

			# (+z edge) x (+x edge) is the UPWARD normal; the reverse order points into the
			# ground and leaves every lit material black under a sun.
			var fn: Vector3 = (
				(verts[base + 3] - verts[base]).cross(verts[base + 1] - verts[base]).normalized()
			)
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)

			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


## The height difference across a cell's four corners — what MAX_SLOPE_DIFF is compared
## against to call the cell too steep to traverse.
static func _corner_spread(h00: float, h10: float, h11: float, h01: float) -> float:
	return maxf(maxf(h00, h10), maxf(h11, h01)) - minf(minf(h00, h10), minf(h11, h01))


## The per-vertex COLOR for one cell: its ground material's map colour with the type index
## packed into alpha, or the cliff sentinel (black, alpha 1.0) for a cell too steep to walk.
## A void cell never reaches here — it is out of play, so the caller omits it.
func _cell_color(a_terrain_data: TerrainData, a_cell: Vector2i, a_spread: float) -> Color:
	if a_spread > MAX_SLOPE_DIFF:
		return Color(0.0, 0.0, 0.0, 1.0)
	var col: Color = (
		a_terrain_data.cell_map_color(a_cell)
		if a_terrain_data != null
		else TileType.DEFAULT_MAP_COLOR
	)
	col.a = (a_terrain_data.tile_at(a_cell) if a_terrain_data != null else 0) / 255.0
	return col


## Walk up to the owning Map (the generator lives under Map/NavigationRegion/Body).
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
#endregion
