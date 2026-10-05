extends Node

## Step 1 of the dominion-rate analysis
## (gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md): generate a fixed set of
## 2-player maps with the CURRENT generation parameters, write each as a map scene, and export
## what the analysis model needs as JSON — starts, shelters, extraction sites, ponds, and the
## walkable-cell grid as the game itself computes it.
##
## Run as a scene (autoloads must exist for the entity scenes the writer loads):
##   godot --headless --path . res://tools/dominion_analysis/export_maps.tscn
##
## Output: OUTPUT_DIR (gitignored map scenes) and JSON_DIR (gitignored JSON). Both are derived from
## the seeds and the parameters and are reproduced by running this again, never hand-edited.

#region Constants
const OUTPUT_DIR: String = "res://scenes/scenarios/generated/dominion"
const JSON_DIR: String = "res://tools/dominion_analysis/out/maps"
const MAP_COUNT: int = 10
const START_COUNT: int = 2
## Its own seed range, apart from generate_maps' review set (2000+), so the two never collide.
const FIRST_SEED: int = 3000
const SEEDS_PER_MAP: int = 20
## Physics frames to let a loaded map settle: its terrain grid, blocked and submerged masks, and
## the deferred registration of its neutral structures.
const SETTLE_FRAMES: int = 6
#endregion


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(JSON_DIR))
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(START_COUNT)
	var next_seed: int = FIRST_SEED
	var summary: Array = []
	for index: int in MAP_COUNT:
		var generated: GeneratedMap = null
		for _try: int in SEEDS_PER_MAP:
			generated = MapGenerator.generate(params, next_seed)
			next_seed += 1
			if generated.is_valid():
				break
			print("seed %d rejected: %s" % [generated.generation_seed, ", ".join(generated.errors)])
		if not generated.is_valid():
			push_error("export_maps: no valid map %d in %d seeds" % [index + 1, SEEDS_PER_MAP])
			continue
		var map_name: String = "dom_%02d" % (index + 1)
		var scene_path: String = "%s/%s.tscn" % [OUTPUT_DIR, map_name]
		if writer.write(generated, scene_path) != OK:
			push_error("export_maps: could not write %s" % scene_path)
			continue
		var data: Dictionary = await _export(generated, scene_path, params)
		data["name"] = map_name
		var file := FileAccess.open("%s/%s.json" % [JSON_DIR, map_name], FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		summary.append(
			"%s seed=%d grid=%dx%d shelters=%d sites=%d ponds=%d walkable=%d"
			% [
				map_name,
				generated.generation_seed,
				data.grid_w,
				data.grid_d,
				data.shelters.size(),
				data.sites.size(),
				data.ponds.size(),
				data.walkable_count
			]
		)
	for line: String in summary:
		print(line)
	get_tree().quit()


## Everything the model reads off one map. Positions are continuous CELL coordinates (cell
## (x, z) spans [x, x+1) × [z, z+1)), the generator's own frame; the walkable grid is the loaded
## Map's TerrainGrid with neutral structures registered, read through Map.world_to_grid so the two
## frames are checked against each other rather than assumed equal.
func _export(
	a_map: GeneratedMap, a_scene_path: String, a_params: MapGenerationParams
) -> Dictionary:
	var map := (load(a_scene_path) as PackedScene).instantiate() as Map
	add_child(map)
	for _i: int in SETTLE_FRAMES:
		await get_tree().physics_frame
	var grid: TerrainGrid = map.terrain_grid
	var w: int = grid.grid_width()
	var d: int = grid.grid_depth()
	var rows: PackedStringArray = []
	var walkable_count: int = 0
	for z: int in d:
		var row := PackedByteArray()
		row.resize(w)
		for x: int in w:
			var ok: bool = grid.is_passable(Vector2i(x, z))
			row[x] = 49 if ok else 48  # "1" / "0"
			walkable_count += 1 if ok else 0
		rows.append(row.get_string_from_ascii())
	var data: Dictionary = {
		"seed": a_map.generation_seed,
		"grid_w": w,
		"grid_d": d,
		"play_cells": a_map.play_cell_count,
		"walkable_count": walkable_count,
		"walkable": rows,
		"starts": [],
		"shelters": [],
		"sites": [],
		"ponds": [],
		"shelter_band":
		[a_params.shelter_start_band_min_cells, a_params.shelter_start_band_max_cells],
		"frame_check": [],
	}
	for start: MapStart in a_map.starts:
		data.starts.append([start.position.x, start.position.y])
	for feature: MapFeature in a_map.features:
		match feature.kind:
			MapFeature.Kind.SHELTER:
				data.shelters.append([feature.center.x, feature.center.y])
			MapFeature.Kind.SITE_CLUSTER:
				var cluster: int = data.sites.size()
				for placement: Dictionary in feature.placements:
					var piece: MapPiece = placement.piece
					var c: Vector2 = Vector2(placement.origin) + Vector2(piece.footprint) * 0.5
					data.sites.append({"pos": [c.x, c.y], "cluster": cluster})
			MapFeature.Kind.POND:
				data.ponds.append(
					{
						"center": [feature.center.x, feature.center.y],
						"cells": feature.pond_cells.size(),
						"charge": feature.pond_charge,
					}
				)
	# Frame check: the loaded map's grid cell under each shelter must be the generator's own
	# cell for that shelter's centre, or the two frames disagree. (Outside a Scenario the neutral
	# structures never register on the grid, so their footprints read as walkable here; the
	# model blocks nothing for them — a few cells per structure.)
	var generated_cells: Array = []
	for feature: MapFeature in a_map.features_of(MapFeature.Kind.SHELTER):
		generated_cells.append(Vector2i(feature.center.floor()))
	for node: Node in map.find_children("*", "", true, false):
		var piece := node as Node3D
		if piece != null and piece.has_node("Shelter"):
			var cell: Vector2i = map.world_to_grid(VU.in_xz(piece.global_position))
			data.frame_check.append([cell.x, cell.y, generated_cells.has(cell)])
	map.queue_free()
	await get_tree().physics_frame
	return data
