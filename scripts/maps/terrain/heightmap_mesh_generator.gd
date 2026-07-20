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
	set(value): build()

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

	var cat := _catalog()
	if cat == null:
		sm.set_shader_parameter("tile_count", 0)
		return
	if cat != _tex_source_catalog or _tex_array == null:
		var built: Dictionary = cat.build_texture_array()
		_tex_array = built["array"]
		_tex_flags = built["flags"]
		_tex_source_catalog = cat
	if _tex_array == null:
		# Catalog present but no type has a texture yet — stay on flat colours.
		sm.set_shader_parameter("tile_count", 0)
		return
	sm.set_shader_parameter("tile_textures", _tex_array)
	sm.set_shader_parameter("tile_has_texture", _tex_flags)
	sm.set_shader_parameter("tile_count", cat.count())

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

func _build_mesh() -> ArrayMesh:
	var w: int = shape.map_width
	var d: int = shape.map_depth
	var hw: float = (w - 1) * 0.5
	var hd: float = (d - 1) * 0.5
	var gw: int = w - 1
	var gd: int = d - 1
	var data: PackedFloat32Array = shape.map_data

	# Each cell gets its own 4 vertices — no vertex sharing across cells — so tile boundaries are
	# hard-edged and every cell can carry its own per-vertex data with no bleed. The only cells
	# OMITTED (a literal geometry gap) are OUT-OF-PLAY cells, so the playable diamond reads against
	# the background. Non-passable obstacles (too-steep cells, or cliff/no-go tile types with
	# renders_surface = false) are still rendered, but as solid BLACK, so they don't show the
	# background through a hole (see the "void" sentinel below). Water/forest are impassable for
	# NAV yet rendered with their colour: passability and visibility are deliberately separate.
	#
	# Each cell bakes its tile identity into per-vertex data for the shader:
	#   * COLOR.rgb = the cell type's map_color (or black for a void cell).
	#   * COLOR.a   = the tile-type index / 255, sampled as a Texture2DArray layer — EXCEPT the
	#                 reserved value 1.0 (index 255), the "void" sentinel that forces flat black.
	#   * UV        = per-cell 0..1 (each cell samples a full texture once real texturing lands).
	#   * UV2       = global 0..1 across the whole map (kept for map-wide overlays: AO, minimap).
	var td: TerrainData = _terrain_data()

	var verts   := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var uv2s    := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors  := PackedColorArray()
	var indices := PackedInt32Array()

	for z in gd:
		for x in gw:
			var cell := Vector2i(x, z)
			# Out-of-play cells stay gaps (they're outside the map, so the play-area diamond edge
			# stays visible against the background rather than being framed in black).
			if td != null and not td.is_cell_in_play(cell):
				continue
			var h00: float = data[ z      * w + x    ]
			var h10: float = data[ z      * w + x + 1]
			var h11: float = data[(z + 1) * w + x + 1]
			var h01: float = data[(z + 1) * w + x    ]

			var spread: float = maxf(maxf(h00, h10), maxf(h11, h01)) \
							  - minf(minf(h00, h10), minf(h11, h01))

			# Non-passable OBSTACLES — a cliff/no-go tile type (renders_surface = false) or a cell
			# too steep to traverse — render as solid BLACK geometry rather than gaps, so they read
			# as black under fog / when unexplored instead of showing the background through a hole.
			# COLOR.a == 1.0 is the shader's "void" sentinel: skip texturing, keep COLOR.rgb (black).
			var is_void: bool = spread > MAX_SLOPE_DIFF \
							 or (td != null and not td.cell_renders_surface(cell))
			var col: Color
			if is_void:
				col = Color(0.0, 0.0, 0.0, 1.0)
			else:
				col = td.cell_map_color(cell) if td != null else TileType.DEFAULT_MAP_COLOR
				col.a = (td.tile_at(cell) if td != null else 0) / 255.0

			var base: int = verts.size()

			verts.append(Vector3(x     - hw, h00, z     - hd))
			verts.append(Vector3(x + 1 - hw, h10, z     - hd))
			verts.append(Vector3(x + 1 - hw, h11, z + 1 - hd))
			verts.append(Vector3(x     - hw, h01, z + 1 - hd))

			# Per-cell UVs: each cell spans the full 0..1 texture space.
			uvs.append(Vector2(0.0, 0.0))
			uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(1.0, 1.0))
			uvs.append(Vector2(0.0, 1.0))

			# Global UVs preserved in UV2 for whole-map overlays.
			uv2s.append(Vector2(float(x    ) / gw, float(z    ) / gd))
			uv2s.append(Vector2(float(x + 1) / gw, float(z    ) / gd))
			uv2s.append(Vector2(float(x + 1) / gw, float(z + 1) / gd))
			uv2s.append(Vector2(float(x    ) / gw, float(z + 1) / gd))

			colors.append(col)
			colors.append(col)
			colors.append(col)
			colors.append(col)

			var fn: Vector3 = (verts[base + 1] - verts[base]) \
							   .cross(verts[base + 3] - verts[base]).normalized()
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)

			indices.append_array([base, base+1, base+2, base, base+2, base+3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]   = verts
	arrays[Mesh.ARRAY_NORMAL]   = normals
	arrays[Mesh.ARRAY_TEX_UV]   = uvs
	arrays[Mesh.ARRAY_TEX_UV2]  = uv2s
	arrays[Mesh.ARRAY_COLOR]    = colors
	arrays[Mesh.ARRAY_INDEX]    = indices

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


## Walk up to the owning Map (the generator lives under Map/NavigationRegion/Body).
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
#endregion
