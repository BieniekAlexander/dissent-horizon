@tool
class_name Map
extends Node3D


### SPACE THINGS

#### TERRAIN
## The heightmap resource that defines terrain extent and corner heights.
## This is the single source of truth for heightmap data; the StaticBody3D
## under NavigationRegion/Body may hold a reference to the same resource for
## physics collision but is no longer the authoritative data source.
@export var height_map: HeightMapShape3D

## StaticBody3D retained as a physics collider for future terrain raycasts.
## Its global_transform is still consumed by NavManager until that path is
## updated; Map coordinate functions now use Map's own global_transform instead.
@onready var terrain_body: StaticBody3D = $NavigationRegion/Body

@onready var nav_region: NavigationRegion3D = $NavigationRegion

## Editor-only container that holds one HeightPin child per heightmap corner.
## Resolved lazily so it works even when the node doesn't exist in the scene yet.
var _pin_container: Node3D

## World-space side length of one terrain cell.
## Encoded as Map's own scale (set to 2 in the scene) so that
## global_transform serves directly as the heightmap-to-world frame.
const CELL_SIZE: float = 2.0

#### GRID
var cell_grid: Array = []

# Populated by TerrainGrid/NavManager on _ready; used by Commandable.map_cells.
var structure_cell_map: Dictionary = {}  # Commandable -> Array[Vector2i]

var terrain_grid: TerrainGrid
var nav_manager: NavManager


# --- Coordinate helpers ----------------------------------------------------

## Convert a grid cell (integer indices) to the world XZ centre of that cell.
## Y is taken from the terrain surface at the cell centre corner; for flat
## maps with uniform height this is the actual surface Y.
func grid_to_world(cell: Vector2i) -> Vector3:
	var hs := height_map
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


# --- Map bounds ------------------------------------------------------------

## Returns [low: Vector2, high: Vector2] in grid-cell index space.
## Compatible with the legacy call shape used by fog.gd.
func get_min_max() -> Array:
	var bounds := terrain_grid.get_bounds()
	return [Vector2(bounds[0]), Vector2(bounds[1])]


# --- Entity placement ------------------------------------------------------

## Add a game [Entity] to the map, allowing the [Map] to govern it in the game world
func add_entity(a_entity: Entity, a_location: Vector2, a_commander: Commander) -> void:
	if a_entity is Commandable and a_entity.get_node_or_null("Obstruction") != null:
		a_entity.initialize(self, a_commander)
		add_structure(a_entity, a_location, 0, false)
	else:
		# Compute position BEFORE add_child (inside initialize) so the physics
		# server registers the entity at the correct world position from the start.
		# If initialize ran first, the entity would enter the broadphase at (0,0,0)
		# for the rest of that physics frame — close enough to the map centre that
		# nearby aggro/attack-range queries on existing units (turret, technician)
		# would incorrectly detect the freshly spawned enemies as in range.
		# Commander is a plain Node (not Node3D), so entity.position == world position.
		var radius: float = a_entity.bounding_radius(CollisionLayers.Layer.MOVEMENT_OBSTRUCTION)
		var placement_xz: Vector2
		if radius > 0.0:
			placement_xz = SU.get_nonoverlapping_points(
				self,
				a_location,
				radius,
				get_world_3d(),
				CollisionLayers.Layer.MOVEMENT_OBSTRUCTION,
				5.
			)[0]
		else:
			placement_xz = a_location
		a_entity.position = Vector3(
			placement_xz.x,
			terrain_height_at(placement_xz),
			placement_xz.y
		)
		a_entity.initialize(self, a_commander)


func add_structure(a_structure: Commandable, grid_location: Vector2i, rotation: int, _rebake: bool = true) -> void:
	# Footprint size comes from the Obstruction component so the cells we reserve
	# match exactly what Commandable.valid_placement validated.  Falls back to
	# 1×1 for structures without an Obstruction node (shouldn't happen in normal
	# play — add_entity guards on its presence, but add_structure can be called
	# directly e.g. from _auto_initialize).
	var obs := a_structure.get_node_or_null("Obstruction") as Obstruction
	var dims: Vector2i = obs.dimensions if obs != null else Vector2i.ONE
	var origin := grid_location - Vector2i((dims.x - 1) / 2, (dims.y - 1) / 2)
	var footprint: Array[Vector2i] = []
	var centroid := Vector3.ZERO
	for w in range(dims.x):
		for l in range(dims.y):
			var cell := Vector2i(origin.x + w, origin.y + l)
			if not grid_coordinates_in_bounds(cell):
				continue
			cell_grid[cell.x][cell.y] = a_structure
			footprint.append(cell)
			centroid += grid_to_world(cell)

	if not footprint.is_empty():
		centroid /= footprint.size()
	a_structure.global_position = centroid

	structure_cell_map[a_structure] = footprint
	terrain_grid.place_building(footprint, a_structure)
	a_structure.map = self


func remove_structure(a_structure: Commandable, _rebake: bool = true) -> void:
	var cells: Array = terrain_grid.get_building_cells(a_structure)
	for cell: Vector2i in cells:
		cell_grid[cell.x][cell.y] = null
	terrain_grid.remove_building(a_structure)
	structure_cell_map.erase(a_structure)



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
	get: return get_tree().get_nodes_in_group("commandable").filter(func(c: Commandable): return c.is_in_group("unit"))

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

	nav_manager = NavManager.new()
	nav_manager.navigation_region = nav_region
	nav_manager.terrain_grid      = terrain_grid
	add_child(nav_manager)
#endregion


# ---------------------------------------------------------------------------
# Heightmap editor (editor-only)
# ---------------------------------------------------------------------------

## Click to spawn one HeightPin per heightmap corner under HeightPins.
## Each pin's Y position directly equals the corresponding map_data value in
## the HeightMapShape3D's local space.  Moving a pin writes back to map_data
## and triggers a mesh rebuild via the sibling HeightmapMeshGenerator.
@export var generate_height_pins: bool:
	set(_v): _spawn_height_pins()

var _pin_updating: bool = false


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

	var gen := terrain_body.get_node_or_null("HeightmapMeshGenerator") as HeightmapMeshGenerator
	if gen != null:
		gen.build()
