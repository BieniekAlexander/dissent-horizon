class_name NavField
extends RefCounted

## HOW FAR EVERY CELL OF A LATTICE IS FROM THE NEAREST OF SOME SOURCES, over passable ground.
##
## A Dijkstra sweep over a width × depth lattice: `over` takes the passability mask, `add_source`
## the cells the distance is measured from, `run` settles the field, `distance` reads it. The
## result is ONE INTEGER PER CELL and nothing else — no paths, no predecessor map — because the
## bot derives every spatial read (an approach band, quiet ground, an arrival time) from the
## scalars, and a scalar field cannot leak the order in which neighbours were expanded. Two
## mirrored source sets give bit-identical mirrored fields; that is what `tests/test_NavField.gd`
## checks. Rule and reasoning: gdd/systems/ai/world-model/lattice-and-topology.md §Distance
## fields.
##
## LIVES IN THE MAP LAYER ON PURPOSE, beside `NavPlacement`. The bot is the first caller, but
## how far ground is from a point is a fact about the map, reusable by the HUD (an arrival
## estimate) and by mission tactics; the bot owns only which sources it believes in. Nothing
## here reads a Commander, a Bot or a difficulty.
##
## Costs are integers in tenths of a lattice pitch — an orthogonal step is 10, a diagonal 14,
## and a per-cell penalty is added in the same units on ENTERING the cell — so a mirrored
## sweep sums the same integers and "mirror-exact" means byte-equal, with no float noise to
## argue about. Eight neighbours rather than `NavPlacement`'s four, because a travel time wants
## the octile distance (four neighbours overstate every diagonal by 41%); a diagonal is refused
## where either cell it cuts between is impassable, since a lattice cell is coarse and a crack
## between two walls is not a road.
##
## A source may stand on impassable ground — a believed enemy structure is one. It seeds its
## own cell at its start cost and expands into passable neighbours; an impassable cell that is
## not a source is never entered and reads UNREACHABLE.
##
## The sweep is RESUMABLE: `run(n)` settles at most `n` cells and reports whether it finished,
## so a bot can spread one field over several think ticks on the scheduler's budget
## (gdd/systems/ai/think-scheduling.md). Reads are meaningful once `is_done()`.

#region Constants
## Cost of an orthogonal step, in tenths of a pitch. The unit everything else is scaled to.
const STEP_ORTHOGONAL: int = 10
## Cost of a diagonal step: 10·√2 rounded — the octile approximation, exact enough for a
## travel time and integer so that sums are order-independent.
const STEP_DIAGONAL: int = 14
## No distance: the cell is impassable, cut off from every source, or the field has not run.
const UNREACHABLE: int = -1

## The eight neighbour offsets. A diagonal entry's two orthogonal components are the cells it
## cuts between, which must both be passable.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

## Heap keys pack (distance << INDEX_BITS) | index into one int, so the native integer order
## IS the priority order and a popped key carries both halves.
const _INDEX_BITS: int = 32
const _INDEX_MASK: int = (1 << _INDEX_BITS) - 1
#endregion

var _width: int = 0
var _depth: int = 0
var _passable: PackedByteArray = PackedByteArray()
## Extra cost to enter each cell; empty means none anywhere.
var _penalty: PackedInt32Array = PackedInt32Array()
## index → start cost, for every source added.
var _sources: Dictionary = {}

var _distance: PackedInt32Array = PackedInt32Array()
var _settled: PackedByteArray = PackedByteArray()
## A binary min-heap of packed keys, with lazy deletion: a stale key for an already-settled
## cell is skipped on pop.
var _heap: PackedInt64Array = PackedInt64Array()
var _started: bool = false
var _done: bool = false
var _settled_total: int = 0


#region Construction
## A field over a `width` × `depth` lattice whose cell (x, z) is passable iff
## `passable[z * width + x]` is non-zero. Add sources, then run.
static func over(width: int, depth: int, passable: PackedByteArray) -> NavField:
	var field := NavField.new()
	field._width = width
	field._depth = depth
	field._passable = passable
	return field


## Measure from `a_cell` too, with `a_start_cost` already on the clock there (a believed group
## that is some way off its last sighting, say). Out-of-bounds cells are ignored. Resets a run
## in progress, since a new source can undercut cells already settled.
func add_source(a_cell: Vector2i, a_start_cost: int = 0) -> void:
	if not is_in_bounds(a_cell):
		return
	_sources[index_of(a_cell)] = a_start_cost
	_reset()


## A cost added on ENTERING each cell, in the same tenths-of-a-pitch units as a step: the
## bot's own presence on the enemy's field, an area to avoid. One entry per cell, or empty
## for none. Resets a run in progress.
func set_penalty(a_penalty: PackedInt32Array) -> void:
	_penalty = a_penalty
	_reset()


#endregion


#region Running
## Settle up to `a_max_settled` cells (every cell when negative) and report whether the
## whole field is now settled. Call again to continue.
func run(a_max_settled: int = -1) -> bool:
	_ensure_started()
	var settled_now: int = 0
	while not _heap.is_empty():
		if a_max_settled >= 0 and settled_now >= a_max_settled:
			return false
		var key: int = _pop()
		var index: int = key & _INDEX_MASK
		if _settled[index] == 1:
			continue
		_settled[index] = 1
		settled_now += 1
		_settled_total += 1
		_relax_neighbours(index, key >> _INDEX_BITS)
	_done = true
	return true


func is_done() -> bool:
	return _done


## How many cells the sweep has settled so far — what a budgeted caller is charged for.
func settled_count() -> int:
	return _settled_total


#endregion


#region Reading
## The cost from the nearest source to `a_cell`, or UNREACHABLE. Meaningful once is_done().
func distance(a_cell: Vector2i) -> int:
	if not is_in_bounds(a_cell) or _distance.is_empty():
		return UNREACHABLE
	return _distance[index_of(a_cell)]


## The cost to `a_cell`, or — when the cell itself is never reached — to the nearest cell
## beside it: how a walker reaches a structure, which stands on impassable ground and is
## arrived at by standing against its wall. UNREACHABLE when neither is reached.
func distance_beside(a_cell: Vector2i) -> int:
	var best: int = distance(a_cell)
	if best != UNREACHABLE:
		return best
	for offset: Vector2i in _NEIGHBOURS:
		var d: int = distance(a_cell + offset)
		if d != UNREACHABLE and (best == UNREACHABLE or d < best):
			best = d
	return best


## Every cell's distance, indexed as the passability mask is. Empty before the first run.
func distances() -> PackedInt32Array:
	return _distance


func width() -> int:
	return _width


func depth() -> int:
	return _depth


func is_in_bounds(a_cell: Vector2i) -> bool:
	return a_cell.x >= 0 and a_cell.x < _width and a_cell.y >= 0 and a_cell.y < _depth


func index_of(a_cell: Vector2i) -> int:
	return a_cell.y * _width + a_cell.x


func cell_of(a_index: int) -> Vector2i:
	return Vector2i(a_index % _width, a_index / _width)


## The cost of the straight octile walk between two cells over open ground — the lower bound
## any field distance between them respects, and the read a caller makes where no field
## exists.
static func octile_distance(from: Vector2i, to: Vector2i) -> int:
	var dx: int = absi(to.x - from.x)
	var dz: int = absi(to.y - from.y)
	var diagonal: int = mini(dx, dz)
	return diagonal * STEP_DIAGONAL + (maxi(dx, dz) - diagonal) * STEP_ORTHOGONAL


#endregion


#region The sweep
func _reset() -> void:
	_started = false
	_done = false
	_settled_total = 0
	_heap = PackedInt64Array()


func _ensure_started() -> void:
	if _started:
		return
	_started = true
	var cells: int = _width * _depth
	_distance = PackedInt32Array()
	_distance.resize(cells)
	_distance.fill(UNREACHABLE)
	_settled = PackedByteArray()
	_settled.resize(cells)
	_heap = PackedInt64Array()
	for index: int in _sources:
		_offer(index, _sources[index])


## Record a shorter way to `a_index` and queue it.
func _offer(a_index: int, a_cost: int) -> void:
	var current: int = _distance[a_index]
	if current != UNREACHABLE and current <= a_cost:
		return
	_distance[a_index] = a_cost
	_push((a_cost << _INDEX_BITS) | a_index)


func _relax_neighbours(a_index: int, a_distance: int) -> void:
	var cell: Vector2i = cell_of(a_index)
	for offset: Vector2i in _NEIGHBOURS:
		var next: Vector2i = cell + offset
		if not is_in_bounds(next):
			continue
		var next_index: int = index_of(next)
		if _passable[next_index] == 0:
			continue
		var is_diagonal: bool = offset.x != 0 and offset.y != 0
		if is_diagonal and not _can_cut(cell, offset):
			continue
		var step: int = STEP_DIAGONAL if is_diagonal else STEP_ORTHOGONAL
		var penalty: int = _penalty[next_index] if not _penalty.is_empty() else 0
		_offer(next_index, a_distance + step + penalty)


## Whether a diagonal step from `a_cell` along `a_offset` passes between two passable cells.
func _can_cut(a_cell: Vector2i, a_offset: Vector2i) -> bool:
	var across: Vector2i = a_cell + Vector2i(a_offset.x, 0)
	var along: Vector2i = a_cell + Vector2i(0, a_offset.y)
	return _passable[index_of(across)] != 0 and _passable[index_of(along)] != 0


#endregion


#region The heap
func _push(a_key: int) -> void:
	_heap.append(a_key)
	var i: int = _heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) >> 1
		if _heap[parent] <= _heap[i]:
			break
		_swap(parent, i)
		i = parent


func _pop() -> int:
	var top: int = _heap[0]
	var last: int = _heap[_heap.size() - 1]
	_heap.resize(_heap.size() - 1)
	if _heap.is_empty():
		return top
	_heap[0] = last
	var i: int = 0
	var size: int = _heap.size()
	while true:
		var left: int = 2 * i + 1
		var right: int = left + 1
		var smallest: int = i
		if left < size and _heap[left] < _heap[smallest]:
			smallest = left
		if right < size and _heap[right] < _heap[smallest]:
			smallest = right
		if smallest == i:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a_i: int, a_j: int) -> void:
	var held: int = _heap[a_i]
	_heap[a_i] = _heap[a_j]
	_heap[a_j] = held
#endregion
