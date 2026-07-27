extends GutTest

## The importer DERIVES a piece's structural groups ("piece", "unit", "fixture", "structure")
## and writes them on the piece's own scene. A scene that PLACES the piece must not store them
## on its instance: Godot unions an instance's stored groups with its scene's, so a stale copy
## outlives any change to the rule — which is how the shelter and extraction site would have
## stayed in "structure" after it came to mean a COMMANDABLE fixture (piece-vocabulary.md).
## Authored groups ("extraction_site", "remaining_camps") are unaffected.
##
## Asserted over scene TEXT, like test_EntitySceneHierarchy: a stored group is exactly what an
## instantiated scene cannot show you, because it resolves to the union.

const SpecSchema := preload("res://tools/spec_import/schema.gd")
const SCENE_ROOT: String = "res://scenes"


func test_a_placed_instance_carrying_a_derived_group_is_found() -> void:
	var text: String = "\n".join([
		'[node name="Site" parent="." groups=["extraction_site", "structure"] instance=ExtResource("1")]',
		'[node name="Camp" parent="." groups=["remaining_camps"] instance=ExtResource("2")]',
		'[node name="Root" type="CharacterBody3D" groups=["piece", "structure"]]',
	])
	assert_eq(_derived_group_lines(text), [1] as Array[int],
		"only the instance line, and only for a derived group — a piece's own root is its scene's")


func test_no_scene_stores_a_derived_group_on_a_placed_instance() -> void:
	var offenders: Array[String] = []
	for path: String in _scenes_under(SCENE_ROOT):
		for line_number: int in _derived_group_lines(FileAccess.get_file_as_string(path)):
			offenders.append("%s:%d" % [path, line_number])
	assert_eq(offenders, [] as Array[String],
		"remove the derived groups from these instances; the piece scene supplies them")


## Line numbers (1-based) of instance nodes in `a_text` that store a derived group.
func _derived_group_lines(a_text: String) -> Array[int]:
	var found: Array[int] = []
	var lines: PackedStringArray = a_text.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		if not line.begins_with("[node ") or not line.contains("instance="):
			continue
		var at: int = line.find("groups=[")
		if at < 0:
			continue
		var groups: String = line.substr(at, line.find("]", at) - at)
		if SpecSchema.DERIVED_GROUPS.any(func(g: String) -> bool:
				return groups.contains('"%s"' % g)):
			found.append(i + 1)
	return found


func _scenes_under(a_dir: String) -> Array[String]:
	var found: Array[String] = []
	for entry: String in DirAccess.get_directories_at(a_dir):
		found.append_array(_scenes_under("%s/%s" % [a_dir, entry]))
	for entry: String in DirAccess.get_files_at(a_dir):
		if entry.ends_with(".tscn"):
			found.append("%s/%s" % [a_dir, entry])
	return found
