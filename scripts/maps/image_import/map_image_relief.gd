@tool
class_name MapImageRelief
extends RefCounted

## The height pass of the map image importer: classified cells in, per-corner heights out
## (map-from-image.md §Terrain, §Chasms).
##
## 1. **Targets.** Each cell wants its level's height (MapImageImportParams.level_height), a
##    water cell its bed (MapImageWater), a chasm cell a floor `chasm_depth` below its lowest
##    rim. A corner takes the highest DRY cell touching it — the generator's rule, so a step
##    falls inside the lower cell — a corner with no dry cell its shallowest bed, and a corner
##    touching a chasm the chasm's floor.
## 2. **Pins.** Some corners are fixed and the blur never moves them: a structure's footprint is
##    flat at its level; a chasm's floor corners alternate a RIDGE_ROUGHNESS apart, the ridge's
##    crest turned downward, so nothing walks or lands on it; and a cliff or ramp region is a
##    PLANE graded from its low rim to its high rim across the region.
## 3. **Smoothing.** A masked box blur of `smoothing_radius` over every corner that is not
##    pinned. Cliff and chasm corners are left out of the average as well as out of the update:
##    sampled, they would pull the ground at a cliff's lip or a chasm's rim down into the drop.
##
## **A cliff and a ramp are graded across their width and judged by the result** against
## TerrainGrid.MAX_SLOPE_DIFF: a ramp must come out walkable, a cliff must not. A ramp is one
## plane, low rim to high rim; a cliff falls across its own thickness at each point, so a long or
## curving line is judged where it is drawn. A "cliff" ten cells wide fails, and so does a cliff
## between adjacent levels: one step is walkable however sheer it is drawn.

#region Enums
## A corner's role in the blur: moved by it, kept but averaged into its neighbours, or kept
## and left out of the average.
enum Pin { FREE, KEPT, KEPT_UNSAMPLED }
#endregion

#region Constants
## Edge-noise wavelength in cells: features of the warp are about this size, so an edge wanders
## rather than jitters.
const NOISE_WAVELENGTH_CELLS: float = 12.0
## How far under its water a shore corner is held. Under WATER_OFFSET, so a bank cell — two
## corners at the shore, two at least WATER_OFFSET above the water — still averages above it.
const SHORE_DIP: float = MapImageWater.WATER_OFFSET * 0.5
## How far a rough corner is pushed up or down. Over the slope limit on its own, so a cell with
## one such corner is too steep to walk, and with margin: the talus a cliff's apron is broken by.
const ROUGH_RISE: float = MapGenerationParams.TALUS_ROUGHNESS
## Rim heights above the midpoint of a region's drop are its high side.
const _HALF: float = 0.5
const _FOUR_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
const _EIGHT_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
#endregion

#region Properties
## One import's working state: each step reads the grids the previous one wrote, in order, so
## they are fields rather than eight arrays threaded through every signature.
var _cells: MapImageCells
var _params: MapImageImportParams
var _width: int = 0
var _targets := PackedFloat32Array()
var _pins := PackedByteArray()
## Cell index -> the height a chasm cell's floor is sunk to.
var _chasm_floor: Dictionary = {}
## Corner index -> the water level of the bodies it is a shore of: a corner touching both water
## and dry ground.
var _shores: Dictionary = {}

## The finished heights, index z * (side + 1) + x.
var heights := PackedFloat32Array()
## Each cliff and ramp region: {kind: Meaning, cells: Array[Vector2i], drop, width, spread}.
var regions: Array[Dictionary] = []
#endregion


## Heights for `cells`, with `water`'s beds dug and `structures`' footprints flat. Cliff and
## ramp contradictions are added to `cells.errors`.
static func build(
	cells: MapImageCells,
	params: MapImageImportParams,
	water: MapImageWater,
	structures: MapImageStructures
) -> MapImageRelief:
	var relief := MapImageRelief.new()
	relief._cells = cells
	relief._params = params
	relief._width = cells.side + 1
	relief._sink_chasms()
	relief._corner_targets(water.beds, water.surfaces)
	relief._pin_regions(water.beds)
	relief._pin_footprints(structures)
	relief._roughen()
	relief.heights = relief._smoothed()
	relief._lower_shores()
	return relief


## Displace region edges by seeded noise (map-from-image.md §Terrain): each cell takes the
## terrain and water of a cell a small, smoothly varying distance away. The play area's edge,
## cliffs, ramps and structures are never moved — a cell drawn as one keeps what is under it,
## and no cell takes its terrain from one.
static func warp_edges(cells: MapImageCells, amplitude_cells: float, noise_seed: int) -> void:
	if amplitude_cells <= 0.0:
		return
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 1.0 / NOISE_WAVELENGTH_CELLS
	var terrain: PackedByteArray = cells.terrain.duplicate()
	var water: PackedByteArray = cells.water.duplicate()
	for i: int in cells.cell_count():
		var cell: Vector2i = cells.cell_of(i)
		if not _is_warp_target(cells, cell):
			continue
		# Two decorrelated samples of the one noise: x and z displacements.
		var shift := Vector2(
			noise.get_noise_2d(cell.x, cell.y), noise.get_noise_2d(cell.x + 1000.0, cell.y - 1000.0)
		)
		var source: Vector2i = cell + Vector2i((shift * amplitude_cells).round())
		if source == cell or not _is_warpable(cells, source):
			continue
		terrain[i] = cells.terrain[cells.index_of(source)]
		water[i] = cells.water[cells.index_of(source)]
	cells.terrain = terrain
	cells.water = water


static func _is_warpable(cells: MapImageCells, cell: Vector2i) -> bool:
	if not cells.is_in_play(cell):
		return false
	var index: int = cells.index_of(cell)
	return (
		cells.cliffs[index] == MapImagePalette.Meaning.NONE
		and cells.structures[index] == MapImagePalette.Meaning.NONE
	)


## Whether `cell` may take another cell's terrain: warpable, and not on a cliff's or ramp's rim,
## whose levels decide which way the region falls.
static func _is_warp_target(cells: MapImageCells, cell: Vector2i) -> bool:
	if not _is_warpable(cells, cell):
		return false
	for step: Vector2i in _EIGHT_NEIGHBOURS:
		var near: Vector2i = cell + step
		if (
			cells.has_cell(near)
			and cells.cliffs[cells.index_of(near)] != MapImagePalette.Meaning.NONE
		):
			return false
	return true


func corner_index(a_corner: Vector2i) -> int:
	return a_corner.y * _width + a_corner.x


## The target height of cell `a_index` before smoothing: its level, bed or floor. NAN for a cell
## out of play, which has none.
func cell_target(a_index: int, a_beds: Dictionary) -> float:
	if _cells.in_play[a_index] == 0:
		return NAN
	if a_beds.has(a_index):
		return a_beds[a_index]
	if _chasm_floor.has(a_index):
		return _chasm_floor[a_index]
	return _params.level_height(MapImagePalette.level_of(_cells.terrain[a_index]))


func is_dry(a_index: int, a_beds: Dictionary) -> bool:
	return (
		_cells.in_play[a_index] == 1 and not a_beds.has(a_index) and not _chasm_floor.has(a_index)
	)


#region Targets
## Each 4-connected chasm is sunk `chasm_depth` below its lowest rim.
func _sink_chasms() -> void:
	var seen := PackedByteArray()
	seen.resize(_cells.cell_count())
	for i: int in _cells.cell_count():
		if seen[i] == 1 or not _cells.is_chasm(_cells.cell_of(i)) or _cells.in_play[i] == 0:
			continue
		var patch: Array[Vector2i] = _flood(
			_cells.cell_of(i), seen, func(cell: Vector2i) -> bool: return _cells.is_chasm(cell)
		)
		var rim: float = INF
		for cell: Vector2i in patch:
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var level: int = _cells.level_at(cell + step)
				if level > 0 and _cells.is_in_play(cell + step):
					rim = minf(rim, _params.level_height(level))
		if rim == INF:
			rim = _params.level_height(1)
		for cell: Vector2i in patch:
			_chasm_floor[_cells.index_of(cell)] = rim - _params.generation.chasm_depth


func _corner_targets(a_beds: Dictionary, a_surfaces: Dictionary) -> void:
	var count: int = _width * _width
	_targets.resize(count)
	_pins.resize(count)
	var defined := PackedByteArray()
	defined.resize(count)
	for z: int in _width:
		for x: int in _width:
			var corner := Vector2i(x, z)
			var dry: float = -INF
			var wet: float = -INF
			var surface: float = INF
			var is_floor: bool = false
			var floor_height: float = INF
			for cell: Vector2i in _cells_of_corner(corner):
				var index: int = _cells.index_of(cell)
				if _cells.in_play[index] == 0:
					continue
				if is_dry(index, a_beds):
					dry = maxf(dry, cell_target(index, a_beds))
				elif a_beds.has(index):
					# Between two beds the shallower wins, so a ford beside deep water is not
					# dug past wading at its edge, while deep water keeps its other corners.
					wet = maxf(wet, a_beds[index])
					surface = minf(surface, a_surfaces[index])
				else:
					is_floor = true
					floor_height = minf(floor_height, _chasm_floor[index])
			var k: int = corner_index(corner)
			if is_floor:
				# A chasm's corners are all floor, its rim included, as the generator sinks
				# one: otherwise a chasm a cell wide would keep its rim's height and be ground.
				_targets[k] = floor_height
				if posmod(x + z, 2) == 1:
					_targets[k] -= MapGenerationParams.RIDGE_ROUGHNESS
				_pins[k] = Pin.KEPT_UNSAMPLED
			elif dry > -INF:
				_targets[k] = dry
				if surface < INF:
					_shores[k] = surface
			elif wet > -INF:
				# A bed is held out of the blur both ways: smoothed, a ford beside deep water
				# would be dug past wading, and the bank above a deep bed would sag into it.
				_targets[k] = wet
				_pins[k] = Pin.KEPT_UNSAMPLED
			else:
				continue
			defined[k] = 1
	_fill_undefined(defined)


## Corners touching no cell in play take their nearest defined neighbour's target, so the blur
## near the play edge averages ground rather than zero.
func _fill_undefined(a_defined: PackedByteArray) -> void:
	var frontier: Array[Vector2i] = []
	for k: int in a_defined.size():
		if a_defined[k] == 1:
			frontier.append(Vector2i(k % _width, k / _width))
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for corner: Vector2i in frontier:
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = corner + step
				if near.x < 0 or near.y < 0 or near.x >= _width or near.y >= _width:
					continue
				var k: int = corner_index(near)
				if a_defined[k] == 0:
					a_defined[k] = 1
					_targets[k] = _targets[corner_index(corner)]
					next.append(near)
		frontier = next


#endregion


#region Pins
## Grade every cliff and ramp region, and check its verdict.
func _pin_regions(a_beds: Dictionary) -> void:
	var seen := PackedByteArray()
	seen.resize(_cells.cell_count())
	for i: int in _cells.cell_count():
		var kind: int = _cells.cliffs[i]
		if (
			seen[i] == 1
			or kind == MapImagePalette.Meaning.NONE
			or kind == MapImagePalette.Meaning.ROUGH
		):
			continue
		var patch: Array[Vector2i] = _flood(
			_cells.cell_of(i),
			seen,
			func(cell: Vector2i) -> bool: return _cells.cliffs[_cells.index_of(cell)] == kind,
			_EIGHT_NEIGHBOURS
		)
		_pin_region(kind, patch, a_beds)


func _pin_region(a_kind: int, a_patch: Array[Vector2i], a_beds: Dictionary) -> void:
	var in_patch: Dictionary = {}
	for cell: Vector2i in a_patch:
		in_patch[cell] = true
	var rim: Array[Dictionary] = []
	for cell: Vector2i in a_patch:
		for step: Vector2i in _EIGHT_NEIGHBOURS:
			var near: Vector2i = cell + step
			if in_patch.has(near) or not _cells.is_in_play(near):
				continue
			in_patch[near] = false
			rim.append({cell = near, height = cell_target(_cells.index_of(near), a_beds)})
	var high: float = -INF
	var low: float = INF
	for entry: Dictionary in rim:
		high = maxf(high, entry.height)
		low = minf(low, entry.height)
	var region: Dictionary = {
		kind = a_kind, cells = a_patch, drop = 0.0, width = 0.0, spread = 0.0, walkable = []
	}
	regions.append(region)
	if rim.is_empty() or is_zero_approx(high - low):
		var flat: float = high if not rim.is_empty() else _params.level_height(1)
		for corner: Vector2i in _corners_of_cells(a_patch):
			_pin(corner, flat, a_kind)
		region.walkable = a_patch
	else:
		region.drop = high - low
		if a_kind == MapImagePalette.Meaning.CLIFF:
			_grade_cliff(region, rim, lerpf(low, high, _HALF))
		else:
			_grade_ramp(region, rim, low, high)
	_judge(region)


## A cliff falls from its high rim to its low rim across its own thickness, wherever it is
## drawn: each corner is graded by its distances to the two sides, measured through the region,
## so a long, curving or uneven line is judged by its width at each point. A corner on both
## sides at once — a cliff's tip — takes the high side, the generator's rule for a step.
func _grade_cliff(a_region: Dictionary, a_rim: Array[Dictionary], a_middle: float) -> void:
	var corners: Array[Vector2i] = _corners_of_cells(a_region.cells)
	var high_rim: Array[Dictionary] = []
	var low_rim: Array[Dictionary] = []
	for entry: Dictionary in a_rim:
		if entry.height > a_middle:
			high_rim.append(entry)
		else:
			low_rim.append(entry)
	var from_high: Dictionary = _distances_from(corners, high_rim)
	var from_low: Dictionary = _distances_from(corners, low_rim)
	for corner: Vector2i in corners:
		var high: Vector2 = from_high.get(corner, Vector2(INF, 0.0))
		var low: Vector2 = from_low.get(corner, Vector2(INF, 0.0))
		var height: float = low.y
		if not is_inf(high.x) and (is_inf(low.x) or high.x == 0.0):
			height = high.y
		elif not is_inf(high.x):
			height = lerpf(low.y, high.y, low.x / (low.x + high.x))
		_pin(corner, height, a_region.kind)
	var spreads: Array[float] = []
	for cell: Vector2i in a_region.cells:
		var spread: float = _pinned_spread(cell)
		spreads.append(spread)
		if spread <= TerrainGrid.MAX_SLOPE_DIFF:
			a_region.walkable.append(cell)
	spreads.sort()
	# The typical face, for the report: the median cell's spread.
	a_region.spread = spreads[spreads.size() / 2]


## A ramp is one plane, graded linearly from its low rim to its high rim along the direction its
## rim rises — the least-squares slope through the rim's heights, so a short end does not tilt
## it — across the region's whole extent in that direction.
func _grade_ramp(
	a_region: Dictionary, a_rim: Array[Dictionary], a_low: float, a_high: float
) -> void:
	var direction: Vector2 = _rim_gradient(a_rim).normalized()
	var corners: Array[Vector2i] = _corners_of_cells(a_region.cells)
	var least: float = INF
	var most: float = -INF
	for corner: Vector2i in corners:
		least = minf(least, Vector2(corner).dot(direction))
		most = maxf(most, Vector2(corner).dot(direction))
	var width: float = maxf(most - least, 1.0)
	for corner: Vector2i in corners:
		var along: float = (Vector2(corner).dot(direction) - least) / width
		_pin(corner, lerpf(a_low, a_high, along), a_region.kind)
	a_region.width = width
	# A plane's spread over one cell is its gradient's |x| + |z|.
	a_region.spread = (a_high - a_low) / width * (absf(direction.x) + absf(direction.y))


## The horizontal gradient of the plane fitted to the rim's heights by least squares.
func _rim_gradient(a_rim: Array[Dictionary]) -> Vector2:
	var mean := Vector3.ZERO
	for entry: Dictionary in a_rim:
		mean += Vector3(entry.cell.x, entry.cell.y, entry.height)
	mean /= a_rim.size()
	var sxx: float = 0.0
	var sxz: float = 0.0
	var szz: float = 0.0
	var sxh: float = 0.0
	var szh: float = 0.0
	for entry: Dictionary in a_rim:
		var dx: float = entry.cell.x - mean.x
		var dz: float = entry.cell.y - mean.y
		var dh: float = entry.height - mean.z
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
		sxh += dx * dh
		szh += dz * dh
	var determinant: float = sxx * szz - sxz * sxz
	if is_zero_approx(determinant):
		return Vector2(sxh, szh)
	return Vector2(szz * sxh - sxz * szh, sxx * szh - sxz * sxh) / determinant


## Corner -> Vector2(distance in corner steps, height) from the nearest of `a_rim`'s cells,
## walking only through `a_corners`. A corner a rim cell touches is at distance 0, taking the
## highest such cell.
func _distances_from(a_corners: Array[Vector2i], a_rim: Array[Dictionary]) -> Dictionary:
	var members: Dictionary = {}
	for corner: Vector2i in a_corners:
		members[corner] = true
	var out: Dictionary = {}
	for entry: Dictionary in a_rim:
		for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var corner: Vector2i = entry.cell + step
			if members.has(corner) and entry.height > out.get(corner, Vector2(0.0, -INF)).y:
				out[corner] = Vector2(0.0, entry.height)
	var frontier: Array[Vector2i] = []
	frontier.assign(out.keys())
	var distance: float = 0.0
	while not frontier.is_empty():
		distance += 1.0
		var next: Array[Vector2i] = []
		for corner: Vector2i in frontier:
			for step: Vector2i in _FOUR_NEIGHBOURS:
				var near: Vector2i = corner + step
				if members.has(near) and not out.has(near):
					out[near] = Vector2(distance, out[corner].y)
					next.append(near)
		frontier = next
	return out


func _pinned_spread(a_cell: Vector2i) -> float:
	var lowest: float = INF
	var highest: float = -INF
	for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var height: float = _targets[corner_index(a_cell + step)]
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	return highest - lowest


func _judge(a_region: Dictionary) -> void:
	var limit: float = TerrainGrid.MAX_SLOPE_DIFF
	if a_region.kind == MapImagePalette.Meaning.CLIFF:
		if a_region.walkable.is_empty():
			return
		var walkable: Array[Vector2i] = []
		walkable.assign(
			a_region.walkable.map(func(cell: Vector2i) -> Vector2i: return _cells.pixel_of(cell))
		)
		_cells.add_error(
			(
				(
					"cliffs: %d cells of a cliff dropping %.2f are walkable (the limit is %.2f a "
					+ "cell) — too wide there, or across too small a drop: a cliff needs two "
					+ "levels and a thin line. Draw it thinner, or as a ramp: %s"
				)
				% [walkable.size(), a_region.drop, limit, MapImageCells.describe_pixels(walkable)]
			),
			walkable
		)
	elif a_region.spread > limit:
		var pixels: Array[Vector2i] = []
		pixels.assign(
			a_region.cells.map(func(cell: Vector2i) -> Vector2i: return _cells.pixel_of(cell))
		)
		(
			_cells
			. add_error(
				(
					(
						"cliffs: a ramp drops %.2f across %.1f cells, a grade of %.2f a cell — too "
						+ "steep to walk (the limit is %.2f); draw it wider: %s"
					)
					% [
						a_region.drop,
						a_region.width,
						a_region.spread,
						limit,
						MapImageCells.describe_pixels(pixels),
					]
				),
				pixels
			)
		)


## A cliff corner is kept out of the blur's average; a ramp's is sampled, so the ground beside a
## ramp grades into it.
## Rough ground (map-from-image.md §Terrain): every corner that only rough cells touch is pushed
## up or down by ROUGH_RISE, alternately, and held out of the blur, so each cell touching one is
## steeper than anything walks. A corner a cell of any other kind shares is left alone, so rough
## ground never makes its neighbours steep — and a rough patch must be two cells wide somewhere
## to hold such a corner at all. A corner something else already pinned keeps its pin.
func _roughen() -> void:
	for z: int in _width:
		for x: int in _width:
			var corner := Vector2i(x, z)
			var k: int = corner_index(corner)
			if _pins[k] != Pin.FREE or not _is_only_rough(corner):
				continue
			_targets[k] += ROUGH_RISE if posmod(x + z, 2) == 0 else -ROUGH_RISE
			_pins[k] = Pin.KEPT_UNSAMPLED


## Whether every cell in play touching `a_corner` is drawn rough, and one at least is.
func _is_only_rough(a_corner: Vector2i) -> bool:
	var any: bool = false
	for step: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var cell: Vector2i = a_corner + step
		if not _cells.is_in_play(cell):
			continue
		if _cells.cliffs[_cells.index_of(cell)] != MapImagePalette.Meaning.ROUGH:
			return false
		any = true
	return any


func _pin(a_corner: Vector2i, a_height: float, a_kind: int) -> void:
	var k: int = corner_index(a_corner)
	_targets[k] = a_height
	_pins[k] = (Pin.KEPT_UNSAMPLED if a_kind == MapImagePalette.Meaning.CLIFF else Pin.KEPT)


func _pin_footprints(a_structures: MapImageStructures) -> void:
	for placement: Dictionary in a_structures.placements:
		var rect: Rect2i = MapFeature.placement_rect(placement)
		var height: float = _params.level_height(placement.level)
		for z: int in range(rect.position.y, rect.end.y + 1):
			for x: int in range(rect.position.x, rect.end.x + 1):
				var k: int = corner_index(Vector2i(x, z))
				_targets[k] = height
				_pins[k] = Pin.KEPT


#endregion


#region Smoothing
## Hold every free shore corner SHORE_DIP under its water, after smoothing: so each drawn water
## cell has every corner below the level and is wet, a cell wide or not, while a bank cell keeps
## at least two corners above it and stays dry.
func _lower_shores() -> void:
	for k: int in _shores:
		if _pins[k] == Pin.FREE:
			heights[k] = minf(heights[k], _shores[k] - SHORE_DIP)


## The masked box blur: separable, with each corner's sum and sampled-corner count carried
## through both passes, so the result is the exact mean over the sampled corners in its square.
func _smoothed() -> PackedFloat32Array:
	var radius: int = _params.smoothing_radius
	var out: PackedFloat32Array = _targets.duplicate()
	if radius <= 0:
		return out
	var count: int = _width * _width
	var row_sum := PackedFloat32Array()
	var row_weight := PackedFloat32Array()
	row_sum.resize(count)
	row_weight.resize(count)
	for z: int in _width:
		for x: int in _width:
			var sum: float = 0.0
			var weight: float = 0.0
			for d: int in range(-radius, radius + 1):
				var k: int = z * _width + clampi(x + d, 0, _width - 1)
				if _pins[k] != Pin.KEPT_UNSAMPLED:
					sum += _targets[k]
					weight += 1.0
			row_sum[z * _width + x] = sum
			row_weight[z * _width + x] = weight
	for z: int in _width:
		for x: int in _width:
			var k: int = z * _width + x
			if _pins[k] != Pin.FREE:
				continue
			var sum: float = 0.0
			var weight: float = 0.0
			for d: int in range(-radius, radius + 1):
				var j: int = clampi(z + d, 0, _width - 1) * _width + x
				sum += row_sum[j]
				weight += row_weight[j]
			if weight > 0.0:
				out[k] = sum / weight
	return out


#endregion


#region Grid
## The up-to-four cells a corner touches, in bounds.
func _cells_of_corner(a_corner: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for step: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		if _cells.has_cell(a_corner + step):
			out.append(a_corner + step)
	return out


func _corners_of_cells(a_cells: Array[Vector2i]) -> Array[Vector2i]:
	var seen: Dictionary = {}
	for cell: Vector2i in a_cells:
		for step: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			seen[cell + step] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


func _flood(
	a_start: Vector2i,
	a_seen: PackedByteArray,
	a_member: Callable,
	a_steps: Array[Vector2i] = _FOUR_NEIGHBOURS
) -> Array[Vector2i]:
	var patch: Array[Vector2i] = []
	var frontier: Array[Vector2i] = [a_start]
	a_seen[_cells.index_of(a_start)] = 1
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		patch.append(cell)
		for step: Vector2i in a_steps:
			var near: Vector2i = cell + step
			if not _cells.has_cell(near):
				continue
			var index: int = _cells.index_of(near)
			if a_seen[index] == 0 and a_member.call(near):
				a_seen[index] = 1
				frontier.append(near)
	return patch
#endregion
