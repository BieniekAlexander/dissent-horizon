class_name SaveGame
extends RefCounted

## A SAVED GAME: a SNAPSHOT of the whole simulation on the tick it was saved on
## (SimulationSnapshot), with a digest of that state, and the match's replay so far — the seed,
## the slots and every order applied — carried for the recorder, so a recording of a loaded match
## still holds the whole match. Loading builds the scenario, lays the snapshot over it and hands
## the match to the player (SaveResume). gdd/systems/commands/saved-games.md.
##
## The bytes are a replay's (ReplayFile): gzipped JSON lines, the header first, the snapshot the
## last record. A save from another version of the game is refused, as a replay is.

## Where saves live.
const DIRECTORY: String = "user://saves/"
const EXTENSION: String = "sav"
## The one AUTOSAVE: every autosave overwrites it. A player keeps one by renaming the file.
const AUTOSAVE_NAME: String = "autosave"
## The header fields a save adds to a replay's.
const SAVE_TICK_KEY: String = "save_tick"
const SAVE_DIGEST_KEY: String = "save_digest"
const SAVED_AT_KEY: String = "saved_at"
const CAMERA_KEY: String = "camera"
const CONTROL_GROUPS_KEY: String = "control_groups"
## The record type the snapshot is written as. A record rather than a header field, so listing the
## saves reads only their small headers.
const SNAPSHOT_TYPE: String = "snapshot"


static func path_for(a_name: String, a_directory: String = DIRECTORY) -> String:
	return a_directory.path_join("%s.%s" % [a_name, EXTENSION])


static func autosave_path(a_directory: String = DIRECTORY) -> String:
	return path_for(AUTOSAVE_NAME, a_directory)


## Why `a_scenario` cannot be saved now, or "" when it can.
static func refusal_to_save(a_scenario: Scenario) -> String:
	if a_scenario == null or a_scenario.recorder == null or a_scenario.order_stream == null:
		return "there is no match to save"
	if a_scenario.is_playback():
		return "a replay is watched, not played"
	if a_scenario.is_networked():
		return "a networked match cannot be saved"
	if a_scenario.recorder.is_invalid:
		return "debug mode changed this match"
	if a_scenario.is_resuming():
		return "the save is still loading"
	if a_scenario.is_match_over():
		return "the match is over"
	return ""


## The save of `a_scenario` as it stands: taken between ticks, which is when the world is held
## (the pause menu) and when a requested autosave is written (ReplayRecorder, at the start of a
## tick). Null when it cannot be saved (refusal_to_save).
static func of(a_scenario: Scenario) -> ReplayFile:
	if not refusal_to_save(a_scenario).is_empty():
		return null
	var save := ReplayFile.new()
	save.header = a_scenario.recorder.replay.header.duplicate(true)
	save.header["version"] = ReplayFile.current_version()
	save.header[SAVE_TICK_KEY] = a_scenario.tick
	save.header[SAVE_DIGEST_KEY] = SimulationDigest.of(a_scenario)
	save.header[SAVED_AT_KEY] = int(Time.get_unix_time_from_system())
	var camera: Variant = _camera_focus(a_scenario)
	if camera != null:
		save.header[CAMERA_KEY] = [(camera as Vector2).x, (camera as Vector2).y]
	var controller: RTSController = controller_of(a_scenario)
	if controller != null:
		save.header[CONTROL_GROUPS_KEY] = controller.control_group_serials()
	save.records = a_scenario.recorder.replay.records.duplicate(true)
	save.records.append({"type": SNAPSHOT_TYPE, "state": SimulationSnapshot.capture(a_scenario)})
	return save


## Write `a_scenario` to `a_path`.
static func write(a_scenario: Scenario, a_path: String) -> Error:
	var save: ReplayFile = of(a_scenario)
	if save == null:
		return ERR_UNAVAILABLE
	return save.write(a_path)


## The snapshot `a_save` holds, or an empty dictionary when it holds none.
static func snapshot_of(a_save: ReplayFile) -> Dictionary:
	for record: Dictionary in a_save.records:
		if record.get("type") == SNAPSHOT_TYPE:
			return record.get("state", {})
	return {}


## `a_save`'s replay records, its snapshot left out: what the recorder carries on from.
static func replay_records_of(a_save: ReplayFile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Dictionary in a_save.records:
		if record.get("type") != SNAPSHOT_TYPE:
			out.append(record)
	return out


## The tick `a_save` was saved on, or -1 when it is not a save.
static func save_tick(a_save: ReplayFile) -> int:
	return int(a_save.header.get(SAVE_TICK_KEY, -1)) if a_save != null else -1


## Why the file at `a_path` cannot be loaded, or "" when it can.
static func refusal_to_load(a_save: ReplayFile, a_path: String) -> String:
	if a_save == null or save_tick(a_save) < 0:
		return "%s is not a saved game" % a_path.get_file()
	var refused: String = a_save.playback_refusal(ReplayFile.current_version())
	if not refused.is_empty():
		return "This save cannot be loaded: %s." % refused
	return "%s holds no snapshot" % a_path.get_file() if snapshot_of(a_save).is_empty() else ""


## The scenario the save at `a_path` resumes, set up to be restored to it and not yet in the tree
## — `{scenario}` — or `{refusal}`. The caller owns a returned scenario.
static func prepare_resume(a_path: String) -> Dictionary:
	var save: ReplayFile = ReplayFile.read(a_path)
	var refused: String = refusal_to_load(save, a_path)
	if not refused.is_empty():
		return {"refusal": refused}
	var built: Dictionary = ReplayLibrary.build_scenario_for(save)
	if built.has("scenario"):
		(built["scenario"] as Scenario).save_to_resume = save
	return built


## Every save under `a_directory`, newest first: `{file, path, modified, is_autosave, name}`.
static func entries(a_directory: String = DIRECTORY) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(a_directory):
		return out
	var suffix: String = "." + EXTENSION
	for file: String in DirAccess.get_files_at(a_directory):
		if not file.ends_with(suffix):
			continue
		var path: String = a_directory.path_join(file)
		var name: String = file.trim_suffix(suffix)
		(
			out
			. append(
				{
					"file": file,
					"path": path,
					"name": name,
					"modified": FileAccess.get_modified_time(path),
					"is_autosave": name == AUTOSAVE_NAME,
				}
			)
		)
	return ReplayLibrary.ordered(out)


## How a save reads in a list: its name, the autosave so called.
static func label_for(a_entry: Dictionary) -> String:
	return "Autosave" if bool(a_entry.get("is_autosave", false)) else str(a_entry["name"])


## A file name a player may give a save, or "" when `a_name` cannot be one: not empty, not the
## autosave's, and only letters, digits, spaces, dashes and underscores.
static func valid_name(a_name: String) -> String:
	var name: String = a_name.strip_edges()
	if name.is_empty() or name == AUTOSAVE_NAME:
		return ""
	var allowed := RegEx.create_from_string("^[A-Za-z0-9 _-]+$")
	return name if allowed.search(name) != null else ""


## The local player's controller, or null in a session nobody plays (a headless match, a replay).
static func controller_of(a_scenario: Scenario) -> RTSController:
	var player: Commander = a_scenario.local_player()
	return player.get_node_or_null("Controller") as RTSController if player != null else null


## Where the local player's camera looks, on the ground, or null with no camera.
static func _camera_focus(a_scenario: Scenario) -> Variant:
	var viewport: Viewport = a_scenario.get_viewport() if a_scenario.is_inside_tree() else null
	var camera := viewport.get_camera_3d() as RTSCamera3D if viewport != null else null
	return camera.ground_focus() if camera != null else null
