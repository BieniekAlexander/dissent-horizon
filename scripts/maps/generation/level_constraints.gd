@tool
class_name LevelConstraints
extends RefCounted

## Integer terrace levels for a set of groups, under DIFFERENCE CONSTRAINTS: each one says
## `level[b] - level[a] <= weight`. Pass 6 states its rules this way — walkable neighbours within
## one terrace, a cliff's two sides at least its drop apart, starts fixed, every level in range —
## and a system of them is feasible exactly when its constraint graph has no negative cycle
## (Bellman-Ford). Pure.
##
## Levels are chosen one group at a time, each as near its wanted level as the bounds the rest
## imply allow. Bounds come from shortest paths through the graph, so a value inside them always
## extends to a full solution: assignment never paints itself into a corner.
##
## The constraint list grows as rules are added, and `rollback` truncates it, which is how a
## cliff that would make the system infeasible is tried and dropped.

#region Constants
## A distance no path reaches: larger than any sum of terrace weights, safe from overflow.
const _UNREACHED: int = 1 << 30
#endregion

#region Properties
## Groups 0 … _count - 1, plus one more: the ZERO node every range and fixed value is measured
## against, held at level 0.
var _count: int = 0
## (from, to, weight): level[to] <= level[from] + weight.
var _arcs: Array[Vector3i] = []
#endregion


## `a_count` groups, every level in 0 … `a_top`.
func _init(a_count: int, a_top: int) -> void:
	_count = a_count
	for group: int in a_count:
		bound(_zero(), group, a_top)
		bound(group, _zero(), 0)


## level[a_b] - level[a_a] <= a_weight.
func bound(a_a: int, a_b: int, a_weight: int) -> void:
	_arcs.append(Vector3i(a_a, a_b, a_weight))


## |level[a_a] - level[a_b]| <= a_weight.
func within(a_a: int, a_b: int, a_weight: int) -> void:
	bound(a_a, a_b, a_weight)
	bound(a_b, a_a, a_weight)


## level[a_high] - level[a_low] between `a_least` and `a_most`.
func apart(a_high: int, a_low: int, a_least: int, a_most: int) -> void:
	bound(a_high, a_low, -a_least)
	bound(a_low, a_high, a_most)


func fix(a_group: int, a_level: int) -> void:
	bound(_zero(), a_group, a_level)
	bound(a_group, _zero(), -a_level)


## How many constraints stand: pass it to `rollback` to undo everything added since.
func mark() -> int:
	return _arcs.size()


func rollback(a_mark: int) -> void:
	_arcs.resize(a_mark)


func is_feasible() -> bool:
	return not _distances_from(_zero(), false).is_empty()


## Each group's level in turn, as near `a_wanted[group]` as the constraints allow, fixing it before
## the next — so the system keeps every value it chose. Empty when the system is infeasible.
func solve(a_wanted: PackedInt32Array) -> PackedInt32Array:
	if not is_feasible():
		return PackedInt32Array()
	var levels := PackedInt32Array()
	levels.resize(_count)
	for group: int in _count:
		var highest: PackedInt32Array = _distances_from(_zero(), false)
		var lowest: PackedInt32Array = _distances_from(_zero(), true)
		levels[group] = clampi(a_wanted[group], -lowest[group], highest[group])
		fix(group, levels[group])
	return levels


func _zero() -> int:
	return _count


## Shortest path weights from `a_source` over the arcs — reversed when `a_reverse`, which turns
## upper bounds into lower ones. Empty on a negative cycle: the system is infeasible.
func _distances_from(a_source: int, a_reverse: bool) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_count + 1)
	dist.fill(_UNREACHED)
	dist[a_source] = 0
	for _round: int in _count + 1:
		var changed: bool = false
		for arc: Vector3i in _arcs:
			var from: int = arc.y if a_reverse else arc.x
			var to: int = arc.x if a_reverse else arc.y
			if dist[from] != _UNREACHED and dist[from] + arc.z < dist[to]:
				dist[to] = dist[from] + arc.z
				changed = true
		if not changed:
			return dist
	return PackedInt32Array()
