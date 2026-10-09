extends GutTest

## THE DISTANCE FIELD THE BOT'S TOPOLOGY IS BUILT FROM: `NavField`, a Dijkstra sweep over a
## lattice that returns one integer per cell and nothing else.
##
## Four things are worth a test each: the costs are octile (a diagonal is 14 to an orthogonal
## 10, and a diagonal never cuts a corner); a source may stand on a wall and several sources
## compete; a penalty bends the field around allied ground; and the field is MIRROR-EXACT —
## reflect the mask and the sources and every distance reflects to the bit, which is the
## property that keeps a world axis out of the bot's spatial reads
## (gdd/systems/ai/world-model/lattice-and-topology.md §Determinism).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavField.gd -gexit

const ORTHO: int = NavField.STEP_ORTHOGONAL
const DIAG: int = NavField.STEP_DIAGONAL


## A fully passable `a_width` × `a_depth` mask.
func _open(a_width: int, a_depth: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(a_width * a_depth)
	mask.fill(1)
	return mask


func _block(a_mask: PackedByteArray, a_width: int, a_cells: Array) -> void:
	for cell: Vector2i in a_cells:
		a_mask[cell.y * a_width + cell.x] = 0


func _field(a_width: int, a_depth: int, a_mask: PackedByteArray, a_sources: Array) -> NavField:
	var field: NavField = NavField.over(a_width, a_depth, a_mask)
	for source: Vector2i in a_sources:
		field.add_source(source)
	field.run()
	return field


# ─── COSTS ──────────────────────────────────────────────────────────────────


func test_open_ground_is_octile_distance() -> void:
	var field := _field(5, 5, _open(5, 5), [Vector2i(0, 0)])
	assert_eq(field.distance(Vector2i(0, 0)), 0)
	assert_eq(field.distance(Vector2i(1, 0)), ORTHO)
	assert_eq(field.distance(Vector2i(4, 0)), 4 * ORTHO)
	assert_eq(field.distance(Vector2i(4, 4)), 4 * DIAG)
	assert_eq(field.distance(Vector2i(4, 2)), 2 * DIAG + 2 * ORTHO)
	assert_eq(
		field.distance(Vector2i(3, 1)), NavField.octile_distance(Vector2i(0, 0), Vector2i(3, 1))
	)


func test_a_wall_with_one_gap_routes_through_the_gap() -> void:
	# A wall down x = 3, open only at z = 6: the walk from (0,0) to (6,0) goes down, through
	# the gap, and back up — and the corner rule forces the gap to be entered orthogonally.
	var mask := _open(7, 7)
	var wall: Array = []
	for z: int in range(0, 6):
		wall.append(Vector2i(3, z))
	_block(mask, 7, wall)
	var field := _field(7, 7, mask, [Vector2i(0, 0)])
	var gap := Vector2i(3, 6)
	var to_gap: int = 2 * DIAG + 4 * ORTHO + ORTHO  # (0,0)→(2,6) octile, then one step in
	assert_eq(field.distance(gap), to_gap)
	assert_eq(field.distance(Vector2i(6, 0)), to_gap + ORTHO + 2 * DIAG + 4 * ORTHO)
	# Every wall cell is impassable and reads no distance.
	for cell: Vector2i in wall:
		assert_eq(field.distance(cell), NavField.UNREACHABLE)


func test_a_diagonal_never_cuts_a_corner() -> void:
	# (1,0) and (0,1) blocked: (1,1) is reachable, but not by the diagonal from (0,0).
	var mask := _open(3, 3)
	_block(mask, 3, [Vector2i(1, 0), Vector2i(0, 1)])
	var field := _field(3, 3, mask, [Vector2i(0, 0)])
	assert_eq(field.distance(Vector2i(1, 1)), NavField.UNREACHABLE)
	# Only one of the two blocked: still refused — a crack between a wall and open ground.
	mask = _open(3, 3)
	_block(mask, 3, [Vector2i(1, 0)])
	field = _field(3, 3, mask, [Vector2i(0, 0)])
	assert_eq(field.distance(Vector2i(1, 1)), 2 * ORTHO)


func test_cut_off_ground_is_unreachable() -> void:
	var mask := _open(5, 1)
	_block(mask, 5, [Vector2i(2, 0)])
	var field := _field(5, 1, mask, [Vector2i(0, 0)])
	assert_eq(field.distance(Vector2i(1, 0)), ORTHO)
	assert_eq(field.distance(Vector2i(3, 0)), NavField.UNREACHABLE)
	assert_eq(field.distance(Vector2i(4, 0)), NavField.UNREACHABLE)
	assert_eq(field.distance(Vector2i(9, 9)), NavField.UNREACHABLE, "out of bounds")


func test_a_walled_destination_is_reached_from_beside_it() -> void:
	# A structure's cell is impassable; a walker arrives by standing against it.
	var mask := _open(5, 5)
	_block(mask, 5, [Vector2i(3, 3)])
	var field := _field(5, 5, mask, [Vector2i(0, 0)])
	assert_eq(field.distance(Vector2i(3, 3)), NavField.UNREACHABLE)
	assert_eq(field.distance_beside(Vector2i(3, 3)), 2 * DIAG, "beside it, at (2, 2)")
	assert_eq(field.distance_beside(Vector2i(0, 0)), 0, "a reached cell is its own answer")


# ─── SOURCES ────────────────────────────────────────────────────────────────


func test_the_nearest_source_wins_and_a_start_cost_counts() -> void:
	var field: NavField = NavField.over(5, 5, _open(5, 5))
	field.add_source(Vector2i(0, 0))
	field.add_source(Vector2i(4, 4), 3 * ORTHO)
	field.run()
	assert_eq(field.distance(Vector2i(4, 4)), 3 * ORTHO, "a source starts at its start cost")
	assert_eq(field.distance(Vector2i(4, 0)), 4 * ORTHO, "equidistant: either source")
	# (3,3): 14 + 30 from the far source, 42 from the near one — the near one wins by 2.
	assert_eq(field.distance(Vector2i(3, 3)), 3 * DIAG)


func test_a_source_on_a_wall_seeds_its_neighbours() -> void:
	# A believed enemy structure occupies impassable cells; the field still starts there.
	var mask := _open(5, 5)
	_block(mask, 5, [Vector2i(2, 2)])
	var field := _field(5, 5, mask, [Vector2i(2, 2)])
	assert_eq(field.distance(Vector2i(2, 2)), 0)
	assert_eq(field.distance(Vector2i(2, 3)), ORTHO)
	assert_eq(field.distance(Vector2i(0, 0)), 2 * DIAG)


func test_adding_a_source_after_a_run_recomputes() -> void:
	var field: NavField = NavField.over(5, 1, _open(5, 1))
	field.add_source(Vector2i(0, 0))
	field.run()
	assert_eq(field.distance(Vector2i(4, 0)), 4 * ORTHO)
	field.add_source(Vector2i(4, 0))
	assert_false(field.is_done())
	field.run()
	assert_eq(field.distance(Vector2i(4, 0)), 0)
	assert_eq(field.distance(Vector2i(2, 0)), 2 * ORTHO)


# ─── PENALTY ────────────────────────────────────────────────────────────────


## A 5×5 open lattice, a source at the west edge's middle, a penalty strip down x = 2.
func _penalised(a_penalty: int) -> NavField:
	var field: NavField = NavField.over(5, 5, _open(5, 5))
	var penalty := PackedInt32Array()
	penalty.resize(25)
	for z: int in range(1, 4):
		penalty[z * 5 + 2] = a_penalty
	field.set_penalty(penalty)
	field.add_source(Vector2i(0, 2))
	field.run()
	return field


func test_a_heavy_penalty_bends_the_field_around_the_strip() -> void:
	# Straight through costs 40 + penalty; around the strip's end costs four diagonals, 56.
	assert_eq(_penalised(100).distance(Vector2i(4, 2)), 4 * DIAG)
	assert_eq(_penalised(100).distance(Vector2i(2, 2)), 2 * ORTHO + 100, "entering it is paid")


func test_a_light_penalty_is_paid_rather_than_walked_around() -> void:
	assert_eq(_penalised(5).distance(Vector2i(4, 2)), 4 * ORTHO + 5)


# ─── RESUMABLE ──────────────────────────────────────────────────────────────


func test_a_budgeted_run_settles_in_pieces_to_the_same_field() -> void:
	var mask := _open(6, 6)
	_block(mask, 6, [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)])
	var whole := _field(6, 6, mask, [Vector2i(0, 0)])
	var pieces: NavField = NavField.over(6, 6, mask)
	pieces.add_source(Vector2i(0, 0))
	var runs: int = 0
	while not pieces.run(3):
		runs += 1
	assert_gt(runs, 3, "the budget actually split the sweep")
	assert_true(pieces.is_done())
	assert_eq(pieces.distances(), whole.distances())


# ─── MIRROR-EXACT ───────────────────────────────────────────────────────────


## A seeded random mask with a few sources, and its reflection across x.
func _mirror_pair(a_seed: int, a_width: int, a_depth: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = a_seed
	var mask := _open(a_width, a_depth)
	var mirrored := _open(a_width, a_depth)
	var sources: Array = []
	var mirrored_sources: Array = []
	for z: int in a_depth:
		for x: int in a_width:
			if rng.randf() < 0.3:
				mask[z * a_width + x] = 0
				mirrored[z * a_width + (a_width - 1 - x)] = 0
	for _i: int in 3:
		var source := Vector2i(rng.randi_range(0, a_width - 1), rng.randi_range(0, a_depth - 1))
		sources.append(source)
		mirrored_sources.append(Vector2i(a_width - 1 - source.x, source.y))
	var penalty := PackedInt32Array()
	var mirrored_penalty := PackedInt32Array()
	penalty.resize(a_width * a_depth)
	mirrored_penalty.resize(a_width * a_depth)
	for z: int in a_depth:
		for x: int in a_width:
			var p: int = rng.randi_range(0, 30)
			penalty[z * a_width + x] = p
			mirrored_penalty[z * a_width + (a_width - 1 - x)] = p
	var field: NavField = NavField.over(a_width, a_depth, mask)
	var mirror: NavField = NavField.over(a_width, a_depth, mirrored)
	field.set_penalty(penalty)
	mirror.set_penalty(mirrored_penalty)
	for i: int in sources.size():
		field.add_source(sources[i], i * ORTHO)
		mirror.add_source(mirrored_sources[i], i * ORTHO)
	field.run()
	mirror.run()
	return [field, mirror]


func test_a_reflected_lattice_gives_a_reflected_field_to_the_bit() -> void:
	for seed: int in [1, 2, 3, 4, 5]:
		var pair: Array = _mirror_pair(seed, 13, 9)
		var field: NavField = pair[0]
		var mirror: NavField = pair[1]
		var reachable: int = 0
		for z: int in 9:
			for x: int in 13:
				var d: int = field.distance(Vector2i(x, z))
				assert_eq(
					mirror.distance(Vector2i(12 - x, z)), d, "seed %d cell (%d,%d)" % [seed, x, z]
				)
				if d != NavField.UNREACHABLE:
					reachable += 1
		assert_gt(reachable, 20, "seed %d: the fixture has ground worth comparing" % seed)
