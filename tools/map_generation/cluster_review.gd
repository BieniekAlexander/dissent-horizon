extends Node

## Generates maps and pulls a review set of neutral building clusters out of them: each cluster,
## with the shelter it is built around counted as one of its groupings, is checked against the
## layout rules (map-generation.md §Building layout), drawn as a top-down cell plan, and listed
## with the shot that frames it, so tools/map_generation/cluster_review.sh
## can render it at the game camera's angle.
##
##   godot --headless --path . res://tools/map_generation/cluster_review.tscn -- out=/tmp/clusters
##
## Arguments (after `--`): out= the output directory; count= clusters wanted (default 12);
## seed= the first seed tried (default FIRST_SEED).
##
## Writes, under out: map_NN.tscn per map used, plan_NN.png per cluster, shots.tsv (map scene,
## then the visual_preview shot spec), and rules.md — every rule breach found, or none.

#region Constants
const FIRST_SEED: int = 4000
const DEFAULT_COUNT: int = 12
const START_COUNT: int = 2
const SEEDS_TRIED: int = 40
## Clusters taken from one map, so the review set spans several maps' worth of draws.
const CLUSTERS_PER_MAP: int = 4
## Pixels per cell in a plan.
const PLAN_CELL_PIXELS: int = 12
## Clear cells drawn around a cluster's bounds in its plan and its shot.
const FRAME_MARGIN_CELLS: int = 6
## The game camera's orthographic size; a shot is never framed tighter than this.
const GAME_ZOOM_SIZE: float = 15.0
## Shot size per cell of the cluster's larger extent, margin included: the isometric camera
## shows a footprint's diagonal, so a square fit would clip the corners.
const SHOT_SIZE_PER_CELL: float = 0.8
const PLAN_BACKGROUND: Color = Color(0.93, 0.93, 0.9)
const PLAN_GRID_LINE: Color = Color(0.82, 0.82, 0.78)
const HOST_COLOUR: Color = Color(0.55, 0.55, 0.55)
## One colour per grouping, cycled.
const GROUPING_COLOURS: Array[Color] = [
	Color(0.85, 0.37, 0.25),
	Color(0.24, 0.47, 0.75),
	Color(0.35, 0.65, 0.3),
	Color(0.7, 0.45, 0.75),
	Color(0.85, 0.65, 0.2),
	Color(0.3, 0.7, 0.7),
]
#endregion


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var out: String = String(args.get("out", "user://cluster_review"))
	var wanted: int = int(args.get("count", DEFAULT_COUNT))
	DirAccess.make_dir_recursive_absolute(out)
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(START_COUNT)
	var shots := PackedStringArray()
	var breaches := PackedStringArray()
	var taken: int = 0
	var map_index: int = 0
	var generation_seed: int = int(args.get("seed", FIRST_SEED))
	for _try: int in SEEDS_TRIED:
		if taken >= wanted:
			break
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		generation_seed += 1
		if not map.is_valid():
			continue
		map_index += 1
		var scene: String = out.path_join("map_%02d.tscn" % map_index)
		writer.write(map, scene)
		var grid_half := Vector2(map.terrain.grid_width(), map.terrain.grid_depth()) * 0.5
		var clusters: Array[MapFeature] = map.features_of(MapFeature.Kind.BUILDING_CLUSTER)
		var shelters: Array[MapFeature] = map.features_of(MapFeature.Kind.SHELTER)
		# Clusters built around a shelter first, so the review set always shows some.
		clusters.sort_custom(
			func(a: MapFeature, b: MapFeature) -> bool:
				return _host(a, shelters, params) != null and _host(b, shelters, params) == null
		)
		for cluster: MapFeature in clusters.slice(0, CLUSTERS_PER_MAP):
			if taken >= wanted:
				break
			taken += 1
			var name: String = "cluster_%02d" % taken
			var rects: Array[Rect2i] = cluster.footprints()
			var host: MapFeature = _host(cluster, shelters, params)
			var host_index: int = -1
			if host != null:
				host_index = rects.size()
				rects.append_array(host.footprints())
			var groupings: Array[Array] = _groupings(rects, params)
			breaches.append_array(_breaches(name, rects, groupings, params))
			_plan(rects, groupings, host_index).save_png(out.path_join("plan_%02d.png" % taken))
			var bounds: Rect2i = _bounds(rects).grow(FRAME_MARGIN_CELLS)
			var focus: Vector2 = Vector2(bounds.get_center()) - grid_half
			var size: float = maxf(
				GAME_ZOOM_SIZE, maxi(bounds.size.x, bounds.size.y) * SHOT_SIZE_PER_CELL
			)
			shots.append("%s\t%s:%.1f,%.1f,%.1f" % [scene, name, focus.x, focus.y, size])
			print(
				(
					"cluster_review: %s seed %d — %d buildings in %d groupings, capacity %d%s"
					% [
						name,
						map.generation_seed,
						cluster.placements.size(),
						groupings.size(),
						cluster.value,
						" + host shelter" if host != null else ""
					]
				)
			)
	_write(out.path_join("shots.tsv"), "\n".join(shots) + "\n")
	var rules: String = (
		"# Rule breaches\n\n"
		+ ("None.\n" if breaches.is_empty() else "- " + "\n- ".join(breaches) + "\n")
	)
	_write(out.path_join("rules.md"), rules)
	print("cluster_review: %d clusters, %d rule breaches, wrote %s" % [taken, breaches.size(), out])
	get_tree().quit(0 if breaches.is_empty() else 1)


#region Rules
## The shelter `cluster` is built around: one within the open gap of its buildings. Null if none.
static func _host(
	cluster: MapFeature, shelters: Array[MapFeature], params: MapGenerationParams
) -> MapFeature:
	for shelter: MapFeature in shelters:
		for building: Rect2i in cluster.footprints():
			if (
				BuildingClusterLayout.chebyshev_gap(building, shelter.footprints()[0])
				<= params.cluster_open_gap_cells_max
			):
				return shelter
	return null


## Buildings joined by tight gaps, as index lists: connected components under a gap no wider
## than the grouping maximum. Recomputed from geometry rather than taken from the layout, so
## the check sees what a player would.
static func _groupings(rects: Array[Rect2i], params: MapGenerationParams) -> Array[Array]:
	var seen: Dictionary = {}
	var groupings: Array[Array] = []
	for start: int in rects.size():
		if seen.has(start):
			continue
		var grouping: Array[int] = []
		var frontier: Array[int] = [start]
		seen[start] = true
		while not frontier.is_empty():
			var at: int = frontier.pop_back()
			grouping.append(at)
			for other: int in rects.size():
				if seen.has(other):
					continue
				var gap: int = BuildingClusterLayout.chebyshev_gap(rects[at], rects[other])
				if gap <= params.grouping_gap_cells_max:
					seen[other] = true
					frontier.append(other)
		groupings.append(grouping)
	return groupings


static func _breaches(
	name: String, rects: Array[Rect2i], groupings: Array[Array], params: MapGenerationParams
) -> PackedStringArray:
	var found := PackedStringArray()
	for grouping: Array in groupings:
		if grouping.size() > params.grouping_size_weights.size():
			found.append("%s: a grouping of %d buildings" % [name, grouping.size()])
		for i: int in grouping:
			var is_flush_with_one: bool = grouping.any(
				func(j: int) -> bool:
					return (
						i != j
						and (
							BuildingClusterLayout.chebyshev_gap(rects[i], rects[j])
							<= params.grouping_gap_cells_max
						)
						and BuildingClusterLayout.is_flush(rects[i], rects[j])
					)
			)
			if grouping.size() > 1 and not is_flush_with_one:
				found.append("%s: building %d is flush with none of its grouping" % [name, i])
		# The nearest other grouping must stand within the open maximum.
		var nearest: int = 1 << 30
		for i: int in grouping:
			for j: int in rects.size():
				if not grouping.has(j):
					nearest = mini(nearest, BuildingClusterLayout.chebyshev_gap(rects[i], rects[j]))
		if groupings.size() > 1 and nearest > params.cluster_open_gap_cells_max:
			found.append("%s: a grouping stands %d from the rest" % [name, nearest])
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			var gap: int = BuildingClusterLayout.chebyshev_gap(rects[i], rects[j])
			if gap < 1:
				found.append("%s: buildings %d and %d touch" % [name, i, j])
			var is_same_grouping: bool = _grouping_of(groupings, i).has(j)
			if not is_same_grouping and gap < params.cluster_open_gap_cells_min:
				found.append("%s: buildings %d and %d at gap %d" % [name, i, j, gap])
	return found


static func _grouping_of(groupings: Array[Array], index: int) -> Array:
	for grouping: Array in groupings:
		if grouping.has(index):
			return grouping
	return []


#endregion


#region Plan image
## Top-down: one square per cell, each building filled in its grouping's colour and the host
## shelter, rect `host_index` (-1 for none), in grey.
static func _plan(rects: Array[Rect2i], groupings: Array[Array], host_index: int) -> Image:
	var bounds: Rect2i = _bounds(rects).grow(FRAME_MARGIN_CELLS)
	var image := Image.create(
		bounds.size.x * PLAN_CELL_PIXELS, bounds.size.y * PLAN_CELL_PIXELS, false, Image.FORMAT_RGB8
	)
	image.fill(PLAN_BACKGROUND)
	for x: int in bounds.size.x:
		image.fill_rect(Rect2i(x * PLAN_CELL_PIXELS, 0, 1, image.get_height()), PLAN_GRID_LINE)
	for z: int in bounds.size.y:
		image.fill_rect(Rect2i(0, z * PLAN_CELL_PIXELS, image.get_width(), 1), PLAN_GRID_LINE)
	for g: int in groupings.size():
		var colour: Color = GROUPING_COLOURS[g % GROUPING_COLOURS.size()]
		if groupings[g].has(host_index):
			colour = HOST_COLOUR
		for index: int in groupings[g]:
			var rect: Rect2i = rects[index]
			var pixels := Rect2i(
				(rect.position - bounds.position) * PLAN_CELL_PIXELS, rect.size * PLAN_CELL_PIXELS
			)
			image.fill_rect(pixels, colour.darkened(0.35))
			image.fill_rect(pixels.grow(-2), colour)
	return image


static func _bounds(rects: Array[Rect2i]) -> Rect2i:
	var bounds: Rect2i = rects[0]
	for rect: Rect2i in rects:
		bounds = bounds.merge(rect)
	return bounds


#endregion


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for arg: String in args:
		var eq: int = arg.find("=")
		if eq > 0:
			parsed[arg.substr(0, eq)] = arg.substr(eq + 1)
	return parsed
