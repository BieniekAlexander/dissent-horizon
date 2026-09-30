extends GutTest

## A STRUCTURE NEED NOT BE A COMMANDABLE, and `as Commandable` fails SILENTLY.
##
## `CommandReceiver._resolve_movement_target` decides where an ordered unit actually walks.
## For a structure target that must be a cell BESIDE the footprint, because the footprint
## itself is a hole in the navmesh — `TerrainGrid.is_passable` is false on every cell a
## building occupies, so an agent sent to the structure's own centre has no path to finish
## and the unit walks forever without ever reaching build range. That is what "builders
## indefinitely failing to start the process of building something" looked like.
##
## The predicate that chose that branch used to read `target is Commandable and
## target.is_in_group("structure")`. An ExtractionSite is a `structure` and is NOT a
## `Commandable` — it extends `Entity` directly — so the branch was skipped for it and the
## builder was handed `message.position`, a cell inside the site. Nothing errored: a failing
## `as`/`is` narrowing in GDScript is just `null`/`false`.
##
## `RTSController` line 434 is why the site is the target at all:
##   command_message.target = cursor_result if cursor_result is Entity else null
## — ANY Entity under the cursor becomes the target, Commandable or not.
##
## The fixed predicate tests `is Entity` and leans on the "fixture" GROUP for the rest — every
## piece with a footprint, features included (the "structure" group is only the commandable ones).
##
## PATHS, not preloads — a file-scope preload of an entity scene poisons the Tool registry
## for the whole run (CLAUDE.md §A file-scope `preload`…).

const SITE_SCENE: Dictionary = FakePieces.BUILDING
const BUILDER_SCENE: Dictionary = FakePieces.BUILDER
const BUILD_TOOL: String = "command_tool_an_barracks"

const GRID: int = 17
## Where the site is planted. Well inside the grid so it has neighbours on all sides.
const SITE_CELL: Vector2i = Vector2i(8, 8)


## The CoBuild stub, plus a REAL TerrainGrid: the whole point here is which cells are
## passable, and faking that would fake the thing under test. Map's own coordinate helpers
## are left ALONE — grid_to_world, world_to_grid and footprint_origin have to agree with each
## other or the footprint maths lands somewhere else entirely.
class StubMap extends Map:
	var placed: Array = []

	func _ready() -> void:
		cell_grid = []
		for x: int in GRID:
			var col: Array = []
			for y: int in GRID:
				col.append(null)
			cell_grid.append(col)

	func add_structure(a_structure: Entity, a_world_center: Vector2, _a_rotation: int = 0,
			_a_rebake: bool = true) -> void:
		placed.append(a_structure)
		var cell: Vector2i = world_to_grid(a_world_center)
		structure_cell_map[a_structure] = [cell]
		cell_grid[cell.x][cell.y] = a_structure
		# The cell a building stands on stops being navigable — that is what makes the
		# structure's own centre an unreachable destination.
		terrain_grid.place_building([cell], a_structure)
		a_structure.map = self
		a_structure.refresh_movement_collision()

	func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
		structure_cell_map.erase(a_structure)


var _world: Node3D
var _map: StubMap
var _commander: Commander
var _site: Entity


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
	_commander.technology_mapping[Tool.for_name(BUILD_TOOL).type].required_structures = []
	_commander.set_physics_process(false)
	_site = _make_site()


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
	heights.map_width = GRID + 1
	heights.map_depth = GRID + 1
	stub.height_map = heights
	var grid := TerrainGrid.new()
	grid.height_map = heights
	grid.terrain_body = body
	stub.terrain_grid = grid
	stub.add_child(grid)
	return stub


## A NEUTRAL ExtractionSite on the grid — the fixture the whole file is about.
func _make_site() -> Entity:
	var site: Entity = FakePieces.make(SITE_SCENE) as Entity
	_world.add_child(site)
	site.global_position = _map.grid_to_world(SITE_CELL)
	_map.add_structure(site, VU.inXZ(site.global_position))
	return site


func _make_builder(a_cell: Vector2i) -> Commandable:
	var builder: Commandable = FakePieces.make(BUILDER_SCENE) as Commandable
	_world.add_child(builder)
	var builds := builder.get_node("Builds") as Builds
	builds.buildable_types = [Tool.for_name(BUILD_TOOL).type]
	builder.ownership.commander = _commander
	builder.map = _map
	builder.global_position = _map.grid_to_world(a_cell)
	return builder


## An order issued with the cursor over the site: target is the site, position is the site.
func _order_targeting_the_site() -> CommandMessage:
	return CommandMessage.new(_map, _site, Tool.for_name(BUILD_TOOL),
		_map.grid_to_world(SITE_CELL))


## The predicate exactly as it read BEFORE the fix, so the regression is demonstrated
## rather than described.
func _pre_fix_branch_taken(a_target: Variant) -> bool:
	return a_target != null and is_instance_valid(a_target) \
		and a_target is Commandable and (a_target as Node).is_in_group("structure")


## And as it reads now.
func _fixed_branch_taken(a_target: Variant) -> bool:
	return a_target != null and is_instance_valid(a_target) \
		and a_target is Entity and (a_target as Node).is_in_group("fixture")


#region The fixture fact
func test_an_extraction_site_is_a_structure_that_is_not_a_commandable() -> void:
	assert_true(_site is Entity, "it is an Entity")
	assert_false(_site is Commandable, "but NOT a Commandable — it extends Entity directly")
	assert_true(_site.is_in_group("fixture"), "and it is in the fixture group")
	assert_false(_site.is_in_group("structure"), "but not a structure: it takes no orders")
	assert_true(_site.has_node("Structure"), "carrying a real Structure component")


func test_a_failing_narrowing_cast_is_silent() -> void:
	# The trapdoor itself, in one line: no error, no warning, just null.
	var narrowed: Commandable = _site as Commandable
	assert_null(narrowed, "`as Commandable` on a non-Commandable structure yields null quietly")
#endregion


#region The predicate
func test_the_pre_fix_predicate_skipped_an_extraction_site() -> void:
	assert_false(_pre_fix_branch_taken(_site),
		"pre-fix: the footprint-adjacency branch was not taken for a site")
	assert_true(_fixed_branch_taken(_site),
		"fixed: it is taken, because the FIXTURE GROUP decides, not the class")


func test_the_predicate_still_ignores_a_non_structure() -> void:
	# Widening the cast must not turn every entity target into a structure approach.
	var unit: Commandable = _make_builder(Vector2i(2, 2))
	assert_false(_fixed_branch_taken(unit), "a unit target is still a plain point")
	assert_false(_fixed_branch_taken(null), "and so is a ground click")
#endregion


#region Where the builder is actually sent
func test_a_builder_targeting_an_extraction_site_is_sent_to_a_cell_it_can_stand_on() -> void:
	# THE REGRESSION. The destination has to be somewhere the navmesh exists; the site's own
	# cell is a hole in it, so a builder aimed there never finishes its path and never starts.
	var builder: Commandable = _make_builder(Vector2i(2, 2))
	var command := Build.new(_order_targeting_the_site())
	var destination: Vector3 = builder.command_receiver._resolve_movement_target(command)
	var cell: Vector2i = _map.world_to_grid(VU.inXZ(destination))

	assert_false(_map.terrain_grid.is_passable(SITE_CELL),
		"the site's own cell is not navigable — a building occupies it")
	assert_true(_map.terrain_grid.is_passable(cell),
		"so the destination must be a cell the builder can actually reach")
	assert_eq(SU.linf_distance(cell, SITE_CELL), 1,
		"and it is immediately beside the site's footprint")


func test_the_pre_fix_destination_was_a_cell_no_unit_could_reach() -> void:
	# What the old code returned: the fallback, message.position — inside the site.
	var builder: Commandable = _make_builder(Vector2i(2, 2))
	var command := Build.new(_order_targeting_the_site())
	var pre_fix: Vector3 = command.message.position  # the branch was skipped, so: the fallback
	assert_false(_map.terrain_grid.is_passable(_map.world_to_grid(VU.inXZ(pre_fix))),
		"pre-fix the builder was aimed at an impassable cell — it could never arrive")
	assert_ne(builder.command_receiver._resolve_movement_target(command), pre_fix,
		"fixed: it is no longer sent there")


func test_the_destination_is_per_actor_not_one_shared_spot() -> void:
	# Each builder gets ITS OWN nearest approach, which is the other half of why the branch
	# exists — otherwise a whole selection converges on one cell.
	var near_west := _make_builder(Vector2i(2, 8))
	var near_east := _make_builder(Vector2i(14, 8))
	var command := Build.new(_order_targeting_the_site())
	assert_ne(
		near_west.command_receiver._resolve_movement_target(command),
		near_east.command_receiver._resolve_movement_target(command),
		"two builders on opposite sides approach from opposite sides")
#endregion


#region End to end
func test_a_builder_ordered_beside_an_extraction_site_actually_starts_building() -> void:
	# The whole path, through real dispatch: a build ordered on free ground NEXT TO the site
	# places a structure and moves the builder onto Assemble. The site's own cells are
	# occupied and impassable, so this is the case that has to keep working while the
	# approach branch above has been widened to take non-Commandable structures.
	#
	# It is NOT the discriminating regression — it passed before the fix too. The
	# discriminating one is the destination, above: an order whose TARGET is the site.
	var free_cell := Vector2i(SITE_CELL.x + 3, SITE_CELL.y)
	var message := CommandMessage.new(_map, null, Tool.for_name(BUILD_TOOL),
		_map.grid_to_world(free_cell))
	Build.submit_purchase(_commander, message)
	Build.plan_structure(_commander, message)

	var builder: Commandable = _make_builder(free_cell)
	builder.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	builder._process_commands()

	assert_eq(_map.placed.size(), 2, "the site, plus the structure the builder just laid down")
	assert_true(builder.current_command() is Assemble,
		"and the builder is now building it rather than still trying to get there")


func test_a_build_aimed_AT_the_site_is_refused_rather_than_stalling() -> void:
	# The other half of what the widened cast exposes. CommandMessage.position resolves to the
	# TARGET's position when there is one, so "build with the cursor over the site" aims the
	# footprint at the site's own cells. Those are occupied, by something that is not one of
	# our half-built structures, so Build aborts. Ending the order is the right answer —
	# what it must never do is keep the builder walking at a cell it cannot reach.
	var message := _order_targeting_the_site()
	Build.submit_purchase(_commander, message)
	Build.plan_structure(_commander, message)

	var builder: Commandable = _make_builder(Vector2i(SITE_CELL.x + 1, SITE_CELL.y))
	builder.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	builder._process_commands()

	assert_eq(_map.placed.size(), 1, "nothing was built on top of the site")
	assert_null(builder.current_command(), "and the order ended instead of hanging")
#endregion
