extends GutTest

## The replay file and its names: encoding and decoding, the header, refusing another version,
## recognising an autosave, and which autosave the rotation deletes.
## gdd/systems/commands/recording-and-replay.md §Testing.


func _replay() -> ReplayFile:
	var replay := ReplayFile.new()
	replay.header = {"type": ReplayFile.HEADER_TYPE, "seed": 7, "version": "v1", "slots": []}
	replay.records = [
		{"type": "order", "tick": 30, "commander": 1, "command": "move"},
		{"type": "digest", "tick": 30, "digest": "abc"},
	]
	return replay


func test_a_replay_round_trips_through_its_bytes() -> void:
	var back: ReplayFile = ReplayFile.from_bytes(_replay().to_bytes())
	assert_not_null(back)
	assert_eq(back.header.get("seed"), 7.0, "JSON numbers come back as floats")
	assert_eq(back.records.size(), 2)
	assert_eq(back.records[0].get("command"), "move")


func test_the_bytes_are_plain_gzip_of_json_lines() -> void:
	var text: String = (
		_replay()
		. to_bytes()
		. decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		. get_string_from_utf8()
	)
	var lines: PackedStringArray = text.split("\n", false)
	assert_eq(lines.size(), 3, "a header and two records")
	assert_true(JSON.parse_string(lines[0]) is Dictionary)


func test_bytes_without_a_header_first_are_not_a_replay() -> void:
	var bytes: PackedByteArray = '{"type":"order","tick":1}\n'.to_utf8_buffer().compress(
		FileAccess.COMPRESSION_GZIP
	)
	assert_null(ReplayFile.from_bytes(bytes))


func test_a_replay_from_another_version_is_refused() -> void:
	var header: Dictionary = _replay().header
	assert_eq(ReplayFile.refusal(header, "v1"), "")
	assert_string_contains(ReplayFile.refusal(header, "v2"), "another version")
	assert_eq(ReplayFile.refusal({"type": "order"}, "v1"), "not a replay")


func test_the_content_hash_moves_with_the_content() -> void:
	var dir: String = "user://test_replay_hash/"
	DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(dir + "a.txt", FileAccess.WRITE)
	file.store_string("one")
	file.close()
	var paths: Array[String] = [dir]
	var before: String = ReplayFile.content_hash(paths)
	assert_eq(ReplayFile.content_hash(paths), before, "the same content hashes the same")
	file = FileAccess.open(dir + "a.txt", FileAccess.WRITE)
	file.store_string("two")
	file.close()
	assert_ne(ReplayFile.content_hash(paths), before)
	DirAccess.remove_absolute(dir + "a.txt")
	DirAccess.remove_absolute(dir)


func test_an_autosave_is_known_by_its_name() -> void:
	var name: String = ReplayNames.autosave_name(0)
	assert_eq(name, "autosaved_replay_19700101T000000Z.jsonl.gz")
	assert_true(ReplayNames.is_autosave(name))
	assert_false(ReplayNames.is_autosave("autosaved_replay_yesterday.jsonl.gz"), "a bad timestamp")
	assert_false(ReplayNames.is_autosave("my_game_19700101T000000Z.jsonl.gz"), "no prefix")


func test_the_rotation_deletes_the_oldest_to_keep_three() -> void:
	var names := PackedStringArray(
		[
			ReplayNames.autosave_name(300),
			ReplayNames.autosave_name(100),
			"kept_by_hand.jsonl.gz",
			ReplayNames.autosave_name(200),
		]
	)
	assert_eq(
		ReplayNames.autosaves_to_delete(names),
		PackedStringArray([ReplayNames.autosave_name(100)]),
		"three exist, so writing a fourth deletes the oldest — never a kept one"
	)
	assert_eq(ReplayNames.autosaves_to_delete(PackedStringArray()).size(), 0)


func test_a_kept_name_refuses_what_a_file_or_the_rotation_cannot_take() -> void:
	assert_eq(ReplayNames.kept_name_refusal("skirmish_win"), "")
	assert_ne(ReplayNames.kept_name_refusal("a/b"), "")
	assert_ne(ReplayNames.kept_name_refusal("autosaved_replay_mine"), "")
	assert_ne(ReplayNames.kept_name_refusal("  "), "")
	assert_eq(ReplayNames.default_kept_name("s1", 0), "s1_19700101T000000Z")
