extends GutTest

## The spectator HUD's category picker: it writes the overlay's category, follows it when it is
## changed elsewhere, and shows only while the debug view is up.

var _bar: BotDebugCategoryBar


func before_each() -> void:
	BotDebugOverlay.active_category = BotDebugOverlay.DEFAULT_CATEGORY
	_bar = BotDebugCategoryBar.new()
	add_child_autofree(_bar)


func after_each() -> void:
	DebugMode.configure(false)
	BotDebugOverlay.active_category = BotDebugOverlay.DEFAULT_CATEGORY


func test_it_lists_every_category() -> void:
	var picker: OptionButton = _bar.get_node("Picker")
	assert_eq(picker.item_count, BotDebugOverlay.CATEGORY_LABELS.size())


func test_choosing_a_category_sets_the_overlays() -> void:
	_bar.choose(BotDebugOverlay.Category.ENEMY_PICTURE)
	assert_eq(BotDebugOverlay.active_category, BotDebugOverlay.Category.ENEMY_PICTURE)


func test_it_follows_a_category_set_elsewhere() -> void:
	BotDebugOverlay.active_category = BotDebugOverlay.Category.OFF
	await _settle()
	var picker: OptionButton = _bar.get_node("Picker")
	assert_eq(picker.get_selected_id(), BotDebugOverlay.Category.OFF)


func test_it_shows_only_while_the_debug_view_is_up() -> void:
	DebugMode.configure(true)
	await _settle()
	assert_false(_bar.visible, "allowed but not toggled on")
	DebugMode.toggle()
	await _settle()
	assert_true(_bar.visible)


## Two frames: a resumed await runs before the frame's own _process.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
