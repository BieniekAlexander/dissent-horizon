@tool
class_name Map
extends Node3D


### SPACE THINGS

#### TERRAIN
## The authored/generated source of truth for terrain: corner heights + per-cell tile
## types in one resource (see terrain-tile-types.md). When assigned, Map DERIVES the
## working `height_map` (below) and TerrainGrid's blocked mask from it. Maps not yet
## migrated leave this null and assign `height_map` directly.
@export var terrain_data: TerrainData:
	set(v):
		if terrain_data != null and terrain_data.changed.is_connected(_on_terrain_data_changed):
			terrain_data.changed.disconnect(_on_terrain_data_changed)
		terrain_data = v
		# React to inspector edits of the resource itself (e.g. its dimensions), not just to
		# a whole-resource reassignment. The terrain brush edits the arrays by direct
		# assignment (no `changed` emission), so it drives its own rebuilds without routing here.
		if terrain_data != null and not terrain_data.changed.is_connected(_on_terrain_data_changed):
			terrain_data.changed.connect(_on_terrain_data_changed)
		if is_node_ready() and Engine.is_editor_hint():
			_sync_from_terrain_data()

## The working heightmap: terrain extent + corner heights. DERIVED from terrain_data when
## one is assigned (rebuilt each load), else authored directly for un-migrated maps. Read
## by TerrainGrid / NavManager / HeightmapMeshGenerator and used as the picking collider.
@export var height_map: HeightMapShape3D:
	set(v):
		height_map = v
		if is_node_ready() and Engine.is_editor_hint():
			_on_height_map_replaced()

## StaticBody3D retained as a physics collider for terrain raycasts.
@onready var terrain_body: StaticBody3D = $NavigationRegion/Body

## CollisionShape3D on the terrain body; kept in sync with height_map at runtime
## so the physics shape always matches the authoritative heightmap resource.
@onready var _terrain_collision_shape: CollisionShape3D = $NavigationRegion/Body/Shape

@onready var nav_region: NavigationRegion3D = $NavigationRegion

## World-space side length of one terrain cell.
## Encoded as Map's own scale (set to 1 in the scene) so that
## global_transform serves directly as the heightmap-to-world frame.
const CELL_SIZE: float = 1.0

#### GRID
var cell_grid: Array = []

# Maps each grid-occupying Entity to the cells it covers. Any Entity with an
# Structure registers here (units don't; non-commandable structures like Deposit do).
var structure_cell_map: Dictionary = {}  # Entity -> Array[Vector2i]

# The per-cell "no-go" overlay now lives in `terrain_data.tile_types` — a cell is a
# permanent barrier when its tile type is impassable (see TerrainData.blocked_mask).
# The old `blocked_cells` export was cut once s1 was migrated, and terrain is now edited
# with the Terrain Brush plugin (addons/terrain_brush). See terrain-tile-types.md.

var terrain_grid: TerrainGrid
var nav_manager: NavManager


## When terrain_data drives the terrain, height_map is a DERIVED runtime artifact — keep
## it visible in the inspector but don't serialize it, so the scene never stores a stale
## duplicate of the heightmap alongside the authoritative terrain_data.
func _validate_property(property: Dictionary) -> void:
	if property.name == "height_map" and terrain_data != null:
		property.usage &= ~PROPERTY_USAGE_STORAGE


# --- Coordinate helpers ----------------------------------------------------

## Convert a grid cell (integer indices) to the world XZ centre of that cell.
## Y is taken from the terrain surface at the cell centre corner; for flat
## maps with uniform height this is the actual surface Y.
## Returns Vector3.INF for a cell outside the heightmap (same off-surface
## sentinel used by get_navmesh_line_hit / SU._project_to_nav_surface) instead
## of indexing map_data out of bounds.
func grid_to_world(cell: Vector2i) -> Vector3:
	var hs := height_map
	if cell.x < 0 or cell.y < 0 or cell.x > hs.map_width - 2 or cell.y > hs.map_depth - 2:
		return Vector3.INF
	var hw   := (hs.map_width  - 1) * 0.5
	var hd   := (hs.map_depth  - 1) * 0.5
	# Cell centre is at the average of its four corners in local space.
	var cx   := cell.x + 0.5
	var cz   := cell.y + 0.5
	# Bilinear-sample the four surrounding corners for a smoother Y.
	var h00  := hs.map_data[cell.y       * hs.map_width + cell.x    ]
	var h10  := hs.map_data[cell.y       * hs.map_width + cell.x + 1]
	var h11  := hs.map_data[(cell.y + 1) * hs.map_width + cell.x + 1]
	var h01  := hs.map_data[(cell.y + 1) * hs.map_width + cell.x    ]
	var h_center := (h00 + h10 + h11 + h01) * 0.25
	var local_pos := Vector3(cx - hw, h_center, cz - hd)
	return global_transform * local_pos

## Return the world-space Y of the terrain surface at world_xz.
## Bilinearly interpolates between the four surrounding HeightMapShape3D corners,
## then applies terrain_body.global_transform so the result is in world space.
func terrain_height_at(world_xz: Vector2) -> float:
	var hs := height_map
	var hw := (hs.map_width  - 1) * 0.5
	var hd := (hs.map_depth  - 1) * 0.5
	# Convert world XZ to heightmap corner-index float coordinates.
	var local := global_transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var lx    := clampf(local.x + hw, 0.0, hs.map_width  - 1)
	var lz    := clampf(local.z + hd, 0.0, hs.map_depth  - 1)
	var cx0   := floori(lx)
	var cz0   := floori(lz)
	var cx1   := mini(cx0 + 1, hs.map_width  - 1)
	var cz1   := mini(cz0 + 1, hs.map_depth  - 1)
	var fx    := lx - cx0
	var fz    := lz - cz0
	var h00   := hs.map_data[cz0 * hs.map_width + cx0]
	var h10   := hs.map_data[cz0 * hs.map_width + cx1]
	var h01   := hs.map_data[cz1 * hs.map_width + cx0]
	var h11   := hs.map_data[cz1 * hs.map_width + cx1]
	var h_local := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	return (global_transform * Vector3(local.x, h_local, local.z)).y

## Convert a world XZ position to the nearest grid cell indices.
## This is the exact inverse of grid_to_world: it undoes the terrain_body
## transform and the (map_width-1)/2 centering that grid_to_world applies.
func world_to_grid(world_xz: Vector2) -> Vector2i:
	var hs := height_map
	var hw := (hs.map_width  - 1) * 0.5
	var hd := (hs.map_depth  - 1) * 0.5
	var local := global_transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	return Vector2i(floori(local.x + hw), floori(local.z + hd))


## Footprint origin (min-x/min-z cell) for a structure of `dims` whose CENTER is
## at world_xz. Parity-correct: a structure centers on a cell when a dimension is
## ODD and on a grid corner (between cells) when EVEN. Rounding the origin in
## continuous corner-space (rather than flooring the centre cell) makes this
## idempotent — snapping a structure then reading its position back yields the
## same origin, including for 2x2 footprints.
func footprint_origin(world_xz: Vector2, dims: Vector2i) -> Vector2i:
	var hs := height_map
	var local := global_transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var cx := local.x + (hs.map_width  - 1) * 0.5
	var cz := local.z + (hs.map_depth  - 1) * 0.5
	return Vector2i(roundi(cx - dims.x * 0.5), roundi(cz - dims.y * 0.5))


## World-space centroid of the `dims` footprint anchored at `origin` (averages the
## cell centres, so terrain height is sampled too). This is the same placement
## add_structure uses, and the editor terrain-snap plugin snaps to the same point.
func footprint_centroid(origin: Vector2i, dims: Vector2i) -> Vector3:
	var centroid := Vector3.ZERO
	var count := 0
	for w in range(dims.x):
		for l in range(dims.y):
			var cell := origin + Vector2i(w, l)
			if not grid_coordinates_in_bounds(cell):
				continue
			centroid += grid_to_world(cell)
			count += 1
	return centroid / count if count > 0 else grid_to_world(origin)


## The in-bounds grid cells a `dims` structure occupies when its CENTER is at
## world_center. Single source of truth for the footprint rectangle: add_structure
## registers exactly these cells, and the build-reach proximity check measures
## against them, so "close enough to place" and "close enough to build" agree.
func footprint_cells(world_center: Vector2, dims: Vector2i) -> Array[Vector2i]:
	var origin := footprint_origin(world_center, dims)
	var cells: Array[Vector2i] = []
	for w in range(dims.x):
		for l in range(dims.y):
			var cell := Vector2i(origin.x + w, origin.y + l)
			if grid_coordinates_in_bounds(cell):
				cells.append(cell)
	return cells


# --- Map bounds ------------------------------------------------------------

## Returns [low: Vector2, high: Vector2] in grid-cell index space.
## Compatible with the legacy call shape used by fog.gd.
func get_min_max() -> Array:
	var bounds := terrain_grid.get_bounds()
	return [Vector2(bounds[0]), Vector2(bounds[1])]


# --- Entity placement ------------------------------------------------------

## Add a batch of [Entity] instances to the map under [a_commander].
## Structures are placed individually via add_structure. Non-structure entities
## are positioned together with a single get_nonoverlapping_points call so the
## whole batch lands without same-frame broadphase overlap.
## Position is set BEFORE initialize (add_child) so the physics server registers
## each entity at the correct world position from the start — not at (0,0,0).
func add_entities(a_entities: Array, a_location: Vector2, a_commander: Commander) -> void:
	var units: Array = []
	for entity: Entity in a_entities:
		# Any entity with an Structure occupies the grid as a structure — this is
		# no longer gated on Commandable, so non-commandable structures (Deposit)
		# register too.
		if entity.get_node_or_null("Structure") != null:
			entity.initialize(self, a_commander)
			add_structure(entity, a_location, 0, false)
		else:
			units.append(entity)

	if units.is_empty():
		return

	# The largest radius in the batch, not just units[0]'s: a mixed batch (e.g. a
	# faction's starting_units) sizes candidate spacing/clearance for its biggest
	# member, so a smaller unit type earlier in the array doesn't undersize the
	# clearance a larger one later in the array actually needs.
	var radius: float = 0.0
	for unit: Entity in units:
		radius = maxf(radius, unit.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION))
	var region_radius: float = maxf(5.0, radius * 2.5 * float(maxi(units.size(), 1)))
	var points: Array[Vector2] = []
	if radius > 0.0:
		points = SU.get_nonoverlapping_points(
			self,
			a_location,
			radius,
			get_world_3d(),
			# STRUCTURE_BLOCKER (in addition to MOVEMENT_OBSTRUCTION) so candidates
			# also clear any structure's TargetBody — structures drop MOVEMENT_OBSTRUCTION
			# once grid-registered (see refresh_movement_collision) and rely on the
			# navmesh for exclusion instead, but a just-placed structure's navmesh
			# exclusion can still be mid-rebuild/unsynced at this point (see
			# Skirmish._deploy_all_forces), so this catches it regardless of that timing.
			CollisionLayers.Mask.MOVEMENT_OBSTRUCTION | CollisionLayers.Mask.STRUCTURE_BLOCKER,
			region_radius,
			units.size()
		)

	for i: int in units.size():
		var placement_xz: Vector2 = points[i] if i < points.size() else a_location
		# Snap to the nearest navigable location so units never spawn inside a
		# building or other non-navigable cell — e.g. an interaction event that
		# spawns a unit anchored on the target structure. No-op for points that
		# are already on the navmesh.
		var snapped_xz: Vector2 = VU.inXZ(nearest_navmesh_point(
			Vector3(placement_xz.x, terrain_height_at(placement_xz), placement_xz.y)
		))
		units[i].position = Vector3(
			snapped_xz.x,
			terrain_height_at(snapped_xz),
			snapped_xz.y
		)
		units[i].initialize(self, a_commander)

## Convenience wrapper for placing a single entity. See add_entities.
func add_entity(a_entity: Entity, a_location: Vector2, a_commander: Commander) -> void:
	add_entities([a_entity], a_location, a_commander)


## Register a structure on the grid, centred on `world_center` (world-space XZ).
## The footprint origin is resolved with footprint_origin() — the SAME function the
## editor terrain-snap plugin, the build preview (Entity.valid_placement) and
## scene auto-init use — so a structure occupies the identical cells and lands at the
## identical position in every case (even-sized footprints centre on a grid corner,
## odd on a cell).
func add_structure(a_structure: Entity, world_center: Vector2, rotation: int = 0, _rebake: bool = true) -> void:
	# Mines don't occupy the grid: they OVERLAY a Deposit (which stays the sole grid
	# occupant). Link the mine to its deposit — the authored/build-set `deposit`
	# reference if present, otherwise the deposit registered at the centre cell — and
	# sit it on top, without touching cell_grid / terrain_grid.
	if a_structure is Mine:
		var mine := a_structure as Mine
		var dep: Deposit = mine.deposit
		if dep == null:
			var cell := world_to_grid(world_center)
			if grid_coordinates_in_bounds(cell):
				dep = cell_grid[cell.x][cell.y] as Deposit
		if dep == null:
			push_error("Mine placed with no Deposit at %s — ignoring" % world_center)
			return
		mine.map = self
		mine.bind_deposit(dep)
		mine.global_position = dep.global_position
		# Not a grid obstruction → keep MOVEMENT_OBSTRUCTION (the deposit handles
		# navmesh exclusion for these cells).
		mine.refresh_movement_collision()
		return

	# Footprint size from the Structure component (1×1 fallback). footprint_origin
	# centres the structure parity-correctly; footprint_centroid is the same point
	# the editor terrain-snap plugin snaps to.
	var obs := a_structure.get_node_or_null("Structure") as Structure
	var dims: Vector2i = obs.dimensions if obs != null else Vector2i.ONE
	var footprint: Array[Vector2i] = footprint_cells(world_center, dims)
	for cell: Vector2i in footprint:
		cell_grid[cell.x][cell.y] = a_structure

	a_structure.global_position = footprint_centroid(footprint_origin(world_center, dims), dims)
	structure_cell_map[a_structure] = footprint
	terrain_grid.place_building(footprint, a_structure)
	a_structure.map = self
	# Now registered as a grid obstruction — drop MOVEMENT_OBSTRUCTION so moving
	# units route around it via the navmesh instead of colliding with its body.
	a_structure.refresh_movement_collision()


func remove_structure(a_structure: Entity, _rebake: bool = true) -> void:
	var cells: Array = terrain_grid.get_building_cells(a_structure)
	for cell: Vector2i in cells:
		cell_grid[cell.x][cell.y] = null
	terrain_grid.remove_building(a_structure)
	structure_cell_map.erase(a_structure)
	# No longer occupying the grid — restore MOVEMENT_OBSTRUCTION on the root.
	if is_instance_valid(a_structure):
		a_structure.refresh_movement_collision()


## Apply a per-cell impassability mask (water / hazard / scripted no-go) on top of
## the terrain.  Cell-indexed (index = z*(map_width-1)+x); empty clears it.  The
## navmesh rebuilds automatically to route around the blocked cells.  See
## BlockMaskGenerator for a connectivity-safe producer.
func set_blocked_mask(mask: PackedByteArray) -> void:
	if terrain_grid != null:
		terrain_grid.set_blocked_mask(mask)



## Snap `world_pos` to the closest point on the navigation mesh. Used when
## placing units so they never land inside a building or other non-navigable
## cell (the navmesh excludes those). A no-op for points already on the navmesh.
## Returns `world_pos` unchanged when the navigation map hasn't synced yet, so
## callers degrade to the requested position rather than collapsing to the map
## origin (which is what map_get_closest_point returns for an empty map).
func nearest_navmesh_point(world_pos: Vector3) -> Vector3:
	if nav_region == null:
		return world_pos
	var nav_map: RID = nav_region.get_navigation_map()
	if not nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return world_pos
	return NavigationServer3D.map_get_closest_point(nav_map, world_pos)


# Returns the first point on the navmesh along a line, or Vector3.INF if none.
# from and to are Vector3, nav_map is a RID from a NavigationRegion3D.
func get_navmesh_line_hit(
	from: Vector3,
	to: Vector3,
	max_step: float = 0.5
) -> Vector3:
	var nav := NavigationServer3D

	var dir := to - from
	var length := dir.length()
	if length == 0.0:
		return Vector3.INF
	dir /= length

	var t := 0.0
	while t <= length:
		var p := from + dir * t
		var nav_p := nav.map_get_closest_point(nav_region.get_navigation_map(), p)

		if nav_p.distance_to(p) < 0.1: return nav_p
		t += max_step

	return Vector3.INF


### MOVEMENT AND COLLISION
var units: Array:
	get: return get_tree().get_nodes_in_group("commandable").filter(func(c: Entity): return c.is_in_group("unit"))

## returns a dictionary describing what a line hit in space
func line_hit(from: Vector3, to: Vector3, layer_mask: int) -> Variant:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, layer_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result: Dictionary = space_state.intersect_ray(query)
	return null if result.is_empty() else result

# Returns whether `coords` is within the cell_grid bounds.
func grid_coordinates_in_bounds(coords: Vector2i) -> bool:
	return (
		coords.x >= 0 and coords.x < cell_grid.size()
		and coords.y >= 0 and coords.y < (cell_grid[0].size() if not cell_grid.is_empty() else 0)
	)


#region Node
func _ready() -> void:
	if Engine.is_editor_hint():
		if terrain_data != null:
			_sync_from_terrain_data()
		return

	# Derive the working heightmap from the authored TerrainData (heights layer). Maps
	# not yet migrated fall back to a directly-assigned height_map.
	if terrain_data != null:
		height_map = terrain_data.to_height_shape()
	assert(height_map   != null, "Map: assign terrain_data (or height_map) in the inspector")
	assert(terrain_body != null, "Map: terrain_body node not found at NavigationRegion/Body")

	_terrain_collision_shape.shape = height_map

	terrain_grid = TerrainGrid.new()
	terrain_grid.height_map   = height_map
	terrain_grid.terrain_body = terrain_body
	add_child(terrain_grid)

	# Initialize cell_grid from heightmap dimensions.
	cell_grid = []
	for x in range(terrain_grid.grid_width()):
		var inner := []
		for _z in range(terrain_grid.grid_depth()):
			inner.append(null)
		cell_grid.append(inner)

	# Apply the tile-type-derived no-go overlay before the navmesh first builds, so the
	# initial navmesh already excludes impassable-typed cells (water / forest / no-go).
	if terrain_data != null:
		terrain_grid.set_blocked_mask(terrain_data.blocked_mask())

	nav_manager = NavManager.new()
	nav_manager.navigation_region = nav_region
	nav_manager.terrain_grid      = terrain_grid
	add_child(nav_manager)

#endregion


# ---------------------------------------------------------------------------
# Editor pins (editor-only)
# ---------------------------------------------------------------------------

## Inspector trigger: (re)build the visual terrain mesh from the current map fields.
## Creates a HeightmapMeshGenerator under the terrain body if one doesn't exist, then
## syncs its shape to height_map and rebuilds the ArrayMesh — so a fresh map gets a
## generated mesh, and a mesh that drifted from the heightmap is brought back in sync.
@export var generate_visual_mesh: bool:
	set(_v): _regenerate_visual_mesh()

# ---------------------------------------------------------------------------
# Map mirroring (editor-only authoring tool)
# ---------------------------------------------------------------------------

## A mirror axis. HORIZONTAL is the map's vertical centre line (splits left/right);
## VERTICAL is the horizontal centre line (splits bottom/top); NONE means no axis.
enum MirrorAxis { NONE, HORIZONTAL, VERTICAL }

## The PRIMARY axis picks which half is the reference (kept and copied):
## HORIZONTAL keeps the LEFT half (min-X); VERTICAL keeps the BOTTOM half (max-Z,
## +Z / south). NONE disables the mirror.
@export var mirror_primary_axis: MirrorAxis = MirrorAxis.HORIZONTAL

## The SECONDARY axis controls how the reference half is transformed onto the
## opposite half:
##   NONE                 → pure reflection across the primary axis (mirror image).
##   opposite of primary  → reflection across BOTH axes, i.e. a 180° point
##                          reflection through the centre — the copied half is also
##                          flipped along the primary axis (point-symmetric map).
## A secondary equal to the primary (or NONE) is treated as "no secondary flip".
@export var mirror_secondary_axis: MirrorAxis = MirrorAxis.NONE

## Inspector trigger (toggling either way runs the op, like generate_visual_mesh).
## Mirrors the map per mirror_primary_axis / mirror_secondary_axis:
##   1. the reference half's heightmap corners are copied onto the opposite half,
##   2. every game entity on the opposite half is erased from the scene, then
##   3. every game entity on the reference half is duplicated and transformed onto
##      the opposite half (commander 1 ↔ 2 swapped on the copies).
@export var mirror_map: bool:
	set(_v): _run_mirror()


## Resolve the primary/secondary axis exports into the two booleans the mirror
## implementation takes, then run it. Primary NONE is a no-op.
func _run_mirror() -> void:
	if mirror_primary_axis == MirrorAxis.NONE:
		push_warning("Map.mirror_map: primary axis is NONE — nothing to mirror")
		return
	var primary_horizontal: bool = mirror_primary_axis == MirrorAxis.HORIZONTAL
	# A secondary flip only applies when the secondary is the OTHER axis; NONE or
	# the same-as-primary means a plain mirror.
	var flip_secondary: bool = (
		mirror_secondary_axis != MirrorAxis.NONE
		and mirror_secondary_axis != mirror_primary_axis
	)
	_mirror_map(primary_horizontal, flip_secondary)




func _on_height_map_replaced() -> void:
	if height_map == null:
		return
	_rebuild_visual_mesh()
	if _terrain_collision_shape != null:
		_terrain_collision_shape.shape = height_map


## Editor helper for the terrain brush: rebuild just the visual terrain mesh from the
## current terrain_data (fast — used live during a brush stroke, e.g. after painting tile
## types, so impassable cells punch/fill their mesh holes immediately).
func rebuild_terrain_mesh() -> void:
	_rebuild_visual_mesh()


## Editor helper for the height-sculpt brush: push the current terrain_data.heights into
## the LIVE height_map in place, rebuild the mesh, and re-seat editor-placed entities on the
## new surface.
func apply_terrain_heights_live() -> void:
	if terrain_data == null or height_map == null:
		return
	height_map.map_data = terrain_data.heights
	_rebuild_visual_mesh()
	_reseat_entities_on_terrain()


## Editor helper: full refresh after an external terrain_data edit (terrain brush stroke
## end, undo/redo). When the heights layer changed, updates the live height_map in place +
## collider, and re-seats editor-placed entities on the new surface; always rebuilds the mesh.
func rebuild_terrain_visuals(heights_changed: bool) -> void:
	if terrain_data == null:
		return
	if heights_changed and height_map != null:
		height_map.map_data = terrain_data.heights
		if _terrain_collision_shape != null:
			_terrain_collision_shape.shape = height_map
	_rebuild_visual_mesh()
	if heights_changed:
		_reseat_entities_on_terrain()


## Editor-only: snap every scene-placed game entity's Y to the terrain surface at its XZ, so
## brush height edits carry the entities with them (buildings/units sit on the new ground
## instead of floating or sinking). Purely EDITOR-VISUAL — at runtime units resample
## terrain_height_at every tick and structures are re-seated by add_structure, so this never
## affects gameplay. Reuses the same entity set as the mirror tool.
func _reseat_entities_on_terrain() -> void:
	if not Engine.is_editor_hint() or terrain_data == null:
		return
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	for node: Node3D in _collect_game_entities(root):
		var xz := Vector2(node.global_position.x, node.global_position.z)
		node.global_position.y = terrain_height_at(xz)


## Undo-routing helpers for the terrain brush. Registering brush undo ops as METHOD calls
## on Map (a scene node) — rather than a property op on the terrain_data Resource plus a
## method op on Map — keeps the whole action in ONE EditorUndoRedoManager history, avoiding
## the "UndoRedo history mismatch" error you get when an action mixes a Resource and a Node.
func set_terrain_heights(new_heights: PackedFloat32Array) -> void:
	if terrain_data == null:
		return
	terrain_data.heights = new_heights
	rebuild_terrain_visuals(true)


func set_terrain_tile_types(new_types: PackedByteArray) -> void:
	if terrain_data == null:
		return
	terrain_data.tile_types = new_types
	rebuild_terrain_visuals(false)


## Rebuild the working height_map from terrain_data (heights layer) and refresh the
## editor visuals. Called from _ready and the terrain_data setter. Setting height_map
## routes through its setter, which rebuilds the mesh when the node is already ready in
## the editor; we rebuild explicitly here to cover the _ready path too.
func _sync_from_terrain_data() -> void:
	if terrain_data == null:
		return
	height_map = terrain_data.to_height_shape()
	if Engine.is_editor_hint():
		if _terrain_collision_shape != null:
			_terrain_collision_shape.shape = height_map
		_rebuild_visual_mesh()


## Editor: the terrain_data resource itself was edited in the inspector (e.g. its dimensions
## or catalog changed, emitting `changed`). Re-derive the working heightmap, rebuild the
## mesh, and re-seat entities on the new surface. (The brush edits the arrays by direct
## assignment, which does NOT emit `changed`, so brush strokes never re-enter here.)
func _on_terrain_data_changed() -> void:
	if not Engine.is_editor_hint():
		return
	_sync_from_terrain_data()
	_reseat_entities_on_terrain()


func _rebuild_visual_mesh() -> void:
	if terrain_body == null:
		return
	var gen := terrain_body.get_node_or_null("HeightmapMeshGenerator") as HeightmapMeshGenerator
	if gen == null:
		return
	if gen.shape != height_map:
		gen.shape = height_map  # setter calls build() automatically
	else:
		gen.build()


## Inspector-button handler for generate_visual_mesh: ensure a HeightmapMeshGenerator
## exists under the terrain body (creating one if missing), then rebuild the terrain
## mesh from height_map.
func _regenerate_visual_mesh() -> void:
	if not Engine.is_editor_hint():
		return
	if height_map == null:
		push_warning("Map.generate_visual_mesh: no height_map assigned")
		return
	if terrain_body == null:
		push_warning("Map.generate_visual_mesh: terrain body ($NavigationRegion/Body) not ready")
		return
	_ensure_visual_mesh_generator()
	_rebuild_visual_mesh()


## Return the HeightmapMeshGenerator under the terrain body, creating and configuring
## one if it doesn't exist. A created generator is owned by the edited scene so it is
## saved (and rebuilds its mesh from `shape` on load / at runtime), and defaults to
## the game's checkerboard terrain shader so the mesh reads as terrain immediately.
func _ensure_visual_mesh_generator() -> HeightmapMeshGenerator:
	var gen := terrain_body.get_node_or_null("HeightmapMeshGenerator") as HeightmapMeshGenerator
	if gen != null:
		return gen

	gen = HeightmapMeshGenerator.new()
	gen.name = "HeightmapMeshGenerator"
	terrain_body.add_child(gen)
	gen.owner = get_tree().edited_scene_root

	# Default material: the game's terrain shader (build() keeps its grid params in
	# sync with the heightmap). Skipped gracefully if the shader can't be loaded.
	var shader := load("res://scenes/scenarios/s1.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("color_a", Color(0.22, 0.4, 0.22))
		mat.set_shader_parameter("color_b", Color(0.16, 0.3, 0.16))
		gen.material = mat
	return gen


# ---------------------------------------------------------------------------
# Map mirroring implementation (editor-only)
# ---------------------------------------------------------------------------

## Small tolerance (world units) for classifying an entity as on-axis: anything
## within this of the centre line is left untouched (it is its own mirror).
const _MIRROR_AXIS_EPS: float = 0.01


## Mirror the whole map — heightmap then entities — onto the opposite half.
## `primary_horizontal` true keeps the LEFT half (reflect left→right); false keeps
## the BOTTOM half (+Z, reflect bottom→top). `flip_secondary` additionally reflects
## across the OTHER axis, turning the plain mirror into a 180° point reflection.
## Editor-only: it mutates the scene tree and heightmap, meaningless at runtime.
func _mirror_map(primary_horizontal: bool, flip_secondary: bool) -> void:
	if not Engine.is_editor_hint():
		push_warning("Map.mirror_map is an editor-only authoring tool; ignoring at runtime")
		return
	if terrain_data == null:
		push_warning("Map.mirror_map: no terrain_data assigned")
		return
	_mirror_heights(primary_horizontal, flip_secondary)
	_mirror_tile_types(primary_horizontal, flip_secondary)
	_mirror_entities(primary_horizontal, flip_secondary)


## Copy the reference half's heightmap corners onto the opposite half so the two
## halves have identical terrain. Left (min-x) is the reference for a horizontal
## primary; bottom (max-z) for a vertical one. When `flip_secondary`, the source
## corner is additionally reflected across the other axis (point reflection). The
## centre column/row (odd sizes) is the axis and is left as-is.
func _mirror_heights(primary_horizontal: bool, flip_secondary: bool) -> void:
	var w := terrain_data.map_width()
	var d := terrain_data.map_depth()
	var data := terrain_data.heights  # a copy; mutate then assign back
	if primary_horizontal:
		for z in range(d):
			for x in range(w):
				var mx := w - 1 - x
				if x > mx:  # right (opposite) corner ← reference corner
					# Source is the mirror in X, plus the mirror in Z when flipping.
					var src_z := (d - 1 - z) if flip_secondary else z
					data[z * w + x] = data[src_z * w + mx]
	else:
		for z in range(d):
			var mz := d - 1 - z
			if z < mz:  # top (opposite) row ← reference row
				for x in range(w):
					# Source is the mirror in Z, plus the mirror in X when flipping.
					var src_x := (w - 1 - x) if flip_secondary else x
					data[z * w + x] = data[mz * w + src_x]
	terrain_data.heights = data
	_sync_from_terrain_data()   # re-derive height_map + collider, rebuild mesh


## Mirror the per-cell tile types to match the terrain, so the copied half reflects the
## reference half. Same reflect rule as _mirror_heights, on the cell grid (one smaller
## than the corner grid on each axis). No-op when tile_types is empty (all-Open).
func _mirror_tile_types(primary_horizontal: bool, flip_secondary: bool) -> void:
	if terrain_data.tile_types.is_empty():
		return
	var gw := terrain_data.grid_width()   # navigable cell columns
	var gd := terrain_data.grid_depth()   # navigable cell rows
	var t := terrain_data.tile_types  # a copy; mutate then assign back
	if primary_horizontal:
		for z in range(gd):
			for x in range(gw):
				var mx := gw - 1 - x
				if x > mx:  # right (opposite) cell ← reference cell
					var src_z := (gd - 1 - z) if flip_secondary else z
					t[z * gw + x] = t[src_z * gw + mx]
	else:
		for z in range(gd):
			var mz := gd - 1 - z
			if z < mz:  # top (opposite) row ← reference row
				for x in range(gw):
					var src_x := (gw - 1 - x) if flip_secondary else x
					t[z * gw + x] = t[mz * gw + src_x]
	terrain_data.tile_types = t
	_rebuild_visual_mesh()


## Erase every game entity on the opposite half, then duplicate every game entity
## on the reference half and reflect it across the centre. Mine→Deposit links are
## repointed to the duplicated deposits so mirrored mines bind correctly.
func _mirror_entities(primary_horizontal: bool, flip_secondary: bool) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	var center := global_transform.origin
	# The reference half is decided by the PRIMARY axis only; the secondary axis
	# just adds an extra reflection to where each copy lands.
	var axis_val: float = center.x if primary_horizontal else center.z

	# Classify each entity as reference / opposite / on-axis by its position along
	# the primary axis. Reference = left (min-x) for horizontal, bottom (max-z) for
	# vertical. Free opposite-side entities now; keep reference ones for copying.
	var reference: Array[Node3D] = []
	for node: Node3D in _collect_game_entities(root):
		var coord: float = node.global_position.x if primary_horizontal else node.global_position.z
		var delta: float = coord - axis_val
		if primary_horizontal:
			# left is reference, so reference sits at negative delta
			delta = -delta
		if delta > _MIRROR_AXIS_EPS:
			reference.append(node)          # reference half — copy across
		elif delta < -_MIRROR_AXIS_EPS:
			node.free()                     # opposite half — erase
		# else: on the axis — its own mirror, leave untouched

	# Duplicate each reference entity, transform its position onto the opposite
	# half, and parent it back into the scene (owner = scene root so it is saved).
	var orig_to_dup: Dictionary = {}
	for node: Node3D in reference:
		var dup: Node3D = node.duplicate()  # default flags keep instances + groups + script
		dup.name = String(node.name) + "_mirror"
		node.get_parent().add_child(dup)
		dup.owner = root
		# Reflect across the primary axis always; across the other axis too when a
		# secondary flip is requested (making it a 180° point reflection).
		var p := node.global_position
		var reflect_x: bool = primary_horizontal or flip_secondary
		var reflect_z: bool = not primary_horizontal or flip_secondary
		dup.global_position = Vector3(
			(2.0 * center.x - p.x) if reflect_x else p.x,
			p.y,
			(2.0 * center.z - p.z) if reflect_z else p.z
		)
		# The mirrored half belongs to the opposing player: swap commander 1 ↔ 2.
		# Neutral (0) and any other id are left as-is.
		_flip_commander_id(dup)
		orig_to_dup[node] = dup

	# Fix inter-entity references that duplicate() left pointing at originals: a
	# duplicated Mine still references the ORIGINAL deposit, so repoint it at that
	# deposit's duplicate (and sit it on top) when the deposit was mirrored too.
	for node: Node3D in reference:
		if node is Mine:
			var dup_mine := orig_to_dup[node] as Mine
			var orig_dep: Deposit = (node as Mine).deposit
			if orig_dep != null and orig_to_dup.has(orig_dep):
				var dup_dep := orig_to_dup[orig_dep] as Deposit
				dup_mine.deposit = dup_dep
				dup_mine.global_position = dup_dep.global_position


## Swap a mirrored entity's owner between commander 1 and 2 so the copied half
## belongs to the opposing player. Neutral (0) and any other id are untouched.
## No-op for non-Entity nodes (e.g. start-point markers have no commander).
func _flip_commander_id(node: Node3D) -> void:
	if node is Entity:
		var entity := node as Entity
		if entity.default_commander_id == 1:
			entity.default_commander_id = 2
		elif entity.default_commander_id == 2:
			entity.default_commander_id = 1


## Node3D game entities authored under `root` that the mirror should act on:
## anything in the "commandable", "structure" or "start_position" groups (deposits,
## mines, shelters, buildings, start markers, …). Excludes the Map's own subtree
## (terrain, nav, height pins) and de-duplicates across groups.
func _collect_game_entities(root: Node) -> Array[Node3D]:
	var seen: Dictionary = {}
	var result: Array[Node3D] = []
	for group: String in ["commandable", "structure", "start_position"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is Node3D and not seen.has(node) \
					and root.is_ancestor_of(node) \
					and node != self and not is_ancestor_of(node):
				seen[node] = true
				result.append(node as Node3D)
	return result
