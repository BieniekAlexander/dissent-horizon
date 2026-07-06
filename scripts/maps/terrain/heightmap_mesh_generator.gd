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
	_sync_shader_grid()
#endregion

#region Private helpers
## Keep the checkerboard shader's cell count in lockstep with the heightmap so
## each grid cell renders as exactly one checker square.  No-op when the material
## isn't a ShaderMaterial (the parameters are simply ignored if absent).
func _sync_shader_grid() -> void:
	var sm := material as ShaderMaterial
	if sm == null or shape == null:
		return
	sm.set_shader_parameter("grid_width", shape.map_width - 1)
	sm.set_shader_parameter("grid_depth", shape.map_depth - 1)

func _apply_to_instance() -> void:
	var mi: MeshInstance3D = get_node_or_null("GeneratedMesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "GeneratedMesh"
		add_child(mi)
	mi.mesh = mesh
	mi.material_override = material
	_sync_shader_grid()

func _build_mesh() -> ArrayMesh:
	var w: int = shape.map_width
	var d: int = shape.map_depth
	var hw: float = (w - 1) * 0.5
	var hd: float = (d - 1) * 0.5
	var gw: int = w - 1
	var gd: int = d - 1
	var data: PackedFloat32Array = shape.map_data

	# Each passable cell gets its own 4 vertices.  Impassable cells are omitted
	# entirely, leaving literal geometry holes so the background shows through without
	# any transparency shader tricks. A cell is impassable when its corner-height
	# spread > MAX_SLOPE_DIFF (too steep) OR it is an authored no-go cell (the owning
	# Map's blocked_cells) — so toggling a BlockPin punches/fills a hole here just like
	# dragging a HeightPin reshapes the mesh (see Map.set_cell_blocked).
	var blocked: Dictionary = _blocked_lookup()

	var verts   := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for z in gd:
		for x in gw:
			if blocked.has(Vector2i(x, z)):
				continue
			var h00: float = data[ z      * w + x    ]
			var h10: float = data[ z      * w + x + 1]
			var h11: float = data[(z + 1) * w + x + 1]
			var h01: float = data[(z + 1) * w + x    ]

			var spread: float = maxf(maxf(h00, h10), maxf(h11, h01)) \
							  - minf(minf(h00, h10), minf(h11, h01))
			if spread > MAX_SLOPE_DIFF:
				continue

			var base: int = verts.size()

			verts.append(Vector3(x     - hw, h00, z     - hd))
			verts.append(Vector3(x + 1 - hw, h10, z     - hd))
			verts.append(Vector3(x + 1 - hw, h11, z + 1 - hd))
			verts.append(Vector3(x     - hw, h01, z + 1 - hd))

			uvs.append(Vector2(float(x    ) / gw, float(z    ) / gd))
			uvs.append(Vector2(float(x + 1) / gw, float(z    ) / gd))
			uvs.append(Vector2(float(x + 1) / gw, float(z + 1) / gd))
			uvs.append(Vector2(float(x    ) / gw, float(z + 1) / gd))

			var fn: Vector3 = (verts[base + 1] - verts[base]) \
							   .cross(verts[base + 3] - verts[base]).normalized()
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)
			normals.append(fn)

			indices.append_array([base, base+1, base+2, base, base+2, base+3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


## Grid cells the owning Map has flagged as no-go (Map.blocked_cells), as a
## Vector2i → true lookup for O(1) membership in the build loop. Empty when there is
## no Map ancestor (e.g. the generator used standalone), so blocking only takes effect
## inside a Map — and build() always reflects the CURRENT blocked_cells, whoever
## triggered it.
func _blocked_lookup() -> Dictionary:
	var lookup: Dictionary = {}
	var map := _find_map()
	if map != null:
		for c: Vector2i in map.blocked_cells:
			lookup[c] = true
	return lookup


## Walk up to the owning Map (the generator lives under Map/NavigationRegion/Body).
func _find_map() -> Map:
	var node: Node = get_parent()
	while node != null:
		if node is Map:
			return node as Map
		node = node.get_parent()
	return null
#endregion
