extends GutTest

## THE PLAYER'S SAVED OPTIONS.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_GameSettings.gd -gexit
##
## Why: gdd/systems/ux/ui/menus.md §Options.

const SETTINGS: String = "user://test_game_settings.cfg"


func before_each() -> void:
	GameSettings.path = SETTINGS
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.reset()


func after_each() -> void:
	DirAccess.remove_absolute(SETTINGS)
	GameSettings.path = GameSettings.PATH
	GameSettings.reset()


func test_the_jump_scope_defaults_to_negative_alerts() -> void:
	assert_eq(GameSettings.alert_jump_scope(), GameSettings.AlertJumpScope.NEGATIVE)


func test_a_choice_survives_a_restart() -> void:
	GameSettings.set_alert_jump_scope(GameSettings.AlertJumpScope.ALL)
	GameSettings.reset()
	assert_eq(GameSettings.alert_jump_scope(), GameSettings.AlertJumpScope.ALL)


func test_an_unknown_saved_value_falls_back_to_the_default() -> void:
	var file := ConfigFile.new()
	file.set_value(GameSettings.SECTION_ALERTS, GameSettings.KEY_JUMP_SCOPE, "SOMETIMES")
	file.save(SETTINGS)
	assert_eq(GameSettings.alert_jump_scope(), GameSettings.AlertJumpScope.NEGATIVE)


func test_attacks_are_negative_and_completions_are_not() -> void:
	assert_true(AlertCatalog.is_negative(AlertCatalog.Type.UNITS_ATTACKED))
	assert_true(AlertCatalog.is_negative(AlertCatalog.Type.COMMAND_CENTRE_ATTACKED))
	assert_false(AlertCatalog.is_negative(AlertCatalog.Type.UNIT_READY))
	assert_false(AlertCatalog.is_negative(AlertCatalog.Type.ABILITY_CHARGED))
