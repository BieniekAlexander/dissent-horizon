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

func _ready() -> void:
	_apply_to_instance()


## Build the mesh from the current `shape` and store it in `mesh`.
@export var run_build: bool:
	set(value): build()

func build() -> void:
	if shape == null:
		push_warning("HeightmapMeshGenerator: no shape assigned")
		return
	mesh = _build_mesh()
	if material != null:
		mesh.surface_set_material(0, material)

func _apply_to_instance() -> void:
	var mi: MeshInstance3D = get_node_or_null("GeneratedMesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "GeneratedMesh"
		add_child(mi)
	mi.mesh = mesh
	mi.material_override = material


func _build_mesh() -> ArrayMesh:
	var w: int = shape.map_width
	var d: int = shape.map_depth
	var hw: float = (w - 1) * 0.5
	var hd: float = (d - 1) * 0.5
	var data: PackedFloat32Array = shape.map_data

	var verts   := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	verts.resize(w * d)
	uvs.resize(w * d)
	normals.resize(w * d)

	# One vertex per heightmap corner, centred at origin.
	for z in d:
		for x in w:
			var i: int = z * w + x
			verts[i]   = Vector3(x - hw, data[i], z - hd)
			uvs[i]     = Vector2(float(x) / (w - 1), float(z) / (d - 1))
			normals[i] = Vector3.ZERO

	# Two triangles per cell, winding CCW from above so normals point +Y.
	for z in (d - 1):
		for x in (w - 1):
			var i00: int = z * w + x
			var i10: int = z * w + x + 1
			var i01: int = (z + 1) * w + x
			var i11: int = (z + 1) * w + x + 1

			# fn1: triangle (i00, i10, i11)
			# fn2: triangle (i00, i11, i01)
			var fn1: Vector3 = (verts[i10] - verts[i00]).cross(verts[i11] - verts[i00])
			var fn2: Vector3 = (verts[i11] - verts[i00]).cross(verts[i01] - verts[i00])

			normals[i00] += fn1 + fn2
			normals[i10] += fn1
			normals[i11] += fn1 + fn2
			normals[i01] += fn2

			indices.append_array([i00, i10, i11, i00, i11, i01])

	for i in normals.size():
		normals[i] = normals[i].normalized()

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices

	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
