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
## diamond spans 2 units of s or t, so the lane is about √2·PLAY_SIZE.y world units long.
## `MissionLane` (tools/missions/mission_lane.gd) turns lane coordinates into world positions
## for the scene's layout.
##
## A flat corridor, MissionLane.CORRIDOR_HALF_WIDTH either side of the lane's centre line, between
## hills that rise from its edges to the play bounds. The hills are made impassable by their
## STEEPNESS, not their height: a cell whose corners spread more than TerrainGrid.MAX_SLOPE_DIFF
## (tan 30°) is steep, and HILL_SLOPE keeps every hillside cell well past that, so there is no
## walkable plateau on top either. A gentle swell along the lane (HILL_SWELL) keeps the ridge
## line from reading as a ruler. TODO — cover, chokes and high ground are undecided.

const OUT_TRES: String = "res://resources/terrain/prologue_m1_terrain.tres"
const OUT_MESH: String = "res://resources/terrain/prologue_m1_terrain_surface.res"
const TILE_CATALOG: String = "res://resources/terrain/tile_catalog.tres"
## Hill rise per world unit of run away from the corridor's edge. 1.0 is a 45° face, so every
## hillside cell's corner spread is far past TerrainGrid.MAX_SLOPE_DIFF.
const HILL_SLOPE: float = 1.2
## How far the slope swells and dips along the lane, as a fraction of HILL_SLOPE, and over what
## wavelength in world units. Kept small enough that the slope never falls below 1.0.
const HILL_SWELL: float = 0.15
const HILL_SWELL_WAVELENGTH: float = 17.0


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
	var rebake_ok: bool = _verify_rebake_is_noop(heights)
	quit(0 if rebake_ok and _verify_hills_are_impassable(data) else 1)


## The ground height at corner `a_corner` of a `a_dims` corner grid: zero on the corridor, rising
## by HILL_SLOPE per unit of distance past its edge. A corner is a point of the Map-local grid
## centred on the origin, the same frame MissionLane works in.
func _height_at(a_corner: Vector2i, a_dims: Vector2i) -> float:
	var half: Vector2 = Vector2(a_dims - Vector2i.ONE) * 0.5
	var lane: Vector2 = MissionLane.to_lane(Vector3(a_corner.x - half.x, 0.0, a_corner.y - half.y))
	var past_edge: float = absf(lane.y) - MissionLane.CORRIDOR_HALF_WIDTH
	if past_edge <= 0.0:
		return 0.0
	var swell: float = 1.0 + HILL_SWELL * DMath.sin(TAU * lane.x / HILL_SWELL_WAVELENGTH)
	return past_edge * HILL_SLOPE * swell


## Every in-play cell whose centre lies a full cell past the corridor's edge must be too steep to
## cross, and every cell wholly inside the corridor flat: the property the hills exist for, checked
## against the game's own rule (TerrainGrid.MAX_SLOPE_DIFF) rather than assumed from HILL_SLOPE.
## The cells the edge itself crosses are left out — part corridor, part hill.
func _verify_hills_are_impassable(a_data: TerrainData) -> bool:
	var grid_half: Vector2 = Vector2(a_data.grid_width(), a_data.grid_depth()) * 0.5
	var walkable_hill: int = 0
	var uneven_corridor: int = 0
	var hill_cells: int = 0
	for z: int in a_data.grid_depth():
		for x: int in a_data.grid_width():
			var cell := Vector2i(x, z)
			if not a_data.is_cell_in_play(cell):
				continue
			var centre := Vector3(x + 0.5 - grid_half.x, 0.0, z + 0.5 - grid_half.y)
			var past_edge: float = (
				absf(MissionLane.to_lane(centre).y) - MissionLane.CORRIDOR_HALF_WIDTH
			)
			var spread: float = a_data.cell_height_spread(cell)
			if past_edge >= 1.0:
				hill_cells += 1
				if spread <= TerrainGrid.MAX_SLOPE_DIFF:
					walkable_hill += 1
			elif past_edge <= -1.0 and spread != 0.0:
				uneven_corridor += 1
	print(
		(
			"hills: %d hillside cells, %d of them walkable (must be 0); %d uneven corridor cells"
			% [hill_cells, walkable_hill, uneven_corridor]
		)
	)
	return hill_cells > 0 and walkable_hill == 0 and uneven_corridor == 0


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
