class_name CursorReadout
extends PanelContainer

## A one-line label that follows the mouse, for facts about the WORLD under the cursor rather
## than about a HUD control.
##
## Godot's own `tooltip_text` is a Control's, and answers "what is this button": it needs a
## hovered Control, a hover delay, and a rectangle to hang off. Nothing here has any of those
## — what is being hovered is a patch of ground — so this is a plain panel the controller
## positions, shown and hidden by whatever the cursor resolves to that frame.
##
## Deliberately content-agnostic: it shows a string. Water is the first caller (a body's
## remaining energy); anything else the cursor can name reuses it rather than growing a
## second floating label.

#region Constants
## Offset from the cursor's hotspot, so the panel sits clear of the pointer art rather than
## under it. Down-and-right, the direction a cursor tip points away from.
const _CURSOR_OFFSET := Vector2(18.0, 18.0)

## Kept off the viewport edge by this much, so a readout near the bottom-right of the screen
## flips to the other side of the cursor instead of being clipped.
const _EDGE_MARGIN: float = 4.0
#endregion

#region Properties
var _label: Label
#endregion


#region Lifecycle
func _ready() -> void:
	# Purely informational: it must never eat a click meant for the ground beneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


#endregion


#region Public API
## Show `a_text` next to `a_mouse_position`, or hide the readout when the text is empty.
## Called every frame from the controller, so it is the ONE place the readout's visibility is
## decided — there is no separate hide() for a caller to forget.
func show_text(a_text: String, a_mouse_position: Vector2) -> void:
	if a_text.is_empty():
		visible = false
		return
	if _label.text != a_text:
		_label.text = a_text
		# The panel only knows its size after the label has been re-laid-out; without this the
		# edge flip below uses the PREVIOUS string's width for one frame.
		reset_size()
	visible = true
	position = _clamped_position(a_mouse_position)


#endregion


#region Private helpers
## Where the panel goes: down-and-right of the cursor, flipped to the other side of it on
## whichever axis would otherwise run off the viewport.
func _clamped_position(a_mouse_position: Vector2) -> Vector2:
	var viewport: Vector2 = get_viewport_rect().size
	var placed: Vector2 = a_mouse_position + _CURSOR_OFFSET
	if placed.x + size.x + _EDGE_MARGIN > viewport.x:
		placed.x = a_mouse_position.x - _CURSOR_OFFSET.x - size.x
	if placed.y + size.y + _EDGE_MARGIN > viewport.y:
		placed.y = a_mouse_position.y - _CURSOR_OFFSET.y - size.y
	var margin: Vector2 = Vector2(_EDGE_MARGIN, _EDGE_MARGIN)
	return placed.clamp(margin, viewport - size - margin)
#endregion
