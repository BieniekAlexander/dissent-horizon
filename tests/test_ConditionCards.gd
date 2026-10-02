extends GutTest

## The three channels a condition card draws, and the one rule they exist to make legible:
## a player must be able to tell a TEMPORARY affliction from a PERSISTENT benefit without
## reading anything.
##
##   valence      a coloured edge — green at the TOP, red at the BOTTOM, nothing for neutral
##   duration     a depletion sweep, drawn ONLY for something that runs out
##   availability the card greys when the condition is offered but not yet bought
##
## The channels are asserted as STRUCTURE (does the card carry the node, where is it
## anchored) rather than as pixels — whether it looks right is a render pass, see
## CLAUDE.md §Seeing the HUD without a screen.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_ConditionCards.gd -gexit


func _card(a_valence: Valence.Kind, a_temporary: bool) -> ConditionCard:
	var card: ConditionCard = ConditionCard.build("Card", "X", null, a_valence, a_temporary)
	# A ConditionCard is a VerboseTooltipButton, which reports a blank tooltip as an authoring
	# bug — rightly, since a card the player cannot hover for an explanation is unfinished.
	# The rows always set one; a fixture that did not was testing a state the game never has.
	card.simple_tooltip = "A condition, for the card channels under test"
	add_child_autofree(card)
	return card


func _edge(a_card: ConditionCard) -> ColorRect:
	return a_card.get_node_or_null("Edge") as ColorRect


# --- Valence -------------------------------------------------------------------------


func test_a_neutral_condition_draws_no_edge() -> void:
	# Absence is the signal. A grey edge would read as a third state rather than as none.
	assert_null(_edge(_card(Valence.Kind.NEUTRAL, false)))


func test_a_boon_wears_its_edge_at_the_top() -> void:
	var edge: ColorRect = _edge(_card(Valence.Kind.BOON, false))
	assert_not_null(edge)
	assert_eq(edge.anchor_top, 0.0, "anchored to the card's top")
	assert_eq(edge.color, Valence.color_of(Valence.Kind.BOON))


func test_a_bane_wears_its_edge_at_the_bottom() -> void:
	# POSITION as well as colour, so the pair survives a colour-blind reader and a grey
	# screenshot — which colour alone would not.
	var edge: ColorRect = _edge(_card(Valence.Kind.BANE, false))
	assert_not_null(edge)
	assert_eq(edge.anchor_top, 1.0, "anchored to the card's bottom")
	assert_ne(edge.color, Valence.color_of(Valence.Kind.BOON))


# --- Duration ------------------------------------------------------------------------


func test_a_persistent_condition_draws_no_sweep() -> void:
	# Not a full bar — a full bar reads as "just started", and a passive never started.
	assert_null(_card(Valence.Kind.BOON, false)._sweep)


func test_a_temporary_condition_draws_one_and_it_drains() -> void:
	var card: ConditionCard = _card(Valence.Kind.BANE, true)
	assert_not_null(card._sweep)
	card.refresh(0.25, true)
	assert_almost_eq(card._sweep.anchor_right, 0.25, 0.001)


func test_the_sweep_clears_a_banes_edge() -> void:
	# Both live in the card's base strip; drawn last, the sweep covered the red entirely and
	# an affliction only read as one once it was nearly over.
	var bane: ConditionCard = _card(Valence.Kind.BANE, true)
	var boon: ConditionCard = _card(Valence.Kind.BOON, true)
	assert_lt(
		bane._sweep.offset_bottom,
		boon._sweep.offset_bottom,
		"the bane's sweep sits higher, clear of its edge"
	)


func test_remaining_is_clamped() -> void:
	var card: ConditionCard = _card(Valence.Kind.NEUTRAL, true)
	card.refresh(5.0, true)
	assert_eq(card.remaining, 1.0)
	card.refresh(-1.0, true)
	assert_eq(card.remaining, 0.0)


# --- Availability --------------------------------------------------------------------


func test_an_unavailable_condition_greys() -> void:
	var card: ConditionCard = _card(Valence.Kind.BOON, false)
	card.refresh(1.0, false)
	assert_eq(
		card.modulate,
		CommandButtonState.TINT_LOCKED,
		"the same grey an unbought ability's own button wears"
	)
	card.refresh(1.0, true)
	assert_eq(card.modulate, CommandButtonState.TINT_AVAILABLE)


# --- What the two constructs report --------------------------------------------------


func test_a_status_effect_reports_itself_as_temporary_when_it_has_a_duration() -> void:
	var effect := autofree(SlowStatusEffect.new()) as SlowStatusEffect
	effect.duration_ticks = 90
	assert_true(effect.is_temporary())
	assert_almost_eq(effect.remaining_fraction(), 1.0, 0.001, "untouched, so nothing spent")


func test_an_effect_with_no_duration_is_persistent_and_reads_as_full() -> void:
	# 1.0 rather than 0.0: it is not running out, which is a different thing from being over.
	var effect := autofree(SlowStatusEffect.new()) as SlowStatusEffect
	effect.duration_ticks = 0
	assert_false(effect.is_temporary())
	assert_almost_eq(effect.remaining_fraction(), 1.0, 0.001)


func test_an_unknown_valence_name_reads_as_neutral() -> void:
	# Validation is the importer's job; a HUD that fell over on a typo would be worse than a
	# card with no accent.
	assert_eq(Valence.from_name("nonsense"), Valence.Kind.NEUTRAL)
	assert_eq(Valence.from_name("boon"), Valence.Kind.BOON, "case-insensitive")
