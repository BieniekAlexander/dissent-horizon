@tool
class_name Map
extends Node3D

### SPACE THINGS

#### TERRAIN
## THE ONE TERRAIN NUMBER AN AUTHOR SETS BY HAND: the play rectangle, in diamonds. Everything
## else about a map's shape is derived from it — TerrainData.dimensions is a pure function of
## play_size, and the surface mesh is built to fit.
##
## Forwarded to `terrain_data` rather than stored here, and deliberately NOT serialized (see
## _validate_property): the `.tres` owns the value, and a copy in the `.tscn` is a second
## source of truth that drifts. Shown here because this is where an author looks for it, not
## three levels down a nested resource inspector.
@export var play_size: Vector2i:
	get:
		return terrain_data.play_size if terrain_data != null else _play_size_fallback
	set(v):
		_play_size_fallback = v
		if terrain_data == null or terrain_data.play_size == v:
			return
		terrain_data.play_size = v
		if is_node_ready() and Engine.is_editor_hint():
			_sync_from_terrain_data()

## Backing store for `play_size` on a map with no terrain_data. A property with a custom getter
## cannot read its own name without recursing, so the fallback needs a field of its own.
var _play_size_fallback: Vector2i = Vector2i(50, 50)

## The authored/generated source of truth for terrain: corner heights + per-cell tile
## types in one resource (see gdd/systems/terrain-and-navigation/tile-types.md). When assigned, Map
## DERIVES the
## working `height_map` (below) and TerrainGrid's blocked mask from it. Maps not yet
## migrated leave this null and assign `height_map` directly.
@export var terrain_data: TerrainData:
	set(v):
		# IDEMPOTENT, and that is what keeps the editor alive rather than a nicety.
		#
		# Expanding a nested resource row in the inspector makes EditorPropertyResource WRITE THE
		# RESOURCE BACK to the property it came from — the same object, assigned again. Without
		# this guard that write ran the whole body, and `notify_property_list_changed()` below
		# tore down and rebuilt the inspector's property editors *while the inspector was still
		# building the sub-editors for that very row*. The editors it had already created were
		# freed mid-signal, which is exactly:
		#
		#   Object '<Object#...>' was freed or unreferenced while a signal is being emitted
		#   Cannot connect to 'property_list_changed': ... 'EditorInspector::_changed_callback'
		#
		# ...and the inspector was left holding a dead callback, so the NEXT attempt to open the
		# resource crashed. Nothing about the assignment is meaningful when the value has not
		# changed, so the cheapest correct answer is to do nothing at all.
		#
		# TerrainData.play_size guards itself the same way; setters that fan out to signals,
		# property-list rebuilds or scene edits should all be idempotent for this reason.
		if terrain_data == v:
			return
		if terrain_data != null and terrain_data.changed.is_connected(_on_terrain_data_changed):
			terrain_data.changed.disconnect(_on_terrain_data_changed)
		terrain_data = v
		# React to inspector edits of the resource itself (e.g. its play_size), not just to
		# a whole-resource reassignment. The terrain brush edits the arrays by direct
		# assignment (no `changed` emission), so it drives its own rebuilds without routing here.
		#
		# CONNECT_DEFERRED is load-bearing, not tidiness. _on_terrain_data_changed REPLACES
		# height_map (freeing the shape the EditorInspector may be displaying) and rebuilds the
		# terrain mesh. Run synchronously, that happens *inside* the `changed` emission — and
		# Godot propagates `changed` up from sub-resources, so merely expanding terrain_data's
		# source_mesh row in the inspector fires it. The result was "Object was freed or
		# unreferenced while a signal is being emitted from it", a dead
		# EditorInspector::_changed_callback, and an editor crash on the second attempt.
		# Deferring moves the rebuild out of the emission, which is exactly what that engine
		# error tells you to do.
		if terrain_data != null and not terrain_data.changed.is_connected(_on_terrain_data_changed):
			terrain_data.changed.connect(_on_terrain_data_changed, CONNECT_DEFERRED)
		# height_map's usage flags depend on whether terrain_data is set, and Godot caches the
		# property list — without this the inspector keeps showing the stale, editable row.
		notify_property_list_changed()
		if is_node_ready() and Engine.is_editor_hint():
			_sync_from_terrain_data()

## The working heightmap: terrain extent + corner heights. DERIVED from terrain_data when
## one is assigned (rebuilt each load), else authored directly for un-migrated maps. Read
## by TerrainGrid / NavManager / HeightmapMeshGenerator and used as the picking collider.
@export var height_map: HeightMapShape3D:
	set(v):
		# Idempotent for the same reason terrain_data is — this row is shown (read-only) whenever
		# terrain_data drives the terrain, so the inspector writes it back too, and
		# _on_height_map_replaced re-seats every entity in the scene.
		if height_map == v:
			return
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

# Maps each registered fixture to the cells it covers, including an extractor overlaying its
# site (which cell_grid still names as the occupant). Units never register here.
var structure_cell_map: Dictionary = {}  # Entity -> Array[Vector2i]

# The permanent per-cell barrier is everything out of play, void included
# (see TerrainData.blocked_mask); ground material never blocks.
# The old `blocked_cells` export was cut once s1 was migrated, and terrain is now edited
# with the Terrain Brush plugin (addons/terrain_brush). See
# gdd/systems/terrain-and-navigation/tile-types.md.

var terrain_grid: TerrainGrid
var nav_manager: NavManager

#### WATER
## Every WaterBody on this map, in no particular order. Bodies register themselves on
## initialize() and deregister on leaving the tree; nothing else writes this.
var water_bodies: Array[WaterBody] = []

## Cell -> the WaterBody covering it. An INDEX, rebuilt whole by refresh_water() rather than
## maintained incrementally — justified because the readers are per-frame (the cursor's water
## readout) and per-placement, and answering them by asking every body would be O(bodies) on
## a path that runs every frame. Water cells change only when a body is authored, so the
## index is rebuilt about as often as the map is loaded.
var _water_body_by_cell: Dictionary = {}  # Vector2i -> WaterBody

## The cosmetic layer — ground paint, trails, doodads — derived from this map by
## MapDecorationPlanner (map generation pass 7). Null until rebuild_decoration runs, and never
## saved: see gdd/systems/terrain-and-navigation/visual-facets.md.
var decorator: MapDecorator = null

## Whether the editor derives the decoration when the map opens. It costs a second or two on a
## large map, which is the reason to turn it off while sculpting.
@export var decorate_in_editor: bool = true


## Trims the inspector down to what an author actually sets, and keeps derived values out of
## the scene file. Three rules, each stated at the branch that applies it; between them the
## Map's terrain surface is `terrain_source_mesh` + `play_size` and nothing else.
func _validate_property(a_property: Dictionary) -> void:
	# HEIGHT_MAP IS NOT AN AUTHORING SURFACE once terrain_data drives the terrain: it is a
	# derived runtime artifact, rebuilt from `heights` at every load. Hidden outright rather
	# than greyed out, so the inspector shows one terrain source and not two. It stays a
	# normal editable export on the five maps that have no terrain_data and still author it
	# directly (tutorial, skirmish_tournament_desert, the kamikaze pair, test_scout_coverage).
	if a_property.name == "height_map" and terrain_data != null:
		a_property.usage &= ~PROPERTY_USAGE_STORAGE
		a_property.usage &= ~PROPERTY_USAGE_EDITOR
	# An inspector TRIGGER is a button wearing a checkbox: it carries no state worth keeping,
	# and a stored one is a loaded gun. `skirmish.tscn` shipped `create_terrain_mesh = true`
	# and `bake_terrain_from_mesh = true`, so every open of that scene flattened the authored
	# surface and then baked the flat mesh back over the heightfield — the "the map went flat
	# on its own" bug. Dropping STORAGE stops them being serialized at all; _fire_trigger
	# stops a value ALREADY sitting in a scene from acting.
	if a_property.name in TRIGGER_PROPERTIES:
		a_property.usage &= ~PROPERTY_USAGE_STORAGE
	# terrain_data is the BAKED ARTIFACT, not an authoring input: `terrain_source_mesh` is what
	# an author sets and `bake_terrain_from_mesh` is what writes this. Hidden from the inspector
	# so it cannot be repointed or cleared by accident — but still STORED, because it is how a
	# scene binds its map to its terrain and eight of them would otherwise lose it.
	if a_property.name == "terrain_data":
		a_property.usage &= ~PROPERTY_USAGE_EDITOR
	# play_size is a VIEW of terrain_data's: never stored here, and meaningless without one.
	if a_property.name == "play_size":
		a_property.usage &= ~PROPERTY_USAGE_STORAGE
		if terrain_data == null:
			a_property.usage |= PROPERTY_USAGE_READ_ONLY


## The inspector properties that are BUTTONS rather than data. Listed once, because two
## separate rules key off the same set (see _validate_property and _fire_trigger).
const TRIGGER_PROPERTIES: Array[StringName] = [
	&"create_terrain_mesh",
	&"bake_terrain_from_mesh",
	&"generate_visual_mesh",
	&"mirror_map",
	&"shift_map",
]

## True once _ready has run. Scene loading assigns stored property values BEFORE _ready, so
## this is what tells a genuine click apart from deserialization.
var _triggers_armed: bool = false


## Run an inspector trigger, or refuse to.
##
## TWO refusals, and both have bitten. A trigger fires only when the box is ticked TRUE — the
## inspector writes `false` back during its own construction and on revert, and an unguarded
## setter took that for a click. And it fires only once the node is ready, because a value
## already stored in a .tscn is assigned during LOAD: that is how opening `skirmish.tscn`
## silently ran "lay down a flat surface mesh" and then "bake it into the heightfield",
## overwriting both the authored `_surface.res` on disk and every height in the map.
func _fire_trigger(a_ticked: bool, a_action: Callable) -> void:
	if a_ticked and _triggers_armed:
		a_action.call()


# --- Coordinate helpers ----------------------------------------------------

## Cached inverse of global_transform — the world→local (heightmap frame) transform every
## XZ-to-grid conversion below needs.
##
## Inverting per call is small in isolation, but this is the hottest arithmetic path in the
## game: terrain_height_at runs twice per unit per physics tick and seven times for an aerial
## one (Movement's altitude look-ahead), so a few hundred units put it in the low thousands of
## reads per tick — every one recomputing the same matrix for a node that does not move.
##
## INVALIDATION IS ONE FRAME LATE, and that is safe here rather than merely tolerable.
## Godot does NOT deliver NOTIFICATION_TRANSFORM_CHANGED synchronously: setting `position`
## queues the node onto the scene tree's transform-change list, which is flushed before the
## next _process / _physics_process. So a caller that moves the Map and reads a terrain height
## before that flush gets the OLD frame. Nothing does: no scenario scene gives Map a transform
## at all (it is identity everywhere), and nothing assigns to its position or transform at
## runtime — the authoring tools edit terrain_data, not the node. Every gameplay read happens
## in _physics_process, after the flush.
##
## If the Map ever DOES become movable, this is the thing that breaks, and it breaks silently
## (stale heights for one frame). Call invalidate_transform_cache() at the point of the move
## rather than relying on the notification.
var _world_to_local: Transform3D
var _world_to_local_dirty: bool = true


## Ask for transform notifications so the cache above can be invalidated. In _enter_tree
## rather than _ready because _ready returns early under Engine.is_editor_hint(), and the
## editor is the one place the Map actually gets dragged around.
func _enter_tree() -> void:
	set_notify_transform(true)
	_world_to_local_dirty = true


func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_TRANSFORM_CHANGED:
		_world_to_local_dirty = true


## The world→local transform, i.e. global_transform.affine_inverse(), cached until this node
## moves. Use this instead of inverting global_transform on any per-unit or per-tick path.
func world_to_local_transform() -> Transform3D:
	if _world_to_local_dirty:
		_world_to_local = global_transform.affine_inverse()
		_world_to_local_dirty = false
	return _world_to_local


## Drop the cached world→local transform so the next read recomputes it. Only needed by a
## caller that moves the Map and must read terrain back in the SAME frame — the transform
## notification that normally invalidates it does not arrive until the next frame's flush.
func invalidate_transform_cache() -> void:
	_world_to_local_dirty = true


## Convert a grid cell (integer indices) to the world XZ centre of that cell.
## Y is taken from the terrain surface at the cell centre corner; for flat
## maps with uniform height this is the actual surface Y.
## Returns Vector3.INF for a cell outside the heightmap (same off-surface
## sentinel used by get_navmesh_line_hit / SU._project_to_nav_surface) instead
## of indexing map_data out of bounds.
func grid_to_world(a_cell: Vector2i) -> Vector3:
	var hs := height_map
	if a_cell.x < 0 or a_cell.y < 0 or a_cell.x > hs.map_width - 2 or a_cell.y > hs.map_depth - 2:
		return Vector3.INF
	var hw := (hs.map_width - 1) * 0.5
	var hd := (hs.map_depth - 1) * 0.5
	# Cell centre is at the average of its four corners in local space.
	var cx := a_cell.x + 0.5
	var cz := a_cell.y + 0.5
	# Bilinear-sample the four surrounding corners for a smoother Y.
	var h00 := hs.map_data[a_cell.y * hs.map_width + a_cell.x]
	var h10 := hs.map_data[a_cell.y * hs.map_width + a_cell.x + 1]
	var h11 := hs.map_data[(a_cell.y + 1) * hs.map_width + a_cell.x + 1]
	var h01 := hs.map_data[(a_cell.y + 1) * hs.map_width + a_cell.x]
	var h_center := (h00 + h10 + h11 + h01) * 0.25
	var local_pos := Vector3(cx - hw, h_center, cz - hd)
	return global_transform * local_pos


## The world position of grid CORNER `a_corner` — the point shared by the four cells around it,
## at the terrain's authored height there. Corners run 0..map_width-1, one more than cells, so
## cell (x, z) is bounded by corners (x, z) and (x+1, z+1). Clamped to the heightmap.
## For drawing cell borders that lie on the ground rather than cutting through it.
func grid_corner_to_world(a_corner: Vector2i) -> Vector3:
	var hs := height_map
	var c := Vector2i(
		clampi(a_corner.x, 0, hs.map_width - 1), clampi(a_corner.y, 0, hs.map_depth - 1)
	)
	var local_pos := Vector3(
		c.x - (hs.map_width - 1) * 0.5,
		hs.map_data[c.y * hs.map_width + c.x],
		c.y - (hs.map_depth - 1) * 0.5
	)
	return global_transform * local_pos


## The TerrainSurface drawing this map's authored surface mesh, or null when the map is drawn
## by a generated grid mesh instead. Exactly one of the two should ever be present.
func _terrain_surface() -> TerrainSurface:
	if terrain_body == null:
		return null
	return terrain_body.get_node_or_null("TerrainSurface") as TerrainSurface


## The ShaderMaterial the terrain surface is drawn with, whichever node is drawing it.
##
## A map's terrain is rendered by ONE of two nodes under the terrain body — HeightmapMeshGenerator
## for brush-sculpted heights, TerrainSurface for a modelled source mesh (see
## §Terrain can also be BAKED from a surface mesh). Consumers that need to push parameters into
## the terrain shader — Fog is the one today — must not care which, so the lookup lives here
## rather than being a node name spelled out at the call site.
##
## Null when neither node is present or its material is not a ShaderMaterial.
func terrain_material() -> ShaderMaterial:
	if terrain_body == null:
		return null
	var surface: TerrainSurface = _terrain_surface()
	if surface != null:
		return surface.material as ShaderMaterial
	var gen := terrain_body.get_node_or_null("HeightmapMeshGenerator") as HeightmapMeshGenerator
	if gen != null:
		return gen.material as ShaderMaterial
	return null


## The terrain's footprint as a world-space XZ rectangle.
##
## A HeightMapShape3D of map_width W spans W-1 cells, so the extent is (W-1) * CELL_SIZE,
## centred on this node — the same derivation grid_to_world uses, kept here so consumers
## (the camera's pan limits, the minimap's framing) do not each re-derive it.
##
## Empty Rect2 when no heightmap is resolved yet, which callers should treat as "no bounds
## to enforce" rather than as a zero-sized map.
func world_bounds() -> Rect2:
	var hs: HeightMapShape3D = height_map
	if hs == null:
		return Rect2()
	var span := Vector2(float(hs.map_width - 1), float(hs.map_depth - 1)) * CELL_SIZE
	return Rect2(VU.inXZ(global_position) - span * 0.5, span)


## The rectangle the game is actually played on.
##
## Prefers the AUTHORED play bounds (TerrainData.play_size), which are a rectangle in the
## screen-aligned (s, t) frame — a 45°-rotated rectangle in world XZ. That is the real play
## area; the heightmap around it is square, and its four corners are outside the game space.
##
## Falls back to the heightmap rectangle for a map that declares no play bounds, which is
## permissive rather than wrong: it bounds against everything that exists.
##
## Null when there is no heightmap to derive anything from — callers read that as "no bounds
## to enforce".
func play_area() -> PlayArea:
	var data: TerrainData = terrain_data
	if data != null:
		var half_st: Vector2 = data.play_half_extents()
		if half_st != Vector2.ZERO:
			return PlayArea.screen_aligned(VU.inXZ(global_position), half_st, CELL_SIZE)
	var bounds: Rect2 = world_bounds()
	if bounds.size == Vector2.ZERO:
		return null
	return PlayArea.axis_aligned(bounds.get_center(), bounds.size * 0.5)


## The world-space Y of the terrain surface at [a_world_xz]. Bilinearly interpolates between
## the four surrounding HeightMapShape3D corners, then applies terrain_body's transform so
## the result is in world space.
func terrain_height_at(a_world_xz: Vector2) -> float:
	var hs := height_map
	var hw := (hs.map_width - 1) * 0.5
	var hd := (hs.map_depth - 1) * 0.5
	# Convert world XZ to heightmap corner-index float coordinates.
	var local := world_to_local_transform() * Vector3(a_world_xz.x, 0.0, a_world_xz.y)
	var lx := clampf(local.x + hw, 0.0, hs.map_width - 1)
	var lz := clampf(local.z + hd, 0.0, hs.map_depth - 1)
	var cx0 := floori(lx)
	var cz0 := floori(lz)
	var cx1 := mini(cx0 + 1, hs.map_width - 1)
	var cz1 := mini(cz0 + 1, hs.map_depth - 1)
	var fx := lx - cx0
	var fz := lz - cz0
	var h00 := hs.map_data[cz0 * hs.map_width + cx0]
	var h10 := hs.map_data[cz0 * hs.map_width + cx1]
	var h01 := hs.map_data[cz1 * hs.map_width + cx0]
	var h11 := hs.map_data[cz1 * hs.map_width + cx1]
	var h_local := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	return (global_transform * Vector3(local.x, h_local, local.z)).y


## Convert a world XZ position to the nearest grid cell indices.
## This is the exact inverse of grid_to_world: it undoes the terrain_body
## transform and the (map_width-1)/2 centering that grid_to_world applies.
func world_to_grid(a_world_xz: Vector2) -> Vector2i:
	var point: Vector2 = world_to_grid_point(a_world_xz)
	return Vector2i(floori(point.x), floori(point.y))


## A world XZ position in continuous grid coordinates: cell (x, z) spans [x, x+1) × [z, z+1),
## so flooring this is world_to_grid. For walking a segment across cells.
func world_to_grid_point(a_world_xz: Vector2) -> Vector2:
	var hs := height_map
	var hw := (hs.map_width - 1) * 0.5
	var hd := (hs.map_depth - 1) * 0.5
	var local := world_to_local_transform() * Vector3(a_world_xz.x, 0.0, a_world_xz.y)
	return Vector2(local.x + hw, local.z + hd)


## Footprint origin (min-x/min-z cell) for a structure of `dims` whose CENTER is
## at world_xz. Parity-correct: a structure centers on a cell when a dimension is
## ODD and on a grid corner (between cells) when EVEN. Rounding the origin in
## continuous corner-space (rather than flooring the centre cell) makes this
## idempotent — snapping a structure then reading its position back yields the
## same origin, including for 2x2 footprints.
func footprint_origin(a_world_xz: Vector2, a_dims: Vector2i) -> Vector2i:
	var hs := height_map
	var local := world_to_local_transform() * Vector3(a_world_xz.x, 0.0, a_world_xz.y)
	var cx := local.x + (hs.map_width - 1) * 0.5
	var cz := local.z + (hs.map_depth - 1) * 0.5
	return Vector2i(roundi(cx - a_dims.x * 0.5), roundi(cz - a_dims.y * 0.5))


## World-space centroid of the `dims` footprint anchored at `origin` (averages the
## cell centres, so terrain height is sampled too). This is the same placement
## add_structure uses, and the editor terrain-snap plugin snaps to the same point.
func footprint_centroid(a_origin: Vector2i, a_dims: Vector2i) -> Vector3:
	var centroid := Vector3.ZERO
	var count := 0
	for w in range(a_dims.x):
		for l in range(a_dims.y):
			var cell := a_origin + Vector2i(w, l)
			if not grid_coordinates_in_bounds(cell):
				continue
			centroid += grid_to_world(cell)
			count += 1
	return centroid / count if count > 0 else grid_to_world(a_origin)


## The in-bounds grid cells a `dims` structure occupies when its CENTER is at
## world_center. Single source of truth for the footprint rectangle: add_structure
## registers exactly these cells, and the build-reach proximity check measures
## against them, so "close enough to place" and "close enough to build" agree.
func footprint_cells(a_world_center: Vector2, a_dims: Vector2i) -> Array[Vector2i]:
	var origin := footprint_origin(a_world_center, a_dims)
	var cells: Array[Vector2i] = []
	for w in range(a_dims.x):
		for l in range(a_dims.y):
			var cell := Vector2i(origin.x + w, origin.y + l)
			if grid_coordinates_in_bounds(cell):
				cells.append(cell)
	return cells


## The registered structure that a `dims` footprint aimed at `world_center` would sit
## exactly ON TOP OF — same centre point, not merely overlapping — or null.
##
## This is the geometry behind every "build X on top of an existing Y" rule in the game
## (an Extractor over its site, a Safehouse over a neutral Building). Those builds have ONE
## correct position per host, and this is what says so: an aim that only partly covers
## the host resolves to null and the build is refused, rather than being accepted and
## then quietly snapped onto the host at placement time.
##
## Concentric rather than identical, so a host and an overlay of DIFFERENT footprint
## sizes still line up on their shared centre. The test is exact integer arithmetic —
## `2*origin + dims` is the centre in half-cell units, which avoids comparing floats and
## keeps odd and even footprints (which centre on a cell and on a corner respectively) on
## one rule.
##
## The host's own footprint comes from structure_cell_map — what the grid actually holds,
## not what its Structure component declares — so a structure clipped at the map edge is
## judged by the cells it really occupies.
func concentric_structure(a_world_center: Vector2, a_dims: Vector2i) -> Entity:
	var origin: Vector2i = footprint_origin(a_world_center, a_dims)
	var host: Entity = null
	for cell: Vector2i in footprint_cells(a_world_center, a_dims):
		var occupant := cell_grid[cell.x][cell.y] as Entity
		if occupant != null:
			host = occupant
			break
	if host == null:
		return null
	var host_cells: Array = structure_cell_map.get(host, [])
	if host_cells.is_empty():
		return null
	var host_origin: Vector2i = host_cells[0]
	var host_far: Vector2i = host_cells[0]
	for cell: Vector2i in host_cells:
		host_origin = host_origin.min(cell)
		host_far = host_far.max(cell)
	var host_dims: Vector2i = host_far - host_origin + Vector2i.ONE
	var centred: bool = (host_origin * 2 + host_dims) == (origin * 2 + a_dims)
	return host if centred else null


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
##
## `a_unit_points` overrides the scatter with an authored arrangement, one world-XZ point per
## NON-STRUCTURE entity in order. Every point is still snapped onto navigable ground, so an
## authored slot that lands in a wall is corrected rather than obeyed.
func add_entities(
	a_entities: Array,
	a_location: Vector2,
	a_commander: Commander,
	a_unit_points: Array[Vector2] = []
) -> void:
	var units: Array = []
	for entity: Entity in a_entities:
		# A fixture-only piece — Actor or feature alike — registers on the grid. A two-form
		# piece spawns MOBILE here: this site has no opinion about its form.
		if entity.spawns_deployed():
			entity.initialize(self, a_commander)
			add_structure(entity, a_location, -1, false)
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
	# An AUTHORED arrangement (a faction's starting formation) is used as given, in the order
	# the units were passed — indexing the UNIT sublist, not a_entities, since structures were
	# filtered out above. Scattering is what happens when nobody has said where to stand.
	var points: Array[Vector2] = a_unit_points
	if points.is_empty() and radius > 0.0:
		points = (
			SU
			. get_nonoverlapping_points(
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
		)

	for i: int in units.size():
		var placement_xz: Vector2 = points[i] if i < points.size() else a_location
		# Snap to the nearest navigable location so units never spawn inside a
		# building or other non-navigable cell — e.g. an interaction event that
		# spawns a unit anchored on the target structure. No-op for points that
		# are already on the navmesh.
		var snapped_xz: Vector2 = VU.inXZ(
			nearest_navmesh_point(
				Vector3(placement_xz.x, terrain_height_at(placement_xz), placement_xz.y)
			)
		)
		units[i].position = Vector3(snapped_xz.x, terrain_height_at(snapped_xz), snapped_xz.y)
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
##
## `a_quarter_turns` orients the footprint (Structure.quarter_turns; the piece is turned to match).
## The default, -1, means "as the piece already is" — its own count, and its yaw left alone — which
## is what a placed blueprint, an event's spawn and a deploy all want.
## gdd/systems/terrain-and-navigation/footprint-rotation.md
func add_structure(
	a_structure: Entity, a_world_center: Vector2, a_quarter_turns: int = -1, _a_rebake: bool = true
) -> void:
	# Footprint size from the Structure component (1×1 fallback), turned to the piece's
	# orientation. footprint_origin centres the structure parity-correctly; footprint_centroid is
	# the same point the editor terrain-snap plugin snaps to.
	var obs := a_structure.get_node_or_null("Structure") as Structure
	if obs != null and a_quarter_turns >= 0:
		obs.quarter_turns = a_quarter_turns
	var dims: Vector2i = obs.footprint_dimensions() if obs != null else Vector2i.ONE
	var footprint: Array[Vector2i] = footprint_cells(a_world_center, dims)

	# OCCUPANCY and OBSTRUCTION are written separately. `cell_grid` names one occupant per cell,
	# so a structure placed over a HOST (an extractor on its extraction site) leaves the host
	# as the occupant; everything else about it is an ordinary placement. Why the two are split:
	# gdd/systems/terrain-and-navigation/map-composition.md §Occupancy and obstruction.
	var extractor: Extractor = Extractor.of(a_structure)
	var site: Entity = _extraction_site_under(extractor, a_world_center)
	if site != null and structure_cell_map.has(site):
		# The site's footprint is defined to equal the extractor's; take the cells it holds.
		footprint.assign(structure_cell_map[site])
	for cell: Vector2i in footprint:
		if cell_grid[cell.x][cell.y] == null:
			cell_grid[cell.x][cell.y] = a_structure
	structure_cell_map[a_structure] = footprint
	if decorator != null:
		decorator.clear_cells(footprint)
	if obs == null or obs.is_obstruction:
		terrain_grid.place_building(footprint, a_structure)
	a_structure.map = self

	if site != null:
		extractor.bind_extraction_site(site)
		a_structure.global_position = site.global_position
	else:
		a_structure.global_position = footprint_centroid(
			footprint_origin(a_world_center, dims), dims
		)
		# A pond-placed extractor draws from the body it now stands in.
		if extractor != null:
			extractor.bind_water_body(EnergyExtractor.water_body_under(self, a_world_center, dims))
	# Now registered on the grid — drop MOVEMENT_OBSTRUCTION, so moving units route around it
	# via the navmesh (or, for a fixture that does not obstruct, walk across it).
	a_structure.refresh_movement_collision()
	# A two-form piece registered here (deploy, or a build order laying it down) is now in its
	# deployed form. Out of the tree, Entity._ready settles it from the registration instead.
	if a_structure.has_two_forms() and a_structure.is_inside_tree():
		a_structure.set_deployed(true)


## The extraction site an extractor placed at `a_world_center` stands on: the authored/build-set
## `extraction_site` reference if present, otherwise the site occupying the centre cell. Null
## for anything that is not an extractor, and for an extractor in a lithium pond.
func _extraction_site_under(a_extractor: Extractor, a_world_center: Vector2) -> Entity:
	if a_extractor == null:
		return null
	if a_extractor.extraction_site != null:
		return a_extractor.extraction_site
	var cell: Vector2i = world_to_grid(a_world_center)
	if grid_coordinates_in_bounds(cell) and ExtractionSite.of(cell_grid[cell.x][cell.y]) != null:
		return cell_grid[cell.x][cell.y] as Entity
	return null


## Reads the footprint from structure_cell_map rather than from the terrain grid: a fixture
## that does not obstruct never registered there. Only cells this structure OCCUPIES are
## cleared, so removing an extractor leaves its site in place.
func remove_structure(a_structure: Entity, _a_rebake: bool = true) -> void:
	var cells: Array = structure_cell_map.get(a_structure, [])
	for cell: Vector2i in cells:
		if cell_grid[cell.x][cell.y] == a_structure:
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
func set_blocked_mask(a_mask: PackedByteArray) -> void:
	if terrain_grid != null:
		terrain_grid.set_blocked_mask(a_mask)


#region Water
## Adopt a WaterBody. Called by the body itself from WaterBody.initialize, so a body dropped
## into the scene at author time and one loaded with the map arrive by the same route.
func register_water_body(a_body: WaterBody) -> void:
	if a_body != null and not water_bodies.has(a_body):
		water_bodies.append(a_body)


func unregister_water_body(a_body: WaterBody) -> void:
	water_bodies.erase(a_body)
	refresh_water()


## Re-derive everything the map holds about water: the cell index, and the submerged mask the
## terrain grid navigates around.
##
## Republished as a WHOLE, over every body at once, because the grid holds a union — telling
## it about one body would silently clear the others. Cheap enough to do that way: bodies are
## authored, so this runs at load and on an authoring edit, not in the game loop.
func refresh_water() -> void:
	# A body being torn down deregisters mid-teardown, when its siblings may already be freed;
	# the validity check is what keeps that from taking the whole map's water layer with it.
	water_bodies = water_bodies.filter(func(b: WaterBody) -> bool: return is_instance_valid(b))
	_water_body_by_cell.clear()
	for body: WaterBody in water_bodies:
		for cell: Vector2i in body.basin.covered_cells():
			_water_body_by_cell[cell] = body
	if terrain_grid == null or not is_instance_valid(terrain_grid):
		return
	var gw: int = terrain_grid.grid_width()
	var mask := PackedByteArray()
	mask.resize(gw * terrain_grid.grid_depth())
	for cell: Vector2i in _water_body_by_cell:
		if (_water_body_by_cell[cell] as WaterBody).is_deep(cell):
			mask[cell.y * gw + cell.x] = 1
	terrain_grid.set_submerged_mask(mask)


## The water body covering `a_cell`, or null for dry ground. Cells are claimed by exactly one
## body: two bodies overlapping is an authoring error the water tool refuses to create.
func water_body_at(a_cell: Vector2i) -> WaterBody:
	return _water_body_by_cell.get(a_cell)


## The water body under a world-space XZ point, or null. What the cursor readout asks.
func water_body_at_world(a_world_xz: Vector2) -> WaterBody:
	return water_body_at(world_to_grid(a_world_xz))


## Every ShaderMaterial on this map that draws world geometry and therefore has to be told
## about the fog: the terrain, plus each water surface. Fog pushes the shroud into all of
## them — a surface left out of this list is silently unfogged.
func fogged_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	var terrain: ShaderMaterial = terrain_material()
	if terrain != null:
		result.append(terrain)
	if decorator != null:
		result.append_array(decorator.doodad_materials())
	for body: WaterBody in water_bodies:
		if not is_instance_valid(body):
			continue
		var surface: ShaderMaterial = body.surface_material()
		if surface != null:
			result.append(surface)
	return result


## Derive this map's decoration (pass 7) from its current terrain, water and pieces, and draw
## it: props under a MapDecorator child, ground paint into the terrain material. Rebuilt whole;
## the old decoration is discarded.
func rebuild_decoration() -> void:
	var planned: MapDecoration = MapDecorationPlanner.plan(MapDecorationInput.from_map(self))
	if decorator == null:
		decorator = MapDecorator.new()
		decorator.name = "Decoration"
		# Unowned: a derived node must never be written into the scene.
		add_child(decorator)
	decorator.show_decoration(
		planned, Vector2i(terrain_data.grid_width(), terrain_data.grid_depth())
	)
	TerrainShading.push_ground_overlay(terrain_material(), planned.ground_overlay)


## Hand every WaterBody in the scene its map and derive the water layer once. Runs after the
## terrain grid exists, because a body publishes submerged cells into it — and a child is
## ready before its parent, so the bodies cannot have done this for themselves.
func _initialize_water_bodies() -> void:
	for body: WaterBody in _collect_water_bodies(owner if owner != null else self):
		body.initialize(self)
	refresh_water()


## Every WaterBody under `a_root`. Searched from the SCENE ROOT that owns this Map rather than
## from the Map itself, so a body authored as a sibling of the map still finds it — the map is
## what owns the terrain, not what owns the scene layout. Falls back to the Map when it has no
## owner (built in code, as a test harness does).
func _collect_water_bodies(a_root: Node) -> Array[WaterBody]:
	var result: Array[WaterBody] = []
	if a_root == null:
		return result
	if a_root is WaterBody:
		result.append(a_root as WaterBody)
	for child: Node in a_root.get_children():
		result.append_array(_collect_water_bodies(child))
	return result


#endregion


## Snap `world_pos` to the closest point on the navigation mesh. Used when
## placing units so they never land inside a building or other non-navigable
## cell (the navmesh excludes those). A no-op for points already on the navmesh.
## Returns `world_pos` unchanged when the navigation map hasn't synced yet, so
## callers degrade to the requested position rather than collapsing to the map
## origin (which is what map_get_closest_point returns for an empty map).
func nearest_navmesh_point(a_world_pos: Vector3) -> Vector3:
	if nav_region == null:
		return a_world_pos
	var nav_map: RID = nav_region.get_navigation_map()
	if not nav_map.is_valid() or NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return a_world_pos
	return NavigationServer3D.map_get_closest_point(nav_map, a_world_pos)


# Returns the first point on the navmesh along a line, or Vector3.INF if none.
# from and to are Vector3, nav_map is a RID from a NavigationRegion3D.
func get_navmesh_line_hit(a_from: Vector3, a_to: Vector3, a_max_step: float = 0.5) -> Vector3:
	var nav := NavigationServer3D

	var dir := a_to - a_from
	var length := dir.length()
	if length == 0.0:
		return Vector3.INF
	dir /= length

	var t := 0.0
	while t <= length:
		var p := a_from + dir * t
		var nav_p := nav.map_get_closest_point(nav_region.get_navigation_map(), p)

		if nav_p.distance_to(p) < 0.1:
			return nav_p
		t += a_max_step

	return Vector3.INF


### MOVEMENT AND COLLISION
var units: Array:
	get:
		return get_tree().get_nodes_in_group("piece").filter(
			func(c: Entity): return c.is_in_group("unit")
		)


## returns a dictionary describing what a line hit in space
func line_hit(a_from: Vector3, a_to: Vector3, a_layer_mask: int) -> Variant:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(a_from, a_to, a_layer_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result: Dictionary = space_state.intersect_ray(query)
	return null if result.is_empty() else result


## Every collider the segment crosses on `a_layer_mask`, nearest end first.
##
## `line_hit` answers "what is in front", which is the wrong question whenever the thing in
## front should not win — cursor picking prefers a unit to the structure standing over it (see
## RTSController.get_cursor_target). Godot's ray query returns one result, so this walks the
## same segment repeatedly, excluding what it has already found.
##
## `a_max_hits` bounds that walk. Overlapping selection shapes along one ray are few, and an
## unbounded loop here would be a per-frame cost paid on every cursor move.
func line_hits(
	a_from: Vector3, a_to: Vector3, a_layer_mask: int, a_max_hits: int = 8
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(a_from, a_to, a_layer_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var excluded: Array[RID] = []
	for _attempt: int in a_max_hits:
		query.exclude = excluded
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			break
		hits.append(result)
		excluded.append(result["rid"])
	return hits


# Returns whether `coords` is within the cell_grid bounds.
func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
	return (
		a_coords.x >= 0
		and a_coords.x < cell_grid.size()
		and a_coords.y >= 0
		and a_coords.y < (cell_grid[0].size() if not cell_grid.is_empty() else 0)
	)


#region Node
func _ready() -> void:
	if Engine.is_editor_hint():
		if terrain_data != null:
			_sync_from_terrain_data()
			if decorate_in_editor:
				rebuild_decoration()
		# Only NOW may an inspector trigger act: everything a .tscn stored has already been
		# assigned by this point, so nothing that arrives with the scene can fire one.
		_triggers_armed = true
		return

	# Derive the working heightmap from the authored TerrainData (heights layer). Maps
	# not yet migrated fall back to a directly-assigned height_map.
	if terrain_data != null:
		height_map = terrain_data.to_height_shape()
	assert(height_map != null, "Map: assign terrain_data (or height_map) in the inspector")
	assert(terrain_body != null, "Map: terrain_body node not found at NavigationRegion/Body")

	_terrain_collision_shape.shape = height_map

	terrain_grid = TerrainGrid.new()
	terrain_grid.height_map = height_map
	terrain_grid.terrain_body = terrain_body
	add_child(terrain_grid)

	# Initialize cell_grid from heightmap dimensions.
	cell_grid = []
	for x in range(terrain_grid.grid_width()):
		var inner := []
		for _z in range(terrain_grid.grid_depth()):
			inner.append(null)
		cell_grid.append(inner)

	# Apply the out-of-play barrier (void included) before the navmesh first builds, so the
	# initial navmesh already excludes it.
	if terrain_data != null:
		terrain_grid.set_blocked_mask(terrain_data.blocked_mask())

	nav_manager = NavManager.new()
	nav_manager.navigation_region = nav_region
	nav_manager.terrain_grid = terrain_grid
	add_child(nav_manager)

	# After the grid exists and before the first navmesh bake: deep water is an impassability
	# reason like any other, and the initial mesh should already be cut around it.
	_initialize_water_bodies()

	# Before anything collects fogged_materials (Fog does on its own initialisation), so the
	# props are shrouded from the first frame.
	if terrain_data != null:
		rebuild_decoration()


#endregion

# ---------------------------------------------------------------------------
# Editor pins (editor-only)
# ---------------------------------------------------------------------------

## The authored surface MESH this map's heightfield is baked from, and the geometry
## TerrainSurface draws. Optional: leave null and the terrain brush remains the only author.
##
## ON THE MAP NODE rather than on TerrainData, and that placement is load-bearing. As a
## resource-valued property INSIDE a Resource it crashed the Godot editor — a Resource is drawn
## as a nested sub-inspector, and expanding a resource row within one freed objects mid-signal
## and then dereferenced null on the next open. Bisected: clearing the field made the crash
## stop on both test maps. It also reads better here — the mesh is an authoring input and the
## rendered geometry, both scene concerns, while TerrainData is the baked gameplay artifact.
@export var terrain_source_mesh: Mesh

## Applied to every vertex of `terrain_source_mesh` before rasterizing. Use it to scale a
## unit-sized export up to the map, or to recentre one modelled off the origin.
@export var terrain_source_mesh_transform: Transform3D = Transform3D()

## Height the flat surface `create_terrain_mesh` lays down, in world units.
@export var terrain_mesh_initial_height: float = 0.0

## Inspector trigger: replace terrain_source_mesh with a flat, BRUSHABLE grid surface at
## terrain_mesh_initial_height — the "New Map" step, mirroring World Builder's initial-height
## field. This is what you start from before sculpting; everything else on this map is derived
## from it.
##
## Saved next to terrain_data rather than embedded in the scene: the surface carries a vertex
## per grid corner (25,600 on an s1-sized map), and inlining that in the .tscn would bloat the
## scene text and make every diff unreadable.
@export var create_terrain_mesh: bool:
	set(v):
		_fire_trigger(v, _confirm_create_terrain_mesh)


## Ask before laying down a flat surface, because this is the only editor action in the file
## that DESTROYS authored work: it overwrites `<terrain_data>_surface.res` on disk and
## flattens every height in the map. Everything else here is derivable again from the mesh;
## the mesh is not derivable from anything.
func _confirm_create_terrain_mesh() -> void:
	if not Engine.is_editor_hint():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Replace the authored terrain surface?"
	dialog.dialog_text = (
		(
			"This REPLACES the terrain surface mesh with a flat grid at height %.2f, "
			+ "overwrites the saved surface next to %s, and flattens every height in the map.\n\n"
			+ "There is no undo. Use this only when starting a new map."
		)
		% [
			terrain_mesh_initial_height,
			terrain_data.resource_path.get_file() if terrain_data != null else "(no terrain_data)",
		]
	)
	dialog.ok_button_text = "Flatten"
	EditorInterface.get_base_control().add_child(dialog)
	dialog.confirmed.connect(_create_terrain_mesh)
	# The dialog is a throwaway: it is built per click so it can never hold a stale closure
	# over a Map that has since been freed.
	dialog.visibility_changed.connect(
		func() -> void:
			if not dialog.visible:
				dialog.queue_free()
	)
	dialog.popup_centered()


func _create_terrain_mesh() -> void:
	if not Engine.is_editor_hint():
		return
	if terrain_data == null:
		push_warning("Map.create_terrain_mesh: no terrain_data assigned")
		return
	var dims: Vector2i = terrain_data.dimensions
	var mesh: ArrayMesh = TerrainMeshGrid.create(dims, terrain_mesh_initial_height)

	var path: String = terrain_data.resource_path
	if path.is_empty():
		push_warning(
			"Map.create_terrain_mesh: terrain_data has no file, leaving the surface embedded"
		)
	else:
		var out: String = path.get_basename() + "_surface.res"
		var err: int = ResourceSaver.save(mesh, out)
		if err == OK:
			mesh = load(out)
			print("Map: wrote brushable surface to %s" % out)
		else:
			push_warning("Map.create_terrain_mesh: could not save %s (%d)" % [out, err])

	terrain_source_mesh = mesh
	# Bring the gameplay field in line with the surface we just laid down.
	set_terrain_heights(TerrainMeshGrid.read_heights(mesh, dims))
	print(
		(
			"Map: brushable surface %dx%d corners at height %.2f"
			% [dims.x, dims.y, terrain_mesh_initial_height]
		)
	)


## Inspector trigger: rasterize terrain_source_mesh into the heightfield.
##
## The button lives on the MAP rather than on TerrainData, even though the work is entirely the
## resource's, and that is deliberate. An @export whose setter does heavy work and emits
## `changed` is safe enough on a @tool NODE (generate_visual_mesh below is the same pattern)
## and a landmine on a RESOURCE: a resource is shown as a sub-inspector, gets instantiated for
## default/revert comparison, and propagates `changed` to its owner — so the trigger could fire
## from inspection itself and rebuild the map from inside the inspector's own signal.
@export var bake_terrain_from_mesh: bool:
	set(v):
		_fire_trigger(v, _bake_terrain_from_mesh)


func _bake_terrain_from_mesh() -> void:
	if not Engine.is_editor_hint():
		return
	if terrain_source_mesh == null:
		push_warning("Map.bake_terrain_from_mesh: no terrain_source_mesh assigned")
		return
	# A map with no terrain_data gets one, named after the surface it bakes from and sized to
	# it. The binding is then legible from the filename instead of being a slot to remember,
	# which is the whole reason terrain_data is no longer shown in the inspector.
	if terrain_data == null:
		terrain_data = _terrain_data_for_source_mesh()
		if terrain_data == null:
			return
	var report: Dictionary = terrain_data.bake_source_mesh(
		terrain_source_mesh, terrain_source_mesh_transform
	)
	print(
		(
			(
				"Map: baked %s -> %s: %d/%d corners covered, %d/%d cells voided"
				+ " (%d triangles, %d vertical)"
			)
			% [
				terrain_source_mesh.resource_path.get_file(),
				terrain_data.resource_path.get_file(),
				report["covered"],
				report["corners"],
				report["voided"],
				report["cells"],
				report["triangles"],
				report["skipped_triangles"]
			]
		)
	)
	_save_terrain_data()
	rebuild_terrain_visuals(true)


## Write terrain_data back to its own file, and prove it landed by reading it back.
##
## THE BAKE USED TO ONLY MUTATE MEMORY. `bake_source_mesh` writes the resource in place, and a
## `.tres` bound as an ExtResource is a separate file that saving the SCENE does not save — so
## a bake looked perfect in the viewport, was gone on the next load, and left the map drawing
## one surface while playing the heights of another. That is §Regenerating data's failure with
## the arrows reversed, and "the terrain_data seems out of sync with terrain_source_mesh" is
## exactly what it looks like from the outside.
##
## The reload check is the point: saving and looking saved are different, and only reading the
## file back distinguishes them.
func _save_terrain_data() -> void:
	var path: String = terrain_data.resource_path
	if path.is_empty():
		push_warning(
			(
				"Map.bake_terrain_from_mesh: terrain_data has no file of its own, so the "
				+ "bake lives only in memory and will be lost on reload. Save it somewhere first."
			)
		)
		return
	var err: int = ResourceSaver.save(terrain_data, path)
	if err != OK:
		push_warning("Map.bake_terrain_from_mesh: could not save %s (%d)" % [path, err])
		return
	var reloaded: Resource = ResourceLoader.load(
		path, "TerrainData", ResourceLoader.CACHE_MODE_IGNORE
	)
	var residual: float = -1.0
	if reloaded is TerrainData:
		var disk: PackedFloat32Array = (reloaded as TerrainData).heights
		residual = 0.0 if disk.size() == terrain_data.heights.size() else INF
		for i: int in mini(disk.size(), terrain_data.heights.size()):
			residual = maxf(residual, absf(disk[i] - terrain_data.heights[i]))
	print("Map: wrote %s   reload residual %.9f   <- must be 0" % [path.get_file(), residual])


## A TerrainData for `terrain_source_mesh`, saved beside it and sized to its footprint.
##
## play_size is DERIVED from the mesh extent rather than left at its default, because the two
## have to agree: the corner grid is a pure function of play_size, and a grid that does not
## span the mesh rasterizes part of it into nothing. A square mesh of N cells across needs
## play_size (N-1)/2 per axis — see TerrainData.derive_dimensions.
func _terrain_data_for_source_mesh() -> TerrainData:
	var source: String = terrain_source_mesh.resource_path
	if source.is_empty():
		push_warning(
			(
				"Map.bake_terrain_from_mesh: no terrain_data, and terrain_source_mesh is "
				+ "embedded in the scene so there is nowhere obvious to put one. Save the surface "
				+ "mesh to a file first."
			)
		)
		return null
	var extent: Vector3 = (
		terrain_source_mesh.get_aabb().size * terrain_source_mesh_transform.basis.get_scale()
	)
	var cells: int = maxi(int(round(maxf(extent.x, extent.z))), 2)
	var data := TerrainData.new()
	data.play_size = Vector2i(maxi((cells - 1) / 2, 1), maxi((cells - 1) / 2, 1))
	var path: String = source.get_basename() + "_terrain.tres"
	var err: int = ResourceSaver.save(data, path)
	if err != OK:
		push_warning("Map.bake_terrain_from_mesh: could not create %s (%d)" % [path, err])
		return null
	print(
		(
			"Map: created %s (play_size %s) for %s"
			% [path.get_file(), data.play_size, source.get_file()]
		)
	)
	return ResourceLoader.load(path, "TerrainData") as TerrainData


## How far `terrain_data.heights` has drifted from what `terrain_source_mesh` would bake.
## 0.0 means the two agree; -1.0 means there is nothing to compare.
##
## THE TWO CAN DISAGREE SILENTLY, and when they do every tool lies. The viewport draws the
## MESH, while the water tool, placement, pathing and the terrain grid all read `heights`. On
## 2026-09-11 the bake said 0.70-0.85 across a patch the mesh drew flat at 1.00, so the Water
## brush happily flooded basins into ground that is solid on screen — three ponds were authored
## into rock and drew nothing at runtime.
##
## A full re-bake into a scratch resource, so it is an editor-time check and not a per-frame one.
func source_mesh_bake_residual() -> float:
	if terrain_data == null or terrain_source_mesh == null:
		return -1.0
	var scratch := TerrainData.new()
	scratch.play_size = terrain_data.play_size
	scratch.bake_source_mesh(terrain_source_mesh, terrain_source_mesh_transform)
	if scratch.heights.size() != terrain_data.heights.size():
		return INF
	var residual: float = 0.0
	for i: int in scratch.heights.size():
		residual = maxf(residual, absf(scratch.heights[i] - terrain_data.heights[i]))
	return residual


## Inspector trigger: (re)build the visual terrain mesh from the current map fields.
## Creates a HeightmapMeshGenerator under the terrain body if one doesn't exist, then
## syncs its shape to height_map and rebuilds the ArrayMesh — so a fresh map gets a
## generated mesh, and a mesh that drifted from the heightmap is brought back in sync.
@export var generate_visual_mesh: bool:
	set(v):
		_fire_trigger(v, _regenerate_visual_mesh)

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
	set(v):
		_fire_trigger(v, _run_mirror)


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
		mirror_secondary_axis != MirrorAxis.NONE and mirror_secondary_axis != mirror_primary_axis
	)
	_mirror_map(primary_horizontal, flip_secondary)


## How far, in grid cells, `shift_map` moves the whole terrain (+x = east, +y = south).
@export var shift_offset: Vector2i = Vector2i.ZERO

## What happens at the edges when the map is shifted: CLIP drops what falls off and
## default-fills the strip exposed behind it, WRAP re-inserts it on the opposite edge,
## EXTEND_EDGE continues the boundary row/column outward. See TerrainData.EdgePolicy.
@export var shift_edge_policy: TerrainData.EdgePolicy = TerrainData.EdgePolicy.CLIP

## Inspector trigger (toggling either way runs the op, like mirror_map). Shifts the whole
## terrain — heights AND tile types — by shift_offset, then re-seats every entity on the new
## surface and DELETES the ones the new ground can't support (see
## reconcile_entities_with_terrain).
##
## The recipe this exists for: to downsize a map around terrain sculpted somewhere other
## than the top-left, shift that content towards the origin FIRST, then shrink the grid by
## lowering terrain_data.play_size — whose refit preserves the top-left corner and discards
## the rest.
##
## Like mirror_map, this is NOT undoable: it is a deliberate whole-map operation, and Map has
## no editor undo history of its own. The terrain brush's REGION paste is the undoable path.
@export var shift_map: bool:
	set(v):
		_fire_trigger(v, _run_shift)


## Resolve the shift exports and run the op. Zero offset is a no-op.
func _run_shift() -> void:
	if not Engine.is_editor_hint():
		push_warning("Map.shift_map is an editor-only authoring tool; ignoring at runtime")
		return
	if terrain_data == null:
		push_warning("Map.shift_map: no terrain_data assigned")
		return
	if shift_offset == Vector2i.ZERO:
		push_warning("Map.shift_map: shift_offset is zero — nothing to shift")
		return
	var shifted: Dictionary = terrain_data.shift_all(
		shift_offset, TerrainData.LAYER_ALL, shift_edge_policy
	)
	var culled: Array[Dictionary] = apply_terrain_region_paste(
		shifted["heights"], shifted["tile_types"]
	)
	# No undo history here (see shift_map), so the orphaned nodes are ours to release.
	for record: Dictionary in culled:
		var node: Node = record.get("node") as Node
		if is_instance_valid(node):
			node.free()


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
	sync_source_mesh_heights()
	_rebuild_visual_mesh()
	_reseat_entities_on_terrain()


## Editor helper: full refresh after an external terrain_data edit (terrain brush stroke
## end, undo/redo). When the heights layer changed, updates the live height_map in place +
## collider, and re-seats editor-placed entities on the new surface; always rebuilds the mesh.
func rebuild_terrain_visuals(a_heights_changed: bool) -> void:
	if terrain_data == null:
		return
	if a_heights_changed and height_map != null:
		height_map.map_data = terrain_data.heights
		if _terrain_collision_shape != null:
			_terrain_collision_shape.shape = height_map
	if a_heights_changed:
		# Heights and the surface mesh are the same surface twice, so a height COMMIT has to
		# write BOTH. Every height-changing path lands here — stroke end, region paste, undo,
		# mirror, shift — which is why the sync and the save live here rather than in each.
		sync_source_mesh_heights()
		persist_terrain_artifacts()
	_rebuild_visual_mesh()
	if a_heights_changed:
		_reseat_entities_on_terrain()
		# A body of water is a level over a surface that just moved, so its basin is now wrong.
		# Re-flooding here rather than leaving it to the next load is what makes sculpting a pond
		# bank a live operation: the water follows the ground under the brush.
		for body: WaterBody in water_bodies:
			if is_instance_valid(body):
				body.rebuild()


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
func set_terrain_heights(a_new_heights: PackedFloat32Array) -> void:
	if terrain_data == null:
		return
	terrain_data.heights = a_new_heights
	sync_source_mesh_heights()
	rebuild_terrain_visuals(true)


## Write terrain_source_mesh back to its own file after a height commit.
##
## THIS IS THE HALF THAT WAS MISSING, and it cost a map. `sync_source_mesh_heights` mutates the
## mesh IN MEMORY, and a mesh bound as an ExtResource is a file of its own that saving the
## SCENE does not save. So every sculpted basin survived the session and vanished on reload:
## `terrain_data` kept it, the mesh did not, and from then on everything that READS heights
## (units, water, placement, the navmesh) was right while everything you SEE was stale. It is
## §Regenerating data's failure in its purest form — one surface, two artifacts, one of them
## never written.
##
## Only on a COMMIT — stroke end, paste, undo — never on the per-step live preview
## (apply_terrain_heights_live), because this writes the whole mesh.
##
## BOTH artifacts, in one call, because the whole failure mode is writing one and not the
## other. An EMBEDDED resource needs nothing: it is part of the scene and saved with it.
##
## `OS.has_feature("editor")` rather than `Engine.is_editor_hint()`: the condition that matters
## is "may this process write into the project", which is true for the editor AND for the
## headless tool runs that exercise this path, and false for an exported game.
func persist_terrain_artifacts() -> void:
	if not OS.has_feature("editor"):
		return
	_save_resource(terrain_data, "terrain_data")
	if terrain_source_mesh is ArrayMesh:
		_save_resource(terrain_source_mesh, "terrain_source_mesh")


## Save one resource back over its own file. A resource with no path is embedded in the scene
## and is saved with it, so it is skipped rather than treated as an error.
func _save_resource(a_resource: Resource, a_label: String) -> void:
	if a_resource == null or a_resource.resource_path.is_empty():
		return
	var err: int = ResourceSaver.save(a_resource, a_resource.resource_path)
	if err != OK:
		push_warning("Map: could not save %s to %s (%d)" % [a_label, a_resource.resource_path, err])


## Push terrain_data.heights into a BRUSHABLE terrain_source_mesh as vertex Y, and redraw it.
##
## Called from both height write paths — set_terrain_heights (stroke end / undo) and
## apply_terrain_heights_live (every cell during a drag) — so the drawn surface and the
## gameplay field cannot drift apart, and a stroke is visible while you make it.
##
## A mesh that is NOT a grid of this size (an imported sculpt) is left alone: it is still drawn
## and still baked, it just isn't something a brush stroke can meaningfully edit. See
## TerrainMeshGrid.
func sync_source_mesh_heights() -> void:
	if terrain_data == null or not (terrain_source_mesh is ArrayMesh):
		return
	var dims: Vector2i = terrain_data.dimensions
	if not TerrainMeshGrid.is_grid_mesh(terrain_source_mesh, dims):
		return
	TerrainMeshGrid.write_heights(terrain_source_mesh, dims, terrain_data.heights)
	if terrain_body == null:
		return
	var surface := terrain_body.get_node_or_null("TerrainSurface") as TerrainSurface
	if surface != null:
		surface.refresh()


func set_terrain_tile_types(a_new_types: PackedByteArray) -> void:
	if terrain_data == null:
		return
	terrain_data.tile_types = a_new_types
	rebuild_terrain_visuals(false)


# ---------------------------------------------------------------------------
# Region paste / shift + entity reconciliation (editor-only authoring)
# ---------------------------------------------------------------------------


## Commit both terrain layers at once and reconcile the entities standing on them.
##
## One method rather than set_terrain_heights + set_terrain_tile_types because a region
## paste touches BOTH layers in a single user-visible action, and those two each rebuild
## the mesh and collider — calling them in sequence would do that work twice.
##
## Returns one cull record per entity the new terrain could not support (see
## reconcile_entities_with_terrain). The removed nodes are ORPHANED, not freed, and stay
## alive only as long as something holds the returned records — the terrain brush hands
## them to EditorUndoRedoManager.add_undo_reference so an undo can put them back, while
## the inspector-driven shift (which follows mirror_map's non-undoable precedent) frees them.
##
## `region_cells` is an optional Set (Vector2i -> true) limiting which entities are TESTED;
## empty means test everything. Re-seating always happens map-wide regardless — it is
## idempotent for an entity already sitting at its terrain height.
func apply_terrain_region_paste(
	a_new_heights: PackedFloat32Array, a_new_types: PackedByteArray, a_region_cells: Dictionary = {}
) -> Array[Dictionary]:
	if terrain_data == null:
		return []
	terrain_data.heights = a_new_heights
	terrain_data.tile_types = a_new_types
	# Re-derives height_map + collider, rebuilds the mesh, and re-seats every entity on the
	# new surface — which is the whole "entities follow the new height" half of this feature.
	rebuild_terrain_visuals(true)
	return reconcile_entities_with_terrain(a_region_cells)


## Undo counterpart to apply_terrain_region_paste: put the culled entities back, restore the
## previous layers, and refresh.
##
## Order is load-bearing — the nodes are re-added BEFORE the rebuild, so the re-seat inside
## rebuild_terrain_visuals lands them on the restored surface rather than leaving them at
## the height the paste had moved them to.
## `culled` is deliberately an untyped Array: it comes back through EditorUndoRedoManager,
## which stores call arguments as plain Variants, and a typed Array[Dictionary] parameter
## would reject the untyped array it hands back.
func revert_terrain_region_paste(
	a_old_heights: PackedFloat32Array, a_old_types: PackedByteArray, a_culled: Array
) -> void:
	if terrain_data == null:
		return
	for record: Dictionary in a_culled:
		var node: Node = record.get("node") as Node
		var parent: Node = record.get("parent") as Node
		if not is_instance_valid(node) or not is_instance_valid(parent):
			continue
		if node.get_parent() != null:
			continue  # already back in the tree (a double undo, or someone else restored it)
		parent.add_child(node)
		# Restore tree ORDER, not just membership: add_child appends, so without this an undo
		# would quietly reshuffle the scene dock every time.
		parent.move_child(
			node,
			mini(record.get("index", parent.get_child_count() - 1), parent.get_child_count() - 1)
		)
		# A node with a null owner is not saved with the scene — losing this would make the
		# entity reappear now and vanish again on the next save.
		var restored_owner: Node = record.get("owner") as Node
		if is_instance_valid(restored_owner):
			node.owner = restored_owner
	terrain_data.heights = a_old_heights
	terrain_data.tile_types = a_old_types
	rebuild_terrain_visuals(true)


## Remove every scene entity the CURRENT terrain can no longer hold up, returning a cull
## record ({node, parent, index, owner}) for each so the caller can undo or free it.
##
## Deliberately does not consult cell_grid / terrain_grid / structure_cell_map: Map._ready
## returns early in the editor, so none of them exist while authoring. Support is derived
## from terrain_data instead (TerrainData.cell_supports_entity), and footprints are computed
## here rather than via footprint_cells — that helper filters through
## grid_coordinates_in_bounds, which reads the empty editor-time cell_grid and would return
## no cells at all.
func reconcile_entities_with_terrain(a_region_cells: Dictionary = {}) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if terrain_data == null or height_map == null:
		return records
	var root: Node = get_tree().edited_scene_root if get_tree() != null else null
	if root == null:
		return records

	# Pass 1: decide who the terrain can't hold. Start points are never culled — they are
	# skirmish slot markers (Skirmish.START_POINT_GROUP), not entities, and deleting one
	# silently changes how many players the map supports.
	var doomed: Dictionary = {}  # Node -> true
	for node: Node3D in _collect_game_entities(root):
		var cells: Array[Vector2i] = entity_terrain_cells(node)
		if cells.is_empty() or not _cells_intersect_region(cells, a_region_cells):
			continue
		if _terrain_supports_entity(node, cells):
			continue
		if node.is_in_group("start_position"):
			push_warning(
				"Map: start point '%s' now stands on unsupported terrain — move it." % node.name
			)
			continue
		doomed[node] = true

	# Pass 2: cascade. A Extractor with no ExtractionSite is not merely orphaned — Map.add_structure
	# push_errors and bails on it, so leaving one behind trades a visible change for a
	# scene that fails at load.
	for node: Node3D in _collect_game_entities(root):
		var node_extractor: Extractor = Extractor.of(node)
		if node_extractor != null and not doomed.has(node):
			var dep: Entity = node_extractor.extraction_site
			if dep != null and doomed.has(dep):
				doomed[node] = true

	for node: Node in doomed:
		var parent: Node = node.get_parent()
		if parent == null:
			continue
		(
			records
			. append(
				{
					"node": node,
					"parent": parent,
					"index": node.get_index(),
					"owner": node.owner,
				}
			)
		)
		parent.remove_child(node)

	if not records.is_empty():
		push_warning(
			(
				"Map: terrain edit removed %d entities that the new ground can't support: %s"
				% [records.size(), _record_names(records)]
			)
		)
	return records


## The grid cells an entity stands on: a structure's whole footprint, or the single cell
## under anything else. Bounds are NOT filtered here — an out-of-bounds cell is a genuine
## "unsupported" answer, and filtering it away would silently make a structure hanging off
## the map edge look fine.
func entity_terrain_cells(a_node: Node3D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not is_instance_valid(a_node) or height_map == null:
		return cells
	var xz := Vector2(a_node.global_position.x, a_node.global_position.z)
	var structure := a_node.get_node_or_null("Structure") as Structure
	if structure == null:
		cells.append(world_to_grid(xz))
		return cells
	var dims: Vector2i = structure.footprint_dimensions()
	var origin := footprint_origin(xz, dims)
	for w: int in range(dims.x):
		for l: int in range(dims.y):
			cells.append(Vector2i(origin.x + w, origin.y + l))
	return cells


## Whether the current terrain holds `node` up across all of `cells`. Structures additionally
## require perfectly level ground — unless they opt out via Structure.allow_uneven, the same
## flag Structure.valid_placement honours, so the cull can't delete a building the game would
## happily have let the player place.
func _terrain_supports_entity(a_node: Node3D, a_cells: Array[Vector2i]) -> bool:
	var structure := a_node.get_node_or_null("Structure") as Structure
	var requires_flat: bool = structure != null and not structure.allow_uneven
	for cell: Vector2i in a_cells:
		if not terrain_data.cell_supports_entity(cell):
			return false
		if requires_flat and not terrain_data.cell_is_flat(cell):
			return false
	return true


## Whether any of `cells` is in the edited region. An empty region means "test everything"
## (a whole-map shift), so it always matches.
func _cells_intersect_region(a_cells: Array[Vector2i], a_region_cells: Dictionary) -> bool:
	if a_region_cells.is_empty():
		return true
	for cell: Vector2i in a_cells:
		if a_region_cells.has(cell):
			return true
	return false


func _record_names(a_records: Array[Dictionary]) -> String:
	var names: PackedStringArray = PackedStringArray()
	for record: Dictionary in a_records:
		var node: Node = record.get("node") as Node
		if is_instance_valid(node):
			names.append(String(node.name))
	return ", ".join(names)


## Rebuild the working height_map from terrain_data (heights layer) and refresh the
## editor visuals. Called from _ready and the terrain_data setter. Setting height_map
## routes through its setter, which rebuilds the mesh when the node is already ready in
## the editor; we rebuild explicitly here to cover the _ready path too.
func _sync_from_terrain_data() -> void:
	if terrain_data == null:
		return
	# Update the existing shape IN PLACE when it still has the right extent, and only build a
	# fresh one when the grid actually resized. Replacing the resource frees the old one — which
	# the EditorInspector may still be displaying, since height_map is shown (read-only) whenever
	# terrain_data drives the terrain. That free is half of the editor crash this path caused;
	# deferring the signal is the other half. A bake never changes dimensions, so the common case
	# now frees nothing at all.
	var dims: Vector2i = terrain_data.dimensions
	if (
		height_map != null
		and height_map.map_width == dims.x
		and height_map.map_depth == dims.y
		and terrain_data.heights.size() == dims.x * dims.y
	):
		height_map.map_data = terrain_data.heights
	else:
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
	# Deferred (see the connect call), so a burst of emissions — the inspector rewriting several
	# fields, a bake touching heights and tile_types — arrives as several queued calls for the
	# same work. Collapse them, and never re-enter while a sync is already running: _sync
	# reassigns height_map, whose own setter can emit again.
	if _terrain_sync_running:
		return
	_terrain_sync_running = true
	_sync_from_terrain_data()
	_reseat_entities_on_terrain()
	_terrain_sync_running = false


## Guards _on_terrain_data_changed against re-entering itself. See there.
var _terrain_sync_running: bool = false


## Rebuild whichever node draws this map's terrain.
##
## POLYMORPHIC over the two renderers, the same way terrain_material() is, because every
## caller — the brush after a stroke, the generate_visual_mesh button — means "show me the
## current data" and must not care which one is present.
##
## It used to handle HeightmapMeshGenerator ONLY and return silently otherwise, so on a
## surface-mesh map nothing here ever ran: the cell layers the terrain shader samples (tile
## type, the steep flag) were never re-pushed, and a brush stroke or a fresh bake did not show.
func _rebuild_visual_mesh() -> void:
	if terrain_body == null:
		return
	var surface: TerrainSurface = _terrain_surface()
	if surface != null:
		surface.refresh()
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
	# The two terrain renderers must never coexist, and this button is how they came to.
	# A HeightmapMeshGenerator draws the quad-per-cell grid mesh; a TerrainSurface draws the
	# authored surface. Both render the same ground, so the grid one OCCLUDES the surface — and
	# worse, silently breaks fog: terrain_material() prefers TerrainSurface, so Fog pushes the
	# shroud into the material of the mesh that is now hidden behind an unfogged one. The
	# symptom is "fog of war stopped appearing on this map", with nothing obviously wrong.
	# On a surface-mesh map this means "redraw the authored surface from the current data",
	# which is what _rebuild_visual_mesh now does. It must NOT add a HeightmapMeshGenerator:
	# both renderers draw the same ground, so the grid one occludes the surface and silently
	# breaks fog — terrain_material() prefers TerrainSurface, so the shroud would be pushed
	# into the material of the mesh that is now hidden behind an unfogged one.
	if _terrain_surface() != null:
		_rebuild_visual_mesh()
		print(
			(
				"Map: refreshed the TerrainSurface from %s"
				% [
					(
						terrain_source_mesh.resource_path.get_file()
						if terrain_source_mesh != null
						else "(no terrain_source_mesh)"
					)
				]
			)
		)
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
	# Defensive: never create one alongside a TerrainSurface. See _regenerate_visual_mesh.
	if _terrain_surface() != null:
		return null

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
func _mirror_map(a_primary_horizontal: bool, a_flip_secondary: bool) -> void:
	if not Engine.is_editor_hint():
		push_warning("Map.mirror_map is an editor-only authoring tool; ignoring at runtime")
		return
	if terrain_data == null:
		push_warning("Map.mirror_map: no terrain_data assigned")
		return
	_mirror_heights(a_primary_horizontal, a_flip_secondary)
	_mirror_tile_types(a_primary_horizontal, a_flip_secondary)
	_mirror_entities(a_primary_horizontal, a_flip_secondary)


## Copy the reference half's heightmap corners onto the opposite half so the two
## halves have identical terrain. Left (min-x) is the reference for a horizontal
## primary; bottom (max-z) for a vertical one. When `flip_secondary`, the source
## corner is additionally reflected across the other axis (point reflection). The
## centre column/row (odd sizes) is the axis and is left as-is.
func _mirror_heights(a_primary_horizontal: bool, a_flip_secondary: bool) -> void:
	var w := terrain_data.map_width()
	var d := terrain_data.map_depth()
	var data := terrain_data.heights  # a copy; mutate then assign back
	if a_primary_horizontal:
		for z in range(d):
			for x in range(w):
				var mx := w - 1 - x
				if x > mx:  # right (opposite) corner ← reference corner
					# Source is the mirror in X, plus the mirror in Z when flipping.
					var src_z := (d - 1 - z) if a_flip_secondary else z
					data[z * w + x] = data[src_z * w + mx]
	else:
		for z in range(d):
			var mz := d - 1 - z
			if z < mz:  # top (opposite) row ← reference row
				for x in range(w):
					# Source is the mirror in Z, plus the mirror in X when flipping.
					var src_x := (w - 1 - x) if a_flip_secondary else x
					data[z * w + x] = data[mz * w + src_x]
	terrain_data.heights = data
	_sync_from_terrain_data()  # re-derive height_map + collider, rebuild mesh


## Mirror the per-cell tile types to match the terrain, so the copied half reflects the
## reference half. Same reflect rule as _mirror_heights, on the cell grid (one smaller
## than the corner grid on each axis). No-op when tile_types is empty (all-Open).
func _mirror_tile_types(a_primary_horizontal: bool, a_flip_secondary: bool) -> void:
	if terrain_data.tile_types.is_empty():
		return
	var gw := terrain_data.grid_width()  # navigable cell columns
	var gd := terrain_data.grid_depth()  # navigable cell rows
	var t := terrain_data.tile_types  # a copy; mutate then assign back
	if a_primary_horizontal:
		for z in range(gd):
			for x in range(gw):
				var mx := gw - 1 - x
				if x > mx:  # right (opposite) cell ← reference cell
					var src_z := (gd - 1 - z) if a_flip_secondary else z
					t[z * gw + x] = t[src_z * gw + mx]
	else:
		for z in range(gd):
			var mz := gd - 1 - z
			if z < mz:  # top (opposite) row ← reference row
				for x in range(gw):
					var src_x := (gw - 1 - x) if a_flip_secondary else x
					t[z * gw + x] = t[mz * gw + src_x]
	terrain_data.tile_types = t
	_rebuild_visual_mesh()


## Erase every game entity on the opposite half, then duplicate every game entity
## on the reference half and reflect it across the centre. Extractor→ExtractionSite links are
## repointed to the duplicated sites so mirrored extractors bind correctly.
func _mirror_entities(a_primary_horizontal: bool, a_flip_secondary: bool) -> void:
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return
	var center := global_transform.origin
	# The reference half is decided by the PRIMARY axis only; the secondary axis
	# just adds an extra reflection to where each copy lands.
	var axis_val: float = center.x if a_primary_horizontal else center.z

	# Classify each entity as reference / opposite / on-axis by its position along
	# the primary axis. Reference = left (min-x) for horizontal, bottom (max-z) for
	# vertical. Free opposite-side entities now; keep reference ones for copying.
	var reference: Array[Node3D] = []
	for node: Node3D in _collect_game_entities(root):
		var coord: float = (
			node.global_position.x if a_primary_horizontal else node.global_position.z
		)
		var delta: float = coord - axis_val
		if a_primary_horizontal:
			# left is reference, so reference sits at negative delta
			delta = -delta
		if delta > _MIRROR_AXIS_EPS:
			reference.append(node)  # reference half — copy across
		elif delta < -_MIRROR_AXIS_EPS:
			node.free()  # opposite half — erase
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
		var reflect_x: bool = a_primary_horizontal or a_flip_secondary
		var reflect_z: bool = not a_primary_horizontal or a_flip_secondary
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
	# duplicated Extractor still references the ORIGINAL site, so repoint it at that
	# site's duplicate (and sit it on top) when the site was mirrored too.
	for node: Node3D in reference:
		var orig_extractor: Extractor = Extractor.of(node)
		if orig_extractor != null:
			var dup_piece := orig_to_dup[node] as Node3D
			var orig_site: Entity = orig_extractor.extraction_site
			if orig_site != null and orig_to_dup.has(orig_site):
				var dup_site := orig_to_dup[orig_site] as Entity
				Extractor.of(dup_piece).extraction_site = dup_site
				dup_piece.global_position = dup_site.global_position


## Swap a mirrored entity's owner between commander 1 and 2 so the copied half
## belongs to the opposing player. Neutral (0) and any other id are untouched.
## No-op for non-Entity nodes (e.g. start-point markers have no commander).
func _flip_commander_id(a_node: Node3D) -> void:
	if a_node is Entity:
		var entity := a_node as Entity
		if entity.default_commander_id == 1:
			entity.default_commander_id = 2
		elif entity.default_commander_id == 2:
			entity.default_commander_id = 1


## Node3D game entities authored under `root` that the mirror should act on:
## anything in the "piece", "fixture" or "start_position" groups (extraction sites,
## extractors, shelters, buildings, start markers, …). Excludes the Map's own subtree
## (terrain, nav, height pins) and de-duplicates across groups.
func _collect_game_entities(a_root: Node) -> Array[Node3D]:
	var seen: Dictionary = {}
	var result: Array[Node3D] = []
	for group: String in ["piece", "fixture", "start_position"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if (
				node is Node3D
				and not seen.has(node)
				and a_root.is_ancestor_of(node)
				and node != self
				and not is_ancestor_of(node)
			):
				seen[node] = true
				result.append(node as Node3D)
	return result
