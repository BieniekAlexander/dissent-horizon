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
