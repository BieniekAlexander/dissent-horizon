extends GutTest

## Headless runner for the editor-authored TestScenario scenes (scenes/scenarios/test/).
##
## This is the only GDScript "test" for bot scenarios — the scenarios themselves are data,
## authored in the editor. Each one boots the real game and self-evaluates its
## TestExpectations; this runner just drives physics frames until the scenario finishes,
## then asserts every expectation passed (surfacing each as its own assertion so a failure
## names the exact check that broke).
##
## To add a scenario: build a TestScenario scene in the editor and add its path to SCENES.
##
## Run:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotTestScenarios.gd

const SCENES: Array[String] = [
	"res://scenes/scenarios/test/test_kamikaze_cluster.tscn",
	"res://scenes/scenarios/test/test_kamikaze_no_cluster.tscn",
	"res://scenes/scenarios/test/test_scout_coverage.tscn",
]


func test_kamikaze_cluster_scenario() -> void:
	await _run_scenario(SCENES[0])


func test_kamikaze_no_cluster_scenario() -> void:
	await _run_scenario(SCENES[1])


func test_scout_coverage_scenario() -> void:
	await _run_scenario(SCENES[2])


## Instantiate a TestScenario scene, run it to completion, and assert every expectation
## passed. Engine error tracking is muted for the run: booting a live Map on Godot 4.7
## logs benign NavigationServer "before first synchronization" noise while the nav map
## first syncs. The scenario's own pass/fail (its expectations) is what's under test here.
func _run_scenario(path: String) -> void:
	var packed: PackedScene = load(path)
	assert_not_null(packed, "scenario scene loads: %s" % path)
	if packed == null:
		return

	gut.error_tracker.disabled = true
	var scenario := packed.instantiate() as TestScenario
	assert_not_null(scenario, "scene root is a TestScenario: %s" % path)
	if scenario == null:
		gut.error_tracker.disabled = false
		return
	add_child_autofree(scenario)

	var frame_cap: int = scenario.max_ticks + 600
	var frames: int = 0
	while not scenario.is_finished() and frames < frame_cap:
		await get_tree().physics_frame
		frames += 1
	gut.error_tracker.disabled = false

	assert_true(scenario.is_finished(),
		"%s resolved within %d frames" % [path.get_file(), frame_cap])

	for result: Dictionary in scenario._build_results():
		assert_true(result["passed"],
			"%s — %s (%s)" % [
				path.get_file(),
				result["description"],
				"met at tick %d" % result["met_tick"] if result["passed"] else "not met",
			])
