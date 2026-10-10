class_name ReplayFile
extends RefCounted

## A replay on disk: JSON lines compressed with gzip, which plain `gunzip` and Python's `gzip`
## read. The first line is the header; every later line is one record — an order, a state
## digest — stamped with the tick it belongs to.
## gdd/systems/commands/recording-and-replay.md §The file.
##
## TODO: the codec is not decided; gzip is the note's default reach, and the match event log
## already ships in it.

## Where replays live. `user://` is the game's first persistence.
const DIRECTORY: String = "user://replays/"
## A replay's file extension: says what the bytes are, so ordinary tools open it.
const EXTENSION: String = "jsonl.gz"
## The record type of the first line.
const HEADER_TYPE: String = "header"
## Directories and files whose content decides what a replay plays back as: change any and the
## same orders no longer reproduce the match, so the version stamp hashes them.
const VERSIONED_PATHS: Array[String] = [
	"res://scripts/generated/",
	"res://resources/generated/",
	"res://scenes/entities/",
]

## The header: the scenario, its map, the seed, every slot, and the version stamp.
var header: Dictionary = {}
## Every record after the header, oldest first.
var records: Array[Dictionary] = []


## The bytes of this replay as written to disk.
func to_bytes() -> PackedByteArray:
	var lines: PackedStringArray = [JSON.stringify(header)]
	for record: Dictionary in records:
		lines.append(JSON.stringify(record))
	return ("\n".join(lines) + "\n").to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


## The replay in `bytes`, or null when they are not one (not gzip, no header line first).
static func from_bytes(bytes: PackedByteArray) -> ReplayFile:
	# Not gzip at all (its two magic bytes): say so here rather than have the decompressor
	# raise an engine error over a stray file in the replay folder.
	if bytes.size() < 2 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return null
	var text: String = (
		bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	)
	var lines: PackedStringArray = text.split("\n", false)
	if lines.is_empty():
		return null
	var first: Variant = JSON.parse_string(lines[0])
	if not (first is Dictionary) or (first as Dictionary).get("type") != HEADER_TYPE:
		return null
	var replay := ReplayFile.new()
	replay.header = first
	for i: int in range(1, lines.size()):
		var parsed: Variant = JSON.parse_string(lines[i])
		if parsed is Dictionary:
			replay.records.append(parsed)
	return replay


func write(a_path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(a_path.get_base_dir())
	var file: FileAccess = FileAccess.open(a_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(to_bytes())
	file.close()
	return OK


static func read(a_path: String) -> ReplayFile:
	if not FileAccess.file_exists(a_path):
		return null
	return from_bytes(FileAccess.get_file_as_bytes(a_path))


## A header for `a_scenario`, stamped with `a_version`. One entry per player slot.
static func header_for(a_scenario: Scenario, a_version: String) -> Dictionary:
	var slots: Array = []
	for i: int in a_scenario.player_slots.size():
		var slot: PlayerSlot = a_scenario.player_slots[i]
		(
			slots
			. append(
				{
					"faction": slot.faction.resource_path if slot.faction != null else "",
					"difficulty": int(slot.difficulty),
					"is_bot": slot.is_bot,
					"personality": slot.personality,
					"alliance": slot.alliance,
					"start_point": a_scenario.slot_start_point(i),
				}
			)
		)
	var map: Map = a_scenario.get_node_or_null("Map") as Map
	var header: Dictionary = {
		"type": HEADER_TYPE,
		"scenario": a_scenario.scene_file_path,
		"map": map.scene_file_path if map != null else "",
		"seed": a_scenario.rng_seed,
		"slots": slots,
		"version": a_version,
	}
	# A lobby-built skirmish's map exists in no file: its recipe is what rebuilds it.
	if not a_scenario.skirmish_recipe.is_empty():
		header["skirmish"] = a_scenario.skirmish_recipe
	return header


## Why a replay with `a_header` cannot be played by this build, or "" when it can. A simulation
## change cannot be migrated, so any version but this one's is refused.
static func refusal(a_header: Dictionary, a_version: String) -> String:
	if a_header.get("type") != HEADER_TYPE:
		return "not a replay"
	var recorded: String = str(a_header.get("version", ""))
	if recorded != a_version:
		return "recorded by another version of the game (%s; this is %s)" % [recorded, a_version]
	return ""


## Why this replay cannot be played by this build, or "" when it can: another version, or a
## recording debug mode ended (gdd/systems/commands/recording-and-replay.md §Debug mode).
func playback_refusal(a_version: String) -> String:
	var refused: String = refusal(header, a_version)
	if not refused.is_empty():
		return refused
	var reason: String = invalid_reason()
	return "" if reason.is_empty() else "debug mode changed the match (%s)" % reason


## Why debug mode ended this recording, or "" when it did not.
func invalid_reason() -> String:
	for record: Dictionary in records:
		if record.get("type") == ReplayRecorder.INVALID_TYPE:
			return str(record.get("reason", "debug mode"))
	return ""


## The scenario's name as a player reads it: its scene's file name, without the extension.
func scenario_name() -> String:
	return str(header.get("scenario", "")).get_file().get_basename()


## How long the recording runs, in ticks: the last record's tick.
func length_ticks() -> int:
	var last: int = 0
	for record: Dictionary in records:
		last = maxi(last, int(record.get("tick", 0)))
	return last


## This build's version stamp: the build number, the engine, and a hash of everything
## VERSIONED_PATHS holds. Computed once per session: it walks every piece scene.
##
## TODO: the project sets no build number (`application/config/version`), so the first part is
## empty today and the content hash does all the work.
static func current_version() -> String:
	if _current_version.is_empty():
		var build: String = str(ProjectSettings.get_setting("application/config/version", ""))
		var engine: String = Engine.get_version_info().get("string", "")
		_current_version = "%s|%s|%s" % [build, engine, content_hash(VERSIONED_PATHS)]
	return _current_version


## Memoized: hashing every piece scene is a walk of hundreds of files, and the answer cannot
## change while the game runs.
static var _current_version: String = ""


## A hash of every file under `paths` (directories walked recursively, in sorted order, so the
## answer does not depend on the filesystem's listing order).
static func content_hash(paths: Array[String]) -> String:
	var files: PackedStringArray = []
	for path: String in paths:
		files.append_array(_files_under(path))
	files.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for file: String in files:
		context.update(file.to_utf8_buffer())
		context.update(FileAccess.get_file_as_bytes(file))
	return context.finish().hex_encode().substr(0, SimulationDigest.DIGEST_LENGTH)


static func _files_under(path: String) -> PackedStringArray:
	if not path.ends_with("/"):
		return PackedStringArray([path]) if FileAccess.file_exists(path) else PackedStringArray()
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if not file.ends_with(".uid") and not file.ends_with(".import"):
			out.append(path + file)
	for sub: String in dir.get_directories():
		out.append_array(_files_under(path + sub + "/"))
	return out
