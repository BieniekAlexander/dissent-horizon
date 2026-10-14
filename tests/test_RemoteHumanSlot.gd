extends GutTest

## In a networked match each machine plays one seat: its own human slot gets the player's rig, and
## every other human slot is a remote player's — a Bot with its brain off and a fog of its own,
## played by the orders that arrive over the network. A recording names the seat it was played
## from, and its playback plays from the same one.
## gdd/systems/commands/netplay.md §The model.

const HARNESS: String = "res://scenes/scenarios/test/test_kamikaze_cluster.tscn"
const SEED: int = 7
const LOCAL: int = 2
const REMOTE: int = 1
## Ticks a recorded run plays before it is saved.
const RECORD_TICKS: int = 60


func after_each() -> void:
	RTSController.PLAYER_COMMANDER_ID = 0


func test_only_the_local_seat_gets_the_rig() -> void:
	var scenario: Scenario = await _boot(LOCAL)
	assert_eq(RTSController.PLAYER_COMMANDER_ID, LOCAL)
	assert_not_null(scenario.commanders[LOCAL].get_node_or_null("Controller"), "the local rig")
	var remote: Commander = scenario.commanders[REMOTE]
	assert_null(remote.get_node_or_null("Controller"), "no rig for the remote player")
	assert_true(remote is Bot)
	assert_false((remote as Bot).is_ai_controlled(), "its orders come over the network")
	assert_not_null(Fog.for_commander(REMOTE), "the simulation reads its fog for targeting")
	await _tear_down(scenario)


func test_unset_the_first_human_slot_is_local() -> void:
	var scenario: Scenario = await _boot(-1)
	assert_eq(RTSController.PLAYER_COMMANDER_ID, REMOTE, "as a single-machine session always has")
	await _tear_down(scenario)


func test_a_recording_plays_back_from_the_seat_it_was_played_from() -> void:
	var scenario: Scenario = await _boot(LOCAL)
	for frame: int in RECORD_TICKS:
		await get_tree().physics_frame
	var recording: ReplayFile = ReplayFile.from_bytes(scenario.recorder.replay.to_bytes())
	await _tear_down(scenario)
	assert_eq(int(recording.header.get("local_commander_id", -1)), LOCAL)
	var playback: Scenario = await _boot(-1, recording)
	assert_eq(playback.local_commander_id, LOCAL)
	assert_eq(RTSController.PLAYER_COMMANDER_ID, LOCAL)
	await _tear_down(playback)


## The harness with every slot human, as a two-player networked match, played from
## `a_local_commander_id`.
func _boot(a_local_commander_id: int, a_recording: ReplayFile = null) -> Scenario:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	scenario.rng_seed = SEED
	scenario.replay_to_play = a_recording
	var slots: Array[PlayerSlot] = []
	for slot: PlayerSlot in scenario.player_slots:
		# Duplicated, never edited: a scene's slots are sub-resources every instance shares.
		var human: PlayerSlot = slot.duplicate() as PlayerSlot
		human.is_bot = false
		slots.append(human)
	scenario.player_slots = slots
	scenario.local_commander_id = a_local_commander_id
	await get_tree().process_frame
	add_child(scenario)
	return scenario


func _tear_down(a_scenario: Scenario) -> void:
	a_scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false
