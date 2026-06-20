class_name NavManager
extends Node

## Owns and maintains the navigation meshes for the map.
##
## Rather than baking from 3D geometry (which re-parses the whole scene), meshes
## are constructed directly from HeightMapShape3D data.  One quad is emitted per
## passable cell, with shared vertices at cell corners so adjacent cells share
## geometry.
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
## SIZE CLASSES: one mesh is baked per NavAgentClass.Size, space-eroded for that
## class's radius (ring-erosion of obstacle-adjacent cells + a sub-cell inset of
## boundary vertices). All of them live as separate REGIONS on the SAME navigation
## map (the scene region's default world map), each tagged with a distinct
## navigation layer bit; an agent selects its class's mesh via NavigationAgent3D
## .navigation_layers (see layer_for / Movement.configure_for_map). Keeping a single
## map is deliberate: Godot computes RVO avoidance per-map, so every unit must share
## one map to avoid one another regardless of size class. The scene NavigationRegion3D
## keeps an un-eroded mesh (on a reserved layer no agent uses) so map_get_closest_point
## / line-of-sight snapping still cover the full passable surface. Per-region edge
## connections are disabled — each class mesh is one self-contained region and must
## not bleed into the others. See nav-agent-size-classes.md.
##
## Rebuilds are debounced via call_deferred so that a burst of cell changes
## (e.g. a multi-cell building placement) collapses into a single rebuild at
## the end of the same frame.

#region Constants
## Navigation layer bit reserved for the base un-eroded region. Far from the class
## bits (1<<0 .. 1<<3) so no agent's class layer ever selects it.
const _BASE_LAYER: int = 1 << 30
#endregion

#region Signals
## Emitted once the navigation mesh has been built AND force-synchronized for the first
## time, i.e. the map is actually queryable (map_get_closest_point /
## get_nonoverlapping_points return real surface points). Scenario triggers that spawn or
## path on the nav map gate on this so they never run against an empty/unsynced map.
## Re-checks should use is_ready() (the signal won't fire again after the first build).
signal navmesh_ready
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

## One region per size class, all on the scene region's navigation map.
var _class_regions: Dictionary = {}  # NavAgentClass.Size -> RID (region)
#endregion

#region Lifecycle
func _ready() -> void:
	assert(navigation_region != null, "NavManager: navigation_region export must be set")
	assert(terrain_grid      != null, "NavManager: terrain_grid export must be set")
	_init_class_regions()
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
func _physics_process(_delta: float) -> void:
	if not _pending_first_sync:
		set_physics_process(false)
		return
	var nm: RID = navigation_region.get_navigation_map()
	NavigationServer3D.map_force_update(nm)
	if not _map_resolves_navigable_point(nm):
		return  # not merged into the query structure yet — try again next physics frame
	_pending_first_sync = false
	_ready_announced = true
	set_physics_process(false)
	navmesh_ready.emit()

## True once map_get_closest_point on `nm` resolves a point that IS navigable back to (near)
## itself — i.e. the map's query structure has incorporated the region mesh. An empty/unsynced
## map returns the origin instead, which is far from the probe.
func _map_resolves_navigable_point(nm: RID) -> bool:
	var probe: Vector3 = _sample_navigable_world_point()
	if probe == Vector3.INF:
		return true  # no navigable cells at all — nothing to wait for
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nm, probe)
	return snapped.distance_to(probe) < Map.CELL_SIZE

## World-space centre of an arbitrary navigable cell, using the same corner→world mapping
## as _build_mesh, or Vector3.INF if the terrain has no navigable cells. Used as a probe to
## detect when the navigation map is queryable.
func _sample_navigable_world_point() -> Vector3:
	var cells: Dictionary = terrain_grid.get_navigable_cells(0, 1)
	if cells.is_empty():
		return Vector3.INF
	var cell: Vector2i = cells.keys()[0]
	var hs: HeightMapShape3D = terrain_grid.height_shape()
	var tb: StaticBody3D = terrain_grid.terrain_body
	var half_w: float = (hs.map_width - 1) * 0.5
	var half_d: float = (hs.map_depth - 1) * 0.5
	var fx: float = cell.x + 0.5
	var fz: float = cell.y + 0.5
	return tb.global_transform * Vector3(fx - half_w, _sample_height(fx, fz, hs), fz - half_d)

func _exit_tree() -> void:
	for region: RID in _class_regions.values():
		NavigationServer3D.free_rid(region)
	_class_regions.clear()
#endregion

#region Public API
## Schedule a navmesh rebuild at the end of this frame.
## Multiple calls within one frame coalesce into a single rebuild.
func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild_navmesh")

## NavigationAgent3D.navigation_layers value that selects the space-eroded mesh for
## `size`: one distinct bit per class (SMALL -> 1<<0 ... MASSIVE -> 1<<3).
func layer_for(size: NavAgentClass.Size) -> int:
	return 1 << (int(size) - 1)

## True once the first populated navmesh has been built and synchronized — i.e. the nav
## map is queryable. Callers that may run before the first build await navmesh_ready.
func is_ready() -> bool:
	return _ready_announced
#endregion

#region Private helpers
## Create one region per size class on the scene region's map, each on its own
## navigation layer and with cross-region edge connections disabled (each class
## mesh is self-contained — agents must not path across class boundaries).
func _init_class_regions() -> void:
	var map: RID = navigation_region.get_navigation_map()
	var xform: Transform3D = navigation_region.global_transform
	# The base un-eroded region is for snapping only; keep it off every agent layer.
	navigation_region.navigation_layers = _BASE_LAYER
	navigation_region.use_edge_connections = false
	for size: int in NavAgentClass.Size.values():
		var region: RID = NavigationServer3D.region_create()
		NavigationServer3D.region_set_map(region, map)
		NavigationServer3D.region_set_transform(region, xform)
		NavigationServer3D.region_set_navigation_layers(region, layer_for(size))
		NavigationServer3D.region_set_use_edge_connections(region, false)
		_class_regions[size] = region

func _on_cells_changed(_cells: Array) -> void:
	request_rebuild()

func _rebuild_navmesh() -> void:
	_rebuild_pending = false
	# Base, un-eroded mesh on the scene region (reserved layer) — backs
	# Map.get_navmesh_line_hit / EventCommandPoint target snapping over the full
	# passable surface; no agent navigates on it.
	navigation_region.navigation_mesh = _build_mesh(0, 1, 0.0)
	# One space-eroded mesh per size class, each on its own navigation layer.
	var cs: float = Map.CELL_SIZE
	for size: int in _class_regions:
		var rings: int = NavAgentClass.erosion_rings(size, cs)
		var admit_k: int = NavAgentClass.required_clearance(size, cs)
		var inset: float = NavAgentClass.inset(size, cs)
		var mesh: NavigationMesh = _build_mesh(rings, admit_k, inset)
		NavigationServer3D.region_set_navigation_mesh(_class_regions[size], mesh)

	# On the FIRST build, schedule a one-shot physics-frame sync. The meshes are set here
	# (deferred / idle), but NavigationServer3D only synchronizes maps during the physics
	# step and map_force_update is only valid there — so the actual force-sync + readiness
	# announcement happens in _physics_process. Subsequent rebuilds (building placement
	# etc.) ride the normal async sync; nothing gates on them.
	if not _ready_announced and not _pending_first_sync:
		_pending_first_sync = true
		set_physics_process(true)

## Build a NavigationMesh from the cells navigable under (rings, admit_k), with each
## boundary vertex inset toward the walkable interior by `inset` world-units.
func _build_mesh(rings: int, admit_k: int, inset: float) -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	var hs    := terrain_grid.height_shape()
	var tb    := terrain_grid.terrain_body
	var map_w := hs.map_width
	var map_d := hs.map_depth

	# Half-extents in local space.  HeightMapShape3D centers its grid at the
	# origin: corner (0,0) is at local (-half_w, h, -half_d).
	var half_w: float = (map_w - 1) * 0.5
	var half_d: float = (map_d - 1) * 0.5

	# Pre-invert once so every vertex conversion is a cheap multiply.
	var to_nav_local := navigation_region.global_transform.affine_inverse()

	# Displacement is computed in corner-index space, where one unit == one cell;
	# convert the world-space inset into that space.
	var inset_local: float = inset / Map.CELL_SIZE

	var cells: Dictionary = terrain_grid.get_navigable_cells(rings, admit_k)

	# Shared-vertex approach: corners are keyed by their (cx, cz) coordinate
	# so adjacent cells reuse the same vertex instead of duplicating it.
	var vertex_map: Dictionary = {}  # Vector2i -> int index in verts
	var verts := PackedVector3Array()

	for cell: Vector2i in cells:
		# The four corners of this cell in heightmap-corner index space.
		var corners: Array[Vector2i] = [
			Vector2i(cell.x,     cell.y    ),
			Vector2i(cell.x + 1, cell.y    ),
			Vector2i(cell.x + 1, cell.y + 1),
			Vector2i(cell.x,     cell.y + 1),
		]

		var indices := PackedInt32Array()
		for corner: Vector2i in corners:
			if not vertex_map.has(corner):
				vertex_map[corner] = verts.size()
				var world := _corner_world(corner, cells, inset_local, hs, tb, half_w, half_d)
				verts.append(to_nav_local * world)
			indices.append(vertex_map[corner])

		nav_mesh.add_polygon(indices)

	nav_mesh.vertices = verts
	return nav_mesh

## World position of a heightmap corner, shifted toward the walkable interior by
## `inset_local` (corner-index units). The shift direction is the normalised sum of
## directions to the corner's INCLUDED incident cells, so a convex tip is pulled in,
## a straight wall is pushed perpendicularly, and the concave corner around a building
## is cut back — which is what keeps the unit from clipping that corner. Interior
## corners (all four cells included) cancel to zero and don't move. The vertex is
## shared, so moving it here moves it for every quad that references it.
func _corner_world(
	corner: Vector2i,
	cells: Dictionary,
	inset_local: float,
	hs: HeightMapShape3D,
	tb: StaticBody3D,
	half_w: float,
	half_d: float
) -> Vector3:
	var cx: float = corner.x
	var cz: float = corner.y
	if inset_local > 0.0:
		# Incident cells, identified by their min-corner. Centre of cell (ax,az)
		# sits at (ax+0.5, az+0.5), so the direction from this corner is ±0.5.
		var sx: float = 0.0
		var sz: float = 0.0
		for ic: Vector2i in [
			Vector2i(corner.x - 1, corner.y - 1),
			Vector2i(corner.x,     corner.y - 1),
			Vector2i(corner.x - 1, corner.y    ),
			Vector2i(corner.x,     corner.y    ),
		]:
			if cells.has(ic):
				sx += (ic.x + 0.5) - corner.x
				sz += (ic.y + 0.5) - corner.y
		var length: float = sqrt(sx * sx + sz * sz)
		if length > 0.0:
			cx += inset_local * sx / length
			cz += inset_local * sz / length
	var local_pos := Vector3(cx - half_w, _sample_height(cx, cz, hs), cz - half_d)
	return tb.global_transform * local_pos

## Bilinearly sample HeightMapShape3D height at fractional corner coordinates,
## so an inset vertex stays on the terrain surface instead of snapping to a corner.
func _sample_height(fx: float, fz: float, hs: HeightMapShape3D) -> float:
	var w: int = hs.map_width
	var d: int = hs.map_depth
	var lx: float = clampf(fx, 0.0, w - 1)
	var lz: float = clampf(fz, 0.0, d - 1)
	var x0: int = floori(lx)
	var z0: int = floori(lz)
	var x1: int = mini(x0 + 1, w - 1)
	var z1: int = mini(z0 + 1, d - 1)
	var tx: float = lx - x0
	var tz: float = lz - z0
	var h00: float = hs.map_data[z0 * w + x0]
	var h10: float = hs.map_data[z0 * w + x1]
	var h01: float = hs.map_data[z1 * w + x0]
	var h11: float = hs.map_data[z1 * w + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
#endregion
