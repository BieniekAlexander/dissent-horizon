extends GutTest

## Building one structure ON TOP OF another — an Extractor over its site, a Safehouse over a
## neutral Building — plus the footprint agreement that makes any of it work.
##
## Two rules are pinned down here:
##   * ONE placement resolution. The ghost the player aims, the blueprint that goes up on
##     confirmation, and the structure a builder finally lays down are all resolved by
##     Map.footprint_origin. They used to disagree for EVEN footprints (the controller
##     re-derived the origin as `cell - (dims-1)/2`, which is only right for odd ones), so
##     a 2×2 building — which is every overlay host in the game — appeared to jump a cell
##     away from the cursor at the moment the order was given.
##   * An overlay build must be CENTRED on its host, not merely overlapping it
##     (Map.concentric_structure). A partly-overlapping aim used to be accepted and then
##     silently corrected onto the host when the builder arrived.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_OverlayPlacement.gd -gexit

const SAFEHOUSE_TOOL: String = "command_tool_an_infrastructure"
const EXTRACTOR_TOOL: String = "command_tool_nt_extractor"
const BUILDING_SCENE: String = "res://scenes/entities/structures/nt/nt_building_square.tscn"
const EXTRACTION_SITE_SCENE: String = "res://scenes/entities/structures/nt/nt_extractionSite.tscn"

## Every piece in play here is 2×2 — the even footprint, which centres on a grid CORNER.
const DIMS: Vector2i = Vector2i(2, 2)
const CELLS: int = 16


## A real Map with its terrain/navmesh boot skipped (that needs a scene and the navigation
## server); all the footprint math under test is Map's own.
class TestMap extends Map:
	func _ready() -> void:
		pass


var _world: Node3D
var _map: TestMap
var _commander: Commander
var _neutral: Commander
var _controller: RTSController = null


func before_each() -> void:
	_controller = null
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
	_commander.map = _map
	_commander.add_energy(10000)
	# These tests never tick production; the commander's own physics pass wants a
	# scenario rig (fog, blackboard) that none of this stands up.
	_commander.set_physics_process(false)
	_neutral.set_physics_process(false)


## Map resolves its terrain collider through @onready node paths on tree entry, and
## footprint_origin reads the heightmap's extent, so both are provided.
func _make_map() -> TestMap:
	var map: TestMap = TestMap.new()
	var region: NavigationRegion3D = NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	map.add_child(region)
	var heights: HeightMapShape3D = HeightMapShape3D.new()
	heights.map_width = CELLS + 1
	heights.map_depth = CELLS + 1
	heights.map_data = PackedFloat32Array()
	heights.map_data.resize((CELLS + 1) * (CELLS + 1))
	map.height_map = heights
	map.cell_grid = []
	for x in range(CELLS):
		var col: Array = []
		for y in range(CELLS):
			col.append(null)
		map.cell_grid.append(col)
	return map


## Register `structure` on the DIMS footprint at `origin` exactly as Map.add_structure
## would (cells, registry and position), and return its world-space centre.
func _register(a_structure: Entity, a_origin: Vector2i) -> Vector2:
	var cells: Array[Vector2i] = []
	for w in range(DIMS.x):
		for l in range(DIMS.y):
			var cell: Vector2i = a_origin + Vector2i(w, l)
			cells.append(cell)
			_map.cell_grid[cell.x][cell.y] = a_structure
	_map.structure_cell_map[a_structure] = cells
	var centre: Vector3 = _map.footprint_centroid(a_origin, DIMS)
	a_structure.global_position = centre
	return VU.inXZ(centre)


func _order(a_tool_name: String, a_at: Vector2) -> CommandMessage:
	return CommandMessage.new(_map, null, Tool.for_name(a_tool_name), Vector3(a_at.x, 0.0, a_at.y))


## Several of the scenes instanced here (the neutral building, the extractor) still ship without
## flavor text, and Commandable reports that with a push_error the moment one is built —
## which GUT counts as an unexpected error and fails the test on. That is a content gap in
## those pieces' scenes, tracked by the spec-doc description tests, and nothing to do with
## placement, so it is dismissed HERE and only by message: any other error still fails.
func _dismiss_missing_flavor_text() -> void:
	for tracked in get_errors():
		if tracked.contains_text("was given an empty description") \
			or tracked.contains_text("was given an empty verbose description"):
			tracked.handled = true


## A real entity of `scene`, owned by `owner_commander` and registered on the DIMS
## footprint at `origin` exactly as Map.add_structure would. Returns its world-space centre.
func _place_scene(a_scene: String, a_owner_commander: Commander, a_origin: Vector2i) -> Vector2:
	var entity: Entity = load(a_scene).instantiate() as Entity
	a_owner_commander.add_child(entity)
	entity.initialize(_map, a_owner_commander)
	_dismiss_missing_flavor_text()
	return _register(entity, a_origin)


## The ghost's world position for `tool` aimed at `at`. Reaches into the controller's own
## resolver deliberately: the bug this guards against was that function disagreeing with
## Map's, so asserting against a re-implementation here would prove nothing. The controller
## is never added to the tree — its @onready members would want a whole scenario — and
## _footprint_centroid needs only `map`.
func _ghost_position(a_tool_name: String, a_at: Vector2) -> Variant:
	if _controller == null:
		_controller = autofree(RTSController.new()) as RTSController
		# selection_box's default value builds a ColorRect that only the player scene ever
		# adopts, so on a bare instance it would outlive the test as an orphan.
		autofree(_controller.selection_box)
		_controller.map = _map
	return _controller._footprint_centroid(_commander, Tool.for_name(a_tool_name), a_at)


#region One placement resolution
## The reported symptom: the blueprint jumping away from the cursor on confirmation. The
## ghost and the blueprint must land on the same point for EVERY aim within a cell, not
## just the ones where the two derivations happened to agree.
func test_ghost_and_blueprint_agree_across_a_whole_cell() -> void:
	for dx: float in [-0.45, -0.2, 0.0, 0.2, 0.45]:
		for dz: float in [-0.45, -0.2, 0.0, 0.2, 0.45]:
			var aim: Vector2 = Vector2(3.0 + dx, 2.0 + dz)
			var message: CommandMessage = _order(SAFEHOUSE_TOOL, aim)
			var blueprint: Commandable = Build.plan_structure(_commander, message)
			assert_not_null(blueprint, "a blueprint went up for aim %s" % aim)
			var ghost: Variant = _ghost_position(SAFEHOUSE_TOOL, aim)
			assert_not_null(ghost, "the ghost resolved for aim %s" % aim)
			assert_almost_eq(VU.inXZ(blueprint.global_position), VU.inXZ(ghost as Vector3),
				Vector2(0.001, 0.001),
				"ghost and blueprint stand in the same place for aim %s" % aim)


## The other half of the same contract: what the builder finally registers is the footprint
## the ghost was drawn on, so nothing moves when construction starts either.
func test_placement_footprint_matches_the_ghost() -> void:
	var aim: Vector2 = Vector2(3.4, 2.4)
	var ghost: Variant = _ghost_position(SAFEHOUSE_TOOL, aim)
	var cells: Array[Vector2i] = _map.footprint_cells(aim, DIMS)
	var centre: Vector3 = _map.footprint_centroid(_map.footprint_origin(aim, DIMS), DIMS)
	assert_eq(cells.size(), 4, "a 2×2 build claims four cells")
	assert_almost_eq(VU.inXZ(ghost as Vector3), VU.inXZ(centre), Vector2(0.001, 0.001),
		"the ghost stands on the centre of the cells the build will register")
#endregion


#region Extractor on ExtractionSite
func test_extractor_blueprint_stands_on_its_site() -> void:
	var centre: Vector2 = _place_scene(EXTRACTION_SITE_SCENE, _neutral, Vector2i(4, 4))
	var site: Entity = _map.cell_grid[4][4] as Entity

	var message: CommandMessage = _order(EXTRACTOR_TOOL, centre)
	assert_true(EnergyExtractor.valid_placement(message, DIMS),
		"an extractor aimed at the extraction site's centre is a valid placement")
	var blueprint: Commandable = Build.plan_structure(_commander, message)
	_dismiss_missing_flavor_text()
	assert_not_null(blueprint, "the extractor order raised a blueprint")
	assert_almost_eq(VU.inXZ(blueprint.global_position), VU.inXZ(site.global_position),
		Vector2(0.001, 0.001),
		"the extractor's blueprint stands exactly on the extraction site it will be built on")


## Aimed one cell over, the extractor's footprint still covers half the site — and is refused,
## rather than being accepted and then snapped onto the extraction site at placement.
func test_extractor_refuses_a_partly_overlapping_aim() -> void:
	var centre: Vector2 = _place_scene(EXTRACTION_SITE_SCENE, _neutral, Vector2i(4, 4))
	assert_false(EnergyExtractor.valid_placement(_order(EXTRACTOR_TOOL, centre + Vector2(1, 0)), DIMS),
		"an extractor that only half-covers the extraction site is refused")
#endregion


#region Safehouse on Building
func test_safehouse_aimed_at_a_building_converts_it() -> void:
	var centre: Vector2 = _place_scene(BUILDING_SCENE, _neutral, Vector2i(6, 6))
	assert_false(Build.places_new_structure(_commander, _order(SAFEHOUSE_TOOL, centre)),
		"a safehouse squarely on a neutral building converts it instead of placing one")


## Off-centre it is no longer a conversion, so it falls through to an ordinary placement —
## which the building's own cells refuse. Either way the player cannot end up with a
## safehouse sitting half on top of a building.
func test_safehouse_off_centre_is_not_a_conversion_and_cannot_be_placed() -> void:
	var centre: Vector2 = _place_scene(BUILDING_SCENE, _neutral, Vector2i(6, 6))
	var message: CommandMessage = _order(SAFEHOUSE_TOOL, centre + Vector2(1, 0))
	assert_true(Build.places_new_structure(_commander, message),
		"an off-centre safehouse is not treated as a conversion")
	assert_false(Structure.valid_placement(message, DIMS),
		"and it cannot be placed either, since the building holds those cells")
#endregion
