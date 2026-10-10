@tool
class_name MapSymmetry
extends RefCounted

## Makes a generated map point-symmetric about its centre, the self-play harness's training
## control (map-generation.md §Symmetric maps): the half holding the first start is kept, and
## the other half is overwritten with its image under (x, z) -> (-x, -z). Draws nothing, so a
## seed still names one map.
##
## The dividing line is s = x + z through the centre. The grid is G cells square, so corner
## (i, j) images to (G - i, G - j), cell (x, z) to (G - 1 - x, G - 1 - z), and a continuous
## cell-space point p to (G, G) - p.
##
## An instance is one reflection: the grid size and which side of the line is kept, fixed at
## construction and read by every helper.

#region Properties
var _cells: int = 0
## +1 when the kept half is s > centre, -1 when it is s < centre.
var _side: int = 0
#endregion


## Mirror `generated` in place, or append an error and leave it unusable. `share_of(point)` is
## each alliance's access share of a point, measured on the mirrored map — called once per kept
## feature after the terrain, starts and water are final. An image feature takes its original's
## share with the alliances swapped, so balance holds by construction.
static func apply(
	generated: GeneratedMap, start_clear_radius_cells: int, share_of: Callable
) -> void:
	if generated.starts.size() != 2 or generated.starts[0].alliance == generated.starts[1].alliance:
		generated.errors.append("a symmetric map needs exactly two starts, one per alliance")
		return
	var cells: int = generated.terrain.grid_width()
	var first: Vector2 = generated.starts[0].position
	var offset: float = first.x + first.y - cells
	if is_zero_approx(offset):
		generated.errors.append("the first start lies on the symmetry axis")
		return
	var mirror := MapSymmetry.new()
	mirror._cells = cells
	mirror._side = 1 if offset > 0.0 else -1
	if not mirror._is_start_box_kept(first, start_clear_radius_cells):
		generated.errors.append("the first start's clear box crosses the symmetry axis")
		return
	mirror._mirror_terrain(generated.terrain)
	var starts: Array[MapStart] = [
		generated.starts[0], MapStart.at(mirror.point_image(first), generated.starts[1].alliance)
	]
	generated.starts = starts
	generated.chasm_waters = mirror._mirrored_waters(generated.terrain, generated.chasm_waters)
	generated.features = mirror._mirrored_features(generated.features, share_of)


#region Images
func point_image(a_point: Vector2) -> Vector2:
	return Vector2(_cells, _cells) - a_point


func corner_image(a_corner: Vector2i) -> Vector2i:
	return Vector2i(_cells, _cells) - a_corner


func cell_image(a_cell: Vector2i) -> Vector2i:
	return Vector2i(_cells - 1, _cells - 1) - a_cell


## Whether the kept half is the source of the point at (s, t) offsets from the centre: strictly
## on the kept side, or on the line and on the kept side of the centre along it. The centre
## itself is its own image and owned by neither.
func _owns(a_s_offset: int, a_t_offset: int) -> bool:
	if a_s_offset != 0:
		return _side * a_s_offset > 0
	return _side * a_t_offset > 0


func _owns_corner(a_corner: Vector2i) -> bool:
	return _owns(a_corner.x + a_corner.y - _cells, a_corner.x - a_corner.y)


func _owns_cell(a_cell: Vector2i) -> bool:
	return _owns(a_cell.x + a_cell.y + 1 - _cells, a_cell.x - a_cell.y)


## Whether every corner of the cell is strictly on the kept side — so nothing the mirror writes
## touches it, and its image cannot share a corner with it.
func _is_cell_clear_of_axis(a_cell: Vector2i) -> bool:
	var s: int = a_cell.x + a_cell.y
	return _side * (s - _cells) > 0 and _side * (s + 2 - _cells) > 0


#endregion


#region Terrain
func _mirror_terrain(a_terrain: TerrainData) -> void:
	var heights: PackedFloat32Array = a_terrain.heights
	var corners: int = _cells + 1
	for j: int in corners:
		for i: int in corners:
			var image: Vector2i = corner_image(Vector2i(i, j))
			if _owns_corner(image):
				heights[j * corners + i] = heights[image.y * corners + image.x]
	a_terrain.heights = heights
	a_terrain.tile_types = _mirrored_cell_layer(a_terrain.tile_types)
	a_terrain.void_cells = _mirrored_cell_layer(a_terrain.void_cells)


## A per-cell layer with every unowned cell copied from its image. An empty or stale layer
## (the wrong size) is returned untouched: it reads the same everywhere already.
func _mirrored_cell_layer(a_layer: PackedByteArray) -> PackedByteArray:
	if a_layer.size() != _cells * _cells:
		return a_layer
	var layer: PackedByteArray = a_layer.duplicate()
	for z: int in _cells:
		for x: int in _cells:
			var image: Vector2i = cell_image(Vector2i(x, z))
			if _owns_cell(image):
				layer[z * _cells + x] = layer[image.y * _cells + image.x]
	return layer


## The start's clear box and the one-cell ring whose corners it shares — what pass 6 keeps on
## one level — all clear of the axis, so the mirror leaves the start's ground as it was.
func _is_start_box_kept(a_start: Vector2, a_radius: int) -> bool:
	var origin := Vector2i((a_start - Vector2.ONE * a_radius).round()) - Vector2i.ONE
	var side: int = 2 * a_radius + 2
	return PlacementGrid.rect_cells(origin, Vector2i(side, side)).all(_is_cell_clear_of_axis)


#endregion


#region Water
## The kept half's chasm seeds and their images at the same level, minus any seed whose water,
## refilled on the mirrored heights, already holds an earlier seed: one body per stretch, even
## where a stretch now runs across the axis into its own image.
func _mirrored_waters(a_terrain: TerrainData, a_waters: Array[Dictionary]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var images: Array[Dictionary] = []
	for water: Dictionary in a_waters:
		var seed_cell: Vector2i = water.seed_cell
		var image: Vector2i = cell_image(seed_cell)
		if image == seed_cell:
			candidates.append(water)
		elif _owns_cell(seed_cell):
			candidates.append(water)
			images.append({"seed_cell": image, "level": water.level})
	candidates.append_array(images)
	var kept: Array[Dictionary] = []
	for water: Dictionary in candidates:
		var basin: WaterBasin = WaterBasin.fill(a_terrain, water.seed_cell, water.level)
		if not kept.any(func(k: Dictionary) -> bool: return basin.depth_by_cell.has(k.seed_cell)):
			kept.append(water)
	return kept


#endregion


#region Features
## The features clear of the axis, re-measured, followed by their images in the same order.
func _mirrored_features(a_features: Array[MapFeature], a_share_of: Callable) -> Array[MapFeature]:
	var kept: Array[MapFeature] = []
	kept.assign(a_features.filter(_is_feature_kept))
	for feature: MapFeature in kept:
		feature.realised_share = a_share_of.call(feature.center)
	var mirrored: Array[MapFeature] = kept.duplicate()
	for feature: MapFeature in kept:
		mirrored.append(_feature_image(feature))
	return mirrored


## A feature survives only when every cell it stands on — and a pond's rim, whose heights hold
## its water — is clear of the axis. Then its image cannot overlap anything kept.
func _is_feature_kept(a_feature: MapFeature) -> bool:
	var cells: Array[Vector2i] = a_feature.structure_cells()
	for cell: Vector2i in a_feature.pond_cells:
		for dx: int in range(-FeaturePlacer.POND_RIM_CELLS, FeaturePlacer.POND_RIM_CELLS + 1):
			for dz: int in range(-FeaturePlacer.POND_RIM_CELLS, FeaturePlacer.POND_RIM_CELLS + 1):
				cells.append(cell + Vector2i(dx, dz))
	return cells.all(_is_cell_clear_of_axis)


func _feature_image(a_feature: MapFeature) -> MapFeature:
	var image := MapFeature.new()
	image.kind = a_feature.kind
	image.center = point_image(a_feature.center)
	image.value = a_feature.value
	image.target_share = _swapped(a_feature.target_share)
	image.realised_share = _swapped(a_feature.realised_share)
	image.plan = a_feature.plan
	for placement: Dictionary in a_feature.placements:
		var rect: Rect2i = MapFeature.placement_rect(placement)
		var turns: int = placement.get("quarter_turns", 0)
		# The image is the original turned a half turn about the centre, the piece with it.
		image.placements.append(
			{
				"piece": placement.piece,
				"origin": Vector2i(_cells, _cells) - rect.position - rect.size,
				"quarter_turns": posmod(turns + 2, 4),
			}
		)
	for cell: Vector2i in a_feature.pond_cells:
		image.pond_cells.append(cell_image(cell))
	image.pond_charge = a_feature.pond_charge
	image.pond_richness = a_feature.pond_richness
	image.pond_seed_cell = cell_image(a_feature.pond_seed_cell)
	image.pond_level = a_feature.pond_level
	return image


## A two-alliance share with the alliances exchanged, as the starts are by the reflection.
static func _swapped(share: PackedFloat32Array) -> PackedFloat32Array:
	var swapped: PackedFloat32Array = share.duplicate()
	swapped.reverse()
	return swapped
#endregion
