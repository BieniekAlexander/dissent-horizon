@tool
class_name Map
extends Node3D


### SPACE THINGS

#### TERRAIN
## The heightmap resource that defines terrain extent and corner heights.
## This is the single source of truth for heightmap data; the StaticBody3D
## under NavigationRegion/Body may hold a reference to the same resource for
## physics collision but is no longer the authoritative data source.
@export var height_map: HeightMapShape3D:
	set(v):
		if height_map != null and height_map.changed.is_connected(_on_height_shape_changed):
			height_map.changed.disconnect(_on_height_shape_changed)
		height_map = v
		if is_node_ready() and Engine.is_editor_hint():
			_on_height_map_replaced()

## StaticBody3D retained as a physics collider for terrain raycasts.
@onready var terrain_body: StaticBody3D = $NavigationRegion/Body

## CollisionShape3D on the terrain body; kept in sync with height_map at runtime
## so the physics shape always matches the authoritative heightmap resource.
@onready var _terrain_collision_shape: CollisionShape3D = $NavigationRegion/Body/Shape

@onready var nav_region: NavigationRegion3D = $NavigationRegion

## Editor-only container that holds one HeightPin child per heightmap corner.
## Resolved lazily so it works even when the node doesn't exist in the scene yet.
var _pin_container: Node3D

## World-space side length of one terrain cell.
## Encoded as Map's own scale (set to 1 in the scene) so that
## global_transform serves directly as the heightmap-to-world frame.
const CELL_SIZE: float = 1.0

#### GRID
var cell_grid: Array = []

# Maps each grid-occupying Entity to the cells it covers. Any Entity with an
# Structure registers here (units don't; non-commandable structures like Deposit do).
var structure_cell_map: Dictionary = {}  # Entity -> Array[Vector2i]

## Authored per-cell "no-go" overlay (water / rubble / hazard / scripted block) and
## the SINGLE SOURCE OF TRUTH for it — saved with the scene and applied to the
## TerrainGrid at runtime. Cell indices, Vector2i(x, z), 0..grid_width-1 /
## 0..grid_depth-1. The editor BlockPins are only a view/edit surface over this list
## (see generate_editor_pins and BlockPin.blocked).
@export var blocked_cells: Array[Vector2i] = []

var terrain_grid: TerrainGrid
var nav_manager: NavManager


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
		_reconnect_pins()
		return

	assert(height_map   != null, "Map: height_map export must be assigned in the inspector")
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

	# Apply the authored no-go overlay before the navmesh first builds, so the
	# initial navmesh already excludes the blocked cells.
	if not blocked_cells.is_empty():
		terrain_grid.set_blocked_mask(_blocked_cells_to_mask())

	nav_manager = NavManager.new()
	nav_manager.navigation_region = nav_region
	nav_manager.terrain_grid      = terrain_grid
	add_child(nav_manager)

#endregion


# ---------------------------------------------------------------------------
# Editor pins (editor-only)
# ---------------------------------------------------------------------------

## Toggle to (re)spawn all editor authoring pins under Map:
##   - one HeightPin per heightmap corner (drag its Y to sculpt terrain), and
##   - one BlockPin per navigable cell (a view of blocked_cells; red = blocked).
## Both re-read the current map state, so this is safe to toggle any time to
## refresh the pins. Pins are editor-only and delete themselves at runtime.
@export var generate_editor_pins: bool:
	set(_v): _spawn_editor_pins()

## Inspector trigger: (re)build the visual terrain mesh from the current map fields.
## Creates a HeightmapMeshGenerator under the terrain body if one doesn't exist, then
## syncs its shape to height_map and rebuilds the ArrayMesh — so a fresh map gets a
## generated mesh, and a mesh that drifted from the heightmap is brought back in sync.
@export var generate_visual_mesh: bool:
	set(_v): _regenerate_visual_mesh()

var _pin_updating: bool = false


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

## Inspector trigger (toggling either way runs the op, like generate_editor_pins).
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


## Returns the HeightPins container, creating and registering it if necessary.
## Safe to call at any time — does not depend on @onready or _ready() order.
func _get_pin_container() -> Node3D:
	_pin_container = get_node_or_null("HeightPins") as Node3D
	if _pin_container == null:
		_pin_container = Node3D.new()
		_pin_container.name = "HeightPins"
		add_child(_pin_container)
		if Engine.is_editor_hint():
			_pin_container.owner = get_tree().edited_scene_root
	return _pin_container


## Reconnect callbacks for any HeightPin nodes already present in the scene
## (e.g. pins saved to the scene file from a previous Generate session).
## Called from _ready() in editor mode so pins work immediately on scene open.
func _reconnect_pins() -> void:
	if height_map == null:
		return
	var container: Node3D = _get_pin_container()
	if not height_map.changed.is_connected(_on_height_shape_changed):
		height_map.changed.connect(_on_height_shape_changed)
	for child in container.get_children():
		if child is HeightPin:
			if not child.height_changed.is_connected(_on_pin_height_changed):
				child.height_changed.connect(_on_pin_height_changed)
	# BlockPins carry no runtime signal wiring (they write through their `blocked`
	# setter directly), so there's nothing to reconnect — they're respawned from
	# blocked_cells by generate_editor_pins.


func _spawn_height_pins() -> void:
	if not Engine.is_editor_hint():
		return
	if terrain_body == null or height_map == null:  # terrain_body is @onready; null = not ready yet
		return

	var container := _get_pin_container()

	for child in container.get_children():
		if child is HeightPin:
			child.free()

	if height_map.changed.is_connected(_on_height_shape_changed):
		height_map.changed.disconnect(_on_height_shape_changed)
	height_map.changed.connect(_on_height_shape_changed)

	var w := height_map.map_width
	var d := height_map.map_depth
	var hw := (w - 1) * 0.5
	var hd := (d - 1) * 0.5
	var data := height_map.map_data

	var scene_root: Node = get_tree().edited_scene_root
	for z in d:
		for x in w:
			var idx := z * w + x
			var pin := HeightPin.new()
			pin.name = "HeightPin_%d_%d" % [x, z]
			pin.position = Vector3(x - hw, data[idx], z - hd)
			container.add_child(pin)
			pin.owner = scene_root
			pin.height_changed.connect(_on_pin_height_changed)


## Spawn both pin families (heightmap corners + blocked-cell markers). Both read
## current map state, so re-toggling generate_editor_pins refreshes the view.
func _spawn_editor_pins() -> void:
	_spawn_height_pins()
	_spawn_block_pins()


## Returns the BlockPins container, creating it if necessary. Like HeightPins, the
## container and its pins are OWNED by the edited scene (so the editor tracks them
## without the large-map add-node crash) and thus saved. blocked_cells remains the
## authoritative overlay — pins only mirror it and are regenerated by
## generate_editor_pins — and every pin self-deletes at runtime (BlockPin._ready).
func _get_block_pin_container() -> Node3D:
	var container := get_node_or_null("BlockPins") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "BlockPins"
		add_child(container)
		# Own the container (and its pins below) like HeightPins do. Adding thousands
		# of UN-owned nodes to the edited scene at once trips an editor-side crash on
		# large maps (LocalVector insert OOB); owned nodes are what the working height-
		# pin path uses. Pins still self-delete at runtime (BlockPin._ready), so being
		# saved is harmless — blocked_cells remains the source of truth.
		if Engine.is_editor_hint():
			container.owner = get_tree().edited_scene_root
	return container


## Spawn one BlockPin per navigable cell under BlockPins, coloured from the current
## blocked_cells list. Editor-only, and a full respawn (clears existing BlockPins
## first) so it always reflects blocked_cells.
func _spawn_block_pins() -> void:
	if not Engine.is_editor_hint():
		return
	if terrain_body == null or height_map == null:
		return

	var container := _get_block_pin_container()
	for child in container.get_children():
		if child is BlockPin:
			child.free()

	var w := height_map.map_width
	var d := height_map.map_depth
	var hw := (w - 1) * 0.5
	var hd := (d - 1) * 0.5
	var data := height_map.map_data
	var gw := w - 1  # navigable cells span one fewer than corners on each axis
	var gd := d - 1

	var blocked_lookup := {}
	for c: Vector2i in blocked_cells:
		blocked_lookup[c] = true

	var scene_root: Node = get_tree().edited_scene_root
	for z in gd:
		for x in gw:
			var cell := Vector2i(x, z)
			var pin := BlockPin.new()
			pin.name = "BlockPin_%d_%d" % [x, z]
			pin.cell = cell
			# Sit at the cell centre (between corners), lifted just above the average
			# corner height so the marker reads clearly over the terrain.
			var h_center: float = (
				data[z * w + x] + data[z * w + x + 1]
				+ data[(z + 1) * w + x] + data[(z + 1) * w + x + 1]
			) * 0.25
			pin.position = Vector3((x + 0.5) - hw, h_center + 0.1, (z + 0.5) - hd)
			container.add_child(pin)
			# Own the pin (like HeightPins) so the editor tracks it without the
			# large-map crash that adding un-owned nodes en masse triggers.
			pin.owner = scene_root
			# Seed the pin from the overlay WITHOUT writing back (it is the source).
			pin.set_blocked_silently(blocked_lookup.has(cell))


## Write-through from a BlockPin's `blocked` toggle: add or remove one cell in
## blocked_cells (the source of truth). Reassigns the array so the @tool inspector
## registers the change and the scene is marked dirty.
func set_cell_blocked(cell: Vector2i, value: bool) -> void:
	if blocked_cells.has(cell) == value:
		return
	var updated: Array[Vector2i] = blocked_cells.duplicate()
	if value:
		updated.append(cell)
	else:
		updated.erase(cell)
	blocked_cells = updated
	# Rebuild the visual mesh so blocking/clearing a cell punches/fills its hole
	# immediately, mirroring the instant terrain update on a HeightPin drag.
	_rebuild_visual_mesh()


## Convert blocked_cells into the cell-indexed PackedByteArray TerrainGrid expects
## (size grid_width*grid_depth, index = z*grid_width+x, 1 = blocked).
func _blocked_cells_to_mask() -> PackedByteArray:
	var gw := terrain_grid.grid_width()
	var gd := terrain_grid.grid_depth()
	var mask := PackedByteArray()
	mask.resize(gw * gd)  # zero-filled → all clear
	for c: Vector2i in blocked_cells:
		if c.x >= 0 and c.x < gw and c.y >= 0 and c.y < gd:
			mask[c.y * gw + c.x] = 1
	return mask


func _on_height_shape_changed() -> void:
	if _pin_updating or height_map == null:
		return
	var container := _get_pin_container()
	var expected := height_map.map_width * height_map.map_depth
	var actual := container.get_children().filter(func(c): return c is HeightPin).size()
	if expected != actual:
		_spawn_height_pins()
	else:
		_sync_height_pins()


func _sync_height_pins() -> void:
	if height_map == null:
		return
	var w := height_map.map_width
	var hw := (w - 1) * 0.5
	var hd := (height_map.map_depth - 1) * 0.5
	var data := height_map.map_data
	_pin_updating = true
	for child in _get_pin_container().get_children():
		if child is HeightPin:
			var gx := roundi(child.position.x + hw)
			var gz := roundi(child.position.z + hd)
			var idx := gz * w + gx
			if idx >= 0 and idx < data.size():
				child.position.y = data[idx]
	_pin_updating = false


func _on_height_map_replaced() -> void:
	if height_map == null:
		return
	if not height_map.changed.is_connected(_on_height_shape_changed):
		height_map.changed.connect(_on_height_shape_changed)
	_on_height_shape_changed()
	_rebuild_visual_mesh()
	if _terrain_collision_shape != null:
		_terrain_collision_shape.shape = height_map


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


func _on_pin_height_changed(pin: HeightPin) -> void:
	if _pin_updating or height_map == null:
		return

	var w := height_map.map_width
	var hw := (w - 1) * 0.5
	var hd := (height_map.map_depth - 1) * 0.5
	var gx := roundi(pin.position.x + hw)
	var gz := roundi(pin.position.z + hd)

	var expected_x := gx - hw
	var expected_z := gz - hd
	if not is_equal_approx(pin.position.x, expected_x) \
			or not is_equal_approx(pin.position.z, expected_z):
		_pin_updating = true
		pin.position.x = expected_x
		pin.position.z = expected_z
		_pin_updating = false

	var idx := gz * w + gx
	var data := height_map.map_data
	if idx < 0 or idx >= data.size() or is_equal_approx(data[idx], pin.position.y):
		return

	_pin_updating = true
	data[idx] = pin.position.y
	height_map.map_data = data
	_pin_updating = false

	_rebuild_visual_mesh()


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
	if height_map == null:
		push_warning("Map.mirror_map: no height_map assigned")
		return
	_mirror_heightmap(primary_horizontal, flip_secondary)
	_mirror_blocked_cells(primary_horizontal, flip_secondary)
	_mirror_entities(primary_horizontal, flip_secondary)


## Copy the reference half's heightmap corners onto the opposite half so the two
## halves have identical terrain. Left (min-x) is the reference for a horizontal
## primary; bottom (max-z) for a vertical one. When `flip_secondary`, the source
## corner is additionally reflected across the other axis (point reflection). The
## centre column/row (odd sizes) is the axis and is left as-is.
func _mirror_heightmap(primary_horizontal: bool, flip_secondary: bool) -> void:
	var w := height_map.map_width
	var d := height_map.map_depth
	var data := height_map.map_data  # a copy; mutate then assign back
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
	height_map.map_data = data
	if _terrain_collision_shape != null:
		_terrain_collision_shape.shape = height_map
	_on_height_shape_changed()  # resync/respawn HeightPins to the new data
	_rebuild_visual_mesh()


## Mirror the authored blocked-cell overlay to match the terrain: drop opposite-half
## blocked cells, keep the reference half, and add the reflection of each reference
## cell onto the opposite half. Uses the SAME reflect-X/reflect-Z rule as the entity
## mirror, on cell indices (grid is one smaller than the corner grid on each axis).
func _mirror_blocked_cells(primary_horizontal: bool, flip_secondary: bool) -> void:
	if blocked_cells.is_empty():
		return
	var gw := height_map.map_width - 1   # navigable cell columns
	var gd := height_map.map_depth - 1   # navigable cell rows

	# Keep only reference-half (and on-axis) cells; drop the opposite half. Reference
	# is left (min-x) for a horizontal primary, bottom (max-z) for a vertical one —
	# matching the heightmap/entity mirrors.
	var kept: Dictionary = {}
	for cell: Vector2i in blocked_cells:
		var on_opposite: bool = (
			cell.x > (gw - 1 - cell.x) if primary_horizontal
			else cell.y < (gd - 1 - cell.y)
		)
		if not on_opposite:
			kept[cell] = true

	# Add the reflection of every kept cell (on-axis cells reflect to themselves on
	# the primary axis, but still flip across the secondary when point-mirroring).
	var reflect_x: bool = primary_horizontal or flip_secondary
	var reflect_z: bool = not primary_horizontal or flip_secondary
	var result: Dictionary = {}
	for cell: Vector2i in kept.keys():
		result[cell] = true
		var rx: int = (gw - 1 - cell.x) if reflect_x else cell.x
		var rz: int = (gd - 1 - cell.y) if reflect_z else cell.y
		result[Vector2i(rx, rz)] = true

	var updated: Array[Vector2i] = []
	for cell: Vector2i in result.keys():
		updated.append(cell)
	blocked_cells = updated

	# Recolour existing BlockPins to the mirrored data (no-op if none are spawned).
	var container := get_node_or_null("BlockPins")
	if container != null and container.get_child_count() > 0:
		_spawn_block_pins()


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
