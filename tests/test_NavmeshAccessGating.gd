extends GutTest

## WHERE A BUILDING MAY GO WITHOUT STRANDING ITS OWN UNITS — the human-facing half of
## NavPlacement (scripts/maps/nav_placement.gd), which until now only the bot asked.
##
## Two wirings, not a re-test of NavPlacement's own rules (test_NavPlacement.gd already
## covers those against a brute-force reference):
##
##   * Build.meets_precondition refuses a placement that would split the walkable surface
##     (rule 1, every structure) or leave a PRODUCTION structure no side to spawn from
##     (rule 2, scoped to a Production component — NavPlacement.accepts' `a_needs_access`).
##   * Train.meets_precondition refuses to train at a producer the grid can show has no
##     navmesh side right now (Commandable.has_navmesh_access) — the safety net for a
##     structure placement can no longer create new, but terrain changing later or a
##     scenario-authored pocket can still reach.
##
## gdd/tasks.md "CPU Bot Behavior Work" — the navmesh-spawn question, answered 4 + 1.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavmeshAccessGating.gd -gexit

const PRODUCER_TYPE: StringName = &"fake_producer"
const PRODUCTION_DIMS: Vector2i = Vector2i(3, 3)
## Anarchical, so the anarchical builder below may place it, and with no Production
## component — the "everything else" side of the rule-2 scoping.
const PLAIN_TYPE: StringName = &"fake_plain"
const TRAINEE_TYPE: StringName = &"fake_trainee"
const PLAIN_DIMS: Vector2i = Vector2i(2, 2)
const BUILDER_SCENE: Dictionary = {"speed": 2.0, "vision": 8.0,
	"builds": [&"fake_producer", &"fake_plain"]}
## Height-map corner count; the cell grid is one smaller in each axis. Large enough to hold
## three well-separated fixtures (a sealed 3x3 pocket, a sealed 2x2 pocket, and a walled
## corridor with a gap) with open ground between and around them.
const MAP_CORNERS: int = 41
const GRID_CELLS: int = MAP_CORNERS - 1


## A Map with a real TerrainGrid (so passability/region answers are real) and a hand-managed
## cell grid — the same fixture shape as test_BuildApproach.gd's StubMap.
class StubMap extends Map:
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
		return a_coords.x >= 0 and a_coords.x < GRID_CELLS \
			and a_coords.y >= 0 and a_coords.y < GRID_CELLS


var _world: Node3D
var _map: StubMap
var _commander: Commander


var PRODUCTION_TOOL: Tool
var PLAIN_TOOL: Tool
var TRAIN_TOOL: Tool


func after_each() -> void:
	FakePieces.restore_tools()


func before_each() -> void:
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.add_energy(10000)
	_commander.technology_mapping = {PRODUCER_TYPE: FakePieces.tech(), PLAIN_TYPE: FakePieces.tech(),
		TRAINEE_TYPE: FakePieces.tech()}
	PRODUCTION_TOOL = FakePieces.register_tool(FakePieces.tool(PRODUCER_TYPE,
		{"structure": true, "production": true, "dimensions": PRODUCTION_DIMS}))
	PLAIN_TOOL = FakePieces.register_tool(FakePieces.tool(PLAIN_TYPE,
		{"structure": true, "dimensions": PLAIN_DIMS}))
	TRAIN_TOOL = FakePieces.register_tool(FakePieces.tool(TRAINEE_TYPE, FakePieces.PLAIN, [],
		ControlBinding.ControlContext.TRAIN))
	_commander.set_physics_process(false)


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


## World position whose footprint (of `a_dims`) lands exactly on `a_origin` — the exact
## algebraic inverse of Map.footprint_origin under the identity transform this fixture never
## disturbs, so it holds for both odd and even dims.
func _world_for_origin(a_origin: Vector2i, a_dims: Vector2i) -> Vector3:
	var half: float = (MAP_CORNERS - 1) * 0.5
	return Vector3(
		a_origin.x + a_dims.x * 0.5 - half, 0.0, a_origin.y + a_dims.y * 0.5 - half
	)


func _rect(a_origin: Vector2i, a_dims: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for w: int in a_dims.x:
		for l: int in a_dims.y:
			out.append(a_origin + Vector2i(w, l))
	return out


## Blocks the one-cell-thick ring around `a_interior` (a rect of `a_dims`), leaving the
## interior itself passable but reachable from nowhere else — a pocket with no gate at all.
func _seal_pocket(a_interior_origin: Vector2i, a_dims: Vector2i) -> void:
	var ring := _rect(a_interior_origin - Vector2i.ONE, a_dims + Vector2i(2, 2))
	var interior: Dictionary = {}
	for cell: Vector2i in _rect(a_interior_origin, a_dims):
		interior[cell] = true
	for cell: Vector2i in ring:
		if not interior.has(cell):
			_map.terrain_grid.set_blocked(cell, true)


func _make_builder() -> Commandable:
	var builder: Commandable = FakePieces.make(BUILDER_SCENE) as Commandable
	_world.add_child(builder)
	builder.ownership.commander = _commander
	builder.map = _map
	return builder


## A producer registered directly on the grid at `a_origin`, bypassing Build entirely — the
## "terrain changed later" and "authored into a pocket" cases Train's own gate exists for.
func _register_producer(a_origin: Vector2i, a_dims: Vector2i, a_trainee: StringName) -> Commandable:
	var producer: Commandable = FakePieces.structure({"production": true, "dimensions": a_dims})
	_world.add_child(producer)
	producer.ownership.commander = _commander
	producer.map = _map
	var cells: Array = _rect(a_origin, a_dims)
	_map.structure_cell_map[producer] = cells
	for cell: Vector2i in cells:
		_map.cell_grid[cell.x][cell.y] = producer
	producer.global_position = _map.footprint_centroid(a_origin, a_dims)
	if a_trainee != &"":
		producer.production.producible_types = [a_trainee]
	return producer


# ─── COMMANDABLE.HAS_NAVMESH_ACCESS ─────────────────────────────────────────

func test_has_navmesh_access_is_true_with_no_map() -> void:
	var producer: Commandable = FakePieces.structure({"production": true, "dimensions": PRODUCTION_DIMS})
	add_child_autofree(producer)
	assert_true(producer.has_navmesh_access(), "nothing to ask, so nothing to refuse")


func test_has_navmesh_access_is_true_for_an_open_footprint() -> void:
	var producer := _register_producer(Vector2i(2, 2), PRODUCTION_DIMS, &"")
	assert_true(producer.has_navmesh_access())


func test_has_navmesh_access_is_false_for_a_sealed_footprint() -> void:
	var origin := Vector2i(10, 10)
	_seal_pocket(origin, PRODUCTION_DIMS)
	var producer := _register_producer(origin, PRODUCTION_DIMS, &"")
	assert_false(producer.has_navmesh_access(), "walled in on every side")


# ─── TRAIN — REFUSES A PRODUCER THE GRID SHOWS IS SEALED IN ────────────────

func test_train_refuses_at_a_sealed_producer() -> void:
	var origin := Vector2i(10, 10)
	_seal_pocket(origin, PRODUCTION_DIMS)
	var trainee: StringName = TRAINEE_TYPE
	var producer := _register_producer(origin, PRODUCTION_DIMS, trainee)
	var message := CommandMessage.new(_map, null, TRAIN_TOOL)
	assert_eq(
		Train.meets_precondition(producer, message),
		MoveCommand.PreconditionFailureCause.NO_NAVMESH_ACCESS
	)


func test_train_allows_an_open_producer() -> void:
	var trainee: StringName = TRAINEE_TYPE
	var producer := _register_producer(Vector2i(2, 2), PRODUCTION_DIMS, trainee)
	var message := CommandMessage.new(_map, null, TRAIN_TOOL)
	assert_eq(
		Train.meets_precondition(producer, message), MoveCommand.PreconditionFailureCause.NONE
	)


# ─── BUILD — RULE 2, SCOPED TO A PRODUCTION STRUCTURE ──────────────────────

func test_build_refuses_a_production_structure_with_no_exposed_side() -> void:
	var origin := Vector2i(10, 10)
	_seal_pocket(origin, PRODUCTION_DIMS)
	var at: Vector3 = _world_for_origin(origin, PRODUCTION_DIMS)
	assert_eq(_map.footprint_cells(Vector2(at.x, at.z), PRODUCTION_DIMS), _rect(origin, PRODUCTION_DIMS),
		"guards the fixture: the world position must resolve to the sealed origin")
	var builder := _make_builder()
	assert_eq(
		Build.meets_precondition(builder, CommandMessage.new(_map, null, PRODUCTION_TOOL, at)),
		MoveCommand.PreconditionFailureCause.INVALID_PLACEMENT
	)


func test_build_allows_a_non_production_structure_with_no_exposed_side() -> void:
	# The same pocket a producer is refused: rule 2 (a side to spawn from) does not apply to
	# a structure with no Production component, and rule 1 is trivially satisfied because the
	# pocket was never connected to anything to begin with.
	var origin := Vector2i(20, 20)
	_seal_pocket(origin, PLAIN_DIMS)
	var at: Vector3 = _world_for_origin(origin, PLAIN_DIMS)
	assert_eq(_map.footprint_cells(Vector2(at.x, at.z), PLAIN_DIMS), _rect(origin, PLAIN_DIMS),
		"guards the fixture")
	var builder := _make_builder()
	assert_eq(
		Build.meets_precondition(builder, CommandMessage.new(_map, null, PLAIN_TOOL, at)),
		MoveCommand.PreconditionFailureCause.NONE
	)


# ─── BUILD — RULE 1, EVERY STRUCTURE ────────────────────────────────────────

func test_build_refuses_a_placement_that_seals_a_corridor() -> void:
	# A wall two cells thick at x = 30..31, open only at z = 15..16 — the one route between
	# the two halves of the map. Placing the 2x2 tool exactly on the gap reseals it.
	var gap_origin := Vector2i(30, 15)
	for x: int in range(30, 32):
		for z: int in range(0, GRID_CELLS):
			if z >= 15 and z <= 16:
				continue  # the gap
			_map.terrain_grid.set_blocked(Vector2i(x, z), true)
	assert_eq(_map.terrain_grid.component_at(Vector2i(0, 15)), _map.terrain_grid.component_at(Vector2i(38, 15)),
		"guards the fixture: the gap must actually join the two halves")
	var at: Vector3 = _world_for_origin(gap_origin, PLAIN_DIMS)
	assert_eq(_map.footprint_cells(Vector2(at.x, at.z), PLAIN_DIMS), _rect(gap_origin, PLAIN_DIMS),
		"guards the fixture")
	var builder := _make_builder()
	assert_eq(
		Build.meets_precondition(builder, CommandMessage.new(_map, null, PLAIN_TOOL, at)),
		MoveCommand.PreconditionFailureCause.INVALID_PLACEMENT
	)


func test_build_allows_an_ordinary_open_placement() -> void:
	var origin := Vector2i(2, 2)
	var at: Vector3 = _world_for_origin(origin, PRODUCTION_DIMS)
	var builder := _make_builder()
	assert_eq(
		Build.meets_precondition(builder, CommandMessage.new(_map, null, PRODUCTION_TOOL, at)),
		MoveCommand.PreconditionFailureCause.NONE
	)
