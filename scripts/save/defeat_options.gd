class_name DefeatOptions
extends HBoxContainer

## What a player who has lost can do next, on the end-of-match summary: start the mission again,
## load the last autosave, or go back to the title screen (Alex, 2026-10-18).
## gdd/systems/commands/saved-games.md §Menus.
##
## Restarting needs a scene file to start from — a lobby-built skirmish has none — and loading
## needs an autosave; a choice that cannot be made is shown greyed, with why.

## The match lost. Set before this enters the tree.
var scenario: Scenario = null
## Where the autosave is looked for. A test points it elsewhere.
var directory: String = SaveGame.DIRECTORY

var restart_button: Button = null
var load_button: Button = null
var menu_button: Button = null


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	restart_button = _button("RestartButton", "Restart Mission", _on_restart)
	var can_restart: bool = scenario != null and not scenario.scene_file_path.is_empty()
	restart_button.disabled = not can_restart
	if not can_restart:
		restart_button.tooltip_text = "This match was built in the lobby: it has no mission to restart."
	load_button = _button("LoadAutosaveButton", "Load Last Autosave", _on_load)
	var has_autosave: bool = FileAccess.file_exists(SaveGame.autosave_path(directory))
	load_button.disabled = not has_autosave
	if not has_autosave:
		load_button.tooltip_text = "There is no autosave."
	menu_button = _button("MainMenuButton", "Main Menu", SceneManager.to_main_menu)


func _button(a_name: String, a_text: String, a_action: Callable) -> Button:
	var button := Button.new()
	button.name = a_name
	button.text = a_text
	button.pressed.connect(a_action)
	add_child(button)
	return button


func _on_restart() -> void:
	SceneManager.restart(scenario)


func _on_load() -> void:
	var refused: String = SceneManager.load_save(SaveGame.autosave_path(directory))
	if not refused.is_empty():
		load_button.disabled = true
		load_button.tooltip_text = refused
