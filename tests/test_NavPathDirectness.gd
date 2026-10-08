extends GutTest

## How DIRECT is a path across open ground, and why can't the navmesh just use bigger
## polygons? Agents visibly travelled in X/Z-aligned legs where a straight diagonal was
## available (navigation-and-pathing.md §Do NOT merge cells into larger polygons).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavPathDirectness.gd -gexit
##
## Two halves:
##
##  1. THE PROBLEM. Godot's polygon A* picks one cell corridor out of many equal-cost ones,
##     and the funnel can only pull the string taut INSIDE the corridor it was handed, so
##     one-quad-per-cell yields a path that runs along an axis and then cuts. The same open
##     square as ONE polygon returns the exact straight line at every angle.
##
##  2. WHY BIGGER POLYGONS ARE NOT THE FIX. Godot links polygons by exactly-matching edges,
##     so a merged rectangle's long side against smaller neighbours is a T-junction that
##     silently fails to connect — and subdividing the perimeter to fix that breaks point
##     containment outright. Both are pinned below so the next attempt fails in five seconds
##     instead of after a day's work. See the note after NavManager._build_chunk.

const HALF: int = 18  ## square runs from -HALF..HALF world units
const PER_CELL_LAYER: int = 1 << 20
const SINGLE_LAYER: int = 1 << 21
const PROBE_LAYER: int = 1 << 22

var _map: RID = RID()
var _regions: Array[RID] = []


func after_each() -> void:
	for region: RID in _regions:
		NavigationServer3D.free_rid(region)
	_regions.clear()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()


# --- Fixtures ------------------------------------------------------------------


func _new_map() -> void:
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, 0.25)
	NavigationServer3D.map_set_active(_map, true)


func _add_region(a_mesh: NavigationMesh, a_layer: int) -> void:
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, _map)
	NavigationServer3D.region_set_navigation_layers(region, a_layer)
	NavigationServer3D.region_set_use_edge_connections(region, false)
	NavigationServer3D.region_set_navigation_mesh(region, a_mesh)
	_regions.append(region)


## A region mesh can take more than one sync to merge into the map's query structure — the
## same caveat NavManager._physics_process polls around.
func _sync() -> void:
	for _i in 10:
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(_map)


## One quad per cell with corners shared between neighbours — NavManager._build_chunk's shape.
func _per_cell_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	var verts := PackedVector3Array()
	var index_of: Dictionary = {}
	for z: int in range(-HALF, HALF):
		for x: int in range(-HALF, HALF):
			var indices := PackedInt32Array()
			for corner: Vector2i in [
				Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)
			]:
				if not index_of.has(corner):
					index_of[corner] = verts.size()
					verts.append(Vector3(corner.x, 0.0, corner.y))
				indices.append(index_of[corner])
			mesh.add_polygon(indices)
	mesh.vertices = verts
	return mesh


func _single_polygon_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array(
		[
			Vector3(-HALF, 0, -HALF),
			Vector3(HALF, 0, -HALF),
			Vector3(HALF, 0, HALF),
			Vector3(-HALF, 0, HALF),
		]
	)
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh


func _open_map() -> void:
	_new_map()
	_add_region(_per_cell_mesh(), PER_CELL_LAYER)
	_add_region(_single_polygon_mesh(), SINGLE_LAYER)
	await _sync()


# --- Measurement ---------------------------------------------------------------


func _length(a_path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, a_path.size()):
		total += a_path[i].distance_to(a_path[i - 1])
	return total


## Path length over straight-line distance, minus one: 0.0 is a perfectly direct path.
func _excess(a_layer: int, a_from: Vector3, a_to: Vector3) -> float:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		_map, a_from, a_to, true, a_layer
	)
	assert_gt(
		path.size(), 1, "a path was found from %s to %s on layer %d" % [a_from, a_to, a_layer]
	)
	return _length(path) / a_from.distance_to(a_to) - 1.0


func _worst_excess(a_layer: int) -> float:
	var worst: float = 0.0
	for case: Array in _cases():
		worst = maxf(worst, _excess(a_layer, case[0], case[1]))
	return worst


## Endpoints spanning the square west-to-east at a range of angles, kept a half cell inside
## the border so neither end snaps to an edge.
func _cases() -> Array:
	var result: Array = []
	for dz: int in range(0, 2 * HALF - 6, 4):
		result.append(
			[Vector3(-HALF + 0.5, 0, -HALF + 0.5), Vector3(HALF - 0.5, 0, -HALF + 0.5 + dz)]
		)
	return result


# --- 1. The problem -------------------------------------------------------------


func test_one_polygon_gives_the_exact_straight_line() -> void:
	await _open_map()
	assert_almost_eq(
		_worst_excess(SINGLE_LAYER),
		0.0,
		1e-3,
		"one polygon over open ground is the straight line at every angle"
	)


func test_per_cell_polygons_bend_the_path() -> void:
	await _open_map()
	var worst: float = _worst_excess(PER_CELL_LAYER)
	gut.p("per-cell mesh: worst excess over the straight line = %.1f%%" % (100.0 * worst))
	assert_gt(
		worst, 0.02, "one quad per cell measurably lengthens a diagonal — the reported problem"
	)


# --- 2. Why bigger polygons are not the fix ------------------------------------


## `w` x `h` cells as ONE rectangle. `subdivided` puts a vertex at every cell corner along
## the perimeter — what a merged mesh MUST do, since Godot connects polygons only by
## exactly-matching edges and a long unbroken side against smaller neighbours is a
## T-junction.
func _rectangle_mesh(a_w: int, a_h: int, a_subdivided: bool) -> NavigationMesh:
	var corners: Array[Vector2i] = []
	if a_subdivided:
		for x: int in range(0, a_w + 1):
			corners.append(Vector2i(x, 0))
		for z: int in range(1, a_h + 1):
			corners.append(Vector2i(a_w, z))
		for x: int in range(a_w - 1, -1, -1):
			corners.append(Vector2i(x, a_h))
		for z: int in range(a_h - 1, 0, -1):
			corners.append(Vector2i(0, z))
	else:
		corners = [Vector2i(0, 0), Vector2i(a_w, 0), Vector2i(a_w, a_h), Vector2i(0, a_h)]

	var mesh := NavigationMesh.new()
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for corner: Vector2i in corners:
		indices.append(verts.size())
		verts.append(Vector3(corner.x, 0, corner.y))
	mesh.vertices = verts
	mesh.add_polygon(indices)
	return mesh


## How many of the rectangle's cell centres resolve onto the mesh at all.
func _contained_centres(a_w: int, a_h: int) -> int:
	var contained: int = 0
	for z: int in a_h:
		for x: int in a_w:
			var p := Vector3(x + 0.5, 0, z + 0.5)
			if NavigationServer3D.map_get_closest_point(_map, p).distance_to(p) < 0.01:
				contained += 1
	return contained


func test_a_plain_rectangle_contains_its_interior() -> void:
	# The control for the case below: nothing about the SHAPE is a problem.
	_new_map()
	_add_region(_rectangle_mesh(3, 32, false), PROBE_LAYER)
	await _sync()
	assert_eq(
		_contained_centres(3, 32),
		96,
		"a 4-vertex rectangle resolves every one of its interior points"
	)


func test_a_subdivided_rectangle_contains_NONE_of_its_interior() -> void:
	# THE BLOCKER. Give the same rectangle collinear perimeter vertices — which is the only
	# way to avoid T-junctions against smaller neighbours — and NavigationServer stops
	# treating it as covering its own interior; map_get_closest_point snaps queries out to
	# the nearest polygon EDGE instead, and path endpoints are resolved through exactly that.
	#
	# This is what makes "merge cells into big polygons" unavailable in this engine, and it
	# is not a small effect: on s3's authored terrain a merged mesh bent 87% of the 5-tile
	# diagonal moves whose straight line is fully walkable (mean excess 24.8%) against 22%
	# and 4.1% for one quad per cell.
	_new_map()
	_add_region(_rectangle_mesh(3, 32, true), PROBE_LAYER)
	await _sync()
	assert_eq(
		_contained_centres(3, 32),
		0,
		"a rectangle with collinear perimeter vertices resolves NONE of its interior points"
	)
