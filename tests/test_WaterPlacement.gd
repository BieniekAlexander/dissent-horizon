extends GutTest

## Tests for the two rules water adds to the rest of the game: where a structure may stand in
## it (Fixture.allow_submerged / EnergyExtractor.valid_placement), and what a lithium pond
## pays out as it drains (WaterBody.extract).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_WaterPlacement.gd \
##     -gdir=res://tests/none -gexit
##
## The map is a real Map over a terrain this file sculpts — a shallow pan with a deep well cut
## into the middle of it — rather than a stub, because the rules under test ARE coordinate
## math: which cells a footprint covers, and how deep the water is over each.

const _PLAY: Vector2i = Vector2i(10, 10)
const _GROUND: float = 4.0
const _DIMS: Vector2i = Vector2i(2, 2)

## Shallow pan: cells (6..15) x (6..15) sunk half a wade depth. Deep well: cells (12..14) x
## (12..14) sunk well past it. The two are contiguous, so one body holds both.
const _PAN_ORIGIN: Vector2i = Vector2i(6, 6)
const _PAN_SIZE: Vector2i = Vector2i(10, 10)
const _WELL_ORIGIN: Vector2i = Vector2i(12, 12)
const _WELL_SIZE: Vector2i = Vector2i(3, 3)

## A 2x2 footprint entirely in the shallow pan, one entirely in the deep well, and one on the
## dry ground outside.
const _SHALLOW_ORIGIN: Vector2i = Vector2i(8, 8)
const _DEEP_ORIGIN: Vector2i = Vector2i(12, 12)
const _DRY_ORIGIN: Vector2i = Vector2i(2, 2)


## A real Map with only its terrain/navmesh boot skipped — the same fixture shape
## test_Extractor uses, and for the same reason: Map._ready would drag the navigation server
## into a unit test, while everything that decides where a structure lands is the real thing.
## The TerrainGrid is built by hand here because the placement rule reads is_flat off it.
class TestMap:
	extends Map

	func _ready() -> void:
		pass


## Enough of a Bot for BotEconomy's pond search: a map, a base, and a unit list.
class StubBot:
	extends Bot
	var units: Array = []
	var base: Vector3 = Vector3.ZERO

	func get_units() -> Array:
		return units

	func base_centroid() -> Vector3:
		return base

	func buildable_income_structure_types() -> Array:
		return [&"test_extractor"]

	## Which world positions the bot has explored; everything, unless a test narrows it.
	var explored_filter: Callable = func(_a_pos: Vector3) -> bool: return true

	func has_explored(a_world_pos: Vector3) -> bool:
		return explored_filter.call(a_world_pos)

	## Nothing is in vision now, so every claim the bot knows of is its own or remembered.
	func has_vision_at(_a_world_pos: Vector3) -> bool:
		return false


func _terrain() -> TerrainData:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(_GROUND)
	td.heights = heights
	_sink(td, _PAN_ORIGIN, _PAN_SIZE, _GROUND - WaterBasin.WADE_DEPTH * 0.5)
	_sink(td, _WELL_ORIGIN, _WELL_SIZE, _GROUND - WaterBasin.WADE_DEPTH * 3.0)
	return td


## Sink the corners bounding the block of CELLS spanning [origin, origin + size), so every
## cell strictly inside the block is flat at that height.
func _sink(a_td: TerrainData, a_origin: Vector2i, a_size: Vector2i, a_height: float) -> void:
	var heights: PackedFloat32Array = a_td.heights
	var w: int = a_td.map_width()
	for z: int in range(a_origin.y, a_origin.y + a_size.y + 1):
		for x: int in range(a_origin.x, a_origin.x + a_size.x + 1):
			heights[z * w + x] = a_height
	a_td.heights = heights


## A Map over that terrain, with one WaterBody filled to _GROUND — so the pan is shallow
## water, the well is deep water, and everything outside is dry.
func _make_map() -> Map:
	var td: TerrainData = _terrain()
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
		for _z: int in map.terrain_grid.grid_depth():
			column.append(null)
		map.cell_grid.append(column)
	return map


func _add_water(a_map: Map, a_energy: int = 0) -> WaterBody:
	var water := WaterBody.new()
	water.seed_cell = _SHALLOW_ORIGIN
	water.level = _GROUND
	water.energy = a_energy
	a_map.add_child(water)
	water.initialize(a_map)
	return water


## The world XZ a 2x2 footprint must be aimed at to land on `origin`.
func _aim(a_map: Map, a_origin: Vector2i) -> Vector2:
	return VU.in_xz(a_map.footprint_centroid(a_origin, _DIMS))


func _msg(a_map: Map, a_xz: Vector2) -> CommandMessage:
	return CommandMessage.new(a_map, null, null, Vector3(a_xz.x, 0.0, a_xz.y))


#region One extractor per body
## A pond is a FINITE charge, so a second extractor on it does not add income — it splits the
## same remaining total between two structures and drains it twice as fast. The
## ExtractionSite branch of the same routine has always enforced one per site; this is its
## missing counterpart, added 2026-09-12.
func test_a_pond_admits_an_extractor_while_it_is_unclaimed() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	assert_false(water.has_extractor(), "nothing is working it yet")
	assert_true(water.is_workable(), "charged and free")
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true),
		"the control: an unclaimed pond takes an extractor"
	)


func test_a_pond_refuses_a_second_extractor() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	water.extractor = autofree(Node.new())  # stands in for the structure holding the claim
	assert_true(water.has_extractor())
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true),
		"a body already being worked has no room for a second extractor"
	)


func test_a_released_claim_makes_the_body_workable_again() -> void:
	# What Extractor._on_death does: a destroyed extractor must not strand its pond.
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	water.extractor = autofree(Node.new())
	water.extractor = null
	assert_true(water.is_workable())
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true)
	)


func test_a_freed_claimant_does_not_strand_the_body() -> void:
	# The claim is released explicitly, but a body outliving a MISSED release must not become
	# permanently unworkable — which is why has_extractor() validates rather than trusting the
	# field, and why the field is untyped (a typed read of a freed object errors outright).
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	var claimant := Node.new()
	water.extractor = claimant
	claimant.free()
	assert_false(water.has_extractor(), "a freed claimant holds nothing")
	assert_true(water.is_workable())


func test_a_drained_pond_is_not_worth_working() -> void:
	# is_workable is what the bot's income search filters on: a spent pond is dry ground with
	# a surface on it. Placement itself is a separate question and stays permissive.
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, 0)
	assert_false(water.is_workable(), "no charge left to take")


#endregion


#region The node sits on its pond
## Cosmetic only, and the tests are here to keep it cosmetic: the node is a gizmo, and the
## moment anything starts reading its transform this becomes a behaviour change.
func _basin_centre(a_map: Map, a_body: WaterBody) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	var cells: Array[Vector2i] = a_body.basin.covered_cells()
	for cell: Vector2i in cells:
		total += a_map.grid_to_world(cell)
	return total / float(cells.size())


func test_the_node_is_centred_on_its_basin() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	var centre: Vector3 = _basin_centre(map, water)
	assert_almost_eq(water.global_position.x, centre.x, 0.001, "centred in X")
	assert_almost_eq(water.global_position.z, centre.z, 0.001, "centred in Z")
	assert_almost_eq(
		water.global_position.y,
		water.level,
		0.001,
		"and sits at the water's own surface, not on the ground under it"
	)


func test_recentring_does_not_move_the_water() -> void:
	# The surface pins itself to the MAP's frame rather than this node's, which is what makes
	# the move safe. If that ever changes, the pond visibly slides off its basin.
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	var surface: Node3D = water.get_node_or_null(^"Surface") as Node3D
	assert_not_null(surface, "the generated surface child exists")
	assert_almost_eq(
		surface.global_position.distance_to(map.global_position),
		0.0,
		0.001,
		"the surface stays in the Map's frame however the body node is placed"
	)


func test_recentring_does_not_move_the_footprint() -> void:
	# Coverage is grid-derived from seed_cell, so the transform cannot reach it — asserted
	# rather than assumed, because this is the thing a careless change would break.
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	assert_true(water.covers_cell(_SHALLOW_ORIGIN), "the pan is still flooded")
	assert_true(water.is_shallow(_SHALLOW_ORIGIN), "and still wadeable")
	assert_true(water.is_deep(_DEEP_ORIGIN), "and the well is still deep")


func test_the_transform_is_derived_and_never_saved() -> void:
	# `transform` is the property Node3D stores; position/rotation/scale are editor views of
	# it. Keeping STORAGE off is what stops a stale centre being written into the scene and
	# then disagreeing with the terrain after a re-sculpt (~/.claude/CLAUDE.md §10).
	var water: WaterBody = autofree(WaterBody.new())
	for property: Dictionary in water.get_property_list():
		if property["name"] == "transform":
			assert_eq(
				int(property["usage"]) & PROPERTY_USAGE_STORAGE,
				0,
				"a derived transform is not authored content"
			)
			return
	fail_test("Node3D no longer exposes `transform` — this guard needs rewriting")


#endregion


#region Two builders, one pond
## The one-per-body rule is enforced at PLACEMENT, and placement happens when a builder
## ARRIVES — so two builders ordered at one pond before either arrives both pass the order-time
## check and both raise an extractor. Observed on `skirmish.tscn`: pond (55,104) finished a
## match with two. Both halves of the repair are pinned here.
##
## Bot half: a body an in-flight job is already aimed into is not offered again. `_is_claimed
## _spot` cannot do this job — it is a RADIUS, and a pond is far wider than it, so two jobs
## aimed at different cells of one body both pass.
func _economy_with(a_map: Map, a_units: Array) -> BotEconomy:
	var bot: StubBot = autofree(StubBot.new())
	bot.id = 2
	bot.map = a_map
	bot.units = a_units
	bot.blackboard = CommanderBlackboard.new(bot)
	return autofree(BotEconomy.new(bot, autofree(BotActuator.new(a_map))))


## A builder holding a Build aimed at `a_world`, which is what makes it read as in flight.
func _builder_building_at(a_map: Map, a_world: Vector3) -> Actor:
	var unit := FakePieces.unit(FakePieces.BUILDER)
	add_child_autofree(unit)
	var tool := Tool.new("command_tool_x", &"test_extractor", null, "x", Vector2i.ZERO, 0, 0)
	unit.update_commands(
		[Build.new(CommandMessage.new(a_map, null, tool, a_world))] as Array[MoveCommand]
	)
	return unit


func test_a_pond_an_in_flight_job_is_aimed_into_is_reported() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	var aim: Vector3 = map.grid_to_world(_SHALLOW_ORIGIN)
	var economy: BotEconomy = _economy_with(map, [_builder_building_at(map, aim)])
	assert_eq(
		economy._ponds_under_way(),
		[water] as Array,
		"a body is claimed from the moment a builder is SENT, not when it arrives"
	)


func test_a_pond_already_under_way_is_not_offered_again() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var aim: Vector3 = map.grid_to_world(_SHALLOW_ORIGIN)
	var economy: BotEconomy = _economy_with(map, [_builder_building_at(map, aim)])
	assert_null(
		economy._nearest_workable_pond_spot(),
		"the only pond is spoken for, so there is nowhere to send a second builder"
	)


func test_an_unworked_pond_is_offered_when_nothing_is_under_way() -> void:
	# The control — the rule must not make every pond permanently invisible.
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var economy: BotEconomy = _economy_with(map, [])
	assert_not_null(
		economy._nearest_workable_pond_spot(),
		"with no job in flight the bot still reaches for the pond"
	)


func test_an_unexplored_pond_is_never_offered() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var economy: BotEconomy = _economy_with(map, [])
	(economy._bot as StubBot).explored_filter = func(_a_pos: Vector3) -> bool: return false
	assert_null(
		economy._nearest_workable_pond_spot(),
		"a pond the bot has never had in vision is one it does not know exists"
	)


func test_a_partly_explored_pond_is_offered_only_where_it_was_seen() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var economy: BotEconomy = _economy_with(map, [])
	var seen: Vector3 = map.grid_to_world(_SHALLOW_ORIGIN)
	# The whole footprint aimed there, since placement refuses unexplored ground under any part
	# of it (construction.md §Placement is judged against what the commander knows).
	var seen_cells: Array[Vector2i] = map.footprint_cells(VU.in_xz(seen), _DIMS)
	(economy._bot as StubBot).explored_filter = func(a_pos: Vector3) -> bool:
		return seen_cells.has(map.world_to_grid(VU.in_xz(a_pos)))
	assert_eq(
		economy._nearest_workable_pond_spot(),
		seen,
		"the spot offered is a cell the bot has actually looked at"
	)


func test_a_pond_taken_out_of_sight_still_reads_open() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	var enemy: Commander = Commander.new()
	enemy.id = 1
	add_child_autofree(enemy)
	var claimant := FakePieces.unit(FakePieces.BUILDER)
	add_child_autofree(claimant)
	claimant.ownership.commander = enemy
	water.extractor = claimant
	assert_not_null(
		_economy_with(map, [])._nearest_workable_pond_spot(),
		"the bot has not seen the enemy extractor, so it believes the pond is free"
	)


func test_a_remembered_structure_in_the_water_claims_the_pond() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var economy: BotEconomy = _economy_with(map, [])
	var entry := CommanderBlackboard.Entry.new()
	entry.instance_id = 1
	entry.is_structure = true
	entry.last_known_location = map.grid_to_world(_SHALLOW_ORIGIN)
	economy._bot.blackboard._entries[entry.instance_id] = entry
	assert_null(
		economy._nearest_workable_pond_spot(),
		"it last saw an enemy structure standing in the pond, and has not looked since"
	)


func test_a_drained_pond_is_never_offered() -> void:
	var map: Map = _make_map()
	_add_water(map, 0)
	assert_null(
		_economy_with(map, [])._nearest_workable_pond_spot(),
		"a spent pond is dry ground with a surface on it"
	)


#endregion


#region The water layer itself
func test_the_pan_is_shallow_and_the_well_is_deep() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	assert_true(water.is_shallow(_SHALLOW_ORIGIN), "the pan is wadeable")
	assert_true(water.is_deep(_DEEP_ORIGIN), "the well is not")
	assert_false(water.covers_cell(_DRY_ORIGIN), "ground at the level is dry")


## Deep water is an impassability reason in the terrain grid, which is what takes it out of
## the navmesh. Shallow water is not: units wade through it with no change at all.
func test_deep_water_leaves_the_navmesh_and_shallow_water_does_not() -> void:
	var map: Map = _make_map()
	_add_water(map)
	assert_true(map.terrain_grid.is_submerged(_DEEP_ORIGIN), "a deep cell is marked submerged")
	assert_false(map.terrain_grid.is_passable(_DEEP_ORIGIN), "and is therefore impassable")
	assert_false(map.terrain_grid.is_submerged(_SHALLOW_ORIGIN), "a wadeable cell is not")
	assert_true(map.terrain_grid.is_passable(_SHALLOW_ORIGIN), "and stays walkable")


## The submerged bit is its own reason: republishing the water layer must not disturb the
## tile-type / out-of-play mask, and removing a body must not unblock what that mask blocked.
func test_water_and_the_blocked_mask_are_independent() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	map.terrain_grid.set_blocked(_SHALLOW_ORIGIN, true)
	water.level = _GROUND + 1.0  # republishes the whole water layer
	assert_true(
		map.terrain_grid.is_blocked(_SHALLOW_ORIGIN), "the blocked bit survives a water edit"
	)
	map.terrain_grid.set_blocked(_DEEP_ORIGIN, true)
	map.terrain_grid.set_submerged_mask(PackedByteArray())
	assert_true(map.terrain_grid.is_blocked(_DEEP_ORIGIN), "clearing the water layer leaves it")


#endregion


#region Where a structure may stand
func test_an_ordinary_structure_is_refused_by_shallow_water() -> void:
	var map: Map = _make_map()
	_add_water(map)
	assert_true(
		Fixture.valid_placement(_msg(map, _aim(map, _DRY_ORIGIN)), _DIMS),
		"dry flat ground takes an ordinary structure"
	)
	assert_false(
		Fixture.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS),
		"shallow water admits nothing that has not declared allow_submerged"
	)


func test_allow_submerged_grants_shallow_water_but_never_deep() -> void:
	var map: Map = _make_map()
	_add_water(map)
	assert_true(
		Fixture.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true),
		"a submersible structure stands in wadeable water"
	)
	assert_false(
		Fixture.valid_placement(_msg(map, _aim(map, _DEEP_ORIGIN)), _DIMS, false, true),
		"deep water is impassable ground and holds nothing at all"
	)


func test_an_extractor_may_be_built_in_shallow_water() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true),
		"a pond is a host: an extractor may be built anywhere shallow in it"
	)
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _DEEP_ORIGIN)), _DIMS, false, true),
		"not in the deep part of it"
	)
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _DRY_ORIGIN)), _DIMS, false, true),
		"and not on dry ground with no site under it"
	)


## A piece that overlays sites but collects no energy (the Technocratic Lab) is refused a pond
## that an extractor would take: a pond is a finite ENERGY reservoir, so there is nothing in it
## for such a piece to work.
func test_a_site_only_piece_is_refused_the_pond_an_extractor_takes() -> void:
	var map: Map = _make_map()
	_add_water(map, WaterBody.NOMINAL_ENERGY)
	var aim: CommandMessage = _msg(map, _aim(map, _SHALLOW_ORIGIN))
	assert_true(
		EnergyExtractor.valid_placement(aim, _DIMS, false, true),
		"the control: an extractor may go here"
	)
	assert_false(
		EnergyExtractor.valid_placement(aim, _DIMS, false, true, false),
		"a site-only piece may not"
	)


## The pond does not have to be charged for an extractor to be legal in it — buildability is
## a property of the water, not of what is dissolved in it. An extractor on a spent pond is a
## waste, not an error.
func test_an_uncharged_body_still_admits_an_extractor() -> void:
	var map: Map = _make_map()
	_add_water(map, 0)
	assert_true(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, _SHALLOW_ORIGIN)), _DIMS, false, true),
		"plain shallow water takes an extractor too"
	)


func test_a_footprint_half_out_of_the_water_is_refused() -> void:
	var map: Map = _make_map()
	_add_water(map)
	# The pan's min corner is cell (6, 6), so a footprint at (5, 6) straddles the shoreline.
	assert_false(
		EnergyExtractor.valid_placement(_msg(map, _aim(map, Vector2i(5, 6))), _DIMS, false, true),
		"an extractor must be entirely inside one body of water"
	)


#endregion


#region What a pond pays
func test_a_pond_pays_the_multiple_of_the_extractor_rate() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, WaterBody.NOMINAL_ENERGY)
	var rate: int = 100
	assert_eq(
		water.extract(rate),
		rate * WaterBody.POND_RATE_MULTIPLIER,
		"a pond yields the pond multiple of the extractor's own rate"
	)
	assert_eq(
		water.energy,
		WaterBody.NOMINAL_ENERGY - rate * WaterBody.POND_RATE_MULTIPLIER,
		"and debits itself by exactly what it paid"
	)


func test_a_withdrawal_is_clamped_to_what_is_left() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, 30)
	assert_eq(water.extract(100), 30, "the last withdrawal yields only the remainder")
	assert_eq(water.energy, 0, "which empties the pond")
	assert_eq(water.extract(100), 0, "a spent pond yields nothing")


func test_an_uncharged_body_yields_nothing() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, 0)
	assert_eq(water.extract(100), 0, "plain water is not a reservoir")
	assert_eq(water.charge_fraction(), 0.0, "and reads as fully drained, like a spent pond")


## The charge fraction is what fades the surface from its lithium colour back to blue, so it
## has to be measured against the body's FULL charge rather than against whatever is left.
func test_charge_fraction_tracks_the_draw_down() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map, 200 * WaterBody.POND_RATE_MULTIPLIER)
	assert_eq(water.charge_fraction(), 1.0, "a full pond is fully tinted")
	water.extract(100)  # draws 100 x POND_RATE_MULTIPLIER: half the charge
	assert_almost_eq(water.charge_fraction(), 0.5, 0.001, "half drained is half tinted")


#endregion


#region Surviving an undo/redo round trip
## A body removed from the tree and added back — what undo/redo does to the SAME instance —
## must still respond to an edit. `_ready` fires only once per node, so the body used to come
## back with no map, `rebuild()` returned early, and every later change to `level` was
## silently ignored while the old surface stayed on screen.
func test_a_body_re_added_to_the_tree_still_responds_to_level() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	var before: int = water.basin.covered_cells().size()
	assert_gt(before, 0, "the fixture pond holds water to begin with")

	map.remove_child(water)
	assert_false(map.water_bodies.has(water), "leaving the tree deregisters the body")

	map.add_child(water)
	water.level = _GROUND + WaterBasin.WADE_DEPTH  # a deeper pond than it had
	assert_true(map.water_bodies.has(water), "editing it after re-entry re-binds it to the map")
	assert_gt(
		water.basin.covered_cells().size(),
		before,
		"raising the level after a remove/re-add actually re-floods the basin"
	)
	water.free()


## The number that would have caught "the pond is invisible in game": a body far shallower than
## the terrain's own relief is drawn and still cannot be seen, because the steps around it hide
## the flat plane from an oblique camera.
func test_a_basin_reports_its_depth_and_where_terrain_breaks_through() -> void:
	var map: Map = _make_map()
	var water: WaterBody = _add_water(map)
	assert_almost_eq(
		water.basin.max_depth,
		WaterBasin.WADE_DEPTH * 3.0,
		0.001,
		"max_depth is the deepest cell, which is the well, not the pan"
	)
	# The SHORELINE always pierces — that ring is where the ground meets the level by
	# definition — so what matters is that it stays a minority. Half or more is the brush's
	# "too shallow to see" threshold.
	var covered: int = water.basin.covered_cells().size()
	var pierced_before: int = water.basin.cells_pierced_by_terrain
	assert_gt(pierced_before, 0, "the shoreline ring breaks the surface, as it must")
	assert_lt(
		pierced_before * 2,
		covered,
		"a pond with a real floor is mostly open water, not mostly shoreline"
	)

	# Poke isolated CORNERS just above the level, well away from the seed. Each cell touching
	# one still averages below the level — so it stays covered — while the corner itself breaks
	# the surface, which is exactly the case that makes a pond unreadable in game. (Raising a
	# whole block instead would shrink the basin rather than pierce it.)
	var td: TerrainData = map.terrain_data
	var heights: PackedFloat32Array = td.heights
	for corner: Vector2i in [Vector2i(11, 11), Vector2i(14, 14)]:
		heights[corner.y * td.map_width() + corner.x] = _GROUND + 0.05
	td.heights = heights
	water.rebuild()
	assert_gt(
		water.basin.cells_pierced_by_terrain,
		pierced_before,
		"terrain raised through the surface is counted, which is what warns an author off"
	)
#endregion
