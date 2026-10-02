@tool
class_name ObstacleRegions
extends RefCounted

## Pass 4's obstacle regions (map-generation.md §Obstacle regions): uncarved cuts grown into
## mountains and lakes until the play area's traversable share falls to its target.
##
## A grown cut is its own Voronoi band, widened: every barrier-eligible cell whose two nearest
## nodes are the cut's pair, out to a wider gap from equidistant than a plain cut takes. Widening
## thickens the cut and lengthens it toward the Voronoi vertices, where neighbouring grown cuts
## meet and enclose ground; enclosed ground holding no feature or start is filled. A cell whose
## nearest pair is an OPEN edge never qualifies, so the corridors the routes run through stay.
##
## A growth that would strand a feature or a start is undone. The next cut grown is the one
## leaning most toward the alliance with the least impassable ground so far, so obstruction falls
## about evenly between them, and of the kind (lake or mountain) short of its share.
##
## One run's state, thrown away once the topology holds the result.

#region Constants
## The next cut is drawn from this many of the best-balancing candidates, not always the best,
## so two maps from neighbouring seeds do not grow the same cuts.
const _TOP_CANDIDATES: int = 3
## Rounds of growing then trimming for the choke floor. Trimming gives ground back, so a round
## that ends under its target grows more; a few settle it, and more would only grow slivers.
const _ROUNDS: int = 3
## A piece of walkable ground this large is open ground, not a pocket: larger than any face of
## the feature graph a region can close off, far smaller than the play area.
const _POCKET_CAP: int = 5000
## Walkable cells within this many cells of a grown cell seed the pocket search: the steep ring
## the topology gives a barrier, and the first walkable cell past it.
const _POCKET_SEED_REACH: int = 2
#endregion

#region Properties
var _topology: MapTopology
var _params: MapGenerationParams
var _rng: RandomNumberGenerator
var _terrain: TerrainData
var _grid: PlacementGrid
var _starts: Array[MapStart] = []
## Graph edge -> the eligible cells whose nearest two nodes are that pair.
var _cells_of_pair: Dictionary = {}
## Cells a region may not take: a start's clear box grown by feature_spacing.
var _start_buffer: Dictionary = {}
## Footprint cells: walkable in the topology's mask, but not traversable on the finished map.
var _footprints: Dictionary = {}
## One cell per start and feature, each of which must stay on the main walkable ground.
var _anchors: Array[Vector2i] = []
var _anchor_set: Dictionary = {}
var _play_cells: int = 0
## Impassable cells so far, split by MapFavor.access_share: the cost each alliance carries.
var _obstructed := PackedFloat32Array()
## Grown cells so far, lakes then mountains.
var _grown_lake: int = 0
var _grown_mountain: int = 0
var _noise := FastNoiseLite.new()
#endregion


static func grow(
	topology: MapTopology,
	params: MapGenerationParams,
	rng: RandomNumberGenerator,
	terrain: TerrainData,
	grid: PlacementGrid,
	starts: Array[MapStart],
	features: Array[MapFeature]
) -> void:
	var regions := ObstacleRegions.new()
	regions._topology = topology
	regions._params = params
	regions._rng = rng
	regions._terrain = terrain
	regions._grid = grid
	regions._starts = starts
	regions._index(features)
	regions._run()


func _index(a_features: Array[MapFeature]) -> void:
	_noise.seed = _rng.randi()
	_noise.frequency = 1.0 / _params.region_noise_scale_cells
	for cell: Vector2i in _topology.nearest_of:
		var key: Vector2i = MapTopology.pair_key(_topology.nearest_of[cell])
		if not _cells_of_pair.has(key):
			_cells_of_pair[key] = []
		_cells_of_pair[key].append(cell)
	var dims: Vector2i = Vector2i.ONE * 2 * _params.start_clear_radius_cells
	var spacing: int = ceili(_params.feature_spacing_cells)
	for start: MapStart in _starts:
		_anchors.append(Vector2i(start.position.floor()))
		# The clear box as MapGenerator reserves it, grown by the spacing every feature keeps.
		var origin := Vector2i((start.position - Vector2(dims) * 0.5).round())
		for cell: Vector2i in PlacementGrid.rect_cells(
			origin - Vector2i.ONE * spacing, dims + Vector2i.ONE * 2 * spacing
		):
			_start_buffer[cell] = true
	for feature: MapFeature in a_features:
		var cells: Array[Vector2i] = (
			feature.pond_cells
			if feature.kind == MapFeature.Kind.POND
			else feature.structure_cells()
		)
		if not cells.is_empty():
			_anchors.append(cells[0])
		if feature.kind != MapFeature.Kind.POND:
			for cell: Vector2i in cells:
				_footprints[cell] = true
	for anchor: Vector2i in _anchors:
		_anchor_set[anchor] = true
	_play_cells = _topology.in_play_mask().count(1)
	_obstructed.resize(_params.alliance_count)
	for cell: Vector2i in _topology.barrier_of:
		_tally(cell)


func _run() -> void:
	var target_blocked: float = (1.0 - _params.target_traversable_fraction) * _play_cells
	var candidates: Array[int] = []
	for i: int in _topology.cuts.size():
		if not _topology.carved[i]:
			candidates.append(i)
	for _round: int in _ROUNDS:
		while not candidates.is_empty() and _blocked_cells() < target_blocked:
			var cut: int = _next_cut(candidates)
			candidates.erase(cut)
			_grow_cut(cut)
		_topology.enforce_choke_width({})
		if candidates.is_empty() or _blocked_cells() >= target_blocked:
			return


## Cells the finished map will not let a unit stand on, as far as pass 4 can tell: barriers and
## the steep ring pass 5 gives them, plus footprints. Pass 6's cliffs come on top.
func _blocked_cells() -> int:
	var mask: PackedByteArray = _topology.passable_mask()
	var walkable: int = mask.count(1)
	for cell: Vector2i in _footprints:
		walkable -= mask[cell.y * _grid.width + cell.x]
	return _play_cells - walkable


## Of the kind short of its share, the cut leaning most toward the least-obstructed alliance,
## drawn from the best few.
func _next_cut(a_candidates: Array[int]) -> int:
	var want_lake: bool = wants_lake(
		_grown_lake, _grown_mountain, _params.region_lake_fraction, _rng.randf()
	)
	var pool: Array[int] = a_candidates.filter(
		func(cut: int) -> bool: return _topology.flooded[cut] == want_lake
	)
	if pool.is_empty():
		pool = a_candidates.duplicate()
	var neediest: int = 0
	for a: int in _obstructed.size():
		if _obstructed[a] < _obstructed[neediest]:
			neediest = a
	var lean: Dictionary = {}
	for cut: int in pool:
		lean[cut] = MapFavor.access_share(_midpoint(cut), _starts, _params.alliance_count)[neediest]
	pool.sort_custom(func(a: int, b: int) -> bool: return lean[a] > lean[b])
	return pool[_rng.randi() % mini(_TOP_CANDIDATES, pool.size())]


## Whether the next region should be a lake: the kind further below its share of the cells grown
## so far, `lake_fraction` of them lakes; a tie, as at the start, is decided by `roll` in [0, 1).
static func wants_lake(
	lake_cells: int, mountain_cells: int, lake_fraction: float, roll: float
) -> bool:
	var grown_total: float = lake_cells + mountain_cells
	var lake_short: float = lake_fraction * grown_total - lake_cells
	var mountain_short: float = (1.0 - lake_fraction) * grown_total - mountain_cells
	if is_equal_approx(lake_short, mountain_short):
		return roll < lake_fraction
	return lake_short > mountain_short


func _midpoint(a_cut: int) -> Vector2:
	var edge: Vector2i = _topology.graph.edges[_topology.cuts[a_cut]]
	return (_topology.graph.positions[edge.x] + _topology.graph.positions[edge.y]) * 0.5


## Widen `a_cut` and fill what it encloses; undone whole if it strands a feature or a start.
func _grow_cut(a_cut: int) -> void:
	var width: float = _rng.randf_range(
		_params.region_width_min_cells, _params.region_width_max_cells
	)
	var added: Array[Vector2i] = []
	for cell: Vector2i in _cells_of_pair.get(_topology.graph.edges[_topology.cuts[a_cut]], []):
		if (
			_topology.barrier_of.has(cell)
			or _topology.carved_cells.has(cell)
			or _start_buffer.has(cell)
		):
			continue
		var ragged: float = 1.0 + _params.region_edge_noise * _noise.get_noise_2d(cell.x, cell.y)
		if (_topology.nearest_of[cell] as Vector3).z <= width * ragged:
			added.append(cell)
	if added.is_empty():
		return
	var before: PackedByteArray = _topology.passable_mask()
	for cell: Vector2i in added:
		_topology.barrier_of[cell] = a_cut
	var pockets: Array[Vector2i] = _enclosed_pockets(added, before)
	if pockets.size() == 1 and pockets[0] == Vector2i(-1, -1):
		for cell: Vector2i in added:
			_topology.barrier_of.erase(cell)
		return
	for cell: Vector2i in pockets:
		_topology.barrier_of[cell] = a_cut
	added.append_array(pockets)
	_topology.grown[a_cut] = true
	for cell: Vector2i in added:
		_tally(cell)
	if _topology.flooded[a_cut]:
		_grown_lake += added.size()
	else:
		_grown_mountain += added.size()


## The walkable ground beside `a_added` that it closed off, to be filled; [(-1, -1)] when a
## piece it closed off holds an anchor, a reserved cell or a start's buffer, which a growth must
## neither strand nor fill.
##
## Local rather than a flood of the whole map: each piece beside the new cells is flooded up to
## _POCKET_CAP cells, and one that reaches it is the open ground. TODO: a growth that split the open
## ground into two halves that large is not caught here; the topology's connectivity repair
## carves it open again. Ground `a_before` already closed off is left alone.
func _enclosed_pockets(a_added: Array[Vector2i], a_before: PackedByteArray) -> Array[Vector2i]:
	var mask: PackedByteArray = _topology.passable_mask()
	var width: int = _grid.width
	var visited := PackedByteArray()
	visited.resize(mask.size())
	var pockets: Array[Vector2i] = []
	for cell: Vector2i in a_added:
		for dz: int in range(-_POCKET_SEED_REACH, _POCKET_SEED_REACH + 1):
			for dx: int in range(-_POCKET_SEED_REACH, _POCKET_SEED_REACH + 1):
				var at := Vector2i(cell.x + dx, cell.y + dz)
				if at.x < 0 or at.y < 0 or at.x >= width or at.y >= _grid.depth:
					continue
				var i: int = at.y * width + at.x
				if mask[i] == 0 or visited[i] != 0:
					continue
				var piece: PackedInt32Array = _flood(mask, i, visited)
				if piece.size() >= _POCKET_CAP:
					continue
				if _flood(a_before, i, PackedByteArray()).size() < _POCKET_CAP:
					continue  # already closed off before this growth
				for index: int in piece:
					var pocket_cell := Vector2i(index % width, index / width)
					if (
						not _grid.is_free(pocket_cell)
						or _anchor_set.has(pocket_cell)
						or _start_buffer.has(pocket_cell)
					):
						return [Vector2i(-1, -1)]
					pockets.append(pocket_cell)
	return pockets


## Cells 8-connected to index `a_from` over `a_mask`, stopping at _POCKET_CAP; each is marked in
## `a_visited` when that is given.
func _flood(a_mask: PackedByteArray, a_from: int, a_visited: PackedByteArray) -> PackedInt32Array:
	var width: int = _grid.width
	var seen: Dictionary = {a_from: true}
	var piece := PackedInt32Array([a_from])
	var head: int = 0
	while head < piece.size() and piece.size() < _POCKET_CAP:
		var at: int = piece[head]
		head += 1
		var x: int = at % width
		var z: int = at / width
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var nx: int = x + dx
				var nz: int = z + dz
				if nx < 0 or nz < 0 or nx >= width or nz >= _grid.depth:
					continue
				var next: int = nz * width + nx
				if a_mask[next] != 0 and not seen.has(next):
					seen[next] = true
					piece.append(next)
	if not a_visited.is_empty():
		for index: int in piece:
			a_visited[index] = 1
	return piece


func _tally(a_cell: Vector2i) -> void:
	var share: PackedFloat32Array = MapFavor.access_share(
		Vector2(a_cell) + Vector2(0.5, 0.5), _starts, _params.alliance_count
	)
	for a: int in share.size():
		_obstructed[a] += share[a]
