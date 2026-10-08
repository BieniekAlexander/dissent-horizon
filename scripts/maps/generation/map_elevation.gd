@tool
class_name MapElevation
extends RefCounted

## Pass 6 of gdd/systems/terrain-and-navigation/map-generation.md: discrete ground levels.
## Every start and feature — a node of pass 4's FeatureGraph — gets a height, and each cell takes
## the height of the region it lies in. A height is a TERRACE level, and a terrace step is under
## MAX_SLOPE_DIFF, so it is walked over.
##
## - **Regions a walker can cross between differ by at most one terrace** (Alex, 2026-10-02): a
##   larger step would be graded into a long slope. **Elevation may not divide ground the
##   topology left open** (Alex, 2026-09-19).
## - **A cliff is a cut pass 4 made whose two sides end several terraces apart** — one way of
##   realising a barrier, chosen here. The levels are solved as constraints (LevelConstraints).
##
## Ramps are then chosen the way pass 4 carves: until every pair of starts keeps its routes and
## all walkable ground is one piece.
##
## It decides a height OFFSET per terrain corner; MapGenerator adds it to the ground pass 5
## shaped. One run's state, thrown away with the generator.

#region Constants
## Cell priorities when a corner is shared by cells of different levels: the highest wins, so a
## reserved zone keeps its footprints level and the neighbouring free ground takes the step.
const _FREE: int = 1
const _BARRIER: int = 2
const _OWNED: int = 3
## Ramp attempts per stranded stretch of ground before the generation fails.
const _REPAIRS: int = 32
## Rounds of choke trim then repair: each round only settles what the last one disturbed, so a
## map that has not settled in a few will not — and every round runs a full repair.
const _SETTLE_ROUNDS: int = 4
## Owned zones this close (Chebyshev, in cells) share a level. Zones already include a one-cell
## ring, so footprints within about four cells of each other end up level: a closer pair on
## different levels leaves a sliver of ground walled in by cliff.
const _UNION_REACH: int = 2
## Walkable ground cut off in a sliver smaller than this — a cell or two trapped between a
## barrier's border and a cliff — is left unreachable, like a ridge top: no ramp fits one, and
## chasing them only piles up ramps. Anything larger must be joined.
const _POCKET_CELLS: int = 25
## Relaxation rounds per level of range when holding terrace steps to one: a level can only need
## as many rounds as the range is wide, and the factor is slack for groups pulling against each
## other.
const _TERRACE_ROUNDS: int = 3
## Ramps the widening pass will see to before giving up: each round settles one ramp, and a map
## with more narrow ramps than this has something else wrong with it.
const _WIDEN_ROUNDS: int = 24
## The most one cell of graded ground may rise over its neighbour. Well under MAX_SLOPE_DIFF: a
## corner takes the highest cell touching it, so a cell crossed DIAGONALLY by the grade spans two
## steps, and anything above half the limit reads as a cliff.
const _GRADE_PER_CELL: float = TerrainGrid.MAX_SLOPE_DIFF * 0.45
## Sweeps of the grading relaxation. Each spreads a band by a cell in every direction, so this
## caps how wide a graded slope can get — a terrace's step needs about two sweeps.
const _GRADE_SWEEPS: int = 12
## How much a too-narrow ramp is widened before it is given up on.
const _WIDEN_FACTOR: float = 1.6
const _NONE: int = -1
## A cut may be a cliff while its two sides touch, round its ends, along at most this share of
## its barrier's length: there the drop is graded into a short slope (Alex, 2026-10-02). Past it
## the barrier is a short wall in open ground, and the slope round it would be the long ramp the
## one-terrace rule exists to prevent.
const _CLIFF_END_SHARE: float = 0.2
## Cells of a cliff's band kept above its face: one is enough to hold the crest steep.
const _CLIFF_CREST_CELLS: float = 1.0
## Half of a cell's eight neighbours — right and the three below — so a scan visits each
## neighbouring pair once.
const _FORWARD_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]
#endregion

#region Properties
## Terrace level per graph node, and per union group of nodes that must share one.
var level_of_node := PackedInt32Array()
## Cut index -> true, for each cut chosen as a cliff; it stands as one only while its sides stay
## a cliff's drop apart (is_cliff), and is drawn as the ridge or river it was otherwise.
var cliff_cuts: Dictionary = {}
## Cuts tried as cliffs that the levels could not hold apart, so stayed ridges or rivers.
var cliff_fallbacks: int = 0
## Plateau per graph node: nodes joined by graph edges on one level. A ramp joins two plateaus
## anywhere along their shared boundary, which is long where a single pair's is short.
var plateau_of_node := PackedInt32Array()
## Corner -> height offset set by a ramp, overriding the regional level. Rebuilt from `_ramps`
## on every relabel, so a ramp follows its two sides' levels and vanishes if they come to match.
var ramp_offsets: Dictionary = {}
## How many ramps stand.
var ramp_count: int = 0
## Each ramp: {at: Vector2i, low: int, high: int, run: float, half_width: float}.
var _ramps: Array[Dictionary] = []
## Cells made steep by a level step: the cliffs.
var cliff_cells: Dictionary = {}
## Height offset per terrain corner, index z * (width + 1) + x.
var offsets := PackedFloat32Array()
var errors := PackedStringArray()
## Graph edges given a ramp, kept for the final routes check.
var _ramped: Dictionary = {}

var _params: MapGenerationParams
var _rng: RandomNumberGenerator
var _terrain: TerrainData
var _topology: MapTopology
var _width: int = 0
var _depth: int = 0
## Cell -> owning node, for reserved ground that must stay level with its owner.
var _owner: Dictionary = {}
var _height := PackedFloat32Array()
## Cell -> the node whose height it took, so a re-level can copy that node's terrace.
var _source := PackedInt32Array()
var _priority := PackedInt32Array()
## Cell -> nearest node, for free ground.
var _nearest := PackedInt32Array()
## Union group per node; a group shares one level, so a re-level moves the whole group.
var _group_of_node := PackedInt32Array()
var _start_count: int = 0
#endregion


## `a_owned` maps each node to the cells it reserves (a start's box, a feature's footprint or
## pond pan, each grown by the ring whose corners it shares).
static func run(
	params: MapGenerationParams,
	rng: RandomNumberGenerator,
	terrain: TerrainData,
	topology: MapTopology,
	start_count: int,
	a_owned: Array
) -> MapElevation:
	var elevation := MapElevation.new()
	elevation._params = params
	elevation._rng = rng
	elevation._terrain = terrain
	elevation._topology = topology
	elevation._width = terrain.grid_width()
	elevation._depth = terrain.grid_depth()
	elevation._start_count = start_count
	elevation._index_nearest()
	elevation._assign_levels(start_count, a_owned)
	elevation._narrow_cliff_bands()
	elevation._relabel()
	elevation._ramp_for_routes(start_count)
	elevation._settle()
	elevation._widen_narrow_ramps()
	elevation._settle()
	elevation._check_routes()
	elevation._check_terraces()
	return elevation


## Hold the choke floor and connectivity together until neither changes anything. Cliffs are
## fixed obstacles for the floor, so a barrier too near one is trimmed; trimming frees cells and
## can expose cliff, and a repair ramp adds walls — each can undo the other, so they alternate.
func _settle() -> void:
	for _pass: int in _SETTLE_ROUNDS:
		var barriers: int = _topology.barrier_of.size()
		var ramps: int = _ramps.size()
		var levels: PackedInt32Array = level_of_node.duplicate()
		_topology.enforce_choke_width(cliff_cells)
		if _topology.barrier_of.size() != barriers:
			_relabel()
		if not _repair_connectivity():
			return
		if (
			_topology.barrier_of.size() == barriers
			and _ramps.size() == ramps
			and level_of_node == levels
		):
			return


## The routes invariant, on the final levels: later repairs can re-level ground an earlier
## ramping pass gave up on, so it is judged once, at the end.
func _check_routes() -> void:
	for a: int in _start_count:
		for b: int in range(a + 1, _start_count):
			if (
				_topology.graph.disjoint_paths(a, b, open_edges(_ramped), _params.min_routes)
				< _params.min_routes
			):
				errors.append(
					(
						"starts %d and %d cannot keep %d routes across levels"
						% [a, b, _params.min_routes]
					)
				)


## The terrace invariant, on the final levels and the final barriers: a re-level holds it where
## it can, and where it cannot the map is rejected rather than shipped with a step the topology
## never asked for — or with the long slope it would be graded into.
func _check_terraces() -> void:
	# A group's root is one of its own nodes, and every node of a group shares its level.
	for pair: Vector2i in _level_pairs():
		if absi(level_of_node[pair.x] - level_of_node[pair.y]) > 1:
			errors.append(
				(
					"regions %d and %d are open to each other but %d terraces apart"
					% [pair.x, pair.y, absi(level_of_node[pair.x] - level_of_node[pair.y])]
				)
			)


#region Levels
## The level every start shares, drawn among those between start_level_fraction_min and _max of
## the range; the nearest level to that band when none falls inside it.
func start_level() -> int:
	if _params.elevation_levels <= 1:
		return 0
	var top: int = _params.elevation_levels - 1
	var inside: Array[int] = []
	for level: int in _params.elevation_levels:
		var fraction: float = float(level) / top
		if (
			fraction >= _params.start_level_fraction_min
			and fraction <= _params.start_level_fraction_max
		):
			inside.append(level)
	if not inside.is_empty():
		return inside[_rng.randi() % inside.size()]
	var middle: float = (_params.start_level_fraction_min + _params.start_level_fraction_max) * 0.5
	return clampi(roundi(middle * top), 0, top)


## Nodes whose reserved ground touches, and the two sides of every carved pass-4 cut, share a
## height: a step between them would split a footprint or block a passage already promised.
## Each group asks for a terrace from smooth noise at its first node, or the start's if it holds
## a start, and gets the nearest the rules allow (_solve_levels).
##
## REJECTED — smoothing the noise, pulling a group to its neighbours' commonest level: with the
## one-step limit already holding terraces together it dragged whole maps onto the start's
## terrace, and three of six seeds came out with no relief.
func _assign_levels(a_start_count: int, a_owned: Array) -> void:
	var positions: PackedVector2Array = _topology.graph.positions
	var parent := PackedInt32Array()
	for i: int in positions.size():
		parent.append(i)
	for node: int in a_owned.size():
		for cell: Vector2i in a_owned[node]:
			if _topology.barrier_of.has(cell):
				continue
			for dx: int in range(-_UNION_REACH, _UNION_REACH + 1):
				for dz: int in range(-_UNION_REACH, _UNION_REACH + 1):
					var other: int = _owner.get(cell + Vector2i(dx, dz), _NONE)
					if other != _NONE and other != node:
						_union(parent, node, other)
			_owner[cell] = node
	for i: int in _topology.cuts.size():
		if _topology.carved[i]:
			var edge: Vector2i = _topology.graph.edges[_topology.cuts[i]]
			_union(parent, edge.x, edge.y)
	_group_of_node.resize(positions.size())
	for node: int in positions.size():
		_group_of_node[node] = _find(parent, node)
	_solve_levels(_wanted_levels(a_start_count), a_start_count)
	_find_plateaus()


## Group -> the level its noise sample asks for, stretched over the ladder; the starts' groups
## ask for the start level.
func _wanted_levels(a_start_count: int) -> Dictionary:
	var positions: PackedVector2Array = _topology.graph.positions
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 1.0 / _params.elevation_scale_cells
	var wanted: Dictionary = {}
	var starts_level: int = start_level()
	for node: int in a_start_count:
		wanted[_group_of_node[node]] = starts_level
	var samples: Array[Vector2] = []  # (noise, group)
	var sampled: Dictionary = {}
	for node: int in positions.size():
		var group: int = _group_of_node[node]
		if not wanted.has(group) and not sampled.has(group):
			sampled[group] = true
			samples.append(Vector2(noise.get_noise_2dv(positions[node]), group))
	_spread_over_levels(samples, wanted, _params.elevation_levels)
	return wanted


## Every group's level, as near the one it wants as the rules allow: walkable neighbours within
## one terrace, the starts at their level, and each cut chosen as a cliff its drop apart.
func _solve_levels(a_wanted: Dictionary, a_start_count: int) -> void:
	var groups: Array = a_wanted.keys()
	groups.sort()
	var index_of: Dictionary = {}
	for i: int in groups.size():
		index_of[groups[i]] = i
	var system := LevelConstraints.new(groups.size(), _params.elevation_levels - 1)
	for node: int in a_start_count:
		system.fix(index_of[_group_of_node[node]], a_wanted[_group_of_node[node]])
	var contact: Dictionary = _group_contacts()
	var candidates: Array[int] = _cliff_candidates(contact)
	var deferred: Dictionary = {}
	for cut: int in candidates:
		deferred[_group_pair(cut)] = true
	for pair: Vector2i in contact:
		if not deferred.has(pair):
			system.within(index_of[pair.x], index_of[pair.y], 1)
	_choose_cliffs(system, index_of, candidates, contact, a_wanted)
	var wanted_levels := PackedInt32Array()
	for group: int in groups:
		wanted_levels.append(a_wanted[group])
	var levels: PackedInt32Array = system.solve(wanted_levels)
	if levels.is_empty():
		# Unreachable while every rule is added only if the system stays solvable; a level
		# ladder too short for the starts' band is the one way left to get here.
		errors.append("no terrace levels satisfy the walkable-neighbour and cliff rules")
		levels.resize(groups.size())
		levels.fill(a_wanted[_group_of_node[0]])
	level_of_node.resize(_group_of_node.size())
	for node: int in _group_of_node.size():
		level_of_node[node] = levels[index_of[_group_of_node[node]]]


## The cuts that may be cliffs: thin, uncarved, between two groups, and with a barrier that
## dominates the ground the groups share — they touch along at most _CLIFF_END_SHARE of it.
func _cliff_candidates(a_contact: Dictionary) -> Array[int]:
	var barrier_cells: Dictionary = {}
	for cell: Vector2i in _topology.barrier_of:
		var cut: int = _topology.barrier_of[cell]
		barrier_cells[cut] = barrier_cells.get(cut, 0) + 1
	var candidates: Array[int] = []
	for i: int in _topology.cuts.size():
		var pair: Vector2i = _group_pair(i)
		if (
			_topology.carved[i]
			or _topology.grown[i]
			or not barrier_cells.has(i)
			or pair.x == pair.y
			or a_contact.get(pair, 0) > _CLIFF_END_SHARE * barrier_cells[i]
		):
			continue
		candidates.append(i)
	return candidates


## Draw cliff_cut_fraction of the candidate group pairs as cliffs, each a drawn drop apart, the
## side whose noise asks higher on top. A pair not drawn, or that no drop in range fits, holds
## within a terrace where its ground touches — unless the cliffs already standing force it
## apart, when it is a cliff all the same. Every cut between a cliff pair is a cliff.
func _choose_cliffs(
	a_system: LevelConstraints,
	a_index_of: Dictionary,
	a_candidates: Array[int],
	a_contact: Dictionary,
	a_wanted: Dictionary
) -> void:
	var cuts_of_pair: Dictionary = {}
	for cut: int in a_candidates:
		var pair: Vector2i = _group_pair(cut)
		if not cuts_of_pair.has(pair):
			cuts_of_pair[pair] = [] as Array[int]
		cuts_of_pair[pair].append(cut)
	var pairs: Array[Vector2i] = []
	pairs.assign(cuts_of_pair.keys())
	pairs.sort()
	_shuffle_pairs(pairs)
	var tried: int = roundi(_params.cliff_cut_fraction * pairs.size())
	for i: int in range(tried, pairs.size()):
		_hold_within(a_system, a_index_of, pairs[i], a_contact, cuts_of_pair[pairs[i]])
	for i: int in tried:
		var pair: Vector2i = pairs[i]
		if _try_cliff(a_system, a_index_of, pair, a_wanted):
			for cut: int in cuts_of_pair[pair]:
				cliff_cuts[cut] = true
		else:
			cliff_fallbacks += 1
			_hold_within(a_system, a_index_of, pair, a_contact, cuts_of_pair[pair])


## Hold `a_pair` within a terrace where its ground touches; when the system cannot — cliffs
## already standing force the pair apart — `a_cuts` are cliffs instead.
func _hold_within(
	a_system: LevelConstraints,
	a_index_of: Dictionary,
	a_pair: Vector2i,
	a_contact: Dictionary,
	a_cuts: Array
) -> void:
	if not a_contact.has(a_pair):
		return
	var before: int = a_system.mark()
	a_system.within(a_index_of[a_pair.x], a_index_of[a_pair.y], 1)
	if a_system.is_feasible():
		return
	a_system.rollback(before)
	for cut: int in a_cuts:
		cliff_cuts[cut] = true


## Hold `a_pair` a drop apart: the drawn drop or, failing it, each smaller one in range, the side
## whose noise asks higher on top or else the other way up. False, with nothing added, when no
## drop in range fits the ways round.
func _try_cliff(
	a_system: LevelConstraints, a_index_of: Dictionary, a_pair: Vector2i, a_wanted: Dictionary
) -> bool:
	var high: int = a_index_of[a_pair.x]
	var low: int = a_index_of[a_pair.y]
	if a_wanted[a_pair.y] > a_wanted[a_pair.x]:
		var held: int = high
		high = low
		low = held
	var drawn: int = _rng.randi_range(
		_params.cliff_drop_terraces_min, _params.cliff_drop_terraces_max
	)
	for drop: int in range(drawn, _params.cliff_drop_terraces_min - 1, -1):
		if _holds_apart(a_system, high, low, drop) or _holds_apart(a_system, low, high, drop):
			return true
	return false


func _shuffle_pairs(a_values: Array[Vector2i]) -> void:
	for i: int in range(a_values.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var held: Vector2i = a_values[i]
		a_values[i] = a_values[j]
		a_values[j] = held


## The two groups either side of cut `a_cut`, lower first.
func _group_pair(a_cut: int) -> Vector2i:
	var edge: Vector2i = _topology.graph.edges[_topology.cuts[a_cut]]
	var g: int = _group_of_node[edge.x]
	var h: int = _group_of_node[edge.y]
	return Vector2i(mini(g, h), maxi(g, h))


## Group pairs, lower first, whose ground a walker crosses between -> how many neighbouring cell
## pairs they share where no barrier stands (at least 1 for an open graph edge). A cut whose
## barrier was clipped or trimmed short is crossed there all the same.
func _group_contacts() -> Dictionary:
	var contact: Dictionary = {}
	for edge: Vector2i in _topology.open_edges():
		var g: int = _group_of_node[edge.x]
		var h: int = _group_of_node[edge.y]
		if g != h:
			var pair := Vector2i(mini(g, h), maxi(g, h))
			contact[pair] = maxi(contact.get(pair, 0), 1)
	for z: int in _depth:
		for x: int in _width:
			var mine: int = _region_of(Vector2i(x, z))
			if mine == _NONE:
				continue
			for step: Vector2i in _FORWARD_NEIGHBOURS:
				var theirs: int = _region_of(Vector2i(x + step.x, z + step.y))
				if theirs == _NONE:
					continue
				var g: int = _group_of_node[mine]
				var h: int = _group_of_node[theirs]
				if g != h:
					var pair := Vector2i(mini(g, h), maxi(g, h))
					contact[pair] = contact.get(pair, 0) + 1
	return contact


## Group pairs held within one terrace: every pair a walker crosses between, but the two sides of
## a standing cliff, whose ends are graded across its drop.
func _level_pairs() -> Array[Vector2i]:
	var across_cliffs: Dictionary = {}
	for cut: int in cliff_cuts:
		if is_cliff(cut):
			across_cliffs[_group_pair(cut)] = true
	var pairs: Array[Vector2i] = []
	for pair: Vector2i in _group_contacts():
		if not across_cliffs.has(pair):
			pairs.append(pair)
	return pairs


## Add "`a_high` at least `a_drop` above `a_low`" to `a_system`, and keep it only if the system
## stays solvable.
func _holds_apart(a_system: LevelConstraints, a_high: int, a_low: int, a_drop: int) -> bool:
	var before: int = a_system.mark()
	a_system.apart(a_high, a_low, a_drop, _params.cliff_drop_terraces_max)
	if a_system.is_feasible():
		return true
	a_system.rollback(before)
	return false


## Pull each cliff's band in to its face (Alex, 2026-10-02): a six-cell band of talus either side
## buried a one- or two-unit drop. Below the face it keeps the cells the drop hides from the
## lowest camera pitch, so the ground a cliff hides is still its own; above it, a one-cell crest.
## The rest becomes ground of its own side. Measured on the band's own Voronoi gap, which is
## twice a cell's distance from the midline.
func _narrow_cliff_bands() -> void:
	var view_slope: float = tan(deg_to_rad(TerrainGrid.MIN_VIEW_PITCH_DEGREES))
	for cell: Vector2i in _topology.barrier_of.keys():
		var cut: int = _topology.barrier_of[cell]
		if not is_cliff(cut):
			continue
		var edge: Vector2i = _topology.graph.edges[_topology.cuts[cut]]
		var high: int = edge.x if level_of_node[edge.x] > level_of_node[edge.y] else edge.y
		var drop: float = absf(node_height(edge.x) - node_height(edge.y))
		var keep: float = (
			_CLIFF_CREST_CELLS
			if _nearest[cell.y * _width + cell.x] == high
			else ceilf(drop / view_slope)
		)
		if (_topology.nearest_of[cell] as Vector3).z * 0.5 > keep:
			_topology.barrier_of.erase(cell)


## Whether cut `a_cut` stands as a cliff: chosen as one, and its sides still a cliff's drop apart
## after every re-level since.
func is_cliff(a_cut: int) -> bool:
	if not cliff_cuts.has(a_cut):
		return false
	var edge: Vector2i = _topology.graph.edges[_topology.cuts[a_cut]]
	return absi(level_of_node[edge.x] - level_of_node[edge.y]) >= _params.cliff_drop_terraces_min


## The node whose ground `a_cell` is — its owner, or the nearest — or _NONE for a barrier cell or
## one out of play.
func _region_of(a_cell: Vector2i) -> int:
	if a_cell.x < 0 or a_cell.y < 0 or a_cell.x >= _width or a_cell.y >= _depth:
		return _NONE
	if _topology.in_play_mask()[a_cell.y * _width + a_cell.x] == 0:
		return _NONE
	if _topology.barrier_of.has(a_cell):
		return _NONE
	return _owner.get(a_cell, _nearest[a_cell.y * _width + a_cell.x])


## Terraces are walked over, so regions a walker crosses between may differ by at most one step.
## Across an uncarved cut a barrier already divides them, and any gap is its to carry (Alex,
## 2026-09-30). The levels are solved to this; a re-level breaks it near the groups it moves, and
## this restores it. Relaxation: pull each group to within one of its walkable neighbours,
## holding `a_fixed` (groups), until nothing moves. It converges because every round strictly
## narrows the spread, and the levels are bounded. An edge whose two ends are both held is left
## as it is — `_check_terraces` rejects the map if one survives.
func _limit_terrace_steps(a_fixed: Dictionary) -> void:
	var open: Array[Vector2i] = _level_pairs()
	for _round: int in _params.elevation_levels * _TERRACE_ROUNDS:
		var changed: bool = false
		for edge: Vector2i in open:
			var gap: int = level_of_node[edge.x] - level_of_node[edge.y]
			if absi(gap) <= 1:
				continue
			var high: int = edge.x if gap > 0 else edge.y
			var low: int = edge.y if gap > 0 else edge.x
			if a_fixed.has(_group_of_node[low]) and a_fixed.has(_group_of_node[high]):
				continue
			var moved: int = low if not a_fixed.has(_group_of_node[low]) else high
			var toward: int = 1 if moved == low else -1
			_set_group_level(_group_of_node[moved], level_of_node[moved] + toward)
			changed = true
		if not changed:
			return


func _set_group_level(a_group: int, a_level: int) -> void:
	for node: int in level_of_node.size():
		if _group_of_node[node] == a_group:
			level_of_node[node] = clampi(a_level, 0, _params.elevation_levels - 1)


## A node's ground height above the pass-5 ground: its terrace's steps.
func node_height(a_node: int) -> float:
	return level_of_node[a_node] * _params.elevation_step


## Whether the step between two nodes is a cliff rather than something a walker crosses.
func is_step(a_node: int, b_node: int) -> bool:
	return absf(node_height(a_node) - node_height(b_node)) > TerrainGrid.MAX_SLOPE_DIFF


func _find_plateaus() -> void:
	var parent := PackedInt32Array()
	for i: int in level_of_node.size():
		parent.append(i)
	for edge: Vector2i in _topology.graph.edges:
		if not is_step(edge.x, edge.y):
			_union(parent, edge.x, edge.y)
	plateau_of_node.resize(level_of_node.size())
	for node: int in level_of_node.size():
		plateau_of_node[node] = _find(parent, node)


## Map each group's noise sample onto a level, stretched so the whole ladder gets used: raw
## noise clusters near its middle and would leave most maps on two levels.
##
## Stretched, not RANKED. Ranking spreads the groups evenly over the ladder, which puts
## neighbouring regions at opposite ends — and the one-step limit then squashes them back
## together, flattening whole maps (seed 2006 came out at a single height).
static func _spread_over_levels(
	samples: Array[Vector2], level_of_group: Dictionary, levels: int
) -> void:
	var low: float = INF
	var high: float = -INF
	for sample: Vector2 in samples:
		low = minf(low, sample.x)
		high = maxf(high, sample.x)
	for sample: Vector2 in samples:
		var fraction: float = 0.5 if is_equal_approx(low, high) else (sample.x - low) / (high - low)
		level_of_group[int(sample.y)] = clampi(roundi(fraction * (levels - 1)), 0, levels - 1)


static func _find(parent: PackedInt32Array, node: int) -> int:
	while parent[node] != node:
		parent[node] = parent[parent[node]]
		node = parent[node]
	return node


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var root_a: int = _find(parent, a)
	var root_b: int = _find(parent, b)
	if root_a != root_b:
		# The lower root survives, so a start (the first nodes) always leads its group.
		parent[maxi(root_a, root_b)] = mini(root_a, root_b)


func _index_nearest() -> void:
	_nearest.resize(_width * _depth)
	for z: int in _depth:
		for x: int in _width:
			_nearest[z * _width + x] = int(_topology.nearest_two(Vector2(x + 0.5, z + 0.5)).x)


#endregion


#region Labels and offsets
## Recompute every cell's level and priority, the corner offsets (ramps override), and the cliffs.
func _relabel() -> void:
	_height.resize(_width * _depth)
	_source.resize(_width * _depth)
	_priority.resize(_width * _depth)
	for z: int in _depth:
		for x: int in _width:
			var cell := Vector2i(x, z)
			var at: int = z * _width + x
			if _owner.has(cell) and not _topology.barrier_of.has(cell):
				_height[at] = node_height(_owner[cell])
				_source[at] = _owner[cell]
				_priority[at] = _OWNED
			elif _topology.barrier_of.has(cell):
				var cut: int = _topology.barrier_of[cell]
				var edge: Vector2i = _topology.graph.edges[_topology.cuts[cut]]
				# A cliff's cells stand at their own side's level, so the step falls on the
				# band's midline; a chasm sits at the lower side's level and a ridge rises from
				# the higher.
				var wants_low: bool = _topology.flooded[cut]
				var lower: bool = node_height(edge.x) <= node_height(edge.y)
				if is_cliff(cut):
					_source[at] = _nearest[at]
				else:
					_source[at] = edge.x if lower == wants_low else edge.y
				_height[at] = node_height(_source[at])
				_priority[at] = _BARRIER
			else:
				_source[at] = _nearest[at]
				_height[at] = node_height(_source[at])
				_priority[at] = _FREE
	_grade_free_ground()
	_rebuild_ramps()
	var corners_wide: int = _width + 1
	offsets.resize(corners_wide * (_depth + 1))
	for cz: int in _depth + 1:
		for cx: int in corners_wide:
			var corner := Vector2i(cx, cz)
			offsets[cz * corners_wide + cx] = (
				ramp_offsets[corner] if ramp_offsets.has(corner) else _corner_height(corner)
			)
	cliff_cells.clear()
	var in_play: PackedByteArray = _topology.in_play_mask()
	for z: int in _depth:
		for x: int in _width:
			var cell := Vector2i(x, z)
			if (
				in_play[z * _width + x] == 1
				and _offset_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF
				and not _topology.barrier_of.has(cell)
			):
				cliff_cells[cell] = true


## Grade the free ground between regions of different height to within `_GRADE_PER_CELL` of its
## neighbours, so a cliff stands only where a barrier does (map-generation.md §6. Elevation —
## terraces and cliffs). Reserved ground and barriers are held. Sweeps over the grid like a
## distance transform, so a band spreads a cell per sweep each way.
func _grade_free_ground() -> void:
	_sweep_grade()
	_settle_owned_zones()
	_sweep_grade()


## A reserved zone is held flat while the ground around it grades away, which rings it in cliff.
## So each zone is dropped onto the graded ground: its cells all take the mean height of the free
## ground around them — one height, so the footprint stays buildable — and the grade is swept
## again to meet it. Per union GROUP, not per zone: zones within a couple of cells of each other
## share a group precisely because a step between them would fall inside one of their rings — a
## start box whose ring is shared with a feature came out with a step across it.
func _settle_owned_zones() -> void:
	var total: Dictionary = {}
	var count: Dictionary = {}
	for cell: Vector2i in _owner:
		var at: int = cell.y * _width + cell.x
		if _priority[at] != _OWNED:
			continue
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var near: Vector2i = cell + Vector2i(dx, dz)
				if near.x < 0 or near.y < 0 or near.x >= _width or near.y >= _depth:
					continue
				var near_at: int = near.y * _width + near.x
				if _priority[near_at] != _FREE or not _terrain.is_cell_in_play(near):
					continue
				var group: int = _group_of_node[_owner[cell]]
				total[group] = total.get(group, 0.0) + _height[near_at]
				count[group] = count.get(group, 0) + 1
	for cell: Vector2i in _owner:
		var at: int = cell.y * _width + cell.x
		var group: int = _group_of_node[_owner[cell]]
		if _priority[at] == _OWNED and count.get(group, 0) > 0:
			_height[at] = total[group] / count[group]


## Hot: it runs twice per _relabel, and ramp-building relabels once per ramp it tries, so it was
## nine-tenths of a generation. It therefore visits only the cells that can move, in index order
## and then reversed — the row-major sweep the grid walk did — with every per-cell test read from
## a mask built once.
func _sweep_grade() -> void:
	var in_play: PackedByteArray = _topology.in_play_mask()
	var cell_count: int = _width * _depth
	var fixed := PackedByteArray()
	fixed.resize(cell_count)
	# A barrier is the one place a drop may land whole, so its own height must not drag the
	# ground either side toward it. Ground out of play is never graded, so it must not drag the
	# edge either. Neither is read as a neighbour.
	var ignored := PackedByteArray()
	ignored.resize(cell_count)
	for at: int in cell_count:
		fixed[at] = 1 if _priority[at] != _FREE or in_play[at] == 0 else 0
		ignored[at] = 1 if _priority[at] == _BARRIER or in_play[at] == 0 else 0
	var active: PackedInt32Array = _grading_frontier(fixed)
	var last: int = active.size() - 1
	for _sweep: int in _GRADE_SWEEPS:
		var moved: bool = false
		for pass_index: int in 2:
			for k: int in active.size():
				var at: int = active[k] if pass_index == 0 else active[last - k]
				var x: int = at % _width
				var z: int = at / _width
				var low: float = INF
				var high: float = -INF
				for nz: int in range(maxi(z - 1, 0), mini(z + 2, _depth)):
					for nx: int in range(maxi(x - 1, 0), mini(x + 2, _width)):
						var near: int = nz * _width + nx
						if ignored[near] == 1:
							continue
						low = minf(low, _height[near])
						high = maxf(high, _height[near])
				if is_inf(low):
					continue  # walled in by barriers: nothing to grade against
				var floor_height: float = high - _GRADE_PER_CELL
				var ceiling: float = low + _GRADE_PER_CELL
				# Squeezed between a high neighbour and a low one: sit between them and let the
				# next sweep pull both ends toward this.
				var graded: float = (
					(low + high) * 0.5
					if floor_height > ceiling
					else clampf(_height[at], floor_height, ceiling)
				)
				if not is_equal_approx(graded, _height[at]):
					_height[at] = graded
					moved = true
		if not moved:
			return


## The cells a grade can reach, as ascending indices: those beside a height change, and
## everything within a slope's length of them, less `a_fixed`. The rest of the map is one flat
## height and cannot move, so sweeping it is the difference between a generation taking seconds
## and taking a minute.
func _grading_frontier(a_fixed: PackedByteArray) -> PackedInt32Array:
	var active := PackedByteArray()
	active.resize(_width * _depth)
	var frontier: Array[Vector2i] = []
	# Two cells differ symmetrically, so each pair is compared once, from the cell above-left of
	# it: right, and the three below.
	for z: int in _depth:
		for x: int in _width:
			var at: int = z * _width + x
			for step: Vector2i in _FORWARD_NEIGHBOURS:
				var nx: int = x + step.x
				var nz: int = z + step.y
				if nx < 0 or nz >= _depth or nx >= _width:
					continue
				var near: int = nz * _width + nx
				if not is_equal_approx(_height[near], _height[at]):
					active[at] = 1
					active[near] = 1
	for at: int in active.size():
		if active[at] == 1:
			frontier.append(Vector2i(at % _width, at / _width))
	# Walkable neighbours differ by at most a terrace, but a cliff's ends grade across its whole
	# drop; a drop to a barrier is not graded.
	var reach: int = (
		ceili(_params.cliff_drop_terraces_max * _params.elevation_step / _GRADE_PER_CELL) + 2
	)
	for _ring: int in reach:
		var next: Array[Vector2i] = []
		for cell: Vector2i in frontier:
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var near := Vector2i(cell.x + dx, cell.y + dz)
					if near.x < 0 or near.y < 0 or near.x >= _width or near.y >= _depth:
						continue
					var at: int = near.y * _width + near.x
					if active[at] == 0 and a_fixed[at] == 0:
						active[at] = 1
						next.append(near)
		frontier = next
	var movable := PackedInt32Array()
	for at: int in active.size():
		if active[at] == 1 and a_fixed[at] == 0:
			movable.append(at)
	return movable


## The height of the highest-priority cell touching `corner`; among equals, the highest ground.
func _corner_height(a_corner: Vector2i) -> float:
	var best_priority: int = 0
	var best_height: float = 0.0
	for dx: int in range(-1, 1):
		for dz: int in range(-1, 1):
			var cell: Vector2i = a_corner + Vector2i(dx, dz)
			if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _depth:
				continue
			var at: int = cell.y * _width + cell.x
			if (
				_priority[at] > best_priority
				or (_priority[at] == best_priority and _height[at] > best_height)
			):
				best_priority = _priority[at]
				best_height = _height[at]
	return best_height


func _offset_spread(a_cell: Vector2i) -> float:
	var top: int = a_cell.y * (_width + 1) + a_cell.x
	var bottom: int = top + _width + 1
	var h00: float = offsets[top]
	var h10: float = offsets[top + 1]
	var h01: float = offsets[bottom]
	var h11: float = offsets[bottom + 1]
	return maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))


#endregion


#region Ramps
## Graph edges a walker can cross: open in pass 4, and on one level or ramped between them.
func open_edges(a_ramped: Dictionary) -> Array[Vector2i]:
	var open: Array[Vector2i] = []
	for edge: Vector2i in _topology.open_edges():
		if not is_step(edge.x, edge.y) or a_ramped.has(edge):
			open.append(edge)
	return open


## Ramp level steps until every pair of starts keeps min_routes routes. A ramp that raises the
## deficient pair's count is taken first, as pass 4 carves; when no single ramp does — joining
## two starts can need several at once — one extending what the first start already reaches is
## taken instead. Either way each ramp is progress, so the loop ends.
func _ramp_for_routes(a_start_count: int) -> void:
	var graph: FeatureGraph = _topology.graph
	var ramped: Dictionary = _ramped
	for a: int in a_start_count:
		for b: int in range(a + 1, a_start_count):
			while (
				graph.disjoint_paths(a, b, open_edges(ramped), _params.min_routes)
				< _params.min_routes
			):
				if (
					not _ramp_one_raising(a, b, ramped)
					and not _ramp_one_extending(a, ramped)
					and not _relevel_one_extending(a, ramped)
				):
					return


## Unramped open edges between two levels, shuffled.
func _ramp_candidates(a_ramped: Dictionary) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for edge: Vector2i in _topology.open_edges():
		if is_step(edge.x, edge.y) and not a_ramped.has(edge):
			candidates.append(edge)
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var held: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = held
	return candidates


func _ramp_one_raising(a_from: int, a_to: int, a_ramped: Dictionary) -> bool:
	var graph: FeatureGraph = _topology.graph
	var before: int = graph.disjoint_paths(a_from, a_to, open_edges(a_ramped), _params.min_routes)
	for edge: Vector2i in _ramp_candidates(a_ramped):
		a_ramped[edge] = true
		if (
			graph.disjoint_paths(a_from, a_to, open_edges(a_ramped), _params.min_routes) > before
			and _build_ramp_between(edge.x, edge.y)
		):
			return true
		a_ramped.erase(edge)
	return false


## Where no ramp fits at the frontier of what `a_from` reaches, re-level a plateau just beyond it
## (one without a start) to the level of its reached neighbour.
func _relevel_one_extending(a_from: int, a_ramped: Dictionary) -> bool:
	var reached: Dictionary = _reached_nodes(a_from, a_ramped)
	for edge: Vector2i in _topology.open_edges():
		for pair: Vector2i in [edge, Vector2i(edge.y, edge.x)]:
			if (
				reached.has(pair.x)
				and not reached.has(pair.y)
				and _relevel_plateau(plateau_of_node[pair.y], pair.x)
			):
				return true
	return false


func _reached_nodes(a_from: int, a_ramped: Dictionary) -> Dictionary:
	var reached: Dictionary = {a_from: true}
	var open: Array[Vector2i] = open_edges(a_ramped)
	var grew: bool = true
	while grew:
		grew = false
		for edge: Vector2i in open:
			if reached.has(edge.x) != reached.has(edge.y):
				reached[edge.x] = true
				reached[edge.y] = true
				grew = true
	return reached


## Set every union group touching `a_plateau` to `a_node`'s height. Refused for one with a start.
func _relevel_plateau(a_plateau: int, a_node: int) -> bool:
	for node: int in _start_count:
		if plateau_of_node[node] == a_plateau:
			return false
	var groups: Dictionary = {}
	for node: int in level_of_node.size():
		if plateau_of_node[node] == a_plateau:
			groups[_group_of_node[node]] = true
	_set_groups_to(groups, a_node)
	_find_plateaus()
	_relabel()
	return true


## Ramp an edge leading out of what `a_from` reaches over the open graph; failing that, any edge
## that takes a ramp — a second route can need a ramp inside the reached set.
func _ramp_one_extending(a_from: int, a_ramped: Dictionary) -> bool:
	var reached: Dictionary = _reached_nodes(a_from, a_ramped)
	var candidates: Array[Vector2i] = _ramp_candidates(a_ramped)
	candidates.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool:
			return (
				(reached.has(p.x) != reached.has(p.y))
				and not (reached.has(q.x) != reached.has(q.y))
			)
	)
	for edge: Vector2i in candidates:
		if _build_ramp_between(edge.x, edge.y):
			a_ramped[edge] = true
			return true
	return false


## A ramp across the step between the plateaus of nodes `a` and `b`, at the cliff cell on
## their shared boundary nearest the midpoint of the a-b edge that has room for one. False when
## no cliff cell does.
func _build_ramp_between(a: int, b: int) -> bool:
	var positions: PackedVector2Array = _topology.graph.positions
	var midpoint: Vector2 = (positions[a] + positions[b]) * 0.5
	var want := Vector2i(
		mini(plateau_of_node[a], plateau_of_node[b]), maxi(plateau_of_node[a], plateau_of_node[b])
	)
	var boundary: Array[Vector2i] = []
	for cell: Vector2i in cliff_cells:
		var pair: Vector3 = _topology.nearest_two(Vector2(cell) + Vector2(0.5, 0.5))
		var p: int = plateau_of_node[int(pair.x)]
		var q: int = plateau_of_node[int(pair.y)]
		if Vector2i(mini(p, q), maxi(p, q)) == want:
			boundary.append(cell)
	boundary.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool:
			return (
				Vector2(p).distance_squared_to(midpoint) < Vector2(q).distance_squared_to(midpoint)
			)
	)
	for cell: Vector2i in boundary:
		var pair: Vector3 = _topology.nearest_two(Vector2(cell) + Vector2(0.5, 0.5))
		if _build_ramp_at(cell, int(pair.x), int(pair.y)):
			return true
	return false


## Grade the corners around `a_at` from node a's level to node b's, along the line a -> b, over a
## run long enough that no cell's corners spread past MAX_SLOPE_DIFF (sqrt(2) covers a ramp at
## any angle to the grid). Its walkable width is drawn from MIN_CHOKE_WIDTH up to twice that.
## Refused when the ramp would touch reserved ground, a barrier, the play edge, or a third region.
func _build_ramp_at(a_at: Vector2i, a: int, b: int, a_half_width: float = 0.0) -> bool:
	var low: int = a if node_height(a) <= node_height(b) else b
	var high: int = b if low == a else a
	var rise: float = node_height(high) - node_height(low)
	var ramp: Dictionary = {
		at = a_at,
		low = low,
		high = high,
		run = ceilf(rise * sqrt(2.0) / TerrainGrid.MAX_SLOPE_DIFF) + 1.0,
		half_width =
		(
			a_half_width
			if a_half_width > 0.0
			else (MapGenerationParams.MIN_CHOKE_WIDTH * (1.0 + _rng.randf()) + 1.0) * 0.5
		),
	}
	var corners: Dictionary = _ramp_corners(ramp)
	for corner: Vector2i in corners:
		for dx: int in range(-1, 1):
			for dz: int in range(-1, 1):
				if not _is_rampable(corner + Vector2i(dx, dz), low, high):
					return false
	_ramps.append(ramp)
	_relabel()
	return true


## A ramp's graded corners at the current levels: from its low node's level to its high node's
## along the line between them, over its run, across its width.
func _ramp_corners(a_ramp: Dictionary) -> Dictionary:
	var positions: PackedVector2Array = _topology.graph.positions
	var along: Vector2 = (positions[a_ramp.high] - positions[a_ramp.low]).normalized()
	var low_offset: float = node_height(a_ramp.low)
	var high_offset: float = node_height(a_ramp.high)
	var run: float = a_ramp.run
	var origin: Vector2 = Vector2(a_ramp.at) + Vector2(0.5, 0.5)
	var reach: int = ceili(maxf(a_ramp.half_width, run * 0.5)) + 2
	var corners: Dictionary = {}
	for dz: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var corner: Vector2i = a_ramp.at + Vector2i(dx, dz)
			var offset: Vector2 = Vector2(corner) - origin
			var s: float = offset.dot(along)
			if absf(offset.cross(along)) > a_ramp.half_width or absf(s) > run * 0.5 + 1.0:
				continue
			corners[corner] = lerpf(low_offset, high_offset, clampf(s / run + 0.5, 0.0, 1.0))
	return corners


## Rebuild the ramp overrides at the current levels, dropping ramps whose sides now match.
func _rebuild_ramps() -> void:
	ramp_offsets.clear()
	var standing: Array[Dictionary] = []
	for ramp: Dictionary in _ramps:
		if not is_step(ramp.low, ramp.high):
			continue
		if node_height(ramp.low) > node_height(ramp.high):
			var held: int = ramp.low
			ramp.low = ramp.high
			ramp.high = held
		var rise: float = node_height(ramp.high) - node_height(ramp.low)
		ramp.run = maxf(ramp.run, ceilf(rise * sqrt(2.0) / TerrainGrid.MAX_SLOPE_DIFF) + 1.0)
		ramp_offsets.merge(_ramp_corners(ramp), true)
		standing.append(ramp)
	_ramps = standing
	ramp_count = _ramps.size()


func _is_rampable(a_cell: Vector2i, a_low: int, a_high: int) -> bool:
	if a_cell.x < 0 or a_cell.y < 0 or a_cell.x >= _width or a_cell.y >= _depth:
		return false
	if (
		not _terrain.is_cell_in_play(a_cell)
		or _owner.has(a_cell)
		or _topology.barrier_of.has(a_cell)
	):
		return false
	var region: int = _nearest[a_cell.y * _width + a_cell.x]
	return not is_step(region, a_low) or not is_step(region, a_high)


#endregion


## Every ramp must carry a corridor at least MIN_CHOKE_WIDTH wide from its foot to its head: a
## feature, a barrier or a second cliff can cut across a ramp and leave a sliver nothing fits
## through. A ramp that cannot be widened enough is dropped, and its two sides brought level.
##
## TODO: no generated map at the defaults has a ramp at all any more — grading crosses a height
## change without one, and ramps are left to connectivity repair, which nothing has needed.
## Only the width measure itself is tested (test_MapElevation), so this path is unexercised:
## either build a fixture that forces a ramp, or retire the widening with the repair ramps.
func _widen_narrow_ramps() -> void:
	for _round: int in _WIDEN_ROUNDS:
		var narrow: Dictionary = {}
		for ramp: Dictionary in _ramps:
			if _ramp_corridor_width(ramp) < MapGenerationParams.MIN_CHOKE_WIDTH:
				narrow = ramp
				break
		if narrow.is_empty():
			return
		_ramps.erase(narrow)
		var wider: Dictionary = narrow.duplicate()
		wider.half_width = narrow.half_width * _WIDEN_FACTOR
		_ramps.append(wider)
		_relabel()
		if _ramp_corridor_width(wider) >= MapGenerationParams.MIN_CHOKE_WIDTH:
			continue
		_ramps.erase(wider)
		_relabel()
		if (
			not _relevel_plateau(plateau_of_node[narrow.high], narrow.low)
			and not _relevel_plateau(plateau_of_node[narrow.low], narrow.high)
		):
			errors.append("a ramp is too narrow to cross and its sides cannot be levelled")
			return


## The narrowest walkable slice of a ramp, measured across the line it climbs.
func _ramp_corridor_width(a_ramp: Dictionary) -> float:
	var positions: PackedVector2Array = _topology.graph.positions
	var along: Vector2 = (positions[a_ramp.high] - positions[a_ramp.low]).normalized()
	var origin: Vector2 = Vector2(a_ramp.at) + Vector2(0.5, 0.5)
	var passable: PackedByteArray = passable_mask()
	var run: float = a_ramp.run
	var reach: int = ceili(maxf(a_ramp.half_width, run * 0.5)) + 2
	var rows: Dictionary = {}  # step along the climb -> the crossing offsets that are walkable
	for dz: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var cell: Vector2i = a_ramp.at + Vector2i(dx, dz)
			if cell.x < 0 or cell.y < 0 or cell.x >= _width or cell.y >= _depth:
				continue
			var offset: Vector2 = Vector2(cell) + Vector2(0.5, 0.5) - origin
			if absf(offset.cross(along)) > a_ramp.half_width or absf(offset.dot(along)) > run * 0.5:
				continue
			if passable[cell.y * _width + cell.x] == 0:
				continue
			var step: int = roundi(offset.dot(along))
			if not rows.has(step):
				rows[step] = {}
			rows[step][roundi(offset.cross(along))] = true
	if rows.is_empty():
		return 0.0
	var narrowest: float = INF
	for step: int in rows:
		narrowest = minf(narrowest, _longest_run(rows[step]))
	return narrowest


## The longest unbroken run of walkable offsets in one slice — a slice split in two by an
## obstacle is two narrow corridors, not one wide one.
static func _longest_run(a_offsets: Dictionary) -> float:
	var sorted: Array = a_offsets.keys()
	sorted.sort()
	var longest: int = 0
	var run: int = 0
	var last: int = 0
	for offset: int in sorted:
		run = run + 1 if run > 0 and offset == last + 1 else 1
		last = offset
		longest = maxi(longest, run)
	return float(longest)


#endregion


#region Connectivity
## Ramp the step nearest any stranded walkable ground until the walkable ground is one piece.
## Where no ramp fits — a corner region hemmed in by the play edge or a barrier — a stranded
## plateau without a start is re-levelled to a reachable neighbour's level instead, which removes
## the step outright.
func _repair_connectivity() -> bool:
	for _repair: int in _REPAIRS:
		var stranded: Array[Vector2i] = _stranded_stretch()
		if stranded.is_empty():
			return true
		if (
			not _ramp_beside(stranded)
			and not _relevel_groups_in(stranded)
			and not _relevel_stranded(stranded[0])
		):
			break
	if _stranded_stretch().is_empty():
		return true
	errors.append("ground on different levels could not be joined into one piece")
	return false


## Try the cliff cells bordering a stranded stretch until one takes a ramp. Only bordering ones:
## a ramp anywhere else cannot reach the stretch, and building it anyway piles up ramps.
func _ramp_beside(a_stretch: Array[Vector2i]) -> bool:
	var tried: Dictionary = {}
	for cell: Vector2i in a_stretch:
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var near: Vector2i = cell + Vector2i(dx, dz)
				if not cliff_cells.has(near) or tried.has(near):
					continue
				tried[near] = true
				var pair: Vector3 = _topology.nearest_two(Vector2(near) + Vector2(0.5, 0.5))
				var a: int = int(pair.x)
				var b: int = int(pair.y)
				if is_step(a, b) and _build_ramp_at(near, a, b):
					return true
	return false


## Re-level the union groups owning or nearest to a stranded stretch to the level of reachable
## ground beside it — a feature's reserved square left as an island on its own level, say.
## Refused if any of those groups holds a start.
func _relevel_groups_in(a_stretch: Array[Vector2i]) -> bool:
	var field: PathField = PathField.from_seeds(
		passable_mask(), _width, _depth, [Vector2i(_topology.graph.positions[0].floor())]
	)
	var target: int = _NONE
	var groups: Dictionary = {}
	for cell: Vector2i in a_stretch:
		var node: int = _owner.get(cell, _nearest[cell.y * _width + cell.x])
		groups[_group_of_node[node]] = true
		if target != _NONE:
			continue
		for dx: int in range(-2, 3):
			for dz: int in range(-2, 3):
				var near: Vector2i = cell + Vector2i(dx, dz)
				if (
					near.x >= 0
					and near.y >= 0
					and near.x < _width
					and near.y < _depth
					and not is_inf(field.distance(near))
				):
					target = _source[near.y * _width + near.x]
	if target == _NONE:
		return false
	for node: int in _start_count:
		if groups.has(_group_of_node[node]):
			return false
	_set_groups_to(groups, target)
	_find_plateaus()
	_relabel()
	return true


## Give every node in `a_groups` the terrace of `a_node`, so their ground comes level
## with its. The re-levelled groups' OTHER open neighbours can now be terraces away, so the
## terrace limit is run again, holding the starts, the moved groups and `a_node`'s own — the
## join the re-level made is the point of it.
func _set_groups_to(a_groups: Dictionary, a_node: int) -> void:
	for node: int in level_of_node.size():
		if a_groups.has(_group_of_node[node]):
			level_of_node[node] = level_of_node[a_node]
	var held: Dictionary = a_groups.duplicate()
	held[_group_of_node[a_node]] = true
	for node: int in _start_count:
		held[_group_of_node[node]] = true
	_limit_terrace_steps(held)


func _relevel_stranded(a_cell: Vector2i) -> bool:
	var plateau: int = plateau_of_node[_nearest[a_cell.y * _width + a_cell.x]]
	var field: PathField = PathField.from_seeds(
		passable_mask(), _width, _depth, [Vector2i(_topology.graph.positions[0].floor())]
	)
	for edge: Vector2i in _topology.graph.edges:
		for pair: Vector2i in [edge, Vector2i(edge.y, edge.x)]:
			if (
				plateau_of_node[pair.x] == plateau
				and plateau_of_node[pair.y] != plateau
				and not is_inf(field.distance(Vector2i(_topology.graph.positions[pair.y].floor())))
			):
				return _relevel_plateau(plateau, pair.y)
	return false


## The first stretch of walkable ground, at least _POCKET_CELLS large, that the first start
## cannot reach; empty when there is none.
func _stranded_stretch() -> Array[Vector2i]:
	var mask: PackedByteArray = _topology.passable_mask(cliff_cells)
	var field: PathField = PathField.from_seeds(
		mask, _width, _depth, [Vector2i(_topology.graph.positions[0].floor())]
	)
	var seen: Dictionary = {}
	for z: int in _depth:
		for x: int in _width:
			var cell := Vector2i(x, z)
			if mask[z * _width + x] == 0 or not is_inf(field.distance(cell)) or seen.has(cell):
				continue
			var stretch: Array[Vector2i] = _stretch(cell, mask, seen)
			if stretch.size() >= _POCKET_CELLS:
				return stretch
	var none: Array[Vector2i] = []
	return none


## The 8-connected walkable stretch holding `a_cell`, marking its cells in `a_seen`.
func _stretch(a_cell: Vector2i, a_mask: PackedByteArray, a_seen: Dictionary) -> Array[Vector2i]:
	var stack: Array[Vector2i] = [a_cell]
	a_seen[a_cell] = true
	var cells: Array[Vector2i] = []
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		cells.append(at)
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var next: Vector2i = at + Vector2i(dx, dz)
				if next.x < 0 or next.y < 0 or next.x >= _width or next.y >= _depth:
					continue
				if a_mask[next.y * _width + next.x] != 0 and not a_seen.has(next):
					a_seen[next] = true
					stack.append(next)
	return cells


## Features moved after levels were set reserve different ground: re-derive the owned cells from
## `a_owned` (levels and groups unchanged), relabel, and re-join the walkable ground.
func reown(a_owned: Array) -> void:
	_owner.clear()
	for node: int in a_owned.size():
		for cell: Vector2i in a_owned[node]:
			if not _topology.barrier_of.has(cell):
				_owner[cell] = node
	_relabel()
	_settle()
	_check_terraces()


## Walkable cells after elevation: pass 4's, less the cliffs.
func passable_mask() -> PackedByteArray:
	return _topology.passable_mask(cliff_cells)
#endregion
