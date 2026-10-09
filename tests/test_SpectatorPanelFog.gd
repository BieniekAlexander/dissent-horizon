extends GutTest

## The spectator panel's fog toggle: the spectator's own setting, which the debug view overrides
## while it is up — the toggle then reads off and is locked — and gives back when lowered.

var _panel: SpectatorPanel
var _was_allowed: bool


func before_each() -> void:
	_was_allowed = DebugMode.is_allowed()
	DebugMode.configure(true)
	Fog.set_view_lifted(false)
	_panel = SpectatorPanel.new()
	add_child_autofree(_panel)


func after_each() -> void:
	DebugMode.configure(_was_allowed)
	Fog.set_view_lifted(false)


func _toggle() -> CheckButton:
	return _panel.find_child("FogToggle", true, false) as CheckButton


func test_the_toggle_lifts_and_shows_the_fog() -> void:
	assert_true(_toggle().button_pressed, "the fog starts shown")
	_panel.set_fog_shown(false)
	assert_true(Fog.is_lifted())
	_panel.set_fog_shown(true)
	assert_false(Fog.is_lifted())


func test_the_debug_view_locks_the_toggle_off_and_lowering_it_restores_the_setting() -> void:
	DebugMode.toggle()
	_panel._refresh()
	assert_true(Fog.is_lifted(), "the debug view lifts the fog")
	assert_false(_toggle().button_pressed, "the toggle reads off")
	assert_true(_toggle().disabled, "and is locked")
	DebugMode.toggle()
	_panel._refresh()
	assert_false(_toggle().disabled)
	assert_true(_toggle().button_pressed, "the spectator's own setting is back")
	assert_false(Fog.is_lifted())


func test_leaving_the_panel_shows_the_fog_again() -> void:
	_panel.set_fog_shown(false)
	remove_child(_panel)
	assert_false(Fog.is_lifted())
	add_child(_panel)
