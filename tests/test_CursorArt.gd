extends GutTest

## Every cursor SHAPE the interface asks for must have game art registered against it.
##
## RTSController swaps the world cursor by re-registering an image against CURSOR_ARROW
## (_apply_cursor), so any OTHER shape arrives with nothing behind it and the OS draws its own
## pointer. A Control marking itself clickable with `mouse_default_cursor_shape` therefore
## replaced the game's cursor for as long as the mouse was over it.
##
## The remedy is ART for the shape (_register_hud_cursor), not a ban on asking for one — and
## THAT is what this pins, because banning it was tried and made things worse: a shape change
## is the one thing that reliably re-pushes a custom cursor to the OS (see _apply_cursor on
## why re-sending an unchanged one is a no-op), so HUD buttons crossing between two shapes had
## been quietly repairing the cursor all along. Removing them removed the repair.
##
## Asserted over FILE TEXT: the lines run inside button factories that need a live panel, and
## the rule is about what the source asks for.
##
## Full write-up: gdd/systems/ux/ui/hud-layout.md §The cursor is game art.

const INTERFACE_DIR: String = "res://scripts/interface"

## The shapes RTSController registers an image for. CURSOR_ARROW is the world cursor
## (_apply_cursor); CURSOR_POINTING_HAND is the HUD's clickable mark (_register_hud_cursor).
const SHAPES_WITH_ART: Array[String] = ["CURSOR_ARROW", "CURSOR_POINTING_HAND"]


func _script_paths(a_dir: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(a_dir)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			found.append("%s/%s" % [a_dir, file])
	for sub: String in dir.get_directories():
		found.append_array(_script_paths("%s/%s" % [a_dir, sub]))
	return found


## Code lines only. The rule is explained in comments in the very files it governs, so
## scanning raw text would match the prose rather than the assignments.
func _code_lines(a_script_path: String) -> Array[String]:
	var found: Array[String] = []
	for line: String in FileAccess.get_file_as_string(a_script_path).split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("#"):
			found.append(trimmed)
	return found


func test_no_control_asks_for_a_shape_with_no_art_behind_it() -> void:
	var re := RegEx.create_from_string("mouse_default_cursor_shape\\s*=\\s*Control\\.(\\w+)")
	var offenders: Array[String] = []
	var seen: int = 0
	for script_path: String in _script_paths(INTERFACE_DIR):
		for line: String in _code_lines(script_path):
			var m: RegExMatch = re.search(line)
			if m == null:
				continue
			seen += 1
			if not SHAPES_WITH_ART.has(m.get_string(1)):
				offenders.append("%s -> %s" % [script_path.get_file(), m.get_string(1)])
	assert_gt(seen, 0, "guards the fixture: the HUD does mark its clickable controls")
	assert_eq(
		offenders,
		[] as Array[String],
		"a shape with no registered image shows the OS cursor instead of the game's"
	)


## The other half of the same rule: the shape the HUD names is one the controller actually
## registers. A rename on either side breaks the pair, and the symptom is a cosmetic bug
## nobody would think to trace back to a constant.
func test_the_hud_shape_is_one_the_controller_registers() -> void:
	assert_true(SHAPES_WITH_ART.has("CURSOR_POINTING_HAND"))
	assert_eq(
		Control.CURSOR_POINTING_HAND,
		Input.CURSOR_POINTING_HAND,
		"Control and Input agree on the shape's value, which _register_hud_cursor relies on"
	)
	var source: String = FileAccess.get_file_as_string("res://scripts/interface/rts_controller.gd")
	assert_true(
		source.contains("Input.CURSOR_POINTING_HAND"),
		"_register_hud_cursor still gives that shape an image"
	)


func test_every_cursor_image_the_controller_can_show_is_loadable() -> void:
	for cursor: Resource in [
		RTSController.FREE_CURSOR,
		RTSController.SELECTION_CURSOR,
		RTSController.ATTACK_CURSOR,
		RTSController.INVALID_CURSOR,
		RTSController.UNKNOWN_CURSOR
	]:
		assert_not_null(cursor)
