extends GutTest

## "Save replay" at a match's end: the name field's default, its refusals, asking before an
## overwrite, and the file it writes. gdd/systems/commands/recording-and-replay.md §Watching.

const DIR: String = "user://test_replay_save_form/"


func before_each() -> void:
	_clear()


func after_all() -> void:
	_clear()


func _clear() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _form() -> ReplaySaveForm:
	var recorder := ReplayRecorder.new()
	recorder.replay.header = {
		"type": ReplayFile.HEADER_TYPE,
		"scenario": "res://scenes/scenarios/skirmish.tscn",
		"seed": 1,
		"version": "v-test",
	}
	recorder.replay.records = [{"type": ReplayRecorder.DIGEST_TYPE, "tick": 30, "digest": "d"}]
	autofree(recorder)
	var form := ReplaySaveForm.new()
	form.directory = DIR
	add_child_autofree(form)
	form.bind(recorder)
	return form


func test_the_name_field_opens_prefilled_with_the_scenario_and_a_timestamp() -> void:
	var form: ReplaySaveForm = _form()
	assert_false(form.is_open(), "only the button until it is pressed")
	form.open()
	assert_true(form.is_open())
	assert_true(form.entered_name().begins_with("skirmish_"), form.entered_name())
	assert_eq(ReplayNames.kept_name_refusal(form.entered_name()), "", "the default is keepable")


func test_a_character_no_file_name_holds_is_refused_as_typed() -> void:
	var form: ReplaySaveForm = _form()
	form.open()
	form.type_name("best/game?")
	assert_eq(form.entered_name(), "bestgame", "taken back out of the field")
	assert_string_contains(form.status_text(), "cannot hold")


func test_an_autosave_name_is_refused() -> void:
	var form: ReplaySaveForm = _form()
	form.open()
	form.type_name("autosaved_replay_mine")
	form.save()
	assert_string_contains(form.status_text(), "autosave")
	assert_false(FileAccess.file_exists(DIR + "autosaved_replay_mine.jsonl.gz"))


func test_saving_writes_a_kept_replay_with_the_version_stamp() -> void:
	var form: ReplaySaveForm = _form()
	watch_signals(form)
	form.open()
	form.type_name("final")
	form.save()
	var path: String = DIR + "final.jsonl.gz"
	assert_signal_emitted_with_parameters(form, "saved", [path])
	var back: ReplayFile = ReplayFile.read(path)
	assert_not_null(back)
	assert_eq(back.header.get("version"), "v-test")
	assert_false(ReplayNames.is_autosave(path.get_file()), "the rotation never deletes it")


func test_a_name_already_taken_asks_before_overwriting() -> void:
	var first: ReplaySaveForm = _form()
	first.open()
	first.type_name("taken")
	first.save()
	var modified: int = FileAccess.get_modified_time(DIR + "taken.jsonl.gz")
	var form: ReplaySaveForm = _form()
	watch_signals(form)
	form.open()
	form.type_name("taken")
	form.save()
	assert_true(form.is_asking_to_overwrite(), "the first press asks")
	assert_signal_not_emitted(form, "saved")
	form.save()
	assert_signal_emitted(form, "saved", "the second press overwrites")
	assert_gte(FileAccess.get_modified_time(DIR + "taken.jsonl.gz"), modified)


func test_editing_the_name_takes_back_an_agreement_to_overwrite() -> void:
	var first: ReplaySaveForm = _form()
	first.open()
	first.type_name("taken")
	first.save()
	var form: ReplaySaveForm = _form()
	form.open()
	form.type_name("taken")
	form.save()
	form.type_name("taken")
	assert_false(form.is_asking_to_overwrite())
