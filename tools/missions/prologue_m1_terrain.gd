extends SceneTree

## The PRIMARY source of prologue mission 1's terrain
## (gdd/campaigns/01-prologue/01-pervasive-mechanics.md §Setup). Writes both artifacts that
## describe the surface — `TerrainData.heights` and the brushable surface mesh — from one
## computation, then proves they agree by re-baking the mesh and requiring the heights back
## unchanged (CLAUDE.md §Regenerating data). Change the map HERE and rerun; never edit the two
## outputs apart.
##
##   godot --headless --path . -s res://tools/missions/prologue_m1_terrain.gd
##
## The walkable ground is the union of REGIONS, flat rectangles in MissionLane's frame (along,
## across); everything else is hillside that rises from the nearest region's edge at HILL_SLOPE,
## up to HILL_CAP. The hills are impassable by their STEEPNESS — a cell whose corners spread more
## than TerrainGrid.MAX_SLOPE_DIFF (tan 30°) is steep — and where they reach the cap the flat top
## is ringed by steep ground, so nothing can climb onto it. A gentle swell along the map
## (HILL_SWELL) keeps ridge lines from reading as rulers.
##
## The route, decided 2026-10-18 (Alex) and extended the same day: the player starts in START,
## walks north up WEST (the rescue fight) to the prison Compounds in NORTH, east through
## EAST_PASSAGE to the Recruits in SKIRMISH, on along GARRISON_ROAD past the building the player
## takes cover in, into FORK. From FORK, the Watch Towers' TOWER_FIELD lies east — open ground,
## with BEYOND, an empty lane, past it — and the narrow SOUTH_PASSAGE drops into MAIN, the
## west–east corridor the waves fight in. From MAIN's west end LANE_LINK drops south into
## SOUTH_LANE, a second west–east lane (added 2026-10-18). START does not open onto MAIN.
## `_verify_route` checks exactly that.
##
## TODO — cover, chokes and high ground inside the regions are undecided.

const OUT_TRES: String = "res://resources/terrain/prologue_m1_terrain.tres"
const OUT_MESH: String = "res://resources/terrain/prologue_m1_terrain_surface.res"
const TILE_CATALOG: String = "res://resources/terrain/tile_catalog.tres"

## The walkable regions: name -> Rect2 in MissionLane's frame, position = (west edge, south edge),
## size = (length along, width across). Rect2 is used for its arithmetic only.
const REGIONS: Dictionary = {
	"MAIN": Rect2(-10, -9, 80, 18),
	"START": Rect2(-70, -36, 20, 18),
	"WEST": Rect2(-72, -18, 22, 62),
	"NORTH": Rect2(-72, 44, 26, 18),
	"EAST_PASSAGE": Rect2(-46, 48, 16, 10),
	"SKIRMISH": Rect2(-32, 36, 20, 24),
	"GARRISON_ROAD": Rect2(-12, 44, 22, 12),
	"FORK": Rect2(10, 30, 30, 34),
	"TOWER_FIELD": Rect2(40, 36, 26, 24),
	"BEYOND": Rect2(66, 42, 18, 12),
	"SOUTH_PASSAGE": Rect2(20, 9, 5, 21),
	"LANE_LINK": Rect2(-10, -24, 10, 15),
	"SOUTH_LANE": Rect2(-10, -40, 100, 16),
}
## Where the flood fill of walkable ground starts.
const ROUTE_START: String = "START"
## Regions the route must never reach directly from START without the rest of the route between
## them: checked as "START's flood, with SOUTH_PASSAGE walled off, does not reach MAIN".
const ROUTE_GATE: String = "SOUTH_PASSAGE"
const ROUTE_END: String = "MAIN"

## Hill rise per world unit of run away from the nearest region. 1.0 is a 45° face, so a
## hillside cell's corner spread is far past TerrainGrid.MAX_SLOPE_DIFF.
const HILL_SLOPE: float = 1.2
## The hills' height cap, so the far corners are hills rather than towers over the camera. At
## 3 (Alex, 2026-10-18) a hill tops out 2.5 units past its region's edge, so most hill country
## is a flat-topped mesa: walkable ground, but ringed by its steep face, so nothing reaches it
## (`_verify_route` checks that).
const HILL_CAP: float = 3.0
## How far the slope swells and dips along the map, as a fraction of HILL_SLOPE, and over what
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
	var half: Vector2 = Vector2(dims - Vector2i.ONE) * 0.5
	for j: int in dims.y:
		for i: int in dims.x:
			var lane: Vector2 = MissionLane.to_lane(Vector3(i - half.x, 0.0, j - half.y))
			heights[j * dims.x + i] = _height_at(lane)
	data.heights = heights
	print("map: play_size %s, corner grid %s" % [data.play_size, dims])

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
	var route_ok: bool = _verify_route(data)
	quit(0 if rebake_ok and route_ok else 1)


## How far `a_lane` lies outside every region, in world units; 0 inside any of them.
static func region_distance(a_lane: Vector2) -> float:
	var nearest: float = INF
	for rect: Rect2 in REGIONS.values():
		var dx: float = maxf(maxf(rect.position.x - a_lane.x, a_lane.x - rect.end.x), 0.0)
		var dy: float = maxf(maxf(rect.position.y - a_lane.y, a_lane.y - rect.end.y), 0.0)
		nearest = minf(nearest, Vector2(dx, dy).length())
	return nearest


## The ground height at `a_lane`: zero in a region, rising by HILL_SLOPE per unit of distance
## from the nearest, up to HILL_CAP.
func _height_at(a_lane: Vector2) -> float:
	var past_edge: float = region_distance(a_lane)
	if past_edge <= 0.0:
		return 0.0
	var swell: float = 1.0 + HILL_SWELL * DMath.sin(TAU * a_lane.x / HILL_SWELL_WAVELENGTH)
	return minf(past_edge * HILL_SLOPE * swell, HILL_CAP)


## The cells a unit could actually walk, flooded from ROUTE_START's centre through in-play,
## not-steep cells (TerrainGrid.MAX_SLOPE_DIFF, the game's own rule), and the property that
## makes the hills hills:
## - nothing walkable is reached that lies a full cell outside every region (no way over a hill);
## - every region's centre is reached (the route is whole);
## - with ROUTE_GATE walled off, ROUTE_END is not reached (START does not open onto MAIN).
func _verify_route(a_data: TerrainData) -> bool:
	var reached: Dictionary = _flood(a_data, "")
	var strays: int = 0
	for cell: Vector2i in reached:
		if region_distance(_cell_lane(a_data, cell)) >= 1.0:
			strays += 1
	var missing: Array[String] = []
	for name: String in REGIONS:
		if not reached.has(_lane_cell(a_data, (REGIONS[name] as Rect2).get_center())):
			missing.append(name)
	var gated: Dictionary = _flood(a_data, ROUTE_GATE)
	var leaks: bool = gated.has(_lane_cell(a_data, (REGIONS[ROUTE_END] as Rect2).get_center()))
	print(
		(
			(
				"route: %d walkable cells reached, %d of them outside the regions (must be 0); "
				+ "unreached regions %s; %s reachable from %s without %s: %s (must be false)"
			)
			% [reached.size(), strays, missing, ROUTE_END, ROUTE_START, ROUTE_GATE, leaks]
		)
	)
	return strays == 0 and missing.is_empty() and not leaks


## The walkable cells reachable from ROUTE_START, never entering region `a_wall` ("" = none).
func _flood(a_data: TerrainData, a_wall: String) -> Dictionary:
	var start: Vector2i = _lane_cell(a_data, (REGIONS[ROUTE_START] as Rect2).get_center())
	var wall: Rect2 = REGIONS[a_wall] if REGIONS.has(a_wall) else Rect2()
	var seen: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + step
			if seen.has(next) or not a_data.is_cell_in_play(next):
				continue
			if a_data.cell_height_spread(next) > TerrainGrid.MAX_SLOPE_DIFF:
				continue
			if not a_wall.is_empty() and wall.has_point(_cell_lane(a_data, next)):
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## The lane position of a cell's centre.
func _cell_lane(a_data: TerrainData, a_cell: Vector2i) -> Vector2:
	var grid_half: Vector2 = Vector2(a_data.grid_width(), a_data.grid_depth()) * 0.5
	return MissionLane.to_lane(
		Vector3(a_cell.x + 0.5 - grid_half.x, 0.0, a_cell.y + 0.5 - grid_half.y)
	)


## The cell under a lane position.
func _lane_cell(a_data: TerrainData, a_lane: Vector2) -> Vector2i:
	var grid_half: Vector2 = Vector2(a_data.grid_width(), a_data.grid_depth()) * 0.5
	var world: Vector3 = MissionLane.to_world(a_lane.x, a_lane.y)
	return Vector2i(floori(world.x + grid_half.x), floori(world.z + grid_half.y))


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
