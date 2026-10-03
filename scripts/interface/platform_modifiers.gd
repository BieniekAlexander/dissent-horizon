class_name PlatformModifiers
extends RefCounted
## Which physical key `modifier_broaden` and `modifier_narrow` sit on, per platform.
##
## project.godot binds them for Windows and Linux: broaden is Ctrl, narrow is Alt. macOS cannot
## keep that. It turns Ctrl + left click into a right click before the engine sees it, so a
## Ctrl-modified mouse gesture never arrives as the player pressed it. There the two move to
## Option (broaden) and Command (narrow). Godot calls those keys ALT and META.
##
## The InputMap has no per-platform bindings, so `apply` rewrites the two actions at startup;
## everything that reads them, polled or by prompt text, follows. Rules:
## gdd/systems/ux/ui/interface-idioms.md §Constraints that shape the design.

const BROADEN: StringName = &"modifier_broaden"
const NARROW: StringName = &"modifier_narrow"

const MACOS: String = "macOS"


## The key each remapped modifier sits on for `a_platform` (an `OS.get_name()` value). Empty when
## the platform keeps the project.godot defaults.
static func keys_for(a_platform: String) -> Dictionary:
	if a_platform == MACOS:
		return {BROADEN: KEY_ALT, NARROW: KEY_META}
	return {}


## Rebind the modifiers for `a_platform`. Only the KEY events of each action are replaced, so
## anything else bound to it survives. Returns whether anything was rebound.
static func apply(a_platform: String = OS.get_name()) -> bool:
	var keys: Dictionary = keys_for(a_platform)
	for action: StringName in keys:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action] as Key
		InputMap.action_add_event(action, key)
	return not keys.is_empty()
