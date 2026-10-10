extends GutTest

## MainMenu turns its authored `scenarios` list into one button per entry, in order. The
## list is data, so adding a mission is a new array row rather than a new node — these guard
## that the row → button mapping stays honest, including the misconfigured cases.
##
## Nothing here PRESSES a button: `open()` calls change_scene_to_packed, which would swap the
## whole tree out from under the running test. The wiring is covered by asserting the labels
## and by calling open() with a deliberately invalid entry.

const SCENE := "res://scenes/menu/main_menu.tscn"
## A real, cheap scene, used where the test needs a PackedScene with a resource_path.
const SOME_SCENE := "res://scenes/interface/help_overlay.tscn"


func _entry(a_title: String, a_scene_path: String = SOME_SCENE) -> ScenarioEntry:
	var entry := ScenarioEntry.new()
	entry.title = a_title
	if not a_scene_path.is_empty():
		entry.scene = load(a_scene_path)
	return entry


## Build a menu with `entries` instead of the authored list. Assigned BEFORE add_child so it
## is in place when _ready builds the buttons.
func _menu(a_entries: Array[ScenarioEntry]) -> MainMenu:
	var menu: MainMenu = load(SCENE).instantiate() as MainMenu
	menu.scenarios = a_entries
	add_child_autofree(menu)
	return menu


#region ScenarioEntry
func test_entry_prefers_its_authored_title() -> void:
	assert_eq(_entry("Prologue").button_text(), "Prologue", "an authored title is used as-is")


func test_entry_falls_back_to_the_scene_file_name() -> void:
	assert_eq(
		_entry("").button_text(),
		"help_overlay",
		"a row with a scene but no title still reads as something"
	)


func test_entry_without_a_scene_is_invalid() -> void:
	assert_false(_entry("Nowhere", "").is_valid(), "no scene means no working button")
	assert_true(_entry("Somewhere").is_valid(), "a scene is all an entry needs to be valid")


#endregion


#region Button construction
func test_one_button_per_entry_in_authored_order() -> void:
	var menu := _menu([_entry("First"), _entry("Second"), _entry("Third")] as Array[ScenarioEntry])

	assert_eq(
		menu.button_labels(),
		["First", "Second", "Third"] as Array[String],
		"buttons follow the authored order"
	)


func test_the_hidden_template_is_not_one_of_the_buttons() -> void:
	var menu := _menu([_entry("Only")] as Array[ScenarioEntry])

	assert_eq(menu.button_labels().size(), 1, "the template does not count as a scenario button")
	assert_false(menu.get_node("%ButtonTemplate").visible, "and it stays hidden")


func test_an_entry_with_no_scene_is_skipped_and_reported() -> void:
	var menu := _menu(
		[_entry("Good"), _entry("Broken", ""), _entry("Also good")] as Array[ScenarioEntry]
	)

	assert_eq(
		menu.button_labels(),
		["Good", "Also good"] as Array[String],
		"the unusable row is dropped rather than becoming a dead button"
	)
	assert_push_error("names no scene", "and the author is told which row is wrong")


func test_an_empty_list_produces_no_buttons_and_warns() -> void:
	var menu := _menu([] as Array[ScenarioEntry])

	assert_eq(menu.button_labels(), [] as Array[String], "nothing authored, nothing offered")
	# GUT files push_warning under "engine" errors; there is no assert_push_warning.
	assert_push_warning("no scenarios authored", "a title screen that goes nowhere says so")


func test_opening_an_invalid_entry_is_refused_rather_than_crashing() -> void:
	var menu := _menu([_entry("Fine")] as Array[ScenarioEntry])

	menu.open(_entry("Broken", ""))
	menu.open(null)

	assert_push_error_count(2, "both bad opens are reported")
	assert_eq(menu.button_labels(), ["Fine"] as Array[String], "and the screen is left alone")


#endregion


#region Pages
func test_the_main_page_leads_everywhere() -> void:
	var menu: MainMenu = _menu([])
	assert_eq(
		menu.main_labels(),
		["Campaign", "Arcade (WIP)", "Skirmish", "Replays", "Options", "Quit"] as Array[String]
	)
	assert_eq(menu.page, MainMenu.Page.MAIN)


func test_arcade_is_greyed_out() -> void:
	assert_true(_menu([]).main_button("Arcade").disabled)


func test_each_entry_opens_its_page_and_back_returns() -> void:
	var menu: MainMenu = _menu([_entry("First")])
	for entry: Array in [
		["Campaign", MainMenu.Page.CAMPAIGN],
		["Skirmish", MainMenu.Page.SKIRMISH],
		["Replays", MainMenu.Page.REPLAYS],
		["Options", MainMenu.Page.OPTIONS],
	]:
		menu.main_button(entry[0]).pressed.emit()
		assert_eq(menu.page, entry[1], entry[0])
		assert_false(menu.main_button(entry[0]).is_visible_in_tree(), "the main page is hidden")
		menu.show_page(MainMenu.Page.MAIN)


func test_the_campaign_lists_the_scenarios() -> void:
	var menu: MainMenu = _menu([_entry("First"), _entry("Second")])
	menu.show_page(MainMenu.Page.CAMPAIGN)
	assert_eq(menu.button_labels(), ["First", "Second"] as Array[String])


func test_quit_asks_to_close_the_application() -> void:
	var menu: MainMenu = _menu([])
	SceneManager.suppress_quit = true
	watch_signals(SceneManager)
	menu.main_button("Quit").pressed.emit()
	SceneManager.suppress_quit = false
	assert_signal_emitted(SceneManager, "quit_requested")


func test_the_lobby_back_button_returns_to_the_main_page() -> void:
	var menu: MainMenu = _menu([])
	menu.show_page(MainMenu.Page.SKIRMISH)
	menu.lobby().back_requested.emit()
	assert_eq(menu.page, MainMenu.Page.MAIN)
#endregion
