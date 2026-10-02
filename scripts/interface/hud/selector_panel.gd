class_name SelectorPanel
extends Control

## The three selector families — army / builder / production — as HUD buttons, shown in the
## slot that otherwise holds selection info.
##
## They used to be three cells of the command grid, visible only in the SELECT context (i.e.
## only while nothing was selected). Moving them here does two things: it frees the grid's
## top row for the production contexts, and it puts them somewhere the selection state does
## not decide, which is what a selector needs — you reach for one precisely when the current
## selection is wrong.
##
## **The buttons preview the cell you are in.** The selector rules are a 2×2 — cycle-one
## against take-all, crossed with any against idle-only — that until now existed only in
## documentation. Each button polls the held modifiers every frame and re-renders with the
## verb and count its press would actually produce, so holding `modifier_broaden` visibly
## turns "cycle 3" into "select 12". That makes the other cells discoverable by pressing a
## key rather than by reading about it, which is idiom VII (feedback before commitment)
## pointed at selection instead of at orders.
##
## Greying follows the CURRENT cell rather than idleness alone: a family with members but
## none idle greys under `modifier_narrow` and un-greys without it, because the unmodified
## cycle is idle-FIRST rather than idle-only. A greyed button does nothing when pressed — it
## never quietly widens its own cell to find something.
##
## Both modifiers are POLLED rather than latched, for the same reason the selectors already
## poll them: a modifier keypress before a click on a HUD button goes to the focused Control
## rather than to _unhandled_input.

#region Constants
const BUTTON_SIZE: Vector2 = Vector2(74, 46)
const NAME_FONT_SIZE: int = 12
const SCOPE_FONT_SIZE: int = 11

const TEXT_COLOR: Color = Color(0.86, 0.87, 0.86)
const MUTED_COLOR: Color = Color(0.60, 0.63, 0.59)
## Applied to a button whose current cell would select nothing.
const EMPTY_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.32)
## Applied while either modifier is held, so it is obvious the buttons have changed meaning
## rather than merely changed number.
const MODIFIED_MODULATE: Color = Color(0.72, 0.94, 0.97)

## Family, label, and the action whose binding the tooltip names. Order is the display order.
const FAMILIES: Array = [
	[RTSController.SelectorFamily.ARMY, "Army", "command_select_army"],
	[RTSController.SelectorFamily.BUILDER, "Builders", "command_select_builder"],
	[RTSController.SelectorFamily.PRODUCTION, "Producers", "command_select_production"],
]
#endregion

#region Properties
## The controller that owns the selector rules. Injected by RTSController at _ready — this
## panel never re-implements the matrix, it only draws what selector_preview reports.
var controller: RTSController = null

## family index -> [button, name Label, scope Label]
var _rows: Array = []
#endregion


#region Lifecycle
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.name = "Selectors"
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for entry: Array in FAMILIES:
		_rows.append(_build_button(row, entry[0] as int, entry[1] as String, entry[2] as String))


func _process(_a_delta: float) -> void:
	refresh()


#endregion


#region Public API
## Repaint every button from the modifiers currently held. Cheap — three predicate scans over
## the player's commandables, the same work a selector press does.
func refresh() -> void:
	if controller == null:
		return
	var modified: bool = (
		Input.is_action_pressed(RTSController.MODIFIER_NARROW)
		or Input.is_action_pressed(RTSController.MODIFIER_BROADEN)
	)
	for i in _rows.size():
		var entry: Array = _rows[i]
		var button: Button = entry[0]
		var scope_label: Label = entry[2]
		var preview: Dictionary = controller.selector_preview(FAMILIES[i][0] as int)
		var count: int = preview.get("count", 0)
		# The label already carries the verb and the count — see selector_preview, which builds
		# it so this panel and the press it previews cannot word the same cell differently.
		scope_label.text = preview.get("label", "")
		# Disabled rather than merely dimmed: a press that would select nothing should do
		# nothing, not silently widen its own scope to find something.
		button.disabled = count == 0
		button.modulate = (
			EMPTY_MODULATE if count == 0 else (MODIFIED_MODULATE if modified else Color(1, 1, 1))
		)


#endregion


#region Construction
func _build_button(a_parent: Node, a_family: int, a_label: String, a_action: String) -> Array:
	var button := VerboseTooltipButton.new()
	# Name the button BEFORE assigning tooltips, so a tooltip authoring error identifies it.
	button.name = a_label
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	# CURSOR_POINTING_HAND carries the game's own pointer art, registered once in
	# RTSController._register_hud_cursor. Asking for a shape with no art behind it is what
	# drops the cursor to the OS default — see hud-layout.md.
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.simple_tooltip = InputPrompt.format(
		"Select %s ({{ %s }})" % [a_label.to_lower(), a_action]
	)
	button.verbose_tooltip = (
		InputPrompt
		. format(
			(
				"On its own this cycles one member at a time, idle ones first and"
				+ " least-recently-selected within that, so repeated presses walk the whole group.\n"
				+ "Hold {{ modifier_broaden }} to take every one of them at once, and"
				+ " {{ modifier_narrow }} to stay strictly among the idle ones; the two combine, and the"
				+ " button says which set it would take. Hold {{ modifier_additive }} to add to the"
				+ " current selection instead of replacing it.\n"
				+ "Every selector searches the whole map — to grab only what you can see, drag a box"
				+ " over it. The camera comes to the pick when it is off screen."
			)
		)
	)
	button.pressed.connect(
		func() -> void:
			if controller != null:
				controller.run_selector_family(a_family)
	)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _make_label(NAME_FONT_SIZE, TEXT_COLOR)
	name_label.text = a_label
	var scope_label := _make_label(SCOPE_FONT_SIZE, MUTED_COLOR)
	column.add_child(name_label)
	column.add_child(scope_label)
	button.add_child(column)

	a_parent.add_child(button)
	return [button, name_label, scope_label]


func _make_label(a_font_size: int, a_color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", a_font_size)
	label.add_theme_color_override("font_color", a_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
#endregion
