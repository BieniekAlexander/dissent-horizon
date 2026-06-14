@tool
class_name GraphPlateauHeightmapGenerator
extends HeightmapGenerator

## Red Alert 2-style terrain: large flat plateaus at discrete elevation tiers,
## separated by hard cliffs, with explicit RAMPS carved between adjacent plateaus
## so the whole playable area is guaranteed connected.
##
## Pipeline (see design notes):
##   1. Scatter `region_count` Voronoi seeds  → organic plateau shapes.
##   2. One corner pass assigns each corner its nearest seed and records the
##      (nearest, second-nearest) pairs — that set IS the region-adjacency graph.
##   3. A random spanning tree of that graph assigns each region an integer level
##      (each tree edge keeps the level or steps it by exactly ±1).  Because every
##      region hangs off the tree, the ramp+seam network spans all plateaus.
##   4. Tree edges whose level changed become RAMPS (plus optional loop ramps).
##   5. Heights: every corner = level*height_step (hard cliffs everywhere), then
##      each ramp is carved as an explicit channel along the segment between its
##      two seeds.  Two Voronoi-adjacent seeds form a Delaunay edge, so that
##      segment crosses exactly their shared border — the channel is a clean notch
##      through the cliff, independent of triple-junction geometry.
##
## Passability is emergent, via TerrainGrid: a cell is impassable when its four
## corner heights span more than MAX_SLOPE_DIFF (0.5 raw units).
##   * A bare one-level step (height_step) is a CLIFF when height_step > 0.5.
##   * A ramp spreads that rise over `ramp_run` corners, so the slope is
##     height_step / ramp_run per corner.  A diagonal channel can compound the
##     axis slopes by up to ~sqrt(2), so keep
##         ramp_run >= 3 * height_step       (e.g. height_step 1.0 → ramp_run >= 3)
##     to keep the steepest ramp cell passable.

#region Properties
## Number of Voronoi regions (plateaus).  Used directly when cells_per_region <= 0.
@export var region_count: int = 14

## Target average plateau size, in cells.  When > 0 it OVERRIDES region_count:
## the region count is derived from the map area so feature size stays consistent
## as the map grows (a 120×120 map gets ~16× the regions of a 30×30 one rather
## than 16×-bigger plateaus).  This is the knob that makes larger maps look right.
## Set to 0 to control region_count directly.
@export var cells_per_region: int = 0

## Number of distinct elevation tiers (levels 0 … height_levels-1).
@export var height_levels: int = 3

## Height increment per tier in HeightMapShape3D local space.
@export var height_step: float = 1.0

## Length, in heightmap corners, of a ramp's sloped section (the climb direction).
## Larger = gentler, longer slopes.  Keep >= 3*height_step so ramp cells stay
## passable.  This is the STEEPNESS knob, independent of width.
@export var ramp_run: int = 4

## Half-width of a ramp, across the climb direction.  The walkable throat is
## roughly 2*this cells, so 2.5 yields a ~5-cell-wide ramp — enough lateral room
## for unit columns and structure footprints to use plateau connections.
## This is the WIDTH knob.  Both the graph ramps and the connectivity-repair
## corridors honour it, so every plateau connection is ~the same width.
@export var ramp_half_width: float = 2.5

## Probability that a spanning-tree edge changes elevation (becomes a ramp/cliff)
## rather than staying a flat seam.  Lower = flatter maps with fewer tiers in use.
@export_range(0.0, 1.0) var elevation_change_chance: float = 0.7

## Probability that a NON-tree single-level adjacency also becomes a ramp,
## adding loops/shortcuts on top of the minimal spanning-tree connectivity.
@export_range(0.0, 1.0) var loop_ramp_chance: float = 0.25

## When true, a final repair pass carves extra corridors until the passable
## surface is a single connected component.  This is the playability guarantee;
## disable only to inspect the raw graph output.
@export var guarantee_connected: bool = true

@export var seed: int = 0
#endregion

#region Public API
## Effective region count: derived from cells_per_region when that is set (so
## plateau size stays constant across map sizes), else the explicit region_count.
func _resolved_region_count() -> int:
	if cells_per_region > 0:
		var cells: int = (width - 1) * (depth - 1)
		return clampi(roundi(float(cells) / float(cells_per_region)), 1, maxi(1, cells))
	return region_count

func generate() -> PackedFloat32Array:
	# Resolve the area-scaled region count by temporarily standing in for
	# region_count, which the algorithm and its helpers read directly.
	var saved_region_count: int = region_count
	region_count = _resolved_region_count()
	var result: PackedFloat32Array = _generate_impl()
	region_count = saved_region_count
	return result
#endregion

#region Private helpers
func _generate_impl() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(width * depth)

	if region_count <= 0:
		return data  # all zeros — flat map

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# --- 1. Scatter seeds ---------------------------------------------------
	var seeds: Array[Vector2] = []
	for _i: int in region_count:
		seeds.append(Vector2(
			rng.randf_range(0.0, float(width - 1)),
			rng.randf_range(0.0, float(depth - 1))
		))

	# --- 2. Corner pass: nearest seed + weighted adjacency graph ------------
	var nearest := PackedInt32Array()
	nearest.resize(width * depth)

	# adjacency[region] = set of neighbour regions.
	# border_weight[edge_key] = number of corners sitting on that pair's border,
	# i.e. an estimate of the shared-border LENGTH.  Fat borders survive the
	# discrete cell grid; thin ones (sub-cell / diagonal-only) do not.
	var adjacency: Dictionary = {}
	for i: int in region_count:
		adjacency[i] = {}
	var border_weight: Dictionary = {}

	for z: int in depth:
		for x: int in width:
			var pos := Vector2(float(x), float(z))
			var i1: int = 0
			var i2: int = -1
			# Squared distance — only the ordering matters, so skip the sqrt.
			var d1: float = pos.distance_squared_to(seeds[0])
			var d2: float = INF
			for i: int in range(1, region_count):
				var d: float = pos.distance_squared_to(seeds[i])
				if d < d1:
					d2 = d1
					i2 = i1
					d1 = d
					i1 = i
				elif d < d2:
					d2 = d
					i2 = i
			nearest[z * width + x] = i1
			if i2 >= 0:
				adjacency[i1][i2] = true
				adjacency[i2][i1] = true
				var ek: int = _edge_key(i1, i2)
				border_weight[ek] = int(border_weight.get(ek, 0)) + 1

	# --- 3. MAX-weight spanning tree → levels + ramp (level-changing) edges --
	# Building the tree from the fattest borders means every tree connection has a
	# real, traversable shared border — same-level edges are passable for free and
	# ramps get a wide throat — so connectivity holds without trenching plateaus.
	var ramp_edges: Dictionary = {}  # edge_key → true (level-changing tree edges)
	var levels: PackedInt32Array = _build_tree_levels(rng, adjacency, border_weight, ramp_edges)

	# 4. Optional loop ramps on non-tree single-level adjacencies (extra routes).
	if loop_ramp_chance > 0.0:
		for a: int in region_count:
			for b: Variant in adjacency[a]:
				var nb: int = b
				if nb <= a:
					continue  # visit each undirected pair once
				var key: int = _edge_key(a, nb)
				if ramp_edges.has(key):
					continue
				if absi(levels[a] - levels[nb]) == 1 and rng.randf() < loop_ramp_chance:
					ramp_edges[key] = true

	# --- 5a. Base heights: hard cliffs everywhere ---------------------------
	for idx: int in width * depth:
		data[idx] = float(levels[nearest[idx]]) * height_step

	# --- 5b. Carve a ramp for every level-changing edge --------------------
	for key: Variant in ramp_edges:
		var k: int = key
		var a: int = k / region_count
		var b: int = k % region_count
		_carve_ramp(data, seeds[a], seeds[b], float(levels[a]) * height_step, float(levels[b]) * height_step)

	# --- 6. Repair: guarantee a single connected passable surface -----------
	if guarantee_connected:
		_repair_connectivity(data)

	return data
#endregion

#region Connectivity repair
## Flood-fill the passable cells; while more than one component exists, carve the
## cheapest ramp corridor joining a stranded component to the largest one.  This
## is the guarantee that the graph stage only approximates: on a discrete corner
## grid, thin Voronoi borders and triple-junction pinches can sever an otherwise
## passable ramp, so a final verify-and-repair pass makes connectivity certain.
func _repair_connectivity(data: PackedFloat32Array) -> void:
	var gw: int = width - 1
	var gh: int = depth - 1
	if gw <= 0 or gh <= 0:
		return

	# Bounded number of merges (each pass joins >= 1 component to the main one).
	for _attempt: int in range(gw * gh):
		var comp := PackedInt32Array()
		comp.resize(gw * gh)
		comp.fill(-1)
		var sizes: Array[int] = []
		var n: int = 0
		for z: int in gh:
			for x: int in gw:
				if _cell_passable(data, x, z) and comp[z * gw + x] == -1:
					var sz: int = _flood(data, comp, gw, gh, x, z, n)
					sizes.append(sz)
					n += 1
		if n <= 1:
			return

		# Largest component is the "mainland" everything else must reach.
		var main_id: int = 0
		for i: int in sizes.size():
			if sizes[i] > sizes[main_id]:
				main_id = i

		# 0-1 BFS outward from the mainland; entering an impassable cell costs 1,
		# a passable cell costs 0.  The first passable cell of another component we
		# settle is the cheapest place to punch a corridor through.
		if not _connect_nearest(data, comp, gw, gh, main_id):
			return  # nothing left we can reach — give up rather than spin

## Carve the cheapest corridor from `main_id` to the nearest other component.
## Returns false if no other component is reachable.
func _connect_nearest(data: PackedFloat32Array, comp: PackedInt32Array, gw: int, gh: int, main_id: int) -> bool:
	var INF_D: int = 1 << 30
	var dist := PackedInt32Array()
	var parent := PackedInt32Array()
	dist.resize(gw * gh)
	parent.resize(gw * gh)
	dist.fill(INF_D)
	parent.fill(-1)

	var deque: Array[int] = []  # cell indices; treated as a 0-1 BFS deque
	for z: int in gh:
		for x: int in gw:
			if comp[z * gw + x] == main_id:
				dist[z * gw + x] = 0
				deque.push_back(z * gw + x)

	var target: int = -1
	while not deque.is_empty():
		var cur: int = deque.pop_front()
		var cx: int = cur % gw
		var cz: int = cur / gw
		# Settling a passable cell of another component → cheapest crossing found.
		if _cell_passable(data, cx, cz) and comp[cur] != main_id and comp[cur] != -1:
			target = cur
			break
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nx: int = cx + d.x
			var nz: int = cz + d.y
			if nx < 0 or nx >= gw or nz < 0 or nz >= gh:
				continue
			var ni: int = nz * gw + nx
			var w: int = 0 if _cell_passable(data, nx, nz) else 1
			if dist[cur] + w < dist[ni]:
				dist[ni] = dist[cur] + w
				parent[ni] = cur
				if w == 0:
					deque.push_front(ni)
				else:
					deque.push_back(ni)

	if target < 0:
		return false

	# Reconstruct the corridor (target → mainland) and carve it as a ramp.
	var path: Array[Vector2i] = []
	var c: int = target
	while c != -1:
		path.append(Vector2i(c % gw, c / gw))
		c = parent[c]
	_carve_corridor(data, path)
	return true

## Carve a list of cells (a connected path from a stranded cell to the mainland)
## into a passable ramp by writing a monotonic height profile between the two
## passable endpoints.  The corridor is widened perpendicular to its direction by
## `ramp_half_width` so repair connections are as wide as the graph ramps, not
## 1-cell bottlenecks.  If the endpoint height difference would exceed
## MAX_SLOPE_DIFF per cell, the run is extended with real cells past the mainland
## end (a short notch into that plateau) so the slope stays passable.
func _carve_corridor(data: PackedFloat32Array, path: Array[Vector2i]) -> void:
	var gw: int = width - 1
	var gh: int = depth - 1
	var max_slope: float = 0.5  # TerrainGrid.MAX_SLOPE_DIFF
	if path.size() < 2:
		return
	var ha: float = _cell_height(data, path[0].x, path[0].y)
	var hb: float = _cell_height(data, path[path.size() - 1].x, path[path.size() - 1].y)

	# Extend the mainland end with new in-bounds cells until the run is long
	# enough to keep each step <= max_slope.
	var needed: int = ceili(absf(hb - ha) / max_slope) + 1
	while path.size() < needed:
		var n: int = path.size()
		var dir: Vector2i = path[n - 1] - path[n - 2]
		var nxt: Vector2i = path[n - 1] + dir
		if nxt.x < 0 or nxt.x >= gw or nxt.y < 0 or nxt.y >= gh:
			break  # ran out of room — accept the gentlest slope we can manage
		path.append(nxt)

	var last: int = path.size() - 1
	var half_w: int = maxi(1, int(ramp_half_width))  # band half-width in cells
	for i: int in path.size():
		var h: float = lerpf(ha, hb, float(i) / float(last))
		# Lay a flat lateral band at this step's height, perpendicular to travel.
		# Same height across the band → flat → passable; consecutive bands differ
		# by <= max_slope → passable along the climb.
		var fwd: Vector2i = _corridor_dir(path, i)
		var perp := Vector2i(-fwd.y, fwd.x)
		for k: int in range(-half_w, half_w + 1):
			var cell: Vector2i = path[i] + perp * k
			if cell.x >= 0 and cell.x < gw and cell.y >= 0 and cell.y < gh:
				_set_cell_height(data, cell.x, cell.y, h)

## Unit axis direction of the path at index `i` (reduced to a single axis so the
## perpendicular band is axis-aligned and clean).
func _corridor_dir(path: Array[Vector2i], i: int) -> Vector2i:
	var a: Vector2i = path[mini(i + 1, path.size() - 1)]
	var b: Vector2i = path[maxi(i - 1, 0)]
	var d: Vector2i = a - b
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(1, 0)
	return Vector2i(0, signi(d.y))

func _flood(data: PackedFloat32Array, comp: PackedInt32Array, gw: int, gh: int, sx: int, sz: int, id: int) -> int:
	var size: int = 0
	var stack: Array[Vector2i] = [Vector2i(sx, sz)]
	comp[sz * gw + sx] = id
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		size += 1
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nx: int = c.x + d.x
			var nz: int = c.y + d.y
			if nx >= 0 and nx < gw and nz >= 0 and nz < gh \
					and _cell_passable(data, nx, nz) and comp[nz * gw + nx] == -1:
				comp[nz * gw + nx] = id
				stack.append(Vector2i(nx, nz))
	return size

func _cell_passable(data: PackedFloat32Array, x: int, z: int) -> bool:
	var h00: float = data[z * width + x]
	var h10: float = data[z * width + x + 1]
	var h01: float = data[(z + 1) * width + x]
	var h11: float = data[(z + 1) * width + x + 1]
	return (maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))) <= 0.5

func _cell_height(data: PackedFloat32Array, x: int, z: int) -> float:
	return (data[z * width + x] + data[z * width + x + 1]
		+ data[(z + 1) * width + x] + data[(z + 1) * width + x + 1]) * 0.25

func _set_cell_height(data: PackedFloat32Array, x: int, z: int, h: float) -> void:
	data[z * width + x] = h
	data[z * width + x + 1] = h
	data[(z + 1) * width + x] = h
	data[(z + 1) * width + x + 1] = h
#endregion

#region Ramp carving
## Carve a passable channel from seed `pa` (height `ha`) to seed `pb` (height
## `hb`).  Corners within `ramp_half_width` of the segment are overridden with a
## linear flat→slope→flat profile, centred on the segment midpoint (which lies on
## the shared Voronoi border for adjacent seeds).
func _carve_ramp(data: PackedFloat32Array, pa: Vector2, pb: Vector2, ha: float, hb: float) -> void:
	var seg: Vector2 = pb - pa
	var seg_len: float = seg.length()
	if seg_len < 0.001:
		return
	var u: Vector2 = seg / seg_len

	# Half-length of the sloped window as a fraction of the segment, centred at 0.5.
	var hrf: float = minf((float(ramp_run) / seg_len) * 0.5, 0.5)

	# Iterate the segment's bounding box, padded by the channel half-width.
	var pad: float = ramp_half_width + 1.0
	var min_x: int = maxi(0, floori(minf(pa.x, pb.x) - pad))
	var max_x: int = mini(width - 1, ceili(maxf(pa.x, pb.x) + pad))
	var min_z: int = maxi(0, floori(minf(pa.y, pb.y) - pad))
	var max_z: int = mini(depth - 1, ceili(maxf(pa.y, pb.y) + pad))

	for z: int in range(min_z, max_z + 1):
		for x: int in range(min_x, max_x + 1):
			var p := Vector2(float(x), float(z))
			var along: float = clampf((p - pa).dot(u), 0.0, seg_len)
			var t: float = along / seg_len
			var perp: float = p.distance_to(pa + u * along)
			if perp > ramp_half_width:
				continue
			# Linear flat→slope→flat: 0 near pa, 1 near pb.
			var s: float = clampf((t - (0.5 - hrf)) / (2.0 * hrf), 0.0, 1.0)
			data[z * width + x] = lerpf(ha, hb, s)
#endregion

#region Graph helpers
## Prim's MAXIMUM-weight spanning tree over the region-adjacency graph, preferring
## the fattest shared borders.  Assigns each region an integer level as the tree
## grows (root = 0; each tree edge keeps the level or steps ±1, clamped to
## [0, height_levels-1]).  Records level-changing tree edges into `ramp_edges`.
## Returns a level per region (regions in disconnected graph fragments → 0).
func _build_tree_levels(rng: RandomNumberGenerator, adjacency: Dictionary, border_weight: Dictionary, ramp_edges: Dictionary) -> PackedInt32Array:
	var levels := PackedInt32Array()
	levels.resize(region_count)  # PackedInt32Array zero-initialises

	var visited: Dictionary = {}
	# Seed Prim from the region with the most total border (the "biggest" plateau).
	var start: int = 0
	var best_total: int = -1
	for i: int in region_count:
		var total: int = 0
		for nb: Variant in adjacency[i]:
			total += int(border_weight.get(_edge_key(i, nb), 0))
		if total > best_total:
			best_total = total
			start = i
	visited[start] = true

	# Grow the tree by repeatedly adding the heaviest border crossing the frontier.
	# O(V·E) without a heap — fine for the handful of regions we use.
	for _step: int in range(region_count - 1):
		var best_u: int = -1
		var best_v: int = -1
		var best_w: int = -1
		for u: Variant in visited:
			for v: Variant in adjacency[u]:
				if visited.has(v):
					continue
				var w: int = int(border_weight.get(_edge_key(u, v), 0))
				if w > best_w:
					best_w = w
					best_u = u
					best_v = v
		if best_v < 0:
			break  # remaining regions are in a disconnected graph fragment

		visited[best_v] = true
		var delta: int = 0
		if rng.randf() < elevation_change_chance:
			delta = 1 if rng.randf() < 0.5 else -1
		var lvl: int = clampi(levels[best_u] + delta, 0, height_levels - 1)
		levels[best_v] = lvl
		if absi(lvl - levels[best_u]) == 1:
			ramp_edges[_edge_key(best_u, best_v)] = true
	return levels

## Order-independent integer key for an undirected region pair.
func _edge_key(a: int, b: int) -> int:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	return lo * region_count + hi
#endregion
