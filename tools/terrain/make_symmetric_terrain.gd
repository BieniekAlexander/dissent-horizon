extends SceneTree

## Regenerate the POINT-SYMMETRIC terrain that `skirmish_symmetric.tscn` plays on, writing
## the PRIMARY data and re-deriving everything else from it.
##
##   godot --headless --path . -s res://tools/terrain/make_symmetric_terrain.gd
##
## WHY THIS EXISTS RATHER THAN A `.tres` REWRITE. The first pass at this map symmetrized
## `TerrainData.heights` in the resource text and left the SURFACE MESH alone, on the reasoning
## that the mesh is "cosmetic only — gameplay geometry comes from terrain_data". That holds
## right up until someone presses `Map.bake_terrain_from_mesh`, which runs the arrow the other
## way (mesh -> heights) and replaced the whole symmetric heightfield with the flat grid the
## `.res` still held. Two artifacts describe one surface, and an edit that touches only one of
## them is a landmine armed for whoever rebakes next.
##
## THE RULE, and it is the one in CLAUDE.md §Terrain: the surface mesh and `heights` are the
## SAME DATA in two representations. Write both, from one computation, in one pass — and then
## prove it by re-deriving: a bake of the mesh this wrote must reproduce the heights it wrote.
## That check runs at the bottom of this script and is what makes the output trustworthy.
##
## The scene half (entity reflection, the two start points) is
## `tools/selfplay/results/make_symmetric_scenario.py`; residuals are reported by
## `verify_symmetry.py`. This owns the terrain half only.

const SRC_TRES: String = "res://resources/terrain/mesh_plateau_terrain.tres"
const OUT_TRES: String = "res://resources/terrain/mesh_plateau_terrain_symmetric.tres"
const OUT_MESH: String = "res://resources/terrain/mesh_plateau_terrain_symmetric_surface.res"


func _initialize() -> void:
	var src: TerrainData = ResourceLoader.load(SRC_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	if src == null:
		push_error("make_symmetric_terrain: cannot load %s" % SRC_TRES)
		quit(1)
		return

	var dims: Vector2i = src.dimensions
	var w: int = dims.x
	var d: int = dims.y
	if src.heights.size() != w * d:
		push_error(
			(
				"make_symmetric_terrain: %s heights are %d, expected %d"
				% [SRC_TRES, src.heights.size(), w * d]
			)
		)
		quit(1)
		return

	print(
		(
			"source %s: play_size=%s corner grid %dx%d, height range [%.3f, %.3f]"
			% [SRC_TRES.get_file(), src.play_size, w, d, _min(src.heights), _max(src.heights)]
		)
	)

	var heights: PackedFloat32Array = _symmetrize_heights(src.heights, w, d)
	var tiles: PackedByteArray = _symmetrize_tiles(src, w - 1, d - 1)

	# ---- PRIMARY, written first ------------------------------------------------------------
	var out := TerrainData.new()
	out.play_size = src.play_size
	out.catalog = src.catalog
	out.heights = heights
	out.tile_types = tiles

	# ---- DERIVED, re-generated from it -----------------------------------------------------
	# The brushable surface mesh carries one vertex per corner, so it IS `heights` as geometry.
	var mesh := ArrayMesh.new()
	TerrainMeshGrid.write_heights(mesh, dims, heights)
	var err: int = ResourceSaver.save(mesh, OUT_MESH)
	if err != OK:
		push_error("make_symmetric_terrain: could not save %s (%d)" % [OUT_MESH, err])
		quit(1)
		return
	print("wrote %s (%d verts, aabb %s)" % [OUT_MESH.get_file(), w * d, mesh.get_aabb()])

	err = ResourceSaver.save(out, OUT_TRES)
	if err != OK:
		push_error("make_symmetric_terrain: could not save %s (%d)" % [OUT_TRES, err])
		quit(1)
		return
	print("wrote %s" % OUT_TRES.get_file())

	# ---- The check the first pass was missing: a rebake must be a NO-OP ---------------------
	quit(0 if _verify_rebake_is_noop(heights, w, d) else 1)


## Copy the x < 0 half of the corner grid onto the x > 0 half through the 180-degree point
## reflection (x, z) -> (-x, -z), which is corner (i, j) -> (W-1-i, D-1-j).
##
## The map declares that axis itself (`Map.mirror_secondary_axis = 2`), and W is EVEN, so
## x = i - (W-1)/2 is never zero and the two halves partition with no self-mapping column.
func _symmetrize_heights(a_heights: PackedFloat32Array, a_w: int, a_d: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = a_heights.duplicate()
	for j: int in a_d:
		for i: int in range(a_w / 2, a_w):
			out[j * a_w + i] = a_heights[(a_d - 1 - j) * a_w + (a_w - 1 - i)]
	return out


## The same reflection over the CELL grid, which is one smaller on each axis and therefore has
## an ODD side — so there IS a centre column, and it reflects onto itself with z negated. It
## needs its own pass or the two ends of that column disagree.
func _symmetrize_tiles(a_src: TerrainData, a_gw: int, a_gd: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a_gw * a_gd)
	for j: int in a_gd:
		for i: int in a_gw:
			out[j * a_gw + i] = a_src.tile_at(Vector2i(i, j))
	var centre: int = a_gw / 2
	for j: int in a_gd:
		for i: int in range(centre + 1, a_gw):
			out[j * a_gw + i] = out[(a_gd - 1 - j) * a_gw + (a_gw - 1 - i)]
	for j: int in range(centre + 1, a_gd):
		out[j * a_gw + centre] = out[(a_gd - 1 - j) * a_gw + centre]
	return out


## Re-read BOTH artifacts from disk (cache bypassed, so this is the bytes and not what is still
## in memory), bake the mesh into the resource exactly as `Map.bake_terrain_from_mesh` would,
## and require the heights to come back unchanged. This is the property the broken map failed.
func _verify_rebake_is_noop(a_expected: PackedFloat32Array, a_w: int, a_d: int) -> bool:
	var data: TerrainData = ResourceLoader.load(OUT_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	var mesh: Mesh = ResourceLoader.load(OUT_MESH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if data == null or mesh == null:
		push_error("make_symmetric_terrain: re-load failed")
		return false

	var on_disk: float = _max_abs_diff(data.heights, a_expected)
	var report: Dictionary = data.bake_source_mesh(mesh)
	var after_bake: float = _max_abs_diff(data.heights, a_expected)
	var asym: float = _asymmetry(data.heights, a_w, a_d)

	print(
		(
			"rebake: %d/%d corners covered, %d/%d cells voided (%d triangles, %d vertical)"
			% [
				report["covered"],
				report["corners"],
				report["voided"],
				report["cells"],
				report["triangles"],
				report["skipped_triangles"]
			]
		)
	)
	print("residual  saved-vs-computed   %.9f" % on_disk)
	print(
		"residual  rebaked-vs-computed %.9f   <- must be 0 for a rebake to be a no-op" % after_bake
	)
	print("residual  point-reflection    %.9f" % asym)

	var ok: bool = on_disk == 0.0 and after_bake == 0.0 and asym == 0.0
	print("VERDICT: %s" % ("rebake is a NO-OP" if ok else "REBAKE CHANGES THE MAP"))
	return ok


func _max_abs_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var worst: float = 0.0
	for i: int in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


## Max |h(x, z) - h(-x, -z)| over the whole corner grid.
func _asymmetry(a_heights: PackedFloat32Array, a_w: int, a_d: int) -> float:
	var worst: float = 0.0
	for j: int in a_d:
		for i: int in a_w:
			worst = maxf(
				worst, absf(a_heights[j * a_w + i] - a_heights[(a_d - 1 - j) * a_w + (a_w - 1 - i)])
			)
	return worst


func _min(a: PackedFloat32Array) -> float:
	var v: float = INF
	for f: float in a:
		v = minf(v, f)
	return v


func _max(a: PackedFloat32Array) -> float:
	var v: float = -INF
	for f: float in a:
		v = maxf(v, f)
	return v
