extends GutTest

## OCCUPANCY AND OBSTRUCTION ARE SEPARATE. Map.add_structure writes a fixture's cells into
## `cell_grid` (nothing else may be placed there) and, only if its Structure is an obstruction,
## into the terrain grid (units may not walk there). The extraction site is the fixture that
## occupies without obstructing; the extractor built over it is what obstructs.
## See gdd/systems/terrain-and-navigation/map-composition.md §Occupancy and obstruction.
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry
## (CLAUDE.md §A file-scope `preload`…).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapOccupancy.gd -gexit

const SITE_SCENE: Dictionary = FakePieces.BUILDING
const EXTRACTOR_SCENE: Dictionary = FakePieces.BUILDING
const BUILDING_SCENE: Dictionary = FakePieces.BUILDING
## Height-map corner count; the cell grid is one smaller in each axis.
const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1
## Every piece here is 2×2, with its footprint's min corner at ORIGIN.
const DIMS: Vector2i = Vector2i(2, 2)
const ORIGIN: Vector2i = Vector2i(6, 6)


## A Map with a real TerrainGrid, so passability — the navmesh's input — answers truthfully,
## and a hand-managed cell grid; none of the terrain or navmesh loading.
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
var _neutral: Commander
var _commander: Commander


func before_each() -> void:
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	_neutral = Commander.new()
	_neutral.id = 0
	_world.add_child(_neutral)
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	for commander: Commander in [_neutral, _commander]:
		commander.map = _map
		commander.set_physics_process(false)


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


## Several scenes here still ship without flavour text, which Commandable reports with a
## push_error that GUT would count against the test. Dismissed by message only.
func _dismiss_missing_flavor_text() -> void:
	for tracked in get_errors():
		if tracked.contains_text("was given an empty description") \
			or tracked.contains_text("was given an empty verbose description"):
			tracked.handled = true


## A piece of `a_scene`, owned by `a_commander` and placed through Map.add_structure on the
## DIMS footprint at ORIGIN.
func _place(a_options: Dictionary, a_commander: Commander) -> Entity:
	var entity: Entity = FakePieces.make(a_options) as Entity
	a_commander.add_child(entity)
	entity.initialize(_map, a_commander)
	_dismiss_missing_flavor_text()
	_map.add_structure(entity, VU.inXZ(_map.footprint_centroid(ORIGIN, DIMS)))
	return entity


func _footprint() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx: int in DIMS.x:
		for dz: int in DIMS.y:
			cells.append(ORIGIN + Vector2i(dx, dz))
	return cells


func _all_passable() -> bool:
	return _footprint().all(func(c: Vector2i) -> bool: return _map.terrain_grid.is_passable(c))


func _none_passable() -> bool:
	return _footprint().all(func(c: Vector2i) -> bool: return not _map.terrain_grid.is_passable(c))


func _all_occupied_by(a_entity: Entity) -> bool:
	return _footprint().all(func(c: Vector2i) -> bool: return _map.cell_grid[c.x][c.y] == a_entity)


# --- An ordinary structure -----------------------------------------------------------

func test_an_ordinary_structure_occupies_and_obstructs() -> void:
	var building: Entity = _place(BUILDING_SCENE, _neutral)
	assert_true(_all_occupied_by(building))
	assert_true(_none_passable(), "its cells leave the navmesh")
	assert_true(building.is_grid_obstruction())


func test_removing_an_ordinary_structure_frees_its_cells() -> void:
	var building: Entity = _place(BUILDING_SCENE, _neutral)
	_map.remove_structure(building)
	assert_true(_all_occupied_by(null))
	assert_true(_all_passable())
	assert_false(building.is_on_grid())


# --- The extraction site: occupant, not obstruction ---------------------------------

func test_a_site_occupies_its_cells_without_obstructing_them() -> void:
	var site: Entity = _place(SITE_SCENE, _neutral)
	assert_true(_all_occupied_by(site), "nothing else may be placed there")
	assert_true(_all_passable(), "units walk across it")
	assert_true(site.is_on_grid())
	assert_false(site.is_grid_obstruction())


func test_a_site_does_not_collide_with_units() -> void:
	var site: Entity = _place(SITE_SCENE, _neutral)
	assert_eq(site.collision_layer & CollisionLayers.Mask.MOVEMENT_OBSTRUCTION, 0,
		"a walkable fixture must not stop units with its body either")


# --- An extractor over its site ------------------------------------------------------

func test_an_extractor_on_a_site_obstructs_the_sites_cells() -> void:
	var site: Entity = _place(SITE_SCENE, _neutral)
	var extractor: Entity = _place(EXTRACTOR_SCENE, _commander)
	assert_true(_all_occupied_by(site), "the site stays the cells' occupant")
	assert_eq(_map.structure_cell_map.get(extractor, []), _map.structure_cell_map[site],
		"the extractor registers the site's footprint")
	assert_true(_none_passable(), "and it is what obstructs them")
	assert_true(extractor.is_grid_obstruction())
	assert_eq(ExtractionSite.of(site).extractor, extractor, "the two are bound")


func test_removing_the_extractor_leaves_the_site_walkable_and_in_place() -> void:
	var site: Entity = _place(SITE_SCENE, _neutral)
	var extractor: Entity = _place(EXTRACTOR_SCENE, _commander)
	_map.remove_structure(extractor)
	assert_true(_all_occupied_by(site), "the site is still there to be worked again")
	assert_true(_map.structure_cell_map.has(site))
	assert_true(_all_passable())
