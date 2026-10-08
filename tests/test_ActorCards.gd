extends GutTest

## The unit card's two right-hand columns: the main bar (hit points, or training / purchase
## progress) filling UPWARD, and beside it the charge dials over a garrison bar. Driven with
## FakePieces; the colours are a vocabulary written in gdd/systems/ux/ui/actor-cards.md and
## pinned here only where the test is that two states look DIFFERENT.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ActorCards.gd -gexit

const SpecRegistryScript := preload("res://tools/spec_import/spec_registry.gd")

const CAST: StringName = &"fake_cast"
const PASSIVE: StringName = &"fake_passive"


func before_each() -> void:
	FakePieces.install_ability(CAST, {"title": "Cast"})
	FakePieces.install_ability(PASSIVE, {"title": "Passive", "passive": true})


func after_each() -> void:
	FakePieces.restore_abilities()


func _piece(a_options: Dictionary) -> Actor:
	var piece: Actor = FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.set_physics_process(false)
	piece.top_level = true
	return piece


func _card(a_piece: Actor) -> CommandableCard:
	var card := CommandableCard.new()
	add_child_autofree(card)
	card.bind_existing(a_piece)
	return card


# --- The main column ---------------------------------------------------------------------


func test_hit_points_fill_the_main_column_upward() -> void:
	var piece := _piece({"hp": 100.0})
	piece.defense.hp = 25.0
	var card := _card(piece)
	card._refresh_existing()
	assert_almost_eq(card.main_bar_ratio(), 0.25, 0.001)
	var fill := card.get_node("MainBar/Fill") as Control
	var bar := card.get_node("MainBar") as Control
	assert_almost_eq(fill.position.y + fill.size.y, bar.size.y, 0.001, "it grows up from the bottom")


func test_a_growing_bar_never_leaves_a_gap_at_the_bottom() -> void:
	# Every step of a training job's progress, not just the round numbers: a fractional height
	# once left a sliver of empty track under the fill.
	var card := CommandableCard.new()
	add_child_autofree(card)
	var bar := card.get_node("MainBar") as Control
	var fill := card.get_node("MainBar/Fill") as Control
	for step: int in 101:
		card.set_main_bar(step / 100.0, CommandableCard.TRAINING_COLOR)
		assert_eq(fill.position.y + fill.size.y, bar.size.y, "bottom filled at %d%%" % step)
		assert_eq(fill.size.y, roundf(fill.size.y), "whole pixels at %d%%" % step)


func test_the_columns_sit_right_of_the_picture() -> void:
	var card := _card(_piece({"hp": 100.0}))
	var main: Control = card.get_node("MainBar")
	var dials: Control = card.get_node("Dials")
	assert_almost_eq(main.position.x + main.size.x, card.size.x, 0.5, "flush right")
	assert_lt(dials.position.x, main.position.x, "the dial column is left of the main one")
	assert_lte(card.label_rect().end.x, dials.position.x, "text keeps clear of both")


func test_the_picture_fills_the_whole_card_under_the_columns() -> void:
	var card := _card(_piece({"hp": 100.0}))
	assert_eq(card._picture.size, card.size)


func test_the_columns_are_the_strip_a_staggered_row_leaves_showing() -> void:
	var card := _card(_piece({"hp": 100.0}))
	var dials: Control = card.get_node("Dials")
	var strip: float = CommandableCard.column_strip_width(card.size.y)
	assert_almost_eq(card.size.x - dials.position.x + CommandableCard.COLUMN_GAP, strip, 0.5)


# --- The garrison bar --------------------------------------------------------------------


func test_an_empty_hold_hides_its_bar() -> void:
	var card := _card(_piece({"structure": true, "garrison": {"capacity": 4}}))
	card._refresh_existing()
	assert_eq(card.garrison_ratio(), -1.0)


func test_an_occupied_hold_shows_how_full_it_is() -> void:
	var host := _piece({"structure": true, "garrison": {"capacity": 4}})
	(host.get_node("Garrison") as Garrison).garrison(_piece({"speed": 2.0}))
	var card := _card(host)
	card._refresh_existing()
	assert_almost_eq(card.garrison_ratio(), 0.25, 0.001)


# --- Which dials a piece gets ------------------------------------------------------------


func test_a_cast_pool_gets_a_dial_and_a_passive_one_does_not() -> void:
	var card := _card(
		_piece({"abilities": [{"grants": [CAST]}, {"grants": [PASSIVE]}]})
	)
	assert_eq(card.dial_count(), 1)


func test_a_producer_gets_a_dial_for_its_queue() -> void:
	var card := _card(_piece({"structure": true, "production": true}))
	assert_eq(card.dial_count(), 1)


func test_an_idle_producer_draws_an_empty_track() -> void:
	var piece := _piece({"structure": true, "production": true})
	var state: ChargeDial.State = ChargeDial.production_state(piece.production)
	assert_eq(state.full, 0)
	assert_eq(state.progress, 0.0)


func test_only_a_slow_or_charged_weapon_gets_a_dial() -> void:
	var ticks: int = TimeUtils.ticks_per_second()
	var rifle := _card(_piece({"weapon": {"ground": 6.0, "reload_ticks": ticks}}))
	var mortar := _card(_piece({"weapon": {"ground": 6.0, "reload_ticks": ticks * 6}}))
	var rockets := _card(_piece({"weapon": {"ground": 6.0, "charged": true, "clip_size": 4}}))
	assert_eq(rifle.dial_count(), 0, "a one-second reload is nothing to plan around")
	assert_eq(mortar.dial_count(), 1)
	assert_eq(rockets.dial_count(), 1, "a charged weapon never comes back on its own")


func test_more_dials_than_fit_are_dropped_and_reported() -> void:
	var capacity: int = CommandableCard.dial_capacity(CommandableCard.CARD_SIZE.y)
	var pools: Array = []
	for i: int in capacity + 1:
		pools.append({"grants": [CAST]})
	var card := _card(_piece({"abilities": pools}))
	assert_eq(card.dial_count(), capacity)
	assert_push_error("charge dials")


func test_the_default_card_fits_at_least_two_dials() -> void:
	# The most any piece needs today is two (the Recruit's two pools, or a producer with one
	# pool); a geometry change that leaves room for fewer would start dropping real dials.
	assert_gte(CommandableCard.dial_capacity(CommandableCard.CARD_SIZE.y), 2)


# --- What a dial draws -------------------------------------------------------------------


func test_a_pool_dial_is_cut_per_charge_and_fills_per_charge() -> void:
	var piece := _piece({"abilities": [{"grants": [CAST], "max_charges": 3, "cooldown_ticks": 30}]})
	var abilities := piece.get_node("Abilities") as Abilities
	abilities.spend(CAST)
	var state: ChargeDial.State = ChargeDial.pool_state(abilities, 0)
	assert_eq(state.sectors, 3)
	assert_eq(state.full, 2)
	assert_eq(state.progress_sectors, 1, "a pool earns back one charge at a time")
	assert_true(state.is_self_recharging)


func test_a_pool_dial_grows_as_the_charge_comes_back() -> void:
	var piece := _piece({"abilities": [{"grants": [CAST], "cooldown_ticks": 10}]})
	var abilities := piece.get_node("Abilities") as Abilities
	abilities.spend(CAST)
	for i: int in 4:
		abilities._physics_process(0.0)
	assert_almost_eq(ChargeDial.pool_state(abilities, 0).progress, 0.4, 0.001)


func test_an_empty_charged_weapon_is_stalled_not_recharging() -> void:
	var piece := _piece({"weapon": {"ground": 6.0, "charged": true, "clip_size": 2}})
	var weapon: Weapon = ChargeDial.dial_weapons(piece)[0]
	weapon.consume_round()
	weapon.consume_round()
	var state: ChargeDial.State = ChargeDial.weapon_state(weapon)
	assert_eq(state.full, 0)
	assert_false(state.is_self_recharging)
	assert_eq(state.progress, 0.0, "nothing is bringing it back")


func test_a_reloading_weapon_sweeps_every_empty_round() -> void:
	# A clip refills whole, so the sweep spans the rounds it will bring back together.
	var ticks: int = TimeUtils.ticks_per_second() * 6
	var piece := _piece({"weapon": {"ground": 6.0, "clip_size": 4, "reload_ticks": ticks}})
	var weapon: Weapon = ChargeDial.dial_weapons(piece)[0]
	weapon.fill_clip()
	weapon.consume_round()
	var state: ChargeDial.State = ChargeDial.weapon_state(weapon)
	assert_eq(state.full, 3)
	assert_eq(state.progress_sectors, 1)
	assert_true(state.is_self_recharging)


func test_recharging_and_stalled_read_apart_from_a_held_charge() -> void:
	assert_lt(ChargeDial.recharging_color().s, ChargeDial.HUE.s)
	assert_lt(ChargeDial.stalled_color().s, ChargeDial.recharging_color().s)


# --- The importer's count matches the card's -----------------------------------------------


func test_the_importer_counts_cast_pools_and_slow_weapons() -> void:
	var spec: Dictionary = {
		"trains": ["recruit"],
		"abilities": [{"grants": ["scan"]}, {"grants": ["aura"]}],
		"weapons": [{"reload_time": 1.0}, {"reload_time": 8.0}, {"charged": true}],
	}
	var ability_specs: Dictionary = {"scan": {}, "aura": {"passive": true}}
	assert_eq(SpecRegistryScript.charge_dials_needed(spec, ability_specs), 4)


# --- The other bind modes share the column -------------------------------------------------


func test_a_purchase_card_draws_its_progress_in_the_main_column() -> void:
	var card := CommandableCard.new()
	add_child_autofree(card)
	card.set_main_bar(0.5, CommandableCard.PURCHASE_COLOR)
	assert_almost_eq(card.main_bar_ratio(), 0.5, 0.001)
	assert_eq(card.dial_count(), 0)


# --- A multi-selection: one fanned row per type -------------------------------------------


func test_a_selection_groups_by_type_in_the_order_types_were_met() -> void:
	var a1 := _piece({"id": &"alpha"})
	var b1 := _piece({"id": &"beta"})
	var a2 := _piece({"id": &"alpha"})
	var rows: Array = InfoView.rows_by_type([a1, b1, a2], 10)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0], [a1, a2], "every alpha in one row, first-met type first")
	assert_eq(rows[1], [b1])


func test_a_type_wider_than_the_pane_continues_on_the_next_row() -> void:
	var pieces: Array = []
	for i: int in 5:
		pieces.append(_piece({"id": &"alpha"}))
	var rows: Array = InfoView.rows_by_type(pieces, 2)
	assert_eq(rows.map(func(r: Array) -> int: return r.size()), [2, 2, 1])


func test_tucked_cards_step_by_their_columns_plus_a_margin() -> void:
	var row := StaggeredCardRow.new()
	add_child_autofree(row)
	for i: int in 3:
		row.add_card(CommandableCard.new())
	var stride: float = (
		CommandableCard.column_strip_width(CommandableCard.CARD_SIZE.y)
		+ StaggeredCardRow.STRIDE_MARGIN
	)
	var cards: Array[Control] = row.cards()
	for i: int in cards.size():
		assert_almost_eq(cards[i].position.x, i * stride, 0.001, "card %d" % i)
	assert_almost_eq(row.custom_minimum_size.x, CommandableCard.CARD_SIZE.x + 2 * stride, 0.001)


func test_the_first_card_is_on_top_of_the_fan() -> void:
	# A later child draws over an earlier one, and the fan's first card is the whole one.
	var row := StaggeredCardRow.new()
	add_child_autofree(row)
	for i: int in 3:
		row.add_card(CommandableCard.new())
	var cards: Array[Control] = row.cards()
	assert_gt(cards[0].get_index(), cards[1].get_index())
	assert_gt(cards[1].get_index(), cards[2].get_index())


func test_a_pane_fits_one_whole_card_then_a_stride_per_card() -> void:
	var size: Vector2 = CommandableCard.CARD_SIZE
	var stride: float = StaggeredCardRow.stride_for(size)
	assert_eq(StaggeredCardRow.capacity_for(size.x - 1.0, size), 1)
	assert_eq(StaggeredCardRow.capacity_for(size.x + 2.0 * stride, size), 3)
