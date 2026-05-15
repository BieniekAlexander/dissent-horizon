class_name NavManager
extends Node

## Owns and maintains the NavigationRegion3D for the map.
##
## Rather than baking from 3D geometry (which re-parses the whole scene), the
## mesh is constructed directly from HeightMapShape3D data.  One quad is emitted
## per passable cell, with shared vertices at cell corners so adjacent cells
## share geometry.
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
## Rebuilds are debounced via call_deferred so that a burst of cell changes
## (e.g. a multi-cell building placement) collapses into a single rebuild at
## the end of the same frame.

@export var navigation_region: NavigationRegion3D
@export var terrain_grid: TerrainGrid

var _rebuild_pending: bool = false


func _ready() -> void:
	assert(navigation_region != null, "NavManager: navigation_region export must be set")
	assert(terrain_grid      != null, "NavManager: terrain_grid export must be set")
	terrain_grid.cells_changed.connect(_on_cells_changed)
	# Defer so all _ready() calls finish before the first build.
	call_deferred("_rebuild_navmesh")


# --- Public API ------------------------------------------------------------

## Schedule a navmesh rebuild at the end of this frame.
## Multiple calls within one frame coalesce into a single rebuild.
func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild_navmesh")


# --- Internal --------------------------------------------------------------

func _on_cells_changed(_cells: Array) -> void:
	request_rebuild()


func _rebuild_navmesh() -> void:
	_rebuild_pending = false
	navigation_region.navigation_mesh = _build_mesh()


func _build_mesh() -> NavigationMesh:
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

	# Shared-vertex approach: corners are keyed by their (cx, cz) coordinate
	# so adjacent cells reuse the same vertex instead of duplicating it.
	var vertex_map: Dictionary = {}  # Vector2i -> int index in verts
	var verts := PackedVector3Array()

	for cell: Vector2i in terrain_grid.get_all_passable_cells():
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
				var cx := corner.x
				var cz := corner.y
				var local_pos := Vector3(
					cx - half_w,
					hs.map_data[cz * map_w + cx],
					cz - half_d
				)
				var world := tb.global_transform * local_pos
				verts.append(to_nav_local * world)
			indices.append(vertex_map[corner])

		nav_mesh.add_polygon(indices)

	nav_mesh.vertices = verts
	return nav_mesh
