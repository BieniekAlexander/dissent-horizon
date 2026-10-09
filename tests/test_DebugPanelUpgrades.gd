extends GutTest

## The debug menu's upgrade card (gdd/systems/ux/ui/debug-mode.md §The debug menu): a toggle per
## upgrade of the faction the piece card shows, pressed while the selected player owns it, and
## granting or revoking it when pressed. Fixture upgrades and commanders throughout.

const PANEL_SCENE: String = "res://scenes/interface/debug_panel.tscn"
const PLAYER_ID: int = 1
const RED_ARMOUR: StringName = &"fake_red_armour"
const RED_AIM: StringName = &"fake_red_aim"
const BLUE_SPEED: StringName = &"fake_blue_speed"
const HARDY: StringName = &"fake_hardy"

var _saved_entries: Dictionary
var _saved_player_id: int


func before_each() -> void:
	_saved_entries = UpgradeCatalog._entries.duplicate(true)
	_saved_player_id = RTSController.PLAYER_COMMANDER_ID
	UpgradeCatalog._entries[RED_ARMOUR] = {
		"title": "Armour",
		"faction": "red",
		"modifies": [{"piece": String(HARDY), "hp_factor": 1.25}],
	}
	UpgradeCatalog._entries[RED_AIM] = {"title": "Aim", "faction": "red", "modifies": []}
	UpgradeCatalog._entries[BLUE_SPEED] = {"title": "Speed", "faction": "blue", "modifies": []}


func after_each() -> void:
	UpgradeCatalog._entries = _saved_entries
	RTSController.PLAYER_COMMANDER_ID = _saved_player_id


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


## The panel over two fixture factions, showing "red", with commander 1 as the player.
func _panel() -> DebugPanel:
	var panel: DebugPanel = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	var scenario: Scenario = autofree(Scenario.new())
	scenario.commanders = [_commander(0), _commander(PLAYER_ID)]
	panel._scenario = scenario
	RTSController.PLAYER_COMMANDER_ID = PLAYER_ID
	panel._factions = ["red", "blue"] as Array[String]
	panel._faction_option.clear()
	for faction: String in panel._factions:
		panel._faction_option.add_item(faction)
	panel._faction_option.select(0)
	panel._build_upgrades()
	return panel


func _buttons(a_panel: DebugPanel) -> Array:
	return a_panel._upgrade_list.get_children().filter(
		func(n: Node) -> bool: return not n.is_queued_for_deletion()
	)


func _button(a_panel: DebugPanel, a_id: StringName) -> Button:
	return a_panel._upgrade_list.get_node(String(a_id)) as Button


func test_the_card_lists_the_shown_factions_upgrades_by_title() -> void:
	var panel: DebugPanel = await _panel()
	var titles: Array = _buttons(panel).map(func(b: Button) -> String: return b.text)
	assert_eq(titles, ["Aim", "Armour"])


func test_switching_faction_lists_that_factions_upgrades() -> void:
	var panel: DebugPanel = await _panel()
	panel._faction_option.select(1)
	panel._build_upgrades()
	var ids: Array = _buttons(panel).map(func(b: Button) -> String: return String(b.name))
	assert_eq(ids, [String(BLUE_SPEED)])


func test_pressing_grants_and_pressing_again_revokes() -> void:
	var panel: DebugPanel = await _panel()
	var player: Commander = panel._scenario.commanders[PLAYER_ID]
	var button: Button = _button(panel, RED_ARMOUR)
	button.button_pressed = true
	assert_true(player.has_upgrade(RED_ARMOUR))
	button.button_pressed = false
	assert_false(player.has_upgrade(RED_ARMOUR))


func test_a_toggle_reads_an_upgrade_researched_elsewhere() -> void:
	var panel: DebugPanel = await _panel()
	(panel._scenario.commanders[PLAYER_ID] as Commander).complete_upgrade(RED_AIM)
	panel._sync_upgrade_buttons()
	assert_true(_button(panel, RED_AIM).button_pressed)
	assert_false(_button(panel, RED_ARMOUR).button_pressed)


func test_with_no_player_the_toggles_are_disabled() -> void:
	var panel: DebugPanel = await _panel()
	RTSController.PLAYER_COMMANDER_ID = 0
	panel._sync_upgrade_buttons()
	assert_true(_button(panel, RED_ARMOUR).disabled)


func test_revoking_takes_a_raised_hit_point_maximum_back_down() -> void:
	var commander: Commander = _commander(PLAYER_ID)
	var unit: Actor = FakePieces.make({"hp": 100.0, "frame": Defense.FrameType.MECH})
	unit.id = HARDY
	add_child_autofree(unit)
	unit.ownership.commander = commander
	DebugPanel.set_upgrade(commander, RED_ARMOUR, true)
	assert_almost_eq(unit.defense.hp_max, 125.0, 0.001)
	DebugPanel.set_upgrade(commander, RED_ARMOUR, false)
	assert_almost_eq(unit.defense.hp_max, 100.0, 0.001)
	assert_almost_eq(unit.defense.hp, 100.0, 0.001, "the fraction of health is kept")


func test_revoking_an_unowned_upgrade_changes_nothing() -> void:
	var commander: Commander = _commander(PLAYER_ID)
	watch_signals(commander)
	commander.revoke_upgrade(RED_AIM)
	assert_signal_not_emitted(commander, "upgrades_changed")
