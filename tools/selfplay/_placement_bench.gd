extends Node3D

## WHAT THE PLACEMENT CONSTRAINTS COST, measured rather than argued.
##
##   godot --headless --path . tools/selfplay/_placement_bench.tscn
##
## Grid is 159 x 159 cells — the size of `skirmish.tscn` (160 x 160 height corners) — with a
## plausible obstacle field, because the quantity that matters is how the cost scales with
## the map rather than with a toy fixture. The old flood fill is O(map) twice per candidate;
## the local check is O(the footprint's perimeter) and does not see the map at all.

const SIDE: int = 160  # height corners -> 159 x 159 cells
const SAMPLES: int = 400


func _ready() -> void:
	var grid: TerrainGrid = _make_grid()
	print(
		(
			"cells: %d, passable: %d, regions: %d"
			% [
				grid.grid_width() * grid.grid_depth(),
				grid.get_all_passable_cells().size(),
				grid.component_count()
			]
		)
	)

	var spots: Array = _sample_footprints(grid, SAMPLES)
	print("footprints sampled: %d (2x2, on passable ground)" % spots.size())

	_time(
		"TerrainGrid.placement_preserves_connectivity  (OLD, 2 full flood fills)",
		spots,
		func(f): return grid.placement_preserves_connectivity(f)
	)
	_time(
		"NavPlacement.preserves_connectivity           (NEW, local)",
		spots,
		func(f): return NavPlacement.preserves_connectivity(grid, f)
	)
	_time(
		"NavPlacement.has_navmesh_side                 (NEW, 4 sides)",
		spots,
		func(f): return NavPlacement.has_navmesh_side(grid, f, grid.largest_component())
	)
	_time(
		"NavPlacement.accepts                          (both rules)",
		spots,
		func(f): return NavPlacement.accepts(grid, f, true, grid.largest_component())
	)

	# The one cost the labels ADD, against the fields the navmesh already pays for. Both are
	# per cells_changed rather than per query, and the labels have their own dirty flag so a
	# navmesh bake that never asks for them does not pay.
	var relabel_usec: int = 0
	var fields_usec: int = 0
	for i: int in 20:
		grid.set_blocked(Vector2i(1, 1 + i), true)
		var start: int = Time.get_ticks_usec()
		grid.component_at(Vector2i(80, 80))  # forces the relabel only
		relabel_usec += Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		grid.clearance_at(Vector2i(80, 80))  # forces clearance + distance only
		fields_usec += Time.get_ticks_usec() - start
	print(
		(
			"\nper cells_changed: region relabel %.2f ms   (clearance+distance, pre-existing: %.2f ms)"
			% [relabel_usec / 20.0 / 1000.0, fields_usec / 20.0 / 1000.0]
		)
	)

	# What ONE placement decision costs: the bot scores the whole disc, then validates in score
	# order, so the navigation rules run on the chosen candidate and its near-misses only.
	var decision_usec: int = 0
	for footprint: Array in a_first(spots, 50):
		grid.set_blocked(Vector2i(3, 3), grid.is_passable(Vector2i(3, 3)))  # a build happened
		var start: int = Time.get_ticks_usec()
		for _try: int in 3:
			NavPlacement.accepts(grid, footprint, true, grid.largest_component())
		decision_usec += Time.get_ticks_usec() - start
	print(
		(
			"one placement decision (relabel + 3 candidates validated): %.2f ms"
			% (decision_usec / 50.0 / 1000.0)
		)
	)
	_bench_whole_decision(grid)
	get_tree().quit()


func a_first(a_array: Array, a_n: int) -> Array:
	return a_array.slice(0, a_n)


func _time(a_label: String, a_spots: Array, a_call: Callable) -> void:
	var accepted: int = 0
	var start: int = Time.get_ticks_usec()
	for footprint: Array in a_spots:
		if a_call.call(footprint):
			accepted += 1
	var total: int = Time.get_ticks_usec() - start
	print(
		(
			"%-58s %8.1f us/call   (%d/%d accepted)"
			% [a_label, float(total) / float(a_spots.size()), accepted, a_spots.size()]
		)
	)


func _make_grid() -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = SIDE
	shape.map_depth = SIDE
	var data := PackedFloat32Array()
	data.resize(SIDE * SIDE)
	shape.map_data = data
	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = StaticBody3D.new()
	add_child(grid)  # _ready sizes the state, marks steep

	# An obstacle field with corridors in it: 60 blobs plus two long walls with gates, which
	# is the shape that makes the connectivity question non-trivial.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910
	var gw: int = grid.grid_width()
	for _i: int in 60:
		var cx: int = rng.randi_range(4, gw - 8)
		var cz: int = rng.randi_range(4, gw - 8)
		var w: int = rng.randi_range(2, 6)
		var d: int = rng.randi_range(2, 6)
		for x: int in w:
			for z: int in d:
				grid.set_blocked(Vector2i(cx + x, cz + z), true)
	for z: int in gw:
		if z < 60 or z > 66:
			grid.set_blocked(Vector2i(50, z), true)
		if z < 90 or z > 96:
			grid.set_blocked(Vector2i(110, z), true)
	return grid


## 2x2 footprints on passable ground, spread over the map.
func _sample_footprints(a_grid: TerrainGrid, a_count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gw: int = a_grid.grid_width()
	var out: Array = []
	while out.size() < a_count:
		var x: int = rng.randi_range(1, gw - 3)
		var z: int = rng.randi_range(1, gw - 3)
		var footprint: Array = [
			Vector2i(x, z),
			Vector2i(x + 1, z),
			Vector2i(x, z + 1),
			Vector2i(x + 1, z + 1),
		]
		var ok: bool = true
		for cell: Vector2i in footprint:
			if not a_grid.is_passable(cell):
				ok = false
		if ok:
			out.append(footprint)
	return out


# ─── WHAT ONE WHOLE PLACEMENT DECISION COSTS ────────────────────────────────
# The scoring pass is O(the candidate disc) and runs on every decision; the navigation rules
# run only on the candidates the score actually offers. This times the real entry point.


class BenchMap:
	extends Map
	var grid: TerrainGrid

	func _ready() -> void:
		height_map = grid.height_map
		terrain_grid = grid
		cell_grid = []
		for _x: int in grid.grid_width():
			var column: Array = []
			for _z: int in grid.grid_depth():
				column.append(null)
			cell_grid.append(column)


class BenchBot:
	extends Bot
	var base: Vector3 = Vector3.ZERO

	func base_centroid() -> Vector3:
		return base

	func get_units() -> Array:
		return []

	func buildable_production_structure_types() -> Array:
		return [&"bench_production"]

	func nearest_believed_enemy_structure_position(_a_accept: Variant = null) -> Variant:
		return Vector3(40.0, 0.0, 40.0)

	func nearest_believed_enemy_unit_position(
		_a_from: Vector3, _a_accept: Variant = null
	) -> Variant:
		return null


class BenchEconomy:
	extends BotEconomy

	func _dims_for_type(_a_type: StringName) -> Vector2i:
		return Vector2i(2, 2)


func _bench_whole_decision(a_grid: TerrainGrid) -> void:
	var map := BenchMap.new()
	map.grid = a_grid
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	map.add_child(region)
	add_child(map)

	var bot := BenchBot.new()
	bot.map = map
	var economy := BenchEconomy.new(bot, null)

	# Three regimes, because which one the game is in matters more than the average:
	#   cold   — the grid changed and NOTHING has rebuilt anything yet
	#   baked  — the grid changed and the navmesh has already rebuilt (NavManager rebuilds on
	#            cells_changed, and that rebuild is what pays for the clearance/distance
	#            fields), so the decision pays only for the region labels. THE REAL CASE.
	#   warm   — nothing has changed since the last decision
	var cold: int = 0
	var baked: int = 0
	var warm: int = 0
	var found: int = 0
	for i: int in 40:
		bot.base = map.grid_to_world(Vector2i(20 + i * 3, 20 + i * 2))

		a_grid.set_blocked(Vector2i(3, 3), a_grid.is_passable(Vector2i(3, 3)))  # a build happened
		var start: int = Time.get_ticks_usec()
		if economy._find_build_spot(&"bench_production") != null:
			found += 1
		cold += Time.get_ticks_usec() - start

		a_grid.set_blocked(Vector2i(3, 3), a_grid.is_passable(Vector2i(3, 3)))
		a_grid.clearance_at(Vector2i(80, 80))  # stand in for the navmesh rebuild
		start = Time.get_ticks_usec()
		economy._find_build_spot(&"bench_production")
		baked += Time.get_ticks_usec() - start

		start = Time.get_ticks_usec()
		economy._find_build_spot(&"bench_production")
		warm += Time.get_ticks_usec() - start
	print(
		(
			(
				"BotEconomy._find_build_spot: cold %.2f ms | after a navmesh bake %.2f "
				+ "ms | unchanged %.2f ms  (%d/40 found a spot)"
			)
			% [cold / 40.0 / 1000.0, baked / 40.0 / 1000.0, warm / 40.0 / 1000.0, found]
		)
	)
	bot.free()
