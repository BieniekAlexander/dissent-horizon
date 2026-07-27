extends GutTest

## Every PIECE ID a scenario scene names must be a real one.
##
## A trigger's `structure_type` / `unit_type` is a bare StringName in a .tscn: nothing loads
## it, nothing type-checks it, and a piece rename leaves it pointing at a name that no longer
## exists. The condition then evaluates against zero matches FOREVER and the scenario simply
## stops progressing, with no error anywhere — s3's "Make a mine" objective sat on
## `&"mine"` after the piece became `nt_extractor` and could never be completed, which blocked
## every trigger chained behind it.
##
## The inverted comparisons are worse than a stuck objective: `ConditionUnitCount` with
## EXACTLY 0 is how "your sapper must survive" is written, so a stale id makes the count
## permanently zero and fires the DEFEAT immediately.
##
## Asserted over FILE TEXT rather than by loading the scenes, for the same reason
## test_SuiteIntegrity works that way: these scenes are enormous and instantiating one drags
## in a map, a navmesh and every entity in it.

const SCENES_DIR: String = "res://scenes"

## The trigger properties that hold a piece id, as they appear in a .tscn line. Each is an
## `@export var ...: StringName` on a Condition subclass (see scripts/scenario/conditions).
const ID_PROPERTIES: Array[String] = ["structure_type", "unit_type"]


func _scene_paths(a_dir: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(a_dir)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			found.append("%s/%s" % [a_dir, file])
	for sub: String in dir.get_directories():
		found.append_array(_scene_paths("%s/%s" % [a_dir, sub]))
	return found


## Every piece id the file names, as "<property> = &\"<id>\"" lines. An EMPTY id is the
## documented "any piece" wildcard on all of these properties, so it is skipped rather than
## reported.
func _referenced_ids(a_scene_path: String) -> Array[String]:
	var found: Array[String] = []
	var pattern: String = "^(%s) = &\"([^\"]*)\"$" % "|".join(ID_PROPERTIES)
	var re := RegEx.create_from_string(pattern)
	for line: String in FileAccess.get_file_as_string(a_scene_path).split("\n"):
		var m: RegExMatch = re.search(line.strip_edges())
		if m != null and m.get_string(2) != "":
			found.append(m.get_string(2))
	return found


func _known_ids() -> Dictionary:
	var known: Dictionary = {}
	for id: StringName in EntityIds.new().get_script().get_script_constant_map().values():
		known[String(id)] = true
	return known


func test_every_piece_id_named_in_a_scene_exists() -> void:
	var known: Dictionary = _known_ids()
	assert_gt(known.size(), 0, "guards the fixture: EntityIds has constants to check against")
	var unknown: Array[String] = []
	var checked: int = 0
	for scene_path: String in _scene_paths(SCENES_DIR):
		for id: String in _referenced_ids(scene_path):
			checked += 1
			if not known.has(id):
				unknown.append("%s -> %s" % [scene_path.get_file(), id])
	assert_gt(checked, 0, "guards the fixture: some scene names a piece id")
	assert_eq(unknown, [] as Array[String],
		"a stale id silently freezes the trigger that holds it")
