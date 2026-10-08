extends GutTest

## WHERE A BUILDER WALKS TO. A build aimed on top of an OBSTRUCTION — the Anarchical
## safehouse (an_infrastructure) converting a neutral building — names the host's approach
## cell, because the site centre is inside the host and nobody can stand there. Every other
## build walks at the site centre: open ground, and an extractor on its extraction site,
## which is walkable. See Build.movement_destination.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BuildApproach.gd -gexit

## Fake pieces. The safehouse tool keeps the ONE id the conversion rule is keyed on in code, and the
## neutral building the id the registry lists as a neutral building (Build._conversion_target).
const EXTRACTOR: Dictionary = {"structure": true, "extractor": true, "dimensions": Vector2i(2, 2)}
const ORDINARY: Dictionary = {"structure": true, "dimensions": Vector2i(3, 3)}
const SAFEHOUSE: Dictionary = {"structure": true, "dimensions": Vector2i(2, 2)}
var EXTRACTOR_TOOL: Tool
var ORDINARY_TOOL: Tool
var SAFEHOUSE_TOOL: Tool
var BUILDING_SCENE: Dictionary:
	get:
		return {
			"structure": true,
			"dimensions": Vector2i(2, 2),
			"id": PieceFamilies.members(PieceFamilies.NEUTRAL_BUILDING)[0]
		}
const BUILDER_SCENE: Dictionary = FakePieces.BUILDER
const SITE_SCENE: Dictionary = {
	"feature": true, "extraction_site": true, "obstruction": false, "dimensions": Vector2i(2, 2)
}
## Height-map corner count; the cell grid is one smaller in each axis.
const MAP_CORNERS: int = 17
const GRID_CELLS: int = MAP_CORNERS - 1


## A Map with a real TerrainGrid (so passability answers) and a hand-managed cell grid, but
## none of the navmesh/terrain loading. grid_to_world / world_to_grid / footprint_* are the
## REAL ones — the point of the test is which cell a destination lands in, so the two
## directions have to be genuine inverses.
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


func after_each() -> void:
	FakePieces.restore_tools()


func before_each() -> void:
	EXTRACTOR_TOOL = FakePieces.register_tool(FakePieces.tool(&"fake_extractor", EXTRACTOR))
	ORDINARY_TOOL = FakePieces.register_tool(FakePieces.tool(&"fake_ordinary", ORDINARY))
	SAFEHOUSE_TOOL = FakePieces.register_tool(
		FakePieces.tool(EntityIds.AN_INFRASTRUCTURE, SAFEHOUSE)
	)
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


## Register an ExtractionSite occupying `a_dims` cells from `a_origin`, exactly as
## Map.add_structure would — the real host an Extractor overlays.
func _occupy(a_origin: Vector2i, a_dims: Vector2i) -> Entity:
	var host: Entity = FakePieces.make(SITE_SCENE) as Entity
	_world.add_child(host)
	var cells: Array[Vector2i] = []
	for dx: int in a_dims.x:
		for dz: int in a_dims.y:
			var cell := a_origin + Vector2i(dx, dz)
			cells.append(cell)
			_map.cell_grid[cell.x][cell.y] = host
	_map.structure_cell_map[host] = cells
	host.map = _map
	host.global_position = _map.footprint_centroid(a_origin, a_dims)
	return host


func _make_builder(a_at: Vector3) -> Actor:
	var builder: Actor = FakePieces.make(BUILDER_SCENE) as Actor
	_world.add_child(builder)
	builder.ownership.commander = _commander
	builder.map = _map
	builder.global_position = a_at
	return builder


func _build(a_tool: Tool, a_at: Vector3) -> Build:
	return Build.new(CommandMessage.new(_map, null, a_tool, a_at))


## The footprint size the extractor tool places, so the host it overlays is the same shape
## — concentric_structure only reports a host whose footprint is centred on the same point.
func _extractor_dimensions() -> Vector2i:
	var preview: Node = _commander.get_build_preview_instance(EXTRACTOR_TOOL)
	return (preview.get_node("Fixture") as Fixture).dimensions


## A neutral nt_building registered through Map.add_structure on `a_origin`, so it is a real
## obstruction on the terrain grid — the host a safehouse conversion aims at.
func _neutral_building(a_origin: Vector2i) -> Entity:
	var neutral := Commander.new()
	neutral.id = 0
	_world.add_child(neutral)
	neutral.map = _map
	neutral.set_physics_process(false)
	var building: Entity = FakePieces.make(BUILDING_SCENE) as Entity
	neutral.add_child(building)
	building.initialize(_map, neutral)
	for tracked in get_errors():
		if tracked.contains_text("entered the tree with no"):
			tracked.handled = true
	var dims: Vector2i = (building.get_node("Fixture") as Fixture).dimensions
	_map.add_structure(building, VU.in_xz(_map.footprint_centroid(a_origin, dims)))
	return building


func test_a_build_over_an_obstruction_walks_to_a_cell_beside_it() -> void:
	var host: Entity = _neutral_building(Vector2i(8, 8))
	var site: Vector3 = host.global_position
	var builder := _make_builder(site - Vector3(5.0, 0.0, 0.0))
	var command := _build(SAFEHOUSE_TOOL, site)

	var destination: Variant = command.movement_destination(builder)

	assert_true(destination is Vector3, "a build over an obstruction names its own destination")
	var cell: Vector2i = _map.world_to_grid(VU.in_xz(destination))
	var footprint: Array = _map.structure_cell_map[host]
	assert_false(cell in footprint, "and it is not a cell the host blocks")
	assert_true(
		footprint.any(func(c: Vector2i) -> bool: return SU.linf_distance(cell, c) <= 1.0),
		"but it is adjacent to the host"
	)


## The destination and the reach test have to agree: standing on the named cell must be
## close enough to act, or the builder arrives and stalls.
func test_arriving_beside_the_obstruction_is_close_enough_to_build() -> void:
	var host: Entity = _neutral_building(Vector2i(8, 8))
	var site: Vector3 = host.global_position
	var builder := _make_builder(site - Vector3(5.0, 0.0, 0.0))
	var command := _build(SAFEHOUSE_TOOL, site)
	assert_false(command.can_act(builder), "precondition: it cannot act from where it starts")

	builder.global_position = command.movement_destination(builder)

	assert_true(command.can_act(builder), "having walked to the named cell, it can build")


## An extraction site is walkable, so an extractor aimed at one walks at the site centre
## like any build on open ground.
func test_an_extractor_on_a_site_names_no_destination_of_its_own() -> void:
	var dims: Vector2i = _extractor_dimensions()
	var origin := Vector2i(8, 8)
	_occupy(origin, dims)
	var site: Vector3 = _map.footprint_centroid(origin, dims)
	var builder := _make_builder(site - Vector3(5.0, 0.0, 0.0))

	assert_null(
		_build(EXTRACTOR_TOOL, site).movement_destination(builder),
		"the site does not block the builder"
	)


## An ORDINARY build names nothing and keeps the default resolution (the site centre).
## Its target cells are empty by the placement rule, so that centre is walkable.
func test_an_ordinary_build_names_no_destination_of_its_own() -> void:
	var site: Vector3 = _map.grid_to_world(Vector2i(8, 8))
	var builder := _make_builder(site - Vector3(5.0, 0.0, 0.0))

	assert_null(
		_build(ORDINARY_TOOL, site).movement_destination(builder),
		"a build on empty ground is left to walk at message.position"
	)


# --- The overlay CO-BUILD handover --------------------------------------------------


## A second builder ordered onto a site one of ours is already bound to JOINS it.
##
## This is the question an overlay build has to be asked differently: its target cells are
## legitimately occupied by the host, so the generic "is anything on these cells" scan
## reports the host itself as a conflict. Build._structure_on_target_footprint therefore
## asks "is one of OURS bound to that host" instead — and get_updated_state acts on the
## answer every tick, range-independently, so an approaching builder converts before it
## needs to be in range. See CLAUDE.md §Command system.
func test_a_second_builder_joins_the_extractor_already_on_the_site() -> void:
	var dims: Vector2i = _extractor_dimensions()
	var origin := Vector2i(8, 8)
	var host: Entity = _occupy(origin, dims)
	var site: Vector3 = _map.footprint_centroid(origin, dims)
	var tool: Tool = EXTRACTOR_TOOL

	var bound: Actor = tool.packed_scene.instantiate() as Actor
	bound.begin_construction()
	_world.add_child(bound)
	bound.ownership.commander = _commander
	bound.map = _map
	bound.global_position = site
	ExtractionSite.of(host).extractor = bound

	# Out of range: the handover is range-independent, so a builder converts while it walks.
	var builder := _make_builder(site - Vector3(6.0, 0.0, 0.0))
	var command := _build(EXTRACTOR_TOOL, site)
	assert_false(command.can_act(builder), "precondition: the builder is not in range")

	assert_true(
		command.get_updated_state(builder) is Assemble,
		"it converts to Assemble on the bound extractor rather than waiting to place a second"
	)
