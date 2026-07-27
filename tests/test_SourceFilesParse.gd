extends GutTest

## EVERY `.gd` FILE IN THE PROJECT STILL PARSES.
##
## The cheapest possible check, and the one the project most needed. On 2026-09-10 forty-two
## files were rewritten from 2-space to tab indentation at tab width 4, almost certainly by a
## Godot editor save under the per-user editor setting `text_editor/behavior/indent/type =
## tabs`. Godot refuses a file whose statement indentation changes style mid-block, so
## `damage_profile.gd` stopped parsing — and then `DamageTable` (an AUTOLOAD) failed to
## instantiate, and `Map`, `Commandable`, `Commander` and `Bot` all failed to compile behind
## it. The project was dead for hours. Nobody ran a formatter. A tool regenerated files from a
## setting nobody had looked at. See CLAUDE.md §Regenerating data.
##
## WHY A PARSE CHECK RATHER THAN AN INDENTATION CHECK. Mixing tabs and spaces is the CAUSE,
## but it is not reliably the fault: Godot tolerates a tab on a wrapped continuation line
## inside a space-indented file (`tests/test_DamageCatalog.gd` has three and parses fine), and
## it tolerates more besides. An indentation rule therefore fails on honest edits, which is
## the one thing a guard must not do (CLAUDE.md §A unit test does not assert facts about
## authored content). "Does it parse" has no false positives and catches the failure whatever
## produced it — a bad merge, a truncated write, a rename that orphaned a `class_name`.
##
## WHY THE TEST SUITE CANNOT NOTICE THIS ON ITS OWN. GUT reports a run GREEN when a test file
## fails to parse — the tests inside simply stop existing (CLAUDE.md §A skipped test file is
## invisible). And a broken file under `scripts/` shows up as a cascade of unrelated failures
## in whatever depended on it, which is a long way from the one line that says what is wrong.
##
## Sibling of `test_SuiteIntegrity`, which guards `tests/` by file TEXT; this one covers the
## whole source tree by asking the engine.

const ROOTS: Array[String] = [
	"res://scripts", "res://tests", "res://tools", "res://addons/terrain_brush",
]

## GUT is vendored third-party code and is not this project's to keep green.
const SKIP_DIRS: Array[String] = ["addons/gut", "__pycache__"]


func test_every_gd_file_in_the_project_parses() -> void:
	var broken: Array[String] = []
	for path: String in _all_gd_files():
		# CACHE_MODE_REUSE (the default) on purpose: nearly every script here is already loaded
		# by the time a test runs, so this re-reads almost nothing and, importantly, does not
		# re-run anybody's `_static_init`.
		var script := ResourceLoader.load(path, "Script") as GDScript
		# `load` does NOT return null for a script with a parse error — it hands back a GDScript
		# carrying the source and nothing else. `can_instantiate()` is what actually separates
		# "compiled" from "the engine gave up on this file"; a bare null check silently passes
		# every broken file, which is how the first draft of this test passed a tree with four
		# of them in it. (No script in this project is `@abstract`, which is the only other way
		# a healthy script answers false here.)
		if script == null or not script.can_instantiate():
			broken.append(path)

	# Loading is the measurement, so the engine errors it raises ARE the result and must not
	# also be counted as unexpected errors — that would fail this test with a stack trace
	# instead of the list of files. `handled` is GUT's supported way to say so (test.gd
	# §get_errors). A couple of unrelated static initialisers push_error on load too
	# (ControlFeedbackSounds, EntityDeathSounds); those are content gaps other tests own.
	for error: Variant in get_errors():
		error.handled = true

	assert_eq(broken, [] as Array[String],
		"these scripts do not parse — everything that depends on them is dead until they do")


func test_the_walk_actually_reaches_the_tree() -> void:
	# A guard on the guard: a walk that silently found nothing would report every file clean.
	# A ratchet floor, not a pin — it can only be too LOW to mean anything.
	var files: Array[String] = _all_gd_files()
	assert_gt(files.size(), 300, "the walk reaches the source tree")
	assert_true(files.has("res://scripts/maps/fog.gd"), "and a known file is in it")
	assert_true(files.has("res://scripts/damage/damage_table.gd"),
		"including the autoload whose failure took the project down")


#region Helpers
func _all_gd_files() -> Array[String]:
	var found: Array[String] = []
	for root: String in ROOTS:
		_walk(root, found)
	found.sort()
	return found


func _walk(a_dir: String, a_out: Array[String]) -> void:
	for skip: String in SKIP_DIRS:
		if a_dir.ends_with(skip):
			return
	var dir := DirAccess.open(a_dir)
	if dir == null:
		return
	for name: String in dir.get_directories():
		_walk("%s/%s" % [a_dir, name], a_out)
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			a_out.append("%s/%s" % [a_dir, name])
#endregion
