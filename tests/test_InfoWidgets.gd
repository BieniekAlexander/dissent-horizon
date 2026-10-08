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


func _piece(a_options: Dictionary) -> Actor:
	var piece: Actor = FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	return piece


func _captions() -> Array[String]:
	var out: Array[String] = []
	for widget: VerboseTooltipButton in _row.widgets():
		out.append(String(widget.name))
	return out


# --- Which widgets a piece gets ------------------------------------------------------


func test_a_single_selection_draws_the_row() -> void:
	_row.update([_piece(TURRET_SCENE)])
	assert_true(_row.visible)
	assert_gt(_row.widgets().size(), 0)


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
	for button: VerboseTooltipButton in _row.widgets():
		assert_ne(
			button.simple_tooltip,
			VerboseTooltipButton.MISSING_TOOLTIP,
			"%s has real copy" % button.name
		)


func test_only_the_range_bearing_widgets_ask_for_a_reveal() -> void:
	# Hovering the name or the hit points has nothing to draw on the ground, and a hover
	# that revealed the last card's rings would be worse than one that revealed none.
	_row.update([_piece(TURRET_SCENE)])
	for widget: VerboseTooltipButton in _row.widgets():
		var expected: bool = String(widget.name) in ["Widget_Weapon", "Widget_Sight"]
		assert_eq(widget.has_meta(&"range_kinds"), expected, "%s asks for a reveal" % widget.name)


# --- The fixed slot layout ----------------------------------------------------------
## Name, then hit points, each a full row; everything else two to a row. A piece without a
## property leaves its slot empty rather than letting a neighbour grow into it.


func _slot_of(a_widget: Control) -> Control:
	return a_widget.get_parent() as Control


func test_name_then_hit_points_lead_the_block() -> void:
	_row.update([_piece(TURRET_SCENE)])
	assert_eq(_slot_of(_row.widget_for("name")).get_index(), 0)
	assert_eq(_slot_of(_row.widget_for("hp")).get_index(), 1)
	assert_eq(_slot_of(_row.widget_for("name")).get_parent(), _row, "a row of its own")
	assert_eq(_slot_of(_row.widget_for("hp")).get_parent(), _row, "a row of its own")


func test_the_other_widgets_sit_two_to_a_row() -> void:
	_row.update([_piece(TURRET_SCENE)])
	for key: String in ["weapon", "sight"]:
		var row: Node = _slot_of(_row.widget_for(key)).get_parent()
		assert_true(row is HBoxContainer, "%s sits in a two-column row" % key)
		assert_eq(row.get_child_count(), 2)


func test_every_slot_exists_whatever_the_piece_has() -> void:
	# The layout is the same for every piece; only what is IN it differs. So the turret, which
	# cannot move, still has a speed slot — empty.
	_row.update([_piece(TURRET_SCENE)])
	var slot: Node = _row.find_child("Slot_Speed", true, false)
	assert_not_null(slot, "the slot is kept")
	assert_eq(slot.get_child_count(), 0, "and left empty")


func test_a_slot_is_the_same_size_whether_or_not_its_neighbour_is_filled() -> void:
	# The rule the layout exists for: a widget does not grow into an absent neighbour's room.
	_row.size = Vector2(400, 200)
	_row.update([_piece(TURRET_SCENE)])
	var stationary_width: float = _laid_out_width("weapon")
	_row.update([_piece({"speed": 2.0, "weapon": {"ground": 6.0}})])
	assert_almost_eq(_laid_out_width("weapon"), stationary_width, 0.5)
	assert_gt(stationary_width, 0.0)


## The width `a_key`'s widget is laid out at. Sorted synchronously, block then row, rather than
## by waiting frames: a frame lets every earlier test's deferred popup work run mid-test.
func _laid_out_width(a_key: String) -> float:
	_row.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var slot: Control = _row.widget_for(a_key).get_parent() as Control
	slot.get_parent().notification(Container.NOTIFICATION_SORT_CHILDREN)
	return slot.size.x


func test_a_producer_gets_a_production_widget() -> void:
	_row.update([_piece({"structure": true, "production": true})])
	assert_has(_captions(), "Widget_Production")


func test_a_piece_that_builds_nothing_gets_none() -> void:
	_row.update([_piece(TURRET_SCENE)])
	assert_does_not_have(_captions(), "Widget_Production")


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
