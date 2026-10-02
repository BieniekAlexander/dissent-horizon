@tool
class_name TerrainMeshGrid
extends RefCounted

## The BRUSHABLE terrain surface: a subdivided plane carrying one vertex per corner of the
## map's grid, which is the mesh the terrain brush edits and TerrainSurface draws.
##
## WHY A REGULAR GRID. Brushing is "raise everything within radius r", which needs vertices
## where the brush lands — well defined on a regular grid and not on arbitrary imported
## topology. So a brushable surface is always one of these; an imported Blender mesh can still
## be composited into the heightfield by MeshHeightfieldBaker, it just cannot be sculpted.
##
## WHY SHARED VERTICES (one per corner, indexed) rather than four per cell the way
## HeightmapMeshGenerator emits them: a brush moves ONE vertex and every triangle touching that
## corner follows. With per-cell duplicates the same corner exists four times and they would
## have to be kept in step by hand. Sharing also gives smooth normals for free.
##
## The per-cell tile identity that the duplicated-vertex layout existed to carry is not lost —
## terrain_surface.gdshader looks tile type up PER FRAGMENT by world XZ out of
## TerrainData.cell_data_texture(), which is exactly why that indirection was built.
##
## Resolution is one vertex per gameplay corner (RA3 sculpts at its gameplay tile resolution
## too). A full rebuild of s1's 160x160 grid measures ~7.7 ms — 130 fps — so a brush stroke
## rebuilds the whole surface and no chunked partial-update machinery is needed.


#region Public API
## A flat grid spanning the `dims` corner grid at `height`, centred on the origin exactly as
## HeightMapShape3D centres its own — the frame MeshHeightfieldBaker and Map.grid_to_world
## already share.
static func create(dims: Vector2i, height: float = 0.0) -> ArrayMesh:
	var heights := PackedFloat32Array()
	heights.resize(maxi(dims.x, 2) * maxi(dims.y, 2))
	heights.fill(height)
	var mesh := ArrayMesh.new()
	write_heights(mesh, dims, heights)
	return mesh


## Whether `mesh` is a grid of exactly this size — i.e. something this class can edit. A mesh
## that fails this is drawn and baked but never brushed.
static func is_grid_mesh(mesh: Mesh, dims: Vector2i) -> bool:
	if mesh == null or mesh.get_surface_count() != 1:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size() == dims.x * dims.y


## Per-corner heights read back out of the mesh's vertices, in TerrainData.heights' layout.
## Empty when `mesh` is not a grid of this size.
static func read_heights(mesh: Mesh, dims: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not is_grid_mesh(mesh, dims):
		return out
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	out.resize(verts.size())
	for i: int in verts.size():
		out[i] = verts[i].y
	return out


## Rewrite the surface from `heights`. Replaces the whole surface rather than patching vertices:
## Godot cannot partially update an ArrayMesh surface through the resource API, and at this
## grid size a full rebuild is cheap enough to do per brush step.
static func write_heights(mesh: ArrayMesh, dims: Vector2i, heights: PackedFloat32Array) -> void:
	var w: int = dims.x
	var d: int = dims.y
	if w < 2 or d < 2 or heights.size() != w * d:
		return

	var verts := PackedVector3Array()
	verts.resize(w * d)
	var normals := PackedVector3Array()
	normals.resize(w * d)
	var uvs := PackedVector2Array()
	uvs.resize(w * d)
	var half_w: float = (w - 1) * 0.5
	var half_d: float = (d - 1) * 0.5

	for z: int in d:
		for x: int in w:
			var i: int = z * w + x
			verts[i] = Vector3(x - half_w, heights[i], z - half_d)
			# Central difference on the heightfield rather than averaged face normals: it is the
			# exact gradient of the surface being drawn, one pass, and it clamps cleanly at the rim.
			var hx0: float = heights[z * w + maxi(x - 1, 0)]
			var hx1: float = heights[z * w + mini(x + 1, w - 1)]
			var hz0: float = heights[maxi(z - 1, 0) * w + x]
			var hz1: float = heights[mini(z + 1, d - 1) * w + x]
			var dx: float = (hx1 - hx0) / (1.0 if x == 0 or x == w - 1 else 2.0)
			var dz: float = (hz1 - hz0) / (1.0 if z == 0 or z == d - 1 else 2.0)
			normals[i] = Vector3(-dx, 1.0, -dz).normalized()
			uvs[i] = Vector2(float(x) / (w - 1), float(z) / (d - 1))

	var idx := PackedInt32Array()
	idx.resize((w - 1) * (d - 1) * 6)
	var k: int = 0
	for z: int in d - 1:
		for x: int in w - 1:
			var a: int = z * w + x
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + w + 1
			idx[k + 3] = a
			idx[k + 4] = a + w + 1
			idx[k + 5] = a + w
			k += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx

	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
#endregion
