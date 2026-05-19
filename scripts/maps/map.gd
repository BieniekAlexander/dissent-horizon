class_name Map
extends Node3D


enum CollisionMask {
	UNITS = 1 << 0,
	TERRAIN = 1 << 4,
	SELECTION = 1 << 8
}

### SPACE THINGS

#### TERRAIN
## CollisionShape3D whose .shape is the HeightMapShape3D that defines the
## terrain surface.  Set in the scene inspector.
@onready var terrain_collision: CollisionShape3D = $NavigationRegion/Body/Shape

## StaticBody3D that owns terrain_collision.  Its global_transform is used by
## TerrainGrid/NavManager to convert grid positions to world space.
@onready var terrain_body: StaticBody3D = $NavigationRegion/Body


@onready var nav_region: NavigationRegion3D = $NavigationRegion

## World-space side length of one terrain cell
@onready var cell_size: float = terrain_body.scale.x

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
	var hs: HeightMapShape3D = terrain_grid.height_shape()
	var tb   := terrain_grid.terrain_body
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
	return tb.global_transform * local_pos

## Convert a world XZ position to the nearest grid cell indices.
## This is the exact inverse of grid_to_world: it undoes the terrain_body
## transform and the (map_width-1)/2 centering that grid_to_world applies.
func world_to_grid(world_xz: Vector2) -> Vector2i:
	var hs: HeightMapShape3D = terrain_grid.height_shape()
	var hw := (hs.map_width  - 1) * 0.5
	var hd := (hs.map_depth  - 1) * 0.5
	var local := terrain_body.global_transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
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
	a_entity.initialize(self, a_commander)

	if a_entity is Commandable and a_entity.is_in_group("structure"):
		add_structure(a_entity, a_location, 0, false)
	else:
		a_entity.global_position = VU.fromXZ(
			SU.get_nonoverlapping_points(
				self,
				a_location,
				a_entity.collision_radius,
				get_world_3d(),
				CollisionMask.UNITS,
				1,
				5.
			)[0]
		) + .5 * Vector3.UP


func add_structure(a_structure: Commandable, grid_location: Vector2i, rotation: int, _rebake: bool = true) -> void:
	a_structure.global_position = grid_to_world(grid_location)

	var footprint: Array[Vector2i] = []
	for w in range(a_structure.width):
		for l in range(a_structure.length):
			var cell := Vector2i(grid_location.x + w, grid_location.y + l)
			cell_grid[cell.x][cell.y] = a_structure
			footprint.append(cell)

	structure_cell_map[a_structure] = footprint
	terrain_grid.place_building(footprint, a_structure)
	# TODO guarantee structure is centered on its cells
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
	assert(terrain_collision != null, "Map: terrain_collision export must be set in the scene")
	assert(terrain_body      != null, "Map: terrain_body export must be set in the scene")

	terrain_grid = TerrainGrid.new()
	terrain_grid.terrain_collision = terrain_collision
	terrain_grid.terrain_body      = terrain_body
	terrain_grid.cell_size         = cell_size
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
