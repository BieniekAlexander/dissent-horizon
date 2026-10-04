extends GutTest

## Staged reinforcements and the wave gates — BotMilitary's answer to an army that arrived
## one unit at a time (gdd/systems/ai/squads-and-relations.md §What started it).
##
## The fixture is the same stub piece test_BotClaimsInManagers builds: a Commandable with a
## weapon and a Movement, owned by a Bot in a bare Scenario, so _combat_units admits it. The
## Bot overrides the senses the military reads — a unit's price, where home is, army value —
## because they come from the world and a unit test has none.


class StubPiece:
	extends Commandable

	static func make() -> StubPiece:
		var piece := StubPiece.new()
		for pair: Array in [
			["Ownership", Ownership.new()],
			["AvoidanceObstacle", NavigationObstacle3D.new()],
			["Veterancy", Veterancy.new()]
		]:
			var node: Node = pair[1]
			node.name = pair[0]
			piece.add_child(node)
		var bar := Node3D.new()
		bar.name = "HPBar"
		var fill := Sprite3D.new()
		fill.name = "HPBarFill"
		bar.add_child(fill)
		piece.add_child(bar)
		return piece

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


## Every unit costs the same, home is a fixed point, and the army's value and the enemy's are
## whatever the test says.
class FakeBot:
	extends Bot
	const UNIT_PRICE: int = 100
	const HOME: Vector3 = Vector3(10.0, 0.0, 10.0)
	var army_value: float = 0.0
	var believed_value: float = 0.0
	var producers: Array = []
	var now: float = 0.0
	var holding_hosts: Array = []

	func seconds_elapsed() -> float:
		return now

	func get_hosts_holding_my_units() -> Array:
		return holding_hosts

	func unit_cost(_a_unit_type) -> int:
		return UNIT_PRICE

	func base_centroid() -> Vector3:
		return HOME

	func army_resource_value() -> float:
		return army_value

	func believed_enemy_army_value() -> float:
		return believed_value

	func get_production_structures() -> Array:
		return producers


## Records orders instead of issuing them, so no map is needed. One entry per call, so a
## test can tell "sent as a body" from "sent one at a time".
class RecordingActuator:
	extends BotActuator
	var attack_moves: Array = []  # [{"units": Array, "to": Vector3}]
	var rallies: Array = []  # [{"structures": Array, "to": Vector3}]

	func attack_move(
		a_units: Array,
		a_world_pos: Vector3,
		_a_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_STRUCTURES
	) -> void:
		attack_moves.append({"units": a_units.duplicate(), "to": a_world_pos})

	func rally(a_structures: Array, a_world_pos: Vector3) -> void:
		rallies.append({"structures": a_structures.duplicate(), "to": a_world_pos})

	var evacuated: Array = []

	func evacuate(a_hosts: Array) -> void:
		evacuated.append_array(a_hosts)


const OBJECTIVE: Vector3 = Vector3(110.0, 0.0, 10.0)

var _scenario: Scenario
var _bot: FakeBot
var _act: RecordingActuator
var _military: BotMilitary


func before_each() -> void:
	_scenario = autofree(Scenario.new()) as Scenario
	_bot = FakeBot.new()
	_bot.id = 1
	_bot.initialize(null, _scenario)
	add_child_autofree(_bot)
	_scenario.commanders = [_bot]
	_act = RecordingActuator.new(null)
	_military = BotMilitary.new(_bot, _act)


func _armed_unit(a_at: Vector3 = Vector3.ZERO) -> Commandable:
	var piece: StubPiece = StubPiece.make()
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	var loadout := autofree(Loadout.new()) as Loadout
	var weapon := Weapon.new()
	weapon.melee_damage = 10.0
	loadout.add_child(weapon)
	piece.weapon_inventory = loadout
	var movement := autofree(Movement.new()) as Movement
	piece.movement = movement
	return piece


## A wave in the field: `a_members` are its units and it launched at `a_value`.
func _launch_wave(a_members: Array, a_value: float) -> void:
	_military._wave_active = true
	_military._wave_launch_value = a_value
	for unit: Commandable in a_members:
		_military._wave_members[unit.get_instance_id()] = true


func _destinations_of(a_unit: Commandable) -> Array:
	var out: Array = []
	for call: Dictionary in _act.attack_moves:
		if call["units"].has(a_unit):
			out.append(call["to"])
	return out


func _staging() -> Vector3:
	return _military._staging_point(OBJECTIVE)


# ─── STAGING ─────────────────────────────────────────────────────────────────


func test_the_staging_point_is_on_the_threat_side_of_home() -> void:
	var staging: Vector3 = _staging()
	assert_almost_eq(
		staging.distance_to(FakeBot.HOME), BotMilitary.STAGING_OFFSET, 0.001, "offset from home"
	)
	assert_lt(
		staging.distance_to(OBJECTIVE), FakeBot.HOME.distance_to(OBJECTIVE), "toward the objective"
	)


func test_a_new_unit_stages_instead_of_walking_to_the_front_alone() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	var recruit := _armed_unit(FakeBot.HOME)
	_military._tick_reinforcements(OBJECTIVE)
	assert_eq(_destinations_of(recruit), [_staging()], "the recruit gathers at the staging point")
	assert_false(_military._is_wave_member(recruit), "and is not in the wave yet")


func test_a_staged_unit_already_there_is_left_alone() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_armed_unit(_staging())
	_act.attack_moves.clear()
	_military._tick_reinforcements(OBJECTIVE)
	var to_staging: Array = _act.attack_moves.filter(
		func(call: Dictionary) -> bool: return call["to"] == _staging()
	)
	assert_eq(to_staging.size(), 0, "nobody is told to walk to where they stand")


func test_an_idle_wave_member_presses_on_to_the_objective() -> void:
	# Idle short of the objective — its fight ended on the way — not standing on it.
	var veteran := _armed_unit(OBJECTIVE + Vector3(-20.0, 0.0, 0.0))
	_launch_wave([veteran], 1000.0)
	_military._tick_reinforcements(OBJECTIVE)
	assert_eq(_destinations_of(veteran), [OBJECTIVE])


func test_the_reserve_is_released_as_a_body_once_it_is_worth_sending() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.reinforce_fraction = 0.5
	# Four units at 100 are worth 400 against a 500 bar: they stage.
	var reserve: Array = []
	for i: int in 4:
		reserve.append(_armed_unit(FakeBot.HOME))
	_military._tick_reinforcements(OBJECTIVE)
	for unit: Commandable in reserve:
		assert_false(_military._is_wave_member(unit), "400 of 500: still staging")
	# The fifth tips it, and ALL five go together in one order.
	reserve.append(_armed_unit(FakeBot.HOME))
	_act.attack_moves.clear()
	_military._tick_reinforcements(OBJECTIVE)
	var release: Array = _act.attack_moves.filter(
		func(call: Dictionary) -> bool: return call["to"] == OBJECTIVE and call["units"].size() == 5
	)
	assert_eq(release.size(), 1, "one order carrying the whole reserve to the objective")
	for unit: Commandable in reserve:
		assert_true(_military._is_wave_member(unit), "released units are the wave's now")


func test_a_spent_wave_releases_the_reserve_however_small() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	var recruit := _armed_unit(FakeBot.HOME)
	veteran.free()
	_military._tick_reinforcements(OBJECTIVE)
	assert_eq(_destinations_of(recruit), [OBJECTIVE], "nobody is left at the front to wait for")
	assert_true(_military._wave_members.is_empty() or _military._is_wave_member(recruit))


func test_zero_fraction_is_the_old_trickle() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.reinforce_fraction = 0.0
	var recruit := _armed_unit(FakeBot.HOME)
	_military._tick_reinforcements(OBJECTIVE)
	assert_eq(_destinations_of(recruit), [OBJECTIVE], "the A/B arm: straight to the front, alone")


# ─── THE WAVE GATES ARE IN SERIES ─────────────────────────────────────────────


func _ahead_in_value() -> void:
	_bot.army_value = 1000.0
	_bot.believed_value = 0.0
	_military.attack_value_ratio = 1.0  # 1000 against the 850 humility prior clears a bar of 1.0


func test_value_alone_does_not_launch_a_wave() -> void:
	_ahead_in_value()
	_armed_unit()
	_military.army_commit_threshold = 2
	assert_false(_military._committing_to_attack(), "one body short of the count")
	assert_false(_military._wave_active)


func test_count_alone_does_not_launch_a_wave() -> void:
	_bot.army_value = 1000.0
	_bot.believed_value = 5000.0  # badly behind
	_military.attack_value_ratio = 1.3
	_armed_unit()
	_armed_unit()
	_military.army_commit_threshold = 2
	assert_false(_military._committing_to_attack(), "enough bodies, but outgunned")
	assert_eq(_military._decide_posture(), BotMilitary.Posture.MASS, "and no count-only ATTACK")


func test_both_gates_met_launches_a_wave() -> void:
	_ahead_in_value()
	_armed_unit()
	_armed_unit()
	_military.army_commit_threshold = 2
	assert_true(_military._committing_to_attack())
	assert_true(_military._wave_active)
	assert_eq(_military._wave_launch_value, 1000.0)


# ─── RALLY ───────────────────────────────────────────────────────────────────


func test_producers_rally_to_the_point_and_only_when_it_moves() -> void:
	var producer: StubPiece = StubPiece.make()
	add_child_autofree(producer)
	_bot.producers = [producer]
	_military._rally_production(FakeBot.HOME, false)
	assert_eq(_act.rallies.size(), 1, "the first point is always issued")
	assert_eq(_act.rallies[0]["to"], FakeBot.HOME)
	producer.set_rally(MoveCommand.new(CommandMessage.new(null, null, null, FakeBot.HOME)))
	_military._rally_production(FakeBot.HOME, false)
	assert_eq(_act.rallies.size(), 1, "the same point again is not re-issued")
	_military._rally_production(OBJECTIVE, false)
	assert_eq(_act.rallies.size(), 2, "a moved point is")


func test_a_producer_without_a_rally_gets_the_standing_one() -> void:
	var old: StubPiece = StubPiece.make()
	add_child_autofree(old)
	old.set_rally(MoveCommand.new(CommandMessage.new(null, null, null, FakeBot.HOME)))
	var fresh: StubPiece = StubPiece.make()
	add_child_autofree(fresh)
	_bot.producers = [old, fresh]
	_military._rally_point = FakeBot.HOME
	_military._has_rally = true
	_military._rally_production(FakeBot.HOME, false)
	assert_eq(_act.rallies.size(), 1)
	assert_eq(_act.rallies[0]["structures"], [fresh], "only the one that has none")


# ─── WHERE THE ARMY STANDS ───────────────────────────────────────────────────


## A bot that owns structures: the fake's HOME is still the centroid it reports, and the
## structures are what frontmost_structure walks.
func _structure_at(a_at: Vector3) -> Commandable:
	var piece: Commandable = FakePieces.structure({})
	_bot.add_child(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	return piece


func test_the_frontmost_structure_is_the_one_furthest_along_the_threat_axis() -> void:
	var rear := _structure_at(FakeBot.HOME + Vector3(-20.0, 0.0, 0.0))
	var front := _structure_at(FakeBot.HOME + Vector3(20.0, 0.0, 0.0))
	assert_eq(_bot.frontmost_structure(Vector2(1.0, 0.0)), front)
	assert_eq(_bot.frontmost_structure(Vector2(-1.0, 0.0)), rear, "the other way round, the other")


func test_the_army_stands_in_front_of_the_exposed_structure_not_on_the_centroid() -> void:
	_structure_at(FakeBot.HOME + Vector3(-20.0, 0.0, 0.0))
	var front := _structure_at(FakeBot.HOME + Vector3(20.0, 0.0, 0.0))
	var station: Vector3 = _military._station_point(Vector2(1.0, 0.0))
	assert_almost_eq(station.distance_to(front.global_position), BotMilitary.STAGING_OFFSET, 0.001)
	assert_gt(station.x, front.global_position.x, "on the threat side of it")


func test_with_no_structure_the_station_is_in_front_of_home() -> void:
	var station: Vector3 = _military._station_point(Vector2(0.0, 1.0))
	assert_almost_eq(station.distance_to(FakeBot.HOME), BotMilitary.STAGING_OFFSET, 0.001)


# ─── ARRIVED UNITS ARE LEFT STANDING; A WAVE THAT FINDS NOTHING MOVES ON ─────


func test_a_unit_standing_on_its_destination_is_not_re_ordered() -> void:
	var there := _armed_unit(OBJECTIVE + Vector3(1.0, 0.0, 0.0))
	var away := _armed_unit(FakeBot.HOME)
	_military._send_idle([there, away], OBJECTIVE)
	assert_eq(
		_destinations_of(there), [], "arrived: an order to walk to where it stands is the swarm"
	)
	assert_eq(_destinations_of(away), [OBJECTIVE])


func test_an_idle_wave_member_standing_on_the_objective_is_left_alone() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military._tick_reinforcements(OBJECTIVE)
	assert_eq(_destinations_of(veteran), [])


func test_a_wave_standing_on_a_silent_objective_abandons_it() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military._has_objective = true
	_bot.now = 100.0
	_military._objective_since = 100.0
	_military._check_objective_stall(OBJECTIVE)
	assert_false(_military._is_abandoned(OBJECTIVE), "not yet: the clock has just started")
	_bot.now = 100.0 + BotMilitary.OBJECTIVE_STALL_SECONDS + 1.0
	_military._check_objective_stall(OBJECTIVE)
	assert_true(_military._is_abandoned(OBJECTIVE), "stood there with nothing to fight: abandoned")
	assert_false(_military._has_objective, "and the next think picks afresh")
	_bot.now += BotMilitary.OBJECTIVE_ABANDON_SECONDS
	assert_false(_military._is_abandoned(OBJECTIVE), "a cooldown, not a ban")


func test_a_wave_still_travelling_or_fighting_is_not_stalled() -> void:
	var veteran := _armed_unit(FakeBot.HOME)  # far from the objective: travelling
	_launch_wave([veteran], 1000.0)
	_bot.now = 100.0
	_military._objective_since = 0.0
	_military._check_objective_stall(OBJECTIVE)
	assert_false(_military._is_abandoned(OBJECTIVE))
	assert_eq(_military._objective_since, 100.0, "travelling restarts the clock")
	veteran.global_position = OBJECTIVE
	_military.claims.claim(veteran, BotTargeting.CLAIM_OWNER, BotClaims.Priority.COMBAT)
	_bot.now = 200.0
	_military._objective_since = 0.0
	_military._check_objective_stall(OBJECTIVE)
	assert_false(_military._is_abandoned(OBJECTIVE), "fighting is not standing still")


func test_an_abandoned_objective_covers_the_ground_around_it() -> void:
	_bot.now = 10.0
	_military._abandon_objective(OBJECTIVE)
	assert_true(_military._is_abandoned(OBJECTIVE + Vector3(BotMilitary.HOLD_RADIUS, 0.0, 0.0)))
	assert_false(_military._is_abandoned(OBJECTIVE + Vector3(100.0, 0.0, 0.0)))


func test_a_wave_launch_collects_the_bunkered_units() -> void:
	var host: StubPiece = StubPiece.make()
	add_child_autofree(host)
	_bot.holding_hosts = [host]
	var unit := _armed_unit(FakeBot.HOME)
	_military._launch([unit], OBJECTIVE)
	assert_eq(_act.evacuated, [host], "the hosts holding its units are turned out first")
	assert_true(_military._is_wave_member(unit))
	assert_eq(_destinations_of(unit), [OBJECTIVE])
