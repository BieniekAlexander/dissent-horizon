@tool
class_name MapDecorationPlanner
extends RefCounted

## Map generation pass 7, visual facets: derive a map's cosmetic layer — ground paint, trails
## between settlements, doodads, and the sites of later set dressing — from the map alone.
## A pure function of MapDecorationInput; the rules and their reasons are
## gdd/systems/terrain-and-navigation/visual-facets.md.
##
## Every number below is a placeholder density or radius, tuned by eye on generated maps
## (TODO: none is tuned against real art; they move when the visual language does).

#region Constants
## Ground within this many cells of a settlement is meadow (a clearing around a town).
const MEADOW_RADIUS_CELLS: float = 10.0
## Passable ground within this many cells of a cliff or barrier carries scree.
const SCREE_RADIUS_CELLS: float = 2.5
## Dry ground within this many cells of water is shore.
const SHORE_RADIUS_CELLS: float = 2.0
## Neutral buildings and shelters closer than this join one settlement, which trails connect.
const SETTLEMENT_LINK_CELLS: float = 14.0
## A settlement pair farther apart than this gets no direct trail; the tree routes around it.
const TRAIL_MAX_LENGTH_CELLS: float = 120.0
## Trail cost multipliers: wading, and how much the noise field bends a trail off straight.
const TRAIL_SHALLOW_COST: float = 6.0
const TRAIL_WANDER: float = 0.8
## Bounds A*'s work per trail, so a pathological map costs a missing trail, not a stall.
const TRAIL_MAX_EXPANSIONS: int = 60000
## How far from a fixture's footprint nothing is scattered (structures must read cleanly).
const FIXTURE_MARGIN_CELLS: float = 1.5
## Feature size of the noise that groups trees into stands and meadows into patches.
const FOREST_NOISE_CELLS: float = 9.0
const PATCH_NOISE_CELLS: float = 23.0
## Chances per eligible cell.
const TALL_PER_IMPASSABLE_CELL: float = 0.5
const REED_CHANCE: float = 0.35
const SCREE_ROCK_CHANCE: float = 0.08
const EDGE_BUSH_CHANCE: float = 0.10
const FLOWER_CHANCE: float = 0.05
const GRASS_TUFT_CHANCE: float = 0.04
const STUMP_CHANCE: float = 0.008
## A water cell this far above ground within WATERFALL_REACH_CELLS is a waterfall's lip.
const WATERFALL_DROP: float = 1.0
const WATERFALL_REACH_CELLS: int = 3
## Steep cells at least this deep inside an impassable region are mountain core.
const MOUNTAIN_CORE_CELLS: float = 3.0

## Cell flags.
const _IN_PLAY: int = 1
const _STEEP: int = 2
const _DEEP: int = 4
const _SHALLOW: int = 8
const _FIXTURE: int = 16
const _TRAIL: int = 32
const _SETTLEMENT: int = 64
const _WET: int = _DEEP | _SHALLOW

const _CARDINAL: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _AROUND: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
#endregion


#region Public API
static func plan(input: MapDecorationInput) -> MapDecoration:
	var result := MapDecoration.new()
	if input == null or input.terrain == null or input.terrain.grid_width() <= 0:
		return result
	var grid := _Grid.new(input)
	var settle_dist: PackedFloat32Array = grid.distance_to(_SETTLEMENT)
	var steep_dist: PackedFloat32Array = grid.distance_to(_STEEP)
	var water_dist: PackedFloat32Array = grid.distance_to(_WET)
	var fixture_dist: PackedFloat32Array = grid.distance_to(_FIXTURE)
	result.trails = _route_trails(grid, input)
	result.ground_overlay = _paint(grid, settle_dist, steep_dist, water_dist)
	result.doodads = _scatter(grid, input.rng_seed, settle_dist, steep_dist, fixture_dist)
	result.facets = _detect_facets(grid)
	return result


## Whether a doodad of `kind` may stand on a cell with `flags`. Tall props only where no unit
## walks (DoodadLibrary.LOW_MAX_HEIGHT); nothing on fixtures, trails or deep water.
static func is_admissible(kind: DoodadLibrary.Kind, flags: int) -> bool:
	if flags & _IN_PLAY == 0 or flags & (_FIXTURE | _TRAIL | _DEEP) != 0:
		return false
	return flags & _STEEP != 0 or DoodadLibrary.is_low(kind)
#endregion


#region Trails
## Settlements joined by a minimum spanning tree over straight-line distance, each edge routed
## over walkable ground. Starts are never endpoints: a trail converging on empty ground would
## point at a hidden spawn.
static func _route_trails(grid: _Grid, input: MapDecorationInput) -> Array[PackedVector2Array]:
	var nodes: Array[Vector2] = _settlements(input)
	var trails: Array[PackedVector2Array] = []
	for edge: Vector2i in _spanning_tree(nodes):
		var from: Vector2i = grid.nearest_open_cell(nodes[edge.x])
		var to: Vector2i = grid.nearest_open_cell(nodes[edge.y])
		if from.x < 0 or to.x < 0:
			continue
		var path: PackedVector2Array = grid.route(from, to)
		if path.is_empty():
			continue
		grid.stamp_trail(path)
		trails.append(path)
	return trails


## Centroids of settlements: neutral buildings and shelters, grouped by SETTLEMENT_LINK_CELLS.
static func _settlements(input: MapDecorationInput) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for fixture: Dictionary in input.fixtures:
		var kind: MapDecorationInput.FixtureKind = fixture.kind
		if kind != MapDecorationInput.FixtureKind.BUILDING \
				and kind != MapDecorationInput.FixtureKind.SHELTER:
			continue
		var sum := Vector2.ZERO
		for cell: Vector2i in fixture.cells:
			sum += Vector2(cell) + Vector2(0.5, 0.5)
		points.append(sum / maxf(1.0, float(fixture.cells.size())))
	var group: PackedInt32Array = PackedInt32Array(range(points.size()))
	for i: int in points.size():
		for j: int in range(i + 1, points.size()):
			if points[i].distance_to(points[j]) <= SETTLEMENT_LINK_CELLS:
				_union(group, i, j)
	var sums: Dictionary = {}
	for i: int in points.size():
		var root: int = _find(group, i)
		var acc: Array = sums.get(root, [Vector2.ZERO, 0])
		sums[root] = [acc[0] + points[i], acc[1] + 1]
	var centroids: Array[Vector2] = []
	for root: int in sums:
		centroids.append(sums[root][0] / float(sums[root][1]))
	return centroids


static func _find(group: PackedInt32Array, i: int) -> int:
	while group[i] != i:
		group[i] = group[group[i]]
		i = group[i]
	return i


static func _union(group: PackedInt32Array, a: int, b: int) -> void:
	group[_find(group, a)] = _find(group, b)


## Prim's tree over the points, as index pairs; edges over TRAIL_MAX_LENGTH_CELLS are dropped
## (the forest that leaves is the point: far-apart towns need not be linked).
static func _spanning_tree(points: Array[Vector2]) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	if points.size() < 2:
		return edges
	var in_tree: PackedByteArray = PackedByteArray()
	in_tree.resize(points.size())
	in_tree[0] = 1
	for _added: int in points.size() - 1:
		var best := Vector2i(-1, -1)
		var best_length: float = INF
		for i: int in points.size():
			if in_tree[i] == 0:
				continue
			for j: int in points.size():
				if in_tree[j] == 0 and points[i].distance_to(points[j]) < best_length:
					best_length = points[i].distance_to(points[j])
					best = Vector2i(i, j)
		in_tree[best.y] = 1
		if best_length <= TRAIL_MAX_LENGTH_CELLS:
			edges.append(best)
	return edges
#endregion


#region Ground paint
static func _paint(
	grid: _Grid, settle_dist: PackedFloat32Array, steep_dist: PackedFloat32Array,
	water_dist: PackedFloat32Array
) -> Image:
	var patches: FastNoiseLite = _noise(grid.rng_seed, PATCH_NOISE_CELLS)
	var data := PackedByteArray()
	data.resize(grid.size * 4)
	for i: int in grid.size:
		var flags: int = grid.flags[i]
		if flags & _IN_PLAY == 0:
			continue
		var cell := Vector2i(i % grid.width, i / grid.width)
		var land: bool = flags & (_STEEP | _WET) == 0
		var patch: float = patches.get_noise_2dv(Vector2(cell)) * 0.5 + 0.5
		var meadow: float = 0.0
		var scree: float = 0.0
		var shore: float = 0.0
		if land:
			meadow = clampf(1.0 - settle_dist[i] / MEADOW_RADIUS_CELLS, 0.0, 1.0) \
				* (0.5 + patch)
			meadow = maxf(meadow, clampf((patch - 0.62) * 3.0, 0.0, 0.8))
			scree = clampf(1.0 - (steep_dist[i] - 1.0) / SCREE_RADIUS_CELLS, 0.0, 1.0)
			shore = clampf(1.0 - (water_dist[i] - 1.0) / SHORE_RADIUS_CELLS, 0.0, 1.0)
		elif flags & _SHALLOW != 0:
			shore = 1.0
		data[i * 4] = int(clampf(meadow, 0.0, 1.0) * 255.0)
		data[i * 4 + 1] = int(grid.trail[i] * 255.0)
		data[i * 4 + 2] = int(scree * 255.0)
		data[i * 4 + 3] = int(shore * 255.0)
	return Image.create_from_data(grid.width, grid.depth, false, Image.FORMAT_RGBA8, data)
#endregion


#region Doodads
static func _scatter(
	grid: _Grid, rng_seed: int, settle_dist: PackedFloat32Array,
	steep_dist: PackedFloat32Array, fixture_dist: PackedFloat32Array
) -> Array[DoodadPlacement]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var forest: FastNoiseLite = _noise(rng_seed + 1, FOREST_NOISE_CELLS)
	var placed: Array[DoodadPlacement] = []
	for i: int in grid.size:
		var flags: int = grid.flags[i]
		if flags & _IN_PLAY == 0 or fixture_dist[i] <= FIXTURE_MARGIN_CELLS:
			continue
		var cell := Vector2i(i % grid.width, i / grid.width)
		var kind: int = _pick_kind(grid, cell, flags, rng, forest, settle_dist[i], steep_dist[i])
		if kind < 0 or not is_admissible(kind as DoodadLibrary.Kind, flags):
			continue
		var at := Vector2(cell) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))
		placed.append(DoodadPlacement.of(kind as DoodadLibrary.Kind,
			Vector3(at.x, grid.height_at(at), at.y), rng.randf() * TAU,
			rng.randf_range(0.8, 1.25)))
	return placed


## The doodad kind for one cell, or -1 for none. Draws from `rng` in a fixed order per branch,
## so the result depends only on the map.
static func _pick_kind(
	grid: _Grid, cell: Vector2i, flags: int, rng: RandomNumberGenerator, forest: FastNoiseLite,
	settle: float, steep: float
) -> int:
	var roll: float = rng.randf()
	if flags & _STEEP != 0:
		var stand: float = forest.get_noise_2dv(Vector2(cell))
		if roll >= TALL_PER_IMPASSABLE_CELL * (0.6 + stand):
			return -1
		var pick: float = rng.randf()
		if stand > -0.1:
			return DoodadLibrary.Kind.CONIFER if pick < 0.6 \
				else (DoodadLibrary.Kind.BROADLEAF if pick < 0.9 else DoodadLibrary.Kind.DEAD_TREE)
		return DoodadLibrary.Kind.BOULDER if pick < 0.65 else DoodadLibrary.Kind.ROCK_PILE
	if flags & _SHALLOW != 0:
		return DoodadLibrary.Kind.REEDS if roll < REED_CHANCE and grid.touches(cell, 0) else -1
	if steep <= 1.5 and roll < SCREE_ROCK_CHANCE:
		return DoodadLibrary.Kind.ROCK_PILE
	if steep <= 3.0 and roll < SCREE_ROCK_CHANCE + EDGE_BUSH_CHANCE:
		return DoodadLibrary.Kind.BUSH
	if settle < MEADOW_RADIUS_CELLS and roll < FLOWER_CHANCE:
		return DoodadLibrary.Kind.FLOWERS
	if settle < 2.0 * MEADOW_RADIUS_CELLS and roll > 1.0 - STUMP_CHANCE:
		return DoodadLibrary.Kind.STUMP
	if roll < GRASS_TUFT_CHANCE:
		return DoodadLibrary.Kind.GRASS_TUFT
	return -1
#endregion


#region Facets
static func _detect_facets(grid: _Grid) -> Dictionary:
	var core_dist: PackedFloat32Array = grid.distance_to_clear(_STEEP)
	var facets: Dictionary = {}
	for facet: int in MapDecoration.Facet.values():
		facets[facet] = [] as Array[Vector2i]
	for i: int in grid.size:
		var flags: int = grid.flags[i]
		if flags & _IN_PLAY == 0:
			continue
		var cell := Vector2i(i % grid.width, i / grid.width)
		if flags & _STEEP != 0:
			if grid.touches(cell, _STEEP | _WET, true):
				facets[MapDecoration.Facet.CLIFF_FACE].append(cell)
			if core_dist[i] >= MOUNTAIN_CORE_CELLS:
				facets[MapDecoration.Facet.MOUNTAIN].append(cell)
		elif flags & _WET != 0:
			if grid.is_waterfall_lip(cell):
				facets[MapDecoration.Facet.WATERFALL].append(cell)
		else:
			if grid.touches(cell, _WET, false, true):
				facets[MapDecoration.Facet.SHORE].append(cell)
			if grid.is_ramp(cell):
				facets[MapDecoration.Facet.RAMP].append(cell)
	return facets
#endregion


static func _noise(rng_seed: int, feature_cells: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = rng_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / feature_cells
	return noise


## The cell grid pass 7 works on: one flag byte per cell plus the heights, and the per-cell
## queries the passes share. Mutable only through stamp_trail — the one pass whose output
## (trail cells) later passes read.
class _Grid:
	var width: int = 0
	var depth: int = 0
	var size: int = 0
	var rng_seed: int = 0
	var flags := PackedByteArray()
	var trail := PackedFloat32Array()
	var water_level := PackedFloat32Array()
	var _terrain: TerrainData = null
	var _wander: FastNoiseLite = null

	func _init(input: MapDecorationInput) -> void:
		_terrain = input.terrain
		width = _terrain.grid_width()
		depth = _terrain.grid_depth()
		size = width * depth
		rng_seed = input.rng_seed
		flags.resize(size)
		trail.resize(size)
		water_level.resize(size)
		_wander = MapDecorationPlanner._noise(rng_seed + 2, 7.0)
		for i: int in size:
			var cell := Vector2i(i % width, i / width)
			if not _terrain.is_cell_in_play(cell):
				continue
			flags[i] = _IN_PLAY
			if _terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF:
				flags[i] |= _STEEP
		for water: Dictionary in input.waters:
			var basin: WaterBasin = WaterBasin.fill(_terrain, water.seed_cell, water.level)
			for cell: Vector2i in basin.covered_cells():
				var i: int = index(cell)
				flags[i] |= _DEEP if basin.is_deep(cell) else _SHALLOW
				water_level[i] = basin.level
		for fixture: Dictionary in input.fixtures:
			var kind: MapDecorationInput.FixtureKind = fixture.kind
			var settled: bool = kind == MapDecorationInput.FixtureKind.BUILDING \
				or kind == MapDecorationInput.FixtureKind.SHELTER
			for cell: Vector2i in fixture.cells:
				if _terrain.is_cell_in_bounds(cell):
					flags[index(cell)] |= _FIXTURE | (_SETTLEMENT if settled else 0)

	func index(cell: Vector2i) -> int:
		return cell.y * width + cell.x

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth

	## Whether any in-play neighbour has one of `mask`'s flags — or, with `negate`, lacks them
	## all. A `mask` of 0 asks instead whether any neighbour is dry ground.
	func touches(cell: Vector2i, mask: int, negate: bool = false, cardinal: bool = true) -> bool:
		var steps: Array[Vector2i] = MapDecorationPlanner._CARDINAL if cardinal \
			else MapDecorationPlanner._AROUND
		for step: Vector2i in steps:
			var n: Vector2i = cell + step
			if not in_bounds(n) or flags[index(n)] & _IN_PLAY == 0:
				continue
			var f: int = flags[index(n)]
			if mask == 0:
				if f & _WET == 0:
					return true
			elif negate:
				if f & mask == 0:
					return true
			elif f & mask != 0:
				return true
		return false

	## Ground height at a continuous cell-space point, bilinear over the corners.
	func height_at(point: Vector2) -> float:
		var cx: int = clampi(floori(point.x), 0, width - 1)
		var cz: int = clampi(floori(point.y), 0, depth - 1)
		var fx: float = point.x - cx
		var fz: float = point.y - cz
		var c := Vector2i(cx, cz)
		return lerpf(
			lerpf(_terrain.corner_height(c), _terrain.corner_height(c + Vector2i(1, 0)), fx),
			lerpf(_terrain.corner_height(c + Vector2i(0, 1)),
				_terrain.corner_height(c + Vector2i(1, 1)), fx), fz)

	## Chamfer distance (in cells) from every cell to the nearest cell carrying `mask`.
	func distance_to(mask: int) -> PackedFloat32Array:
		var seeds := PackedByteArray()
		seeds.resize(size)
		for i: int in size:
			seeds[i] = 1 if flags[i] & mask != 0 else 0
		return _chamfer(seeds)

	## Distance from every cell to the nearest in-play cell WITHOUT `mask`: depth inside a region.
	func distance_to_clear(mask: int) -> PackedFloat32Array:
		var seeds := PackedByteArray()
		seeds.resize(size)
		for i: int in size:
			seeds[i] = 1 if flags[i] & _IN_PLAY != 0 and flags[i] & mask == 0 else 0
		return _chamfer(seeds)

	## Two-pass 3-4 chamfer transform; a forward and a backward sweep over the whole grid.
	func _chamfer(seeds: PackedByteArray) -> PackedFloat32Array:
		var far: float = float(width + depth) * 2.0
		var d := PackedFloat32Array()
		d.resize(size)
		for i: int in size:
			d[i] = 0.0 if seeds[i] != 0 else far
		var diag: float = sqrt(2.0)
		for z: int in depth:
			for x: int in width:
				var i: int = z * width + x
				if x > 0: d[i] = minf(d[i], d[i - 1] + 1.0)
				if z > 0:
					d[i] = minf(d[i], d[i - width] + 1.0)
					if x > 0: d[i] = minf(d[i], d[i - width - 1] + diag)
					if x < width - 1: d[i] = minf(d[i], d[i - width + 1] + diag)
		for z: int in range(depth - 1, -1, -1):
			for x: int in range(width - 1, -1, -1):
				var i: int = z * width + x
				if x < width - 1: d[i] = minf(d[i], d[i + 1] + 1.0)
				if z < depth - 1:
					d[i] = minf(d[i], d[i + width] + 1.0)
					if x < width - 1: d[i] = minf(d[i], d[i + width + 1] + diag)
					if x > 0: d[i] = minf(d[i], d[i + width - 1] + diag)
		return d

	func is_walkable(i: int) -> bool:
		return flags[i] & _IN_PLAY != 0 and flags[i] & (_STEEP | _DEEP | _FIXTURE) == 0

	## The walkable cell nearest a point, searching outward ring by ring; (-1, -1) if none
	## within twice the settlement link distance.
	func nearest_open_cell(point: Vector2) -> Vector2i:
		var center := Vector2i(point.floor())
		var reach: int = int(MapDecorationPlanner.SETTLEMENT_LINK_CELLS * 2.0)
		for radius: int in reach:
			var best := Vector2i(-1, -1)
			var best_d: float = INF
			for dz: int in range(-radius, radius + 1):
				for dx: int in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dz)) != radius:
						continue
					var cell: Vector2i = center + Vector2i(dx, dz)
					if in_bounds(cell) and is_walkable(index(cell)):
						var dist: float = Vector2(cell).distance_to(point)
						if dist < best_d:
							best_d = dist
							best = cell
			if best.x >= 0:
				return best
		return Vector2i(-1, -1)

	## A* over walkable cells, 8-connected without corner cutting. Empty when unreachable or
	## past TRAIL_MAX_EXPANSIONS.
	func route(from: Vector2i, to: Vector2i) -> PackedVector2Array:
		var g := PackedFloat32Array()
		g.resize(size)
		g.fill(INF)
		var parent := PackedInt32Array()
		parent.resize(size)
		parent.fill(-1)
		var heap := _Heap.new()
		var start: int = index(from)
		var goal: int = index(to)
		g[start] = 0.0
		heap.push(start, 0.0)
		var expansions: int = 0
		while not heap.is_empty() and expansions < MapDecorationPlanner.TRAIL_MAX_EXPANSIONS:
			var current: int = heap.pop()
			if current == goal:
				return _walk_back(parent, goal)
			expansions += 1
			var cell := Vector2i(current % width, current / width)
			for step: Vector2i in MapDecorationPlanner._AROUND:
				var n: Vector2i = cell + step
				if not in_bounds(n) or not is_walkable(index(n)):
					continue
				if step.x != 0 and step.y != 0 and not (
						is_walkable(index(Vector2i(n.x, cell.y)))
						and is_walkable(index(Vector2i(cell.x, n.y)))):
					continue
				var ni: int = index(n)
				var cost: float = g[current] + _step_cost(n, step)
				if cost < g[ni]:
					g[ni] = cost
					parent[ni] = current
					heap.push(ni, cost + Vector2(n).distance_to(Vector2(to)))
		return PackedVector2Array()

	func _step_cost(cell: Vector2i, step: Vector2i) -> float:
		var length: float = Vector2(step).length()
		var wander: float = 1.0 + MapDecorationPlanner.TRAIL_WANDER \
			* (_wander.get_noise_2dv(Vector2(cell)) * 0.5 + 0.5)
		var wading: float = MapDecorationPlanner.TRAIL_SHALLOW_COST \
			if flags[index(cell)] & _SHALLOW != 0 else 1.0
		var slope: float = 1.0 + 4.0 * _terrain.cell_height_spread(cell)
		return length * wander * wading * slope

	func _walk_back(parent: PackedInt32Array, goal: int) -> PackedVector2Array:
		var path := PackedVector2Array()
		var at: int = goal
		while at >= 0:
			path.append(Vector2(at % width, at / width))
			at = parent[at]
		path.reverse()
		return path

	## Mark a routed trail: full strength on the path, half on its 8 neighbours.
	func stamp_trail(path: PackedVector2Array) -> void:
		for point: Vector2 in path:
			var cell := Vector2i(point)
			flags[index(cell)] |= _TRAIL
			trail[index(cell)] = 1.0
			for step: Vector2i in MapDecorationPlanner._AROUND:
				var n: Vector2i = cell + step
				if in_bounds(n) and flags[index(n)] & _IN_PLAY != 0:
					trail[index(n)] = maxf(trail[index(n)], 0.5)

	## A water cell whose surface stands WATERFALL_DROP above ground within reach: the lip.
	func is_waterfall_lip(cell: Vector2i) -> bool:
		var level: float = water_level[index(cell)]
		for step: Vector2i in MapDecorationPlanner._CARDINAL:
			for reach: int in range(1, MapDecorationPlanner.WATERFALL_REACH_CELLS + 1):
				var n: Vector2i = cell + step * reach
				if not in_bounds(n) or flags[index(n)] & _IN_PLAY == 0:
					break
				if flags[index(n)] & _WET != 0 and water_level[index(n)] >= level - 0.01:
					break
				if level - _terrain.cell_mean_height(n) >= MapDecorationPlanner.WATERFALL_DROP \
						and flags[index(n)] & _STEEP == 0:
					return true
		return false

	## A sloped, walkable cell with cliff on at least two sides: a ramp through a cliff line.
	func is_ramp(cell: Vector2i) -> bool:
		if _terrain.cell_height_spread(cell) <= 0.0:
			return false
		var steep_neighbours: int = 0
		for step: Vector2i in MapDecorationPlanner._AROUND:
			var n: Vector2i = cell + step
			if in_bounds(n) and flags[index(n)] & _STEEP != 0:
				steep_neighbours += 1
		return steep_neighbours >= 2


## Binary min-heap of (cell index, priority) for A*.
class _Heap:
	var _items := PackedInt32Array()
	var _keys := PackedFloat32Array()

	func is_empty() -> bool:
		return _items.is_empty()

	func push(item: int, key: float) -> void:
		_items.append(item)
		_keys.append(key)
		var i: int = _items.size() - 1
		while i > 0:
			var up: int = (i - 1) / 2
			if _keys[up] <= _keys[i]:
				break
			_swap(i, up)
			i = up

	func pop() -> int:
		var top: int = _items[0]
		var last: int = _items.size() - 1
		_swap(0, last)
		_items.resize(last)
		_keys.resize(last)
		var i: int = 0
		while true:
			var smallest: int = i
			for child: int in [2 * i + 1, 2 * i + 2]:
				if child < last and _keys[child] < _keys[smallest]:
					smallest = child
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var item: int = _items[a]
		_items[a] = _items[b]
		_items[b] = item
		var key: float = _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
