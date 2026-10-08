class_name ReplayNames
extends RefCounted

## How replay files are named, and which autosaves the rotation deletes. Pure: names in, names
## out, so the rules are tested without a filesystem.
## gdd/systems/commands/recording-and-replay.md §Watching.

## An autosave's file name begins with this, and nothing else's may.
const AUTOSAVE_PREFIX: String = "autosaved_replay_"
## How many autosaves are kept. Writing one more deletes the oldest.
const AUTOSAVES_KEPT: int = 3
## Characters a file name cannot hold on some platform; a kept replay's name refuses them.
const FORBIDDEN_CHARACTERS: String = '<>:"/\\|?*'

## The UTC timestamp form a name carries: safe in a file name on every platform, and sorting as
## text sorts it in time. `20260929T221500Z`.
static var _timestamp_pattern: RegEx = RegEx.create_from_string("^\\d{8}T\\d{6}Z$")


## `a_unix_seconds` (UTC) as a file-name timestamp.
static func timestamp(unix_seconds: int) -> String:
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix_seconds)
	return "%04d%02d%02dT%02d%02d%02dZ" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


## The file name of an autosave written at `unix_seconds`.
static func autosave_name(unix_seconds: int) -> String:
	return "%s%s.%s" % [AUTOSAVE_PREFIX, timestamp(unix_seconds), ReplayFile.EXTENSION]


## The timestamp an autosave's name carries, or "" when `a_file_name` is not an autosave: no
## prefix, or a timestamp that does not parse. Only a name like this is ever deleted by the
## rotation.
static func autosave_timestamp(file_name: String) -> String:
	var suffix: String = "." + ReplayFile.EXTENSION
	if not file_name.begins_with(AUTOSAVE_PREFIX) or not file_name.ends_with(suffix):
		return ""
	var stamp: String = file_name.substr(
		AUTOSAVE_PREFIX.length(), file_name.length() - AUTOSAVE_PREFIX.length() - suffix.length()
	)
	return stamp if _timestamp_pattern.search(stamp) != null else ""


static func is_autosave(file_name: String) -> bool:
	return autosave_timestamp(file_name) != ""


## The autosaves among `file_names` to delete before writing one more, oldest first, so that
## AUTOSAVES_KEPT remain once it is written.
static func autosaves_to_delete(file_names: PackedStringArray) -> PackedStringArray:
	var autosaves: Array = Array(file_names).filter(is_autosave)
	autosaves.sort_custom(
		func(a: String, b: String) -> bool: return autosave_timestamp(a) < autosave_timestamp(b)
	)
	var excess: int = autosaves.size() - (AUTOSAVES_KEPT - 1)
	return PackedStringArray(autosaves.slice(0, maxi(excess, 0)))


## Why `a_name` cannot name a kept replay, or "" when it can: empty, a character no file name
## holds, or the autosave prefix (which would put it into the rotation).
static func kept_name_refusal(name: String) -> String:
	if name.strip_edges().is_empty():
		return "a replay needs a name"
	for character: String in FORBIDDEN_CHARACTERS:
		if name.contains(character):
			return "a file name cannot hold '%s'" % character
	if name.begins_with(AUTOSAVE_PREFIX):
		return "names beginning '%s' are kept for autosaves" % AUTOSAVE_PREFIX
	return ""


## The name a kept replay's field is prefilled with: `<scenario>_<timestamp>`.
static func default_kept_name(scenario_name: String, unix_seconds: int) -> String:
	return "%s_%s" % [scenario_name, timestamp(unix_seconds)]
