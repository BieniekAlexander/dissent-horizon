extends GutTest

## Tests for InputPrompt — {{ action }} placeholders in player-facing copy resolving to
## whatever the InputMap has that action bound to.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_InputPrompt.gd -gexit
##
## Bindings come from project.godot, so these assert on the SHAPE of the result rather than on
## exact key names wherever rebinding would otherwise break the test. The two that do pin text
## use mouse buttons, whose names are stable across platforms — unlike keyboard modifiers,
## where macOS reports Alt as "Option".

const ACTION_LMB: StringName = &"world_select"
const ACTION_RMB: StringName = &"command_issue"
# A physically-mapped keyboard action. It has to be a real INPUT action rather than a grid
# command: grid commands stopped being actions when hotkeys became positional (the cell
# carries the key), so `command_attack_move` resolves through CommandGrid now and would not
# exercise action_text at all.
const ACTION_KEY: StringName = &"card_toggle_family"


func test_a_placeholder_becomes_the_bound_button() -> void:
	assert_eq(
		InputPrompt.format("Hold and drag {{ world_select }} to select."),
		"Hold and drag Left Mouse Button to select."
	)


func test_whitespace_inside_the_braces_is_tolerated() -> void:
	# String.format would match exactly one spelling and silently leave the others on screen;
	# authors write both.
	var expected: String = "Left Mouse Button"
	assert_eq(InputPrompt.format("{{world_select}}"), expected, "no spaces")
	assert_eq(InputPrompt.format("{{ world_select }}"), expected, "spaces")
	assert_eq(InputPrompt.format("{{   world_select   }}"), expected, "lots")


func test_several_placeholders_in_one_string() -> void:
	var out: String = InputPrompt.format("{{ command_issue }} then {{ world_select }}")
	assert_eq(out, "Right Mouse Button then Left Mouse Button")


func test_the_same_placeholder_twice() -> void:
	var out: String = InputPrompt.format("{{ command_issue }} and {{ command_issue }}")
	assert_eq(out, "Right Mouse Button and Right Mouse Button")


func test_text_without_placeholders_is_untouched() -> void:
	var plain: String = "The road is open, commander."
	assert_eq(InputPrompt.format(plain), plain)
	assert_eq(InputPrompt.format(""), "", "and an empty string is fine")


func test_substitution_adds_no_markup_of_its_own() -> void:
	# A straight name-for-name swap. Styling is the author's business: a page that wants the
	# key to stand out writes the markup around the placeholder itself.
	assert_eq(InputPrompt.format("Drag {{ world_select }} now."), "Drag Left Mouse Button now.")


func test_author_supplied_markup_survives_around_a_placeholder() -> void:
	assert_eq(
		InputPrompt.format("Drag [b]{{ world_select }}[/b] now."),
		"Drag [b]Left Mouse Button[/b] now."
	)


func test_an_unknown_action_is_left_visible_and_reported() -> void:
	# Left as authored — braces and all — so it reads as the bug it is rather than as a
	# confusing bare word in the middle of a sentence.
	var out: String = InputPrompt.format("Press {{ no_such_action }}.")
	assert_eq(out, "Press {{ no_such_action }}.")
	assert_push_warning("'no_such_action' is neither an InputMap action nor a command in the grid")


## A placeholder may name a grid COMMAND instead of an action, and resolves through the
## cell that command occupies — which is the only way copy can keep naming verbs now that
## hotkeys are positional. See InputPrompt.resolve_action.
func test_a_grid_command_resolves_through_its_cell() -> void:
	assert_false(InputMap.has_action(&"command_attack_move"), "it is not an action")
	assert_eq(InputPrompt.format("Press {{ command_attack_move }}."), "Press A.")


func test_a_keyboard_binding_drops_the_physical_suffix() -> void:
	# InputEvent.as_text() renders this project's physically-mapped keys as "A - Physical";
	# the engine's own wording, not something to show a player.
	var text: String = InputPrompt.action_text(ACTION_KEY)
	assert_false(text.is_empty(), "the action is bound")
	assert_false(text.contains("Physical"), "no engine detail in player-facing copy")
	assert_false(text.contains(" - "), "and no leftover separator")


func test_action_text_uses_the_first_binding() -> void:
	# project.godot lists events in authored order, so the first is the primary way to do the
	# thing. `move` is right-click first, M second — the prompt should say right-click.
	assert_gt(InputMap.action_get_events(ACTION_RMB).size(), 1, "this action has alternates")
	assert_eq(InputPrompt.action_text(ACTION_RMB), "Right Mouse Button")


func test_action_text_on_an_unknown_action_is_empty() -> void:
	assert_eq(InputPrompt.action_text(&"no_such_action"), "")


func test_referenced_actions_lists_them_once_each() -> void:
	var actions: Array[StringName] = InputPrompt.referenced_actions(
		"{{ command_issue }} then {{ world_select }} then {{ command_issue }}"
	)
	assert_eq(actions, [ACTION_RMB, ACTION_LMB] as Array[StringName])


# --- Integration with DialogPage ----------------------------------------------


func test_a_page_renders_resolved_copy_but_keeps_its_source() -> void:
	var page := DialogPage.new()
	page.title = "Selecting"
	page.body = "Drag {{ world_select }}."
	page.acknowledge_text = "Press {{ command_issue }}"
	add_child_autofree(page)

	assert_eq(
		page.body,
		"Drag {{ world_select }}.",
		"the authored source keeps its placeholders, so rebinding re-renders correctly"
	)
	assert_eq(
		page._body_label.text,
		"Drag Left Mouse Button.",
		"the label shows the resolved binding, unstyled"
	)
	assert_eq(page.resolved_acknowledge_text(), "Press Right Mouse Button", "plain for a Button")


func test_a_page_title_resolves_too() -> void:
	var page := DialogPage.new()
	page.title = "Using {{ world_select }}"
	add_child_autofree(page)
	assert_eq(page._title_label.text, "Using Left Mouse Button")


func test_every_authored_page_references_real_actions() -> void:
	# Discovered rather than listed: pages get added, renamed and moved between scenario
	# folders, and a hardcoded list silently stops covering the ones that moved (and breaks
	# outright on the ones that went away). A placeholder naming a renamed action renders as
	# literal braces to the player, so every page is worth checking.
	var pages: Array[String] = _dialog_page_scenes("res://scenes")
	assert_gt(pages.size(), 0, "the project has authored dialog pages to check")
	for path: String in pages:
		var page := (load(path) as PackedScene).instantiate() as DialogPage
		assert_not_null(page, "%s instantiates as a DialogPage" % path)
		autofree(page)
		for text: String in [page.title, page.body, page.acknowledge_text]:
			for name: StringName in InputPrompt.referenced_actions(text):
				# Either an InputMap action or a grid command (which resolves through the
				# cell it occupies) — copy is written without caring which.
				assert_ne(
					InputPrompt.resolve_action(name),
					&"",
					"%s references '%s', which resolves to no binding" % [path, name]
				)


## Every .tscn under `root` whose root node runs dialog_page.gd, found by scanning the file
## text so no scene has to be loaded just to be ruled out.
func _dialog_page_scenes(a_root: String) -> Array[String]:
	const SCRIPT_UID: String = "uid://b60p17fa5hvfc"
	var found: Array[String] = []
	var dirs: Array[String] = [a_root]
	while not dirs.is_empty():
		var dir_path: String = dirs.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for name: String in dir.get_directories():
			dirs.append(dir_path.path_join(name))
		for name: String in dir.get_files():
			if not name.ends_with(".tscn"):
				continue
			var path: String = dir_path.path_join(name)
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null and file.get_as_text().contains(SCRIPT_UID):
				found.append(path)
	return found
