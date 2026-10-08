extends GutTest

## CO-BUILDING — several builders in one multi-select Build order working ONE structure.
##
## Only the first builder to arrive lays the foundation; every later arrival finds the
## structure already on its target footprint and joins ASSEMBLING it instead of placing
## a duplicate (which TerrainGrid.place_building would assert on). This test pins that
## contract end to end, through the real command-dispatch path rather than by calling
## Build.fulfill_action directly — the co-build guard is only worth anything if the
## receiver actually installs the Assemble it hands back.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CoBuild.gd -gexit
##
## NOT COVERED HERE: the Extractor-on-site OVERLAY case — its host resolution, its approach
## cell and its co-build handover all live in tests/test_BuildApproach.gd, which stubs a map
## with a real TerrainGrid so passability answers.
##
## SCOPE: every builder here starts IN RANGE (can_act true on the first tick), because
## the stub map has no navmesh and units cannot actually move in it. The case these tests
## therefore do NOT cover is the one that matters in play: a builder that has to APPROACH
## the site. See CommandReceiver._process_commands' navigation-arrival branch, which nulls
## the active command on arrival regardless of whether can_act has become true.

const BUILD_TYPE: StringName = &"fake_building"
const BUILDER_SCENE: Dictionary = {"speed": 2.0, "vision": 8.0, "builds": [&"fake_building"]}


class StubMap:
	extends Map
	var placed: Array = []

	func _ready() -> void:
		cell_grid = []
		for x: int in 17:
			var col: Array = []
			for y: int in 17:
				col.append(null)
			cell_grid.append(col)

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return a_coords.x >= 0 and a_coords.x < 17 and a_coords.y >= 0 and a_coords.y < 17

	func add_structure(
		a_structure: Entity, a_world_center: Vector2, _a_rotation: int = 0, _a_rebake: bool = true
	) -> void:
		placed.append({"structure": a_structure, "center": a_world_center})
		var cell: Vector2i = world_to_grid(a_world_center)
		structure_cell_map[a_structure] = [cell]
		cell_grid[cell.x][cell.y] = a_structure
		a_structure.map = self
		a_structure.refresh_movement_collision()

	func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
		structure_cell_map.erase(a_structure)


var _world: Node3D
var _map: StubMap
var _commander: Commander
var _tool: Tool


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
	# The tech prerequisite for BUILD_TOOL, satisfied so these tests are about co-building
	# and nothing else. Build now waits at the site until its prerequisites are actually
	# standing (that is what lets requisition mode order a downstream structure while its
	# dependency is still going up), so without this every placement here would stall.
	_commander.technology_mapping = {BUILD_TYPE: FakePieces.tech()}
	_tool = FakePieces.register_tool(
		FakePieces.tool(BUILD_TYPE, {"structure": true, "dimensions": Vector2i(3, 3)})
	)
	_commander.set_physics_process(false)


func after_each() -> void:
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
	heights.map_width = 17
	heights.map_depth = 17
	stub.height_map = heights
	return stub


## A real builder unit, instanced from its scene rather than built from a bare
## Actor: the tick path resolves several required children with `$` (HPBar,
## Veterancy, AvoidanceObstacle), so a hand-assembled stand-in errors its way through
## every frame. `buildable_types` is widened to the structure under test.
func _make_builder(a_at: Vector2) -> Actor:
	var builder: Actor = FakePieces.make(BUILDER_SCENE) as Actor
	_world.add_child(builder)
	var builds := builder.get_node("Builds") as Builds
	builds.buildable_types = [BUILD_TYPE]
	builder.ownership.commander = _commander
	builder.map = _map
	builder.global_position = Vector3(a_at.x, 0.0, a_at.y)
	return builder


func _order(a_at: Vector2) -> CommandMessage:
	var message := CommandMessage.new(_map, null, _tool, Vector3(a_at.x, 0.0, a_at.y))
	Build.submit_purchase(_commander, message)
	Build.plan_structure(_commander, message)
	return message


func test_second_builder_joins_instead_of_placing_a_duplicate() -> void:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	var a := _make_builder(site)
	var b := _make_builder(site + Vector2(1.0, 0.0))

	a.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	b.update_commands(Build.new(CommandMessage.deep_copy(message)), false)

	a._process_commands()
	b._process_commands()

	assert_eq(_map.placed.size(), 1, "exactly one structure is laid down")
	assert_true(a.current_command() is Assemble, "the placing builder switches to building it")
	assert_true(b.current_command() is Assemble, "the second builder joins rather than re-placing")


func test_every_builder_registers_but_the_second_buys_no_tempo() -> void:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	var a := _make_builder(site)
	var b := _make_builder(site + Vector2(1.0, 0.0))
	a.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	b.update_commands(Build.new(CommandMessage.deep_copy(message)), false)

	# Tick once to place and swap both builders onto Assemble, then again so both
	# register — Assemble registers its actor on its first fulfil, not on assignment.
	for i: int in 2:
		a._process_commands()
		b._process_commands()

	var structure: Actor = _map.placed[0]["structure"]
	assert_eq(structure._active_builders.size(), 2, "both builders are registered on the structure")

	# Both contribute, but the SECOND one buys no tempo: MARGINAL_BUILDER_EFFICIENCY is 0,
	# so the site advances at 1/T per tick however many builders are on it (see
	# Actor.effective_build_increment).
	var before: float = structure.build_progress
	a._process_commands()
	b._process_commands()
	var two_builder_step: float = structure.build_progress - before
	var solo_step: float = 1.0 / float(_commander.technology_mapping[structure.id].creation_time)
	assert_almost_eq(two_builder_step, solo_step, 1e-6, "two builders build at one builder's rate")


## The post-placement fixup runs deferred, so it lands a frame AFTER the structure goes
## down and can displace units standing on the new footprint — including the co-builders,
## who all converge on the same cell (Build is excluded from the destination spread).
## Co-building has to survive that.
func test_co_building_survives_the_post_placement_displacement() -> void:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	var a := _make_builder(site)
	var b := _make_builder(site + Vector2(1.0, 0.0))
	a.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	b.update_commands(Build.new(CommandMessage.deep_copy(message)), false)

	a._process_commands()
	b._process_commands()
	# Let _after_placement's call_deferred actually fire.
	await get_tree().process_frame
	await get_tree().process_frame

	var structure: Actor = _map.placed[0]["structure"]
	var before: float = structure.build_progress
	for i: int in 3:
		a._process_commands()
		b._process_commands()

	assert_eq(structure._active_builders.size(), 2, "both builders still on the job")
	assert_gt(structure.build_progress, before, "and still making progress")


## A Movement that always claims it has arrived. Stands in for the real agent reporting a
## finished path — which happens the moment the destination stops being reachable, e.g.
## when a co-builder places the structure the approaching builder was walking toward.
class ArrivedMovement:
	extends Movement

	func is_navigation_finished() -> bool:
		return true


## Replace `unit`'s Movement with the always-arrived double, keeping the node name so the
## @onready lookups and `movement` field still resolve.
func _force_arrived(a_unit: Actor) -> void:
	var old: Movement = a_unit.movement
	var stub := ArrivedMovement.new()
	stub.name = "MovementStub"
	a_unit.add_child(stub)
	a_unit.movement = stub
	old.queue_free()


## THE APPROACH CASE — the one the in-range tests above cannot reach.
##
## A builder that had to walk to its site used to lose its Build outright the instant the
## navigation agent reported arrival, whether or not it was yet in range to act. It then
## stood there with no command, which is exactly what a player sees when only one unit of
## a multi-select build order ends up working.
func test_a_build_survives_arriving_out_of_range() -> void:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	# Well outside can_act's L-inf <= 1 ring around the footprint.
	var b := _make_builder(site + Vector2(9.0, 9.0))
	_force_arrived(b)
	b.update_commands(Build.new(CommandMessage.deep_copy(message)), false)

	assert_false(b.current_command().can_act(b), "precondition: it is not in range yet")
	b._process_commands()

	assert_true(b.has_command(), "the build order survives arriving short of the site")
	assert_true(b.current_command() is Build, "and it is still the Build, not something else")


## The counterpart: a plain move IS finished by arriving, and must still end there —
## otherwise every unit that ever walks anywhere keeps a command forever.
func test_a_plain_move_still_ends_on_arrival() -> void:
	var b := _make_builder(Vector2(4.0, 4.0))
	_force_arrived(b)
	b.update_commands(
		MoveCommand.new(CommandMessage.new(_map, null, null, Vector3(9.0, 0.0, 9.0))), false
	)

	b._process_commands()

	assert_false(b.has_command(), "a plain move ends when the unit gets there")


## THE DEADLOCK — an out-of-range builder must convert to Assemble without first getting
## in range.
##
## A Build navigates toward the site CENTRE, which is exactly where the structure a
## co-builder just placed now stands: impassable, with collision. The approaching builder
## is stopped short, so can_act never becomes true, so the handover in fulfill_action
## never runs, so it never gets the Assemble whose approach WOULD be reachable. It idles a
## couple of cells out forever. The conversion therefore has to happen off get_updated_state
## (every tick, range-independent), not off fulfill_action.
func test_an_out_of_range_builder_converts_to_assemble() -> void:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	var placer := _make_builder(site)
	var walker := _make_builder(site + Vector2(9.0, 9.0))
	placer.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	walker.update_commands(Build.new(CommandMessage.deep_copy(message)), false)

	# The in-range builder lays it down; the far one is nowhere near being able to act.
	placer._process_commands()
	assert_eq(_map.placed.size(), 1, "precondition: the structure is down")
	assert_false(
		walker.current_command().can_act(walker), "precondition: the walker is out of range"
	)

	walker._process_commands()

	assert_true(
		walker.current_command() is Assemble,
		(
			"the walker converts to Assemble while still out of range, so it can "
			+ "approach a cell it can actually reach"
		)
	)


# --- The build RATE: extra builders are redundancy, not tempo ------------------------


## A structure on the map, with the tech entry `effective_build_increment` prices it from.
func _placed_site() -> Actor:
	var site := Vector2(4.0, 4.0)
	var message := _order(site)
	var builder := _make_builder(site)
	builder.update_commands(Build.new(CommandMessage.deep_copy(message)), false)
	builder._process_commands()
	return _map.placed[0]["structure"]


## Register `a_crew` stand-in builders on `a_site` and return the site's total progress for
## one tick in which `a_acting` of them work. Bare Commandables: the rate only counts them.
func _rate_with_crew(a_site: Actor, a_crew: int, a_acting: int) -> float:
	a_site._active_builders.clear()
	for _i: int in a_crew:
		var stand_in := Actor.new()
		autofree(stand_in)
		a_site._active_builders.append(stand_in)
	return float(a_acting) * a_site.effective_build_increment()


func test_a_full_crew_builds_at_one_builders_rate_however_big_it_is() -> void:
	var site: Actor = _placed_site()
	var expected: float = 1.0 / float(_commander.technology_mapping[site.id].creation_time)
	for crew: int in [1, 2, 3, 5, 8]:
		assert_almost_eq(
			_rate_with_crew(site, crew, crew),
			expected,
			1e-6,
			"a crew of %d builds no faster than one" % crew
		)


func test_a_staggered_builder_does_not_stop_the_others() -> void:
	# The reason multi-builder support is kept at all: lose one to a stagger (or to death)
	# and the site keeps going up, at the share the survivors carry.
	var site: Actor = _placed_site()
	assert_gt(_rate_with_crew(site, 3, 2), 0.0, "two of three still make progress")


func test_the_marginal_factor_is_what_makes_the_curve_flat() -> void:
	# MARGINAL_BUILDER_EFFICIENCY is the single revert point: at 1.0 the rate would be the
	# plain AOE2 curve, (n+2)/(3T), which for n=2 is 4/3 of a lone builder's.
	var site: Actor = _placed_site()
	var solo: float = 1.0 / float(_commander.technology_mapping[site.id].creation_time)
	assert_eq(Actor.MARGINAL_BUILDER_EFFICIENCY, 0.0, "extra builders buy no tempo")
	assert_almost_eq(_rate_with_crew(site, 2, 2), solo, 1e-6, "so two builders match one")
