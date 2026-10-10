extends GutTest

## THE SKIRMISH LOBBY DRAWS ITS SETUP AND EDITS IT. Play is not pressed: it generates a map
## and swaps the scene.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SkirmishLobby.gd -gexit
##
## Why: gdd/systems/ux/ui/menus.md §Skirmish.

var _lobby: SkirmishLobby


func before_each() -> void:
	_lobby = SkirmishLobby.new()
	add_child_autofree(_lobby)


func _rows() -> GridContainer:
	return _lobby.get_node("Rows") as GridContainer


func test_one_row_per_player() -> void:
	assert_eq(_rows().get_child_count(), SkirmishSetup.MIN_PLAYERS * _rows().columns)
	var count := _lobby.find_child("PlayerCount", true, false) as OptionButton
	count.select(2)
	count.item_selected.emit(2)
	assert_eq(_lobby.setup.player_count(), SkirmishSetup.MIN_PLAYERS + 2)
	await wait_process_frames(1)
	assert_eq(_rows().get_child_count(), (SkirmishSetup.MIN_PLAYERS + 2) * _rows().columns)


func test_only_the_first_slot_has_the_human_box() -> void:
	assert_not_null(_rows().get_node_or_null("HumanSlot"))
	var box := _rows().get_node("HumanSlot") as CheckBox
	box.toggled.emit(false)
	assert_false(_lobby.setup.human_plays_first_slot)


func test_play_is_disabled_when_everyone_is_one_team() -> void:
	var play := _lobby.find_child("Play", true, false) as Button
	assert_false(play.disabled)
	_lobby.setup.set_team(0, 1)
	_lobby.setup.set_team(1, 1)
	_lobby.refresh()
	assert_true(play.disabled)
	assert_ne((_lobby.get_node("Status") as Label).text, "")


func test_picking_a_team_edits_the_setup() -> void:
	var team := _rows().get_node("Team2") as OptionButton
	team.select(3)
	team.item_selected.emit(3)
	assert_eq(_lobby.setup.team_of(1), 3)
