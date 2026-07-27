@tool
extends SceneTree

## Builds the surface meshes for the mesh-terrain test scenarios, bakes each into a
## TerrainData heightfield, and writes both to disk.
##
## Run with:
##   godot --headless -s res://tools/terrain_meshes/generate_test_meshes.gd
##
## The meshes are generated rather than modelled so the scenarios are reproducible from
## source and reviewable as code — but nothing downstream cares where the mesh came from:
## assign any Mesh to the Map's terrain_source_mesh and press bake_terrain_from_mesh.
##
## Both maps use s1's grid (play_size 79x79 -> a 160x160 corner grid, 159x159 cells), so they
## exercise the pipeline at the size a real scenario runs at.

const PLAY_SIZE := Vector2i(79, 79)
const CATALOG_PATH := "res://resources/terrain/tile_catalog.tres"
const MESH_DIR := "res://resources/terrain/test_meshes/"
const TERRAIN_DIR := "res://resources/terrain/"

## Disc: the largest true circle that fits the play area. The play rectangle is authored in
## screen-aligned (s, t) space, so in world XZ it is a square rotated 45 degrees whose
## INSCRIBED radius is play_size.x / sqrt(2) = 55.86 — a disc any larger would have its rim
## clipped by the play bounds and stop being round.
const DISC_RADIUS: float = 55.0
## A shallow paraboloid rather than a flat plate, so the scenario actually exercises height
## sampling and unit terrain-following. Max slope is 2*H/R = 0.09 per unit, comfortably under
## TerrainGrid.MAX_SLOPE_DIFF (0.5), so the whole dome stays passable.
const DISC_HEIGHT: float = 2.5
const DISC_RINGS: int = 64
const DISC_SEGMENTS: int = 128

## Plateau: a square covering the whole corner grid (159x159 units, so half-extent 80 spills
## past it deliberately — the play bounds do the clipping).
const SQUARE_HALF: float = 80.0
## A cylinder with genuinely vertical sides. The baker skips vertical triangles (zero XZ
## area), so the rim resolves to a one-cell height step of PLATEAU_HEIGHT — far over
## MAX_SLOPE_DIFF, which is what makes the ring impassable and renders it as a cliff face.
const PLATEAU_RADIUS: float = 18.0
const PLATEAU_HEIGHT: float = 6.0
const PLATEAU_SEGMENTS: int = 96


func _initialize() -> void:
	var catalog: TerrainTileCatalog = load(CATALOG_PATH)
	if catalog == null:
		push_error("could not load tile catalog at %s" % CATALOG_PATH)
		quit(1)
		return

	_emit("flat_plain", _build_flat(), catalog, "mesh_flat_terrain")
	_emit("disc_island", _build_disc(), catalog, "mesh_disc_terrain")
	_emit("plateau_square", _build_plateau(), catalog, "mesh_plateau_terrain")
	quit()


## Save `mesh`, bake it into a TerrainData, save that too, and report coverage.
func _emit(a_mesh_name: String, a_mesh: ArrayMesh, a_catalog: TerrainTileCatalog, a_terrain_name: String) -> void:
	var mesh_path: String = MESH_DIR + a_mesh_name + ".res"
	var err: int = ResourceSaver.save(a_mesh, mesh_path)
	if err != OK:
		push_error("failed to save %s (%d)" % [mesh_path, err])
		return

	var data := TerrainData.new()
	data.play_size = PLAY_SIZE
	data.catalog = a_catalog
	var mesh_res: Mesh = load(mesh_path)
	var report: Dictionary = data.bake_source_mesh(mesh_res)

	var terrain_path: String = TERRAIN_DIR + a_terrain_name + ".tres"
	err = ResourceSaver.save(data, terrain_path)
	if err != OK:
		push_error("failed to save %s (%d)" % [terrain_path, err])
		return

	print("%s -> %s" % [mesh_path, terrain_path])
	print("   grid %dx%d corners | triangles %d (%d vertical, skipped)" % [
		data.dimensions.x, data.dimensions.y, report["triangles"], report["skipped_triangles"]])
	print("   corners covered %d/%d | cells voided %d/%d" % [
		report["covered"], report["corners"], report["voided"], report["cells"]])
	var lo: float = INF
	var hi: float = -INF
	for h: float in data.heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	print("   height range %.3f .. %.3f" % [lo, hi])


## A dead-flat square covering the whole grid — the control surface. Nothing to climb, nothing
## to path around, no height variation at all, so any deviation a unit shows on it belongs to
## navigation or steering rather than to the terrain.
func _build_flat() -> ArrayMesh:
	var s: float = SQUARE_HALF
	var verts := PackedVector3Array([
		Vector3(-s, 0.0, -s), Vector3(s, 0.0, -s), Vector3(s, 0.0, s),
		Vector3(-s, 0.0, -s), Vector3(s, 0.0, s), Vector3(-s, 0.0, s),
	])
	var normals := PackedVector3Array()
	for _i: int in 6:
		normals.append(Vector3.UP)
	return _mesh_from(verts, normals)


## A shallow domed disc: h(r) = H * (1 - (r/R)^2), triangulated as a fan of concentric rings.
## Nothing outside the rim, so the baker leaves those corners uncovered and TerrainData voids
## the cells — which is the whole point of this scenario.
func _build_disc() -> ArrayMesh:
	var verts := PackedVector3Array()

	var normals := PackedVector3Array()

	for ring: int in DISC_RINGS:
		var r0: float = DISC_RADIUS * float(ring) / DISC_RINGS
		var r1: float = DISC_RADIUS * float(ring + 1) / DISC_RINGS
		for seg: int in DISC_SEGMENTS:
			var a0: float = TAU * float(seg) / DISC_SEGMENTS
			var a1: float = TAU * float(seg + 1) / DISC_SEGMENTS
			var p00 := _dome_point(r0, a0)
			var p01 := _dome_point(r0, a1)
			var p10 := _dome_point(r1, a0)
			var p11 := _dome_point(r1, a1)
			if ring == 0:
				# Innermost ring degenerates to a fan around the apex.
				verts.append_array([p10, p11, p00])
			else:
				verts.append_array([p00, p10, p11])
				verts.append_array([p00, p11, p01])
	# Normals are computed ANALYTICALLY per vertex rather than averaged from faces: the
	# surface has a closed form, so its exact gradient is both cheaper and smoother than
	# welding vertices and averaging (welding would also fuse the rim into the ground).
	for v: Vector3 in verts:
		normals.append(_dome_normal(v))
	return _mesh_from(verts, normals)


func _dome_point(a_r: float, a_angle: float) -> Vector3:
	var t: float = a_r / DISC_RADIUS
	return Vector3(a_r * cos(a_angle), DISC_HEIGHT * (1.0 - t * t), a_r * sin(a_angle))


## Exact surface normal of h(x, z) = H * (1 - (x^2 + z^2) / R^2), i.e. (-dh/dx, 1, -dh/dz).
func _dome_normal(a_p: Vector3) -> Vector3:
	var k: float = -2.0 * DISC_HEIGHT / (DISC_RADIUS * DISC_RADIUS)
	return Vector3(-k * a_p.x, 1.0, -k * a_p.z).normalized()


## A flat square with a vertical-sided cylindrical plateau standing on it.
##
## The square is emitted whole (it passes UNDER the plateau) rather than cut around it: the
## baker keeps the highest surface at each corner, so the cap wins where it overlaps and the
## square wins everywhere else. That is what lets a plateau be modelled as a solid sitting on
## the ground instead of as a carefully-stitched single sheet.
func _build_plateau() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	var s: float = SQUARE_HALF
	verts.append_array([
		Vector3(-s, 0.0, -s), Vector3(s, 0.0, -s), Vector3(s, 0.0, s),
		Vector3(-s, 0.0, -s), Vector3(s, 0.0, s), Vector3(-s, 0.0, s),
	])
	for _i: int in 6:
		normals.append(Vector3.UP)

	for seg: int in PLATEAU_SEGMENTS:
		var a0: float = TAU * float(seg) / PLATEAU_SEGMENTS
		var a1: float = TAU * float(seg + 1) / PLATEAU_SEGMENTS
		var r0 := Vector3(PLATEAU_RADIUS * cos(a0), PLATEAU_HEIGHT, PLATEAU_RADIUS * sin(a0))
		var r1 := Vector3(PLATEAU_RADIUS * cos(a1), PLATEAU_HEIGHT, PLATEAU_RADIUS * sin(a1))
		# Cap, as a fan from the centre. Flat-up normals — the cap IS flat.
		verts.append_array([Vector3(0.0, PLATEAU_HEIGHT, 0.0), r0, r1])
		for _i: int in 3:
			normals.append(Vector3.UP)
		# Wall, straight down to the ground. Vertical, so the baker skips it for HEIGHT
		# purposes — but it is real geometry and, now that the surface mesh is what gets
		# drawn, it is the cliff face the player actually sees.
		var g0 := Vector3(r0.x, 0.0, r0.z)
		var g1 := Vector3(r1.x, 0.0, r1.z)
		verts.append_array([r0, g0, g1])
		verts.append_array([r0, g1, r1])
		# Radial normals, so the wall shades as a cylinder rather than as flat facets.
		var n0 := Vector3(cos(a0), 0.0, sin(a0))
		var n1 := Vector3(cos(a1), 0.0, sin(a1))
		normals.append_array([n0, n0, n1])
		normals.append_array([n0, n1, n1])
	return _mesh_from(verts, normals)


func _mesh_from(a_verts: PackedVector3Array, a_normals: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a_verts
	arrays[Mesh.ARRAY_NORMAL] = a_normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
