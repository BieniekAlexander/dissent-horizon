extends GutTest

## The overlay's category layers, driven against a stub bot whose beliefs and figures are
## supplied: what each draws for a given state, and how it colours it.


class StubBot:
	extends Bot
	var now: float = 0.0
	var armed: Dictionary = {}  # type -> true
	var demand: Dictionary = {}

	func seconds_elapsed() -> float:
		return now

	func unit_can_attack(a_type) -> bool:
		return armed.has(a_type)

	func unit_cost(_a_type) -> int:
		return 100

	func army_resource_value() -> float:
		return 250.0

	func enemy_demand_map() -> Dictionary:
		return demand


var _bot: StubBot


func before_each() -> void:
	_bot = StubBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_bot.blackboard = CommanderBlackboard.new(_bot)


func _believe(a_id: int, a_type: StringName, a_is_structure: bool, a_seen_at: float) -> void:
	var entry := CommanderBlackboard.Entry.new()
	entry.instance_id = a_id
	entry.type = a_type
	entry.is_structure = a_is_structure
	entry.last_known_location = Vector3(a_id, 0.0, 0.0)
	entry.last_seen_time = a_seen_at
	_bot.blackboard._entries[a_id] = entry


# ─── ENEMY PICTURE ───────────────────────────────────────────────────────────


func test_a_believed_unit_is_a_filled_mark_and_a_structure_an_outline() -> void:
	_believe(1, &"soldier", false, 0.0)
	var pen := BotDebugPen.new()
	BotDebugEnemyPictureLayer.new().draw(_bot, pen)
	assert_eq(pen.triangle_vertex_count(), 6)
	assert_eq(pen.line_vertex_count(), 0, "an unarmed unit has no stick")

	_believe(2, &"depot", true, 0.0)
	pen = BotDebugPen.new()
	BotDebugEnemyPictureLayer.new().draw(_bot, pen)
	assert_eq(pen.triangle_vertex_count(), 6)
	assert_eq(pen.line_vertex_count(), 8)


func test_a_piece_that_can_shoot_carries_a_stick() -> void:
	_believe(1, &"soldier", false, 0.0)
	_bot.armed[&"soldier"] = true
	var pen := BotDebugPen.new()
	BotDebugEnemyPictureLayer.new().draw(_bot, pen)
	assert_eq(pen.line_vertex_count(), 2)


func test_in_view_reads_red_and_a_remembered_unit_fades_to_its_expiry() -> void:
	var layer := BotDebugEnemyPictureLayer
	assert_eq(layer.belief_color(true, false, 0.0), layer.COLOR_IN_VIEW)
	assert_almost_eq(layer.belief_color(false, false, 0.0).a, layer.REMEMBERED_ALPHA_FRESH, 1e-5)
	var lapsing: float = (
		layer.belief_color(false, false, CommanderBlackboard.BLACKBOARD_EXPIRATION).a
	)
	assert_almost_eq(lapsing, layer.REMEMBERED_ALPHA_LAPSING, 1e-5)


func test_a_remembered_structure_does_not_fade() -> void:
	var layer := BotDebugEnemyPictureLayer
	var long_ago: float = CommanderBlackboard.BLACKBOARD_EXPIRATION * 10.0
	assert_eq(layer.belief_color(false, true, 0.0), layer.belief_color(false, true, long_ago))


func test_the_readout_counts_beliefs_and_ranks_counter_demand() -> void:
	_believe(1, &"soldier", false, 0.0)
	_believe(2, &"soldier", false, 0.0)
	_believe(3, &"depot", true, 0.0)
	_bot.blackboard._in_view = {1: true}
	_bot.demand = {&"low": {"demand": 0.5}, &"high": {"demand": 2.0}}
	var lines: PackedStringArray = BotDebugEnemyPictureLayer.new().readout(_bot)
	assert_eq(lines[0], "believed: 2 units (1 in view), 1 structures")
	assert_eq(lines[1], "enemy army: 200 energy believed, own 250")
	assert_true(lines[3].contains("high") and lines[4].contains("low"), "highest demand first")


# ─── SCOUTING ────────────────────────────────────────────────────────────────


func test_grid_points_run_green_to_red_over_the_expiry_and_grey_unseen() -> void:
	var layer := BotDebugScoutingLayer
	assert_eq(layer.recency_color(0.0, false, 0.0), layer.COLOR_NEVER)
	var fresh: Color = layer.recency_color(10.0, true, 10.0)
	assert_true(Color(fresh, 1.0).is_equal_approx(layer.COLOR_FRESH))
	var stale: Color = layer.recency_color(0.0, true, BotScout.SCOUT_EXPIRATION_TIMER * 2.0)
	assert_true(Color(stale, 1.0).is_equal_approx(layer.COLOR_STALE))


func test_a_scout_reads_white_waiting_and_orange_at_the_stall_limit() -> void:
	var layer := BotDebugScoutingLayer
	assert_eq(layer.scout_color(BotScout.SCOUT_STALL_SECONDS, true), layer.COLOR_SCOUT_WAITING)
	assert_eq(layer.scout_color(0.0, false), layer.COLOR_SCOUT)
	var stalled: Color = layer.scout_color(BotScout.SCOUT_STALL_SECONDS, false)
	assert_true(stalled.is_equal_approx(layer.COLOR_SCOUT_STALLED))


func test_a_bot_without_a_brain_draws_no_scouting() -> void:
	var pen := BotDebugPen.new()
	BotDebugScoutingLayer.new().draw(_bot, pen)
	assert_true(pen.is_empty())
	assert_eq(
		BotDebugScoutingLayer.new().readout(_bot), PackedStringArray(["no scout manager yet"])
	)


# ─── BASE DEFENCE ────────────────────────────────────────────────────────────


func test_a_regions_demand_reads_against_the_turret_price() -> void:
	var layer := BotDebugBaseDefenceLayer
	assert_eq(layer.demand_fraction(0.0, 1.0, 400.0), 0.0)
	assert_almost_eq(layer.demand_fraction(200.0, 1.0, 400.0), 0.5, 1e-5)
	assert_almost_eq(layer.demand_fraction(200.0, 2.0, 400.0), 1.0, 1e-5, "propensity scales it")
	assert_eq(layer.demand_fraction(900.0, 1.0, 400.0), 1.0, "capped at the price")
	assert_eq(layer.demand_fraction(10.0, 1.0, 0.0), 1.0, "no turret to price: any demand is full")


func test_a_bot_without_a_brain_draws_no_defence_regions() -> void:
	var layer := BotDebugBaseDefenceLayer.new()
	assert_eq(layer.readout(_bot), PackedStringArray(["no economy manager yet"]))


# ─── ARMY ────────────────────────────────────────────────────────────────────


func test_a_squad_policy_is_drawn_at_the_point_it_holds() -> void:
	var at := Vector3(3.0, 0.0, 4.0)
	assert_eq(BotDebugArmyLayer.policy_point(PostPolicy.new(null, at, 1.0)), at)
	assert_null(BotDebugArmyLayer.policy_point(SquadPolicy.new()), "a policy with no point")
	assert_null(BotDebugArmyLayer.policy_point(null), "no policy")


func test_a_bot_without_a_brain_draws_no_army() -> void:
	var pen := BotDebugPen.new()
	BotDebugArmyLayer.new().draw(_bot, pen)
	assert_true(pen.is_empty())


# ─── ECONOMY ─────────────────────────────────────────────────────────────────


func test_the_savings_lines_name_the_goal_and_a_lifted_claim() -> void:
	var savings := BotSavings.new()
	assert_eq(BotDebugEconomyLayer.savings_lines(savings)[0], "saving for: nothing")
	savings.propose(&"economy", &"factory", 0.6, 1200)
	savings.held = false
	var lines: PackedStringArray = BotDebugEconomyLayer.savings_lines(savings)
	assert_true(lines[0].begins_with("saving for: factory") and lines[0].contains("lifted"))
	assert_eq(lines[1], "  economy wants factory: 0.60 for 1200")


func test_decisions_read_latest_first_with_their_runner_up() -> void:
	var log := BotUsageLog.new()
	log.record_choice("train", {&"a": 0.5, &"b": 0.25}, &"a")
	log.record_choice("tech_structure", {&"lab": 1.0}, &"lab")
	var lines: PackedStringArray = BotDebugEconomyLayer.decision_lines(log.recent_choices())
	assert_eq(lines[0], "  tech_structure: lab (1.00)")
	assert_eq(lines[1], "  train: a (0.50) over b (0.25)")
	assert_eq(
		BotDebugEconomyLayer.decision_lines([] as Array[Dictionary]),
		PackedStringArray(["  none yet"])
	)


# ─── UNIT CONTROL ────────────────────────────────────────────────────────────


func test_each_manager_claims_in_its_own_colour() -> void:
	var layer := BotDebugUnitControlLayer
	assert_ne(layer.owner_color(BotEconomy.CLAIM_OWNER), layer.owner_color(BotScout.CLAIM_OWNER))
	assert_eq(layer.owner_color(&"a_mission_owner"), layer.COLOR_OTHER)


# ─── BOT INTERNALS ───────────────────────────────────────────────────────────


func test_the_personality_lists_only_the_fields_drawn_away_from_the_tier() -> void:
	var tier: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	var layer := BotDebugInternalsLayer
	assert_eq(
		layer.personality_lines(tier.copied(), tier), PackedStringArray(["  the tier exactly"])
	)
	var drawn: BotDifficulty = tier.copied()
	drawn.attack_value_ratio = tier.attack_value_ratio + 0.25
	var lines: PackedStringArray = layer.personality_lines(drawn, tier)
	assert_eq(lines.size(), 1)
	assert_true(lines[0].begins_with("  attack_value_ratio"))
	drawn.wave_abort_fraction = tier.wave_abort_fraction + 0.1
	drawn.reinforce_fraction = tier.reinforce_fraction + 0.1
	lines = layer.personality_lines(drawn, tier)
	assert_eq(lines.size(), 2, "three moved fields, two to a line")


func test_orders_are_totalled_issued_against_refused_per_kind() -> void:
	var log := BotUsageLog.new()
	log.record_action("build", &"tower", BotUsageLog.OUTCOME_ISSUED)
	log.record_action("build", &"wall", BotUsageLog.OUTCOME_ISSUED)
	log.record_action(
		"build",
		&"tower",
		BotUsageLog.refused(MoveCommand.PreconditionFailureCause.MISSING_STRUCTURE)
	)
	assert_eq(
		BotDebugInternalsLayer.action_lines(log.actions()), PackedStringArray(["  build  2 / 1"])
	)


# ─── FIELDS ──────────────────────────────────────────────────────────────────


func test_a_bot_without_fields_draws_nothing_and_says_so() -> void:
	var pen := BotDebugPen.new()
	BotDebugFieldsLayer.new().draw(_bot, pen)
	assert_true(pen.is_empty())
	assert_eq(BotDebugFieldsLayer.new().readout(_bot), PackedStringArray(["no fields yet"]))


func test_the_band_is_tiled_and_the_readout_counts_it() -> void:
	var fields: FixtureFields = FixtureFields.over_open(Rect2(0.0, 0.0, 45.0, 45.0))
	fields.add_walker(Vector2i(0, 4), 2.5)
	fields.home = [Vector2i(8, 4)]
	_bot._fields = fields
	var band: int = 0
	for b: int in fields.approach_band(NavAgentClass.Size.SMALL):
		band += b
	assert_gt(band, 0)
	var pen := BotDebugPen.new()
	BotDebugFieldsLayer.new().draw(_bot, pen)
	# Every lattice cell the enemy can reach inside the horizon is a quad (two triangles), the
	# band cells among them; nothing is drawn for quiet ground.
	assert_gte(pen.triangle_vertex_count(), band * 6)
	var lines: PackedStringArray = BotDebugFieldsLayer.new().readout(_bot)
	assert_true(lines[2].contains("approach band: %d cells" % band), lines[2])
	assert_true(lines[0].contains("ready"), lines[0])


func test_arrival_shades_red_now_to_blue_at_the_horizon() -> void:
	var layer := BotDebugFieldsLayer
	assert_true(layer.arrival_color(0.0).is_equal_approx(layer.COLOR_SOON))
	assert_true(
		layer.arrival_color(BotFields.QUIET_HORIZON_SECONDS).is_equal_approx(layer.COLOR_LATE)
	)
