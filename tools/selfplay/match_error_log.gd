extends Logger

## EVERY ERROR A MATCH RAISED, counted, so a result can say whether the code under test ran
## clean. Without a debugger attached a script error does not stop the game — Godot logs it,
## returns a default from the failing function and carries on — so a match full of them still
## reaches a verdict and looks exactly like a clean one. Registered by run_match.gd with
## OS.add_logger; errors raised before that (a parse error at load) are not seen here, and fail
## the match by other routes.
##
## Three kinds, told apart by what Godot hands a Logger: SCRIPT (a GDScript runtime error — a
## bug, always), PUSH (push_error — code reporting a contained failure), and ENGINE (an engine
## check that failed, such as reading a position off the tree). Warnings are not counted.

const KIND_SCRIPT: String = "script"
const KIND_PUSH: String = "push_error"
const KIND_ENGINE: String = "engine"
## How many distinct errors a result lists; the counts cover all of them.
const TOP_LIMIT: int = 20

## Logger calls arrive from whichever thread raised the error.
var _mutex: Mutex = Mutex.new()
## Kind -> count.
var _counts: Dictionary = {KIND_SCRIPT: 0, KIND_PUSH: 0, KIND_ENGINE: 0}
## "kind|message|at" -> {"kind", "message", "at", "count"}.
var _distinct: Dictionary = {}


func _log_error(
	a_function: String,
	a_file: String,
	a_line: int,
	a_code: String,
	a_rationale: String,
	_a_editor_notify: bool,
	a_error_type: int,
	a_backtraces: Array[ScriptBacktrace]
) -> void:
	var kind: String = _kind_of(a_error_type, a_function)
	if kind.is_empty():
		return
	var message: String = a_rationale if not a_rationale.is_empty() else a_code
	var at: String = _script_frame(a_backtraces, "%s:%d" % [a_file, a_line])
	var key: String = "%s|%s|%s" % [kind, message, at]
	_mutex.lock()
	_counts[kind] += 1
	if not _distinct.has(key):
		_distinct[key] = {"kind": kind, "message": message, "at": at, "count": 0}
	_distinct[key]["count"] += 1
	_mutex.unlock()


func script_error_count() -> int:
	_mutex.lock()
	var count: int = _counts[KIND_SCRIPT]
	_mutex.unlock()
	return count


## The result's `errors` block: a count per kind, and the most frequent distinct errors with
## the script line each was raised from.
func summary() -> Dictionary:
	_mutex.lock()
	var counts: Dictionary = _counts.duplicate()
	var distinct: Array = _distinct.values().map(
		func(e: Dictionary) -> Dictionary: return e.duplicate()
	)
	_mutex.unlock()
	distinct.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["count"] > b["count"])
	counts["top"] = distinct.slice(0, TOP_LIMIT)
	return counts


## The counted kind of an error, or "" for one that is not counted (a warning, a shader).
static func _kind_of(error_type: int, function: String) -> String:
	match error_type:
		ERROR_TYPE_SCRIPT:
			return KIND_SCRIPT
		ERROR_TYPE_ERROR:
			return KIND_PUSH if function == "push_error" else KIND_ENGINE
		_:
			return ""


## The innermost GDScript frame, as "res://…:line function" — where in the game's code the
## error was raised, which an engine error's own C++ location does not say.
static func _script_frame(backtraces: Array[ScriptBacktrace], fallback: String) -> String:
	for backtrace: ScriptBacktrace in backtraces:
		if backtrace.get_frame_count() > 0:
			return (
				"%s:%d %s"
				% [
					backtrace.get_frame_file(0),
					backtrace.get_frame_line(0),
					backtrace.get_frame_function(0)
				]
			)
	return fallback
