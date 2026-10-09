extends GutTest

## Playing as another commander (Scenario.play_as), and as nobody (Scenario.spectate), against a
## booted skirmish: the scenario is the HARNESS, and nothing here depends on what it fields —
## only that it has two slots.

const SCENE: String = "res://scenes/scenarios/skirmish.tscn"
## Frames for the opening force to deploy and the HUD to bind.
const BOOT_FRAMES: int = 60


func before_all() -> void:
	gut.error_tracker.disabled = true  # the boot's own engine and content noise


func after_all() -> void:
	gut.error_tracker.disabled = false
	Fog.active_commander_id = -1


## The harness, booted with someone played: commander 1 is attached if the scene seats nobody,
## which is itself attaching from a spectator session.
func _boot() -> Scenario:
	var scenario: Scenario = (load(SCENE) as PackedScene).instantiate() as Scenario
	add_child_autofree(scenario)
	for _i: int in BOOT_FRAMES:
		await get_tree().physics_frame
	if scenario.local_player() == null:
		assert_true(scenario.play_as(1), "a spectator session attaches")
		await get_tree().physics_frame
	return scenario


func test_swapping_rebinds_the_hud_and_hands_the_old_slot_to_its_bot() -> void:
	var scenario: Scenario = await _boot()
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


## Detaching makes the match a spectator one: the slot goes to its bot, the HUD turns
## look-only with the spectator panel, and the view stays on the commander just left.
## Attaching again is play_as from nobody, and gives every one of those back.
func test_detaching_spectates_and_attaching_plays_again() -> void:
	var scenario: Scenario = await _boot()
	var controller: RTSController = scenario.find_children("*", "RTSController", true, false)[0]
	var first: int = RTSController.PLAYER_COMMANDER_ID
	var other: int = 2 if first == 1 else 1

	assert_true(scenario.spectate(), "the player detaches")
	assert_false(scenario.spectate(), "and cannot detach twice")
	await get_tree().physics_frame
	assert_null(scenario.local_player(), "nobody is played")
	assert_true(controller.is_look_only, "the HUD turns look-only")
	assert_null(controller._commander(), "and drives no commander")
	assert_not_null(controller.get_node_or_null("SpectatorPanel"), "the spectator's panel")
	assert_false((controller.get_node("EnergyBar") as Control).visible, "no commander's means")
	assert_not_null(scenario.get_node_or_null("SpectatorHUD"), "the spectator's labels")
	assert_eq(Fog.active_commander_id, first, "still watching the commander just left")
	assert_true((scenario.commanders[first] as Bot).is_ai_controlled(), "its bot plays it")

	assert_true(scenario.play_as(other), "attaching to another commander")
	await get_tree().physics_frame
	assert_false(controller.is_look_only, "the HUD is a player's again")
	assert_eq(controller._commander(), scenario.commanders[other])
	assert_null(controller.get_node_or_null("SpectatorPanel"), "the panel is gone")
	assert_true((controller.get_node("ProductionSlot") as Control).visible, "the rail is back")
	assert_null(scenario.get_node_or_null("SpectatorHUD"), "so are the spectator's labels")
	assert_eq(Fog.get_active_fog().viewer_commander_id(), other, "the player's own view")
	assert_false((scenario.commanders[other] as Bot).is_ai_controlled(), "its bot is put down")
	RTSController.PLAYER_COMMANDER_ID = first


## The spectator's fog toggle lifts the fog over the view, and goes with the panel: a player
## attached again sees their own fog.
func test_the_spectators_fog_setting_does_not_outlive_spectating() -> void:
	var scenario: Scenario = await _boot()
	var controller: RTSController = scenario.find_children("*", "RTSController", true, false)[0]
	var first: int = RTSController.PLAYER_COMMANDER_ID
	scenario.spectate()
	var panel: SpectatorPanel = controller.get_node("SpectatorPanel") as SpectatorPanel
	panel.set_fog_shown(false)
	assert_true(Fog.is_lifted())
	scenario.play_as(first)
	await get_tree().process_frame
	assert_false(Fog.is_lifted(), "the player's fog is back")
	RTSController.PLAYER_COMMANDER_ID = first
