extends GutTest

## Playing as another commander (Scenario.play_as) against a booted skirmish: the scenario is
## the HARNESS, and nothing here depends on what it fields — only that it has a human slot
## and a second one.

const SCENE: String = "res://scenes/scenarios/skirmish.tscn"
## Frames for the opening force to deploy and the HUD to bind.
const BOOT_FRAMES: int = 60


func before_all() -> void:
	gut.error_tracker.disabled = true  # the boot's own engine and content noise


func after_all() -> void:
	gut.error_tracker.disabled = false
	Fog.active_commander_id = -1


func test_swapping_rebinds_the_hud_and_hands_the_old_slot_to_its_bot() -> void:
	var scenario: Scenario = (load(SCENE) as PackedScene).instantiate() as Scenario
	add_child_autofree(scenario)
	for _i: int in BOOT_FRAMES:
		await get_tree().physics_frame
	var controller: RTSController = scenario.find_children("*", "RTSController", true, false)[0]
	var first: int = RTSController.PLAYER_COMMANDER_ID
	var other: int = 2 if first == 1 else 1

	assert_true(scenario.play_as(other), "the swap happens")
	await get_tree().physics_frame

	assert_eq(controller._commander(), scenario.commanders[other], "the controller follows")
	assert_eq(controller._production_rail.commander, scenario.commanders[other], "so does the rail")
	assert_eq(Fog.get_active_fog().viewer_commander_id(), other, "the new commander's fog shows")
	assert_true((scenario.commanders[first] as Bot).is_ai_controlled(), "the old slot is its bot's")
	assert_false((scenario.commanders[other] as Bot).is_ai_controlled(), "the new one is not")
	RTSController.PLAYER_COMMANDER_ID = first
