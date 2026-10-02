extends GutTest

## The per-piece info row and the status-effect row: WHICH widgets a piece gets, and the
## rule that a widget which does not apply is not drawn at all.
##
## Both rows are single-selection only. A mixed group has no single answer to "how fast is
## it", and a row that averaged one would describe a unit that is not on the field.
##
## The COPY is not pinned here — tooltip wording is content and changes freely
## (CLAUDE.md §A unit test does not assert facts about authored content). What is pinned is
## that a widget exists when the piece has the property behind it, and does not when it
## does not.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_InfoWidgets.gd -gexit

## Fake pieces: an anti-air gun, and a builder.
const TURRET_SCENE: Dictionary = {"structure": true, "vision": 10.0, "weapon": {"air": 8.0}}
const WORKER_SCENE: Dictionary = FakePieces.BUILDER

var _row: InfoWidgetRow
var _effects: ConditionRow


func before_each() -> void:
	_row = InfoWidgetRow.new()
	add_child_autofree(_row)
	_effects = ConditionRow.new()
	add_child_autofree(_effects)


func _piece(a_options: Dictionary) -> Commandable:
	var piece: Commandable = FakePieces.make(a_options) as Commandable
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	return piece


func _captions() -> Array[String]:
	var out: Array[String] = []
	for child: Node in _row.get_children():
		out.append(String(child.name))
	return out


# --- Which widgets a piece gets ------------------------------------------------------


func test_a_single_selection_draws_the_row() -> void:
	_row.update([_piece(TURRET_SCENE)])
	assert_true(_row.visible)
	assert_gt(_row.get_child_count(), 0)


func test_a_mixed_selection_draws_nothing() -> void:
	_row.update([_piece(TURRET_SCENE), _piece(WORKER_SCENE)])
	assert_false(_row.visible, "there is no single piece to describe")


func test_an_empty_selection_draws_nothing() -> void:
	_row.update([])
	assert_false(_row.visible)


func test_a_structure_gets_no_movement_widget() -> void:
	# The rule the whole row turns on: a card reading "movement: —" would teach the player
	# that the row is full of blanks rather than that this piece is stationary.
	_row.update([_piece(TURRET_SCENE)])
	assert_does_not_have(_captions(), "Widget_Speed")
	assert_has(_captions(), "Widget_Hp", "but it does have hit points")


func test_an_unarmed_piece_gets_no_weapon_widget() -> void:
	_row.update([_piece(WORKER_SCENE)])
	assert_does_not_have(_captions(), "Widget_Weapon")


func test_an_armed_piece_gets_one() -> void:
	_row.update([_piece(TURRET_SCENE)])
	assert_has(_captions(), "Widget_Weapon")


func test_every_widget_carries_a_tooltip() -> void:
	# VerboseTooltipButton reports an empty simple tooltip as an authoring bug; this is the
	# assertion that the row never produces one.
	_row.update([_piece(TURRET_SCENE)])
	for child: Node in _row.get_children():
		var button := child as VerboseTooltipButton
		assert_not_null(button, "%s is a tooltip button" % child.name)
		assert_ne(
			button.simple_tooltip,
			VerboseTooltipButton.MISSING_TOOLTIP,
			"%s has real copy" % child.name
		)


func test_only_the_range_bearing_widgets_ask_for_a_reveal() -> void:
	# Hovering the name or the hit points has nothing to draw on the ground, and a hover
	# that revealed the last card's rings would be worse than one that revealed none.
	_row.update([_piece(TURRET_SCENE)])
	for child: Node in _row.get_children():
		var expected: bool = String(child.name) in ["Widget_Weapon", "Widget_Sight"]
		assert_eq(child.has_meta(&"range_kinds"), expected, "%s asks for a reveal" % child.name)


# --- The status effect row -----------------------------------------------------------


func test_an_unaffected_piece_draws_no_effect_row() -> void:
	_effects.update([_piece(WORKER_SCENE)])
	assert_false(_effects.visible, "nothing is happening to it")


func test_an_active_effect_draws_a_card() -> void:
	var piece := _piece(WORKER_SCENE)
	var effect := SlowStatusEffect.new()
	effect.title = "Slowed"
	effect.description = "Moving at a fraction of its usual speed."
	piece.add_child(effect)
	effect.apply_to(piece)
	_effects.update([piece])
	assert_true(_effects.visible)
	assert_eq(_effects.get_child_count(), 1)
	var card := _effects.get_child(0) as VerboseTooltipButton
	assert_not_null(card)
	assert_string_contains(card.simple_tooltip, "Slowed")


func test_an_unnamed_effect_reads_as_unfinished_rather_than_blank() -> void:
	var effect := autofree(SlowStatusEffect.new()) as SlowStatusEffect
	assert_eq(ConditionRow.title_of(effect), ConditionRow.UNNAMED_TITLE)


# --- A multi-selection shows unit cards and nothing else -------------------------------
## Every row in the panel is single-selection only. A group has no single answer to any of
## the questions a row asks, and a merged description would describe a unit that is not on
## the field — so what a multi-selection shows is WHO is selected.


func test_the_widget_row_hides_for_a_group() -> void:
	_row.update([_piece(TURRET_SCENE), _piece(WORKER_SCENE)])
	assert_false(_row.visible)


func test_the_conditions_row_hides_for_a_group() -> void:
	# Even when a member genuinely has one: the card would say the group is slowed.
	var piece := _piece(WORKER_SCENE)
	var effect := SlowStatusEffect.new()
	effect.title = "Slowed"
	effect.description = "Moving at a fraction of its usual speed."
	piece.add_child(effect)
	effect.apply_to(piece)
	_effects.update([piece])
	assert_true(_effects.visible, "the fixture's effect really is drawn on its own")
	_effects.update([piece, _piece(TURRET_SCENE)])
	assert_false(_effects.visible, "and not once a second unit joins it")


func test_the_passive_row_hides_for_a_group() -> void:
	# It was the last row that drew for a group, and now that it uses the same ConditionCard
	# as a status effect it READ as one — which is what made the rule worth applying to it.
	var row := PassiveAbilityRow.new()
	add_child_autofree(row)
	row.update([_piece(WORKER_SCENE), _piece(TURRET_SCENE)], null)
	assert_false(row.visible)
