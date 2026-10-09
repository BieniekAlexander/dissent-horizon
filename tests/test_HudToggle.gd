extends GutTest

## The hide-HUD button: above the minimap wherever there is one, in a match and a look-only HUD
## alike; hidden, the HUD leaves that one button on the bottom edge at the same horizontal
## position. gdd/systems/ux/ui/hud-layout.md §Hiding the HUD.
##
## The scenario is a HARNESS — one human slot on a flat map — and its content does not matter.

const HARNESS: String = "res://scenes/scenarios/test/nav_straight_line.tscn"

var _scenario: Scenario


func before_each() -> void:
	gut.error_tracker.disabled = true
	_scenario = (load(HARNESS) as PackedScene).instantiate() as Scenario
	await get_tree().process_frame
	add_child(_scenario)
	await get_tree().process_frame


func after_each() -> void:
	_scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


func _hud() -> RTSController:
	return _scenario.local_player().get_node("Controller") as RTSController


func _toggle(a_hud: RTSController) -> Button:
	return a_hud.find_child("HudToggle", true, false) as Button


func test_a_match_hud_has_the_toggle_just_above_the_minimap() -> void:
	var hud: RTSController = _hud()
	var toggle: Button = _toggle(hud)
	assert_not_null(toggle, "wherever there is a minimap")
	var map_section: Control = hud.get_node("MapSection") as Control
	assert_eq(toggle.offset_left, map_section.offset_left, "at the minimap's left edge")
	assert_lt(toggle.offset_bottom, map_section.offset_top, "above it")
	assert_eq(toggle.text, "Hide HUD")


func test_hiding_leaves_one_button_on_the_bottom_edge_at_the_same_position() -> void:
	var hud: RTSController = _hud()
	var toggle: Button = _toggle(hud)
	var left: float = toggle.offset_left
	toggle.pressed.emit()
	assert_true(hud.is_hud_hidden)
	assert_false(hud.visible, "every panel goes with the HUD's layer")
	assert_false(
		(hud.get_node("MapSection") as Control).is_visible_in_tree(),
		"and a hidden panel no longer blocks a world click"
	)
	assert_true(toggle.is_visible_in_tree(), "the one button stays")
	assert_eq(toggle.offset_left, left, "at the same horizontal position")
	assert_eq(toggle.offset_bottom, -RTSController.HUD_TOGGLE_MARGIN, "on the bottom edge")
	assert_eq(toggle.text, "Show HUD")
	var timer_layer: CanvasLayer = _scenario.get_node("ScenarioTimerLayer") as CanvasLayer
	assert_false(timer_layer.visible, "the other HUD layers follow")


func test_showing_brings_everything_back() -> void:
	var hud: RTSController = _hud()
	hud.set_hud_hidden(true)
	_toggle(hud).pressed.emit()
	assert_false(hud.is_hud_hidden)
	assert_true(hud.visible)
	assert_true((_scenario.get_node("ScenarioTimerLayer") as CanvasLayer).visible)
	assert_eq(_toggle(hud).text, "Hide HUD")


func test_the_drag_box_survives_hiding() -> void:
	var hud: RTSController = _hud()
	hud.set_hud_hidden(true)
	assert_false(hud.selection_box.get_parent() == hud, "kept off the layer that hides")
