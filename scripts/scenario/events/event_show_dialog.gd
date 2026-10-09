@tool
class_name EventShowDialog
extends AbstractEvent

## Pops up a page of copy with an acknowledge button, optionally stopping the world until the
## player clicks it.
##
## The copy lives in a DialogPage SCENE (see scenes/dialogs/), not on this node, so the same
## page can be raised by several triggers and listed in the help book without being written
## out more than once. Point `page` at it and the view brings it into the game when this
## event fires.
##
## The pairing of pause and dialog lives here rather than in the HUD: this event takes the
## SimulationClock hold when it raises the dialog and releases it when the dialog reports
## acknowledged. So the hold is tied to the REQUEST, not to a window — a dialog raised in a
## session with no HUD, or one whose view is torn down mid-scenario, still resolves rather
## than freezing the game forever.
##
## Distinct from EventShowMessage, which is the non-blocking one-liner (it just emits text on
## message_requested and moves on). Use this one when the player is meant to stop and read.
##
## Because it is an ordinary AbstractEvent, it sits under any trigger — including an
## objective, where the natural arrangement is a dialog explaining the NEXT objective as the
## previous one's completion event.

#region Properties
## The DialogPage scene to show.
@export var page: PackedScene

## Hold the simulation while the dialog is up, releasing on acknowledge. This is the tutorial
## default: the player should read the instruction before the world moves on.
@export var pause_simulation: bool = true

## Offer a SECOND button that leaves the scenario for the title screen, alongside the usual
## acknowledge. For end-of-scenario beats: a victory dialog should let the player go, rather
## than stranding them in a match that is already decided — while still letting them stay and
## poke around, which is what the acknowledge button now means on such a dialog.
##
## Off by default, so no tutorial instruction grows a "quit to menu" button by accident.
@export var offer_main_menu: bool = false

## Label for that button. Exported so a scenario can word its own ending.
@export var main_menu_text: String = "Return to Main Menu"
#endregion


#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	if page == null:
		push_warning("EventShowDialog '%s' has no page scene; nothing to show." % name)
		return

	var dialog := ScenarioDialog.new(page)
	if pause_simulation:
		var clock: SimulationClock = a_manager.simulation_clock
		if clock != null:
			clock.hold(SimulationClock.REASON_DIALOG)
			# Bound to the clock rather than to a method on this node, so the hold is released
			# even if this event's subtree is freed while the dialog is still open.
			dialog.acknowledged.connect(clock.release.bind(SimulationClock.REASON_DIALOG))
	if offer_main_menu:
		dialog.secondary_text = main_menu_text
		# Bound straight to the autoload, not to a method on this node: the player may sit on a
		# victory screen indefinitely, and the navigation has to work even if this event's
		# subtree has been freed in the meantime. Same reasoning as the clock binding above.
		# In a playback the recorded choice resolves the dialog but does not leave: the viewer
		# leaves by the pause menu (recording-and-replay.md §Watching).
		if not a_manager.is_playback():
			dialog.secondary_chosen.connect(SceneManager.to_main_menu)
	# Nobody is drawing dialogs in this session — a spectator view, or a headless test
	# scenario. A hold with no window to dismiss would stop the world permanently, so resolve
	# the request instead of emitting it into the void.
	if a_manager.dialog_requested.get_connections().is_empty():
		dialog.acknowledge()
		return
	a_manager.raise_dialog(dialog)
#endregion
