@tool
class_name DoodadLibrary
extends RefCounted

## The sample doodads: placeholder props built from primitive shapes and vertex colours, so the
## decoration pass has something to place before any art exists. Swapping a kind for a real
## model is a change to mesh_of alone; the planner reads only a kind's height.
##
## The setting's ecosystem is undecided, so these are plain Earth flora and stone
## TODO: replace once world-building.md settles the biome — see aesthetics/README.md
## §Art direction.

#region Enums
enum Kind {
	CONIFER, BROADLEAF, DEAD_TREE, BOULDER, ROCK_PILE, BUSH, GRASS_TUFT, FLOWERS, REEDS, STUMP,
}
#endregion

#region Constants
## The tallest a doodad standing on PASSABLE ground may be. Cosmetic props must never read as
## obstacles: an RTS player reads anything taller than a unit's knee as "blocks movement", so
## tall props (trees, boulders) stand only where units cannot go anyway. Enforced by
## MapDecorationPlanner and pinned by a test.
const LOW_MAX_HEIGHT: float = 0.4

const _BARK := Color(0.36, 0.25, 0.16)
const _DEAD_WOOD := Color(0.40, 0.36, 0.31)
const _NEEDLES: Array[Color] = [
	Color(0.12, 0.28, 0.15), Color(0.15, 0.33, 0.17), Color(0.18, 0.38, 0.19)]
const _LEAVES := Color(0.25, 0.44, 0.17)
const _STONE := Color(0.47, 0.45, 0.42)
const _STONE_DARK := Color(0.37, 0.35, 0.33)
const _SHRUB := Color(0.20, 0.36, 0.15)
const _GRASS := Color(0.36, 0.52, 0.20)
const _REED := Color(0.45, 0.50, 0.24)
const _PETALS: Array[Color] = [
	Color(0.95, 0.85, 0.25), Color(0.95, 0.95, 0.92), Color(0.62, 0.42, 0.80)]

## Facet counts for the primitive shapes: low on purpose, so the props read as stylised blocks
## rather than as failed realism.
const _SIDES: int = 6
const _RINGS: int = 3
#endregion

## Kind -> ArrayMesh. Memoized: a mesh is built from dozens of primitives, and every MultiMesh
## of that kind, on every map load, shares the one instance.
static var _meshes: Dictionary = {}


#region Public API
static func mesh_of(kind: Kind) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _build(kind)
	return _meshes[kind]


## The kind's height above its base, read from the mesh itself so it cannot disagree with it.
static func height_of(kind: Kind) -> float:
	return mesh_of(kind).get_aabb().end.y


static func is_low(kind: Kind) -> bool:
	return height_of(kind) <= LOW_MAX_HEIGHT


static func all_kinds() -> Array[Kind]:
	var kinds: Array[Kind] = []
	for value: int in Kind.values():
		kinds.append(value as Kind)
	return kinds
#endregion


#region Mesh construction
static func _build(kind: Kind) -> ArrayMesh:
	var b := _Builder.new()
	match kind:
		Kind.CONIFER:
			b.cylinder(Vector3(0, 0.22, 0), 0.07, 0.10, 0.45, _BARK)
			b.cylinder(Vector3(0, 0.80, 0), 0.0, 0.60, 0.80, _NEEDLES[0])
			b.cylinder(Vector3(0, 1.17, 0), 0.0, 0.46, 0.65, _NEEDLES[1])
			b.cylinder(Vector3(0, 1.52, 0), 0.0, 0.32, 0.55, _NEEDLES[2])
		Kind.BROADLEAF:
			b.cylinder(Vector3(0, 0.35, 0), 0.07, 0.10, 0.70, _BARK)
			b.sphere(Vector3(0, 1.05, 0), 0.45, Vector3.ONE, _LEAVES)
			b.sphere(Vector3(0.30, 0.90, 0.15), 0.35, Vector3.ONE, _LEAVES.darkened(0.1))
			b.sphere(Vector3(-0.25, 0.95, -0.20), 0.38, Vector3.ONE, _LEAVES.lightened(0.08))
		Kind.DEAD_TREE:
			b.cylinder(Vector3(0, 0.55, 0), 0.04, 0.08, 1.10, _DEAD_WOOD)
			b.cylinder(Vector3(0.16, 0.86, 0), 0.015, 0.035, 0.50, _DEAD_WOOD,
				Basis(Vector3.BACK, deg_to_rad(-45.0)))
			b.cylinder(Vector3(0, 0.70, -0.14), 0.015, 0.03, 0.40, _DEAD_WOOD,
				Basis(Vector3.RIGHT, deg_to_rad(-40.0)))
		Kind.BOULDER:
			b.sphere(Vector3(0, 0.22, 0), 0.5, Vector3(1.0, 0.75, 0.85), _STONE)
		Kind.ROCK_PILE:
			b.sphere(Vector3(0, 0.08, 0), 0.20, Vector3(1, 0.8, 1), _STONE)
			b.sphere(Vector3(0.22, 0.06, 0.08), 0.15, Vector3(1, 0.7, 1), _STONE_DARK)
			b.sphere(Vector3(-0.18, 0.06, 0.14), 0.14, Vector3(1, 0.8, 0.9), _STONE)
			b.sphere(Vector3(0.05, 0.05, -0.22), 0.13, Vector3(1, 0.7, 1), _STONE_DARK)
			b.sphere(Vector3(0.06, 0.20, 0.04), 0.10, Vector3.ONE, _STONE.lightened(0.1))
		Kind.BUSH:
			b.sphere(Vector3(0, 0.16, 0), 0.28, Vector3(1, 0.65, 1), _SHRUB)
			b.sphere(Vector3(0.20, 0.13, 0.10), 0.20, Vector3(1, 0.7, 1), _SHRUB.lightened(0.1))
			b.sphere(Vector3(-0.18, 0.12, -0.10), 0.22, Vector3(1, 0.65, 1), _SHRUB.darkened(0.1))
		Kind.GRASS_TUFT:
			_blades(b, 6, 0.28, _GRASS)
		Kind.FLOWERS:
			_blades(b, 4, 0.20, _GRASS)
			for i: int in _PETALS.size():
				var angle: float = TAU * i / _PETALS.size()
				b.sphere(Vector3(cos(angle) * 0.08, 0.21, sin(angle) * 0.08), 0.045, Vector3.ONE,
					_PETALS[i])
		Kind.REEDS:
			for i: int in 6:
				var angle: float = TAU * i / 6.0
				var at := Vector3(cos(angle) * 0.10, 0.15, sin(angle) * 0.10)
				b.cylinder(at, 0.012, 0.018, 0.30, _REED)
				b.cylinder(at + Vector3(0, 0.17, 0), 0.025, 0.025, 0.06, _BARK)
		Kind.STUMP:
			b.cylinder(Vector3(0, 0.08, 0), 0.14, 0.17, 0.16, _BARK)
	return b.commit()


## A fan of thin blades leaning out from the centre: grass at a glance, a dozen triangles.
static func _blades(b: _Builder, count: int, height: float, color: Color) -> void:
	for i: int in count:
		var yaw: float = TAU * i / count
		var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(18.0))
		var base := Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05)
		b.prism(base + lean * Vector3(0, height * 0.5, 0), Vector3(0.05, height, 0.015), color,
			lean)


## Accumulates transformed, vertex-coloured primitive meshes into one ArrayMesh.
class _Builder:
	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()

	func cylinder(
		at: Vector3, top: float, bottom: float, height: float, color: Color,
		basis: Basis = Basis.IDENTITY
	) -> void:
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = _SIDES
		mesh.rings = 1
		add(mesh, Transform3D(basis, at), color)

	func sphere(at: Vector3, radius: float, stretch: Vector3, color: Color) -> void:
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		mesh.radial_segments = _SIDES
		mesh.rings = _RINGS
		add(mesh, Transform3D(Basis.from_scale(stretch), at), color)

	func prism(at: Vector3, size: Vector3, color: Color, basis: Basis) -> void:
		var mesh := PrismMesh.new()
		mesh.size = size
		add(mesh, Transform3D(basis, at), color)

	func add(primitive: PrimitiveMesh, xform: Transform3D, color: Color) -> void:
		var arrays: Array = primitive.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normal_basis: Basis = xform.basis.inverse().transposed()
		var base: int = _verts.size()
		for i: int in verts.size():
			_verts.append(xform * verts[i])
			_normals.append((normal_basis * normals[i]).normalized())
			_colors.append(color)
		for index: int in indices:
			_indices.append(base + index)

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
#endregion
