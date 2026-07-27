extends GutTest

## Guards the one failure this suite cannot report on its own: a test file that does not PARSE.
##
## GUT skips an unparseable script and still prints a green summary, so the tests inside it stop
## running and nothing says so — the count drops and nobody is watching the count. It has
## happened twice. Most recently a piece rename moved two entity scenes and left four files
## preloading the old paths, which took 66 tests out of the run while the suite reported
## "17 failing" exactly as before.
##
## THE ASSERTIONS ARE OVER FILE TEXT, NOT OVER LOADED SCRIPTS, and that is the whole point: a
## file that cannot be parsed cannot be loaded either, so anything that inspects it by loading
## it would be blind to precisely the case this exists for. Reading the text works whether or
## not the file compiles, and it works from a file that DOES parse.
##
## See also test_TscnDoc.gd's roster sweeps, which ask the same question of entity SCENES. This
## one asks it of the suite itself.

const TESTS_DIR: String = "res://tests"

## `preload("res://…")` and `load("res://…")`, capturing the path. Deliberately text-matched
## rather than resolved through the parser — see the note above.
const RESOURCE_CALL: String = "(?:pre)?load\\(\\s*\"(res://[^\"]+)\""

## A path built by concatenation or interpolation cannot be checked statically and is skipped
## rather than guessed at.
const DYNAMIC_MARKERS: Array[String] = ["%s", "{", "+"]


func _test_scripts() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	assert_not_null(dir, "the tests directory is readable")
	if dir == null:
		return paths
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			paths.append("%s/%s" % [TESTS_DIR, file])
	return paths


## Every `res://` path a script names literally, ignoring comments.
##
## COMMENT LINES ARE STRIPPED FIRST, and this file is why: its own doc comment describes the
## pattern it looks for, so scanning the raw text made it match itself. Beyond that self-
## reference it is simply correct — a path inside a comment is not a reference, and a
## commented-out `preload` is often exactly a path that has deliberately stopped existing.
func _referenced_paths(a_script_path: String) -> Array[String]:
	var code_lines: Array[String] = []
	for line: String in FileAccess.get_file_as_string(a_script_path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			code_lines.append(line)
	var found: Array[String] = []
	var re := RegEx.create_from_string(RESOURCE_CALL)
	for m: RegExMatch in re.search_all("\n".join(code_lines)):
		var path: String = m.get_string(1)
		var is_dynamic: bool = false
		for marker: String in DYNAMIC_MARKERS:
			if path.contains(marker):
				is_dynamic = true
		if not is_dynamic:
			found.append(path)
	return found


func test_every_resource_a_test_file_names_actually_exists() -> void:
	# The direct guard. A missing path here is a test file that is about to stop parsing (for a
	# file-scope `preload`) or to fail at run time (for an inline `load`) — and the preload case
	# takes the whole file out of the run silently.
	var missing: Array[String] = []
	for script_path: String in _test_scripts():
		for path: String in _referenced_paths(script_path):
			if not ResourceLoader.exists(path):
				missing.append("%s -> %s" % [script_path.get_file(), path])
	assert_eq(missing, [] as Array[String],
		"every res:// path named in tests/ resolves; a missing one silently removes a whole file")


func test_the_suite_has_not_quietly_shrunk() -> void:
	# A floor, not an exact count — tests are added constantly, and pinning the exact number
	# would make this file fail on every honest addition. What it catches is the number going
	# DOWN, which is the direction that means a file stopped being collected.
	#
	# Counts files rather than tests: a file is the unit GUT skips.
	var scripts: Array[String] = _test_scripts()
	assert_gte(scripts.size(), SUITE_FLOOR,
		"tests/ holds at least %d scripts; a drop means a file was deleted or stopped parsing" % SUITE_FLOOR)

## Raise this when the suite grows past it by a comfortable margin. It is a ratchet against
## silent LOSS, so it is set just under the real count rather than at it.
const SUITE_FLOOR: int = 130


func test_a_non_gut_script_in_tests_is_named_so_it_reads_as_deliberate() -> void:
	# `tests/` holds one script that is NOT a test — a `SceneTree` tool committed there — and GUT
	# correctly ignores it. That is fine, but it is indistinguishable at a glance from a file that
	# is being skipped by accident, which is the confusion this whole file exists to prevent. So
	# the convention is an underscore prefix: a leading `_` means "deliberately not collected".
	var uncollected: Array[String] = []
	for script_path: String in _test_scripts():
		var text: String = FileAccess.get_file_as_string(script_path)
		var is_gut_test: bool = text.contains("extends GutTest")
		if not is_gut_test and not script_path.get_file().begins_with("_"):
			uncollected.append(script_path.get_file())
	assert_eq(uncollected, [] as Array[String],
		"a script in tests/ that does not extend GutTest is prefixed with _ so the skip reads as intended")


func test_no_test_file_mixes_tabs_and_spaces_for_indentation() -> void:
	# GDScript refuses a file that indents with both, and the refusal is a PARSE error — so the
	# file is skipped in silence and its tests simply stop existing. That is this file's whole
	# subject, and it caught the author of this file out within the hour: appending a
	# space-indented block to a tab-indented test made GUT report "Nothing was run."
	#
	# The rule is per FILE, not project-wide: tests/ is overwhelmingly tabs and scripts/ is
	# overwhelmingly two spaces, and a handful of older test files use spaces throughout.
	# Consistency within a file is what the parser demands, so consistency within a file is
	# what this asserts.
	# ONLY STATEMENT LINES COUNT. A line continued inside brackets may be indented however it
	# likes — GDScript is only strict about the indentation that opens a block — so a
	# tab-aligned argument in an otherwise space-indented file is legal, and `test_MainMenu.gd`
	# is exactly that. Counting every line flagged it as broken when it parses perfectly well.
	var mixed: Array[String] = []
	for script_path: String in _test_scripts():
		var has_tab: bool = false
		var has_space: bool = false
		var depth: int = 0
		for line: String in FileAccess.get_file_as_string(script_path).split("\n"):
			if not line.strip_edges().is_empty() and depth == 0:
				if line.begins_with("\t"):
					has_tab = true
				elif line.begins_with(" "):
					has_space = true
			depth = maxi(0, depth + _bracket_delta(line))
		if has_tab and has_space:
			mixed.append(script_path.get_file())
	assert_eq(mixed, [] as Array[String],
		"no test file indents with both tabs and spaces; GDScript rejects the file and GUT skips it silently")


## How many brackets `line` opens minus how many it closes, with string literals and trailing
## comments removed first so a bracket inside either cannot throw the count off. Approximate by
## design — it only has to be right often enough to tell a continuation line from a statement.
static func _bracket_delta(line: String) -> int:
	var code: String = line
	for pattern: String in ["\"[^\"]*\"", "'[^']*'"]:
		code = RegEx.create_from_string(pattern).sub(code, "", true)
	var hash_at: int = code.find("#")
	if hash_at >= 0:
		code = code.substr(0, hash_at)
	var delta: int = 0
	for c: String in code:
		if c in ["(", "[", "{"]:
			delta += 1
		elif c in [")", "]", "}"]:
			delta -= 1
	return delta
