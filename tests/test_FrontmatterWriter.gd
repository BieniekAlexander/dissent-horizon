extends GutTest

## The debug tuning editor's Save path: values written into a doc's frontmatter, touching only
## the lines that hold them. Every fixture is built here — no shipped doc is read.

const Writer := preload("res://tools/spec_import/frontmatter_writer.gd")
const SpecFrontmatter := preload("res://tools/spec_import/frontmatter.gd")

const DOC: String = (
	"---\n"
	+ "kind: Entity\n"
	+ "title: Fixture\n"
	+ "defense:\n"
	+ "  hp: 160  # the tuning target\n"
	+ "  armour: MEDIUM\n"
	+ "movement: {speed: SLOW, turn_rate: 1080}\n"
	+ "weapons:\n"
	+ "  - name: Rifle\n"
	+ "    emits:\n"
	+ "      id: fixture_bullet\n"
	+ "      damage: 12\n"
	+ "      phases:\n"
	+ "        - motion: {preset: BALLISTIC, speed: FAST}\n"
	+ "          lifespan: 0\n"
	+ "        - lifespan: 1\n"
	+ "          payload: once\n"
	+ "    split_time: 1.5\n"
	+ "    reach: {ground: ground_range_medium, air: air_range_long}\n"
	+ "exceptions:\n"
	+ "  some_rule: >-\n"
	+ "    Kept as written.\n"
	+ "---\n"
	+ "# Prose\n"
	+ "\n"
	+ "Body text: not frontmatter, never touched.\n"
)


func _write(a_path: Array, a_value: Variant, a_text: String = DOC) -> String:
	var result: Dictionary = Writer.set_value(a_text, a_path, a_value)
	assert_true(result["ok"], "the edit succeeds: %s" % result["error"])
	return result["text"]


func _read(a_text: String, a_path: Array) -> Variant:
	return Writer.value_at(SpecFrontmatter.parse(a_text)["data"], a_path)


func _changed_lines(a_before: String, a_after: String) -> Array:
	var before: PackedStringArray = a_before.split("\n")
	var after: PackedStringArray = a_after.split("\n")
	var changed: Array = []
	for i: int in mini(before.size(), after.size()):
		if before[i] != after[i]:
			changed.append(after[i])
	return changed


func test_a_scalar_is_rewritten_on_its_own_line_keeping_its_comment() -> void:
	var text: String = _write(["defense", "hp"], 200)
	assert_eq(_changed_lines(DOC, text), ["  hp: 200  # the tuning target"])


func test_writing_the_same_value_changes_no_bytes() -> void:
	assert_eq(_write(["defense", "hp"], 160.0), DOC)


func test_a_flow_map_value_is_edited_in_place() -> void:
	var text: String = _write(["movement", "speed"], "SLUGGISH")
	assert_eq(_changed_lines(DOC, text), ["movement: {speed: SLUGGISH, turn_rate: 1080}"])


func test_a_key_missing_from_a_flow_map_is_appended_to_it() -> void:
	var text: String = _write(["movement", "max_acceleration"], 2.5)
	assert_eq(_read(text, ["movement", "max_acceleration"]), 2.5)
	assert_eq(_read(text, ["movement", "speed"]), "SLOW", "the other keys are kept")


func test_a_value_inside_a_list_item_is_reached_by_index() -> void:
	var text: String = _write(["weapons", 0, "split_time"], 0.75)
	assert_eq(_changed_lines(DOC, text), ["    split_time: 0.75"])


func test_the_first_key_of_a_list_item_shares_the_dash_line() -> void:
	var text: String = _write(["weapons", 0, "name"], "Carbine")
	assert_eq(_changed_lines(DOC, text), ["  - name: Carbine"])


func test_a_flow_map_inside_a_list_item_is_edited_in_place() -> void:
	var text: String = _write(["weapons", 0, "reach", "ground"], "ground_range_long")
	assert_eq(
		_read(text, ["weapons", 0, "reach"]),
		{"ground": "ground_range_long", "air": "air_range_long"}
	)


func test_an_inline_emission_is_reached_through_its_weapon() -> void:
	var text: String = _write(["weapons", 0, "emits", "damage"], 15)
	assert_eq(_changed_lines(DOC, text), ["      damage: 15"])


func test_a_phase_motion_is_edited_inside_its_flow_map() -> void:
	var text: String = _write(["weapons", 0, "emits", "phases", 0, "motion", "gravity"], 3)
	assert_eq(
		_read(text, ["weapons", 0, "emits", "phases", 0, "motion"]),
		{"preset": "BALLISTIC", "speed": "FAST", "gravity": 3}
	)


func test_a_new_key_lands_in_canonical_order() -> void:
	var text: String = _write(["defense", "frame"], "BIO")
	var lines: PackedStringArray = text.split("\n")
	var armour: int = lines.find("  armour: MEDIUM")
	assert_eq(lines[armour + 1], "  frame: BIO", "frame follows armour, as SpecSchema orders it")


func test_a_missing_nest_is_created() -> void:
	var text: String = _write(["senses", "vision"], "vision_ground_small")
	assert_eq(_read(text, ["senses", "vision"]), "vision_ground_small")


func test_a_whole_phase_list_is_rewritten() -> void:
	var phases: Array = [
		{
			"motion": {"preset": "LINEAR", "speed": "RAPID"},
			"lifespan": 2,
			"impact_mask": ["ground"]
		},
		{"lifespan": 0, "payload": "once"},
		{"lifespan": 3, "payload": 0.5},
	]
	var text: String = _write(["weapons", 0, "emits", "phases"], phases)
	assert_eq(_read(text, ["weapons", 0, "emits", "phases"]), phases)
	assert_eq(_read(text, ["weapons", 0, "split_time"]), 1.5, "the weapon's own keys are kept")


func test_a_value_is_removed_from_a_block_and_from_a_flow_map() -> void:
	var text: String = Writer.remove_value(DOC, ["defense", "armour"])["text"]
	assert_null(_read(text, ["defense", "armour"]))
	text = Writer.remove_value(text, ["movement", "turn_rate"])["text"]
	assert_eq(_read(text, ["movement"]), {"speed": "SLOW"})


func test_prose_is_written_as_a_folded_block() -> void:
	var reason: String = "Tuned in the debug editor: this unit is meant to be faster than its class."
	var text: String = _write(["exceptions", "another_rule"], reason)
	assert_eq(_read(text, ["exceptions", "another_rule"]), reason)
	assert_eq(_read(text, ["exceptions", "some_rule"]), "Kept as written.")


func test_the_body_after_the_frontmatter_is_never_touched() -> void:
	var text: String = _write(["defense", "hp"], 1)
	assert_true(text.ends_with("# Prose\n\nBody text: not frontmatter, never touched.\n"))


func test_a_path_through_a_scalar_is_refused_and_the_doc_returned_unchanged() -> void:
	var result: Dictionary = Writer.set_value(DOC, ["title", "nested"], 1)
	assert_false(result["ok"])
	assert_eq(result["text"], DOC)
