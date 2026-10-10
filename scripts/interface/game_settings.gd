class_name GameSettings
extends RefCounted
## THE PLAYER'S OPTIONS, saved between runs in a ConfigFile (`user://settings.cfg`). Static, so
## any screen reads a setting without finding a node; loaded on first read, saved on every
## change. The Options page (MainMenu) is what edits them. gdd/systems/ux/ui/menus.md §Options.
##
## Only what a screen offers lives here. The master volume is not yet one of them (it is set
## live and forgotten — TODO).

#region Constants
## Which alerts the jump key (`camera_jump_to_alert`) visits.
enum AlertJumpScope {
	NEGATIVE,  ## only alerts about harm: attacks, a detected enemy, a dry pond (the default)
	ALL,  ## every alert that may say where, completions and charged abilities included
}

const PATH: String = "user://settings.cfg"
const SECTION_ALERTS: String = "alerts"
const KEY_JUMP_SCOPE: String = "jump_scope"
#endregion

#region Properties
## Where settings are read and written. A test points it elsewhere and calls `reset()`.
static var path: String = PATH

static var _alert_jump_scope: AlertJumpScope = AlertJumpScope.NEGATIVE
static var _loaded: bool = false
#endregion


#region Public API
static func alert_jump_scope() -> AlertJumpScope:
	_ensure_loaded()
	return _alert_jump_scope


static func set_alert_jump_scope(a_scope: AlertJumpScope) -> void:
	_ensure_loaded()
	_alert_jump_scope = a_scope
	save()


## Write every setting to `path`.
static func save() -> Error:
	var file := ConfigFile.new()
	file.set_value(SECTION_ALERTS, KEY_JUMP_SCOPE, AlertJumpScope.keys()[_alert_jump_scope])
	return file.save(path)


## Forget what was read, so the next read loads `path` again — the defaults when it is missing.
static func reset() -> void:
	_alert_jump_scope = AlertJumpScope.NEGATIVE
	_loaded = false


#endregion


#region Internal
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	# Stored by NAME, so reordering the enum never reinterprets a saved choice.
	var scope: String = str(file.get_value(SECTION_ALERTS, KEY_JUMP_SCOPE, ""))
	if AlertJumpScope.has(scope):
		_alert_jump_scope = AlertJumpScope[scope]
#endregion
