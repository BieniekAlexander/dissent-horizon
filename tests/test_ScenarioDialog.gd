extends GutTest

## Tests for the acknowledge-dialog path: EventShowDialog → ScenarioTriggerManager
## .dialog_requested → ScenarioDialogView, and the simulation hold that rides along with it.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScenarioDialog.gd -gexit
##
## The manager is parented to the GutTest node rather than to a Scenario, which makes it warn
## on _ready; that warning is expected and unrelated to what's under test here.

## Two distinct page scenes, so tests can tell "the right page" from "a page".
## Test-owned pages, never the help copy a player reads (simulation-tests.md §Where the
## harnesses live).
const PAGE: PackedScene = preload("res://scenes/harnesses/dialogs/harness_page_a.tscn")
const PAGE_B: PackedScene = preload("res://scenes/harnesses/dialogs/harness_page_b.tscn")

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	# A dialog left un-acknowledged by a failing assertion would hold the whole suite.
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


func _fire(a_event: EventShowDialog) -> void:
	_manager.add_child(a_event)
	_manager.run_event(a_event, null)


func _make_event(a_pauses: bool = true) -> EventShowDialog:
	var event := EventShowDialog.new()
	event.page = PAGE
	event.pause_simulation = a_pauses
	return event


# --- ScenarioDialog ------------------------------------------------------------


func test_acknowledge_emits_once() -> void:
	var dialog := ScenarioDialog.new(PAGE)
	watch_signals(dialog)
	dialog.acknowledge()
	dialog.acknowledge()
	assert_signal_emit_count(dialog, "acknowledged", 1, "a double click can't resolve twice")
	assert_true(dialog.is_acknowledged())


# --- EventShowDialog -----------------------------------------------------------


func test_event_requests_a_dialog_carrying_its_page() -> void:
	var seen: Array[ScenarioDialog] = []
	_manager.dialog_requested.connect(func(d: ScenarioDialog) -> void: seen.append(d))
	_fire(_make_event())

	assert_eq(seen.size(), 1, "firing the event raises exactly one dialog")
	assert_eq(seen[0].page, PAGE, "the request carries the scene, not a copy of its text")
	assert_true(seen[0].has_page())


func test_an_event_with_no_page_shows_nothing_and_warns() -> void:
	var event := EventShowDialog.new()
	event.name = "Unset"
	event.pause_simulation = true
	_fire(event)
	assert_push_warning("has no page scene")
	assert_false(_manager.simulation_clock.is_paused(), "and takes no hold it can't release")


func test_pausing_dialog_holds_until_acknowledged() -> void:
	var seen: Array[ScenarioDialog] = []
	_manager.dialog_requested.connect(func(d: ScenarioDialog) -> void: seen.append(d))
	_fire(_make_event(true))

	assert_true(_manager.simulation_clock.is_paused(), "the world stops while the dialog is up")
	seen[0].acknowledge()
	assert_false(_manager.simulation_clock.is_paused(), "acknowledging resumes it")


func test_non_pausing_dialog_takes_no_hold() -> void:
	_manager.dialog_requested.connect(func(_d: ScenarioDialog) -> void: pass)
	_fire(_make_event(false))
	assert_false(
		_manager.simulation_clock.is_paused(), "an informational dialog doesn't stop the world"
	)


func test_dialog_with_no_listener_resolves_itself() -> void:
	# Spectator sessions and headless test scenarios draw no dialogs. A hold with no window
	# to dismiss would freeze the game permanently, so the request must resolve immediately.
	_fire(_make_event(true))
	assert_false(
		_manager.simulation_clock.is_paused(),
		"a dialog nobody can draw must not leave the world held"
	)


# --- ScenarioDialogView --------------------------------------------------------


func test_view_instantiates_the_page_it_is_given() -> void:
	var view := _bound_view()
	_fire(_make_event())

	assert_true(view.is_showing(), "the view puts the dialog on screen")
	var page := view.current_page_instance() as DialogPage
	assert_not_null(page, "the page scene is brought into the game")
	assert_eq(page.title, "Harness Page A")


func test_view_queues_dialogs_and_each_holds_separately() -> void:
	var view := _bound_view()
	_fire(_make_event())
	_fire(_make_event())

	assert_eq(view.queued_count(), 2, "two dialogs raised on one frame both survive")
	view.acknowledge_current()
	assert_eq(view.queued_count(), 1, "the first is dismissed")
	assert_true(_manager.simulation_clock.is_paused(), "the second dialog's own hold stands")
	view.acknowledge_current()
	assert_false(view.is_showing(), "the queue empties")
	assert_false(_manager.simulation_clock.is_paused(), "and the world resumes")


func test_view_acknowledge_on_empty_queue_is_harmless() -> void:
	var view := ScenarioDialogView.new()
	add_child_autofree(view)
	view.acknowledge_current()
	assert_false(view.is_showing())


func test_view_ignores_pause_so_its_button_works_while_held() -> void:
	var view := ScenarioDialogView.new()
	add_child_autofree(view)
	assert_eq(view.process_mode, Node.PROCESS_MODE_ALWAYS, "a paused dialog must stay clickable")


## A view already listening to the manager.
func _bound_view() -> ScenarioDialogView:
	var view := ScenarioDialogView.new()
	add_child_autofree(view)
	view.bind(_manager)
	return view


# --- DialogPage ----------------------------------------------------------------


func test_a_page_renders_its_authored_copy() -> void:
	var page: DialogPage = PAGE.instantiate()
	add_child_autofree(page)
	assert_false(page.title.is_empty(), "the scene carries its own heading")
	assert_false(page.body.is_empty(), "and its own copy")
	assert_false(page.acknowledge_text.is_empty(), "and its own button label")


# --- Tutorial notes -----------------------------------------------------------


func test_a_tutorial_note_is_recorded_once() -> void:
	_manager.note_tutorial_shown(PAGE)
	_manager.note_tutorial_shown(PAGE_B)
	_manager.note_tutorial_shown(PAGE)
	assert_eq(_manager.tutorial_notes_shown, [PAGE, PAGE_B], "first-shown order, no repeats")


func test_a_pop_up_is_a_tutorial_note_only_when_marked() -> void:
	_bound_view()
	var plain := _make_event()
	plain.page = PAGE
	_fire(plain)
	assert_eq(_manager.tutorial_notes_shown.size(), 0, "a pop-up is not a note by default")
	var note := _make_event(false)
	note.page = PAGE_B
	note.is_tutorial_note = true
	_fire(note)
	assert_eq(_manager.tutorial_notes_shown, [PAGE_B])


func test_the_corner_button_names_the_tab_it_opens() -> void:
	var view := _bound_view()
	assert_eq(view.menu_button_text(), ScenarioDialogView.HOW_TO_PLAY_BUTTON_TEXT, "no objectives")
	var objective := GlobalTrigger.new()
	objective.scope = GlobalTrigger.ObjectiveScope.PRIMARY
	add_child_autofree(objective)
	_manager.global_triggers.append(objective)
	assert_eq(view.menu_button_text(), ScenarioDialogView.BRIEFING_BUTTON_TEXT)


# --- Window sizing --------------------------------------------------------------


## A page built in code with `line_count` lines of body copy.
func _sized_page(a_line_count: int) -> DialogPage:
	var page := DialogPage.new()
	page.title = "Sized"
	var lines: PackedStringArray = []
	for i: int in a_line_count:
		lines.append("Line %d of the body copy." % i)
	page.body = "\n".join(lines)
	return page


func test_a_page_is_a_container_so_its_height_reaches_the_window() -> void:
	# The whole mechanism. A plain Control reports only its own custom_minimum_size, so the
	# body's wrapped height never reached the panel and the window had to guess a fixed
	# height. A container derives its minimum size from its children.
	var page := _sized_page(1)
	add_child_autofree(page)
	assert_true(page is Container, "the page stacks its own children and reports their size")
	assert_gt(page.get_combined_minimum_size().y, 0.0, "and claims real height")


func test_more_copy_asks_for_more_height() -> void:
	var short_page := _sized_page(1)
	var long_page := _sized_page(12)
	add_child_autofree(short_page)
	add_child_autofree(long_page)
	assert_gt(
		long_page.get_combined_minimum_size().y,
		short_page.get_combined_minimum_size().y,
		"the window stretches to the text rather than to a constant"
	)


func test_width_comes_from_the_page_not_the_window() -> void:
	# Height follows the copy; width stays the authored content_width, so the window doesn't
	# reflow between beats.
	var page := _sized_page(3)
	page.content_width = 480.0
	add_child_autofree(page)
	assert_almost_eq(page.get_combined_minimum_size().x, 480.0, 1.0)


func test_an_over_long_page_scrolls_instead_of_growing_off_screen() -> void:
	# Stretch-to-fit with no ceiling is worse than a fixed height: a long enough page pushes
	# the acknowledge button off the bottom, and a dialog that holds the simulation and can't
	# be dismissed is unrecoverable.
	var view := _bound_view()
	var page := _sized_page(200)
	view._clear_page()
	view._page_frame.add_child(page)
	view._fit_page_height()

	var screen_height: float = view.get_viewport().get_visible_rect().size.y
	var ceiling: float = screen_height * ScenarioDialogView.MAX_PAGE_HEIGHT_RATIO
	assert_gt(page.get_combined_minimum_size().y, ceiling, "the page really is oversized")
	assert_almost_eq(
		view._page_frame.custom_minimum_size.y,
		ceiling,
		1.0,
		"and the page area is clamped to the ceiling"
	)


func test_a_page_that_fits_is_not_clamped() -> void:
	var view := _bound_view()
	var page := _sized_page(2)
	view._clear_page()
	view._page_frame.add_child(page)
	view._fit_page_height()
	assert_almost_eq(
		view._page_frame.custom_minimum_size.y,
		page.get_combined_minimum_size().y,
		1.0,
		"a short page gets exactly the height it asked for"
	)
