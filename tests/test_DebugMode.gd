extends GutTest

## DebugMode is two switches: the session's permission and the player's toggle. The view is
## up only when both are on, and a session's permission never outlives the session.


func after_each() -> void:
	DebugMode.configure(false)


func test_the_toggle_action_exists_and_is_bound_to_semicolon() -> void:
	assert_true(InputMap.has_action(DebugMode.TOGGLE_ACTION), "configured in project.godot")
	var events: Array[InputEvent] = InputMap.action_get_events(DebugMode.TOGGLE_ACTION)
	assert_eq(events.size(), 1, "one binding")
	assert_eq((events[0] as InputEventKey).physical_keycode, KEY_SEMICOLON, "bound to ';'")


func test_a_session_starts_hidden() -> void:
	DebugMode.configure(true)
	assert_true(DebugMode.is_allowed(), "the session allows the view")
	assert_false(DebugMode.is_active(), "but it starts down")


func test_the_toggle_raises_and_lowers_the_view() -> void:
	DebugMode.configure(true)
	DebugMode.toggle()
	assert_true(DebugMode.is_active(), "one press raises it")
	DebugMode.toggle()
	assert_false(DebugMode.is_active(), "a second lowers it")


func test_the_toggle_does_nothing_in_a_session_that_does_not_allow_it() -> void:
	DebugMode.configure(false)
	DebugMode.toggle()
	assert_false(DebugMode.is_active(), "no permission, no view")
	DebugMode.configure(true)
	assert_false(DebugMode.is_active(), "and no latent toggle survives into a permitted session")


func test_the_key_toggles_through_the_node() -> void:
	DebugMode.configure(true)
	var node := DebugMode.new()
	add_child_autofree(node)
	var press := InputEventAction.new()
	press.action = DebugMode.TOGGLE_ACTION
	press.pressed = true
	node._unhandled_input(press)
	assert_true(DebugMode.is_active(), "a press raises the view")


func test_leaving_the_tree_revokes_the_permission() -> void:
	DebugMode.configure(true)
	var node := DebugMode.new()
	add_child(node)
	DebugMode.toggle()
	remove_child(node)
	node.free()
	assert_false(DebugMode.is_allowed(), "the session's permission ended with it")
	assert_false(DebugMode.is_active(), "and so did the view")


## Commanding any piece: the debug view widens "mine to command" to every commander's pieces,
## and nothing else about the piece changes.
func test_the_debug_view_lets_the_player_command_anyone() -> void:
	var neutral := Commander.new()
	neutral.id = 0
	neutral.set_physics_process(false)
	add_child_autofree(neutral)
	var foreign: Entity = FakePieces.unit()
	neutral.add_child(foreign)
	foreign.commander = neutral
	var player_id: int = RTSController.PLAYER_COMMANDER_ID
	RTSController.PLAYER_COMMANDER_ID = 1
	DebugMode.configure(true)
	assert_false(RTSController.is_player_commandable(foreign), "not while the view is down")
	DebugMode.toggle()
	assert_true(RTSController.is_player_commandable(foreign), "but while it is up")
	assert_false(RTSController.is_player_commandable(null), "and never nothing")
	RTSController.PLAYER_COMMANDER_ID = player_id


# ─── THE FOG SETTING ─────────────────────────────────────────────────────────


func test_the_view_lifts_the_fog_by_default_and_only_while_up() -> void:
	DebugMode.configure(true)
	assert_false(DebugMode.lifts_fog(), "the view is down: the fog is shown")
	DebugMode.toggle()
	assert_true(DebugMode.lifts_fog(), "up, and lifting by default")


func test_the_view_can_show_the_fog_as_the_viewer_sees_it() -> void:
	DebugMode.configure(true)
	DebugMode.toggle()
	DebugMode.set_fog_lifted(false)
	assert_true(DebugMode.is_active(), "the view stays up")
	assert_false(DebugMode.lifts_fog(), "but the fog is shown")


func test_a_new_session_lifts_the_fog_again() -> void:
	DebugMode.configure(true)
	DebugMode.set_fog_lifted(false)
	DebugMode.configure(true)
	assert_true(DebugMode.is_fog_lifted())
