extends GutTest

## THE RESEARCH RUNG prices an upgrade by what it does for the pieces the bot fields — every
## `modifies:` entry is a factor, and (factor − 1) × the fielded cost of what it selects is the
## value — and buys it when that clears `tech_value_margin` × its cost with the reserve kept
## (gdd/systems/ai/bot-architecture.md §The research rung). The upgrades are installed by
## the test; no shipped id is named.

const HULLS: StringName = &"fake_hulls"
const EYES: StringName = &"fake_eyes"
const TANK: StringName = &"fake_tank"
const SCOUT: StringName = &"fake_scout"
const SPOTTING: StringName = &"fake_spotting"
const TANK_COST: int = 300
const UPGRADE_COST: int = 200


class FakeBot:
	extends Bot
	var own: Array = []
	var labs: Array = []
	var taken: Array = []
	var costs: Dictionary = {}

	func get_units() -> Array:
		return own

	func get_structures() -> Array:
		return []

	func get_research_structures() -> Array:
		return labs

	func is_research_taken(a_type: Variant) -> bool:
		return taken.has(a_type)

	func unit_cost(a_unit_type) -> int:
		return int(costs.get(a_unit_type, 0))

	func can_afford(_a_type: StringName) -> bool:
		return true


class RecordingActuator:
	extends BotActuator
	var trained: Array = []  # [{"at", "type"}]

	func train(a_structure: Actor, a_type: StringName) -> bool:
		trained.append({"at": a_structure, "type": a_type})
		return true


var _bot: FakeBot
var _act: RecordingActuator
var _research: BotResearch
var _saved_upgrades: Dictionary = {}


func before_each() -> void:
	_saved_upgrades = UpgradeCatalog._entries.duplicate()
	UpgradeCatalog._entries[HULLS] = {
		"title": "Hulls", "modifies": [{"piece": String(TANK), "hp_factor": 1.25}]
	}
	UpgradeCatalog._entries[EYES] = {
		"title": "Eyes",
		"modifies": [{"piece": String(SCOUT), "ability": String(SPOTTING), "range": 30.0}]
	}
	FakePieces.install_ability(SPOTTING, {"command": "command_spot", "range": 10.0})
	_bot = FakeBot.new()
	_bot.id = 1
	_bot.energy = 10000
	_bot.costs = {TANK: TANK_COST, SCOUT: TANK_COST, HULLS: UPGRADE_COST, EYES: UPGRADE_COST}
	add_child_autofree(_bot)
	_act = RecordingActuator.new(null)
	_research = BotResearch.new(_bot, _act)
	_research.tech_value_margin = 1.3


func after_each() -> void:
	UpgradeCatalog._entries = _saved_upgrades
	FakePieces.restore_abilities()


func _lab(a_researches: Array) -> Actor:
	var lab: Actor = FakePieces.structure({"produces": a_researches})
	add_child_autofree(lab)
	lab.ownership.commander = _bot
	_bot.labs.append(lab)
	return lab


func _fielded(a_id: StringName, a_count: int) -> void:
	for i: int in a_count:
		var piece: Actor = FakePieces.unit({})
		add_child_autofree(piece)
		piece.id = a_id
		piece.ownership.commander = _bot
		_bot.own.append(piece)


func test_an_upgrade_worth_more_than_its_margin_is_bought_at_the_lab() -> void:
	var lab: Actor = _lab([HULLS])
	_fielded(TANK, 4)  # 0.25 × 1200 = 300 against a 260 bar
	_research.tick()
	assert_eq(_act.trained, [{"at": lab, "type": HULLS}])


func test_an_upgrade_worth_less_than_its_margin_is_priced_and_not_bought() -> void:
	_lab([HULLS])
	_fielded(TANK, 2)  # 0.25 × 600 = 150 against 260
	_research.tick()
	assert_eq(_act.trained, [])
	var choices: Dictionary = _act.usage._choices.get(BotResearch.CHOICE_DOMAIN, {})
	assert_true(choices.has(String(HULLS)), "considered, so the audit can see it was")


func test_an_upgrade_for_pieces_the_bot_has_none_of_is_worth_nothing() -> void:
	_lab([HULLS])
	_fielded(SCOUT, 10)
	_research.tick()
	assert_eq(_act.trained, [], "no tanks: nothing for hulls to improve")


func test_a_reach_upgrade_is_priced_by_how_many_times_the_reach_it_adds() -> void:
	var lab: Actor = _lab([EYES])
	_fielded(SCOUT, 1)  # 30 over 10 is ×3: (3 − 1) × 300 = 600 against 260
	_research.tick()
	assert_eq(_act.trained, [{"at": lab, "type": EYES}])


func test_the_better_of_two_upgrades_is_the_one_bought() -> void:
	var lab: Actor = _lab([HULLS, EYES])
	_fielded(TANK, 4)  # hulls: 300
	_fielded(SCOUT, 1)  # eyes: 600
	_research.tick()
	assert_eq(_act.trained, [{"at": lab, "type": EYES}])


func test_an_upgrade_already_taken_is_not_priced_again() -> void:
	_lab([HULLS])
	_fielded(TANK, 4)
	_bot.taken = [HULLS]
	_research.tick()
	assert_eq(_act.trained, [])


func test_the_reserve_is_kept() -> void:
	_lab([HULLS])
	_fielded(TANK, 4)
	_bot.energy = 250
	_research.reserve = 100  # 250 − 200 leaves 50
	_research.tick()
	assert_eq(_act.trained, [], "worth it, but not at the cost of the bank")
