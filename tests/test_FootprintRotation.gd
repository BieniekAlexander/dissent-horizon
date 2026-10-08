extends GutTest

## FOOTPRINT ROTATION — a piece turned in quarter steps claims the footprint turned with it.
## gdd/systems/terrain-and-navigation/footprint-rotation.md
##
## Three layers, each against a fixture built here (no authored map, no authored scenario):
##   * the pure arithmetic on Structure (which way is front, which count a direction means);
##   * Map.add_structure registering the ORIENTED cells and turning the piece; and
##   * Build's placement check asking about them — a turn that makes a footprint illegal is refused.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_FootprintRotation.gd -gexit

const LONG_SCENE: Dictionary = {"structure": true, "dimensions": Vector2i(3, 5)}
## The an_infrastructure tool's second variant is the long (3×5) neutral building.
const TOOL_TYPE: StringName = &"fake_building"
const SQUARE: StringName = &"fake_square"
const LONG: StringName = &"fake_long"
const LONG_DIMS: Vector2i = Vector2i(3, 5)
const BUILDER_SCENE: Dictionary = {"speed": 2.0, "vision": 8.0, "builds": [&"fake_building"]}
const MAP_CORNERS: int = 41
const GRID_CELLS: int = MAP_CORNERS - 1


class StubMap:
	extends Map

	func _ready() -> void:
		cell_grid = []
		for x: int in GRID_CELLS:
			var col: Array = []
			for y: int in GRID_CELLS:
				col.append(null)
			cell_grid.append(col)
		terrain_grid = TerrainGrid.new()
		terrain_grid.height_map = height_map
		terrain_grid.terrain_body = terrain_body
		add_child(terrain_grid)

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return (
			a_coords.x >= 0
			and a_coords.x < GRID_CELLS
			and a_coords.y >= 0
			and a_coords.y < GRID_CELLS
		)


var _world: Node3D
var _map: StubMap
var _commander: Commander

var _tool: Tool


func before_each() -> void:
	FakePieces.install_families(
		[{"id": SQUARE, "footprint": Vector2i(4, 4)}, {"id": LONG, "footprint": LONG_DIMS}]
	)
	_tool = FakePieces.register_tool(FakePieces.tool(TOOL_TYPE, {}, [SQUARE, LONG]))
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.add_energy(10000)
	_commander.set_physics_process(false)
	_commander.technology_mapping = {
		TOOL_TYPE: FakePieces.tech(), SQUARE: FakePieces.tech(), LONG: FakePieces.tech()
	}


func after_each() -> void:
	FakePieces.restore_families()
	FakePieces.restore_tools()


func _make_map() -> StubMap:
	var stub := StubMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	stub.add_child(region)
	var heights := HeightMapShape3D.new()
	heights.map_width = MAP_CORNERS
	heights.map_depth = MAP_CORNERS
	stub.height_map = heights
	return stub


## World position whose footprint (of `a_dims`) lands exactly on `a_origin` — the inverse of
## Map.footprint_origin under the identity transform this fixture never disturbs.
func _world_for_origin(a_origin: Vector2i, a_dims: Vector2i) -> Vector2:
	var half: float = (MAP_CORNERS - 1) * 0.5
	return Vector2(a_origin.x + a_dims.x * 0.5 - half, a_origin.y + a_dims.y * 0.5 - half)


func _long_building() -> Actor:
	var building: Actor = FakePieces.make(LONG_SCENE) as Actor
	_world.add_child(building)
	building.ownership.commander = _commander
	building.map = _map
	return building


## The piece's target shape as the footprint rectangle, whatever the scene happens to ship.
func _give_box_shape(a_piece: Actor) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(LONG_DIMS.x, 1.0, LONG_DIMS.y)
	(a_piece.hurtbox.get_node("HurtboxShape") as CollisionShape3D).shape = shape


func _make_builder() -> Actor:
	var builder: Actor = FakePieces.make(BUILDER_SCENE) as Actor
	_world.add_child(builder)
	builder.ownership.commander = _commander
	builder.map = _map
	return builder


# ─── THE ARITHMETIC ─────────────────────────────────────────────────────────


func test_an_odd_count_swaps_the_dimensions_and_an_even_one_does_not() -> void:
	assert_eq(Fixture.oriented_dimensions(LONG_DIMS, 0), Vector2i(3, 5))
	assert_eq(Fixture.oriented_dimensions(LONG_DIMS, 1), Vector2i(5, 3))
	assert_eq(
		Fixture.oriented_dimensions(LONG_DIMS, 2), Vector2i(3, 5), "180° claims the same cells"
	)
	assert_eq(Fixture.oriented_dimensions(LONG_DIMS, 3), Vector2i(5, 3))
	assert_eq(Fixture.oriented_dimensions(LONG_DIMS, 4), Vector2i(3, 5), "wraps")
	assert_eq(Fixture.oriented_dimensions(LONG_DIMS, -1), Vector2i(5, 3), "and wraps below zero")


func test_a_count_is_a_counter_clockwise_yaw_from_above() -> void:
	for turns: int in 4:
		assert_almost_eq(Fixture.yaw_of(turns), turns * PI * 0.5, 0.0001)
	assert_eq(Fixture.quarter_turns_of_yaw(0.0), 0)
	assert_eq(
		Fixture.quarter_turns_of_yaw(PI * 0.5 + 0.01),
		1,
		"a near-quarter yaw is read as the quarter"
	)
	assert_eq(Fixture.quarter_turns_of_yaw(PI), 2)
	assert_eq(Fixture.quarter_turns_of_yaw(-PI * 0.5), 3, "a negative yaw wraps")


func test_front_is_plus_z_and_each_count_faces_the_next_axis() -> void:
	# The convention the models are authored to and Movement.get_facing reads: yaw 0 faces +Z.
	assert_eq(Fixture.facing_of(0), Vector2(0, 1))
	assert_eq(Fixture.facing_of(1), Vector2(1, 0))
	assert_eq(Fixture.facing_of(2), Vector2(0, -1))
	assert_eq(Fixture.facing_of(3), Vector2(-1, 0))
	# ...and it agrees with what a yawed node actually does in the engine.
	var node := Node3D.new()
	add_child_autofree(node)
	for turns: int in 4:
		node.rotation.y = Fixture.yaw_of(turns)
		var forward: Vector3 = node.global_transform.basis * Vector3.BACK
		var facing: Vector2 = Fixture.facing_of(turns)
		assert_almost_eq(forward.x, facing.x, 0.0001, "count %d, x" % turns)
		assert_almost_eq(forward.z, facing.y, 0.0001, "count %d, z" % turns)


func test_a_drag_direction_reads_as_the_nearest_axis() -> void:
	for turns: int in 4:
		assert_eq(Fixture.quarter_turns_facing(Fixture.facing_of(turns) * 3.0), turns)
	assert_eq(Fixture.quarter_turns_facing(Vector2(5, 1)), 1)
	assert_eq(Fixture.quarter_turns_facing(Vector2(-5, 2)), 3)
	assert_eq(Fixture.quarter_turns_facing(Vector2(1, -5)), 2)
	assert_eq(Fixture.quarter_turns_facing(Vector2(2, 1)), 1)


func test_a_drag_with_no_direction_keeps_the_fallback() -> void:
	assert_eq(Fixture.quarter_turns_facing(Vector2.ZERO, 3), 3)


func test_a_diagonal_resolves_the_same_way_every_time() -> void:
	# A tie must not flicker between two answers frame to frame.
	assert_eq(Fixture.quarter_turns_facing(Vector2(2, 2)), 0)
	assert_eq(Fixture.quarter_turns_facing(Vector2(-2, -2)), 2)


# ─── REGISTERING A TURNED PIECE ─────────────────────────────────────────────


func test_add_structure_registers_the_unturned_cells_by_default() -> void:
	var building := _long_building()
	var origin := Vector2i(10, 10)
	_map.add_structure(building, _world_for_origin(origin, LONG_DIMS))
	assert_eq(_map.structure_cell_map[building].size(), 15)
	assert_eq(_map.structure_cell_map[building].has(origin + Vector2i(2, 4)), true)
	assert_eq(
		_map.structure_cell_map[building].has(origin + Vector2i(4, 2)), false, "3 wide, 5 deep"
	)


func test_add_structure_registers_the_turned_cells() -> void:
	var building := _long_building()
	var origin := Vector2i(10, 10)
	_map.add_structure(building, _world_for_origin(origin, Vector2i(5, 3)), 1)
	var cells: Array = _map.structure_cell_map[building]
	assert_eq(cells.size(), 15)
	assert_true(cells.has(origin + Vector2i(4, 2)), "5 wide, 3 deep after a quarter turn")
	assert_false(cells.has(origin + Vector2i(2, 4)))
	assert_eq((building.get_node("Fixture") as Fixture).quarter_turns, 1)
	assert_almost_eq(
		building.rotation.y, PI * 0.5, 0.0001, "the piece itself is turned, model and all"
	)


func test_a_half_turn_claims_the_cells_an_unturned_one_does() -> void:
	var a := _long_building()
	var b := _long_building()
	var at: Vector2 = _world_for_origin(Vector2i(6, 6), LONG_DIMS)
	_map.add_structure(a, at, 0)
	var plain: Array = _map.structure_cell_map[a].duplicate()
	_map.remove_structure(a)
	_map.add_structure(b, at, 2)
	var turned: Array = _map.structure_cell_map[b]
	plain.sort()
	turned = turned.duplicate()
	turned.sort()
	assert_eq(turned, plain)
	assert_almost_eq(absf(b.rotation.y), PI, 0.0001, "but it faces the other way")


func test_an_unspecified_turn_leaves_the_piece_as_it_is() -> void:
	# The default (-1) is "as placed": a blueprint set to a count before it is committed, and an
	# event's spawn, keep theirs — and a piece with a yaw of its own is not snapped to zero.
	var building := _long_building()
	(building.get_node("Fixture") as Fixture).quarter_turns = 1
	_map.add_structure(building, _world_for_origin(Vector2i(8, 8), Vector2i(5, 3)))
	assert_eq(_map.structure_cell_map[building].size(), 15)
	assert_true(_map.structure_cell_map[building].has(Vector2i(12, 10)), "still 5 wide")


func test_a_turned_piece_measures_its_ranges_from_the_turned_rectangle() -> void:
	# What the hull's rectangle is sized to is the piece's own business; what rotation owes it is
	# that the rectangle TURNS with the piece, because Entity.hull reads the shape's global basis.
	var building := _long_building()
	_give_box_shape(building)
	_map.add_structure(building, _world_for_origin(Vector2i(10, 10), Vector2i(5, 3)), 1)
	var hull: Hull = building.hull()
	assert_true(hull.is_rect(), "guards the fixture: the piece has a box target shape")
	# Turned a quarter, the rectangle's own X axis lies along world -Z.
	assert_almost_eq(hull.axis_x.x, 0.0, 0.0001)
	assert_almost_eq(hull.axis_x.y, -1.0, 0.0001)
	var unturned := _long_building()
	_give_box_shape(unturned)
	_map.add_structure(unturned, _world_for_origin(Vector2i(20, 20), LONG_DIMS), 0)
	assert_almost_eq(unturned.hull().axis_x.x, 1.0, 0.0001)


func test_a_scene_placed_piece_reads_its_count_from_its_yaw() -> void:
	# Entity._auto_initialize's rule, without a scene to place it in.
	assert_eq(Fixture.quarter_turns_of_yaw(deg_to_rad(89.0)), 1)
	assert_eq(Fixture.quarter_turns_of_yaw(deg_to_rad(181.0)), 2)
	assert_eq(Fixture.quarter_turns_of_yaw(deg_to_rad(-91.0)), 3)


# ─── THE ORDER ──────────────────────────────────────────────────────────────


func _long_tool() -> Tool:
	return _tool.with_variant(1)


func test_a_message_defaults_to_no_turn_and_copies_its_count() -> void:
	var message := CommandMessage.new(_map)
	assert_eq(message.quarter_turns, 0)
	message.quarter_turns = 3
	assert_eq(CommandMessage.deep_copy(message).quarter_turns, 3)


func test_build_reads_the_turned_footprint_when_it_judges_a_placement() -> void:
	var builder := _make_builder()
	# Aim so the 3×5 footprint sits at origin (10, 10). Turned a quarter, the same aim gives a 5×3
	# footprint whose origin the map re-derives — so block a cell only the turned one covers.
	var at: Vector2 = _world_for_origin(Vector2i(10, 10), LONG_DIMS)
	var plain: Array[Vector2i] = _map.footprint_cells(at, LONG_DIMS)
	var turned: Array[Vector2i] = _map.footprint_cells(at, Vector2i(5, 3))
	var only_turned: Vector2i = Vector2i(-1, -1)
	for cell: Vector2i in turned:
		if not plain.has(cell):
			only_turned = cell
			break
	assert_ne(only_turned, Vector2i(-1, -1), "guards the fixture: the two footprints must differ")
	_map.cell_grid[only_turned.x][only_turned.y] = Node.new()
	var message := CommandMessage.new(_map, null, _long_tool(), Vector3(at.x, 0.0, at.y))
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.NONE,
		"unturned, the footprint clears the obstruction"
	)
	message.quarter_turns = 1
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.INVALID_PLACEMENT,
		"turned, it lands on it and is refused"
	)
	message.quarter_turns = 2
	assert_eq(
		Build.meets_precondition(builder, message),
		MoveCommand.PreconditionFailureCause.NONE,
		"a half turn claims what the unturned one did"
	)


func test_a_blueprint_stands_on_and_faces_the_turned_footprint() -> void:
	var at: Vector2 = _world_for_origin(Vector2i(12, 12), Vector2i(5, 3))
	var message := CommandMessage.new(_map, null, _long_tool(), Vector3(at.x, 0.0, at.y))
	message.quarter_turns = 1
	var blueprint: Actor = Build.plan_structure(_commander, message)
	assert_not_null(blueprint)
	if blueprint == null:
		return
	assert_eq((blueprint.get_node("Fixture") as Fixture).quarter_turns, 1)
	assert_almost_eq(blueprint.rotation.y, PI * 0.5, 0.0001)
	var planned: Dictionary = _commander.planned_footprint_cells()
	assert_eq(planned.size(), 15)
	assert_true(planned.has(Vector2i(16, 13)), "the blueprint holds the 5×3 cells")
	assert_false(planned.has(Vector2i(13, 16)))
	# Committing it lays the same oriented cells on the grid.
	blueprint.commit_construction(_map, at)
	assert_true(_map.structure_cell_map[blueprint].has(Vector2i(16, 13)))
