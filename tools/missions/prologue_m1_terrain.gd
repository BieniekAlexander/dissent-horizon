extends SceneTree

## The PRIMARY source of prologue mission 1's terrain: one long west–east lane
## (gdd/campaigns/01-prologue/01-pervasive-mechanics.md §Setup). Writes both artifacts that
## describe the surface — `TerrainData.heights` and the brushable surface mesh — from one
## computation, then proves they agree by re-baking the mesh and requiring the heights back
## unchanged (CLAUDE.md §Regenerating data). Change the lane HERE and rerun; never edit the
## two outputs apart.
##
##   godot --headless --path . -s res://tools/missions/prologue_m1_terrain.gd
##
## The lane is the PLAY RECTANGLE itself: play bounds are impassable by construction, so its
## long, narrow shape is what keeps the fight in one lane. `play_size` is in diamonds along the
## screen axes — `.y` is the on-screen WIDTH (west–east), `.x` the on-screen HEIGHT — and one
## diamond spans 2 units of s or t, so the lane is about √2·LANE_HALF.y world units long.
## `MissionLane` (tools/missions/mission_lane.gd) turns lane coordinates into world positions
## for the scene's layout.
##
## Flat for now, so the first iteration is about the waves rather than the ground. TODO — shape
## (cover, chokes, high ground) is undecided; it goes in `_height_at`.

const OUT_TRES: String = "res://resources/terrain/prologue_m1_terrain.tres"
const OUT_MESH: String = "res://resources/terrain/prologue_m1_terrain_surface.res"
const TILE_CATALOG: String = "res://resources/terrain/tile_catalog.tres"


func _initialize() -> void:
	var data := TerrainData.new()
	data.play_size = MissionLane.PLAY_SIZE
	data.catalog = load(TILE_CATALOG) as TerrainTileCatalog
	var dims: Vector2i = data.dimensions
	var heights := PackedFloat32Array()
	heights.resize(dims.x * dims.y)
	for j: int in dims.y:
		for i: int in dims.x:
			heights[j * dims.x + i] = _height_at(Vector2i(i, j), dims)
	data.heights = heights
	print("lane: play_size %s, corner grid %s" % [data.play_size, dims])

	# ---- PRIMARY and its mesh form, written from the one computation above ------------------
	var mesh := ArrayMesh.new()
	TerrainMeshGrid.write_heights(mesh, dims, heights)
	if ResourceSaver.save(mesh, OUT_MESH) != OK:
		push_error("prologue_m1_terrain: could not save %s" % OUT_MESH)
		quit(1)
		return
	if ResourceSaver.save(data, OUT_TRES) != OK:
		push_error("prologue_m1_terrain: could not save %s" % OUT_TRES)
		quit(1)
		return
	print("wrote %s and %s" % [OUT_TRES.get_file(), OUT_MESH.get_file()])
	quit(0 if _verify_rebake_is_noop(heights) else 1)


## The ground height at corner `a_corner` of a `a_dims` corner grid.
func _height_at(_a_corner: Vector2i, _a_dims: Vector2i) -> float:
	return 0.0


## Re-read both artifacts from disk, cache bypassed, bake the mesh into the resource as
## `Map.bake_terrain_from_mesh` would, and require the heights to come back unchanged.
func _verify_rebake_is_noop(a_expected: PackedFloat32Array) -> bool:
	var data: TerrainData = ResourceLoader.load(OUT_TRES, "", ResourceLoader.CACHE_MODE_IGNORE)
	var mesh: Mesh = ResourceLoader.load(OUT_MESH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if data == null or mesh == null:
		push_error("prologue_m1_terrain: re-load failed")
		return false
	var on_disk: float = _max_abs_diff(data.heights, a_expected)
	var report: Dictionary = data.bake_source_mesh(mesh)
	var after_bake: float = _max_abs_diff(data.heights, a_expected)
	print(
		(
			"rebake: %d/%d corners covered, %d/%d cells voided"
			% [report["covered"], report["corners"], report["voided"], report["cells"]]
		)
	)
	print("residual  saved-vs-computed   %.9f" % on_disk)
	print("residual  rebaked-vs-computed %.9f   <- must be 0" % after_bake)
	var ok: bool = on_disk == 0.0 and after_bake == 0.0 and report["voided"] == 0
	print("VERDICT: %s" % ("rebake is a NO-OP" if ok else "REBAKE CHANGES THE MAP"))
	return ok


func _max_abs_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return INF
	var worst: float = 0.0
	for i: int in a.size():
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst
