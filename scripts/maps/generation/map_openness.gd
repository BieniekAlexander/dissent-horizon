@tool
class_name MapOpenness
extends RefCounted

## How open a map's traversable ground is (map-generation.md §Openness). Pure: it reads a
## traversable mask and nothing else.
##
## CLEARANCE is, per traversable cell, the distance from its centre to the centre of the nearest
## cell a unit cannot stand on — the radius of the largest disc it can be the middle of. A
## passage k cells wide has clearance (k + 1) / 2 along its middle, so width = 2c − 1.
##
## CHOKES are found as BWEM finds them for StarCraft: cells are taken from most to least clear
## and grown into AREAS, a watershed on clearance. Where two areas meet, the meeting cell's
## clearance is the half-width of the narrowest passage between them. The meeting is a choke when
## both areas are genuinely open (their own clearest point is at least `open_clearance`) and the
## passage is markedly narrower than the smaller of them; otherwise the two were one open area
## with a waist, and merge silently.

#region Constants
## A meeting is a choke when its clearance is at most this share of the smaller area's peak:
## below it the passage reads as a constriction rather than a waist in one field.
const CHOKE_PEAK_RATIO: float = 0.7
## The peak clearance that makes an area open ground: a field at least 15 cells across. Smaller
## areas are alcoves and margins, and a passage into one is not a choke.
const OPEN_AREA_CLEARANCE: float = 8.0
## The eight neighbours of a cell.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1)
]
#endregion

#region Properties
var width: int = 0
var depth: int = 0
## Per cell, clearance in cells; 0 for a cell a unit cannot stand on.
var clearance := PackedFloat32Array()
## One {cell: Vector2i, width: float} per choke, width in cells (2c − 1).
var chokes: Array[Dictionary] = []
var traversable_cells: int = 0
#endregion


## `traversable[z * width + x]` non-zero where a unit may stand. Out of bounds is not traversable.
## `open_clearance` is the peak clearance an area needs to count as open ground.
static func measure(
	traversable: PackedByteArray,
	width: int,
	depth: int,
	open_clearance: float = OPEN_AREA_CLEARANCE
) -> MapOpenness:
	var openness := MapOpenness.new()
	openness.width = width
	openness.depth = depth
	openness.traversable_cells = traversable.count(1)
	var squared: PackedInt32Array = squared_clearance(traversable, width, depth)
	openness.clearance.resize(squared.size())
	for i: int in squared.size():
		openness.clearance[i] = sqrt(float(squared[i]))
	openness.chokes = _find_chokes(squared, width, depth, open_clearance)
	return openness


## Share of traversable cells inside some disc of radius `radius` that lies wholly on traversable
## ground — what is left of the ground after a morphological opening at that radius. The rest is
## corridor, margin and pocket.
func open_share(a_radius: float) -> float:
	if traversable_cells == 0:
		return 0.0
	var centres := PackedByteArray()
	centres.resize(clearance.size())
	for i: int in clearance.size():
		# A centre is an OBSTACLE in the distance transform below, so its zero marks the source.
		centres[i] = 0 if clearance[i] >= a_radius else 1
	var to_centre: PackedInt32Array = squared_clearance(centres, width, depth, false)
	var covered: int = 0
	var radius_squared: float = a_radius * a_radius
	for i: int in clearance.size():
		if clearance[i] > 0.0 and float(to_centre[i]) < radius_squared:
			covered += 1
	return float(covered) / traversable_cells


## Chokes narrower than `a_width` cells.
func chokes_narrower_than(a_width: float) -> Array[Dictionary]:
	var narrow: Array[Dictionary] = []
	narrow.assign(chokes.filter(func(c: Dictionary) -> bool: return c.width < a_width))
	return narrow


## Exact squared Euclidean distance (Felzenszwalb–Huttenlocher), per cell, from each cell where
## `mask` is non-zero to the nearest cell where it is zero. When `edges_block`, the grid's
## outside counts as zero cells too.
static func squared_clearance(
	mask: PackedByteArray, width: int, depth: int, edges_block: bool = true
) -> PackedInt32Array:
	# Pad by one cell so the outside is a ring of zeros when edges block.
	var padded_width: int = width + 2
	var padded_depth: int = depth + 2
	var far: int = (padded_width * padded_width + padded_depth * padded_depth) * 4
	var grid := PackedInt32Array()
	grid.resize(padded_width * padded_depth)
	grid.fill(0 if edges_block else far)
	for z: int in depth:
		for x: int in width:
			grid[(z + 1) * padded_width + x + 1] = far if mask[z * width + x] != 0 else 0
	var column := PackedInt32Array()
	column.resize(padded_depth)
	for x: int in padded_width:
		for z: int in padded_depth:
			column[z] = grid[z * padded_width + x]
		var transformed: PackedInt32Array = _transform_1d(column, far)
		for z: int in padded_depth:
			grid[z * padded_width + x] = transformed[z]
	var row := PackedInt32Array()
	row.resize(padded_width)
	for z: int in padded_depth:
		for x: int in padded_width:
			row[x] = grid[z * padded_width + x]
		var transformed: PackedInt32Array = _transform_1d(row, far)
		for x: int in padded_width:
			grid[z * padded_width + x] = transformed[x]
	var result := PackedInt32Array()
	result.resize(width * depth)
	for z: int in depth:
		for x: int in width:
			result[z * width + x] = grid[(z + 1) * padded_width + x + 1]
	return result


## The 1-D lower envelope of parabolas: squared distance along one line.
static func _transform_1d(values: PackedInt32Array, far: int) -> PackedInt32Array:
	var n: int = values.size()
	var result := PackedInt32Array()
	result.resize(n)
	var vertices := PackedInt32Array()
	vertices.resize(n)
	var bounds := PackedFloat64Array()
	bounds.resize(n + 1)
	var k: int = -1
	for q: int in n:
		if values[q] >= far:
			continue
		if k < 0:
			k = 0
			vertices[0] = q
			bounds[0] = -INF
			bounds[1] = INF
			continue
		var s: float = _intersection(values, q, vertices[k])
		while s <= bounds[k]:
			k -= 1
			if k < 0:
				break
			s = _intersection(values, q, vertices[k])
		k += 1
		vertices[k] = q
		bounds[k] = -INF if k == 0 else s
		bounds[k + 1] = INF
	if k < 0:
		result.fill(far)
		return result
	var j: int = 0
	for q: int in n:
		while bounds[j + 1] < q:
			j += 1
		var offset: int = q - vertices[j]
		result[q] = offset * offset + values[vertices[j]]
	return result


static func _intersection(values: PackedInt32Array, q: int, p: int) -> float:
	return float((values[q] + q * q) - (values[p] + p * p)) / float(2 * q - 2 * p)


## The watershed: cells from most to least clear, grown into areas; a choke where two open areas
## meet through a passage markedly narrower than either.
static func _find_chokes(
	squared: PackedInt32Array, width: int, depth: int, open_clearance: float
) -> Array[Dictionary]:
	# Squared clearances are integers, so they bucket exactly.
	var levels: Dictionary = {}
	for i: int in squared.size():
		if squared[i] > 0:
			if not levels.has(squared[i]):
				levels[squared[i]] = PackedInt32Array()
			levels[squared[i]].append(i)
	var keys: Array = levels.keys()
	keys.sort()
	keys.reverse()
	var parent := PackedInt32Array()
	parent.resize(squared.size())
	parent.fill(-1)
	var peak := PackedFloat32Array()
	peak.resize(squared.size())
	var chokes: Array[Dictionary] = []
	for level: int in keys:
		var here: float = sqrt(float(level))
		for i: int in levels[level]:
			var cell := Vector2i(i % width, i / width)
			parent[i] = i
			peak[i] = here
			for step: Vector2i in _NEIGHBOURS:
				var next: Vector2i = cell + step
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= depth:
					continue
				var j: int = next.y * width + next.x
				if parent[j] < 0:
					continue
				var mine: int = _find(parent, i)
				var theirs: int = _find(parent, j)
				if mine == theirs:
					continue
				var lower: float = minf(peak[mine], peak[theirs])
				if lower >= open_clearance and here <= CHOKE_PEAK_RATIO * lower:
					chokes.append({"cell": cell, "width": 2.0 * here - 1.0})
				var merged_peak: float = maxf(peak[mine], peak[theirs])
				parent[theirs] = mine
				peak[mine] = merged_peak
	return chokes


static func _find(parent: PackedInt32Array, node: int) -> int:
	var root: int = node
	while parent[root] != root:
		root = parent[root]
	while parent[node] != root:
		var next: int = parent[node]
		parent[node] = root
		node = next
	return root
