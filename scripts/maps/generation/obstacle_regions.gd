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
## Once the impassable ground leans past this share of obstruction_tolerance, the next cut is
## the best-balancing one rather than a draw: grown masses are large, and a draw that leans the
## wrong way late cannot be made up.
const _STEER_SHARE: float = 0.33
## Rounds of growing then trimming to the open gap. Trimming gives ground back, so a round that
## ends under its target grows more — regrowing cuts already grown once none is left ungrown.
const _ROUNDS: int = 6
## Each round reaches this much further, as a share of the drawn width, than the round before:
## a regrown cut must reach past what it already holds to add anything.
const _REGROWTH_REACH: float = 0.6
## How far either side of its target the balancing phase may move the blocked share, as a
## fraction of traversable_tolerance: half, so a balanced map still lands well inside the band.
const _BALANCE_OVERSHOOT: float = 0.5
## A growth that strands a feature is retried this many times in all, each reaching this share
## of the last.
const _GROWTH_ATTEMPTS: int = 3
## Growths the balancing phase may try, kept or not; each costs a full trim, and the best-leaning
## few are the ones that move the split.
const _BALANCE_ATTEMPTS: int = 12
const _RETRY_REACH: float = 0.6
## Masses broken per settle, at most; each break leaves two smaller ones, so a few suffice.
const _BREAK_ROUNDS: int = 8
## Cells walked per step toward the play edge: half a cell, so a diagonal walk misses none.
const _EDGE_WALK_STEP: float = 0.5
## A barrier's steep border, in cells either side; a passage cut through a mass loses it.
const _BORDER_CELLS: float = 1.0
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
## Graph edge -> mean access share over the cells its cut can grow into: where its ground
## actually lies. The midpoint of the edge can sit far off its Voronoi boundary.
var _lean_of_edge: Dictionary = {}
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
	_index_leans()
	_obstructed.resize(_params.alliance_count)
	_retally()


## Every graph edge's mean access share over the cells it can grow into, in one pass over the
## eligible cells: each lies in exactly one pair's band.
func _index_leans() -> void:
	var edge_of_pair: Dictionary = {}
	for e: int in _topology.graph.edges.size():
		edge_of_pair[_topology.graph.edges[e]] = e
	var totals: Dictionary = {}
	var counts: Dictionary = {}
	for cell: Vector2i in _topology.nearest_of:
		var pair: Vector3 = _topology.nearest_of[cell]
		var e: int = edge_of_pair.get(MapTopology.pair_key(pair), -1)
		if e < 0 or pair.z > _params.region_width_max_cells:
			continue
		if not totals.has(e):
			totals[e] = PackedFloat32Array()
			totals[e].resize(_params.alliance_count)
			counts[e] = 0
		var share: PackedFloat32Array = MapFavor.access_share(
			Vector2(cell) + Vector2(0.5, 0.5), _starts, _params.alliance_count
		)
		for a: int in share.size():
			totals[e][a] += share[a]
		counts[e] += 1
	for e: int in _topology.graph.edges.size():
		if not totals.has(e):
			var edge: Vector2i = _topology.graph.edges[e]
			var midpoint: Vector2 = (
				(_topology.graph.positions[edge.x] + _topology.graph.positions[edge.y]) * 0.5
			)
			_lean_of_edge[e] = MapFavor.access_share(midpoint, _starts, _params.alliance_count)
			continue
		var mean: PackedFloat32Array = totals[e]
		for a: int in mean.size():
			mean[a] /= counts[e]
		_lean_of_edge[e] = mean


func _run() -> void:
	var target_blocked: float = (1.0 - _params.target_traversable_fraction) * _play_cells
	var candidates: Array[int] = []
	for i: int in _topology.cuts.size():
		if not _topology.carved[i]:
			candidates.append(i)
	for round_index: int in _ROUNDS:
		# A cut already grown may grow again, wider: trimming gave back the ground it lost to
		# a neighbour, and only room away from every other obstacle survives the next trim.
		if candidates.is_empty():
			candidates = _grown_cuts()
		if candidates.is_empty():
			return
		while not candidates.is_empty() and _blocked_cells() < target_blocked:
			var cut: int = _next_cut(candidates)
			candidates.erase(cut)
			_grow_cut(cut, _reach_scale(round_index))
		_settle_shapes()
		if _blocked_cells() >= target_blocked:
			break
	var slack: float = _BALANCE_OVERSHOOT * _params.traversable_tolerance * _play_cells
	_balance(target_blocked, target_blocked - slack, target_blocked + slack)


## Even the split of impassable ground between alliances while the blocked cells stay within
## `a_floor` … `a_ceiling`. Masses are large, so the share can still lean hard when the target is
## met. Below the target the next move grows toward the light side — through an uncut graph edge
## too, since the light side may have no cut left; at or above it, the next move un-grows the
## grown cut leaning hardest toward the heavy side.
func _balance(a_target: float, a_floor: float, a_ceiling: float) -> void:
	var cut_of_edge: Dictionary = {}
	for i: int in _topology.cuts.size():
		cut_of_edge[_topology.cuts[i]] = i
	var growable: Array[int] = []
	for e: int in _topology.graph.edges.size():
		if not (cut_of_edge.has(e) and _topology.carved[cut_of_edge[e]]):
			growable.append(e)
	var shrinkable: Array[int] = _grown_cuts()
	for _attempt: int in _BALANCE_ATTEMPTS:
		if _imbalance() <= _STEER_SHARE * _params.obstruction_tolerance:
			return
		if _blocked_cells() >= a_target and not shrinkable.is_empty():
			var cut: int = _cuts_by_lean(shrinkable)[-1]
			shrinkable.erase(cut)
			_try_balancing_move(func() -> int: return _ungrow(cut), a_floor, a_ceiling)
		elif not growable.is_empty():
			var edge: int = _edges_by_lean(growable)[0]
			growable.erase(edge)
			var cut: int = cut_of_edge.get(edge, -1)
			_try_balancing_move(
				func() -> int:
					var grown_cut: int = cut if cut >= 0 else _recruit(edge)
					if grown_cut >= 0:
						_grow_cut(grown_cut, _reach_scale(_ROUNDS))
					return grown_cut,
				a_floor,
				a_ceiling
			)
		else:
			return


## Run `a_move` — a growth or an un-growth, returning the cut it acted on or -1 for none — then
## trim, and keep the result only if it evens the split inside `a_floor` … `a_ceiling`: a growth
## also fills pockets and trims its neighbours, so where its ground lands is known only once it
## has landed.
func _try_balancing_move(a_move: Callable, a_floor: float, a_ceiling: float) -> void:
	var before_imbalance: float = _imbalance()
	var barriers: Dictionary = _topology.barrier_of.duplicate()
	var cut_count: int = _topology.cuts.size()
	var grown_before: Array[bool] = _topology.grown.duplicate()
	var counts := Vector2i(_grown_lake, _grown_mountain)
	var carved_before: Array[bool] = _topology.carved.duplicate()
	var carved_cells: Dictionary = _topology.carved_cells.duplicate()
	if a_move.call() < 0:
		return
	_settle_shapes()
	var blocked: int = _blocked_cells()
	if _imbalance() < before_imbalance and blocked >= a_floor and blocked <= a_ceiling:
		return
	_topology.barrier_of = barriers
	_topology.cuts.resize(cut_count)
	_topology.flooded.resize(cut_count)
	carved_before.resize(cut_count)
	_topology.carved = carved_before
	_topology.carved_cells = carved_cells
	_topology.grown = grown_before
	_grown_lake = counts.x
	_grown_mountain = counts.y
	_retally()


## Return grown cut `a_cut` to a plain barrier: every cell it holds past barrier_width_cells of
## its own band goes, pocket fill included. Returns the cut.
func _ungrow(a_cut: int) -> int:
	var pair: Vector2i = _topology.graph.edges[_topology.cuts[a_cut]]
	var removed: int = 0
	for cell: Vector2i in _topology.barrier_of.keys():
		if _topology.barrier_of[cell] != a_cut:
			continue
		var own: Variant = _topology.nearest_of.get(cell)
		if (
			own != null
			and MapTopology.pair_key(own) == pair
			and (own as Vector3).z <= _params.barrier_width_cells
		):
			continue
		_topology.barrier_of.erase(cell)
		removed += 1
	_topology.grown[a_cut] = false
	if _topology.flooded[a_cut]:
		_grown_lake -= removed
	else:
		_grown_mountain -= removed
	return a_cut


## Cut graph edge `a_edge` as a new region, of the kind short of its share; -1, with nothing
## changed, if that leaves a pair of starts short of min_routes.
func _recruit(a_edge: int) -> int:
	_topology.cuts.append(a_edge)
	_topology.flooded.append(
		wants_lake(_grown_lake, _grown_mountain, _params.region_lake_fraction, _rng.randf())
	)
	_topology.carved.append(false)
	_topology.grown.append(false)
	var open: Array[Vector2i] = _topology.open_edges()
	for a: int in _starts.size():
		for b: int in range(a + 1, _starts.size()):
			if _topology.graph.disjoint_paths(a, b, open, _params.min_routes) < _params.min_routes:
				for column: Array in [
					_topology.cuts, _topology.flooded, _topology.carved, _topology.grown
				]:
					column.pop_back()
				return -1
	return _topology.cuts.size() - 1


func _grown_cuts() -> Array[int]:
	var grown_cuts: Array[int] = []
	for i: int in _topology.cuts.size():
		if _topology.grown[i] and not _topology.carved[i]:
			grown_cuts.append(i)
	return grown_cuts


## Each round reaches further than the last, so a regrown cut adds ground past what it holds.
static func _reach_scale(round_index: int) -> float:
	return 1.0 + _REGROWTH_REACH * round_index


## After any growth: close masses near the play edge onto it, trim to the open gap, break any
## mass too large, and trim what the break left too close, then recount the split. Closing adds
## cells and can make a mass too large, so it goes first; breaking only removes cells, but
## deleting a cut out of the middle of a mass can leave its neighbours too close.
func _settle_shapes() -> void:
	_close_to_edges()
	_topology.enforce_choke_width({})
	if _break_oversized():
		_topology.enforce_choke_width({})
	_retally()


#region Closing onto the play edge
## Fill the ground between the play edge and every obstacle that comes within open_gap_cells of
## it, so an obstacle either meets the edge or stands a field away from it: a band of open ground
## round the whole perimeter tells a player the edge is always a way through. An obstacle whose
## fill would take a reserved cell, or strand a feature or start, is left for the trim instead.
func _close_to_edges() -> void:
	var play: PlayArea = _topology.play_area()
	var obstacle_of: Dictionary = MapTopology.obstacles(_topology.barrier_of)
	var near_of: Dictionary = {}
	for cell: Vector2i in obstacle_of:
		var gap: float = MapTopology.edge_gap(cell, play)
		if gap >= MapTopology.EDGE_TOUCH_GAP and gap < _params.open_gap_cells:
			var id: int = obstacle_of[cell]
			if not near_of.has(id):
				near_of[id] = []
			near_of[id].append(cell)
	for id: int in near_of:
		var fill: Dictionary = {}
		var is_closable: bool = true
		for cell: Vector2i in near_of[id]:
			is_closable = _walk_to_edge(cell, play, _topology.barrier_of[cell], fill)
			if not is_closable:
				break
		if is_closable and not fill.is_empty():
			_add_fill(fill)


## Collect into `a_fill` (cell -> cut) the cells from `a_from` straight to the nearest play edge,
## along the play area's own axis; false if one of them may not become barrier.
func _walk_to_edge(a_from: Vector2i, a_play: PlayArea, a_cut: int, a_fill: Dictionary) -> bool:
	var centre: Vector2 = Vector2(a_from) + Vector2(0.5, 0.5)
	var local: Vector2 = a_play.to_local(centre)
	var margin: Vector2 = a_play.half - local.abs()
	var outward: Vector2 = (
		a_play.axis_a * signf(local.x) if margin.x < margin.y else a_play.axis_b * signf(local.y)
	)
	for step: int in range(1, ceili(2.0 * (_params.open_gap_cells + 2.0))):
		var at := Vector2i((centre + outward * (_EDGE_WALK_STEP * step)).floor())
		if at == a_from or a_fill.has(at) or _topology.barrier_of.has(at):
			continue
		if MapTopology.edge_gap(at, a_play) < MapTopology.EDGE_TOUCH_GAP or not _is_inner(at):
			return true
		if (
			not _topology.is_barrier_eligible(at)
			or _start_buffer.has(at)
			or _topology.carved_cells.has(at)
		):
			return false
		a_fill[at] = a_cut
	return true


## Whether `a_cell` and all eight neighbours are in play: past it the edge has been reached, as
## the cells beyond can hold no barrier and are its steep border.
func _is_inner(a_cell: Vector2i) -> bool:
	var in_play: PackedByteArray = _topology.in_play_mask()
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var at: Vector2i = a_cell + Vector2i(dx, dz)
			if at.x < 0 or at.y < 0 or at.x >= _grid.width or at.y >= _grid.depth:
				return false
			if in_play[at.y * _grid.width + at.x] == 0:
				return false
	return true


## Make `a_fill` (cell -> cut) barrier, filling the pockets it closes off; undone if a pocket
## holds a feature or start.
func _add_fill(a_fill: Dictionary) -> void:
	var before: PackedByteArray = _topology.passable_mask()
	var added: Array[Vector2i] = []
	added.assign(a_fill.keys())
	for cell: Vector2i in added:
		_topology.barrier_of[cell] = a_fill[cell]
	var pockets: Array[Vector2i] = _enclosed_pockets(added, before)
	if pockets.size() == 1 and pockets[0] == Vector2i(-1, -1):
		for cell: Vector2i in added:
			_topology.barrier_of.erase(cell)
		return
	var cut: int = a_fill[added[0]]
	for cell: Vector2i in pockets:
		_topology.barrier_of[cell] = cut


#endregion


#region Breaking oversized masses
## Break every mass whose bounding box, in the play area's own axes, spans more than
## max_obstacle_span_fraction of either side: a mass that large is a long walk round for ground
## units and hands the map to air. Each break is the cheapest that brings the mass under the cap
## — deleting one of its cuts (its graph edge opens) or cutting a passage open_gap_cells wide
## across it — measured in cells lost: deleting a whole mountain could throw away a third of a
## map's obstruction on the last round, with nothing left to grow it back. True if anything
## was removed.
func _break_oversized() -> bool:
	var play: PlayArea = _topology.play_area()
	var changed: bool = false
	for _round: int in _BREAK_ROUNDS:
		var worst: Array[Vector2i] = []
		var worst_span: float = _params.max_obstacle_span_fraction
		for mass: Array[Vector2i] in masses(_topology.barrier_of):
			var span: float = span_fraction(mass, play)
			if span > worst_span:
				worst_span = span
				worst = mass
		if worst.is_empty():
			return changed
		changed = true
		_apply_break(_cheapest_break(worst, play))
	return changed


## Of the ways to break `a_mass` — each of its cuts deleted, or a passage cut across it — the
## one losing fewest cells among those that bring every piece under the cap; failing that, the
## one leaving the largest piece smallest. A break is {cells, cut}: cut is -1 for a passage.
func _cheapest_break(a_mass: Array[Vector2i], a_play: PlayArea) -> Dictionary:
	var cells_of_cut: Dictionary = {}
	for cell: Vector2i in a_mass:
		var cut: int = _topology.barrier_of[cell]
		if not cells_of_cut.has(cut):
			cells_of_cut[cut] = [] as Array[Vector2i]
		cells_of_cut[cut].append(cell)
	var options: Array[Dictionary] = [{cells = _passage_cells(a_mass, a_play), cut = -1}]
	if cells_of_cut.size() > 1:
		for cut: int in cells_of_cut:
			options.append({cells = cells_of_cut[cut], cut = cut})
	var best: Dictionary = {}
	var best_key := Vector2(INF, INF)
	for option: Dictionary in options:
		var removed: Dictionary = {}
		for cell: Vector2i in option.cells:
			removed[cell] = true
		var rest: Dictionary = {}
		for cell: Vector2i in a_mass:
			if not removed.has(cell):
				rest[cell] = true
		var span: float = 0.0
		for piece: Array[Vector2i] in masses(rest):
			span = maxf(span, span_fraction(piece, a_play))
		# Under the cap, rank by cells lost; over it, by the span left, then cells.
		var fits: bool = span <= _params.max_obstacle_span_fraction
		var key := Vector2(0.0 if fits else span, option.cells.size())
		if key < best_key:
			best_key = key
			best = option
	return best


func _apply_break(a_break: Dictionary) -> void:
	if a_break.cut < 0:
		for cell: Vector2i in a_break.cells:
			_topology.barrier_of.erase(cell)
			_topology.carved_cells[cell] = true
		return
	for cell: Vector2i in _topology.barrier_of.keys():
		if _topology.barrier_of[cell] == a_break.cut:
			_topology.barrier_of.erase(cell)
	_topology.carved[a_break.cut] = true
	_topology.grown[a_break.cut] = false


## The cells of a passage open_gap_cells wide across `a_mass`, perpendicular to its longer side
## in the play area's axes and through the median of its cells along it, so it splits in two of
## about equal size. Once applied the passage is carved ground, so nothing grows back into it.
func _passage_cells(a_mass: Array[Vector2i], a_play: PlayArea) -> Array[Vector2i]:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell: Vector2i in a_mass:
		var local: Vector2 = a_play.to_local(Vector2(cell) + Vector2(0.5, 0.5))
		lo = lo.min(local)
		hi = hi.max(local)
	var span: Vector2 = (hi - lo) / (2.0 * a_play.half)
	var axis: int = 0 if span.x >= span.y else 1
	var along := PackedFloat32Array()
	for cell: Vector2i in a_mass:
		along.append(a_play.to_local(Vector2(cell) + Vector2(0.5, 0.5))[axis])
	along.sort()
	var middle: float = along[along.size() / 2]
	# The passage's walkable width, plus the steep border either side of it.
	var half_width: float = (_params.open_gap_cells + 2.0 * _BORDER_CELLS) * 0.5
	var passage: Array[Vector2i] = []
	for cell: Vector2i in a_mass:
		var local: Vector2 = a_play.to_local(Vector2(cell) + Vector2(0.5, 0.5))
		if absf(local[axis] - middle) <= half_width:
			passage.append(cell)
	return passage


## Barrier cells grouped into masses: obstacles whose steep borders meet are one.
static func masses(cells: Dictionary) -> Array:
	var obstacle_of: Dictionary = MapTopology.obstacles(cells)
	var by_id: Dictionary = {}
	for cell: Vector2i in obstacle_of:
		var id: int = obstacle_of[cell]
		if not by_id.has(id):
			var mass: Array[Vector2i] = []
			by_id[id] = mass
		by_id[id].append(cell)
	return by_id.values()


## The larger of a mass's two bounding-box spans, each as a share of the play area's side
## along that axis.
static func span_fraction(mass: Array[Vector2i], play: PlayArea) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell: Vector2i in mass:
		var local: Vector2 = play.to_local(Vector2(cell) + Vector2(0.5, 0.5))
		lo = lo.min(local)
		hi = hi.max(local)
	var span: Vector2 = (hi - lo) / (2.0 * play.half)
	return maxf(span.x, span.y)


#endregion


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
	pool = _cuts_by_lean(pool)
	if _imbalance() > _STEER_SHARE * _params.obstruction_tolerance:
		return pool[0]
	return pool[_rng.randi() % mini(_TOP_CANDIDATES, pool.size())]


## `a_cuts` ordered by how far each leans toward the least-obstructed alliance, most first.
func _cuts_by_lean(a_cuts: Array[int]) -> Array[int]:
	var lean: Dictionary = {}
	for cut: int in a_cuts:
		lean[cut] = _lean_toward_neediest(_topology.cuts[cut])
	var ordered: Array[int] = a_cuts.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool: return lean[a] > lean[b])
	return ordered


## `a_edges` (graph edge indices) ordered the same way.
func _edges_by_lean(a_edges: Array[int]) -> Array[int]:
	var lean: Dictionary = {}
	for edge: int in a_edges:
		lean[edge] = _lean_toward_neediest(edge)
	var ordered: Array[int] = a_edges.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool: return lean[a] > lean[b])
	return ordered


func _lean_toward_neediest(a_edge: int) -> float:
	var neediest: int = 0
	for a: int in _obstructed.size():
		if _obstructed[a] < _obstructed[neediest]:
			neediest = a
	return (_lean_of_edge[a_edge] as PackedFloat32Array)[neediest]


## The worst alliance's distance from an even split of the impassable ground so far.
func _imbalance() -> float:
	var total: float = 0.0
	for value: float in _obstructed:
		total += value
	if total <= 0.0:
		return 0.0
	return MapFavor.worst_deviation(_obstructed, total / _obstructed.size())


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


## Widen `a_cut`, its drawn width scaled by `a_reach_scale`, and fill what it encloses. A growth
## that would strand a feature or a start is retried shorter, and dropped if even the shortest
## would: undoing it whole threw away most regrowth, which reaches far enough to close pockets.
func _grow_cut(a_cut: int, a_reach_scale: float) -> void:
	var width: float = (
		_rng.randf_range(_params.region_width_min_cells, _params.region_width_max_cells)
		* a_reach_scale
	)
	for attempt: int in _GROWTH_ATTEMPTS:
		var added: Array[Vector2i] = _growth_cells(a_cut, width * pow(_RETRY_REACH, attempt))
		if added.is_empty():
			return
		var before: PackedByteArray = _topology.passable_mask()
		for cell: Vector2i in added:
			_topology.barrier_of[cell] = a_cut
		var pockets: Array[Vector2i] = _enclosed_pockets(added, before)
		if pockets.size() == 1 and pockets[0] == Vector2i(-1, -1):
			for cell: Vector2i in added:
				_topology.barrier_of.erase(cell)
			continue
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
		return


## The free cells of `a_cut`'s Voronoi band out to `a_width` from equidistant, ragged by noise.
func _growth_cells(a_cut: int, a_width: float) -> Array[Vector2i]:
	var added: Array[Vector2i] = []
	for cell: Vector2i in _cells_of_pair.get(_topology.graph.edges[_topology.cuts[a_cut]], []):
		if (
			_topology.barrier_of.has(cell)
			or _topology.carved_cells.has(cell)
			or _start_buffer.has(cell)
		):
			continue
		var ragged: float = 1.0 + _params.region_edge_noise * _noise.get_noise_2d(cell.x, cell.y)
		if (_topology.nearest_of[cell] as Vector3).z <= a_width * ragged:
			added.append(cell)
	return added


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


## Recount each alliance's impassable ground from the barriers as they stand: trimming removes
## cells the running tally added, and steering on the stale sum leans the map.
## What is blocked is the barriers and the steep ring pass 5 gives them, so both are counted.
func _retally() -> void:
	_obstructed.fill(0.0)
	var mask: PackedByteArray = _topology.passable_mask()
	var in_play: PackedByteArray = _topology.in_play_mask()
	for i: int in mask.size():
		if in_play[i] != 0 and mask[i] == 0:
			_tally(Vector2i(i % _grid.width, i / _grid.width))


func _tally(a_cell: Vector2i) -> void:
	var share: PackedFloat32Array = MapFavor.access_share(
		Vector2(a_cell) + Vector2(0.5, 0.5), _starts, _params.alliance_count
	)
	for a: int in share.size():
		_obstructed[a] += share[a]
