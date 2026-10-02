@tool
class_name TerrainData
extends Resource

## The single authored/generated source of truth for a map's terrain, replacing the old
## split between Map.height_map (a HeightMapShape3D .tres) and Map.blocked_cells.
##
## Parallel layers on the standard heightfield grids:
##   * `heights`     — per-CORNER, size dimensions.x * dimensions.y, index z*W + x.
##                     Same semantics as HeightMapShape3D.map_data (local-space Y).
##   * `tile_types`  — per-CELL, size (W-1) * (D-1), index z*(W-1) + x. Each byte indexes
##                     into `catalog.types`, a GROUND MATERIAL: art only, never passability.
##   * `void_cells`  — per-CELL, same indexing; 1 where there is no ground at all. Written
##                     only by the mesh bake. A void cell is out of play.
## Corners and cells sit on grids offset by half a cell — the usual heightfield layout.
##
## `play_size` is the ONLY authored geometry: the corner grid `dimensions` is derived to fit
## the play rectangle exactly, since the fit is fully determined by it (see
## `derive_dimensions`). Play bounds are therefore always in force.
##
## HeightMapShape3D is no longer authored directly; Map derives one from `heights`
## (to_height_shape) as a generated intermediate (picking collider + what TerrainGrid /
## NavManager / the mesh generator read), and derives TerrainGrid's blocked mask from the
## play area via `blocked_mask`. See gdd/systems/terrain-and-navigation/tile-types.md.

## Corner grid size (x = width W, y = depth D). Cells span (W-1) x (D-1). DERIVED from the
## authored play area — never authored itself, so there is exactly one place a map's size
## is decided. See `derive_dimensions` for why the fit is fully determined.
var dimensions: Vector2i:
	get:
		return derive_dimensions(play_size)


## The corner grid that exactly holds a `size` play rectangle. `play_size` IS the map size.
##
## ALWAYS SQUARE, with side `size.x + size.y`, whatever the play rectangle's aspect ratio —
## which is why `dimensions` is derived rather than authored: there is no shape left to
## choose. The arithmetic, and why there is deliberately no padding knob:
## gdd/systems/terrain-and-navigation/map-and-terrain-grid.md §The corner grid is DERIVED.
static func derive_dimensions(size: Vector2i) -> Vector2i:
	var side: int = size.x + size.y + 2
	return Vector2i(side, side)


## Re-fit the layers after an edit that moved `dimensions`, and emit `changed` so the Map
## re-derives.
##
## Only acts when BOTH layers currently match the OLD dims — i.e. a fully-loaded, consistent
## resource. During deserialization `play_size` lands before (or after) the layers, so the
## intermediate sizes are mismatched; remapping there would overwrite real data with defaults,
## and emitting would mark the resource dirty and risk an editor re-save writing the transient
## state to disk. Note this guards only the resize SIDE EFFECT — reads of `dimensions` are
## correct at any point during load, since it is a pure function of `play_size`.
func _refit_layers(a_old_dims: Vector2i) -> void:
	var new_dims: Vector2i = dimensions
	if new_dims == a_old_dims:
		return
	var old_cells: int = (a_old_dims.x - 1) * (a_old_dims.y - 1)
	var consistent: bool = (
		heights.size() == a_old_dims.x * a_old_dims.y
		and (tile_types.is_empty() or tile_types.size() == old_cells)
	)
	if not consistent:
		return
	_remap_layers(a_old_dims, new_dims)
	emit_changed()


## Resize `heights` (corner grid) and `tile_types` (cell grid) from `old_dims` to
## `new_dims`, preserving the overlapping top-left region and default-filling growth
## (height 0.0, tile type 0 = Open).
func _remap_layers(a_old_dims: Vector2i, a_new_dims: Vector2i) -> void:
	var new_heights := PackedFloat32Array()
	new_heights.resize(a_new_dims.x * a_new_dims.y)
	for z: int in mini(a_old_dims.y, a_new_dims.y):
		for x: int in mini(a_old_dims.x, a_new_dims.x):
			new_heights[z * a_new_dims.x + x] = heights[z * a_old_dims.x + x]
	heights = new_heights

	# Leave an empty (all-Open) tile_types empty — never materialize a zero-filled array,
	# and only remap when it genuinely matches the OLD cell grid, so a transient/mismatched
	# state can never overwrite real data with zeros.
	var ogw: int = a_old_dims.x - 1
	var ngw: int = a_new_dims.x - 1
	if tile_types.size() == ogw * (a_old_dims.y - 1):
		var new_types := PackedByteArray()
		new_types.resize(ngw * (a_new_dims.y - 1))
		for z: int in mini(a_old_dims.y - 1, a_new_dims.y - 1):
			for x: int in mini(ogw, ngw):
				new_types[z * ngw + x] = tile_types[z * ogw + x]
		tile_types = new_types
	# The void layer is the mesh bake's output and a resize invalidates it; re-bake instead.
	void_cells = PackedByteArray()


## Per-corner heights, size W*D, index z*W + x (local-space Y, = HeightMapShape3D.map_data).
@export var heights: PackedFloat32Array = PackedFloat32Array()

## Per-cell ground-material indices, size (W-1)*(D-1), index z*(W-1) + x. Empty = all the
## default material.
@export var tile_types: PackedByteArray = PackedByteArray()

## Per-cell "no ground here" flags, same indexing; 1 = void. Empty = no void cells. The mesh
## bake's output (bake_source_mesh), never painted. A layer of any other size is stale — the
## map was resized since the bake — and reads as no voids; re-bake to restore them.
@export var void_cells: PackedByteArray = PackedByteArray()

## The shared palette these indices refer to.
@export var catalog: TerrainTileCatalog

## The play rectangle's on-screen size, in DIAMONDS, and THE map's size: the corner grid is
## derived to fit it (see `derive_dimensions`), so this is the one field that decides how big
## a map is. play_size.x is the extent along s = x+z, play_size.y along t = x-z. At the
## default camera (RTSCamera3D at +X+Z looking at origin) screen-right is v = x-z and
## screen-up is -(x+z), so on screen play_size.y is the WIDTH and play_size.x is the HEIGHT.
## Centred on the grid; rotates with the camera. Rectangular is fine — the two axes are
## independent. Play bounds are always in force: the grid is sized to the rectangle, so the
## (x,z) corners falling outside it are chopped (mesh holes + impassable) by construction.
@export var play_size: Vector2i = Vector2i(50, 50):
	set(value):
		var new_size: Vector2i = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		if new_size == play_size:
			return
		var old_dims: Vector2i = dimensions
		play_size = new_size
		_refit_layers(old_dims)


#region Mesh source
## Rasterize `mesh` into `heights`, and mark every cell the mesh does not cover as
## void (out of play: impassable and not rendered), so an island or disc surface reads as a
## hole beyond its rim rather than as flat ground at whatever height the fill extended outward.
##
## Cell coverage is ALL FOUR CORNERS, not any: a cell straddling the surface's edge has no
## well-defined quad, and voiding it keeps the rendered mesh and the navmesh agreeing on where
## the surface stops. The cost is that the rim staircases at cell resolution, which is
## inherent to putting a curved boundary on a grid.
##
## The bake owns `void_cells` outright and never touches `tile_types`, so materials painted
## over baked terrain survive a re-bake.
##
## THE MESH IS A PARAMETER, NOT A FIELD, and that is deliberate. It used to be an
## `@export var source_mesh: Mesh` on this resource, which crashed the Godot editor: a Resource
## is drawn as a nested sub-inspector, and a resource-valued property INSIDE one made the
## inspector free objects mid-signal and then dereference a null pointer on the next open
## (confirmed by bisection — clearing the field made the crash go away, and the four crash
## reports were byte-identical). The mesh is an authoring input and rendered geometry, both
## scene concerns, so it lives on the Map node (`Map.terrain_source_mesh`); this resource stays
## what it always was — the baked gameplay artifact — and its inspector is now structurally
## identical to a brush-authored map's, which was never affected.
##
## `mesh_to_local` is applied to every vertex before rasterizing: it is where a mesh authored
## at a different scale, offset or orientation gets fitted to the corner grid, which is read in
## its own local frame (one unit per cell, centred on the origin, +Y up).
##
## Returns a report Dictionary: corners, covered, cells, voided, triangles, skipped_triangles.
## Empty when there is no mesh to bake.
func bake_source_mesh(a_mesh: Mesh, a_mesh_to_local: Transform3D = Transform3D()) -> Dictionary:
	if a_mesh == null:
		return {}
	var dims: Vector2i = dimensions
	var result = MeshHeightfieldBaker.bake(a_mesh, dims, a_mesh_to_local)
	heights = result.heights

	var gw: int = grid_width()
	var gd: int = grid_depth()
	var voids := PackedByteArray()
	voids.resize(gw * gd)
	var voided: int = 0
	for z: int in gd:
		for x: int in gw:
			var covered: bool = (
				result.hit[z * dims.x + x] == 1
				and result.hit[z * dims.x + x + 1] == 1
				and result.hit[(z + 1) * dims.x + x] == 1
				and result.hit[(z + 1) * dims.x + x + 1] == 1
			)
			if not covered:
				voids[z * gw + x] = 1
				voided += 1
	void_cells = voids if voided > 0 else PackedByteArray()

	emit_changed()
	return {
		"corners": result.corner_count(),
		"covered": result.hit_count(),
		"cells": gw * gd,
		"voided": voided,
		"triangles": result.triangle_count,
		"skipped_triangles": result.skipped_triangles,
	}


#endregion


#region Dimensions
func map_width() -> int:
	return dimensions.x


func map_depth() -> int:
	return dimensions.y


func grid_width() -> int:
	return dimensions.x - 1


func grid_depth() -> int:
	return dimensions.y - 1


#endregion


#region Accessors
## The tile-type index of cell (x, z); DEFAULT (Open) when tile_types is empty or the
## cell is out of range.
func tile_at(a_cell: Vector2i) -> int:
	if tile_types.is_empty():
		return TerrainTileCatalog.DEFAULT_INDEX
	var idx: int = a_cell.y * grid_width() + a_cell.x
	if idx < 0 or idx >= tile_types.size():
		return TerrainTileCatalog.DEFAULT_INDEX
	return tile_types[idx]


## Whether cell (x, z) has no ground at all — the mesh bake found no surface over it.
func is_cell_void(a_cell: Vector2i) -> bool:
	var gw: int = grid_width()
	if void_cells.size() != gw * grid_depth() or not is_cell_in_bounds(a_cell):
		return false
	return void_cells[a_cell.y * gw + a_cell.x] != 0


## The flat albedo the baseline terrain shader shows for cell (x, z)'s type. Default
## open-ground colour when there's no catalog.
func cell_map_color(a_cell: Vector2i) -> Color:
	return catalog.map_color(tile_at(a_cell)) if catalog != null else TileType.DEFAULT_MAP_COLOR


## Whether cell (x, z) is in play: inside the screen-aligned play rectangle (see
## StaggeredGrid) and not void. Everything out of play is impassable and draws as a gap.
##
## The grid is sized to the play rectangle, so this is never vacuously true: the four (x, z)
## grid corners lie outside the rectangle for ANY play_size and are always chopped.
func is_cell_in_play(a_cell: Vector2i) -> bool:
	return (
		StaggeredGrid.screen_rect_contains(a_cell, _play_center_st(), _play_half())
		and not is_cell_void(a_cell)
	)


## Centre of the play rectangle in screen (s = x+z, t = x-z) space — the grid's middle cell.
func _play_center_st() -> Vector2:
	var cx: float = (grid_width() - 1) * 0.5
	var cz: float = (grid_depth() - 1) * 0.5
	return Vector2(cx + cz, cx - cz)


## Play-rectangle half-extents in (s, t) space, derived from play_size. One diamond spans 2
## units of s (or t), so N diamonds across → a half-extent of N.
func _play_half() -> Vector2:
	return Vector2(float(play_size.x), float(play_size.y))


## Screen-aligned play half-extents (along s = x+z and t = x-z), in (s, t) cell-diagonal
## units. For UI that frames the play area (e.g. the minimap): one diamond spans 2 units,
## and the play rectangle is centred on the grid.
func play_half_extents() -> Vector2:
	return _play_half()


## The four corners of the screen-aligned play rectangle as continuous (x, z) cell-space
## points — the tips of the play diamond, in winding order. For editor overlays that want to
## outline the play area.
func play_bounds_grid_corners() -> PackedVector2Array:
	var c: Vector2 = _play_center_st()
	var h: Vector2 = _play_half()
	var corners := PackedVector2Array()
	for st: Vector2 in [
		Vector2(c.x - h.x, c.y - h.y),
		Vector2(c.x + h.x, c.y - h.y),
		Vector2(c.x + h.x, c.y + h.y),
		Vector2(c.x - h.x, c.y + h.y),
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


## The per-cell layers the terrain shader samples by world XZ: one texel per CELL, with
## R = tile index / 255 and G = 255 when the cell is TOO STEEP TO TRAVERSE.
##
## This is how a drawn SURFACE MESH gets per-cell identity. A generated mesh can carry tile type
## in its vertex data because its vertices are the grid; a modelled surface's vertices are not,
## so the lookup has to happen per fragment instead. Sampled with nearest filtering by the
## shader — both channels are per-cell facts that must never blend across a boundary.
##
## THE STEEP CHANNEL IS THE SAME TEST THE NAVMESH USES: corner spread against
## TerrainGrid.MAX_SLOPE_DIFF. Cliff shading therefore marks exactly the cells a unit cannot
## walk on, rather than approximating it from the interpolated surface normal — which was both
## soft-edged and subtly offset, because vertex normals are a central difference spanning
## neighbouring cells. Impassability is a binary fact about a cell and now reads as one.
##
## Built straight into a PackedByteArray rather than through Image.set_pixel, and with the
## spread computed inline: this is rebuilt on every brush step, so per-cell function calls over
## 25,000 cells are the difference between a responsive brush and a stuttering one.
func cell_data_texture() -> ImageTexture:
	var gw: int = grid_width()
	var gd: int = grid_depth()
	var w: int = dimensions.x
	var data := PackedByteArray()
	data.resize(maxi(gw, 1) * maxi(gd, 1) * 2)

	var typed: bool = tile_types.size() == gw * gd
	var measurable: bool = heights.size() == w * dimensions.y
	var limit: float = TerrainGrid.MAX_SLOPE_DIFF

	for z: int in gd:
		for x: int in gw:
			var index: int = tile_types[z * gw + x] if typed else TerrainTileCatalog.DEFAULT_INDEX

			var steep: int = 0
			if measurable:
				var i: int = z * w + x
				var h00: float = heights[i]
				var h10: float = heights[i + 1]
				var h01: float = heights[i + w]
				var h11: float = heights[i + w + 1]
				var lo: float = minf(minf(h00, h10), minf(h01, h11))
				var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
				if hi - lo > limit:
					steep = 255

			var at: int = (z * gw + x) * 2
			data[at] = index
			data[at + 1] = steep

	return ImageTexture.create_from_image(
		Image.create_from_data(maxi(gw, 1), maxi(gd, 1), false, Image.FORMAT_RG8, data)
	)


## The cell-indexed impassability mask (index = z*grid_width()+x, 1 = blocked) that
## TerrainGrid.set_blocked_mask expects: every cell out of play. Ground material never
## blocks — impassability is always something visible in the terrain.
func blocked_mask() -> PackedByteArray:
	var gw: int = grid_width()
	var gd: int = grid_depth()
	var mask := PackedByteArray()
	mask.resize(gw * gd)  # zero-filled = all clear
	for z: int in gd:
		for x: int in gw:
			var cell := Vector2i(x, z)
			if not is_cell_in_play(cell):
				mask[z * gw + x] = 1
	return mask


#endregion


#region Entity support
## Whether cell (x, z) is inside the cell grid at all.
func is_cell_in_bounds(a_cell: Vector2i) -> bool:
	return a_cell.x >= 0 and a_cell.x < grid_width() and a_cell.y >= 0 and a_cell.y < grid_depth()


## Spread (max - min) across cell (x, z)'s four corner heights. 0.0 for an out-of-bounds
## cell or a malformed `heights` layer — degrading to "flat" rather than erroring, the same
## way to_height_shape repairs a wrong-sized array.
func cell_height_spread(a_cell: Vector2i) -> float:
	var w: int = dimensions.x
	if not is_cell_in_bounds(a_cell) or heights.size() != w * dimensions.y:
		return 0.0
	var h00: float = heights[a_cell.y * w + a_cell.x]
	var h10: float = heights[a_cell.y * w + a_cell.x + 1]
	var h01: float = heights[(a_cell.y + 1) * w + a_cell.x]
	var h11: float = heights[(a_cell.y + 1) * w + a_cell.x + 1]
	return maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))


## The average of cell (x, z)'s four corner heights — the surface height AT ITS CENTRE, which
## is what a water level is measured against (see WaterBasin) and where a unit standing in the
## cell sits. 0.0 for an out-of-bounds cell or a malformed `heights` layer, like the spread.
func cell_mean_height(a_cell: Vector2i) -> float:
	var w: int = dimensions.x
	if not is_cell_in_bounds(a_cell) or heights.size() != w * dimensions.y:
		return 0.0
	return (
		0.25
		* (
			heights[a_cell.y * w + a_cell.x]
			+ heights[a_cell.y * w + a_cell.x + 1]
			+ heights[(a_cell.y + 1) * w + a_cell.x]
			+ heights[(a_cell.y + 1) * w + a_cell.x + 1]
		)
	)


## Height at grid CORNER (cx, cz) — the heightmap sample, not a cell average. What the water
## surface mesh needs: a shared corner must read the same height from both cells or the
## depth gradient creases along every cell boundary.
func corner_height(a_corner: Vector2i) -> float:
	var w: int = dimensions.x
	if a_corner.x < 0 or a_corner.x >= w or a_corner.y < 0 or a_corner.y >= dimensions.y:
		return 0.0
	if heights.size() != w * dimensions.y:
		return 0.0
	return heights[a_corner.y * w + a_corner.x]


## Whether cell (x, z)'s four corners are all at the same height. Mirrors TerrainGrid.is_flat,
## which structure placement uses to require perfectly level ground — stricter than the slope
## tolerance cell_supports_entity applies to units.
func cell_is_flat(a_cell: Vector2i) -> bool:
	return is_cell_in_bounds(a_cell) and is_zero_approx(cell_height_spread(a_cell))


## Whether cell (x, z) is ground an entity can stand on: in bounds, in play (which excludes
## void), and no steeper than TerrainGrid.MAX_SLOPE_DIFF.
##
## This is the EDITOR-time counterpart to TerrainGrid.is_passable: Map._ready returns early
## in the editor, so terrain_grid / cell_grid do not exist while authoring and their rules
## have to be re-derived here. The slope threshold is READ FROM TerrainGrid rather than
## restated, so the two can't drift apart. Building occupancy is deliberately not considered
## — that is runtime-only state (see Map.reconcile_entities_with_terrain).
func cell_supports_entity(a_cell: Vector2i) -> bool:
	if not is_cell_in_bounds(a_cell):
		return false
	if not is_cell_in_play(a_cell):
		return false
	return cell_height_spread(a_cell) <= TerrainGrid.MAX_SLOPE_DIFF


#endregion

#region Region translation
## Which layer(s) a region operation touches. A layer left out is returned unchanged, so
## callers can always assign both results back.
const LAYER_HEIGHTS: int = 1 << 0
const LAYER_TILE_TYPES: int = 1 << 1
const LAYER_ALL: int = LAYER_HEIGHTS | LAYER_TILE_TYPES

## Default fill for terrain no source cell maps onto.
const _DEFAULT_HEIGHT: float = 0.0

## Reflection applied to a region as it is written to its destination. Rotation is
## deliberately absent: it transposes width and depth, which no caller handles yet.
enum RegionTransform { NONE, FLIP_X, FLIP_Z, FLIP_BOTH }

## What a whole-map shift does with the cells that fall off one edge (and the ones newly
## exposed on the other):
##   CLIP        — drop what falls off; default-fill what is exposed (height 0, tile Open).
##   WRAP        — re-insert what falls off on the opposite edge (a tiling shift).
##   EXTEND_EDGE — repeat the boundary row/column outward, so the exposed strip continues
##                 the terrain instead of dropping to height 0.
enum EdgePolicy { CLIP, WRAP, EXTEND_EDGE }


## Copy the `source_cells` rectangle (CELL space) so that its origin lands on `dest_origin`,
## returning the resulting layers as {"heights": PackedFloat32Array, "tile_types":
## PackedByteArray}. Never mutates this resource — the caller decides when (and whether) to
## commit, which is what lets the terrain brush snapshot before/after for one undo action.
##
## Corners vs cells is the whole trick here: a w x h block of CELLS is bounded by
## (w+1) x (h+1) CORNERS, so the heights layer copies one more row and column than the
## tile-types layer does. Reads come from this resource's live arrays while writes go into
## copies, so a destination overlapping its own source (nudging a region a cell or two)
## still reads pre-move data.
##
## Destination cells outside the grid are dropped, not rejected — the same permissiveness
## the brush's footprint stamping already has. `clear_source` resets the part of the source
## the destination does NOT cover, which is the difference between Copy and Cut.
##
## Unlike the brush's _stamp_tiles this does NOT skip out-of-play cells. A region translate
## is a bulk data move rather than an authoring gesture, and filtering would make it
## non-invertible (shift +5 then -5 would not restore the map) — a much worse property for a
## primitive than the dead data it avoids, which blocked_mask() masks off anyway.
func translate_region(
	a_source_cells: Rect2i,
	a_dest_origin: Vector2i,
	a_layers: int = LAYER_ALL,
	a_transform: RegionTransform = RegionTransform.NONE,
	a_clear_source: bool = false
) -> Dictionary:
	var result: Dictionary = {"heights": heights, "tile_types": tile_types}
	if a_source_cells.size.x <= 0 or a_source_cells.size.y <= 0:
		return result

	var dest_cells := Rect2i(a_dest_origin, a_source_cells.size)
	var flip_x: bool = (
		a_transform == RegionTransform.FLIP_X or a_transform == RegionTransform.FLIP_BOTH
	)
	var flip_z: bool = (
		a_transform == RegionTransform.FLIP_Z or a_transform == RegionTransform.FLIP_BOTH
	)

	if a_layers & LAYER_HEIGHTS:
		result["heights"] = _translate_heights(
			a_source_cells, a_dest_origin, dest_cells, flip_x, flip_z, a_clear_source
		)
	if a_layers & LAYER_TILE_TYPES:
		result["tile_types"] = _translate_tile_types(
			a_source_cells, a_dest_origin, dest_cells, flip_x, flip_z, a_clear_source
		)
	return result


## The heights half of translate_region, over the source's (w+1) x (h+1) CORNER block. A
## flip reverses corner index i to (w - i), not (w - 1 - i), because a w-cell span has
## w+1 corners.
func _translate_heights(
	a_source_cells: Rect2i,
	a_dest_origin: Vector2i,
	a_dest_cells: Rect2i,
	a_flip_x: bool,
	a_flip_z: bool,
	a_clear_source: bool
) -> PackedFloat32Array:
	var mw: int = dimensions.x
	var md: int = dimensions.y
	if heights.size() != mw * md:
		return heights  # malformed layer — leave it alone rather than half-writing it
	var out: PackedFloat32Array = heights.duplicate()
	var w: int = a_source_cells.size.x
	var h: int = a_source_cells.size.y

	for j: int in range(h + 1):
		for i: int in range(w + 1):
			var src := Vector2i(a_source_cells.position.x + i, a_source_cells.position.y + j)
			if src.x < 0 or src.x >= mw or src.y < 0 or src.y >= md:
				continue
			var dst := Vector2i(
				a_dest_origin.x + ((w - i) if a_flip_x else i),
				a_dest_origin.y + ((h - j) if a_flip_z else j)
			)
			if dst.x < 0 or dst.x >= mw or dst.y < 0 or dst.y >= md:
				continue
			out[dst.y * mw + dst.x] = heights[src.y * mw + src.x]

	if a_clear_source:
		# Corner rects are one larger than their cell rects on each axis.
		var src_corners := Rect2i(a_source_cells.position, a_source_cells.size + Vector2i.ONE)
		var dst_corners := Rect2i(a_dest_cells.position, a_dest_cells.size + Vector2i.ONE)
		for j: int in range(src_corners.size.y):
			for i: int in range(src_corners.size.x):
				var c := src_corners.position + Vector2i(i, j)
				if dst_corners.has_point(c):
					continue  # the move landed here — clearing would erase what was just written
				if c.x < 0 or c.x >= mw or c.y < 0 or c.y >= md:
					continue
				out[c.y * mw + c.x] = _DEFAULT_HEIGHT
	return out


## The tile-types half of translate_region.
func _translate_tile_types(
	a_source_cells: Rect2i,
	a_dest_origin: Vector2i,
	a_dest_cells: Rect2i,
	a_flip_x: bool,
	a_flip_z: bool,
	a_clear_source: bool
) -> PackedByteArray:
	var gw: int = grid_width()
	var out: PackedByteArray = _materialized_tile_types()
	var w: int = a_source_cells.size.x
	var h: int = a_source_cells.size.y

	for j: int in range(h):
		for i: int in range(w):
			var src := Vector2i(a_source_cells.position.x + i, a_source_cells.position.y + j)
			if not is_cell_in_bounds(src):
				continue
			var dst := Vector2i(
				a_dest_origin.x + ((w - 1 - i) if a_flip_x else i),
				a_dest_origin.y + ((h - 1 - j) if a_flip_z else j)
			)
			if not is_cell_in_bounds(dst):
				continue
			out[dst.y * gw + dst.x] = tile_at(src)

	if a_clear_source:
		for j: int in range(h):
			for i: int in range(w):
				var c := a_source_cells.position + Vector2i(i, j)
				if a_dest_cells.has_point(c) or not is_cell_in_bounds(c):
					continue
				out[c.y * gw + c.x] = TerrainTileCatalog.DEFAULT_INDEX
	return _compacted_tile_types(out)


## Shift the WHOLE map by `offset` cells, returning the new layers the same way
## translate_region does. Expressed as a gather (each destination samples cell - offset)
## rather than a scatter, because that is what lets `edge_policy` describe the strip exposed
## on the trailing edge as well as the content that falls off the leading one.
##
## The corner grid shifts by the same integer offset as the cell grid, since corner (x, z)
## and cell (x, z) share an origin.
func shift_all(
	a_offset: Vector2i, a_layers: int = LAYER_ALL, a_edge_policy: EdgePolicy = EdgePolicy.CLIP
) -> Dictionary:
	var result: Dictionary = {"heights": heights, "tile_types": tile_types}
	if a_offset == Vector2i.ZERO:
		return result

	var mw: int = dimensions.x
	var md: int = dimensions.y
	if (a_layers & LAYER_HEIGHTS) and heights.size() == mw * md:
		var out_h := PackedFloat32Array()
		out_h.resize(mw * md)
		for z: int in md:
			for x: int in mw:
				var src := _resolve_source(Vector2i(x, z) - a_offset, mw, md, a_edge_policy)
				out_h[z * mw + x] = heights[src.y * mw + src.x] if src.x >= 0 else _DEFAULT_HEIGHT
		result["heights"] = out_h

	if a_layers & LAYER_TILE_TYPES:
		var gw: int = grid_width()
		var gd: int = grid_depth()
		var out_t := PackedByteArray()
		out_t.resize(gw * gd)
		for z: int in gd:
			for x: int in gw:
				var src := _resolve_source(Vector2i(x, z) - a_offset, gw, gd, a_edge_policy)
				out_t[z * gw + x] = tile_at(src) if src.x >= 0 else TerrainTileCatalog.DEFAULT_INDEX
		result["tile_types"] = _compacted_tile_types(out_t)
	return result


## Map a gathered source coordinate into the grid per `policy`, or Vector2i(-1, -1) when
## CLIP puts it off the edge (the caller default-fills those).
func _resolve_source(a_src: Vector2i, a_w: int, a_d: int, a_policy: EdgePolicy) -> Vector2i:
	match a_policy:
		EdgePolicy.WRAP:
			return Vector2i(wrapi(a_src.x, 0, a_w), wrapi(a_src.y, 0, a_d))
		EdgePolicy.EXTEND_EDGE:
			return Vector2i(clampi(a_src.x, 0, a_w - 1), clampi(a_src.y, 0, a_d - 1))
		_:
			if a_src.x < 0 or a_src.x >= a_w or a_src.y < 0 or a_src.y >= a_d:
				return Vector2i(-1, -1)
			return a_src


## `tile_types` sized to the cell grid, materializing an all-Open array when it is empty
## (the same repair _paint_tiles does before stamping).
func _materialized_tile_types() -> PackedByteArray:
	var expected: int = grid_width() * grid_depth()
	if tile_types.size() == expected:
		return tile_types.duplicate()
	var fresh := PackedByteArray()
	fresh.resize(expected)
	return fresh


## Collapse an all-Open array back to empty, preserving the "empty means all-Open"
## convention _remap_layers is careful about — so a region op on an untouched map doesn't
## silently materialize a full zero-filled layer into the saved resource.
func _compacted_tile_types(a_types: PackedByteArray) -> PackedByteArray:
	for b: int in a_types:
		if b != TerrainTileCatalog.DEFAULT_INDEX:
			return a_types
	return PackedByteArray()
#endregion
