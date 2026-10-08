class_name NavPlacement
extends RefCounted

## WHERE A BUILDING MAY GO WITHOUT BREAKING THE MAP FOR THE UNITS ON IT.
##
## Three rules, all about navigation rather than about geometry (`Fixture.valid_placement`
## already owns in-bounds / unoccupied / flat):
##
##   1. **A placement may not split the walkable surface.** A footprint that seals a corridor
##      strands whatever is on the far side of it — including the builder that placed it.
##   2. **A structure units must reach needs a side on the navmesh.** A production building
##      whose four sides are all walls can train units that have nowhere to appear, which is
##      what the reported match looked like.
##   3. **Both again, for a wider unit** (`accepts_for_class`): the first two ask about
##      passable cells, which is the narrowest unit's view of the map. See §Rule 3.
##
## LIVES IN THE MAP LAYER ON PURPOSE. The bot is the first caller, but neither rule is a bot
## preference — they are facts about the map, and the human player's placement validation
## wants the same answers. Nothing here reads a Commander, a Bot or a difficulty.
##
## ## Why this is cheap, and what it replaced
##
## `TerrainGrid.placement_preserves_connectivity` answers rule 1 by flood-filling the whole
## passable set TWICE per candidate cell. Profiled at **67-133 ms**, it was one of only 13
## ticks in 29,432 that blew the 33 ms frame budget, and the bot ran it on every candidate of
## a ring scan.
##
## The observation that makes it local: blocking a footprint can only disconnect cells that
## were connected THROUGH it, and every such path enters and leaves through a cell 4-adjacent
## to the footprint — a GATE. So the placement is safe exactly when the gates can still reach
## each other with the footprint blocked. Gates are typically 1-3 cells apart around a corner,
## so the search visits a handful of cells rather than the map.
##
## Two facts keep the local search honest:
##
##   * **Gates in different regions are not each other's problem.** On a map already split by
##     terrain, two gates may never have been connected; reconnecting them is not required and
##     looking for a route between them would cost a whole region's walk for nothing.
##     `TerrainGrid.component_at` labels the regions once per `cells_changed` (alongside the
##     clearance and distance fields the navmesh already pays for), so grouping the gates is
##     O(1) per gate.
##   * **The walk stays inside one region and stops at a budget.** `DETOUR_BUDGET` bounds the
##     worst case — a footprint that really is a cut across a large region. Exhausting the
##     budget REJECTS the placement, which is the conservative direction: the caller loses a
##     candidate, never the map.
##
## `TerrainGrid.placement_preserves_connectivity` is kept as the brute-force reference the
## tests check this against; nothing in the game should call it on a hot path.

#region Constants
## 4-neighbour, matching how the navmesh stitches adjacent cells and how the region labels
## are grown. Diagonal slips are not paths here.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## Cells the detour search may expand before it gives up and rejects the placement. Sized far
## above what walking around a building costs (a 4x4 footprint's gates reconnect in under 20)
## and far below a region walk on a 120x120 map, so hitting it means the footprint really is
## a cut across something large — exactly the case worth refusing.
const DETOUR_BUDGET: int = 400
#endregion


#region Rule 1 — the placement may not split the walkable surface
## True when occupying `a_footprint` leaves every pair of cells that could reach each other
## still able to reach each other.
##
## `a_grid` is a TerrainGrid; `a_footprint` an Array of Vector2i (what
## `Map.footprint_cells` returns). Cells of the footprint that are already impassable cost
## nothing — blocking a wall changes no path.
static func preserves_connectivity(
	a_grid: TerrainGrid, a_footprint: Array, a_budget: int = DETOUR_BUDGET
) -> bool:
	var inside: Dictionary = {}
	var blocks_something: bool = false
	for cell: Vector2i in a_footprint:
		inside[cell] = true
		if a_grid.is_passable(cell):
			blocks_something = true
	if not blocks_something:
		return true

	var gates: Array = gate_cells(a_grid, a_footprint)
	# Nothing to reconnect: a footprint with one way in and out is a dead end, and a footprint
	# with none is an island whose removal takes a region away rather than adding one.
	if gates.size() <= 1:
		return true

	var by_region: Dictionary = {}
	for gate: Vector2i in gates:
		var region: int = a_grid.component_at(gate)
		if not by_region.has(region):
			by_region[region] = []
		by_region[region].append(gate)

	for region: int in by_region:
		var group: Array = by_region[region]
		if group.size() < 2:
			continue  # a lone gate in its region was never a route to anything through here
		if not _gates_reconnect(a_grid, inside, region, group, a_budget):
			return false
	return true


## Passable cells 4-adjacent to the footprint but outside it — every route that used the
## footprint entered and left through one of these.
static func gate_cells(a_grid: TerrainGrid, a_footprint: Array) -> Array:
	var inside: Dictionary = {}
	for cell: Vector2i in a_footprint:
		inside[cell] = true
	var gates: Dictionary = {}
	for cell: Vector2i in a_footprint:
		for step: Vector2i in NEIGHBOURS:
			var neighbour: Vector2i = cell + step
			if inside.has(neighbour) or gates.has(neighbour):
				continue
			if a_grid.is_passable(neighbour):
				gates[neighbour] = true
	return gates.keys()


## Breadth-first walk from the first gate through `a_region`'s cells MINUS the footprint,
## stopping the moment every other gate in the group has been reached. Breadth-first rather
## than depth-first because the answer is almost always two cells away around a corner, and a
## depth-first walk would wander the region to find it.
static func _gates_reconnect(
	a_grid: TerrainGrid, a_inside: Dictionary, a_region: int, a_group: Array, a_budget: int
) -> bool:
	var wanted: Dictionary = {}
	for i: int in range(1, a_group.size()):
		wanted[a_group[i]] = true
	var queue: Array = [a_group[0]]
	var seen: Dictionary = {a_group[0]: true}
	var head: int = 0
	while head < queue.size():
		if head >= a_budget:
			return false  # conservative: a cut this large is refused rather than paid for
		var cell: Vector2i = queue[head]
		head += 1
		for step: Vector2i in NEIGHBOURS:
			var neighbour: Vector2i = cell + step
			if seen.has(neighbour) or a_inside.has(neighbour):
				continue
			if a_grid.component_at(neighbour) != a_region:
				continue
			seen[neighbour] = true
			if wanted.erase(neighbour) and wanted.is_empty():
				return true
			queue.append(neighbour)
	return wanted.is_empty()


#endregion


#region Rule 2 — a structure units must reach needs a side on the navmesh
## How many of the footprint's four sides are FULLY on walkable ground — every cell along
## that edge passable, and (when `a_reference_region` is not -1) in the same region as the
## reference.
##
## A whole SIDE rather than a single cell, because that is the shape of the requirement: a
## unit leaving a production building needs somewhere to stand, and one diagonal-ish cell
## poking out between two walls is a gap a unit cannot reliably use. -1 means "any walkable
## ground at all", which is what a caller with no owner to measure against wants.
static func exposed_side_count(
	a_grid: TerrainGrid, a_footprint: Array, a_reference_region: int = -1
) -> int:
	if a_footprint.is_empty():
		return 0
	var min_cell: Vector2i = a_footprint[0]
	var max_cell: Vector2i = a_footprint[0]
	for cell: Vector2i in a_footprint:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	var sides: Array = [
		[Vector2i(min_cell.x - 1, min_cell.y), Vector2i(0, 1), max_cell.y - min_cell.y + 1],
		[Vector2i(max_cell.x + 1, min_cell.y), Vector2i(0, 1), max_cell.y - min_cell.y + 1],
		[Vector2i(min_cell.x, min_cell.y - 1), Vector2i(1, 0), max_cell.x - min_cell.x + 1],
		[Vector2i(min_cell.x, max_cell.y + 1), Vector2i(1, 0), max_cell.x - min_cell.x + 1],
	]
	var count: int = 0
	for side: Array in sides:
		if _side_is_walkable(a_grid, side[0], side[1], side[2], a_reference_region):
			count += 1
	return count


## True when the structure has at least one whole side on walkable ground reachable from
## `a_reference_region` — the rule a PRODUCTION building has to meet, so the units it makes
## have somewhere to come out to.
static func has_navmesh_side(
	a_grid: TerrainGrid, a_footprint: Array, a_reference_region: int = -1
) -> bool:
	return exposed_side_count(a_grid, a_footprint, a_reference_region) > 0


static func _side_is_walkable(
	a_grid: TerrainGrid, a_start: Vector2i, a_step: Vector2i, a_length: int, a_region: int
) -> bool:
	for i: int in a_length:
		var cell: Vector2i = a_start + a_step * i
		if not a_grid.is_passable(cell):
			return false
		if a_region >= 0 and a_grid.component_at(cell) != a_region:
			return false
	return true


#endregion

#region Rule 3 — the same two rules, as a wide unit sees them
## Rules 1 and 2 ask about PASSABLE cells, which is how the narrowest unit sees the map: a
## one-cell gap is a route to it. A unit of a wider NavAgentClass walks its own eroded mesh,
## where that gap does not exist, so a placement rules 1 and 2 accept can still cut a wide
## unit's route or leave a building it must reach standing in a gap it cannot enter. A bot
## packing buildings round its Compound did both to its own Stock Trucks.
##
## Asked by recomputing the class gate (TerrainGrid.is_navigable_for) with the footprint
## blocked, but only in the band the footprint can change — `_class_band` cells — and reading
## the grid's precomputed answer everywhere else. The structure of the connectivity test is
## rule 1's: gates round the band, grouped by how they connect through it now, each group
## required to reconnect afterwards, with a budget whose exhaustion refuses the placement.

## Cells a wide unit's detour may expand before the placement is refused. Larger than
## DETOUR_BUDGET because a wide unit's way round is longer: it cannot slip through the gaps
## between buildings that keep a narrow unit's detour short.
const CLASS_DETOUR_BUDGET: int = 1600


## True when blocking `a_footprint` leaves the class `a_nav_class` able to go everywhere it
## could before, and leaves every nearby building it could reach still reachable — and, when
## `a_needs_access`, gives the new building a place that class can reach it from.
static func accepts_for_class(
	a_grid: TerrainGrid, a_footprint: Array, a_nav_class: int, a_needs_access: bool = false
) -> bool:
	if a_footprint.is_empty():
		return false
	var probe := _ClassProbe.new(a_grid, a_footprint, a_nav_class)
	if a_needs_access and not probe.has_access(a_footprint, true):
		return false
	if not probe.neighbours_keep_access():
		return false
	return probe.preserves_connectivity(CLASS_DETOUR_BUDGET)


## Navigability for one size class, before and after a hypothetical footprint is blocked.
class _ClassProbe:
	var _grid: TerrainGrid
	var _blocked: Dictionary = {}
	var _rings: int
	var _admit_k: int
	## How far the footprint's influence on navigability reaches, in cells: the class gate
	## looks `rings` cells out for an obstacle and `admit_k - 1` cells out for a clear block.
	var _band: int
	## How far from a footprint, in cells, a class cell still counts as reaching it — a cell
	## centre within the class's standoff (SU.class_standoff_reach) of the footprint's edge.
	var _access: int
	var _min: Vector2i
	var _max: Vector2i

	func _init(a_grid: TerrainGrid, a_footprint: Array, a_nav_class: int) -> void:
		_grid = a_grid
		_rings = NavAgentClass.erosion_rings(a_nav_class, Map.CELL_SIZE)
		_admit_k = NavAgentClass.required_clearance(a_nav_class, Map.CELL_SIZE)
		_band = maxi(_rings, _admit_k - 1)
		_access = floori(SU.class_standoff_reach(a_nav_class) / Map.CELL_SIZE + 0.5)
		_min = a_footprint[0]
		_max = a_footprint[0]
		for cell: Vector2i in a_footprint:
			_blocked[cell] = true
			_min = Vector2i(mini(_min.x, cell.x), mini(_min.y, cell.y))
			_max = Vector2i(maxi(_max.x, cell.x), maxi(_max.y, cell.y))

	## Chebyshev distance from `a_cell` to the footprint's bounding box (0 inside it).
	func _distance(a_cell: Vector2i) -> int:
		var dx: int = maxi(maxi(_min.x - a_cell.x, a_cell.x - _max.x), 0)
		var dz: int = maxi(maxi(_min.y - a_cell.y, a_cell.y - _max.y), 0)
		return maxi(dx, dz)

	func before(a_cell: Vector2i) -> bool:
		return _grid.is_navigable_for(a_cell, _rings, _admit_k)

	func after(a_cell: Vector2i) -> bool:
		if _blocked.has(a_cell):
			return false
		if _distance(a_cell) > _band:
			return before(a_cell)
		for dz: int in range(-_rings, _rings + 1):
			for dx: int in range(-_rings, _rings + 1):
				if not _clear(a_cell + Vector2i(dx, dz)):
					return false
		if _admit_k <= 1:
			return true
		for az: int in range(a_cell.y - _admit_k + 1, a_cell.y + 1):
			for ax: int in range(a_cell.x - _admit_k + 1, a_cell.x + 1):
				if _block_clear(Vector2i(ax, az)):
					return true
		return false

	func _clear(a_cell: Vector2i) -> bool:
		return _grid.is_passable(a_cell) and not _blocked.has(a_cell)

	func _block_clear(a_anchor: Vector2i) -> bool:
		for dz: int in _admit_k:
			for dx: int in _admit_k:
				if not _clear(a_anchor + Vector2i(dx, dz)):
					return false
		return true

	## Whether some class-navigable cell lies within `_access` of `a_cells`' bounding box.
	func has_access(a_cells: Array, a_after: bool) -> bool:
		var lo: Vector2i = a_cells[0]
		var hi: Vector2i = a_cells[0]
		for cell: Vector2i in a_cells:
			lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
			hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
		for z: int in range(lo.y - _access, hi.y + _access + 1):
			for x: int in range(lo.x - _access, hi.x + _access + 1):
				var cell := Vector2i(x, z)
				if after(cell) if a_after else before(cell):
					return true
		return false

	## Every registered building close enough to be affected, that a class unit could reach
	## before, can still be reached after.
	func neighbours_keep_access() -> bool:
		var reach: int = _band + _access
		for building: Object in _grid.buildings():
			var cells: Array = _grid.get_building_cells(building)
			if cells.is_empty() or _blocked.has(cells[0]):
				continue
			var near: bool = false
			for cell: Vector2i in cells:
				if _distance(cell) <= reach:
					near = true
					break
			if near and has_access(cells, false) and not has_access(cells, true):
				return false
		return true

	## Rule 1 for this class: gates just outside the band, grouped by how they connect
	## through it now, must each still reach their group once the footprint is blocked.
	func preserves_connectivity(a_budget: int) -> bool:
		var gate_ring: int = _band + 1
		var gates: Array = []
		for z: int in range(_min.y - gate_ring, _max.y + gate_ring + 1):
			for x: int in range(_min.x - gate_ring, _max.x + gate_ring + 1):
				var cell := Vector2i(x, z)
				if _distance(cell) == gate_ring and before(cell):
					gates.append(cell)
		if gates.size() <= 1:
			return true
		var grouped: Dictionary = {}
		for gate: Vector2i in gates:
			if grouped.has(gate):
				continue
			var group: Array = _local_group(gate, gate_ring)
			for member: Vector2i in group:
				grouped[member] = true
			if group.size() >= 2 and not _reconnects(group, a_budget):
				return false
		return true

	## The gates reachable from `a_gate` through cells navigable NOW, inside the gate ring.
	func _local_group(a_gate: Vector2i, a_gate_ring: int) -> Array:
		var group: Array = [a_gate]
		var seen: Dictionary = {a_gate: true}
		var queue: Array = [a_gate]
		var head: int = 0
		while head < queue.size():
			var cell: Vector2i = queue[head]
			head += 1
			for step: Vector2i in NEIGHBOURS:
				var next: Vector2i = cell + step
				if seen.has(next) or _distance(next) > a_gate_ring or not before(next):
					continue
				seen[next] = true
				queue.append(next)
				if _distance(next) == a_gate_ring:
					group.append(next)
		return group

	func _reconnects(a_group: Array, a_budget: int) -> bool:
		var wanted: Dictionary = {}
		for i: int in range(1, a_group.size()):
			wanted[a_group[i]] = true
		var queue: Array = [a_group[0]]
		var seen: Dictionary = {a_group[0]: true}
		var head: int = 0
		while head < queue.size():
			if head >= a_budget:
				return false
			var cell: Vector2i = queue[head]
			head += 1
			for step: Vector2i in NEIGHBOURS:
				var next: Vector2i = cell + step
				if seen.has(next) or not after(next):
					continue
				seen[next] = true
				if wanted.erase(next) and wanted.is_empty():
					return true
				queue.append(next)
		return wanted.is_empty()


#endregion


#region The two rules together
## The whole navigation verdict on a placement: it does not wall anything off, and — when
## `a_needs_access` — it keeps a side on walkable ground reachable from `a_reference_region`.
##
## The order is the cost order: the side test is a handful of byte reads, the connectivity
## test a bounded walk, so the cheap one runs first.
static func accepts(
	a_grid: TerrainGrid,
	a_footprint: Array,
	a_needs_access: bool = false,
	a_reference_region: int = -1
) -> bool:
	if a_footprint.is_empty():
		return false
	if a_needs_access and not has_navmesh_side(a_grid, a_footprint, a_reference_region):
		return false
	return preserves_connectivity(a_grid, a_footprint)
#endregion
