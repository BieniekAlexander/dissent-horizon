extends GutTest

## The card-mode banner — a STUB surface, tested only for the two things that would make it
## worse than nothing: naming the wrong card, and covering the buttons.
##
## The second is not paranoia. A full-width strip anchored to the top of a panel grows DOWN by
## default, straight across the first row of buttons — the same mistake that drew every
## CommandableCard status bar below its card for months (CLAUDE.md §Seeing the HUD without a
## screen). GUT covers no layout, so the anchors and offsets are asserted directly.

func _banner() -> CardModeBanner:
	var banner := CardModeBanner.new()
	add_child_autofree(banner)
	return banner


func test_each_card_is_named() -> void:
	var banner: CardModeBanner = _banner()
	for family: int in [ControlBinding.CommandFamily.ACTIVE,
			ControlBinding.CommandFamily.PRODUCTION,
			ControlBinding.CommandFamily.ORDNANCE]:
		banner.show_family(family)
		assert_ne(banner.text, "", "family %d has a title" % family)


func test_every_card_is_named_and_coloured_differently() -> void:
	var titles: Dictionary = {}
	var colors: Dictionary = {}
	for family: int in CardModeBanner.MODES:
		titles[CardModeBanner.MODES[family]["title"]] = true
		colors[CardModeBanner.MODES[family]["color"]] = true
	assert_eq(titles.size(), 3, "three distinct titles")
	assert_eq(colors.size(), 3, "and three distinct colours — the tint is the peripheral cue")


func test_the_banner_sits_ABOVE_the_grid_and_never_over_it() -> void:
	var banner: CardModeBanner = _banner()
	assert_eq(banner.anchor_top, 0.0)
	assert_eq(banner.anchor_bottom, 0.0)
	assert_lt(banner.offset_top, 0.0, "it grows UPWARD from the panel's top edge")
	assert_eq(banner.offset_bottom, 0.0, "and stops exactly at it")
	assert_eq(banner.anchor_left, 0.0)
	assert_eq(banner.anchor_right, 1.0, "full width")


func test_the_banner_never_takes_a_click() -> void:
	assert_eq(_banner().mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"a strip over the command panel that ate clicks would be worse than no strip")


## Non-destructive: the blend recomputes from the panel's AUTHORED colour every time, so
## flipping cards repeatedly cannot walk the backdrop away from where it started.
func test_the_backdrop_wash_is_recomputed_not_accumulated() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.1, 0.1, 0.12)
	add_child_autofree(backdrop)
	var banner: CardModeBanner = _banner()
	banner.set_backdrop(backdrop)
	banner.show_family(ControlBinding.CommandFamily.ACTIVE)
	var once: Color = backdrop.color
	for i in 5:
		banner.show_family(ControlBinding.CommandFamily.PRODUCTION)
		banner.show_family(ControlBinding.CommandFamily.ACTIVE)
	assert_eq(backdrop.color, once, "five flips later it is exactly where one flip put it")
	assert_ne(once, Color(0.1, 0.1, 0.12), "and it did actually tint")


func test_an_unknown_family_blanks_rather_than_erroring() -> void:
	var banner: CardModeBanner = _banner()
	banner.show_family(ControlBinding.CommandFamily.ACTIVE)
	banner.show_family(1 << 9)
	assert_eq(banner.text, "", "a fourth card is a design decision, not a crash")
