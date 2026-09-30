class_name ControlScheme
extends RefCounted
## Which button does what once an order is ARMED.
##
## Unarmed, the two pointer buttons never change: `world_select` selects, `command_issue` gives
## the default order. The scheme decides only what they mean while something is armed, and it
## does so through two actions the code reads instead of the buttons:
##
##   `command_armed_issue`   carry out the armed order
##   `command_armed_cancel`  put it down
##
## Their events are COPIED from `world_select` / `command_issue` by `apply`, so a rebinding of
## either button carries through and a prompt can ask the InputMap what they are bound to.
## Rules: gdd/systems/ux/ui/control-matrices.md §Armed-order scheme.

enum Kind {
	## Right click issues the armed order and left click puts it down.
	CLASSIC,
	## Left click issues the armed order and right click puts it down, as in most RTS games.
	ARMED_SWAP,
}

const ARMED_ISSUE: StringName = &"command_armed_issue"
const ARMED_CANCEL: StringName = &"command_armed_cancel"

## TODO: read from the game's settings once there are any, and expose in the options menu.
## Until then this is the hardcoded default.
static var active: Kind = Kind.ARMED_SWAP:
	set(a_kind):
		active = a_kind
		apply()


## The button action that carries out an armed order under `a_kind`.
static func issue_source(a_kind: Kind = active) -> StringName:
	return &"world_select" if a_kind == Kind.ARMED_SWAP else &"command_issue"


## The button action that puts an armed order down under `a_kind`.
static func cancel_source(a_kind: Kind = active) -> StringName:
	return &"command_issue" if a_kind == Kind.ARMED_SWAP else &"world_select"


## Give the two armed actions the events of the buttons the active scheme sources them from.
static func apply() -> void:
	_copy_events(issue_source(), ARMED_ISSUE)
	_copy_events(cancel_source(), ARMED_CANCEL)


static func _copy_events(a_from: StringName, a_to: StringName) -> void:
	if not InputMap.has_action(a_from) or not InputMap.has_action(a_to):
		return
	InputMap.action_erase_events(a_to)
	for event: InputEvent in InputMap.action_get_events(a_from):
		InputMap.action_add_event(a_to, event.duplicate() as InputEvent)


## Whether `a_event` is the armed action `a_action` being pressed (or released, with
## `a_pressed` false). Reads the button it is sourced from too, so a synthetic event for the
## button itself counts as the same thing a real click does.
static func matches(a_event: InputEvent, a_action: StringName, a_pressed: bool = true) -> bool:
	var source: StringName = issue_source() if a_action == ARMED_ISSUE else cancel_source()
	for action: StringName in [a_action, source]:
		if a_pressed and a_event.is_action_pressed(action):
			return true
		if not a_pressed and a_event.is_action_released(action):
			return true
	return false
