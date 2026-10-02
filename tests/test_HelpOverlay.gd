extends GutTest

## HelpOverlay swaps two panels on the `show_help` hold: the small hint above the minimap
## while the key is up, the large centred panel while it is held. Exactly one is ever on
## screen. Copy on both resolves {{ action }} placeholders through InputPrompt, the same
## mechanism DialogPage uses, so a prompt names whatever the action is bound to today.

const SCENE := "res://scenes/interface/help_overlay.tscn"

var _overlay: HelpOverlay


func before_each() -> void:
	_overlay = load(SCENE).instantiate() as HelpOverlay
	add_child_autofree(_overlay)


func after_each() -> void:
	# A held action leaks across tests — Input state is global and outlives the node.
	Input.action_release(HelpOverlay.ACTION)
	DebugMode.configure(false)


## Put the action in the given state and let the overlay's _process observe it.
##
## wait_PROCESS_frames, not wait_frames: the latter is deprecated and counts _physics_process
## frames, so it advances the simulation clock without ever running the idle _process this
## overlay polls in — the assertions then read a panel that was never given a chance to swap.
func _set_held(a_held: bool) -> void:
	if a_held:
		Input.action_press(HelpOverlay.ACTION)
	else:
		Input.action_release(HelpOverlay.ACTION)
	await wait_process_frames(2)


func test_the_action_exists_and_is_bound_to_f4() -> void:
	# H moved to F4 when the command grid widened to six columns: cell (5, 1) takes H under
	# the positional scheme (QWERTY / ASDFGH / ZXCVBN), and a grid cell has the stronger
	# claim on a letter than a held overlay does. F4 also puts it beside the F1-F3
	# selectors, which are likewise off the alphabetical block.
	assert_true(InputMap.has_action(HelpOverlay.ACTION), "show_help is configured in project.godot")
	assert_eq(InputPrompt.action_text(HelpOverlay.ACTION), "F4", "show_help is bound to F4")


func test_hint_shows_and_help_hides_when_the_key_is_not_held() -> void:
	await _set_held(false)

	assert_true(_overlay.get_node("%HintPanel").visible, "the hint is the resting state")
	assert_false(_overlay.get_node("%HelpPanel").visible, "the help panel stays down")
	assert_false(_overlay.is_showing_help(), "is_showing_help() agrees")


func test_holding_the_key_swaps_to_the_help_panel() -> void:
	await _set_held(true)

	assert_true(_overlay.get_node("%HelpPanel").visible, "holding show_help raises the help panel")
	assert_false(_overlay.get_node("%HintPanel").visible, "and drops the hint")
	assert_true(_overlay.is_showing_help(), "is_showing_help() agrees")


func test_releasing_the_key_returns_to_the_hint() -> void:
	await _set_held(true)
	await _set_held(false)

	assert_true(_overlay.get_node("%HintPanel").visible, "releasing restores the hint")
	assert_false(_overlay.get_node("%HelpPanel").visible, "and drops the help panel")


func test_the_two_panels_are_never_both_up() -> void:
	for held: bool in [false, true, false, true]:
		await _set_held(held)
		assert_ne(
			_overlay.get_node("%HintPanel").visible,
			_overlay.get_node("%HelpPanel").visible,
			"exactly one panel is visible (held=%s)" % held
		)


func test_hint_copy_resolves_action_placeholders() -> void:
	_overlay.hint_text = "hold {{ show_help }} for help"

	assert_eq(
		_overlay.resolved_hint_text(), "hold F4 for help", "the placeholder becomes the binding"
	)
	assert_eq(
		_overlay.get_node("%HintText").text,
		"hold F4 for help",
		"and the label carries the resolved copy"
	)
	assert_eq(
		_overlay.hint_text,
		"hold {{ show_help }} for help",
		"the authored string keeps its placeholder"
	)


func test_help_copy_resolves_action_placeholders() -> void:
	_overlay.help_text = "attack-move is {{ command_attack_move }}"

	assert_eq(
		_overlay.resolved_help_text(), "attack-move is A", "the placeholder becomes the binding"
	)
	assert_eq(
		_overlay.get_node("%HelpText").text,
		"attack-move is A",
		"and the label carries the resolved copy"
	)


func test_copy_without_placeholders_is_passed_through_untouched() -> void:
	_overlay.hint_text = "plain copy, no braces"

	assert_eq(
		_overlay.resolved_hint_text(),
		"plain copy, no braces",
		"nothing to substitute, nothing changed"
	)


func test_empty_copy_is_allowed() -> void:
	_overlay.hint_text = ""
	_overlay.help_text = ""

	assert_eq(
		_overlay.resolved_hint_text(), "", "an unauthored hint resolves to empty, not an error"
	)
	assert_eq(
		_overlay.resolved_help_text(),
		"",
		"an unauthored help panel resolves to empty, not an error"
	)


func test_the_debug_hint_is_down_in_a_session_that_does_not_allow_debugging() -> void:
	DebugMode.configure(false)
	await wait_process_frames(2)

	assert_false(_overlay.get_node("%DebugHintPanel").visible, "no debug hint without permission")
	assert_false(_overlay.is_showing_debug_hint(), "is_showing_debug_hint() agrees")


func test_the_debug_hint_is_up_while_debugging_is_allowed_but_hidden() -> void:
	DebugMode.configure(true)
	await wait_process_frames(2)

	assert_true(_overlay.get_node("%DebugHintPanel").visible, "the hint offers the debug view")
	assert_true(_overlay.get_node("%HintPanel").visible, "alongside the testing-info hint")


func test_the_debug_hint_drops_once_the_debug_view_is_up() -> void:
	DebugMode.configure(true)
	DebugMode.toggle()
	await wait_process_frames(2)

	assert_false(_overlay.get_node("%DebugHintPanel").visible, "the hint has done its job")


func test_the_debug_hint_names_the_toggle_key() -> void:
	var key: String = InputPrompt.action_text(DebugMode.TOGGLE_ACTION)
	assert_true(
		_overlay.resolved_debug_hint_text().contains(key),
		"the debug hint names the key bound to the toggle"
	)
