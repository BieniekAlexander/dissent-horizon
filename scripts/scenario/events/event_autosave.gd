@tool
class_name EventAutosave
extends AbstractEvent

## Autosaves the match: writes the ONE autosave (SaveGame.AUTOSAVE_NAME), overwriting the last,
## at the start of the next tick — a trigger fires mid-tick, and a save is taken between ticks
## (Scenario.request_save). A player who wants to keep an autosave renames the file.
## gdd/systems/commands/saved-games.md §Autosaves.
##
## Saving costs no more than writing the match's order log, so nothing is held for it. Skipped
## while a save is still being re-simulated, in a replay and anywhere SaveGame refuses a save.
## Nothing is written in a headless run (the suite, self-play) unless `directory` points
## somewhere else, or it would overwrite a player's autosave.

## Where the autosave is written. A test points it elsewhere.
static var directory: String = SaveGame.DIRECTORY


func execute(a_manager: ScenarioTriggerManager) -> void:
	var scenario: Scenario = a_manager.scenario
	if scenario == null:
		return
	if directory == SaveGame.DIRECTORY and DisplayServer.get_name() == "headless":
		return
	scenario.request_save(SaveGame.autosave_path(directory))
