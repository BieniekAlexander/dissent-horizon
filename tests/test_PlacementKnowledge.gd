extends GutTest

## Placement is judged against what the commander KNOWS, so a refused placement never tells it
## what stands in the fog: ground in vision by the true grid, explored ground by what it last
## saw, unexplored ground not at all. construction.md §Placement is judged against what the
## commander knows.

const _PLAY: Vector2i = Vector2i(16, 16)
const _DIMS: Vector2i = Vector2i(2, 2)
const _ME: int = 1
const _ENEMY: int = 2
## Cells with x below this are in vision; below _EXPLORED_X, explored.
const _VISION_X: int = 6
const _EXPLORED_X: int = 12
const _IN_VISION: Vector2i = Vector2i(2, 2)
const _FOGGED: Vector2i = Vector2i(8, 2)
const _UNEXPLORED: Vector2i = Vector2i(13, 2)


## A real Map with its terrain/navmesh boot skipped (test_WaterPlacement's fixture shape).
class TestMap:
	extends Map

	func _ready() -> void:
		pass


## A commander whose vision and exploration are bands of columns rather than a Fog.
class StubCommander:
	extends Commander
	var test_map: Map

	func has_explored(a_world_pos: Vector3) -> bool:
		return test_map.world_to_grid(VU.in_xz(a_world_pos)).x < _EXPLORED_X

	func has_vision_at(a_world_pos: Vector3) -> bool:
		return test_map.world_to_grid(VU.in_xz(a_world_pos)).x < _VISION_X


var _map: Map
var _me: StubCommander


func before_each() -> void:
	_map = _make_map()
	_me = StubCommander.new()
	_me.id = _ME
	_me.test_map = _map
	add_child_autofree(_me)
	_me.map = _map
	_me.blackboard = CommanderBlackboard.new(_me)


func _make_map() -> Map:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(1.0)
	td.heights = heights
	var map: Map = TestMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	body.add_child(collision)
	region.add_child(body)
	map.add_child(region)
	add_child_autofree(map)
	map.terrain_data = td
	map.height_map = td.to_height_shape()
	map.terrain_grid = TerrainGrid.new()
	map.terrain_grid.height_map = map.height_map
	map.terrain_grid.terrain_body = body
	map.add_child(map.terrain_grid)
	map.cell_grid = []
	for _x: int in map.terrain_grid.grid_width():
		var column: Array = []
		column.resize(map.terrain_grid.grid_depth())
		map.cell_grid.append(column)
	return map


## A structure owned by `a_owner_id`, standing on the 2x2 block at `a_origin` of the grid.
func _structure_on(a_origin: Vector2i, a_owner_id: int) -> Actor:
	var owner: Commander = Commander.new()
	owner.id = a_owner_id
	add_child_autofree(owner)
	var piece: Actor = FakePieces.structure()
	add_child_autofree(piece)
	piece.ownership.commander = owner
	piece.global_position = _map.footprint_centroid(a_origin, _DIMS)
	var cells: Array[Vector2i] = []
	for w: int in _DIMS.x:
		for l: int in _DIMS.y:
			var cell: Vector2i = a_origin + Vector2i(w, l)
			_map.cell_grid[cell.x][cell.y] = piece
			cells.append(cell)
	_map.structure_cell_map[piece] = cells
	return piece


## The commander's blackboard sighting of `a_piece`, as its update would record it.
func _remember(a_piece: Actor) -> void:
	_me.blackboard._upsert(a_piece, 0.0)


func _admits(a_origin: Vector2i) -> bool:
	var xz: Vector3 = _map.footprint_centroid(a_origin, _DIMS)
	return Fixture.valid_placement(
		CommandMessage.new(_map, null, null, xz),
		_DIMS,
		false,
		false,
		PlacementKnowledge.of(_me, _map)
	)


func test_open_ground_is_placeable_wherever_it_was_explored() -> void:
	assert_true(_admits(_IN_VISION), "in vision")
	assert_true(_admits(_FOGGED), "explored, out of vision")


func test_unexplored_ground_refuses_outright() -> void:
	assert_false(_admits(_UNEXPLORED))


func test_an_enemy_structure_in_vision_refuses() -> void:
	_structure_on(_IN_VISION, _ENEMY)
	assert_false(_admits(_IN_VISION))


func test_an_unseen_enemy_structure_in_the_fog_is_not_revealed() -> void:
	_structure_on(_FOGGED, _ENEMY)
	assert_true(_admits(_FOGGED), "the order is accepted; the builder finds out on arrival")


func test_a_remembered_enemy_structure_in_the_fog_refuses() -> void:
	_remember(_structure_on(_FOGGED, _ENEMY))
	assert_false(_admits(_FOGGED))


func test_a_remembered_structure_destroyed_out_of_sight_still_refuses() -> void:
	var piece: Actor = _structure_on(_FOGGED, _ENEMY)
	_remember(piece)
	for cell: Vector2i in _map.structure_cell_map[piece]:
		_map.cell_grid[cell.x][cell.y] = null
	_map.structure_cell_map.erase(piece)
	assert_false(_admits(_FOGGED), "its loss was never seen")


func test_an_own_structure_in_the_fog_refuses() -> void:
	_structure_on(_FOGGED, _ME)
	assert_false(_admits(_FOGGED))


func test_a_neutral_structure_in_the_fog_refuses() -> void:
	_structure_on(_FOGGED, 0)
	assert_false(_admits(_FOGGED))


func test_without_knowledge_the_true_grid_decides() -> void:
	_structure_on(_FOGGED, _ENEMY)
	var xz: Vector3 = _map.footprint_centroid(_FOGGED, _DIMS)
	assert_false(Fixture.valid_placement(CommandMessage.new(_map, null, null, xz), _DIMS))
	assert_true(
		Fixture.valid_placement(
			CommandMessage.new(_map, null, null, _map.footprint_centroid(_UNEXPLORED, _DIMS)), _DIMS
		),
		"the debug spawner's view: unexplored ground is no bar"
	)
