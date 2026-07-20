@tool
class_name TerrainData
extends Resource

## The single authored/generated source of truth for a map's terrain, replacing the old
## split between Map.height_map (a HeightMapShape3D .tres) and Map.blocked_cells.
##
## Two parallel layers on the standard heightfield grids:
##   * `heights`     — per-CORNER, size dimensions.x * dimensions.y, index z*W + x.
##                     Same semantics as HeightMapShape3D.map_data (local-space Y).
##   * `tile_types`  — per-CELL, size (W-1) * (D-1), index z*(W-1) + x. Each byte indexes
##                     into `catalog.types`; the type governs passability (permanent) and,
##                     later, textures.
## Corners and cells sit on grids offset by half a cell — the usual heightfield layout.
##
## HeightMapShape3D is no longer authored directly; Map derives one from `heights`
## (to_height_shape) as a generated intermediate (picking collider + what TerrainGrid /
## NavManager / the mesh generator read), and derives TerrainGrid's blocked mask from
## `tile_types` via `blocked_mask`. See terrain-tile-types.md.

## Corner grid size (x = width W, y = depth D). Cells span (W-1) x (D-1). Editing this
## (e.g. in the inspector) RESIZES the layers to match — preserving the overlapping top-left
## region and default-filling any growth — and emits `changed` so the Map re-derives.
@export var dimensions: Vector2i = Vector2i(120, 120):
	set(value):
		var new_dims: Vector2i = Vector2i(maxi(value.x, 2), maxi(value.y, 2))
		if new_dims == dimensions:
			return
		var old_dims: Vector2i = dimensions
		# Treat this as a genuine in-editor RESIZE (remap the layers + emit `changed`) ONLY
		# when BOTH layers currently match the OLD dims — i.e. a fully-loaded, consistent
		# resource. During deserialization the layers are transiently empty/mismatched, so we
		# just record the new size and neither remap nor emit (emitting there would mark the
		# resource dirty and risk an editor re-save writing the transient state to disk).
		var old_cells: int = (old_dims.x - 1) * (old_dims.y - 1)
		var consistent: bool = heights.size() == old_dims.x * old_dims.y \
			and (tile_types.is_empty() or tile_types.size() == old_cells)
		dimensions = new_dims
		if consistent:
			_remap_layers(old_dims, new_dims)
			emit_changed()


## Resize `heights` (corner grid) and `tile_types` (cell grid) from `old_dims` to
## `new_dims`, preserving the overlapping top-left region and default-filling growth
## (height 0.0, tile type 0 = Open).
func _remap_layers(old_dims: Vector2i, new_dims: Vector2i) -> void:
	var new_heights := PackedFloat32Array()
	new_heights.resize(new_dims.x * new_dims.y)
	for z: int in mini(old_dims.y, new_dims.y):
		for x: int in mini(old_dims.x, new_dims.x):
			new_heights[z * new_dims.x + x] = heights[z * old_dims.x + x]
	heights = new_heights

	# Leave an empty (all-Open) tile_types empty — never materialize a zero-filled array,
	# and only remap when it genuinely matches the OLD cell grid, so a transient/mismatched
	# state can never overwrite real data with zeros.
	var ogw: int = old_dims.x - 1
	var ngw: int = new_dims.x - 1
	if tile_types.size() == ogw * (old_dims.y - 1):
		var new_types := PackedByteArray()
		new_types.resize(ngw * (new_dims.y - 1))
		for z: int in mini(old_dims.y - 1, new_dims.y - 1):
			for x: int in mini(ogw, ngw):
				new_types[z * ngw + x] = tile_types[z * ogw + x]
		tile_types = new_types

## Per-corner heights, size W*D, index z*W + x (local-space Y, = HeightMapShape3D.map_data).
@export var heights: PackedFloat32Array = PackedFloat32Array()

## Per-cell type indices, size (W-1)*(D-1), index z*(W-1) + x. Empty = all Open.
@export var tile_types: PackedByteArray = PackedByteArray()

## The shared palette these indices refer to.
@export var catalog: TerrainTileCatalog

## Screen-aligned play bounds (see StaggeredGrid). When enabled, cells OUTSIDE the screen-
## aligned rectangle are out-of-play: omitted from the visual mesh (holes) and marked
## impassable — so the four (x,z) grid corners that fall outside a square-bounded playspace
## are chopped automatically instead of by hand. Disabled = the whole grid is in play.
@export var play_bounds_enabled: bool = false:
	set(value):
		if value == play_bounds_enabled:
			return
		play_bounds_enabled = value
		emit_changed()

## The play rectangle's on-screen size, in DIAMONDS. play_size.x is the extent along s = x+z,
## play_size.y along t = x-z. At the default camera (RTSCamera3D at +X+Z looking at origin)
## screen-right is v = x-z and screen-up is -(x+z), so on screen play_size.y is the WIDTH and
## play_size.x is the HEIGHT. Centred on the grid; rotates with the camera. A zero component
## means "auto" for that axis: the largest that fits the (x,z) grid. Only used when
## play_bounds_enabled. Rectangular is fine — the two axes are independent.
@export var play_size: Vector2i = Vector2i.ZERO:
	set(value):
		play_size = Vector2i(maxi(value.x, 0), maxi(value.y, 0))
		if play_bounds_enabled:
			emit_changed()


#region Dimensions
func map_width() -> int:  return dimensions.x
func map_depth() -> int:  return dimensions.y
func grid_width() -> int: return dimensions.x - 1
func grid_depth() -> int: return dimensions.y - 1
#endregion


#region Accessors
## The tile-type index of cell (x, z); DEFAULT (Open) when tile_types is empty or the
## cell is out of range.
func tile_at(cell: Vector2i) -> int:
	if tile_types.is_empty():
		return TerrainTileCatalog.DEFAULT_INDEX
	var idx: int = cell.y * grid_width() + cell.x
	if idx < 0 or idx >= tile_types.size():
		return TerrainTileCatalog.DEFAULT_INDEX
	return tile_types[idx]


## Whether cell (x, z)'s TYPE is passable (ignores steepness/buildings — those are
## TerrainGrid's concern). Open when there's no catalog.
func is_cell_type_passable(cell: Vector2i) -> bool:
	return catalog == null or catalog.passable(tile_at(cell))


## Whether cell (x, z) contributes surface geometry to the visual terrain mesh (see
## TileType.renders_surface). Rendered when there's no catalog. Distinct from passability:
## a water/forest cell is impassable yet still rendered; a cliff/no-go cell is a hole.
func cell_renders_surface(cell: Vector2i) -> bool:
	return catalog == null or catalog.renders_surface(tile_at(cell))


## The flat albedo the baseline terrain shader shows for cell (x, z)'s type. Default
## open-ground colour when there's no catalog.
func cell_map_color(cell: Vector2i) -> Color:
	return catalog.map_color(tile_at(cell)) if catalog != null else TileType.DEFAULT_MAP_COLOR


## Whether cell (x, z) is inside the screen-aligned play area (see StaggeredGrid). Always
## true when play_bounds_enabled is false, so callers can consult it unconditionally.
func is_cell_in_play(cell: Vector2i) -> bool:
	if not play_bounds_enabled:
		return true
	return StaggeredGrid.screen_rect_contains(cell, _play_center_st(), _play_half())


## Centre of the play rectangle in screen (s = x+z, t = x-z) space — the grid's middle cell.
func _play_center_st() -> Vector2:
	var cx: float = (grid_width() - 1) * 0.5
	var cz: float = (grid_depth() - 1) * 0.5
	return Vector2(cx + cz, cx - cz)


## Play-rectangle half-extents in (s, t) space, derived from play_size. One diamond spans 2
## units of s (or t), so N diamonds across → a half-extent of N. A zero play_size component
## falls back to the largest half-extent that fits the grid (its inscribed diamond).
func _play_half() -> Vector2:
	var auto_r: float = minf(grid_width() - 1, grid_depth() - 1) * 0.5
	var hs: float = float(play_size.x) if play_size.x > 0 else auto_r
	var ht: float = float(play_size.y) if play_size.y > 0 else auto_r
	return Vector2(hs, ht)


## Screen-aligned play half-extents (along s = x+z and t = x-z), in (s, t) cell-diagonal
## units, or Vector2.ZERO when play bounds are disabled. For UI that frames the play area
## (e.g. the minimap): one diamond spans 2 units, and the play rectangle is centred on the grid.
func play_half_extents() -> Vector2:
	return _play_half() if play_bounds_enabled else Vector2.ZERO


## The four corners of the screen-aligned play rectangle as continuous (x, z) cell-space
## points — the tips of the play diamond, in winding order. Empty when play bounds are
## disabled. For editor overlays that want to outline the play area.
func play_bounds_grid_corners() -> PackedVector2Array:
	if not play_bounds_enabled:
		return PackedVector2Array()
	var c: Vector2 = _play_center_st()
	var h: Vector2 = _play_half()
	var corners := PackedVector2Array()
	for st: Vector2 in [
		Vector2(c.x - h.x, c.y - h.y), Vector2(c.x + h.x, c.y - h.y),
		Vector2(c.x + h.x, c.y + h.y), Vector2(c.x - h.x, c.y + h.y),
	]:
		# (s, t) -> continuous (x, z): x = (s + t) / 2, z = (s - t) / 2.
		corners.append(Vector2((st.x + st.y) * 0.5, (st.x - st.y) * 0.5))
	return corners
#endregion


#region Derived artifacts
## Build a HeightMapShape3D mirroring `heights`/`dimensions`. Map uses this as the terrain
## picking collider and the resource TerrainGrid / NavManager / HeightmapMeshGenerator read,
## so the heightmap stays a GENERATED intermediate rather than an authored resource.
func to_height_shape() -> HeightMapShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = dimensions.x
	shape.map_depth = dimensions.y
	# HeightMapShape3D requires map_data length == map_width*map_depth; pad/repair if the
	# authored heights are the wrong size so a malformed resource degrades to flat rather
	# than erroring the whole map.
	var expected: int = dimensions.x * dimensions.y
	if heights.size() == expected:
		shape.map_data = heights
	else:
		var repaired := PackedFloat32Array()
		repaired.resize(expected)
		for i: int in mini(heights.size(), expected):
			repaired[i] = heights[i]
		shape.map_data = repaired
	return shape


## The cell-indexed impassability mask (index = z*grid_width()+x, 1 = blocked) that
## TerrainGrid.set_blocked_mask expects. A cell is blocked when its tile TYPE is impassable
## OR it is out-of-play (outside the screen-aligned bounds). Empty (all-clear) when there's
## no catalog, no impassable types, and no play bounds.
func blocked_mask() -> PackedByteArray:
	var gw: int = grid_width()
	var gd: int = grid_depth()
	var mask := PackedByteArray()
	mask.resize(gw * gd)  # zero-filled = all clear
	var have_catalog: bool = catalog != null
	for z: int in gd:
		for x: int in gw:
			var cell := Vector2i(x, z)
			if (have_catalog and not is_cell_type_passable(cell)) or not is_cell_in_play(cell):
				mask[z * gw + x] = 1
	return mask
#endregion
