extends GutTest

## The debug menu's fog picker: it writes DebugMode's fog setting, follows it when it is reset
## elsewhere, and shows only while the debug view is up.

var _row: DebugFogRow


func before_each() -> void:
	DebugMode.configure(true)
	_row = DebugFogRow.new()
	add_child_autofree(_row)


func after_each() -> void:
	DebugMode.configure(false)


## Two frames: a resumed await runs before the frame's own _process.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_choosing_shown_keeps_the_fog_while_the_view_is_up() -> void:
	DebugMode.toggle()
	_row.choose(DebugFogRow.Choice.SHOWN)
	assert_false(DebugMode.lifts_fog())
	_row.choose(DebugFogRow.Choice.LIFTED)
	assert_true(DebugMode.lifts_fog())


func test_it_follows_a_reset_from_outside() -> void:
	_row.choose(DebugFogRow.Choice.SHOWN)
	DebugMode.configure(true)
	await _settle()
	var picker: OptionButton = _row.get_node("Picker")
	assert_eq(picker.get_selected_id(), DebugFogRow.Choice.LIFTED)


func test_it_shows_only_while_the_debug_view_is_up() -> void:
	await _settle()
	assert_false(_row.visible, "allowed but not toggled on")
	DebugMode.toggle()
	await _settle()
	assert_true(_row.visible)
