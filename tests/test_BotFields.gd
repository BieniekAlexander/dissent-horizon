extends GutTest

## THE BOT'S LATTICE PASSABILITY READS THE TRUE GRID, COARSELY; THE EXPLORED SET IS A
## SEPARATE GATE; THE FIELDS OVER THEM ARE PURE RULES: a lattice cell is passable when enough of
## the terrain cells under it survive
## the class's erosion, whatever the fog says, and a cell is a legal destination only once the
## commander has explored its centre. Both rules are pure functions (`BotFields.lattice_mask`,
## `BotFields.explored_mask_over`), exercised here with no map, no fog and no scene
## (gdd/systems/ai/world-model/lattice-and-topology.md §Passability is relative).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotFields.gd -gexit

## A 10 × 10 terrain grid of unit cells with its min corner at the origin, under a 2 × 2
## lattice of pitch 5 — four lattice cells of 25 terrain cells each.
const TERRAIN: int = 10
const FIRST_CENTRE := Vector2(0.5, 0.5)


func _lattice() -> Lattice:
	return Lattice.covering(Rect2(0.0, 0.0, 10.0, 10.0), 5.0)


func _terrain(a_blocked: Array = []) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(TERRAIN * TERRAIN)
	mask.fill(1)
	for cell: Vector2i in a_blocked:
		mask[cell.y * TERRAIN + cell.x] = 0
	return mask


func _mask(a_terrain: PackedByteArray, a_lattice: Lattice = _lattice()) -> PackedByteArray:
	return BotFields.lattice_mask(a_lattice, a_terrain, TERRAIN, TERRAIN, FIRST_CENTRE, 1.0)


## The terrain cells of the first `a_columns` columns, over the first five rows — a wall
## standing in lattice cell (0, 0).
func _columns(a_columns: int) -> Array:
	var out: Array = []
	for x: int in a_columns:
		for z: int in 5:
			out.append(Vector2i(x, z))
	return out


# ─── PASSABILITY ────────────────────────────────────────────────────────────


func test_open_ground_is_passable_everywhere() -> void:
	assert_eq(_mask(_terrain()), PackedByteArray([1, 1, 1, 1]))


func test_a_block_more_wall_than_ground_is_a_wall() -> void:
	# Three of five columns blocked: 10 of 25 navigable, under the half.
	assert_eq(_mask(_terrain(_columns(3))), PackedByteArray([0, 1, 1, 1]))
	# Two of five: 15 of 25 navigable, over it.
	assert_eq(_mask(_terrain(_columns(2))), PackedByteArray([1, 1, 1, 1]))


func test_a_lattice_cell_hanging_past_the_terrain_is_impassable() -> void:
	# 11 wide at pitch 5 wants 3 cells centred on 6: cells span [-1.5, 13.5), and the outer
	# ones only half-cover the 12-cell terrain — still passable, since what they cover is open;
	# a lattice laid wholly off the terrain covers nothing and is a wall. (An even extent would
	# take 4 cells, by the parity rule in Lattice.covering.)
	var lattice: Lattice = Lattice.covering(Rect2(0.5, 0.5, 11.0, 11.0), 5.0)
	var mask: PackedByteArray = _mask(_terrain(), lattice)
	assert_eq(mask.size(), 9)
	assert_eq(mask[lattice.index_of(Vector2i(0, 0))], 1)
	var beyond: Lattice = Lattice.covering(Rect2(50.0, 50.0, 10.0, 10.0), 5.0)
	assert_eq(_mask(_terrain(), beyond), PackedByteArray([0, 0, 0, 0]))


func test_the_terrain_cells_counted_are_exactly_those_centred_in_the_cell() -> void:
	# Block the whole row z = 5, the first row of the southern lattice cells: 5 of 25 gone
	# there, nothing gone from the northern ones, which end at z = 4.
	var row: Array = []
	for x: int in TERRAIN:
		row.append(Vector2i(x, 5))
	assert_eq(_mask(_terrain(row)), PackedByteArray([1, 1, 1, 1]))
	# Block rows 5..7 as well: 15 of 25 gone from the southern cells.
	var rows: Array = []
	for x: int in TERRAIN:
		for z: int in range(5, 8):
			rows.append(Vector2i(x, z))
	assert_eq(_mask(_terrain(rows)), PackedByteArray([1, 1, 0, 0]))


# ─── THE EXPLORED GATE ──────────────────────────────────────────────────────


func test_the_explored_set_is_sampled_at_cell_centres_and_is_not_passability() -> void:
	var east_only: Callable = func(a_xz: Vector2) -> bool: return a_xz.x > 5.0
	assert_eq(BotFields.explored_mask_over(_lattice(), east_only), PackedByteArray([0, 1, 0, 1]))
	# The west is unexplored and still passable: a field sweeps it, an order never lands on it.
	assert_eq(_mask(_terrain()), PackedByteArray([1, 1, 1, 1]))


# ─── THE FIELDS ─────────────────────────────────────────────────────────────


## A 7 × 7 open lattice of pitch 5 at the origin.
func _open_lattice() -> Lattice:
	return Lattice.covering(Rect2(0.0, 0.0, 35.0, 35.0), 5.0)


func _open(a_cells: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(a_cells)
	mask.fill(1)
	return mask


func test_the_band_is_a_corridor_between_enemy_and_home_not_a_line() -> void:
	var lattice: Lattice = _open_lattice()
	var open: PackedByteArray = _open(49)
	var enemy: NavField = BotFields.sweep(lattice, open, [Vector2i(0, 3)], PackedInt32Array())
	var home: NavField = BotFields.sweep(lattice, open, [Vector2i(6, 3)], PackedInt32Array())
	var band: PackedByteArray = BotFields.band(enemy, home, BotFields.BAND_SLACK_COST)
	for x: int in 7:
		assert_eq(band[lattice.index_of(Vector2i(x, 3))], 1, "the straight row is on it")
	assert_eq(band[lattice.index_of(Vector2i(3, 2))], 1, "one hop aside is within the slack")
	assert_eq(band[lattice.index_of(Vector2i(3, 0))], 0, "the far corners are not")
	assert_eq(band[lattice.index_of(Vector2i(0, 6))], 0)


func test_the_band_narrows_to_a_gap_which_is_the_chokepoint_read() -> void:
	# A wall down x = 3 with one gap at z = 1: every approach crosses (3, 1).
	var lattice: Lattice = _open_lattice()
	var mask: PackedByteArray = _open(49)
	for z: int in 7:
		if z != 1:
			mask[lattice.index_of(Vector2i(3, z))] = 0
	var enemy: NavField = BotFields.sweep(lattice, mask, [Vector2i(0, 5)], PackedInt32Array())
	var home: NavField = BotFields.sweep(lattice, mask, [Vector2i(6, 5)], PackedInt32Array())
	var band: PackedByteArray = BotFields.band(enemy, home, BotFields.BAND_SLACK_COST)
	var on_wall_column: int = 0
	for z: int in 7:
		on_wall_column += band[lattice.index_of(Vector2i(3, z))]
	assert_eq(on_wall_column, 1, "only the gap")
	assert_eq(band[lattice.index_of(Vector2i(3, 1))], 1)
	assert_eq(band[lattice.index_of(Vector2i(0, 5))], 1, "the ends are on it")
	assert_eq(band[lattice.index_of(Vector2i(6, 5))], 1)


func test_an_unconnected_pair_has_no_band() -> void:
	var lattice: Lattice = _open_lattice()
	var mask: PackedByteArray = _open(49)
	for z: int in 7:
		mask[lattice.index_of(Vector2i(3, z))] = 0
	var enemy: NavField = BotFields.sweep(lattice, mask, [Vector2i(0, 3)], PackedInt32Array())
	var home: NavField = BotFields.sweep(lattice, mask, [Vector2i(6, 3)], PackedInt32Array())
	assert_eq(BotFields.band(enemy, home, BotFields.BAND_SLACK_COST), PackedByteArray())


func test_arrival_seconds_is_field_distance_over_speed_in_world_units() -> void:
	var lattice: Lattice = _open_lattice()
	var field: NavField = BotFields.sweep(lattice, _open(49), [Vector2i(0, 0)], PackedInt32Array())
	# Four orthogonal cells at pitch 5 is 20 world units; at 4 units per second, 5 seconds.
	assert_almost_eq(BotFields.arrival_seconds(field, Vector2i(4, 0), 5.0, 4.0), 5.0, 0.001)
	assert_eq(
		BotFields.arrival_seconds(field, Vector2i(4, 0), 5.0, 0.0), INF, "no speed, no arrival"
	)
	var walled: PackedByteArray = _open(49)
	walled[lattice.index_of(Vector2i(1, 0))] = 0
	walled[lattice.index_of(Vector2i(1, 1))] = 0
	walled[lattice.index_of(Vector2i(0, 1))] = 0
	var sealed: NavField = BotFields.sweep(lattice, walled, [Vector2i(0, 0)], PackedInt32Array())
	assert_eq(
		BotFields.arrival_seconds(sealed, Vector2i(4, 0), 5.0, 4.0),
		INF,
		"cut off: missing, not zero"
	)


func test_the_presence_penalty_covers_a_piece_s_reach_and_bends_the_enemy_field() -> void:
	var lattice: Lattice = _open_lattice()
	# One 1,000-energy piece standing at the centre of (3, 3), reaching one pitch.
	var stamps: Array = [{"xz": lattice.centre_of(Vector2i(3, 3)), "reach": 5.0, "value": 1000.0}]
	var penalty: PackedInt32Array = BotFields.presence_penalty_of(lattice, stamps, 0.03)
	assert_eq(penalty[lattice.index_of(Vector2i(3, 3))], 30)
	assert_eq(penalty[lattice.index_of(Vector2i(5, 3))], 30, "two pitches: reach plus the pitch")
	assert_eq(penalty[lattice.index_of(Vector2i(6, 3))], 0)
	assert_eq(penalty[lattice.index_of(Vector2i(5, 5))], 0, "outside the disc's corner")
	# The enemy's field from (0, 3) now prices the straight walk through the army above the
	# walk around it: the cell beyond the army reads further than a clear walk would.
	var clear: NavField = BotFields.sweep(lattice, _open(49), [Vector2i(0, 3)], PackedInt32Array())
	var bent: NavField = BotFields.sweep(lattice, _open(49), [Vector2i(0, 3)], penalty)
	assert_gt(bent.distance(Vector2i(6, 3)), clear.distance(Vector2i(6, 3)))
	assert_eq(
		clear.distance(Vector2i(6, 0)), bent.distance(Vector2i(6, 0)), "a clear corner is unchanged"
	)


# ─── THE REBUILD: BUDGETED, BEHIND A SNAPSHOT ───────────────────────────────


## A 9 × 9 open fixture (tests/_fixture_fields.gd): a walker at 2.5 on the west edge's middle,
## home on the east edge's middle.
func _fixture() -> FixtureFields:
	var fields: FixtureFields = FixtureFields.over_open(Rect2(0.0, 0.0, 45.0, 45.0))
	fields.add_walker(Vector2i(0, 4), 2.5)
	fields.home = [Vector2i(8, 4)]
	return fields


func test_a_budgeted_rebuild_settles_in_pieces_to_the_same_snapshot() -> void:
	var whole: FixtureFields = _fixture()
	whole.rebuild_now()
	var pieces: FixtureFields = _fixture()
	pieces.refresh()
	var calls: int = 0
	while pieces.is_pending():
		pieces.advance(40)  # ten cells a call
		calls += 1
	assert_gt(calls, 10, "the budget really split it")
	assert_eq(
		pieces.approach_band(NavAgentClass.Size.SMALL),
		whole.approach_band(NavAgentClass.Size.SMALL)
	)
	var home: Vector2 = whole.lattice.centre_of(Vector2i(8, 4))
	assert_almost_eq(pieces.arrival_seconds_at(home), whole.arrival_seconds_at(home), 0.001)
	assert_almost_eq(whole.arrival_seconds_at(home), 8.0 * 5.0 / 2.5, 0.001, "eight cells at 2.5")


func test_reads_serve_the_last_complete_snapshot_while_a_rebuild_is_pending() -> void:
	var fields: FixtureFields = _fixture()
	fields.rebuild_now()
	var home: Vector2 = fields.lattice.centre_of(Vector2i(8, 4))
	var before: float = fields.arrival_seconds_at(home)
	# The enemy moves next door; the rebuild is begun and barely advanced.
	fields.sources[0]["cell"] = Vector2i(6, 4)
	fields.refresh()
	fields.advance(4)
	assert_true(fields.is_pending())
	assert_almost_eq(fields.arrival_seconds_at(home), before, 0.001, "still the old picture")
	fields.advance(BotJob.UNLIMITED_WORK_UNITS)
	assert_false(fields.is_pending())
	assert_almost_eq(fields.arrival_seconds_at(home), 2.0 * 5.0 / 2.5, 0.001, "now the new one")


func test_the_first_read_completes_the_build_so_nothing_reads_nothing() -> void:
	var fields: FixtureFields = _fixture()
	assert_true(fields.has_enemy_sources())
	assert_false(fields.is_pending())
	assert_gt(fields.approach_band(NavAgentClass.Size.SMALL).size(), 0)


# ─── THE CONSUMERS' READS ───────────────────────────────────────────────────


func test_the_post_is_the_band_cell_nearest_home_beyond_the_standoff() -> void:
	var fields: FixtureFields = _fixture()
	var home: Vector2 = fields.lattice.centre_of(Vector2i(8, 4))
	var forward := Vector2(-1.0, 0.0)  # the enemy is west
	var post: Variant = fields.approach_post(home, forward, 10.0)
	assert_not_null(post)
	# Two cells west of home is the nearest band cell at least ten units out.
	assert_eq(post, fields.lattice.centre_of(Vector2i(6, 4)))
	# An unexplored band is no post: the gate every destination passes.
	var blind: FixtureFields = _fixture()
	blind.rebuild_now()
	blind._explored = PackedByteArray()
	blind._explored.resize(blind.lattice.cell_count())
	assert_null(blind.approach_post(home, forward, 10.0))
	# Nothing believed: no band, no post, and the caller keeps its bearing rule.
	var empty: FixtureFields = FixtureFields.over_open(Rect2(0.0, 0.0, 45.0, 45.0))
	empty.home = [Vector2i(8, 4)]
	assert_null(empty.approach_post(home, forward, 10.0))


func test_the_post_breaks_ties_in_the_bot_s_frame_so_mirrors_agree() -> void:
	# Two band cells at equal home distance, one each side of the axis: the one further
	# RIGHT of forward wins, and reflecting the whole situation reflects the choice.
	var lattice: Lattice = Lattice.covering(Rect2(0.0, 0.0, 35.0, 35.0), 5.0)
	var band := PackedByteArray()
	band.resize(49)
	var explored := PackedByteArray()
	explored.resize(49)
	explored.fill(1)
	band[lattice.index_of(Vector2i(2, 2))] = 1
	band[lattice.index_of(Vector2i(2, 4))] = 1
	var open := PackedByteArray()
	open.resize(49)
	open.fill(1)
	var home: NavField = BotFields.sweep(lattice, open, [Vector2i(6, 3)], PackedInt32Array())
	var anchor: Vector2 = lattice.centre_of(Vector2i(6, 3))
	var forward := Vector2(-1.0, 0.0)
	var post: Variant = BotFields.post_on_band(lattice, band, home, explored, anchor, forward, 1.0)
	# right of (-1, 0) is (0, -1): the cell with the smaller z.
	assert_eq(post, lattice.centre_of(Vector2i(2, 2)))
	var flipped: Variant = BotFields.post_on_band(
		lattice, band, home, explored, anchor, -forward, 1.0
	)
	assert_eq(flipped, lattice.centre_of(Vector2i(2, 4)), "turned about, the other side")


func test_arrival_between_two_points_reads_a_field_at_the_destination() -> void:
	var fields: FixtureFields = _fixture()
	var walker: Dictionary = {"speed": 2.0, "nav_class": NavAgentClass.Size.SMALL, "is_air": false}
	var from: Vector2 = fields.lattice.centre_of(Vector2i(1, 1))
	var to: Vector2 = fields.lattice.centre_of(Vector2i(1, 7))
	assert_almost_eq(fields.arrival_seconds_between(from, to, walker), 6.0 * 5.0 / 2.0, 0.001)
	var flyer: Dictionary = {"speed": 10.0, "nav_class": NavAgentClass.Size.SMALL, "is_air": true}
	assert_almost_eq(fields.arrival_seconds_between(from, to, flyer), 30.0 / 10.0, 0.001)
	assert_eq(fields.arrival_seconds_between(from, to, {}), INF, "what cannot move never arrives")


func test_a_destination_asked_about_last_snapshot_is_swept_inside_the_next_rebuild() -> void:
	var fields: FixtureFields = _fixture()
	var walker: Dictionary = {"speed": 2.0, "nav_class": NavAgentClass.Size.SMALL, "is_air": false}
	var from: Vector2 = fields.lattice.centre_of(Vector2i(1, 1))
	var to: Vector2 = fields.lattice.centre_of(Vector2i(1, 7))
	var key: String = BotFields.point_field_key(Vector2i(1, 7), NavAgentClass.Size.SMALL)
	var before: float = fields.arrival_seconds_between(from, to, walker)  # swept on the spot
	fields.refresh()
	while fields.is_pending():
		fields.advance(40)
	assert_true(fields._point_fields.has(key), "the next rebuild swept it within its budget")
	assert_almost_eq(fields.arrival_seconds_between(from, to, walker), before, 0.001)
	# That read asked again, so the next snapshot keeps it; the one after, unasked, lets it go.
	fields.rebuild_now()
	assert_true(fields._point_fields.has(key), "asked about last snapshot: kept warm")
	fields.rebuild_now()
	assert_false(fields._point_fields.has(key), "a destination nobody asks about is not kept warm")


func test_reach_coverage_is_the_share_of_the_band_a_gun_at_each_cell_covers() -> void:
	var lattice: Lattice = Lattice.covering(Rect2(0.0, 0.0, 35.0, 35.0), 5.0)
	var band := PackedByteArray()
	band.resize(49)
	for x: int in range(2, 5):  # three band cells along row 3: (2,3) (3,3) (4,3)
		band[lattice.index_of(Vector2i(x, 3))] = 1
	var coverage: PackedFloat32Array = BotFields.reach_coverage_of(lattice, band, 7.5)
	assert_almost_eq(coverage[lattice.index_of(Vector2i(3, 3))], 1.0, 0.001, "on the band's middle")
	assert_almost_eq(coverage[lattice.index_of(Vector2i(2, 3))], 2.0 / 3.0, 0.001, "at its end")
	assert_almost_eq(
		coverage[lattice.index_of(Vector2i(3, 4))], 1.0, 0.001, "one row off: all three"
	)
	assert_almost_eq(coverage[lattice.index_of(Vector2i(0, 0))], 0.0, 0.001, "a cliff-side corner")
	assert_eq(BotFields.reach_coverage_of(lattice, PackedByteArray(), 7.5), PackedFloat32Array())
