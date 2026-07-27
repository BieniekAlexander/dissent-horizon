@tool
class_name PathField
extends RefCounted

## Walking distance, in cells, from a set of seed cells to every cell reachable over a passable
## mask — 8-connected, diagonal steps costing sqrt(2). What pass 4 measures favor with once
## barriers make some features farther by foot than by line (map-generation.md §4). Pure.
##
## Dial's algorithm over integer costs: the grid is tens of thousands of cells, and a bucket
## queue keeps the search linear where a sorted frontier would not be.

#region Constants
## Integer step costs: 10 straight, 14 diagonal — sqrt(2) to within 1%.
const _STRAIGHT_COST: int = 10
const _DIAGONAL_COST: int = 14
const UNREACHED: float = INF
#endregion

#region Properties
var width: int = 0
var depth: int = 0
## Per cell, in cost units (_STRAIGHT_COST per cell); -1 unreached.
var _cost := PackedInt32Array()
#endregion


## `passable[z * width + x]` non-zero where a walker may stand.
static func from_seeds(
	passable: PackedByteArray, width: int, depth: int, seeds: Array[Vector2i]
) -> PathField:
	var field := PathField.new()
	field.width = width
	field.depth = depth
	field._cost.resize(width * depth)
	field._cost.fill(-1)
	var buckets: Dictionary = {0: []}
	for seed_cell: Vector2i in seeds:
		if field._in_bounds(seed_cell):
			field._cost[seed_cell.y * width + seed_cell.x] = 0
			buckets[0].append(seed_cell)
	var current: int = 0
	var remaining: int = seeds.size()
	while remaining > 0:
		var bucket: Array = buckets.get(current, [])
		buckets.erase(current)
		remaining -= bucket.size()
		for cell: Vector2i in bucket:
			if field._cost[cell.y * width + cell.x] != current:
				continue  # a stale entry, already reached more cheaply
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var next := Vector2i(cell.x + dx, cell.y + dz)
					if not field._in_bounds(next) or passable[next.y * width + next.x] == 0:
						continue
					var step: int = _DIAGONAL_COST if dx != 0 and dz != 0 else _STRAIGHT_COST
					var cost: int = current + step
					var at: int = next.y * width + next.x
					if field._cost[at] >= 0 and field._cost[at] <= cost:
						continue
					field._cost[at] = cost
					if not buckets.has(cost):
						buckets[cost] = []
					buckets[cost].append(next)
					remaining += 1
		current += 1
	return field


## Walking distance to `cell`, in cells; UNREACHED if no path leads there.
func distance(cell: Vector2i) -> float:
	if not _in_bounds(cell):
		return UNREACHED
	var cost: int = _cost[cell.y * width + cell.x]
	return UNREACHED if cost < 0 else float(cost) / _STRAIGHT_COST


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < depth
