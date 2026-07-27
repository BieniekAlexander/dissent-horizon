extends GutTest

## The first time debug mode opens, the piece card shows the faction the player STARTED as
## (gdd/systems/ux/ui/debug-mode.md §The faction dropdown). Driven through the real panel
## scene with a fixture roster and a fixture commander, opened the way the game opens it.

const PANEL_SCENE: String = "res://scenes/interface/debug_panel.tscn"
const PLAYER_ID: int = 1
const OTHER_ID: int = 2


func after_each() -> void:
	DebugMode.configure(false)


func _entry(a_id: String, a_faction: String, a_scene: String) -> Dictionary:
	return {"id": a_id, "label": a_id, "faction": a_faction, "scene": a_scene,
		"is_fixture": false, "producers": [], "tool": ""}


## A commander whose faction starts with `a_scene`, which is what names its faction.
func _commander_starting_with(a_id: int, a_scene: String) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	if a_scene != "":
		var starting := PackedScene.new()
		starting.resource_path = a_scene
		var faction: Faction = autofree(Faction.new())
		faction.starting_units = [starting] as Array[PackedScene]
		commander.faction = faction
	add_child_autofree(commander)
	return commander


## The panel over a two-faction fixture roster, with commander 1 (a blue player) as the seat
## the game started in.
func _panel() -> DebugPanel:
	var panel: DebugPanel = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame  # its deferred start-up, which reads the starting seat
	panel._entries = [
		_entry("soldier", "red", "res://red/soldier.tscn"),
		_entry("tank", "blue", "res://blue/tank.tscn"),
	]
	panel._factions = ["red", "blue"] as Array[String]
	panel._faction_option.clear()
	for faction: String in panel._factions:
		panel._faction_option.add_item(faction)
	panel._faction_option.select(0)
	var scenario: Scenario = autofree(Scenario.new())
	scenario.commanders = [_commander_starting_with(0, ""),
		_commander_starting_with(PLAYER_ID, "res://blue/tank.tscn"),
		_commander_starting_with(OTHER_ID, "res://red/soldier.tscn")]
	panel._scenario = scenario
	panel._starting_player_id = PLAYER_ID
	return panel


func _open_debug_mode() -> void:
	DebugMode.configure(true)
	if not DebugMode.is_active():
		DebugMode.toggle()
	await get_tree().process_frame


func _close_debug_mode() -> void:
	if DebugMode.is_active():
		DebugMode.toggle()
	await get_tree().process_frame


func _shown_faction(a_panel: DebugPanel) -> String:
	return a_panel._factions[a_panel._faction_option.selected]


func test_opening_debug_mode_shows_the_players_starting_faction() -> void:
	var panel: DebugPanel = await _panel()
	assert_eq(_shown_faction(panel), "red", "before opening, the card is wherever it was built")
	await _open_debug_mode()
	assert_eq(_shown_faction(panel), "blue", "opened on the faction the player started as")


func test_a_faction_browsed_since_stays_on_the_next_opening() -> void:
	var panel: DebugPanel = await _panel()
	await _open_debug_mode()
	panel._faction_option.select(0)
	await _close_debug_mode()
	await _open_debug_mode()
	assert_eq(_shown_faction(panel), "red", "chosen once, on the first opening only")


func test_it_is_the_starting_seat_even_after_playing_as_another() -> void:
	# play_as moves who the local player is; the card still follows where the game began.
	var panel: DebugPanel = await _panel()
	RTSController.PLAYER_COMMANDER_ID = OTHER_ID
	await _open_debug_mode()
	RTSController.PLAYER_COMMANDER_ID = 0
	assert_eq(_shown_faction(panel), "blue")
