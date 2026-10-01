@tool
class_name MapTopology
extends RefCounted

## Pass 4 of gdd/systems/terrain-and-navigation/map-generation.md: which neighbouring features
## a barrier separates, where the barriers lie, and where they are carved open. It decides
## cells, not heights — pass 5 raises or floods them.
##
## A barrier is a CUT edge of the FeatureGraph drawn on the Voronoi boundary between its two
## nodes: the cells whose two nearest nodes are that pair, and nearly equidistant. Connectivity
## is then restored by CARVING — a band across the barrier — never by rejecting cuts, so the
## pass terminates.
##
## One run's state, thrown away with the generator; see MapGenerator for why a run holds it.

#region Constants
## Passes of connectivity repair allowed per cut before the generation fails.
const _REPAIRS_PER_CUT: int = 4
## Cells between a barrier cell's centre and the walkable ground beyond it: the cell's own half
## and its steep border. Two barrier cells a distance d apart leave d - 2 * this walkable (three
## apart: the two cells between are both borders, so none).
const _OBSTACLE_REACH: float = 1.5
## The same for a cliff cell, which is steep itself and has no border of its own.
const _CLIFF_REACH: float = 0.5
## Barrier cells within this Chebyshev distance share an obstacle — their steep borders meet.
const _SAME_OBSTACLE_REACH: int = 2
## A barrier fragment smaller than this, left by trimming, is dropped rather than kept as a
## lone steep stub.
const _MIN_FRAGMENT_CELLS: int = 4
#endregion

#region Properties
var graph: FeatureGraph
## Indices into graph.edges.
var cuts: Array[int] = []
## Per cut: flooded chasm rather than ridge, and whether it has been carved open.
var flooded: Array[bool] = []
var carved: Array[bool] = []
## Per cut: grown into an obstacle region (ObstacleRegions): a ridge into a mountain, a chasm
## into a lake. An ungrown flooded cut is a river.
var grown: Array[bool] = []
## Cell -> cut index, for every cell that stays a barrier.
var barrier_of: Dictionary = {}
## Cells a carve opened, so nothing placed later can close them again.
var carved_cells: Dictionary = {}
## Cell -> nearest_two() for every barrier-eligible cell, kept from drawing the barriers so
## ObstacleRegions can widen a cut without measuring every cell against every node again.
var nearest_of: Dictionary = {}
var errors := PackedStringArray()

var _params: MapGenerationParams
var _rng: RandomNumberGenerator
var _terrain: TerrainData
var _grid: PlacementGrid
var _start_count: int = 0
var _in_play := PackedByteArray()
#endregion


## `a_grid` is the placement grid after pass 3: free cells are the only ones a barrier may take.
static func run(
	params: MapGenerationParams, rng: RandomNumberGenerator, terrain: TerrainData,
	grid: PlacementGrid, starts: Array[MapStart], features: Array[MapFeature]
) -> MapTopology:
	var topology := MapTopology.new()
	topology._params = params
	topology._rng = rng
	topology._terrain = terrain
	topology._grid = grid
	topology._start_count = starts.size()
	var points := PackedVector2Array()
	for start: MapStart in starts:
		points.append(start.position)
	for feature: MapFeature in features:
		points.append(feature.center)
	topology.graph = FeatureGraph.build(points)
	topology._choose_cuts()
	topology._carve_for_routes()
	topology._draw_barriers()
	for i: int in topology.cuts.size():
		if topology.carved[i]:
			topology._carve_band(i, topology._nearest_barrier_cell(i, topology._midpoint(i)))
	ObstacleRegions.grow(topology, params, rng, terrain, grid, starts, features)
	topology._repair_connectivity()
	topology._enforce_choke_width()
	return topology


#region Cuts and routes
func _choose_cuts() -> void:
	var order: Array[int] = []
	for i: int in graph.edges.size():
		order.append(i)
	_shuffle(order)
	var count: int = roundi(_params.cut_fraction * graph.edges.size())
	for i: int in count:
		cuts.append(order[i])
		flooded.append(_rng.randf() < _params.flooded_cut_fraction)
		carved.append(false)
		grown.append(false)


## Carve cuts until every pair of starts has min_routes vertex-disjoint routes over the open
## graph. Each carve must raise the deficient pair's count, so this runs at most once per cut.
func _carve_for_routes() -> void:
	for a: int in _start_count:
		for b: int in range(a + 1, _start_count):
			while graph.disjoint_paths(a, b, open_edges(), _params.min_routes) < _params.min_routes:
				if not _carve_one_raising(a, b):
					errors.append("starts %d and %d cannot keep %d routes" % [a, b, _params.min_routes])
					return


func _carve_one_raising(a_from: int, a_to: int) -> bool:
	var before: int = graph.disjoint_paths(a_from, a_to, open_edges(), _params.min_routes)
	var order: Array[int] = []
	for i: int in cuts.size():
		if not carved[i]:
			order.append(i)
	_shuffle(order)
	for i: int in order:
		carved[i] = true
		if graph.disjoint_paths(a_from, a_to, open_edges(), _params.min_routes) > before:
			return true
		carved[i] = false
	return false


## Graph edges a walker can cross: every edge not cut, plus the cuts carved open.
func open_edges() -> Array[Vector2i]:
	var closed: Dictionary = {}
	for i: int in cuts.size():
		if not carved[i]:
			closed[cuts[i]] = true
	var open: Array[Vector2i] = []
	for e: int in graph.edges.size():
		if not closed.has(e):
			open.append(graph.edges[e])
	return open
#endregion


#region Drawing barriers
## Every free cell whose two nearest nodes are a cut pair, within barrier_width of equidistant.
## A cell next to anything reserved is left out: pass 5 moves a barrier cell's corners, which
## it shares with its neighbours, and a footprint or a start's box must stay level.
func _draw_barriers() -> void:
	var cut_by_pair: Dictionary = cut_of_pair()
	for z: int in _grid.depth:
		for x: int in _grid.width:
			var cell := Vector2i(x, z)
			if not is_barrier_eligible(cell):
				continue
			var pair: Vector3 = nearest_two(Vector2(cell) + Vector2(0.5, 0.5))
			nearest_of[cell] = pair
			var key: Vector2i = pair_key(pair)
			if cut_by_pair.has(key) and pair.z <= _params.barrier_width_cells:
				barrier_of[cell] = cut_by_pair[key]


## Graph edge (lower node, higher node) -> cut index, for every cut.
func cut_of_pair() -> Dictionary:
	var of_pair: Dictionary = {}
	for i: int in cuts.size():
		of_pair[graph.edges[cuts[i]]] = i
	return of_pair


## The pair of nodes a cell's nearest_two names, ordered as graph edges are.
static func pair_key(pair: Vector3) -> Vector2i:
	return Vector2i(mini(int(pair.x), int(pair.y)), maxi(int(pair.x), int(pair.y)))


func is_barrier_eligible(a_cell: Vector2i) -> bool:
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			if not _grid.is_free(a_cell + Vector2i(dx, dz)):
				return false
	return true


## (nearest index, second index, distance gap between them).
func nearest_two(a_point: Vector2) -> Vector3:
	var best: int = -1
	var second: int = -1
	var best_d: float = INF
	var second_d: float = INF
	for i: int in graph.positions.size():
		var d: float = a_point.distance_squared_to(graph.positions[i])
		if d < best_d:
			second = best
			second_d = best_d
			best = i
			best_d = d
		elif d < second_d:
			second = i
			second_d = d
	return Vector3(best, second, sqrt(second_d) - sqrt(best_d))
#endregion


#region Carving
func _midpoint(a_cut: int) -> Vector2:
	var edge: Vector2i = graph.edges[cuts[a_cut]]
	return (graph.positions[edge.x] + graph.positions[edge.y]) * 0.5


## The cell of cut `a_cut` nearest `a_point`; (-1, -1) if the cut drew no cells.
func _nearest_barrier_cell(a_cut: int, a_point: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for cell: Vector2i in barrier_of:
		if barrier_of[cell] != a_cut:
			continue
		var d: float = (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(a_point)
		if d < best_d:
			best_d = d
			best = cell
	return best


## Open a band across cut `a_cut` through `a_through`, running along its graph edge — the
## direction that crosses the barrier. Its walkable width is drawn from MIN_CHOKE_WIDTH up to
## twice that; the band is two cells wider still because pass 5 makes each cell bordering a
## barrier steep.
func _carve_band(a_cut: int, a_through: Vector2i) -> void:
	if a_through == Vector2i(-1, -1):
		return
	carved[a_cut] = true
	var edge: Vector2i = graph.edges[cuts[a_cut]]
	var along: Vector2 = (graph.positions[edge.y] - graph.positions[edge.x]).normalized()
	var origin: Vector2 = Vector2(a_through) + Vector2(0.5, 0.5)
	var walkable: float = MapGenerationParams.MIN_CHOKE_WIDTH * (1.0 + _rng.randf())
	var half_width: float = (walkable + 2.0 * _OBSTACLE_REACH - 1.0) * 0.5
	var opened: Array[Vector2i] = []
	for cell: Vector2i in barrier_of:
		if barrier_of[cell] != a_cut:
			continue
		var offset: Vector2 = Vector2(cell) + Vector2(0.5, 0.5) - origin
		if absf(offset.cross(along)) <= half_width:
			opened.append(cell)
	for cell: Vector2i in opened:
		barrier_of.erase(cell)
		carved_cells[cell] = true
#endregion


#region Choke width
## Trim barriers until no walkable passage between two of them, or between one and the edge of
## the play area, is narrower than MIN_CHOKE_WIDTH. Trimming only removes barrier, so the
## connectivity and routes already settled survive it.
##
## TODO: a narrow bay inside ONE bent barrier is not measured — only gaps between separate
## obstacles. Barriers are near-straight today, so none has been seen.
func _enforce_choke_width() -> void:
	enforce_choke_width({})


## As above, with `a_cliffs` — cells a later pass made steep — as obstacles that never give way:
## a barrier too close to one is trimmed whatever the sizes.
func enforce_choke_width(a_cliffs: Dictionary) -> void:
	var play := PlayArea.screen_aligned(
		Vector2(_grid.width, _grid.depth) * 0.5, _terrain.play_half_extents(), Map.CELL_SIZE)
	while true:
		var doomed: Dictionary = too_narrow_cells(barrier_of, play, a_cliffs)
		if doomed.is_empty():
			break
		for cell: Vector2i in doomed:
			barrier_of.erase(cell)
	_drop_fragments()


## Barrier cells that leave a passage narrower than MIN_CHOKE_WIDTH: every cell too close to the
## play edge, every cell too close to a `fixed` obstacle cell, and — of two barrier obstacles too
## close together — the cells of the smaller one that are. Fixed cells (cliffs) are never
## returned, and a cliff may meet the play edge: it closes that side rather than narrowing it.
static func too_narrow_cells(
	cells: Dictionary, play: PlayArea, fixed: Dictionary = {}
) -> Dictionary:
	var width: float = MapGenerationParams.MIN_CHOKE_WIDTH
	var everything: Dictionary = cells.merged(fixed)
	var obstacle_of: Dictionary = obstacles(everything)
	var sizes: Dictionary = {}
	for cell: Vector2i in obstacle_of:
		sizes[obstacle_of[cell]] = sizes.get(obstacle_of[cell], 0) + 1
	# Cells bucketed at the width that matters, so each is compared only with its neighbourhood.
	var bucket_size: int = ceili(width + 2.0 * _OBSTACLE_REACH)
	var buckets: Dictionary = {}
	for cell: Vector2i in everything:
		var key: Vector2i = cell / bucket_size
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(cell)
	var doomed: Dictionary = {}
	for cell: Vector2i in cells:
		if edge_gap(cell, play) < width:
			doomed[cell] = true
			continue
		var mine: int = obstacle_of[cell]
		var key: Vector2i = cell / bucket_size
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				for other: Vector2i in buckets.get(key + Vector2i(dx, dz), []):
					var theirs: int = obstacle_of[other]
					if theirs == mine:
						continue
					var other_reach: float = _CLIFF_REACH if fixed.has(other) else _OBSTACLE_REACH
					if walkable_gap(cell, other, _OBSTACLE_REACH, other_reach) >= width:
						continue
					var smaller: bool = sizes[mine] < sizes[theirs] \
						or (sizes[mine] == sizes[theirs] and mine < theirs)
					if fixed.has(other) or smaller:
						doomed[cell] = true
	return doomed


## Walkable cells between two obstacle cells, along the line joining them; barrier cells by
## default, which reach one border cell beyond themselves.
static func walkable_gap(
	a: Vector2i, b: Vector2i, a_reach: float = _OBSTACLE_REACH, b_reach: float = _OBSTACLE_REACH
) -> float:
	return Vector2(a).distance_to(Vector2(b)) - a_reach - b_reach


## Walkable cells between a barrier cell's obstacle and the nearest edge of the play area.
static func edge_gap(cell: Vector2i, play: PlayArea) -> float:
	var local: Vector2 = play.to_local(Vector2(cell) + Vector2(0.5, 0.5))
	return minf(play.half.x - absf(local.x), play.half.y - absf(local.y)) - _OBSTACLE_REACH


## Cell -> obstacle id: barrier cells whose steep borders meet are one obstacle.
static func obstacles(cells: Dictionary) -> Dictionary:
	var obstacle_of: Dictionary = {}
	var next_id: int = 0
	for start: Vector2i in cells:
		if obstacle_of.has(start):
			continue
		obstacle_of[start] = next_id
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			for dx: int in range(-_SAME_OBSTACLE_REACH, _SAME_OBSTACLE_REACH + 1):
				for dz: int in range(-_SAME_OBSTACLE_REACH, _SAME_OBSTACLE_REACH + 1):
					var near: Vector2i = at + Vector2i(dx, dz)
					if cells.has(near) and not obstacle_of.has(near):
						obstacle_of[near] = next_id
						stack.append(near)
		next_id += 1
	return obstacle_of


func _drop_fragments() -> void:
	var obstacle_of: Dictionary = obstacles(barrier_of)
	var sizes: Dictionary = {}
	for cell: Vector2i in obstacle_of:
		sizes[obstacle_of[cell]] = sizes.get(obstacle_of[cell], 0) + 1
	for cell: Vector2i in obstacle_of:
		if sizes[obstacle_of[cell]] < _MIN_FRAGMENT_CELLS:
			barrier_of.erase(cell)
#endregion


#region Connectivity
## Walkable cells: in play, and neither a barrier nor bordering one. Feature footprints count as
## walkable — they are islands in open ground, and the paths around them are pass 5's navmesh.
func passable_mask(a_steep: Dictionary = {}) -> PackedByteArray:
	var mask: PackedByteArray = in_play_mask().duplicate()
	for cell: Vector2i in barrier_of:
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var at: Vector2i = cell + Vector2i(dx, dz)
				if at.x >= 0 and at.y >= 0 and at.x < _grid.width and at.y < _grid.depth:
					mask[at.y * _grid.width + at.x] = 0
	for cell: Vector2i in a_steep:
		mask[cell.y * _grid.width + cell.x] = 0
	return mask


## 1 per cell in play. Memoized: the play area never changes within a run, and the mask is asked
## for on every connectivity check, where testing each cell against the play area dominated.
func in_play_mask() -> PackedByteArray:
	if _in_play.is_empty():
		_in_play.resize(_grid.width * _grid.depth)
		for z: int in _grid.depth:
			for x: int in _grid.width:
				_in_play[z * _grid.width + x] = 1 if _terrain.is_cell_in_play(Vector2i(x, z)) else 0
	return _in_play


## Carve until the walkable ground is one component containing every node — invariants (1) and
## (2). Each repair opens the barrier nearest a stranded component, through that cut.
func _repair_connectivity() -> void:
	for _repair: int in maxi(1, cuts.size() * _REPAIRS_PER_CUT):
		var stranded: Vector2i = _stranded_cell()
		if stranded == Vector2i(-1, -1):
			return
		var nearest := Vector2i(-1, -1)
		var nearest_d: float = INF
		for cell: Vector2i in barrier_of:
			var d: float = Vector2(cell).distance_squared_to(Vector2(stranded))
			if d < nearest_d:
				nearest_d = d
				nearest = cell
		if nearest == Vector2i(-1, -1):
			break
		_carve_band(barrier_of[nearest], nearest)
	if _stranded_cell() != Vector2i(-1, -1):
		errors.append("the walkable ground could not be joined into one piece")


## A walkable cell outside the component holding the first start; (-1, -1) when there is none.
## Every node sits on walkable ground (barriers keep off reserved cells), so this also finds a
## stranded start or feature.
func _stranded_cell() -> Vector2i:
	var mask: PackedByteArray = passable_mask()
	var field: PathField = PathField.from_seeds(
		mask, _grid.width, _grid.depth, [Vector2i(graph.positions[0].floor())])
	for z: int in _grid.depth:
		for x: int in _grid.width:
			if mask[z * _grid.width + x] != 0 and is_inf(field.distance(Vector2i(x, z))):
				return Vector2i(x, z)
	return Vector2i(-1, -1)
#endregion


func _shuffle(a_values: Array[int]) -> void:
	for i: int in range(a_values.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var held: int = a_values[i]
		a_values[i] = a_values[j]
		a_values[j] = held
