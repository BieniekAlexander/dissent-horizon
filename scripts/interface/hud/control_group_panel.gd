class_name ControlGroupPanel
extends Control

## The ten control groups as a row of HUD buttons — number, head count, and the two presses
## that read and write a group.
##
## PERSISTENT, by the rule in gdd/systems/ux/ui/hud-layout.md: "what have I got squadded up" is
## a question you ask with nothing selected, and reaching for a group is something you do
## precisely because the current selection is wrong. Same reasoning that moved SelectorPanel
## out of the command grid.
##
## **This panel never re-implements the group rules.** Membership, pruning and every gesture
## live on RTSController (see its #region Control groups); the panel reads `control_group()`
## for the count and calls `apply_control_group_gesture()` for a press. That is what keeps
## the button and the number key from ever disagreeing about what a group holds.
##
## The count is HEAD COUNT, not occupancy or any other weighting — "how many things are in
## this group" is the question a player asks of a squad.
##
## The two mouse buttons ARE the read/write axis, which frees a modifier the number row has
## to spend on it — see RTSController.control_group_button_gesture, and
## gdd/systems/ux/ui/selection-and-input.md §The control-group panel.

#region Constants
const BUTTON_SIZE: Vector2 = Vector2(38, 34)
const NUMBER_FONT_SIZE: int = 13
const COUNT_FONT_SIZE: int = 10

const TEXT_COLOR: Color = Color(0.86, 0.87, 0.86)
const MUTED_COLOR: Color = Color(0.60, 0.63, 0.59)
## An EMPTY but visible slot — the next group you could assign. Dimmed rather than hidden,
## because it is an invitation rather than a state (see button_is_visible).
const EMPTY_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.38)
#endregion

#region Visibility
## Whether the button for group `a_index` (0-based) is on screen, given how many members each
## group holds. `a_counts` is one head count per group, in group order.
##
## Three rules, and they compose into "the populated run, plus the next empty slot":
##   * GROUP 1 IS ALWAYS SHOWN, empty or not. Authored rather than derived — it is the base
##     case the third rule chains from, and an untouched game that shows no panel at all
##     teaches the player nothing.
##   * a group with members is always shown;
##   * the group AFTER a populated one is shown, so there is always somewhere to assign to.
##
## An emptied group is not remembered as having existed: when its last member dies it returns
## to exactly the state it had before anything was assigned to it, so the row shrinks back.
## That is why this is computed from the live counts every frame rather than from a
## "has ever been used" flag.
static func button_is_visible(index: int, counts: Array) -> bool:
	if index < 0 or index >= counts.size():
		return false
	if index == 0:
		return true
	if int(counts[index]) > 0:
		return true
	return int(counts[index - 1]) > 0
#endregion

#region Properties
## The controller that owns the groups. Injected by RTSController each frame, the same way
## SelectorPanel is — this panel is a view over that state and holds none of its own.
var controller: RTSController = null

## group index -> [button, number Label, count Label]
var _rows: Array = []
#endregion

#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.name = "Groups"
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for i: int in RTSController.CONTROL_GROUP_COUNT:
		_rows.append(_build_button(row, i))

func _process(_a_delta: float) -> void:
	refresh()
#endregion

#region Public API
## Repaint every button from the live group membership. Cheap: ten validity scans over arrays
## that hold a squad each, which is the same work a group keypress already does.
func refresh() -> void:
	if controller == null:
		return
	var counts: Array = []
	for i: int in _rows.size():
		counts.append(controller.control_group(i).size())
	for i: int in _rows.size():
		var entry: Array = _rows[i]
		var button: Button = entry[0]
		var count: int = int(counts[i])
		button.visible = button_is_visible(i, counts)
		# Blank rather than "0": an empty slot is an invitation to assign, and a zero reads as a
		# count that means something.
		(entry[2] as Label).text = str(count) if count > 0 else ""
		button.modulate = Color(1, 1, 1) if count > 0 else EMPTY_MODULATE
#endregion

#region Construction
func _build_button(a_parent: Node, a_index: int) -> Array:
	var button := VerboseTooltipButton.new()
	# Named before the tooltips are assigned, so a tooltip authoring error identifies it.
	button.name = "Group%d" % (a_index + 1)
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	# CURSOR_POINTING_HAND carries the game's own pointer art, registered once in
	# RTSController._register_hud_cursor. Asking for a shape with no art behind it is what
	# drops the cursor to the OS default — see hud-layout.md.
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.simple_tooltip = InputPrompt.format(
		"Control group %d ({{ %s }})" % [a_index + 1, RTSController.control_group_action(a_index)]
	)
	button.verbose_tooltip = InputPrompt.format(
		("LEFT click reads the group and acts on your selection; RIGHT click writes the group."
		+ "\nHold {{ modifier_additive }} to add rather than replace, or {{ modifier_narrow }}"
		+ " to remove.\nThe same group answers to {{ %s }} on the keyboard."
		+ "\nAn empty slot is the next one you can assign to; a group whose members have all"
		+ " died goes back to being one.") % RTSController.control_group_action(a_index)
	)
	# LEFT reads the group. The modifiers are read at press time — see
	# RTSController.control_group_button_gesture for the whole table.
	button.pressed.connect(func() -> void:
		if controller != null:
			controller.run_control_group_button(a_index, false)
	)
	# RIGHT click writes the group. Connected to the `gui_input` SIGNAL rather than by
	# overriding _gui_input, for the reason ButtonSpec gives: that virtual is BaseButton's, and
	# a script override would replace the press handling the left click depends on.
	button.gui_input.connect(func(event: InputEvent) -> void:
		var mouse_event := event as InputEventMouseButton
		if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
				or not mouse_event.pressed:
			return
		button.accept_event()
		if controller != null:
			controller.run_control_group_button(a_index, true)
	)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number_label := _make_label(NUMBER_FONT_SIZE, TEXT_COLOR)
	number_label.text = str(a_index + 1)
	var count_label := _make_label(COUNT_FONT_SIZE, MUTED_COLOR)
	column.add_child(number_label)
	column.add_child(count_label)
	button.add_child(column)

	a_parent.add_child(button)
	return [button, number_label, count_label]

func _make_label(a_font_size: int, a_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", a_font_size)
	label.add_theme_color_override("font_color", a_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
#endregion
