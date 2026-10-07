extends GutTest

## The fog boundary, as a check that runs at the earliest stage its inputs are fixed: no bot
## MANAGER may read enemy state from the scene. A manager decides from what the bot's senses
## say it can see or remembers (Bot's fog-limited senses, the CommanderBlackboard), and the
## senses that read the live scene — `Commander.get_enemies_near` is a physics overlap that
## returns fogged and stealthed enemies too — are perception's to wrap, not a manager's to
## call. Three such reads shipped and were found by survey rather than by a test
## (gdd/systems/ai/world-model.md §The fog boundary); this is the test.
##
## ASSERTED OVER FILE TEXT, in the manner of test_SuiteIntegrity: the question is "does this
## identifier appear in this file", which is answerable without loading anything and without a
## scenario, and a leak is a leak whether or not the code path runs in a test.

const MANAGER_DIR: String = "res://scripts/interface/commander"

## The manager files: every bot_*.gd under the commander directory EXCEPT the perception layer
## itself (bot.gd), which is where the fog-limited wrappers of these reads live.
const MANAGER_PREFIX: String = "bot_"

## Calls a manager may not make. Each returns enemy state without the fog gate.
const FORBIDDEN_CALLS: Array[String] = [
	"get_enemies_near(",
	"get_all_enemies(",
	"get_enemy_units(",
	"get_enemy_structures(",
	"nearest_enemy_structure_to_base(",
	'get_nodes_in_group("piece")',
	'get_nodes_in_group(&"piece")',
]


func _manager_scripts() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(MANAGER_DIR)
	assert_not_null(dir, "the commander directory is readable")
	if dir == null:
		return paths
	for file: String in dir.get_files():
		if file.begins_with(MANAGER_PREFIX) and file.ends_with(".gd"):
			paths.append("%s/%s" % [MANAGER_DIR, file])
	return paths


## The code lines of a script, comments stripped: a forbidden name in a comment is prose
## about the rule, not a breach of it.
func _code_lines(a_script_path: String) -> Array[String]:
	var lines: Array[String] = []
	for line: String in FileAccess.get_file_as_string(a_script_path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			lines.append(line)
	return lines


func test_no_manager_reads_enemy_state_from_the_scene() -> void:
	var breaches: Array[String] = []
	for script_path: String in _manager_scripts():
		var number: int = 0
		for line: String in _code_lines(script_path):
			number += 1
			for call: String in FORBIDDEN_CALLS:
				if line.contains(call):
					breaches.append("%s:%d %s" % [script_path.get_file(), number, call])
	assert_eq(
		breaches,
		[] as Array[String],
		"a manager reads enemies only through a fog-limited sense; these read the scene"
	)


func test_the_scan_covers_the_managers() -> void:
	# A ratchet on the scan's own reach: if the managers move, the test must move with them
	# rather than pass over an empty directory.
	assert_true(_manager_scripts().size() >= 10, "the manager files were found")
