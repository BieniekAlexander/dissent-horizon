extends Node

## Writes a fixed review set of generated maps as MAP scenes, with one balance report — open
## one to look it over, or instance it under a Scenario to play it. Interactive generation is
## the editor dock (addons/map_generator); this is the batch form of the same pipeline, both
## over GeneratedMapWriter.
##
## Run as a scene, not with -s, so autoloads exist for the entity scenes it loads:
##   godot --headless --path . res://tools/map_generation/generate_maps.tscn
##
## Output goes to OUTPUT_DIR, which is gitignored: a generated map is reproduced from its seed
## and parameters, never hand-edited (~/.claude/CLAUDE.md §10).

#region Constants
const OUTPUT_DIR: String = "res://scenes/scenarios/generated"
const MAP_COUNT: int = 5
const START_COUNT: int = 2
const FIRST_SEED: int = 2000
## Seeds tried per map before giving up on it; a failed seed is reported, not hidden.
const SEEDS_PER_MAP: int = 20
#endregion


func _ready() -> void:
	_clear_output()
	var writer := GeneratedMapWriter.new()
	var params: MapGenerationParams = writer.default_params(START_COUNT)
	var report := PackedStringArray(["# Generated maps", ""])
	var next_seed: int = FIRST_SEED
	for index: int in MAP_COUNT:
		var map: GeneratedMap = null
		for _try: int in SEEDS_PER_MAP:
			map = MapGenerator.generate(params, next_seed)
			next_seed += 1
			if map.is_valid():
				break
			report.append("- seed %d rejected: %s" % [map.generation_seed, ", ".join(map.errors)])
		if not map.is_valid():
			push_error("generate_maps: no valid map %d in %d seeds" % [index + 1, SEEDS_PER_MAP])
			continue
		var map_name: String = "gen_%02d" % (index + 1)
		writer.write(map, "%s/%s.tscn" % [OUTPUT_DIR, map_name])
		report.append("")
		report.append_array(GeneratedMapWriter.report(map, map_name))
	var file := FileAccess.open(OUTPUT_DIR + "/report.md", FileAccess.WRITE)
	file.store_string("\n".join(report) + "\n")
	file.close()
	print("generate_maps: wrote %s" % OUTPUT_DIR)
	get_tree().quit()


## Empty the review set: every run replaces it whole, so a map from an earlier run is never
## mistaken for one of this run's. The editor dock's draft is left alone.
func _clear_output() -> void:
	var path: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(path)
	for file: String in DirAccess.get_files_at(path):
		if file.begins_with("gen_") or file == "report.md":
			DirAccess.remove_absolute(path.path_join(file))
