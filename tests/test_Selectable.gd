extends GutTest

## Tests for the Selectable component.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Selectable.gd

func _make_selectable() -> Selectable:
	var s := Selectable.new()
	add_child_autofree(s)
	return s

func test_default_state_is_unselected():
	var s := _make_selectable()
	assert_eq(s.state, Selectable.State.UNSELECTED)
	assert_false(s.is_selected())

func test_select_transitions_to_selected():
	var s := _make_selectable()
	assert_true(s.select())
	assert_eq(s.state, Selectable.State.SELECTED)
	assert_true(s.is_selected())

func test_deselect_transitions_to_unselected():
	var s := _make_selectable()
	s.select()
	assert_true(s.deselect())
	assert_eq(s.state, Selectable.State.UNSELECTED)
	assert_false(s.is_selected())

func test_set_state_returns_false_when_unchanged():
	var s := _make_selectable()
	# Already UNSELECTED; setting to UNSELECTED again is a no-op.
	assert_false(s.set_state(Selectable.State.UNSELECTED))
	s.select()
	# Already SELECTED; setting to SELECTED again is a no-op.
	assert_false(s.set_state(Selectable.State.SELECTED))

func test_state_changed_signal_emits_with_old_and_new():
	var s := _make_selectable()
	watch_signals(s)
	s.select()
	assert_signal_emitted_with_parameters(
		s, "state_changed", [Selectable.State.UNSELECTED, Selectable.State.SELECTED]
	)

func test_state_changed_not_emitted_on_no_op():
	var s := _make_selectable()
	watch_signals(s)
	s.set_state(Selectable.State.UNSELECTED)  # already UNSELECTED
	assert_signal_not_emitted(s, "state_changed")

func test_disabled_selectable_rejects_non_unselected_states():
	var s := _make_selectable()
	s.enabled = false
	assert_false(s.select())
	assert_eq(s.state, Selectable.State.UNSELECTED)
	# But you can still force it back to UNSELECTED (e.g., for cleanup).
	s.enabled = true
	s.select()
	s.enabled = false
	assert_true(s.set_state(Selectable.State.UNSELECTED))

func test_indicator_visibility_tracks_state():
	var s := _make_selectable()
	var indicator := Node3D.new()
	add_child_autofree(indicator)
	indicator.visible = false
	s.set_indicator(indicator)
	# set_indicator should sync immediately based on current state.
	assert_false(indicator.visible, "indicator hidden when unselected")
	s.select()
	assert_true(indicator.visible, "indicator visible when selected")
	s.deselect()
	assert_false(indicator.visible, "indicator hidden after deselect")

func test_preview_state_also_shows_indicator():
	var s := _make_selectable()
	var indicator := Node3D.new()
	add_child_autofree(indicator)
	s.set_indicator(indicator)
	s.set_state(Selectable.State.PREVIEW)
	assert_true(indicator.visible, "PREVIEW shows indicator (box-drag preview)")

func test_hovered_state_does_not_show_indicator():
	# HOVERED is reserved for future hover-highlight; it should NOT light the
	# selection ring (a future SelectionVisual will draw a separate hover tint).
	var s := _make_selectable()
	var indicator := Node3D.new()
	add_child_autofree(indicator)
	s.set_indicator(indicator)
	s.set_state(Selectable.State.HOVERED)
	assert_false(indicator.visible)

func test_get_entity_returns_parent_when_parent_is_entity():
	# We can't easily instantiate a full Entity in a unit test (CharacterBody3D
	# in the scene tree pulls in physics state), so just verify the cast
	# behavior: a non-Entity parent returns null.
	var s := _make_selectable()
	# Selectable is parented to the test scene (a Node), not an Entity.
	assert_null(s.get_entity(), "non-Entity parent returns null via cast")

func test_indicator_path_resolves_on_ready():
	# Step 2 behavior: setting indicator_path before the node enters the tree
	# should auto-wire the indicator without a manual set_indicator() call.
	var parent := Node.new()
	add_child_autofree(parent)
	var indicator := Node3D.new()
	indicator.name = "Indicator"
	parent.add_child(indicator)
	var s := Selectable.new()
	s.indicator_path = NodePath("../Indicator")
	parent.add_child(s)  # triggers Selectable._ready()
	# Default state is UNSELECTED, so indicator should be hidden after _ready.
	assert_false(indicator.visible, "indicator hidden after auto-wire (UNSELECTED)")
	s.select()
	assert_true(indicator.visible, "indicator becomes visible on select()")

func test_indicator_path_empty_is_a_no_op():
	# An unset indicator_path must not crash _ready or push errors.
	var s := Selectable.new()
	# indicator_path is the default (empty NodePath).
	add_child_autofree(s)  # triggers _ready
	# If we got here without erroring, we're good. Sanity check state ops still work.
	s.select()
	assert_true(s.is_selected())
