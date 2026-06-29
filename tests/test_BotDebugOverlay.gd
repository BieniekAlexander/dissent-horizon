extends GutTest

## Verifies the BotDebugOverlay's two gates and that it actually emits geometry for the
## scout coverage grid. Rendering can't be asserted headlessly, so we check the generated
## ImmediateMesh surface count instead: >0 means markers were drawn this frame.
##
## Boots the scout-coverage TestScenario (a lone bot that scouts), lets the brain build its
## managers + scout grid, then toggles the gates (hold debug_info + the bot-view toggle).

const SCENE: String = "res://scenes/scenarios/test/test_scout_coverage.tscn"

var _scenario: Scenario
var _overlay: BotDebugOverlay


func before_all() -> void:
	gut.error_tracker.disabled = true  # mute Godot 4.7 navmesh bring-up engine noise


func after_all() -> void:
	gut.error_tracker.disabled = false
	Input.action_release("debug_info")
	Fog.active_commander_id = -1


func _boot() -> void:
	_scenario = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(_scenario)
	# Let the navmesh sync and the brain build its managers + scout grid.
	for _i: int in 90:
		await get_tree().physics_frame
	_overlay = _scenario.get_node("BotDebugOverlay") as BotDebugOverlay
	assert_not_null(_overlay, "scenario created a BotDebugOverlay")


func test_overlay_draws_only_when_both_gates_open() -> void:
	await _boot()
	if _overlay == null:
		return
	var mesh: ImmediateMesh = _overlay._mesh

	# Gate the bot-view toggle to the scout bot (commander 1).
	Fog.active_commander_id = 1

	# debug_info NOT held → nothing drawn, even with a bot selected.
	Input.action_release("debug_info")
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn unless debug_info is held")

	# Both gates open → scout markers drawn.
	Input.action_press("debug_info")
	await get_tree().process_frame
	assert_gt(mesh.get_surface_count(), 0, "scout points drawn when held + bot is the active view")

	# Held, but the active view is the player (not a bot) → nothing.
	Fog.active_commander_id = -1
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn when the active view isn't a bot")

	# Held, but the active id isn't a real bot → nothing.
	Fog.active_commander_id = 999
	await get_tree().process_frame
	assert_eq(mesh.get_surface_count(), 0, "nothing drawn for an id that isn't a bot")
