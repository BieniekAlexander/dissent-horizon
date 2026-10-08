extends GutTest

## A SPAWN ANCHORED ON A STRUCTURE STANDS BESIDE IT. A shelter producing a resident, or a
## garrison releasing its occupants, asks for points around a centre that is inside its own
## footprint: no navmesh there, and its hurtbox in the way. SU.get_nonoverlapping_points grows
## its scatter from points it has already placed, so it seeds off-centre when the centre is
## taken; Map.add_entities measures its scatter region from the anchoring fixture's edge, so a
## footprint wider than the region still leaves room.
##
## Run with:
## godot --headless --fixed-fps 30 -s addons/gut/gut_cmdln.gd \
##   -gtest=res://tests/test_ScatterBesideStructure.gd -gexit

const W: int = 2 * NavManager.CHUNK_SIZE_CELLS + 1  # corners; one fewer cells per side
const CELLS: int = W - 1
## Wider than Map.MIN_SCATTER_REGION_RADIUS from its centre to its edge, so only a region
## measured from the edge reaches free ground.
const FOOTPRINT: int = 11
const POINT_RADIUS: float = 0.4
## The structure's hurtbox height; any height the probe sphere reaches will do.
const HURTBOX_HEIGHT: float = 2.0
## Bounded by the wall clock: the navmesh builds on a worker thread (see test_NavChangeReplanning).
const READY_TIMEOUT_MSEC: int = 4000
const CLEARANCE_MASK: int = (
	CollisionLayers.Mask.MOVEMENT_OBSTRUCTION | CollisionLayers.Mask.STRUCTURE_BLOCKER
)


## A Map over the flat fixture grid: the navmesh and cell grid are the fixture's, the ground
## is at height 0, and none of the terrain loading runs.
class FixtureMap:
	extends Map

	func _ready() -> void:
		pass

	func world_to_grid_point(a_world_xz: Vector2) -> Vector2:
		return a_world_xz + Vector2.ONE * (CELLS * 0.5)

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return a_coords.x >= 0 and a_coords.x < CELLS and a_coords.y >= 0 and a_coords.y < CELLS


var _map: FixtureMap
var _structure: Commandable
var _commander: Commander


func before_each() -> void:
	_map = _make_map()
	add_child_autofree(_map)
	_commander = Commander.new()
	_commander.map = _map
	add_child_autofree(_commander)
	_commander.set_physics_process(false)

	_structure = _place_structure(_map.terrain_grid)

	var nav := NavManager.new()
	nav.navigation_region = _map.nav_region
	nav.terrain_grid = _map.terrain_grid
	add_child_autofree(nav)
	var deadline: int = Time.get_ticks_msec() + READY_TIMEOUT_MSEC
	while not nav.is_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


## The fixture map with the children Map's own @onready lookups expect, a TerrainGrid over a
## flat height map, and an empty cell grid. Not yet in the tree.
func _make_map() -> FixtureMap:
	var map := FixtureMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	map.add_child(region)

	var heights := HeightMapShape3D.new()
	heights.map_width = W
	heights.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)
	heights.map_data = data
	map.height_map = heights
	var grid := TerrainGrid.new()
	grid.height_map = heights
	grid.terrain_body = body
	map.add_child(grid)
	map.terrain_grid = grid

	map.cell_grid = []
	for x: int in CELLS:
		var column: Array = []
		column.resize(CELLS)
		map.cell_grid.append(column)
	return map


## A FOOTPRINT×FOOTPRINT obstruction centred on the map, registered on the cell grid and the
## terrain grid, with a hurtbox covering its whole footprint as a real building's does.
func _place_structure(a_grid: TerrainGrid) -> Commandable:
	var piece := FakePieces.structure({"dimensions": Vector2i(FOOTPRINT, FOOTPRINT)})
	var hurtbox := piece.get_node("Hurtbox") as CollisionObject3D
	var box := BoxShape3D.new()
	box.size = Vector3(FOOTPRINT, HURTBOX_HEIGHT, FOOTPRINT)
	(hurtbox.get_node("HurtboxShape") as CollisionShape3D).shape = box
	add_child_autofree(piece)
	piece.set_physics_process(false)
	hurtbox.collision_layer = CollisionLayers.Mask.STRUCTURE_BLOCKER
	var first: int = (CELLS - FOOTPRINT) / 2
	var cells: Array = []
	for x: int in range(first, first + FOOTPRINT):
		for z: int in range(first, first + FOOTPRINT):
			cells.append(Vector2i(x, z))
			_map.cell_grid[x][z] = piece
	a_grid.place_building(cells, piece)
	return piece


## Asserts `a_point`, snapped onto the navmesh as every placement snaps it, stands outside the
## structure's footprint. How far outside is the physics probe's business, not this test's.
func _assert_beside_structure(a_point: Vector2) -> void:
	var ground: Vector3 = _map.nearest_navmesh_point(Vector3(a_point.x, 0.0, a_point.y))
	assert_gt(
		_structure.hull().distance_to_point(VU.in_xz(ground)),
		0.0,
		"%s stands beside the structure, not inside its footprint" % a_point
	)


func test_a_scatter_anchored_inside_a_footprint_seeds_beside_it() -> void:
	var points: Array[Vector2] = SU.get_nonoverlapping_points(
		_map, Vector2.ZERO, POINT_RADIUS, _map.get_world_3d(), CLEARANCE_MASK, FOOTPRINT, 1
	)
	assert_eq(points.size(), 1, "the taken centre does not end the search")
	if points.size() == 1:
		_assert_beside_structure(points[0])


func test_a_batch_anchored_inside_a_footprint_all_stand_clear_and_apart() -> void:
	var count: int = 3
	var points: Array[Vector2] = SU.get_nonoverlapping_points(
		_map, Vector2.ZERO, POINT_RADIUS, _map.get_world_3d(), CLEARANCE_MASK, FOOTPRINT, count
	)
	assert_eq(points.size(), count)
	for i: int in points.size():
		_assert_beside_structure(points[i])
		for j: int in range(i + 1, points.size()):
			assert_gte(points[i].distance_to(points[j]), 2.0 * POINT_RADIUS, "no two overlap")


func test_a_unit_spawned_on_a_structure_wider_than_the_scatter_stands_beside_it() -> void:
	var unit := FakePieces.unit({"speed": 1.0})
	_map.add_entity(unit, Vector2.ZERO, _commander)
	_assert_beside_structure(VU.in_xz(unit.position))
