extends GutTest

## Scenario builds its commanders from player_slots: id 0 is the implicit neutral
## world commander, then one commander per slot at ids 1..N, with the slot's faction
## propagated and its difficulty carried to the BotBrain (PASSIVE → inert).
##
## These cover the bot / neutral / faction / difficulty logic. The human-rig path
## (a non-bot slot → player.tscn + the local viewpoint) is covered by the s1.tscn
## boot instead — instantiating that rig in a unit test trips unrelated push_errors.
##
## The Scenario is kept ORPHAN (never added to the tree) so its heavy _ready boot
## doesn't run; we drive _build_commanders / _attach_brain directly.

const FACTION := "res://scenes/factions/anarchical.tscn"

var _scn: Scenario


func before_each() -> void:
	_scn = Scenario.new()


func after_each() -> void:
	# _build_commanders creates commanders out of tree; free them explicitly.
	for c in _scn.commanders:
		if is_instance_valid(c):
			c.free()
	_scn.free()


func _bot_slot(a_difficulty: int = PlayerSlot.Difficulty.MEDIUM) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = true
	slot.faction = load(FACTION)
	slot.difficulty = a_difficulty
	return slot


func test_neutral_then_one_commander_per_slot() -> void:
	var slots: Array[PlayerSlot] = [_bot_slot(), _bot_slot()]
	_scn.player_slots = slots
	_scn._build_commanders()

	assert_eq(_scn.commanders.size(), 3, "neutral + 2 slots")
	assert_eq((_scn.commanders[0] as Commander).id, 0, "id 0 is neutral")
	assert_false(_scn.commanders[0] is Bot, "neutral is a plain Commander, not a Bot")
	assert_eq((_scn.commanders[1] as Commander).id, 1, "first slot is commander 1")
	assert_eq((_scn.commanders[2] as Commander).id, 2, "second slot is commander 2")
	assert_true(_scn.commanders[2] is Bot, "a bot slot builds a Bot")


func test_slot_caches_its_built_commander() -> void:
	var slots: Array[PlayerSlot] = [_bot_slot()]
	_scn.player_slots = slots
	_scn._build_commanders()

	assert_same(slots[0].commander, _scn.commanders[1], "slot stores the commander it built")


func test_starting_resources_come_from_the_slot() -> void:
	var slot := _bot_slot()
	slot.starting_energy = 321
	slot.starting_dominion = 654
	var slots: Array[PlayerSlot] = [slot]
	_scn.player_slots = slots
	_scn._build_commanders()

	var c: Commander = _scn.commanders[1]
	assert_eq(c.energy, 321, "starting energy is applied from the slot")
	assert_eq(c.dominion, 654, "starting dominion is applied from the slot")
	assert_eq((_scn.commanders[0] as Commander).dominion, 0, "the neutral commander has no slot, so zero")


func test_spectator_when_every_slot_is_a_bot() -> void:
	var slots: Array[PlayerSlot] = [_bot_slot(), _bot_slot()]
	_scn.player_slots = slots
	_scn._build_commanders()

	assert_lt(RTSController.PLAYER_COMMANDER_ID, 1, "no human slot → spectator viewpoint")


func test_faction_is_propagated_onto_the_commander() -> void:
	var slots: Array[PlayerSlot] = [_bot_slot()]
	_scn.player_slots = slots
	_scn._build_commanders()

	assert_eq(
		(_scn.commanders[1] as Commander).faction_scene, slots[0].faction,
		"the slot's faction is set on its commander"
	)


## A slot's faction is REQUIRED — Scenario._validate_player_slots fails the boot
## without one, so there is no path by which a commander picks up a faction from
## anywhere but its slot. These drive the pure detector rather than the reporting
## wrapper: that wrapper calls assert(false), which would halt the whole GUT run.
func test_no_missing_factions_when_every_slot_names_one() -> void:
	_scn.player_slots = [_bot_slot(), _bot_slot()] as Array[PlayerSlot]

	assert_eq(_scn._missing_faction_slots(), [] as Array[int], "fully configured slots report nothing missing")


func test_slot_without_a_faction_is_reported_by_its_commander_id() -> void:
	var bare := PlayerSlot.new()  # faction left null
	_scn.player_slots = [_bot_slot(), bare] as Array[PlayerSlot]

	assert_eq(
		_scn._missing_faction_slots(), [2] as Array[int],
		"the second slot (commander id 2) is reported, 1-based like the commander ids"
	)


func test_every_offending_slot_is_reported_not_just_the_first() -> void:
	_scn.player_slots = [PlayerSlot.new(), _bot_slot(), PlayerSlot.new()] as Array[PlayerSlot]

	assert_eq(
		_scn._missing_faction_slots(), [1, 3] as Array[int],
		"an author sees every misconfigured slot in one pass"
	)


func test_an_empty_array_row_counts_as_missing() -> void:
	_scn.player_slots = [null, _bot_slot()] as Array[PlayerSlot]

	assert_eq(_scn._missing_faction_slots(), [1] as Array[int], "a null slot is reported, not skipped")


## PASSIVE is a KIND of opponent, not an absent one. It used to leave the brain inert, which
## made it scenery; the tier means "minimally active, and never attacks the player", so it
## thinks, builds and defends itself and `may_attack` is what keeps it home.
func test_passive_difficulty_still_thinks_but_never_attacks() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)  # so the brain's owner (the scenario) is an ancestor
	_scn._attach_brain(bot, PlayerSlot.Difficulty.PASSIVE, true)

	var brain := bot.get_node("BotBrain") as BotBrain
	assert_eq(brain.difficulty, PlayerSlot.Difficulty.PASSIVE, "difficulty is carried to the brain")
	assert_true(brain.active, "it is not inert any more")
	assert_false(brain.config.may_attack, "and it is the config that keeps it home")


func test_non_passive_difficulty_keeps_the_brain_active() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)
	_scn._attach_brain(bot, PlayerSlot.Difficulty.HARD, true)

	var brain := bot.get_node("BotBrain") as BotBrain
	assert_eq(brain.difficulty, PlayerSlot.Difficulty.HARD, "difficulty is maintained for non-passive tiers")
	assert_true(brain.active, "a non-PASSIVE bot thinks")
	assert_true(brain.config.may_attack)


## THE TIER SELECTS PARAMETERS, and the parameters are what the managers read. Pinned as a
## RAMP rather than by value: the numbers are placeholders awaiting a tuning run, but the
## DIRECTION each knob means is the settled part and a tier that inverted one would be a bug.
func test_the_tiers_are_a_monotone_ramp() -> void:
	var tiers: Array = [
		PlayerSlot.Difficulty.EASY,
		PlayerSlot.Difficulty.MEDIUM,
		PlayerSlot.Difficulty.HARD,
		PlayerSlot.Difficulty.IMPOSSIBLE,
	]
	var previous: BotDifficulty = null
	for tier: PlayerSlot.Difficulty in tiers:
		var config: BotDifficulty = BotDifficulty.for_tier(tier)
		assert_true(config.may_attack, "every non-passive tier attacks")
		if previous != null:
			for period: String in ["combat_period_seconds", "strategy_period_seconds",
					"scout_period_seconds"]:
				assert_lte(config.get(period), previous.get(period),
					"a harder bot reacts no slower (%s)" % period)
			assert_lte(config.army_commit_threshold, previous.army_commit_threshold,
				"a harder bot commits no later")
			assert_lte(config.retarget_switch_margin, previous.retarget_switch_margin,
				"a harder bot micros no less")
			assert_lte(config.economy_reserve, previous.economy_reserve,
				"a harder bot banks no more before expanding")
			assert_gte(config.scout_unit_budget, previous.scout_unit_budget,
				"a harder bot is willing to spend no fewer units looking")
			assert_gte(_concurrency_rank(config), _concurrency_rank(previous),
				"a harder bot runs no fewer construction jobs at once")
		previous = config


## `build_concurrency` carries a sentinel (-1 = UNCAPPED), so it cannot be compared raw on a
## ramp — uncapped is the TOP, not the bottom. Same shape as preserve_min_cost's -1.
func _concurrency_rank(a_config: BotDifficulty) -> int:
	return 9999 if BotDifficulty.is_build_uncapped(a_config.build_concurrency) \
		else a_config.build_concurrency


## It was 1 on EVERY tier — a constant wearing a parameter's clothes, and a visible one: a
## Colonial opening pairs two Servants, so the second stood idle all match because nothing
## else in the bot claims an unarmed unit.
func test_build_concurrency_is_a_real_ramp_and_not_a_flat_one() -> void:
	var values: Array = [
		PlayerSlot.Difficulty.PASSIVE,
		PlayerSlot.Difficulty.EASY,
		PlayerSlot.Difficulty.MEDIUM,
		PlayerSlot.Difficulty.HARD,
	].map(func(t: PlayerSlot.Difficulty) -> int:
		return BotDifficulty.for_tier(t).build_concurrency)
	assert_gt(values.max(), values.min(), "the tiers do not all build the same amount at once")
	assert_gt(values.max(), 1, "and the ceiling is above the one-at-a-time it shipped with")


func test_the_hardest_tier_is_uncapped_rather_than_merely_large() -> void:
	assert_true(
		BotDifficulty.is_build_uncapped(
			BotDifficulty.for_tier(PlayerSlot.Difficulty.IMPOSSIBLE).build_concurrency),
		"IMPOSSIBLE builds with everything it can spare")
	assert_false(
		BotDifficulty.is_build_uncapped(
			BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM).build_concurrency),
		"and a middling tier is still throttled")


func test_the_concurrency_sentinel_is_never_read_as_a_count() -> void:
	# The trap the helpers exist to prevent: `maxi(1, -1)` is 1, so a raw read would turn
	# "uncapped" into the tightest possible throttle — silently, and only on the hardest tier.
	assert_eq(BotDifficulty.build_slots(-1), 1, "the raw count of the sentinel is misleading")
	assert_true(BotDifficulty.is_build_uncapped(-1), "which is why callers must ask this first")
	assert_eq(BotDifficulty.build_slots(0), 1, "a nonsense zero still means one job")
	assert_eq(BotDifficulty.build_slots(3), 3)


## The budget was 1 for every tier below IMPOSSIBLE — a constant wearing a parameter's
## clothes. It has to actually MOVE across the ramp, or the knob means nothing, and with a
## fog-limited attack objective a bot that cannot look cannot attack.
func test_the_scout_budget_is_a_real_ramp_and_not_a_flat_one() -> void:
	var budgets: Array = [
		PlayerSlot.Difficulty.EASY,
		PlayerSlot.Difficulty.MEDIUM,
		PlayerSlot.Difficulty.HARD,
		PlayerSlot.Difficulty.IMPOSSIBLE,
	].map(func(t: PlayerSlot.Difficulty) -> int: return BotDifficulty.for_tier(t).scout_unit_budget)
	assert_gt(budgets.max(), budgets.min(), "the tiers do not all scout the same amount")
	assert_gt(budgets.max(), 1, "and the ceiling is above the one-scout maximum it shipped with")
	assert_eq(BotDifficulty.for_tier(PlayerSlot.Difficulty.PASSIVE).scout_unit_budget, 0,
		"PASSIVE still plays blind")


func test_preservation_is_a_threshold_rather_than_a_tier_check() -> void:
	# -1 means "never", which is how the easy tiers express it — not a branch on the tier.
	assert_false(BotDifficulty.for_tier(PlayerSlot.Difficulty.EASY)
		.preserves_unit_costing(10_000), "EASY abandons anything")
	assert_true(BotDifficulty.for_tier(PlayerSlot.Difficulty.HARD)
		.preserves_unit_costing(0), "HARD saves everything")
	var medium: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	assert_false(medium.preserves_unit_costing(medium.preserve_min_cost - 1))
	assert_true(medium.preserves_unit_costing(medium.preserve_min_cost))


## Every slot's commander carries a brain; a human slot's is attached switched off, so debug
## mode can hand the slot to it.
func test_a_brain_attached_off_is_not_ai_controlled() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)
	_scn._attach_brain(bot, PlayerSlot.Difficulty.HARD, false)

	assert_not_null(bot.brain(), "the brain is attached")
	assert_false(bot.is_ai_controlled(), "and does not think")


## Waking a brain REBUILDS it: a new node, carrying the old one's difficulty.
func test_switching_ai_control_on_rebuilds_the_brain() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)
	_scn._attach_brain(bot, PlayerSlot.Difficulty.EASY, false)
	var old_brain: BotBrain = bot.brain()

	_scn.set_ai_control(bot, true)

	assert_true(bot.is_ai_controlled(), "the bot now thinks")
	assert_ne(bot.brain(), old_brain, "through a fresh brain")
	assert_eq(bot.brain().difficulty, PlayerSlot.Difficulty.EASY, "keeping its difficulty")


func test_switching_ai_control_off_keeps_the_brain() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)
	_scn._attach_brain(bot, PlayerSlot.Difficulty.EASY, true)
	var brain: BotBrain = bot.brain()

	_scn.set_ai_control(bot, false)

	assert_false(bot.is_ai_controlled(), "the bot stops thinking")
	assert_eq(bot.brain(), brain, "and nothing is rebuilt to stop it")


func test_play_as_hands_the_old_slot_to_its_bot() -> void:
	var slots: Array[PlayerSlot] = [_bot_slot(), _bot_slot()]
	_scn.player_slots = slots
	_scn._build_commanders()
	for i: int in [1, 2]:
		_scn.add_child(_scn.commanders[i])
		_scn._attach_brain(_scn.commanders[i] as Bot, PlayerSlot.Difficulty.MEDIUM, i != 1)
	RTSController.PLAYER_COMMANDER_ID = 1

	assert_true(_scn.play_as(2), "the swap happens")

	assert_eq(RTSController.PLAYER_COMMANDER_ID, 2, "the player is commander 2")
	assert_true((_scn.commanders[1] as Bot).is_ai_controlled(), "the slot left behind is its bot's")
	assert_false((_scn.commanders[2] as Bot).is_ai_controlled(), "the slot taken over is not")
	assert_false(_scn.play_as(2), "swapping to who you already are does nothing")
	assert_false(_scn.play_as(0), "and neutral is never a seat")
	RTSController.PLAYER_COMMANDER_ID = 1
