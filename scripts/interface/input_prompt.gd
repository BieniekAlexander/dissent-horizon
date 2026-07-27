class_name InputPrompt

## Substitutes `{{ action_name }}` placeholders in player-facing copy with whatever that
## InputMap action is actually bound to — "hold and drag {{ world_select }}"
## renders as "hold and drag Left Mouse Button".
##
## Why not just write the button name: the binding is data, and copy that hardcodes it goes
## wrong in three ways. It goes stale the moment an action is rebound in project.godot; it
## can't survive a player-facing rebinding screen; and it is already wrong per-platform today
## — macOS reports the Alt-bound `modifier_narrow` modifier as "Option", not "Alt". Resolving at
## RENDER time (pages are instantiated fresh each time they're shown) means the prompt is
## always what the player would actually press.
##
## ── On Godot's native templating ──
##
## The engine's standard mechanism is `String.format(values, placeholder)`, where the
## placeholder is a pattern whose `_` is swapped for each dictionary key. It handles this
## exact syntax:
##
##     "drag {{ world_select }}".format({"world_select": "LMB"}, "{{ _ }}")
##
## This class uses a RegEx instead, for two things `String.format` can't do:
##   * it accepts `{{name}}` and `{{ name }}` alike, where `String.format` matches ONE exact
##     spelling and silently leaves the other on screen;
##   * it knows which actions the text actually referenced, so a typo can be reported instead
##     of shipping literal braces to the player.
## The syntax is the same either way, so copy stays portable to plain `String.format` if this
## ever needs to go.
##
## (`tr()` / TranslationServer is the other half of the standard story — this composes with
## it: translate first, then substitute, so a translator moves the placeholder around inside
## the sentence without touching the action name.)

#region Constants
## `{{ action_name }}`, tolerating any surrounding whitespace inside the braces.
const PATTERN: String = "\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\}\\}"
#endregion

#region Properties
## Compiled once on first use; RegEx compilation is not free and this runs per page render.
static var _regex: RegEx = null
#endregion

#region Public API
## Replace every `{{ action }}` in `text` with that action's current binding, as plain text.
##
## Styling is the author's business, not this function's: the substitution is a straight
## name-for-name swap, so a page that wants the key to stand out writes the markup around the
## placeholder itself — `[b]{{ world_select }}[/b]`.
##
## A placeholder naming an action that doesn't exist is left as-authored (braces and all, so
## it reads as the bug it is) and reported.
static func format(text: String) -> String:
	if text.is_empty():
		return text
	var matches: Array[RegExMatch] = _compiled().search_all(text)
	if matches.is_empty():
		return text

	# Built by walking the matches forward and splicing, rather than by repeated replace():
	# replace() would rescan from the start each time, and could re-substitute into text a
	# binding had just produced.
	var result: String = ""
	var cursor: int = 0
	for m: RegExMatch in matches:
		result += text.substr(cursor, m.get_start() - cursor)
		var action: StringName = resolve_action(StringName(m.get_string(1)))
		if action != &"":
			var binding: String = action_text(action)
			result += binding
		else:
			push_warning(
				"InputPrompt: '%s' is neither an InputMap action nor a command in the grid; leaving the placeholder in place."
				% m.get_string(1)
			)
			result += m.get_string()
		cursor = m.get_end()
	return result + text.substr(cursor)


## The InputMap action a placeholder name refers to, or &"" if it refers to nothing.
##
## Two kinds of name resolve, and copy is written without caring which it used:
##   * an InputMap action, which is most of them (`{{ command_issue }}`, `{{ modifier_additive }}`);
##   * a COMMAND in the command grid (`{{ command_attack_move }}`), which has no action of
##     its own because grid hotkeys are positional — the cell carries the key, so the
##     command resolves through whichever cell it currently occupies.
##
## The second case is why copy can keep naming commands after the move to positional
## hotkeys: `command_attack_move` stopped being an action, and every tooltip that named it
## goes on rendering the right key, and re-words itself if that button ever moves.
static func resolve_action(name: StringName) -> StringName:
	if InputMap.has_action(name):
		return name
	var cell_action: StringName = CommandGrid.action_for_command(String(name))
	return cell_action if InputMap.has_action(cell_action) else &""


## The player-facing name of whatever `action` is bound to, e.g. "Left Mouse Button", "A",
## "Space". Empty when the action exists but has no binding.
##
## Uses the FIRST event bound to the action — project.godot lists them in the order the
## designer authored, so the first is the primary way to do the thing. (`move` is
## right-click first, `M` second; the prompt should say right-click.)
static func action_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return _event_text(events[0]) if not events.is_empty() else ""


## The actions a piece of copy refers to. For tests and for anything that wants to check a
## page's placeholders without rendering it.
static func referenced_actions(text: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for m: RegExMatch in _compiled().search_all(text):
		var action := StringName(m.get_string(1))
		if action not in result:
			result.append(action)
	return result
#endregion

#region Internal
## One event as player-facing text.
##
## `InputEvent.as_text()` is right for mouse and joypad ("Left Mouse Button", "Mouse Wheel
## Up") but appends " - Physical" for a physically-mapped key — every keyboard binding in
## this project — which is engine detail, not something to show a player. The keycode
## helpers give the bare name.
static func _event_text(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		if key.physical_keycode != 0:
			return key.as_text_physical_keycode()
		return key.as_text_keycode()
	return event.as_text()


static func _compiled() -> RegEx:
	if _regex == null:
		_regex = RegEx.new()
		_regex.compile(PATTERN)
	return _regex
#endregion
