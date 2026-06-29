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


func _bot_slot(difficulty: int = PlayerSlot.Difficulty.MEDIUM) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = true
	slot.faction = load(FACTION)
	slot.difficulty = difficulty
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
	slot.starting_ore = 321
	slot.starting_dominion = 654
	var slots: Array[PlayerSlot] = [slot]
	_scn.player_slots = slots
	_scn._build_commanders()

	var c: Commander = _scn.commanders[1]
	assert_eq(c.ore, 321, "starting ore is applied from the slot")
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


func test_passive_difficulty_disables_the_brain() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)  # so the brain's owner (the scenario) is an ancestor
	_scn._attach_brain(bot, PlayerSlot.Difficulty.PASSIVE)

	var brain := bot.get_node("BotBrain") as BotBrain
	assert_eq(brain.difficulty, PlayerSlot.Difficulty.PASSIVE, "difficulty is carried to the brain")
	assert_false(brain.active, "PASSIVE leaves the think loop disabled")


func test_non_passive_difficulty_keeps_the_brain_active() -> void:
	var bot := Bot.new()
	_scn.add_child(bot)
	_scn._attach_brain(bot, PlayerSlot.Difficulty.HARD)

	var brain := bot.get_node("BotBrain") as BotBrain
	assert_eq(brain.difficulty, PlayerSlot.Difficulty.HARD, "difficulty is maintained for non-passive tiers")
	assert_true(brain.active, "a non-PASSIVE bot thinks")
