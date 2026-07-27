extends GutTest

## Where the debug spawner may put a piece (DebugPlacement.admits), putting it there, and the
## debug delete. A Map with a real TerrainGrid and a hand-managed cell grid, as in
## test_MapOccupancy; none of the terrain or navmesh loading.
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry.

const BUILDING_SCENE: String = "res://scenes/entities/structures/nt/nt_building.tscn"
const SITE_SCENE: String = "res://scenes/entities/structures/nt/nt_extractionSite.tscn"
const WALKER_SCENE: String = "res://scenes/entities/units/nt/nt_bioLight_terrestrial.tscn"
const FLIER_SCENE: String = "res://scenes/entities/units/nt/nt_aircraftMedium_transport.tscn"

const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
## A cell well inside the map, with room around it for a 2×2 footprint.
const OPEN_CELL: Vector2i = Vector2i(8, 8)


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
var _sources: Array[Entity] = []


func before_each() -> void:
	_world = Node3D.new()
	_map = StubMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	_map.add_child(region)
	var heights := HeightMapShape3D.new()
	heights.map_width = MAP_CORNERS
	heights.map_depth = MAP_CORNERS
	_map.height_map = heights
	_world.add_child(_map)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.map = _map
	_commander.set_physics_process(false)


func after_each() -> void:
	for source: Entity in _sources:
		source.free()
	_sources.clear()
	DebugMode.configure(false)


## An out-of-tree instance, as the controller holds for the armed piece.
func _source(a_scene: String) -> Entity:
	var entity: Entity = load(a_scene).instantiate() as Entity
	_sources.append(entity)
	return entity


func _at(a_cell: Vector2i) -> CommandMessage:
	var xz: Vector2 = VU.inXZ(_map.footprint_centroid(a_cell, Vector2i.ONE))
	return CommandMessage.new(_map, null, null, Vector3(xz.x, 0.0, xz.y))


func _dismiss_content_errors() -> void:
	for tracked in get_errors():
		if tracked.contains_text("empty description") or tracked.contains_text("empty verbose"):
			tracked.handled = true


func test_a_fixture_fits_open_ground() -> void:
	assert_true(DebugPlacement.admits(_source(BUILDING_SCENE), _at(OPEN_CELL)))


func test_a_fixture_is_refused_over_an_occupied_cell() -> void:
	_map.cell_grid[OPEN_CELL.x][OPEN_CELL.y] = _world
	assert_false(DebugPlacement.admits(_source(BUILDING_SCENE), _at(OPEN_CELL)))


func test_a_walker_needs_navigable_ground() -> void:
	var walker: Entity = _source(WALKER_SCENE)
	assert_true(DebugPlacement.admits(walker, _at(OPEN_CELL)), "open ground takes it")
	_map.terrain_grid.place_building([OPEN_CELL], _world)
	assert_false(DebugPlacement.admits(walker, _at(OPEN_CELL)), "a building's cell does not")


func test_a_flier_may_go_over_a_building() -> void:
	_map.terrain_grid.place_building([OPEN_CELL], _world)
	assert_true(DebugPlacement.admits(_source(FLIER_SCENE), _at(OPEN_CELL)))


func test_nothing_goes_off_the_map() -> void:
	var off: CommandMessage = CommandMessage.new(_map, null, null, Vector3(-50.0, 0.0, -50.0))
	assert_false(DebugPlacement.admits(_source(FLIER_SCENE), off))


func test_a_placed_structure_stands_finished_on_its_cells() -> void:
	var xz: Vector2 = _at(OPEN_CELL).xz_position
	var structure: Entity = DebugPlacement.spawn(load(BUILDING_SCENE), _map, _commander, xz)
	_dismiss_content_errors()
	assert_eq(structure.commander, _commander, "it is the owner's")
	assert_false(structure.is_planned, "and finished, not a blueprint")
	assert_true(_map.structure_cell_map.has(structure), "on the grid")


## A delete is a death: a piece with no Commandable tick to notice its hit points dies at once.
func test_delete_kills_a_selected_feature() -> void:
	var site: Entity = DebugPlacement.spawn(load(SITE_SCENE), _map, _commander,
		_at(OPEN_CELL).xz_position)
	_dismiss_content_errors()
	var controller := RTSController.new()
	autofree(controller)
	controller.selection = [site]
	controller.delete_selection()
	assert_true(site.is_queued_for_deletion(), "it died")
	assert_false(_map.structure_cell_map.has(site), "and gave its cells back")
	assert_true(controller.selection.is_empty(), "and left the selection")


## A bot takes up a unit it did not train: its units are read from the tree, so a spawned one
## is simply one of them.
func test_a_bot_counts_a_spawned_unit_as_its_own() -> void:
	var bot := Bot.new()
	bot.id = 2
	_world.add_child(bot)
	bot.map = _map
	bot.set_physics_process(false)
	var unit: Entity = DebugPlacement.spawn(load(WALKER_SCENE), _map, bot,
		_at(OPEN_CELL).xz_position)
	_dismiss_content_errors()
	assert_true(bot.get_units().has(unit))


## A purchase through another commander's piece is that commander's to pay.
func test_the_selection_owner_pays_for_its_purchases() -> void:
	var bot := Bot.new()
	bot.id = 2
	_world.add_child(bot)
	bot.set_physics_process(false)
	var unit: Entity = DebugPlacement.spawn(load(WALKER_SCENE), _map, bot,
		_at(OPEN_CELL).xz_position)
	_dismiss_content_errors()
	var controller := RTSController.new()
	autofree(controller)
	controller.selection = [unit]
	assert_eq(controller._selection_commander(), bot)
