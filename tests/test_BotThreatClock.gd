extends GutTest

## THE THREAT CLOCK: a believed enemy weighs on what the bot buys by when it could arrive
## against when the bot could answer (gdd/systems/ai/world-model/lattice-and-topology.md
## §Distance fields; macro-learning.md §2). The shape is `Bot.clock_weight`, a static; the
## read is `Bot.believed_enemy_composition_clocked` over the blackboard and the bot's fields,
## driven here with a fixture lattice and a bot whose answers are set by the test.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotThreatClock.gd -gexit


## A bot that walks every believed type at 2.0 and can answer in ten seconds.
class ClockBot:
	extends Bot
	var answer: float = 10.0

	func mobility_of_type(_a_type: StringName) -> Dictionary:
		return {"speed": 2.0, "nav_class": NavAgentClass.Size.SMALL, "is_air": false}

	func fastest_answer_seconds() -> float:
		return answer

	func base_centroid() -> Vector3:
		return Vector3.ZERO


var _bot: ClockBot


func before_each() -> void:
	_bot = ClockBot.new()
	add_child_autofree(_bot)
	_bot.blackboard = CommanderBlackboard.new(_bot)
	var fields: FixtureFields = FixtureFields.over_open(Rect2(-100.0, -100.0, 200.0, 200.0))
	fields.home = [fields.lattice.index_at(Vector2.ZERO)]
	# The fixture asks its commander for a type's mobility, which this bot fakes.
	fields._commander = _bot
	_bot._fields = fields
	_bot.arrival_margin_falloff_seconds = 30.0


func _believe_unit(a_id: int, a_type: StringName, a_at: Vector3) -> void:
	var entry := CommanderBlackboard.Entry.new()
	entry.instance_id = a_id
	entry.type = a_type
	entry.is_structure = false
	entry.last_known_location = a_at
	entry.last_seen_time = 0.0
	_bot.blackboard._entries[a_id] = entry


# ─── THE PHANTOM OPENING FORCE ───────────────────────────────────────────────


## Before any sighting the enemy's starting units are assumed on their way, weighed at the
## fields' opening prior; the first believed unit ends it for good
## (gdd/systems/ai/objective-selection.md §The opening prior).
func test_the_phantom_force_weighs_at_the_opening_prior_until_a_unit_is_seen() -> void:
	_bot.phantom_force = {&"raider": 2, &"truck": 1}
	assert_eq(_bot.believed_enemy_composition_clocked(), {}, "no prior yet: no phantom")
	_bot._fields.prior_arrival_seconds = 5.0
	assert_eq(
		_bot.believed_enemy_composition_clocked(),
		{&"raider": 2.0, &"truck": 1.0},
		"arriving before the answer: in full"
	)
	assert_almost_eq(
		float(_bot.enemy_demand_map()[&"raider"]["demand"]), 2.0, 1e-9, "the demand map too"
	)
	_bot._fields.prior_arrival_seconds = 40.0
	assert_almost_eq(
		float(_bot.believed_enemy_composition_clocked()[&"raider"]),
		2.0 * Bot.clock_weight(40.0, 10.0, 30.0),
		1e-9,
		"further off, lighter"
	)
	_bot.blackboard.has_believed_unit = true
	assert_eq(_bot.believed_enemy_composition_clocked(), {}, "lapsed at the first sighting")


func test_the_blackboard_records_the_first_unit_it_ever_believes() -> void:
	assert_false(_bot.blackboard.has_believed_unit)
	var unit: Actor = FakePieces.unit({"speed": 2.0})
	add_child_autofree(unit)
	_bot.blackboard._upsert(unit, 0.0)
	assert_true(_bot.blackboard.has_believed_unit)


# ─── THE SHAPE ──────────────────────────────────────────────────────────────


func test_a_threat_that_arrives_before_the_answer_weighs_in_full() -> void:
	assert_eq(Bot.clock_weight(5.0, 10.0, 30.0), 1.0)
	assert_eq(Bot.clock_weight(10.0, 10.0, 30.0), 1.0, "a dead heat is pressing")


func test_a_threat_with_time_to_spare_falls_off_toward_the_floor() -> void:
	var one_falloff: float = Bot.clock_weight(40.0, 10.0, 30.0)
	assert_almost_eq(one_falloff, Bot.CLOCK_FLOOR + (1.0 - Bot.CLOCK_FLOOR) / exp(1.0), 0.001)
	assert_lt(Bot.clock_weight(100.0, 10.0, 30.0), one_falloff, "further off, lighter")
	assert_gt(Bot.clock_weight(100.0, 10.0, 30.0), Bot.CLOCK_FLOOR, "never below the floor")


func test_a_threat_that_cannot_arrive_weighs_the_floor() -> void:
	assert_eq(Bot.clock_weight(INF, 10.0, 30.0), Bot.CLOCK_FLOOR)
	assert_eq(Bot.clock_weight(100.0, INF, 30.0), 1.0, "no answer possible: everything presses")


# ─── THE READ ───────────────────────────────────────────────────────────────


func test_a_believed_unit_at_the_gate_outweighs_one_across_the_map() -> void:
	_believe_unit(1, &"raider", Vector3(10.0, 0.0, 0.0))  # 5 s away at 2.0
	_believe_unit(2, &"raider", Vector3(-90.0, 0.0, 0.0))  # 45 s away
	var clocked: Dictionary = _bot.believed_enemy_composition_clocked()
	var plain: Dictionary = _bot.believed_enemy_composition()
	assert_eq(plain[&"raider"], 2, "the plain count is two")
	assert_gt(float(clocked[&"raider"]), 1.0, "the near one weighs in full")
	assert_lt(float(clocked[&"raider"]), 2.0, "the far one weighs less than one")
	assert_almost_eq(
		float(clocked[&"raider"]),
		1.0 + Bot.clock_weight(45.0, 10.0, 30.0),
		0.001,
		"the sum of the two clocks"
	)


func test_a_slower_answer_makes_the_far_unit_press_harder() -> void:
	_believe_unit(2, &"raider", Vector3(-90.0, 0.0, 0.0))
	_bot.answer = 10.0
	var quick: float = float(_bot.believed_enemy_composition_clocked()[&"raider"])
	_bot.answer = 40.0
	var slow: float = float(_bot.believed_enemy_composition_clocked()[&"raider"])
	assert_gt(slow, quick, "less time to answer leaves less margin")


func test_the_demand_map_weighs_units_by_the_clock_and_structures_as_before() -> void:
	_believe_unit(2, &"raider", Vector3(-90.0, 0.0, 0.0))
	var entry := CommanderBlackboard.Entry.new()
	entry.instance_id = 3
	entry.type = &"wall"
	entry.is_structure = true
	entry.last_known_location = Vector3(-90.0, 0.0, 0.0)
	_bot.blackboard._entries[3] = entry
	_bot.structure_demand_weight = 0.4
	var demand: Dictionary = _bot.enemy_demand_map()
	# No live rep for either fake type, so demand is importance ÷ 1 (coverage 0).
	assert_almost_eq(float(demand[&"raider"]["demand"]), Bot.clock_weight(45.0, 10.0, 30.0), 0.001)
	assert_almost_eq(float(demand[&"wall"]["demand"]), 0.4, 0.001, "a structure keeps its weight")


func test_a_bot_with_no_map_reads_every_believed_unit_as_pressing() -> void:
	_bot._fields = null
	_believe_unit(2, &"raider", Vector3(-90.0, 0.0, 0.0))
	assert_eq(float(_bot.believed_enemy_composition_clocked()[&"raider"]), 1.0)


func test_the_fields_switch_off_leaves_every_consumer_its_old_rule() -> void:
	_believe_unit(2, &"raider", Vector3(-90.0, 0.0, 0.0))
	_bot.use_fields = false
	assert_null(_bot.fields(), "off: no fields to read")
	assert_eq(float(_bot.believed_enemy_composition_clocked()[&"raider"]), 1.0, "unclocked")
	_bot.use_fields = true
	assert_not_null(_bot.fields(), "on again: the fields it already had")
