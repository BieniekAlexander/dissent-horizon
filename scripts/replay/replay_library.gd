class_name ReplayLibrary
extends RefCounted

## The replays on disk, as the start screen lists them, and how one is opened for playback.
## gdd/systems/commands/recording-and-replay.md §Watching.
##
## A replay from another version, or one debug mode ended, is LISTED like any other and refused
## when it is opened: the list is what is on disk, and the refusal says why it cannot play.


## Every replay file under `a_directory`, newest first: `{file, path, modified, is_autosave}`.
## Autosaves and kept replays alike; anything without the replay extension is not listed.
static func entries(a_directory: String = ReplayFile.DIRECTORY) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var suffix: String = "." + ReplayFile.EXTENSION
	for file: String in DirAccess.get_files_at(a_directory):
		if not file.ends_with(suffix):
			continue
		var path: String = a_directory.path_join(file)
		(
			out
			. append(
				{
					"file": file,
					"path": path,
					"modified": FileAccess.get_modified_time(path),
					"is_autosave": ReplayNames.is_autosave(file),
				}
			)
		)
	return ordered(out)


## `a_entries` newest first; ties (a second's resolution) by file name, so the order is stable.
static func ordered(a_entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = a_entries.duplicate()
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["modified"]) != int(b["modified"]):
				return int(a["modified"]) > int(b["modified"])
			return String(a["file"]) < String(b["file"])
	)
	return out


## How an entry reads in the list: a kept replay by its name, an autosave by when it was
## written ("Autosave · 2026-10-08 12:00 UTC").
static func label_for(a_entry: Dictionary) -> String:
	var file: String = a_entry["file"]
	var stamp: String = ReplayNames.autosave_timestamp(file)
	if stamp.is_empty():
		return file.trim_suffix("." + ReplayFile.EXTENSION)
	return (
		"Autosave · %s-%s-%s %s:%s UTC"
		% [
			stamp.substr(0, 4),
			stamp.substr(4, 2),
			stamp.substr(6, 2),
			stamp.substr(9, 2),
			stamp.substr(11, 2),
		]
	)


## The scenario `a_path` records, set up to play the recording back and not yet in the tree —
## `{scenario}` — or `{refusal}` saying why it cannot be: not a replay, another version, a
## recording debug mode ended, or a scenario this build no longer has. The caller owns a
## returned scenario, and frees it if it does not add it to the tree.
static func prepare_playback(a_path: String) -> Dictionary:
	var replay: ReplayFile = ReplayFile.read(a_path)
	if replay == null:
		return {"refusal": "%s is not a replay" % a_path.get_file()}
	var refused: String = replay.playback_refusal(ReplayFile.current_version())
	if not refused.is_empty():
		return {"refusal": "This replay cannot be played: %s." % refused}
	# A lobby-built skirmish is rebuilt from its recipe — its map was generated, not saved.
	# Blocking: generation takes seconds. TODO: generate off the main thread as the lobby does.
	var recipe: Variant = replay.header.get("skirmish")
	if recipe is Dictionary:
		var built: Dictionary = SkirmishLauncher.launch(recipe)
		if built.has("refusal"):
			return {"refusal": "This replay's skirmish cannot be rebuilt: %s." % built["refusal"]}
		(built["scenario"] as Scenario).replay_to_play = replay
		return built
	var scene_path: String = str(replay.header.get("scenario", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return {"refusal": "This replay's scenario is not in this build: '%s'." % scene_path}
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	if not root is Scenario:
		root.free()
		return {"refusal": "'%s' is not a scenario." % scene_path}
	var scenario: Scenario = root as Scenario
	scenario.replay_to_play = replay
	return {"scenario": scenario}
