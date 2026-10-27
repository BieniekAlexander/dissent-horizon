extends GutTest

## How to Play: the tutorial library (TutorialLibrary), its reader (HowToPlayView), the Briefing
## tab's objectives (BriefingObjectivesView), and the pause menu that holds them both. The
## library here is a fixture; the shipped one is content.

## Test-owned pages, never the copy a player reads.
const PAGE: PackedScene = preload("res://scenes/harnesses/dialogs/harness_page_a.tscn")
const PAGE_B: PackedScene = preload("res://scenes/harnesses/dialogs/harness_page_b.tscn")

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


## A library of one category holding PAGE only.
func _library() -> TutorialLibrary:
	var library := TutorialLibrary.new()
	var category := TutorialCategory.new()
	category.title = "Basics"
	category.notes = [PAGE]
	library.add_child(category)
	return library


func _reader() -> HowToPlayView:
	var view := HowToPlayView.new()
	view.bind_library(_library())
	add_child_autofree(view)
	return view


func _title(a_page: PackedScene) -> String:
	var page := a_page.instantiate() as DialogPage
	var title: String = page.title
	page.free()
	return title


## A player-facing objective the manager lists as shown.
func _objective(a_description: String, a_details: String = "") -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.scope = GlobalTrigger.ObjectiveScope.PRIMARY
	trigger.description = a_description
	trigger.details = a_details
	add_child_autofree(trigger)
	_manager.global_triggers.append(trigger)
	_manager.objectives_changed.emit()
	return trigger


# --- The library ---------------------------------------------------------------


func test_the_library_knows_its_own_notes_by_file() -> void:
	var library: TutorialLibrary = autofree(_library())
	assert_true(library.has_note(PAGE))
	assert_false(library.has_note(PAGE_B), "a scenario's own note is not the library's")
	assert_false(library.has_note(null))


# --- The reader ----------------------------------------------------------------


func test_the_reader_lists_the_library_by_category() -> void:
	var view := _reader()
	assert_eq(view.entries(), ["Basics", "  " + _title(PAGE)])
	assert_eq(view.selected_note(), PAGE, "opens on the first note")


func test_a_shown_library_note_is_highlighted() -> void:
	var view := _reader()
	view.show_notes_shown([PAGE])
	assert_eq(view.entries()[1], "  %s %s" % [HowToPlayView.SHOWN_MARK, _title(PAGE)])


func test_a_scenarios_own_note_gets_a_category_of_its_own() -> void:
	var view := _reader()
	view.show_notes_shown([PAGE, PAGE_B])
	var entries: Array[String] = view.entries()
	assert_eq(entries[2], HowToPlayView.MISSION_CATEGORY)
	assert_eq(entries[3], "  %s %s" % [HowToPlayView.SHOWN_MARK, _title(PAGE_B)])
	assert_eq(view.selected_note(), PAGE_B, "opens on the newest note shown")


# --- The Briefing tab ----------------------------------------------------------


func test_the_briefing_lists_objectives_with_their_details() -> void:
	var view := BriefingObjectivesView.new()
	add_child_autofree(view)
	view.bind(_manager)
	assert_false(view.has_objectives(), "a skirmish has nothing to brief")
	_objective("Reach the ridge", "Hold {{ world_select }} to pick your units.")
	var done: GlobalTrigger = _objective("Free the captives")
	done.has_fired = true
	var lines: Array[String] = view.lines()
	assert_eq(lines.size(), 2)
	assert_string_starts_with(lines[0], BriefingObjectivesView.OPEN_MARK)
	assert_false(lines[0].contains("{{"), "key placeholders are resolved")
	assert_string_starts_with(lines[1], BriefingObjectivesView.DONE_MARK)


func test_a_finished_objective_is_crossed_out_details_and_all() -> void:
	var view := BriefingObjectivesView.new()
	add_child_autofree(view)
	view.bind(_manager)
	var done: GlobalTrigger = _objective("Free the captives", "Destroy both Compounds.")
	done.has_fired = true
	view.refresh()
	var row: RichTextLabel = view.get_child(0)
	assert_string_starts_with(row.text, "[s]")
	assert_string_ends_with(row.text, "[/s]")
	assert_true(BriefingObjectivesView.is_done(done))
	var failure: GlobalTrigger = _objective("Lose every Warlord")
	failure.scope = GlobalTrigger.ObjectiveScope.FAILURE
	failure.has_fired = true
	assert_false(BriefingObjectivesView.is_done(failure), "a way to lose is never done")


# --- The pause menu ------------------------------------------------------------


func _pause_menu() -> PauseMenu:
	var menu: PauseMenu = load("res://scenes/menu/pause_menu.tscn").instantiate()
	add_child_autofree(menu)
	menu.bind(_manager)
	menu._how_to_play.bind_library(_library())
	return menu


func test_the_menu_opens_on_how_to_play_without_objectives() -> void:
	var menu := _pause_menu()
	menu.open()
	assert_eq(menu.current_tab(), PauseMenu.Tab.HOW_TO_PLAY)
	menu.open_on(PauseMenu.Tab.BRIEFING)
	assert_eq(menu.current_tab(), PauseMenu.Tab.HOW_TO_PLAY, "no Briefing to show")


func test_the_menu_opens_on_the_briefing_with_objectives() -> void:
	var menu := _pause_menu()
	_objective("Reach the ridge")
	menu.open()
	assert_eq(menu.current_tab(), PauseMenu.Tab.BRIEFING)
	assert_true(_manager.simulation_clock.is_paused(), "the game waits while it is open")
	menu.close()
	assert_false(_manager.simulation_clock.is_paused())


func test_the_menu_highlights_the_notes_shown_so_far() -> void:
	var menu := _pause_menu()
	_manager.note_tutorial_shown(PAGE)
	menu.open_on(PauseMenu.Tab.HOW_TO_PLAY)
	assert_eq(menu._how_to_play.entries()[1], "  %s %s" % [HowToPlayView.SHOWN_MARK, _title(PAGE)])
