extends GutTest

## THE ACTIVATION AXIS — composition-rework step 1. A piece carrying both a Structure and a
## Movement is a TWO-FORM piece: exactly one of the two is live, and everything that follows
## the form follows the switch — grid registration and the navmesh hole, which component
## `movement` reports, which commands are offered, line-of-fire blocking, the unit/structure
## group, and the commander's structure registry.
##
## No shipped piece has two forms, so the fixture is built here: the Anarchical builder with a
## Structure component added before it enters the tree.
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry
## (CLAUDE.md §A file-scope `preload`…).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TwoFormPiece.gd -gexit

const PIECE_SCENE: Dictionary = FakePieces.BUILDER
const SITE_SCENE: Dictionary = FakePieces.BUILDING
## Height-map corner count; the cell grid is one smaller in each axis.
const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
## Where the piece deploys. Well inside the grid so its footprint has neighbours.
const DEPLOY_CELL: Vector2i = Vector2i(8, 8)


## A Map with a real TerrainGrid, so passability — the navmesh's input — answers truthfully,
## and a hand-managed cell grid; none of the terrain or navmesh loading.
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


func before_each() -> void:
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
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


## The builder, given a one-cell footprint before it enters the tree, owned and on the map.
func _two_form_piece() -> Commandable:
	var piece: Commandable = FakePieces.make(PIECE_SCENE) as Commandable
	var structure := Structure.new()
	structure.name = "Structure"
	piece.add_child(structure)
	_world.add_child(piece)
	piece.ownership.commander = _commander
	piece.map = _map
	piece.global_position = _map.grid_to_world(DEPLOY_CELL)
	return piece


func _deploy_center() -> Vector2:
	return VU.in_xz(_map.grid_to_world(DEPLOY_CELL))


func _blocks_line_of_fire(a_piece: Entity) -> bool:
	return (a_piece.target_body.collision_layer & CollisionLayers.Mask.STRUCTURE_BLOCKER) != 0


# --- Spawning ---------------------------------------------------------------------


func test_a_site_with_no_opinion_spawns_it_mobile() -> void:
	var piece := _two_form_piece()
	assert_true(piece.has_two_forms())
	assert_false(piece.spawns_deployed(), "a spawn site with no opinion does not deploy it")
	assert_false(piece.structure_is_active())
	assert_not_null(piece.movement)
	assert_true(piece.is_in_group("unit"))
	assert_false(piece.is_in_group("structure"))
	assert_false(_map.structure_cell_map.has(piece), "it claims no cells")


func test_a_one_form_piece_has_one_form() -> void:
	var site: Entity = FakePieces.make(SITE_SCENE) as Entity
	autofree(site)
	assert_false(site.has_two_forms())
	assert_true(site.spawns_deployed(), "a fixture-only piece still deploys where it spawns")


# --- Deploying --------------------------------------------------------------------


func test_deploying_claims_the_footprint_and_the_navmesh_hole() -> void:
	var piece := _two_form_piece()
	assert_true(_map.terrain_grid.is_passable(DEPLOY_CELL), "the premise: open ground")
	assert_true(piece.deploy(_deploy_center()))
	assert_true(piece.structure_is_active())
	assert_true(_map.structure_cell_map.has(piece))
	assert_false(_map.terrain_grid.is_passable(DEPLOY_CELL), "its cell leaves the navmesh")


func test_a_deployed_piece_reads_as_having_no_movement() -> void:
	var piece := _two_form_piece()
	piece.deploy(_deploy_center())
	assert_null(piece.movement, "a dormant Movement reads as absent")
	assert_not_null(piece.movement_component, "while the component itself survives")
	assert_false(
		piece.movement_component.avoidance_agent().avoidance_enabled,
		"and its avoidance entry is given back"
	)


func test_a_deployed_piece_is_offered_no_move_order() -> void:
	var piece := _two_form_piece()
	assert_true(CommandContextParser.command_available("command_move", piece))
	piece.deploy(_deploy_center())
	assert_false(
		CommandContextParser.command_available("command_move", piece),
		"or the player could order a building to walk"
	)


func test_a_deployed_piece_blocks_line_of_fire() -> void:
	var piece := _two_form_piece()
	assert_false(_blocks_line_of_fire(piece))
	piece.deploy(_deploy_center())
	assert_true(_blocks_line_of_fire(piece))


func test_deploying_moves_it_between_the_groups_and_the_registry() -> void:
	var piece := _two_form_piece()
	piece.deploy(_deploy_center())
	assert_true(piece.is_in_group("structure"))
	assert_false(piece.is_in_group("unit"))
	assert_true(_commander._structures_of(piece.id).contains(piece))


func test_deploying_onto_an_occupied_cell_is_refused() -> void:
	var piece := _two_form_piece()
	var site: Entity = FakePieces.make(SITE_SCENE) as Entity
	_world.add_child(site)
	_map.cell_grid[DEPLOY_CELL.x][DEPLOY_CELL.y] = site
	assert_false(piece.deploy(_deploy_center()))
	assert_false(piece.structure_is_active(), "and nothing changed")
	assert_not_null(piece.movement)


func test_deploying_twice_is_refused() -> void:
	var piece := _two_form_piece()
	piece.deploy(_deploy_center())
	assert_false(piece.deploy(_deploy_center()))


# --- Undeploying ------------------------------------------------------------------


func test_undeploying_gives_everything_back() -> void:
	var piece := _two_form_piece()
	piece.deploy(_deploy_center())
	piece.undeploy()
	assert_false(piece.structure_is_active())
	assert_false(_map.structure_cell_map.has(piece))
	assert_true(_map.terrain_grid.is_passable(DEPLOY_CELL), "the navmesh hole closes")
	assert_not_null(piece.movement)
	assert_true(
		piece.movement_component.avoidance_agent().avoidance_enabled,
		"avoidance is re-armed for its owner"
	)
	assert_true(CommandContextParser.command_available("command_move", piece))
	assert_false(_blocks_line_of_fire(piece))
	assert_true(piece.is_in_group("unit"))
	assert_false(_commander._structures_of(piece.id).contains(piece))
