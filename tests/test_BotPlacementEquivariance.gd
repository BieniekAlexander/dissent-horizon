extends GutTest

## WHERE THE BOT PUTS A BUILDING MUST NOT DEPEND ON WHICH WAY THE MAP IS POINTING.
##
## This is the test that pins the property the old ring scan broke.
## `BotEconomy._find_build_spot` used to walk rings outward and return the FIRST valid cell,
## scanning `for dx` then `for dy` from -radius, so the answer was always the cell furthest
## toward -X and then -Z. On a provably point-symmetric map that made two identically
## configured commanders lay their bases out over DIFFERENT ground — measured at a mean
## offset of dx ≈ -5 for both sides instead of ±5 — and the resulting start-position bias was
## 16 wins out of 16 with a mean material margin of +9,632
## (gdd/systems/ai/selfplay-results-2026-09-06.md §The mechanism).
##
## The property wanted is EQUIVARIANCE, not symmetry:
##
##   * apply an isometry to the bot's whole situation and its choice moves by that isometry
##     (§the mirror, §the quarter turn);
##   * the layout itself is free to be lopsided, and IS — production toward the believed
##     threat, everything else behind the base (§the asymmetry is real).
##
## Ties are broken in the bot's own frame rather than by a random draw, deliberately: a draw
## from the shared `SU.rng` is reproducible across replays but NOT mirror-consistent, since
## two bots drawing from one stream in interleaved order get different numbers.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotPlacementEquivariance.gd
## -gexit

const PRODUCTION: StringName = &"test_redoubt"
const SUPPORT: StringName = &"test_infrastructure"

## 32 x 32 cells centred on the world origin, so cell centres sit at ±0.5, ±1.5, … — a set
## carried onto itself by both the point reflection and the quarter turn about the origin.
const CELLS: int = 32
const EPS: float = 1e-5


## A Map with terrain but no navmesh: everything under test is grid maths.
class TestMap:
	extends Map

	func _ready() -> void:
		var shape := HeightMapShape3D.new()
		shape.map_width = CELLS + 1
		shape.map_depth = CELLS + 1
		var data := PackedFloat32Array()
		data.resize((CELLS + 1) * (CELLS + 1))
		shape.map_data = data
		height_map = shape
		terrain_grid = TerrainGrid.new()
		terrain_grid.height_map = shape
		terrain_grid.terrain_body = terrain_body
		add_child(terrain_grid)
		cell_grid = []
		for _x: int in CELLS:
			var column: Array = []
			for _z: int in CELLS:
				column.append(null)
			cell_grid.append(column)


class FakeBot:
	extends Bot
	var base: Vector3 = Vector3.ZERO
	var threat: Variant = null
	var production: Array = [PRODUCTION]
	## The one static defence type, with a gun reaching this far; none unless a test says.
	var defence: Array = []
	var defence_reach: float = 12.0

	func base_centroid() -> Vector3:
		return base

	func get_units() -> Array:
		return []

	func buildable_production_structure_types() -> Array:
		return production

	func buildable_defence_structure_types() -> Array:
		return defence

	func ground_reach_of_type(_a_type: StringName) -> float:
		return defence_reach

	func nearest_believed_enemy_structure_position(_a_accept: Variant = null) -> Variant:
		return threat

	func nearest_believed_enemy_unit_position(
		_a_from: Vector3, _a_accept: Variant = null
	) -> Variant:
		return null

	## The fields are what a test sets and nothing else: the real accessor would build a
	## BotFields over the test map, and the two-level search would then shape every case here.
	func fields() -> BotFields:
		return _fields


## Footprint dimensions come off a build preview in the real thing, which would drag the
## whole Tool registry into this test; every building here is the 2x2 the game's are, unless
## a test says otherwise.
class StubEconomy:
	extends BotEconomy
	var dims: Vector2i = Vector2i(2, 2)

	func _dims_for_type(_a_type: StringName) -> Vector2i:
		return dims


var _world: Node3D
var _map: TestMap


func before_each() -> void:
	_world = Node3D.new()
	_map = _make_map()
	_world.add_child(_map)
	add_child_autofree(_world)


func _make_map() -> TestMap:
	var map := TestMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	map.add_child(region)
	return map


## A bot anchored at `a_base` believing the enemy is at `a_threat` (or nothing, for null).
func _bot_at(a_base: Vector2, a_threat: Variant) -> FakeBot:
	var bot := FakeBot.new()
	bot.map = _map
	bot.base = VU.from_xz(a_base)
	bot.threat = VU.from_xz(a_threat) if a_threat != null else null
	return autofree(bot)


func _spot(a_bot: FakeBot, a_type: StringName, a_dims: Vector2i = Vector2i(2, 2)) -> Variant:
	var economy := StubEconomy.new(a_bot, null)
	economy.dims = a_dims
	return economy._find_build_spot(a_type)


## The cell reflected through the map's centre — the isometry the symmetric scenario uses.
func _mirror_cell(a_cell: Vector2i) -> Vector2i:
	return Vector2i(CELLS - 1 - a_cell.x, CELLS - 1 - a_cell.y)


func _block(a_cells: Array) -> void:
	for cell: Vector2i in a_cells:
		_map.terrain_grid.set_blocked(cell, true)


## Block `a_cells` AND their reflections, so the map is exactly point-symmetric.
func _block_symmetrically(a_cells: Array) -> void:
	for cell: Vector2i in a_cells:
		_map.terrain_grid.set_blocked(cell, true)
		_map.terrain_grid.set_blocked(_mirror_cell(cell), true)


func _xz(a_spot: Variant) -> Vector2:
	return VU.in_xz(a_spot as Vector3)


# ─── THE MIRROR: THE ACCEPTANCE PROPERTY ────────────────────────────────────


func test_two_mirrored_bots_choose_mirrored_spots() -> void:
	# The exact shape of the symmetric scenario: one map carried onto itself by the point
	# reflection, two commanders at reflected start points believing reflected things.
	_block_symmetrically(
		[
			Vector2i(11, 6),
			Vector2i(12, 6),
			Vector2i(11, 7),
			Vector2i(12, 7),
			Vector2i(20, 14),
			Vector2i(20, 15),
			Vector2i(21, 15),
		]
	)
	var base := Vector2(-6.5, 9.5)
	var threat := Vector2(4.5, -8.5)
	for type: StringName in [PRODUCTION, SUPPORT]:
		var north: Variant = _spot(_bot_at(base, threat), type)
		var south: Variant = _spot(_bot_at(-base, -threat), type)
		assert_not_null(north, "%s: the north bot found somewhere" % type)
		assert_not_null(south, "%s: the south bot found somewhere" % type)
		assert_almost_eq(
			_xz(south),
			-_xz(north),
			Vector2(EPS, EPS),
			"%s: the two choices are each other's reflection, not both toward -X" % type
		)


func test_the_mirror_holds_at_every_footprint_parity() -> void:
	# THE SUBTLER HALF OF THE SAME BUG, and the reason a candidate is a footprint ORIGIN
	# rather than a cell. `Map.footprint_origin` resolves an EVEN footprint by rounding in
	# absolute grid coordinates, so two mirror-image CELL CENTRES resolve to footprints one
	# cell apart — a world-frame preference one layer below the ring scan. It showed up in a
	# real match as a one-cell residual between two otherwise perfect mirror layouts, and it
	# only appears at some base parities, so this sweeps them.
	for base: Vector2 in [
		Vector2(-1.0, 9.0),
		Vector2(-0.5, 9.5),
		Vector2(-1.5, 8.0),
		Vector2(-6.5, 9.5),
		Vector2(-2.0, 10.5),
		Vector2(-3.5, 7.0),
	]:
		for dims: Vector2i in [Vector2i(2, 2), Vector2i(3, 3), Vector2i(1, 1)]:
			var threat := Vector2(2.0, -11.0)
			var north: Variant = _spot(_bot_at(base, threat), PRODUCTION, dims)
			var south: Variant = _spot(_bot_at(-base, -threat), PRODUCTION, dims)
			assert_not_null(north, "base %s dims %s" % [base, dims])
			assert_almost_eq(
				_xz(south),
				-_xz(north),
				Vector2(EPS, EPS),
				"base %s, %s footprint: the two choices must reflect onto each other" % [base, dims]
			)


func test_the_chosen_spot_survives_the_round_trip_to_a_footprint() -> void:
	# The spot handed to Build is a footprint CENTROID, and Fixture.valid_placement
	# re-derives the origin from it. If that round trip moved, the bot would be scoring one
	# footprint and building another.
	var bot := _bot_at(Vector2(-2.5, 3.5), Vector2(10.0, -4.0))
	for dims: Vector2i in [Vector2i(2, 2), Vector2i(3, 3)]:
		var spot: Vector2 = _xz(_spot(bot, PRODUCTION, dims))
		var origin: Vector2i = _map.footprint_origin(spot, dims)
		assert_almost_eq(
			VU.in_xz(_map.footprint_centroid(origin, dims)),
			spot,
			Vector2(EPS, EPS),
			"%s footprint: centroid → origin → centroid is the identity" % dims
		)


func test_the_choice_is_not_pinned_to_a_world_axis() -> void:
	# THE OLD BUG, stated as an assertion. The ring scan returned the -X-most cell of the
	# first ring with any valid cell, whatever the bot's situation was; here the situation is
	# reflected and the answer has to follow it rather than stay put.
	var east: Variant = _spot(_bot_at(Vector2.ZERO, Vector2(12.0, 0.0)), PRODUCTION)
	var west: Variant = _spot(_bot_at(Vector2.ZERO, Vector2(-12.0, 0.0)), PRODUCTION)
	assert_gt(_xz(east).x, 0.0, "a threat to the east puts production east")
	assert_lt(_xz(west).x, 0.0, "and a threat to the west puts it west")
	assert_almost_eq(_xz(west), -_xz(east), Vector2(EPS, EPS))


func test_a_quarter_turn_of_the_situation_turns_the_choice() -> void:
	# Rotation, not just reflection: the square grid is carried onto itself by a quarter turn
	# about the origin, so the bot's answer has to be too.
	var east: Variant = _spot(_bot_at(Vector2.ZERO, Vector2(11.0, 0.0)), PRODUCTION)
	var north: Variant = _spot(_bot_at(Vector2.ZERO, Vector2(0.0, 11.0)), PRODUCTION)
	var turned := Vector2(-_xz(east).y, _xz(east).x)
	assert_almost_eq(
		_xz(north),
		turned,
		Vector2(EPS, EPS),
		"turning the threat a quarter turn turns the placement with it"
	)


# ─── THE ASYMMETRY IS REAL, AND IT IS RELATIVE TO THE BOT ───────────────────


func test_production_goes_toward_the_threat_and_support_behind_the_base() -> void:
	var bot := _bot_at(Vector2.ZERO, Vector2(0.0, 12.0))
	var forward: Vector2 = Vector2(0.0, 1.0)
	var production: float = _xz(_spot(bot, PRODUCTION)).dot(forward)
	var support: float = _xz(_spot(bot, SUPPORT)).dot(forward)
	assert_gt(production, 0.0, "production sits up the threat axis")
	assert_lt(support, 0.0, "and everything else sits behind the base")


func test_the_bearing_weights_move_the_layout() -> void:
	# The two directional terms are the searchable half of the model; at zero the base is
	# concentric and the type no longer matters.
	var bot := _bot_at(Vector2.ZERO, Vector2(0.0, 12.0))
	var economy := StubEconomy.new(bot, null)
	economy.place_frontage_bias = 0.0
	economy.place_shelter_bias = 0.0
	var production: Vector2 = _xz(economy._find_build_spot(PRODUCTION))
	var support: Vector2 = _xz(economy._find_build_spot(SUPPORT))
	assert_almost_eq(
		production,
		support,
		Vector2(EPS, EPS),
		"with both biases at zero the two kinds want the same, nearest, spot"
	)


func test_it_stays_inside_the_search_annulus() -> void:
	var bot := _bot_at(Vector2(3.5, -2.5), Vector2(12.0, 12.0))
	var offset: float = (_xz(_spot(bot, PRODUCTION)) - Vector2(3.5, -2.5)).length()
	assert_between(
		offset, float(BotEconomy.SEARCH_MIN_RING) - 1.5, float(BotEconomy.SEARCH_MAX_RING) + 1.5
	)


# ─── THE HARD CONSTRAINTS, THROUGH THE BOT ──────────────────────────────────


func test_it_will_not_wall_off_part_of_the_map() -> void:
	# A wall across the map with one two-cell gate right where the bot would most like to
	# build. The scored comparison offers that spot first and the constraint refuses it.
	_block(_rect(18, 0, 1, 14))
	_block(_rect(18, 18, 1, 14))
	var bot := _bot_at(Vector2(-13.5, -0.5), Vector2(14.0, 0.0))
	var spot: Variant = _spot(bot, PRODUCTION)
	assert_not_null(spot, "it still finds somewhere")
	var footprint: Array = _map.footprint_cells(_xz(spot), Vector2i(2, 2))
	assert_true(
		_map.terrain_grid.placement_preserves_connectivity(footprint),
		"and the spot it takes does not split the walkable surface"
	)


func test_a_production_structure_is_never_walled_in() -> void:
	# A sealed courtyard right next to the base: cheap, close, and useless. The bot's own
	# units are not in it, so the access rule has to send the building outside.
	_block(_rect(12, 12, 8, 1))
	_block(_rect(12, 19, 8, 1))
	_block(_rect(12, 13, 1, 6))
	_block(_rect(19, 13, 1, 6))
	var bot := _bot_at(Vector2(-0.5, -0.5), Vector2(0.0, 14.0))
	var spot: Variant = _spot(bot, PRODUCTION)
	assert_not_null(spot)
	var footprint: Array = _map.footprint_cells(_xz(spot), Vector2i(2, 2))
	var region: int = _map.terrain_grid.largest_component()
	assert_true(
		NavPlacement.has_navmesh_side(_map.terrain_grid, footprint, region),
		"the chosen spot keeps a whole side on the ground the bot's units are on"
	)


func test_no_spot_at_all_is_null_rather_than_a_bad_one() -> void:
	for x: int in CELLS:
		for z: int in CELLS:
			_map.terrain_grid.set_blocked(Vector2i(x, z), true)
	assert_null(_spot(_bot_at(Vector2.ZERO, Vector2(10.0, 0.0)), PRODUCTION))


func _rect(a_x: int, a_z: int, a_w: int, a_d: int) -> Array:
	var out: Array = []
	for i: int in a_w:
		for j: int in a_d:
			out.append(Vector2i(a_x + i, a_z + j))
	return out


# ─── A SEARCH SPLIT ACROSS TICKS ─────────────────────────────────────────────


## The scheduler may run the search in slices (BotEconomy._find_build_spot is resumable). A
## search run one sliver of budget at a time must land on exactly the spot an uninterrupted one
## picks — the ranking is fixed when the search starts, so slicing may never reorder it.
func test_a_search_split_into_slices_picks_the_same_spot() -> void:
	_block_symmetrically([Vector2i(11, 6), Vector2i(12, 6), Vector2i(20, 14)])
	var bot: FakeBot = _bot_at(Vector2(-6.5, 9.5), Vector2(4.5, -8.5))
	var whole: Variant = _spot(bot, PRODUCTION)
	var economy := StubEconomy.new(bot, null)
	var slices: int = 0
	var sliced: Variant = BotEconomy.SEARCH_PENDING
	while sliced is StringName:
		economy._work = 0
		economy._allowance = 1  # the least a call can be given: one step
		sliced = economy._find_build_spot(PRODUCTION)
		slices += 1
	assert_gt(slices, 2, "the search really was split")
	assert_not_null(whole)
	assert_almost_eq(_xz(sliced), _xz(whole), Vector2(EPS, EPS))


# ─── A NON-SQUARE FOOTPRINT IS PLACED AT EITHER ORIENTATION ─────────────────
# footprint-rotation.md §Slices, slice 4.


## The facing of a laid structure points up the threat axis, within the orientation chosen.
func test_a_structure_faces_up_the_threat_axis() -> void:
	assert_eq(BotEconomy.facing_turns(false, Vector2(0.0, 1.0)), 0)
	assert_eq(BotEconomy.facing_turns(false, Vector2(0.0, -1.0)), 2)
	assert_eq(BotEconomy.facing_turns(true, Vector2(1.0, 0.0)), 1)
	assert_eq(BotEconomy.facing_turns(true, Vector2(-1.0, 0.0)), 3)


## Between two otherwise equal candidates, the one lying ACROSS the threat axis comes first.
func test_a_footprint_lying_along_the_threat_axis_is_ranked_after_one_across_it() -> void:
	var east := Vector2(1.0, 0.0)
	assert_ne(
		BotEconomy._orientation_bits(Vector2i(4, 2), false, east) & BotEconomy.RANK_ALONG_BIT, 0
	)
	assert_eq(
		BotEconomy._orientation_bits(Vector2i(2, 4), true, east) & BotEconomy.RANK_ALONG_BIT, 0
	)
	assert_eq(
		BotEconomy._orientation_bits(Vector2i(3, 3), false, east), 0, "a square has no long axis"
	)


## The orientation is part of the choice, so it turns with the situation like the position does.
func test_a_quarter_turn_of_the_situation_turns_a_long_footprint() -> void:
	var dims := Vector2i(2, 4)
	var east_economy := StubEconomy.new(_bot_at(Vector2.ZERO, Vector2(11.0, 0.0)), null)
	east_economy.dims = dims
	var east: Vector2 = _xz(east_economy._find_build_spot(PRODUCTION))
	var east_turns: int = _turns_of(east_economy)
	var north_economy := StubEconomy.new(_bot_at(Vector2.ZERO, Vector2(0.0, 11.0)), null)
	north_economy.dims = dims
	var north: Vector2 = _xz(north_economy._find_build_spot(PRODUCTION))
	assert_almost_eq(north, Vector2(-east.y, east.x), Vector2(EPS, EPS), "the spot turns")
	assert_ne(_turns_of(north_economy) % 2, east_turns % 2, "and so does which way it lies")


## Both orientations of a long footprint are ranked, in one list.
func test_both_orientations_of_a_long_footprint_are_ranked() -> void:
	var economy := StubEconomy.new(_bot_at(Vector2.ZERO, Vector2(0.0, 12.0)), null)
	economy.dims = Vector2i(2, 4)
	var search: Dictionary = economy._new_spot_search(PRODUCTION)
	economy._continue_ranking(search["ranking"], BotJob.UNLIMITED_WORK_UNITS)
	var turned: int = 0
	var authored: int = 0
	for packed: int in search["ranking"]["out"]:
		if packed & BotEconomy.RANK_TURNED_BIT != 0:
			turned += 1
		else:
			authored += 1
	assert_gt(turned, 0, "the turned footprint is a candidate")
	assert_gt(authored, 0, "and so is the authored one")
	var square := StubEconomy.new(_bot_at(Vector2.ZERO, Vector2(0.0, 12.0)), null)
	var square_search: Dictionary = square._new_spot_search(PRODUCTION)
	assert_eq(square_search["ranking"]["parts"].size(), 1, "a square footprint is ranked once")


func _turns_of(a_economy: BotEconomy) -> int:
	return int(a_economy._spot_turns.values()[0]) if not a_economy._spot_turns.is_empty() else -1


# ─── COVERAGE OF THE APPROACH BAND ──────────────────────────────────────────

const DEFENCE: StringName = &"fake_defence"


## The believed threat lies EAST, so the bearing pulls a frontage building east; but the
## fields say the enemy's actual walk to home comes down from the NORTH (a believed group
## there), so the approach band runs north from the base. A turret goes where the band is.
func test_a_defence_is_pulled_onto_the_approach_band_not_merely_forward() -> void:
	var bot: FakeBot = _bot_at(Vector2.ZERO, Vector2(40.0, 0.0))
	bot.defence = [DEFENCE]
	# A 35-unit lattice at pitch 5 puts a cell centre on the base at (0, 0), so the band from
	# the walker runs due north THROUGH the base rather than up a column beside it (on the
	# 32-cell map's own lattice the centres sit at ±2.5, by Lattice.covering's parity rule).
	var fields: FixtureFields = FixtureFields.over_open(Rect2(-17.5, -17.5, 35.0, 35.0))
	fields.home = [fields.lattice.index_at(Vector2.ZERO)]
	fields.add_walker(fields.lattice.index_at(Vector2(0.0, 14.0)), 2.0)  # inside the 32-cell map
	bot._fields = fields
	var economy := StubEconomy.new(bot, null)
	economy.place_coverage_weight = 0.0
	var by_bearing: Vector2 = _xz(economy._find_build_spot(DEFENCE))
	economy = StubEconomy.new(bot, null)
	economy.place_coverage_weight = 20.0
	var by_coverage: Vector2 = _xz(economy._find_build_spot(DEFENCE))
	assert_gt(by_bearing.x, absf(by_bearing.y), "bearing alone: east, toward the believed threat")
	assert_gt(by_coverage.y, absf(by_coverage.x), "with coverage: north, onto the band")


# ─── THE TWO-LEVEL SEARCH ────────────────────────────────────────────────────
## With the fields, the search picks a lattice cell first and scores origins only in that
## cell's block; without them it is the one-level search above. (lattice-and-topology.md
## §Build order, step 2.)


func _fields_over_map() -> FixtureFields:
	# 35 units at pitch 5: seven cells a side, centred on the origin like the map.
	return FixtureFields.over_open(Rect2(-17.5, -17.5, 35.0, 35.0))


func test_with_fields_every_scored_origin_lies_in_the_chosen_region() -> void:
	var bot: FakeBot = _bot_at(Vector2.ZERO, Vector2(12.0, 0.0))
	bot._fields = _fields_over_map()
	var economy := StubEconomy.new(bot, null)
	var search: Dictionary = economy._new_spot_search(PRODUCTION)
	economy._continue_ranking(search["ranking"], BotJob.UNLIMITED_WORK_UNITS)
	var part: Dictionary = search["ranking"]["parts"][0]  # a square footprint: one orientation
	assert_gt((part["regions"] as PackedInt64Array).size(), 1, "the annulus holds several cells")
	var region: Rect2 = part["region_rect"]
	assert_eq(region.size, Vector2(10.0, 10.0), "a cell grown by half a cell each way")
	var width: int = _map.terrain_grid.grid_width()
	for packed: int in part["out"]:
		var centroid: Vector2 = _xz(
			_map.footprint_centroid(BotEconomy.ranked_origin(packed, width), economy.dims)
		)
		assert_true(region.has_point(centroid), "origin %s is inside the region" % centroid)
	bot._fields = null
	var flat: Dictionary = economy._new_spot_search(PRODUCTION)
	economy._continue_ranking(flat["ranking"], BotJob.UNLIMITED_WORK_UNITS)
	var flat_part: Dictionary = flat["ranking"]["parts"][0]
	assert_true((flat_part["regions"] as PackedInt64Array).is_empty(), "no lattice, no level one")
	assert_gt(
		(flat["ranking"]["out"] as PackedInt64Array).size(),
		(part["out"] as PackedInt64Array).size(),
		"the one-level search scores the whole annulus"
	)


func test_a_region_with_nothing_placeable_falls_back_to_the_next() -> void:
	var bot: FakeBot = _bot_at(Vector2.ZERO, Vector2(12.0, 0.0))
	bot._fields = _fields_over_map()
	var economy := StubEconomy.new(bot, null)
	var search: Dictionary = economy._new_spot_search(PRODUCTION)
	economy._continue_ranking(search["ranking"], BotJob.UNLIMITED_WORK_UNITS)
	var first: Rect2 = search["ranking"]["parts"][0]["region_rect"]
	# Wall the whole first region, so nothing in it can stand.
	for z: int in range(int(first.position.y), int(first.end.y)):
		for x: int in range(int(first.position.x), int(first.end.x)):
			var cell: Vector2i = _map.world_to_grid(Vector2(x + 0.5, z + 0.5))
			if _map.grid_coordinates_in_bounds(cell):
				_map.terrain_grid.set_blocked(cell, true)
	economy._spot_search = {}
	var spot: Variant = economy._find_build_spot(PRODUCTION)
	while spot is StringName and spot == BotEconomy.SEARCH_PENDING:
		spot = economy._find_build_spot(PRODUCTION)
	assert_not_null(spot, "the search moved on to another region")
	assert_false(first.has_point(_xz(spot)), "and placed outside the walled one")


func test_two_mirrored_bots_with_fields_choose_mirrored_spots() -> void:
	_block_symmetrically([Vector2i(11, 6), Vector2i(12, 6), Vector2i(20, 14), Vector2i(20, 15)])
	var base := Vector2(-6.5, 9.5)
	var threat := Vector2(4.5, -8.5)
	var north_bot: FakeBot = _bot_at(base, threat)
	north_bot._fields = _fields_over_map()
	var south_bot: FakeBot = _bot_at(-base, -threat)
	south_bot._fields = _fields_over_map()
	for type: StringName in [PRODUCTION, SUPPORT]:
		var north: Variant = _spot(north_bot, type)
		var south: Variant = _spot(south_bot, type)
		assert_not_null(north, "%s: the north bot found somewhere" % type)
		assert_not_null(south, "%s: the south bot found somewhere" % type)
		assert_almost_eq(_xz(south), -_xz(north), Vector2(EPS, EPS), "%s: mirrored" % type)
