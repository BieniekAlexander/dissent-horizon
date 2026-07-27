extends GutTest

## REACH FOR A UNIT WIDER THAN A CELL. A unit's class navmesh is eroded back from every
## building edge by NavAgentClass.radius, so a MEDIUM unit (radius 0.95) can almost never
## stand in a cell touching a footprint — the grid adjacency test alone is one it cannot
## pass. SU.unit_is_close_to_footprint therefore also accepts a unit within its class's
## standoff. The regression: a Stock Truck parked beside its Compound, loaded, forever.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ClassStandoffReach.gd -gexit

const TRUCK_SCENE: String = "res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn"

const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
const FOOTPRINT_ORIGIN: Vector2i = Vector2i(4, 4)
const FOOTPRINT_SIZE: int = 4


## Real grid_to_world / world_to_grid on a flat height map, no navmesh loading.
class StubMap extends Map:
	func _ready() -> void:
		pass


var _world: Node3D
var _map: StubMap
var _footprint: Array = []


func before_each() -> void:
	_world = Node3D.new()
	_map = StubMap.new()
	var heights := HeightMapShape3D.new()
	heights.map_width = MAP_CORNERS
	heights.map_depth = MAP_CORNERS
	_map.height_map = heights
	_world.add_child(_map)
	add_child_autofree(_world)
	_footprint = []
	for dx: int in FOOTPRINT_SIZE:
		for dz: int in FOOTPRINT_SIZE:
			_footprint.append(FOOTPRINT_ORIGIN + Vector2i(dx, dz))


## A truck standing `a_distance` past the footprint's +z edge, level with its middle.
func _truck_off_edge(a_distance: float, a_class: NavAgentClass.Size) -> Commandable:
	var truck: Commandable = load(TRUCK_SCENE).instantiate() as Commandable
	_world.add_child(truck)
	truck.movement.nav_agent_class = a_class
	var edge_cell: Vector2i = FOOTPRINT_ORIGIN + Vector2i(1, FOOTPRINT_SIZE - 1)
	var centre: Vector3 = _map.grid_to_world(edge_cell)
	truck.global_position = Vector3(centre.x, 0.0, centre.z + Map.CELL_SIZE * 0.5 + a_distance)
	return truck


func test_a_medium_unit_where_its_navmesh_leaves_it_is_close() -> void:
	# 1.5 past the edge is in the SECOND cell out — the grid test says no. Where the reported
	# truck actually came to rest.
	var truck := _truck_off_edge(1.5, NavAgentClass.Size.MEDIUM)
	assert_true(SU.unit_is_close_to_footprint(truck, _map, _footprint),
		"a MEDIUM unit as close as its eroded navmesh allows counts as adjacent")


func test_a_medium_unit_well_clear_is_not_close() -> void:
	var truck := _truck_off_edge(3.0, NavAgentClass.Size.MEDIUM)
	assert_false(SU.unit_is_close_to_footprint(truck, _map, _footprint))


func test_the_standoff_scales_with_size_class() -> void:
	var distance: float = 1.7
	assert_false(SU.unit_is_close_to_footprint(
		_truck_off_edge(distance, NavAgentClass.Size.SMALL), _map, _footprint),
		"a SMALL unit can reach the adjacent cell, so it gets no extra standoff at this range")
	assert_true(SU.unit_is_close_to_footprint(
		_truck_off_edge(distance, NavAgentClass.Size.MEDIUM), _map, _footprint))


func test_the_grid_test_still_answers_for_an_adjacent_cell() -> void:
	var truck := _truck_off_edge(0.5, NavAgentClass.Size.SMALL)
	assert_true(SU.unit_is_close_to_footprint(truck, _map, _footprint))
