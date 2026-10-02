extends GutTest

## A ScenarioDialog may offer a SECOND choice alongside its acknowledge button — what an
## end-of-scenario dialog uses to let the player leave for the title screen instead of
## staying in a decided match.
##
## The critical property is that BOTH paths resolve the dialog, because the simulation hold
## is bound to `acknowledged`: a secondary that bypassed it would leave the world frozen
## behind whatever the choice led to.

# Any DialogPage will do — the secondary is a property of the ScenarioDialog, not of the
# page it carries. (This named s1's win_dialog.tscn, which no longer exists; the shared
# welcome page is what the other dialog tests use.)
const PAGE := "res://scenes/dialogs/welcome.tscn"


func _dialog(a_secondary: String = "") -> ScenarioDialog:
	var dialog := ScenarioDialog.new(load(PAGE))
	dialog.secondary_text = a_secondary
	return dialog


#region ScenarioDialog
func test_a_dialog_has_no_secondary_by_default() -> void:
	assert_false(_dialog().has_secondary(), "the ordinary dialog is one button")


func test_naming_the_secondary_offers_it() -> void:
	assert_true(_dialog("Return to Main Menu").has_secondary(), "a labelled secondary is offered")


func test_choosing_the_secondary_announces_and_resolves() -> void:
	var dialog := _dialog("Return to Main Menu")
	watch_signals(dialog)

	dialog.choose_secondary()

	assert_signal_emitted(dialog, "secondary_chosen", "the choice is announced")
	assert_signal_emitted(dialog, "acknowledged", "and the dialog resolves, releasing any hold")
	assert_true(dialog.is_acknowledged(), "it is done")


func test_the_secondary_releases_the_simulation_hold() -> void:
	var clock := SimulationClock.new()  # orphan: bookkeeping only, never pauses GUT
	var dialog := _dialog("Return to Main Menu")
	clock.hold(SimulationClock.REASON_DIALOG)
	dialog.acknowledged.connect(clock.release.bind(SimulationClock.REASON_DIALOG))

	dialog.choose_secondary()

	assert_false(clock.is_paused(), "leaving by the secondary button still resumes the world")
	clock.free()


func test_choosing_the_secondary_twice_is_idempotent() -> void:
	var dialog := _dialog("Return to Main Menu")
	dialog.choose_secondary()
	watch_signals(dialog)

	dialog.choose_secondary()

	assert_signal_not_emitted(dialog, "secondary_chosen", "a double click cannot fire it twice")


func test_an_acknowledged_dialog_cannot_then_take_the_secondary() -> void:
	var dialog := _dialog("Return to Main Menu")
	dialog.acknowledge()
	watch_signals(dialog)

	dialog.choose_secondary()

	assert_signal_not_emitted(dialog, "secondary_chosen", "the dialog is already resolved")


#endregion


#region ScenarioDialogView
func _view() -> ScenarioDialogView:
	var view := ScenarioDialogView.new()
	add_child_autofree(view)
	return view


func test_the_view_shows_a_second_button_only_when_offered() -> void:
	var view := _view()

	view._on_dialog_requested(_dialog())
	assert_false(view._secondary_button.visible, "a one-button dialog draws one button")

	view.acknowledge_current()
	view._on_dialog_requested(_dialog("Return to Main Menu"))
	assert_true(view._secondary_button.visible, "a dialog offering a way out draws it")
	assert_eq(view._secondary_button.text, "Return to Main Menu", "with the authored label")


func test_the_view_resolves_and_dequeues_on_the_secondary() -> void:
	var view := _view()
	var dialog := _dialog("Return to Main Menu")
	view._on_dialog_requested(dialog)

	view.choose_secondary_current()

	assert_true(dialog.is_acknowledged(), "the dialog resolved")
	assert_false(view.is_showing(), "and left the queue")
	assert_false(view._secondary_button.visible, "the button does not linger")


func test_the_secondary_is_ignored_on_a_dialog_that_does_not_offer_one() -> void:
	var view := _view()
	var dialog := _dialog()
	view._on_dialog_requested(dialog)

	view.choose_secondary_current()

	assert_false(dialog.is_acknowledged(), "there was no secondary to take")
	assert_true(view.is_showing(), "so the dialog is still up")
#endregion
