class_name NavManager
extends Node

## Owns and maintains the navigation meshes for the map.
##
## Rather than baking from 3D geometry (which re-parses the whole scene), meshes
## are constructed directly from the terrain grid: one quad per navigable cell, with
## shared vertices at cell corners so adjacent cells share geometry.
##
## Corner (cx, cz) in HeightMapShape3D local space sits at:
##
##   local.x = cx  - (map_width  - 1) / 2.0
##   local.y = map_data[cz * map_width + cx]       (actual terrain height)
##   local.z = cz  - (map_depth  - 1) / 2.0
##
## terrain_body.global_transform then maps that local position to world space,
## which is subsequently converted into NavigationRegion3D local space —
## the coordinate frame NavigationMesh vertices must be expressed in.
##
## SIZE CLASSES: one mesh is built per NavAgentClass.Size, space-eroded for that
## class's radius (ring-erosion of obstacle-adjacent cells + a sub-cell inset of
## boundary vertices), plus an un-eroded BASE mesh on a reserved layer no agent uses, which
## backs map_get_closest_point / line-of-sight snapping over the full passable surface. All
## of them live on the SAME navigation map (the scene region's world map), each tagged with a
## distinct navigation layer bit; an agent selects its class's mesh via NavigationAgent3D
## .navigation_layers (see layer_for / Movement.configure_for_map). Keeping a single map is
## deliberate: Godot computes RVO avoidance per-map, so every unit must share one map to
## avoid one another regardless of size class. See
## gdd/systems/terrain-and-navigation/agent-size-classes.md.
##
## CHUNKS: every mesh is split into CHUNK_SIZE_CELLS-square chunks, one navigation region
## each, so a change rebuilds only the chunks it can reach instead of the whole map. Godot
## joins neighbouring chunks by their exactly-coincident border edges. Each mesh's chunk grid
## is OFFSET from every other mesh's, which is load-bearing: two meshes sharing a border line
## would put more than two edges on one merge key, and the map would silently drop links. See
## gdd/systems/terrain-and-navigation/incremental-navmesh.md.
##
## Rebuilds are debounced via call_deferred so that a burst of cell changes
## (e.g. a multi-cell building placement) collapses into a single rebuild at
## the end of the same frame.
##
## CHANGES: every rebuild after the first is recorded as a NavChange — where the mesh changed,
## and when path queries can see it — so a moving unit re-plans only when a change crosses its
## path (Movement), instead of every unit re-planning on every change. See
## gdd/systems/terrain-and-navigation/navigation-and-pathing.md §Re-planning after a navmesh
## change.

#region Constants
## Navigation layer bit reserved for the base un-eroded mesh. Far from the class
## bits (1<<0 .. 1<<2, one per NavAgentClass.Size) so no agent's class layer ever selects it.
const _BASE_LAYER: int = 1 << 30

## Side of a navmesh chunk, in cells. A change rebuilds every chunk its reach overlaps, so a
## smaller chunk rebuilds fewer cells; 16 was the fastest of 16/32/64 measured on the 261×261
## skirmish map, with no measurable cost in path queries for the ~670 regions it makes.
const CHUNK_SIZE_CELLS: int = 16

## How many past changes are kept for units to check their paths against. A unit that falls
## further behind than this — one whose last check predates the oldest kept — simply re-plans,
## so this only has to cover how many rebuilds can land between two of one unit's path reads.
const CHANGE_HISTORY: int = 64
#endregion

#region Signals
## Emitted once the navigation mesh has been built AND force-synchronized for the first
## time, i.e. the map is actually queryable (map_get_closest_point /
## get_nonoverlapping_points return real surface points). Scenario triggers that spawn or
## path on the nav map gate on this so they never run against an empty/unsynced map.
## Re-checks should use is_ready() (the signal won't fire again after the first build).
signal navmesh_ready
#endregion

#region Inner classes
## One eroded mesh — the base or a size class — and the chunk regions it is cut into.
class ChunkedMesh:
	extends RefCounted
	var layer: int
	## Erosion parameters, as fed to TerrainGrid.navigable_mask.
	var rings: int
	var admit_k: int
	## Boundary-vertex inset in cells (the class inset divided by Map.CELL_SIZE).
	var inset_cells: float
	## Where this mesh's chunk grid starts, in cells; distinct per mesh (see CHUNKS above).
	var grid_offset: int
	## Vector2i chunk index -> region RID. Created on first build of the chunk.
	var regions: Dictionary = {}
	## Vector2i chunk index -> polygons in its current mesh (the server hands meshes back to
	## nobody, so the count is kept here for base_polygon_count).
	var polygon_counts: Dictionary = {}

	func _init(a_layer: int, a_rings: int, a_admit_k: int, a_inset_cells: float,
			a_grid_offset: int) -> void:
		layer = a_layer
		rings = a_rings
		admit_k = a_admit_k
		inset_cells = a_inset_cells
		grid_offset = a_grid_offset

	## How far, in cells, a changed cell can move this mesh's polygons: navigability reads
	## obstacles `rings` away and admission blocks `admit_k - 1` away, and a vertex's inset
	## reads the cells one further.
	func reach_cells() -> int:
		return maxi(rings, admit_k - 1) + 1
#endregion

#region Properties
@export var navigation_region: NavigationRegion3D
@export var terrain_grid: TerrainGrid

var _rebuild_pending: bool = false
## True once the first real (populated + synced) navmesh build has completed.
var _ready_announced: bool = false
## Set after the first mesh build to force a sync + emit navmesh_ready on the next physics
## frame (map_force_update is only valid during the physics step).
var _pending_first_sync: bool = false
## False until the first build, which covers the whole map whatever changed before it.
var _built_once: bool = false
## Bounding box of the cells changed since the last rebuild; only meaningful while _has_dirty.
var _dirty: Rect2i = Rect2i()
var _has_dirty: bool = false

## The base mesh first, then one per size class.
var _meshes: Array[ChunkedMesh] = []

## Rebuilds after the first, oldest first, at most CHANGE_HISTORY of them.
var _changes: Array[NavChange] = []
var _next_change_serial: int = 1
## The change the rebuild in progress records its regions into; null outside a rebuild.
var _recording: NavChange = null
#endregion


## One rebuild as a moving unit sees it: where the mesh changed, and whether path queries can
## see it yet. A region processes a new mesh at a sync, and the map publishes it only in its
## next iteration after that, so a path re-planned before then would be planned on the old
## mesh. Iteration ids are polled rather than a tick count assumed: navigation is synchronous
## (project.godot, for replay), but the landing tick is the server's business.
class NavChange:
	extends RefCounted
	var serial: int
	## World XZ bounds of the changed cells, grown by the widest class's reach. Nothing outside
	## it was rebuilt any differently.
	var world_area: Rect2
	## Region -> its iteration id before this rebuild handed it a mesh; emptied as each finishes.
	var pending_regions: Dictionary = {}
	## The map iteration current once every region had finished; -1 until then.
	var ready_map_iteration: int = -1
	## True once the map has published an iteration after ready_map_iteration.
	var is_landed: bool = false

	func _init(a_serial: int, a_world_area: Rect2) -> void:
		serial = a_serial
		world_area = a_world_area

	## Whether a unit at `a_origin` heading along `a_path` from waypoint `a_from_index` would
	## pass through this change: any leg, including the one from where it stands, touching the
	## area in XZ.
	func crosses(a_origin: Vector3, a_path: PackedVector3Array, a_from_index: int) -> bool:
		var previous: Vector2 = VU.inXZ(a_origin)
		for i: int in range(maxi(a_from_index, 0), a_path.size()):
			var point: Vector2 = VU.inXZ(a_path[i])
			if NavChange.segment_touches_rect(previous, point, world_area):
				return true
			previous = point
		return world_area.has_point(previous)

	## Whether this change falls within `a_reach` (a square neighbourhood, XZ) of `a_point`.
	func is_near(a_point: Vector3, a_reach: float) -> bool:
		return world_area.grow(a_reach).has_point(VU.inXZ(a_point))

	## Whether segment `a`→`b` touches the closed rectangle `rect` (Liang–Barsky clipping).
	static func segment_touches_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
		var d: Vector2 = b - a
		var t0: float = 0.0
		var t1: float = 1.0
		for axis: int in 2:
			var lo: float = rect.position[axis]
			var hi: float = rect.end[axis]
			if is_zero_approx(d[axis]):
				if a[axis] < lo or a[axis] > hi:
					return false
				continue
			var ta: float = (lo - a[axis]) / d[axis]
			var tb: float = (hi - a[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
		return true

#region Lifecycle
func _ready() -> void:
	assert(navigation_region != null, "NavManager: navigation_region export must be set")
	assert(terrain_grid      != null, "NavManager: terrain_grid export must be set")
	_init_meshes()
	terrain_grid.cells_changed.connect(_on_cells_changed)
	# Defer so all _ready() calls finish before the first build.
	call_deferred("_rebuild_navmesh")
	# Physics processing is only needed for the one-shot first-build force-sync below.
	set_physics_process(false)

## After the first mesh build, force a map sync each physics frame (map_force_update is
## only valid during the physics step) and probe a known-navigable point until the map
## actually resolves it — assigning a region's mesh and having the map merge it into its
## query structure can take more than one sync, so we poll rather than assume one frame is
## enough. Once queryable, announce readiness and stop physics-processing.
##
## Also runs while a change is waiting to land (_advance_changes), and stops once nothing is.
func _physics_process(_a_delta: float) -> void:
	if _pending_first_sync:
		var nm: RID = navigation_region.get_navigation_map()
		NavigationServer3D.map_force_update(nm)
		if _map_resolves_navigable_point(nm):
			_pending_first_sync = false
			_ready_announced = true
			navmesh_ready.emit()
	_advance_changes()
	if not _pending_first_sync and not _changes.any(func(c: NavChange) -> bool:
			return not c.is_landed):
		set_physics_process(false)

## True once map_get_closest_point on `nm` resolves a point that IS navigable back to (near)
## itself — i.e. the map's query structure has incorporated the region mesh. An empty/unsynced
## map returns the origin instead, which is far from the probe.
func _map_resolves_navigable_point(a_nm: RID) -> bool:
	# Iteration 0 is a map that has never synced, which the server refuses to query at all.
	if NavigationServer3D.map_get_iteration_id(a_nm) == 0:
		return false
	var probe: Vector3 = _sample_navigable_world_point()
	if probe == Vector3.INF:
		return true  # no navigable cells at all — nothing to wait for
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(a_nm, probe)
	return snapped.distance_to(probe) < Map.CELL_SIZE

## World-space centre of an arbitrary navigable cell, or Vector3.INF if the terrain has no
## navigable cells. Used as a probe to detect when the navigation map is queryable.
func _sample_navigable_world_point() -> Vector3:
	var bounds: Rect2i = terrain_grid.get_bounds_rect()
	var mask: PackedByteArray = terrain_grid.navigable_mask(bounds, 0, 1)
	var idx: int = mask.find(1)
	if idx < 0:
		return Vector3.INF
	var hs: HeightMapShape3D = terrain_grid.height_shape()
	var fx: float = idx % bounds.size.x + 0.5
	var fz: float = idx / bounds.size.x + 0.5
	return terrain_grid.terrain_body.global_transform * Vector3(
		fx - (hs.map_width - 1) * 0.5,
		_height_at(fx, fz, hs.map_data, hs.map_width, hs.map_depth),
		fz - (hs.map_depth - 1) * 0.5)

func _exit_tree() -> void:
	for mesh: ChunkedMesh in _meshes:
		for region: RID in mesh.regions.values():
			NavigationServer3D.free_rid(region)
		mesh.regions.clear()
#endregion

#region Public API
## The changes after serial `a_seen`, oldest first, that path queries can already see —
## stopping at the first one that cannot, so a unit never checks past a change it has not
## been able to check yet.
func landed_changes_since(a_seen: int) -> Array[NavChange]:
	var out: Array[NavChange] = []
	for change: NavChange in _changes:
		if change.serial <= a_seen:
			continue
		if not change.is_landed:
			break
		out.append(change)
	return out


## Whether a change after `a_seen` has already been dropped from the history, so a unit that
## last checked at `a_seen` cannot tell whether its path was affected.
func has_forgotten(a_seen: int) -> bool:
	return not _changes.is_empty() and _changes[0].serial > a_seen + 1


## The newest change a path planned now is planned with: the last landed one with every
## earlier one landed too.
func landed_serial() -> int:
	var seen: int = _next_change_serial - 1
	for change: NavChange in _changes:
		if not change.is_landed:
			return change.serial - 1
	return seen


## Schedule a navmesh rebuild at the end of this frame.
## Multiple calls within one frame coalesce into a single rebuild.
func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild_navmesh")

## NavigationAgent3D.navigation_layers value that selects the space-eroded mesh for
## `size`: one distinct bit per class (SMALL -> 1<<0 ... LARGE -> 1<<2).
func layer_for(a_size: NavAgentClass.Size) -> int:
	return 1 << (int(a_size) - 1)

## True once the first populated navmesh has been built and synchronized — i.e. the nav
## map is queryable. Callers that may run before the first build await navmesh_ready.
func is_ready() -> bool:
	return _ready_announced

## Polygons in the base (un-eroded) mesh, summed over its chunks — one per navigable cell.
func base_polygon_count() -> int:
	if _meshes.is_empty():
		return 0
	var total: int = 0
	for count: int in _meshes[0].polygon_counts.values():
		total += count
	return total

## Await until every point in `probes` is confirmed excluded from the navmesh —
## i.e. map_get_closest_point no longer resolves it back to (near) itself. Pass
## the world-space centers of a just-placed structure's footprint cells to wait
## out its exclusion before scattering units onto the navmesh.
##
## navmesh_ready/is_ready only cover the very FIRST build — after that, _rebuild_navmesh
## rides the normal per-tick sync with nothing gating on it (see its comment), so a caller
## that places a structure and immediately scatters units onto the navmesh can race the
## rebuild and land a unit on the structure's own footprint. A single map_force_update
## (or even a couple, spread across physics frames) isn't reliably enough — a newly
## region_set_navigation_mesh'd region can take more than a couple of syncs to actually
## merge into the map's query structure (mirrors the same "can take more than one sync"
## caveat as the first-build poll in _physics_process) — so this polls a REAL correctness
## check instead of trusting a fixed iteration count, giving up (returning false) after
## `max_iterations` as a safety net against hanging forever on a bad probe.
func await_excluded(a_probes: Array[Vector3], a_max_iterations: int = 30) -> bool:
	if a_probes.is_empty():
		return true
	# Let a call_deferred("_rebuild_navmesh") queued this frame actually run and set the
	# new region meshes before forcing the server to sync them.
	if _rebuild_pending:
		await get_tree().process_frame
	var nm: RID = navigation_region.get_navigation_map()
	for _i in a_max_iterations:
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(nm)
		var all_excluded := true
		for p: Vector3 in a_probes:
			if NavigationServer3D.map_get_closest_point(nm, p).distance_to(p) < 0.05:
				all_excluded = false
				break
		if all_excluded:
			return true
	push_warning("NavManager.await_excluded: %d probe(s) never confirmed excluded after %d iterations"
		% [a_probes.size(), a_max_iterations])
	return false
#endregion

#region Private helpers
## Describe the base mesh and one mesh per size class, each with its own chunk-grid offset.
## The scene region itself carries no mesh any more — its map and transform are what the
## chunk regions hang off.
func _init_meshes() -> void:
	navigation_region.navigation_layers = _BASE_LAYER
	navigation_region.use_edge_connections = false
	navigation_region.navigation_mesh = NavigationMesh.new()
	var cs: float = Map.CELL_SIZE
	var sizes: Array = NavAgentClass.Size.values()
	var count: int = sizes.size() + 1
	_meshes.append(ChunkedMesh.new(_BASE_LAYER, 0, 1, 0.0, 0))
	for i: int in sizes.size():
		var size: NavAgentClass.Size = sizes[i]
		_meshes.append(ChunkedMesh.new(
			layer_for(size),
			NavAgentClass.erosion_rings(size, cs),
			NavAgentClass.required_clearance(size, cs),
			NavAgentClass.inset(size, cs) / cs,
			(i + 1) * CHUNK_SIZE_CELLS / count))

func _on_cells_changed(a_cells: Array) -> void:
	if a_cells.is_empty():
		return
	var lo: Vector2i = a_cells[0]
	var hi: Vector2i = a_cells[0]
	for cell: Vector2i in a_cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	var changed := Rect2i(lo, hi - lo + Vector2i.ONE)
	_dirty = _dirty.merge(changed) if _has_dirty else changed
	_has_dirty = true
	request_rebuild()

## Rebuild every chunk the changes since the last rebuild can reach — the whole map the first
## time.
func _rebuild_navmesh() -> void:
	_rebuild_pending = false
	var bounds: Rect2i = terrain_grid.get_bounds_rect()
	var changed: Rect2i = _dirty if _built_once else bounds
	if _built_once and not _has_dirty:
		return
	var is_first_build: bool = not _built_once
	_built_once = true
	_has_dirty = false
	var context := _BuildContext.new(self)
	var widest_reach: int = 0
	for mesh: ChunkedMesh in _meshes:
		widest_reach = maxi(widest_reach, mesh.reach_cells())
	if not is_first_build:
		_recording = NavChange.new(_next_change_serial,
			_world_rect(changed.grow(widest_reach).intersection(bounds)))
		_next_change_serial += 1
	for mesh: ChunkedMesh in _meshes:
		var area: Rect2i = changed.grow(mesh.reach_cells()).intersection(bounds)
		if area.has_area():
			_rebuild_chunks(mesh, area, context)
	if _recording != null:
		_changes.append(_recording)
		_recording = null
		while _changes.size() > CHANGE_HISTORY and _changes[0].is_landed:
			_changes.pop_front()
		set_physics_process(true)

	# On the FIRST build, schedule a one-shot physics-frame sync. The meshes are set here
	# (deferred / idle), but NavigationServer3D only synchronizes maps during the physics
	# step and map_force_update is only valid there — so the actual force-sync + readiness
	# announcement happens in _physics_process. Subsequent rebuilds (building placement
	# etc.) ride the normal per-tick sync; nothing gates on them.
	if not _ready_announced and not _pending_first_sync:
		_pending_first_sync = true
		set_physics_process(true)

## First cell of chunk `a_index` along one axis, for a grid starting at `a_offset`. Chunk 0
## is the (possibly narrower, possibly empty) strip before the offset.
static func _chunk_start(a_index: int, a_offset: int) -> int:
	return maxi(0, a_offset + (a_index - 1) * CHUNK_SIZE_CELLS)

static func _chunk_of(a_cell: int, a_offset: int) -> int:
	return (a_cell - a_offset + CHUNK_SIZE_CELLS) / CHUNK_SIZE_CELLS

## Rebuild and hand over every chunk of `a_mesh` that overlaps `a_area`.
func _rebuild_chunks(a_mesh: ChunkedMesh, a_area: Rect2i, a_context: _BuildContext) -> void:
	var bounds: Rect2i = terrain_grid.get_bounds_rect()
	var off: int = a_mesh.grid_offset
	for cz: int in range(_chunk_of(a_area.position.y, off), _chunk_of(a_area.end.y - 1, off) + 1):
		for cx: int in range(_chunk_of(a_area.position.x, off), _chunk_of(a_area.end.x - 1, off) + 1):
			var start := Vector2i(_chunk_start(cx, off), _chunk_start(cz, off))
			var end := Vector2i(_chunk_start(cx + 1, off), _chunk_start(cz + 1, off))
			var rect: Rect2i = Rect2i(start, end - start).intersection(bounds)
			if not rect.has_area():
				continue
			var chunk := Vector2i(cx, cz)
			var region: RID = a_mesh.regions.get(chunk, RID())
			if not region.is_valid():
				region = _create_region(a_mesh.layer)
				a_mesh.regions[chunk] = region
			var nav_mesh: NavigationMesh = _build_chunk(a_mesh, rect, a_context)
			if _recording != null and not _recording.pending_regions.has(region):
				_recording.pending_regions[region] = NavigationServer3D.region_get_iteration_id(region)
			NavigationServer3D.region_set_navigation_mesh(region, nav_mesh)
			a_mesh.polygon_counts[chunk] = nav_mesh.get_polygon_count()

## Mark each waiting change ready once all its regions have processed their meshes, and landed
## once the map has published an iteration that includes them. A SYNCHRONOUS map (the project's
## setting) rebuilds in the very sync that processed the regions, so ready is landed; an async
## one publishes in a later iteration, and waiting for a later one there is still right.
func _advance_changes() -> void:
	var nav_map: RID = navigation_region.get_navigation_map()
	var map_iteration: int = NavigationServer3D.map_get_iteration_id(nav_map)
	var is_map_async: bool = NavigationServer3D.map_get_use_async_iterations(nav_map)
	for change: NavChange in _changes:
		if change.is_landed:
			continue
		if change.ready_map_iteration < 0:
			for region: RID in change.pending_regions.keys():
				if NavigationServer3D.region_get_iteration_id(region) \
						!= int(change.pending_regions[region]):
					change.pending_regions.erase(region)
			if change.pending_regions.is_empty():
				change.ready_map_iteration = map_iteration
				change.is_landed = not is_map_async
		elif map_iteration > change.ready_map_iteration:
			change.is_landed = true


## World XZ bounds of the cells in `a_cells`.
func _world_rect(a_cells: Rect2i) -> Rect2:
	var hs: HeightMapShape3D = terrain_grid.height_shape()
	var to_world: Transform3D = terrain_grid.terrain_body.global_transform
	var half := Vector2((hs.map_width - 1) * 0.5, (hs.map_depth - 1) * 0.5)
	var a: Vector3 = to_world * Vector3(a_cells.position.x - half.x, 0.0, a_cells.position.y - half.y)
	var b: Vector3 = to_world * Vector3(a_cells.end.x - half.x, 0.0, a_cells.end.y - half.y)
	return Rect2(VU.inXZ(a), Vector2.ZERO).expand(VU.inXZ(b))


func _create_region(a_layer: int) -> RID:
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, navigation_region.get_navigation_map())
	NavigationServer3D.region_set_transform(region, navigation_region.global_transform)
	NavigationServer3D.region_set_navigation_layers(region, a_layer)
	# Neighbouring chunks join by exact edge merge; edge connections would also snap across
	# gaps, bleeding one class's mesh into another's.
	NavigationServer3D.region_set_use_edge_connections(region, false)
	return region

## What every chunk of one rebuild shares: the heightfield and the corner→region transform.
class _BuildContext:
	extends RefCounted
	var heights: PackedFloat32Array
	var map_width: int
	var map_depth: int
	var half_w: float
	var half_d: float
	## Heightmap-local corner position -> NavigationRegion3D-local.
	var to_region: Transform3D

	func _init(a_manager: NavManager) -> void:
		var hs: HeightMapShape3D = a_manager.terrain_grid.height_shape()
		heights = hs.map_data
		map_width = hs.map_width
		map_depth = hs.map_depth
		half_w = (map_width - 1) * 0.5
		half_d = (map_depth - 1) * 0.5
		to_region = a_manager.navigation_region.global_transform.affine_inverse() \
			* a_manager.terrain_grid.terrain_body.global_transform

## Build the mesh for the cells of `a_rect`: one quad per navigable cell, each boundary vertex
## inset toward the walkable interior.
##
## Navigability is read one cell PAST the rect, so a corner on a chunk border is computed from
## the same four cells — and comes out bit-identical — in both chunks that share it. That is
## what lets Godot's exact-edge merge stitch the chunks back into one surface.
##
## ONE QUAD PER CELL, and it has to stay that way — see the note below on why merging
## cells into larger polygons is not available in this engine.
func _build_chunk(a_mesh: ChunkedMesh, a_rect: Rect2i, a_context: _BuildContext) -> NavigationMesh:
	var read: Rect2i = a_rect.grow(1).intersection(terrain_grid.get_bounds_rect())
	var mask: PackedByteArray = terrain_grid.navigable_mask(read, a_mesh.rings, a_mesh.admit_k)
	var read_w: int = read.size.x
	var corners_w: int = a_rect.size.x + 1
	var corner_index := PackedInt32Array()
	corner_index.resize(corners_w * (a_rect.size.y + 1))
	corner_index.fill(-1)
	var verts := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	# Hot loop: every cell of the chunk, on every rebuild that reaches it.
	for z: int in range(a_rect.position.y, a_rect.end.y):
		for x: int in range(a_rect.position.x, a_rect.end.x):
			if mask[(z - read.position.y) * read_w + (x - read.position.x)] == 0:
				continue
			var polygon := PackedInt32Array()
			polygon.resize(4)
			for i: int in 4:
				# Corners in the winding the mesh has always used: (0,0) (1,0) (1,1) (0,1).
				var cx: int = x + (1 if i == 1 or i == 2 else 0)
				var cz: int = z + (1 if i >= 2 else 0)
				var slot: int = (cz - a_rect.position.y) * corners_w + (cx - a_rect.position.x)
				if corner_index[slot] < 0:
					corner_index[slot] = verts.size()
					verts.append(_corner_position(cx, cz, a_mesh.inset_cells, mask, read, a_context))
				polygon[i] = corner_index[slot]
			polygons.append(polygon)
	var nav_mesh := NavigationMesh.new()
	nav_mesh.vertices = verts
	nav_mesh.set("polygons", polygons)  # the storage property; no typed setter takes them whole
	return nav_mesh

## DO NOT merge cells into larger convex polygons here. It looks like the obvious fix for
## the L-shaped paths agents walk (Godot's polygon A* picks one cell corridor out of many
## equal-cost ones, and the funnel can only pull the string taut inside the corridor it was
## handed), and on an empty flat square it appears to work perfectly — 6.8% worst-case
## excess over the straight line drops to 0.0%. It was built, measured on real terrain, and
## reverted, because Godot cannot represent the result:
##
##  * Godot links navigation polygons by EXACTLY-matching edges. A merged rectangle's long
##    side against several smaller neighbours is a T-junction, and those polygons silently
##    do not connect.
##  * Subdividing each polygon's perimeter at every cell corner fixes the T-junctions — and
##    breaks point containment. NavigationServer treats a polygon carrying collinear
##    perimeter vertices as covering only its boundary: EVERY interior point of a 3x32
##    subdivided rectangle fails to resolve onto it, while the same rectangle as a plain
##    4-vertex polygon resolves all of them. map_get_closest_point then snaps queries to the
##    nearest polygon EDGE, which is what path endpoints are resolved through.
##
## Measured on s3's authored terrain, over every 5-tile diagonal move whose straight line is
## entirely walkable: one quad per cell bends 22% of them, mean excess 4.1%. The merged mesh
## bent 87% of them, mean excess 24.8% — the merge made real maps roughly five times worse
## while making the synthetic flat case perfect. Both engine behaviours are pinned in
## tests/test_NavPathDirectness.gd so a future attempt fails fast instead of shipping.
##
## Straightening paths has to happen somewhere other than the mesh: string-pulling the
## returned path against the navmesh (Map.get_navmesh_line_hit) is the standing candidate.

## Region-local position of heightmap corner (cx, cz), shifted toward the walkable interior by
## `a_inset_cells`. The shift direction is the normalised sum of directions to the corner's
## NAVIGABLE incident cells, so a convex tip is pulled in, a straight wall is pushed
## perpendicularly, and the concave corner around a building is cut back — which is what keeps
## the unit from clipping that corner. Interior corners (all four cells navigable) cancel to
## zero and don't move. The vertex is shared, so moving it here moves it for every quad that
## references it.
func _corner_position(a_cx: int, a_cz: int, a_inset_cells: float, a_mask: PackedByteArray,
		a_read: Rect2i, a_context: _BuildContext) -> Vector3:
	var fx: float = a_cx
	var fz: float = a_cz
	if a_inset_cells > 0.0:
		# Incident cells, identified by their min-corner. Centre of cell (ax,az) sits at
		# (ax+0.5, az+0.5), so the direction from this corner is ±0.5.
		var sx: float = 0.0
		var sz: float = 0.0
		for az: int in range(a_cz - 1, a_cz + 1):
			for ax: int in range(a_cx - 1, a_cx + 1):
				if a_read.has_point(Vector2i(ax, az)) \
						and a_mask[(az - a_read.position.y) * a_read.size.x + (ax - a_read.position.x)] != 0:
					sx += (ax + 0.5) - a_cx
					sz += (az + 0.5) - a_cz
		var length: float = sqrt(sx * sx + sz * sz)
		if length > 0.0:
			fx += a_inset_cells * sx / length
			fz += a_inset_cells * sz / length
	var height: float = _height_at(fx, fz, a_context.heights, a_context.map_width, a_context.map_depth)
	return a_context.to_region * Vector3(fx - a_context.half_w, height, fz - a_context.half_d)

## Bilinearly sample the heightfield at fractional corner coordinates, so an inset vertex stays
## on the terrain surface instead of snapping to a corner.
static func _height_at(fx: float, fz: float, heights: PackedFloat32Array, width: int,
		depth: int) -> float:
	var lx: float = clampf(fx, 0.0, width - 1)
	var lz: float = clampf(fz, 0.0, depth - 1)
	var x0: int = floori(lx)
	var z0: int = floori(lz)
	var x1: int = mini(x0 + 1, width - 1)
	var z1: int = mini(z0 + 1, depth - 1)
	var tx: float = lx - x0
	var tz: float = lz - z0
	var h00: float = heights[z0 * width + x0]
	var h10: float = heights[z0 * width + x1]
	var h01: float = heights[z1 * width + x0]
	var h11: float = heights[z1 * width + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
#endregion
