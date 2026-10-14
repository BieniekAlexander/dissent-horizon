extends GutTest

## THE SKIRMISH LOBBY'S STATE: players, factions, teams, the human slot, and the recipe it
## freezes into.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SkirmishSetup.gd -gexit
##
## Why: gdd/systems/ux/ui/menus.md §Skirmish.


func _rng(a_seed: int = 7) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = a_seed
	return rng


func test_a_new_setup_is_the_minimum_players_random_and_teamless() -> void:
	var setup := SkirmishSetup.new()
	assert_eq(setup.player_count(), SkirmishSetup.MIN_PLAYERS)
	for i: int in setup.player_count():
		assert_eq(setup.faction_of(i), SkirmishSetup.RANDOM)
		assert_eq(setup.team_of(i), SkirmishSetup.NO_TEAM)
	assert_true(setup.human_plays_first_slot)


func test_the_player_count_is_clamped_and_keeps_choices() -> void:
	var setup := SkirmishSetup.new()
	setup.set_faction(1, SkirmishSetup.FACTIONS[0])
	setup.set_player_count(99)
	assert_eq(setup.player_count(), SkirmishSetup.MAX_PLAYERS)
	setup.set_player_count(0)
	assert_eq(setup.player_count(), SkirmishSetup.MIN_PLAYERS)
	assert_eq(setup.faction_of(1), SkirmishSetup.FACTIONS[0], "a slot that stays keeps its pick")


func test_only_offered_factions_are_accepted() -> void:
	var setup := SkirmishSetup.new()
	setup.set_faction(0, "res://not/a/faction.tscn")
	assert_eq(setup.faction_of(0), SkirmishSetup.RANDOM)


func test_everyone_on_one_team_cannot_play() -> void:
	var setup := SkirmishSetup.new(3)
	for i: int in 3:
		setup.set_team(i, 1)
	assert_false(setup.can_play())
	setup.set_team(2, SkirmishSetup.NO_TEAM)
	assert_true(setup.can_play(), "a teamless third player is an opponent")


func test_teamless_players_are_each_their_own_alliance() -> void:
	var setup := SkirmishSetup.new(4)
	setup.set_team(1, 2)
	setup.set_team(3, 2)
	assert_eq(setup.alliance_indices(), PackedInt32Array([0, 1, 2, 1]))


func test_the_recipe_resolves_random_and_marks_bots() -> void:
	var setup := SkirmishSetup.new(3)
	setup.set_faction(1, SkirmishSetup.FACTIONS[1])
	var recipe: Dictionary = setup.recipe(_rng())
	var players: Array = recipe["players"]
	assert_eq(players.size(), 3)
	for player: Dictionary in players:
		assert_true(SkirmishSetup.FACTIONS.has(player["faction"]), "Random became a real faction")
	assert_eq(players[1]["faction"], SkirmishSetup.FACTIONS[1])
	assert_eq(players.map(func(p: Dictionary) -> bool: return p["is_bot"]), [false, true, true])


func test_unticking_the_first_slot_makes_every_player_a_bot() -> void:
	var setup := SkirmishSetup.new()
	setup.human_plays_first_slot = false
	var players: Array = setup.recipe(_rng())["players"]
	assert_eq(players.map(func(p: Dictionary) -> bool: return p["is_bot"]), [true, true])


func test_the_same_rng_gives_the_same_recipe() -> void:
	var setup := SkirmishSetup.new(4)
	assert_eq(setup.recipe(_rng(3)), setup.recipe(_rng(3)))


func test_each_bot_has_its_own_difficulty_in_the_recipe() -> void:
	var setup := SkirmishSetup.new(3)
	assert_eq(setup.difficulty_of(2), SkirmishSetup.DEFAULT_DIFFICULTY)
	setup.set_difficulty(1, PlayerSlot.Difficulty.EASY)
	setup.set_difficulty(2, PlayerSlot.Difficulty.IMPOSSIBLE)
	var players: Array = setup.recipe(_rng())["players"]
	assert_eq(players[1]["difficulty"], PlayerSlot.Difficulty.EASY)
	assert_eq(players[2]["difficulty"], PlayerSlot.Difficulty.IMPOSSIBLE)


func test_an_unknown_difficulty_is_ignored() -> void:
	var setup := SkirmishSetup.new()
	setup.set_difficulty(1, 99 as PlayerSlot.Difficulty)
	assert_eq(setup.difficulty_of(1), SkirmishSetup.DEFAULT_DIFFICULTY)


# --- Networked: open slots and seats ---------------------------------------------------------


func _networked(a_players: int = 3) -> SkirmishSetup:
	var setup := SkirmishSetup.new(a_players)
	setup.is_networked = true
	return setup


func test_the_host_always_plays_the_first_slot() -> void:
	var setup := SkirmishSetup.new()
	setup.human_plays_first_slot = false
	setup.is_networked = true
	assert_false(setup.is_bot(0))
	assert_eq(setup.peer_in(0), SkirmishSetup.HOST_PEER)
	setup.set_open(0, true)
	assert_false(setup.is_open(0), "the host's slot is never open")


func test_an_open_slot_is_a_persons_and_a_closed_one_a_bot() -> void:
	var setup: SkirmishSetup = _networked()
	setup.set_open(1, true)
	assert_false(setup.is_bot(1))
	assert_true(setup.is_bot(2))
	assert_false(setup.recipe(RandomNumberGenerator.new())["players"][1]["is_bot"])


func test_a_slot_is_never_open_off_the_network() -> void:
	var setup := SkirmishSetup.new(3)
	setup.set_open(1, true)
	assert_false(setup.is_open(1))
	assert_true(setup.is_bot(1))


func test_a_joiner_is_seated_in_the_first_free_open_slot_and_may_move() -> void:
	var setup: SkirmishSetup = _networked(4)
	setup.set_open(2, true)
	setup.set_open(3, true)
	assert_eq(setup.seat_anywhere(5), 2)
	assert_eq(setup.seat_anywhere(6), 3)
	assert_eq(setup.seat_anywhere(7), -1, "no open slot is left")
	setup.unseat(6)
	assert_true(setup.seat(5, 3), "moved")
	assert_eq(setup.slot_of(5), 3)
	assert_eq(setup.peer_in(2), 0, "and the slot it left is free")


func test_a_taken_or_closed_slot_cannot_be_claimed() -> void:
	var setup: SkirmishSetup = _networked()
	setup.set_open(1, true)
	assert_true(setup.seat(5, 1))
	assert_false(setup.seat(6, 1), "taken")
	assert_false(setup.seat(6, 2), "a bot's")
	setup.set_open(1, false)
	assert_eq(setup.slot_of(5), -1, "closing a slot unseats its player")


func test_play_waits_for_every_open_slot_to_be_taken() -> void:
	var setup: SkirmishSetup = _networked()
	setup.set_team(0, 1)
	setup.set_team(1, 2)
	setup.set_open(1, true)
	assert_false(setup.can_play())
	setup.seat_anywhere(5)
	assert_true(setup.can_play())


func test_match_seats_name_each_peer_and_its_commander() -> void:
	var setup: SkirmishSetup = _networked()
	setup.set_open(2, true)
	setup.seat(5, 2)
	assert_eq(setup.match_seats(), {SkirmishSetup.HOST_PEER: 1, 5: 3})


func test_a_setup_survives_the_wire() -> void:
	var setup: SkirmishSetup = _networked(4)
	setup.set_faction(1, SkirmishSetup.FACTIONS[1])
	setup.set_team(2, 3)
	setup.set_difficulty(3, PlayerSlot.Difficulty.EASY)
	setup.set_open(1, true)
	setup.seat(5, 1)
	var back: SkirmishSetup = SkirmishSetup.from_dict(
		JSON.parse_string(JSON.stringify(setup.to_dict()))
	)
	assert_eq(back.to_dict(), setup.to_dict())
