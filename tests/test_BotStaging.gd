extends GutTest

## Staged reinforcements and the wave gates — BotMilitary's answer to an army that arrived
## one unit at a time (gdd/systems/ai/squads-and-relations.md §What started it).
##
## The fixture is the same stub piece test_BotClaimsInManagers builds: a Actor with a
## weapon and a Movement, owned by a Bot in a bare Scenario, so _combat_units admits it. The
## Bot overrides the senses the military reads — a unit's price, where home is, army value —
## because they come from the world and a unit test has none.


class StubPiece:
	extends Actor

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

	var under_threat: bool = false
	var threatened: Actor = null
	## What base_threats answers: [{"enemy", "structure", "value"}].
	var threats: Array = []
	## Units whose matchup against anything is 0; every other unit's is 1.
	var harmless: Array = []

	func base_threats(_a_threat_radius: float = 30.0, _a_centre_radius: float = -1.0) -> Array:
		return threats

	func matchup(a_attacker: Actor, _a_target: Actor) -> float:
		return 0.0 if harmless.has(a_attacker) else 1.0

	func is_base_under_threat(_a_threat_radius: float = 30.0) -> bool:
		return under_threat

	func most_threatened_structure(_a_threat_radius: float = 30.0) -> Actor:
		return threatened


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

	var attacks: Array = []  # [{"units": Array, "target": Entity}]

	func attack(a_units: Array, a_target: Entity, _a_persist: bool = true) -> void:
		attacks.append({"units": a_units.duplicate(), "target": a_target})


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


func _armed_unit(a_at: Vector3 = Vector3.ZERO) -> Actor:
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


## A wave in the field: `a_members` are its units and it launched at `a_value`, already
## ordered on to OBJECTIVE (the launch is not what these tests watch).
func _launch_wave(a_members: Array, a_value: float) -> void:
	_military._wave_active = true
	_military._wave_launch_value = a_value
	_military._posture = BotMilitary.Posture.ATTACK
	_military._main.add_all(a_members)
	_military._main.policy = AssaultPolicy.new(
		_bot, _act, OBJECTIVE, null, 0, BotMilitary.OBJECTIVE_EPSILON
	)
	_military._main._issued = _military._main.policy
	for unit: Actor in a_members:
		_military._main._reached[unit.get_instance_id()] = true


## One ATTACK think with nothing changed: the reinforcement rules, then every squad's dispatch.
func _tick_attack() -> void:
	_military._tick_reinforcements(OBJECTIVE)
	_military._tick_squads()


func _is_wave_member(a_unit: Actor) -> bool:
	return _military._main.has(a_unit)


func _destinations_of(a_unit: Actor) -> Array:
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
	_tick_attack()
	assert_eq(_destinations_of(recruit), [_staging()], "the recruit gathers at the staging point")
	assert_false(_is_wave_member(recruit), "and is not in the wave yet")


func test_a_staged_unit_already_there_is_left_alone() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_armed_unit(_staging())
	_act.attack_moves.clear()
	_tick_attack()
	var to_staging: Array = _act.attack_moves.filter(
		func(call: Dictionary) -> bool: return call["to"] == _staging()
	)
	assert_eq(to_staging.size(), 0, "nobody is told to walk to where they stand")


func test_an_idle_wave_member_presses_on_to_the_objective() -> void:
	# Idle short of the objective — its fight ended on the way — not standing on it.
	var veteran := _armed_unit(OBJECTIVE + Vector3(-20.0, 0.0, 0.0))
	_launch_wave([veteran], 1000.0)
	_tick_attack()
	assert_eq(_destinations_of(veteran), [OBJECTIVE])


func test_the_reserve_is_released_as_a_body_once_it_is_worth_sending() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.reinforce_fraction = 0.5
	# Four units at 100 are worth 400 against a 500 bar: they stage.
	var reserve: Array = []
	for i: int in 4:
		reserve.append(_armed_unit(FakeBot.HOME))
	_tick_attack()
	for unit: Actor in reserve:
		assert_false(_is_wave_member(unit), "400 of 500: still staging")
	# The fifth tips it, and ALL five go together in one order.
	reserve.append(_armed_unit(FakeBot.HOME))
	_act.attack_moves.clear()
	_tick_attack()
	var release: Array = _act.attack_moves.filter(
		func(call: Dictionary) -> bool: return call["to"] == OBJECTIVE and call["units"].size() == 5
	)
	assert_eq(release.size(), 1, "one order carrying the whole reserve to the objective")
	for unit: Actor in reserve:
		assert_true(_is_wave_member(unit), "released units are the wave's now")


func test_a_spent_wave_releases_the_reserve_however_small() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	var recruit := _armed_unit(FakeBot.HOME)
	veteran.free()
	_tick_attack()
	assert_eq(_destinations_of(recruit), [OBJECTIVE], "nobody is left at the front to wait for")
	assert_true(_is_wave_member(recruit), "and is the wave now")


func test_zero_fraction_is_the_old_trickle() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.reinforce_fraction = 0.0
	var recruit := _armed_unit(FakeBot.HOME)
	_tick_attack()
	assert_eq(_destinations_of(recruit), [OBJECTIVE], "the A/B arm: straight to the front, alone")


func test_a_cap_of_one_squad_is_the_trickle_whatever_the_fraction_says() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.reinforce_fraction = 1.0
	_military.squad_cap = 1
	var recruit := _armed_unit(FakeBot.HOME)
	_tick_attack()
	assert_eq(_destinations_of(recruit), [OBJECTIVE], "one body: no reserve to stage in")
	assert_true(_is_wave_member(recruit))
	assert_true(_military._reserve.is_empty())


# ─── THE GUARD ───────────────────────────────────────────────────────────────


## A raid on home while the wave is out: a structure behind home comes under threat.
## A raider of `a_value` beside a building at home; returns the raider, which is where a
## guard is sent.
func _raid_at_home(a_value: float = float(FakeBot.UNIT_PRICE)) -> Actor:
	var building: StubPiece = StubPiece.make()
	add_child_autofree(building)
	building.global_position = FakeBot.HOME + Vector3(-30.0, 0.0, 0.0)
	var raider: StubPiece = StubPiece.make()
	add_child_autofree(raider)
	raider.global_position = building.global_position + Vector3(-3.0, 0.0, 0.0)
	_bot.under_threat = true
	_bot.threatened = building
	_bot.threats = [{"enemy": raider, "structure": building, "value": a_value}]
	return raider


func _end_raid() -> void:
	_bot.under_threat = false
	_bot.threatened = null
	_bot.threats = []


func test_under_a_cap_of_three_the_reserve_answers_a_raid_while_the_wave_is_out() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 3
	_military.reinforce_fraction = 1.0
	var recruit := _armed_unit(FakeBot.HOME)
	_tick_attack()
	assert_true(_military._reserve.has(recruit), "staged, like any reserve")
	var raider: Actor = _raid_at_home()
	_act.attack_moves.clear()
	_tick_attack()
	assert_true(_military._guard.has(recruit), "the reserve is the guard now")
	assert_false(_military._reserve.has(recruit))
	assert_eq(_destinations_of(recruit), [raider.global_position], "and goes at the raider")
	assert_eq(_destinations_of(veteran), [], "the wave is left to its objective")
	_end_raid()
	_tick_attack()
	assert_true(_military._reserve.has(recruit), "threat over: the reserve again")
	assert_true(_military._guard.is_empty())


func test_under_a_cap_of_two_there_is_no_guard_and_the_reserve_stays_staged() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 2
	_military.reinforce_fraction = 1.0
	var recruit := _armed_unit(FakeBot.HOME)
	_tick_attack()
	_raid_at_home()
	_tick_attack()
	assert_true(_military._reserve.has(recruit), "two squads: wave and reserve, nothing else")
	assert_true(_military._guard.is_empty())


func test_the_guard_takes_only_what_the_threat_needs_and_the_rest_reinforces() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 3
	_military.reinforce_fraction = 1.0
	_military.guard_strength_ratio = 1.5
	var recruits: Array = [_armed_unit(), _armed_unit(), _armed_unit(), _armed_unit()]
	_raid_at_home(float(FakeBot.UNIT_PRICE))  # one unit's worth: 1.5 of it takes two
	_tick_attack()
	assert_eq(_military._guard.size(), 2, "enough to beat the raid, and no more")
	assert_eq(_military._reserve.size(), 2, "the rest is still the wave's reserve")
	for unit: Actor in recruits:
		assert_true(_military._guard.has(unit) or _military._reserve.has(unit))


func test_a_guard_grows_and_shrinks_with_the_threat() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 3
	_military.reinforce_fraction = 1.0
	_military.guard_strength_ratio = 1.0
	for i: int in 4:
		_armed_unit()
	_raid_at_home(float(FakeBot.UNIT_PRICE))
	_tick_attack()
	assert_eq(_military._guard.size(), 1)
	_raid_at_home(3.0 * FakeBot.UNIT_PRICE)
	_tick_attack()
	assert_eq(_military._guard.size(), 3, "a bigger raid draws more")
	_raid_at_home(float(FakeBot.UNIT_PRICE))
	_tick_attack()
	assert_eq(_military._guard.size(), 1, "and gives them back as it shrinks")
	assert_eq(_military._reserve.size(), 3)


func test_a_unit_that_cannot_hurt_the_threat_never_guards() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 3
	_military.reinforce_fraction = 1.0
	var useless := _armed_unit()
	_bot.harmless.append(useless)
	var useful := _armed_unit()
	_raid_at_home()
	_tick_attack()
	assert_true(_military._guard.has(useful))
	assert_false(_military._guard.has(useless), "it would stand beside the raider uselessly")
	assert_true(_military._reserve.has(useless))


func test_the_guard_is_not_released_to_the_wave_while_it_holds() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_military.squad_cap = 3
	_military.reinforce_fraction = 0.1  # a single recruit would be released at once
	var recruit := _armed_unit(FakeBot.HOME)
	_raid_at_home()
	_tick_attack()
	assert_true(_military._guard.has(recruit), "a raid at home outranks reinforcing")
	assert_false(_destinations_of(recruit).has(OBJECTIVE))


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
	assert_eq(
		_military._wave_launch_value,
		2.0 * FakeBot.UNIT_PRICE,
		"what the wave sends, not the army's whole value: it is the wave the spent test reads"
	)


func test_a_wave_is_spent_by_its_own_losses_whatever_stands_at_home() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 10.0 * FakeBot.UNIT_PRICE)
	_bot.army_value = 50.0 * FakeBot.UNIT_PRICE  # a big guard and reserve at home
	assert_false(_military._committing_to_attack(), "one unit left of ten: spent")
	assert_false(_military._wave_active)


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
func _structure_at(a_at: Vector3) -> Actor:
	var piece: Actor = FakePieces.structure({})
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
	HoldPolicy.new(_act, OBJECTIVE, BotMilitary.OBJECTIVE_EPSILON).issue([there, away])
	assert_eq(
		_destinations_of(there), [], "arrived: an order to walk to where it stands is the swarm"
	)
	assert_eq(_destinations_of(away), [OBJECTIVE])


func test_an_idle_wave_member_standing_on_the_objective_is_left_alone() -> void:
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_tick_attack()
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
	_military._launch(OBJECTIVE)
	_military._tick_squads()
	assert_eq(_act.evacuated, [host], "the hosts holding its units are turned out first")
	assert_true(_is_wave_member(unit))
	assert_eq(_destinations_of(unit), [OBJECTIVE])


# ─── A WAVE THAT HAS ARRIVED RAZES THE BUILDING IT CAME FOR ───────────────────


## Make `a_building` the wave's objective the way _objective_for does: the reference for the
## Attack order, and the BELIEF that says it is still standing — which is what
## AssaultPolicy.is_target_standing asks, never the node.
func _set_objective(a_building: Actor) -> void:
	if _bot.blackboard == null:
		_bot.blackboard = CommanderBlackboard.new(_bot)
	_bot.blackboard._upsert(a_building, 0.0)
	_military._objective_entity = a_building
	_military._objective_id = a_building.get_instance_id()
	var assault: AssaultPolicy = _military._main.policy as AssaultPolicy
	assault.target = a_building
	assault.target_id = a_building.get_instance_id()


func test_an_idle_wave_member_at_the_objective_attacks_the_building_behind_it() -> void:
	var building: StubPiece = StubPiece.make()
	add_child_autofree(building)
	building.global_position = OBJECTIVE + Vector3(6.0, 0.0, 0.0)
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_set_objective(building)
	_tick_attack()
	assert_eq(_act.attacks.size(), 1, "one Attack order")
	assert_eq(_act.attacks[0]["units"], [veteran])
	assert_eq(_act.attacks[0]["target"], building)
	assert_eq(_destinations_of(veteran), [], "and no walk to where it stands")


func test_a_wave_member_short_of_the_objective_keeps_walking_rather_than_attacking() -> void:
	var building: StubPiece = StubPiece.make()
	add_child_autofree(building)
	var veteran := _armed_unit(OBJECTIVE + Vector3(-40.0, 0.0, 0.0))
	_launch_wave([veteran], 1000.0)
	_set_objective(building)
	_tick_attack()
	assert_eq(_act.attacks, [])
	assert_eq(_destinations_of(veteran), [OBJECTIVE])


func test_a_razed_objective_is_not_attacked() -> void:
	var building: StubPiece = StubPiece.make()
	add_child(building)  # freed below, by the test itself
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_set_objective(building)
	building.free()
	_tick_attack()
	assert_eq(_act.attacks, [], "a freed building cannot be handed to an Attack order")


func test_an_objective_no_longer_believed_is_not_attacked() -> void:
	# The fog-honest half of the rule above: the bot does not know a building fell until it
	# sees the spot empty, and it stops attacking the moment the BELIEF goes — the node's
	# fate is never consulted.
	var building: StubPiece = StubPiece.make()
	add_child_autofree(building)
	building.global_position = OBJECTIVE + Vector3(6.0, 0.0, 0.0)
	var veteran := _armed_unit(OBJECTIVE)
	_launch_wave([veteran], 1000.0)
	_set_objective(building)
	_bot.blackboard._entries.erase(building.get_instance_id())
	_tick_attack()
	assert_eq(_act.attacks, [], "no belief, no Attack — whatever the node says")


# ─── CRUSHING COUNTS AS EFFECTIVENESS ───────────────────────────────────────


func _mover(a_class: Movement.CrushClass) -> Movement:
	var movement := autofree(Movement.new()) as Movement
	movement.crush_class = a_class
	return movement


func test_a_heavy_vehicle_counts_as_a_counter_to_infantry_it_can_run_over() -> void:
	var infantry := _armed_unit()
	infantry.movement.crush_class = Movement.CrushClass.TINY
	assert_true(Bot.crushes(_mover(Movement.CrushClass.LARGE), infantry))
	assert_false(Bot.crushes(_mover(Movement.CrushClass.TINY), infantry), "a peer cannot")
	assert_false(Bot.crushes(null, infantry))
	assert_lt(
		Bot.CRUSH_EFFECTIVENESS, 1.0, "below parity: contact is incidental under the bot's orders"
	)
	assert_gt(Bot.CRUSH_EFFECTIVENESS, 0.0, "but never useless")


# ─── A DRIFTING OBJECTIVE IS NOT A NEW ONE ──────────────────────────────────


## A military whose posture and objective are set by the test, so tick() can be driven
## through its change rule without a believed enemy to find.
class SteeredMilitary:
	extends BotMilitary
	var objective: Variant = null
	## The believed structure behind `objective`, as _objective_for would name it; 0 for none.
	var objective_id: int = 0

	func _decide_posture() -> Posture:
		return Posture.ATTACK

	func _objective_for(_a_posture: Posture) -> Variant:
		_objective_id = objective_id
		return objective


func test_an_objective_that_drifts_a_little_does_not_relaunch_the_wave() -> void:
	# THE FLAP. A believed unit's last-known location moves every tick it is in sight, and
	# each move re-launched the wave — evacuating every garrison and re-ordering the army at
	# the think rate (observed 2026-10-06 on main).
	var military := SteeredMilitary.new(_bot, _act)
	_armed_unit(FakeBot.HOME)
	_bot.holding_hosts = [autofree(Actor.new())]
	military.objective = OBJECTIVE
	military.tick()
	assert_eq(_act.attack_moves.size(), 1, "launched once")
	assert_eq(_act.evacuated.size(), 1, "and emptied the bunker for it")
	military.objective = OBJECTIVE + Vector3(5.0, 0.0, 0.0)  # a soldier walked on
	military.tick()
	assert_eq(_act.evacuated.size(), 1, "a drift is the same objective: no second evacuation")
	# Measured from where the objective now IS, not from where it started.
	military.objective = OBJECTIVE + Vector3(5.0 + BotMilitary.OBJECTIVE_EPSILON + 1.0, 0.0, 0.0)
	military.tick()
	assert_eq(_act.evacuated.size(), 2, "a jump past the epsilon is a new objective")


func _wave_point(a_military: BotMilitary) -> Vector3:
	return (a_military._main.policy as AssaultPolicy).point


func test_a_drift_that_adds_up_re_points_the_wave_without_relaunching_it() -> void:
	# Each think's step is under the epsilon, so none of them is a change by itself; measured
	# against the point the wave holds, the sum is. Seen 2026-10-07: 164 units idle at a point
	# the objective had crept away from.
	var military := SteeredMilitary.new(_bot, _act)
	_armed_unit(FakeBot.HOME)
	_bot.holding_hosts = [autofree(Actor.new())]
	military.objective = OBJECTIVE
	military.tick()
	var step: Vector3 = Vector3(BotMilitary.OBJECTIVE_EPSILON * 0.4, 0.0, 0.0)
	for i: int in 3:
		military.objective += step
		military.tick()
	assert_eq(_wave_point(military), military.objective, "the wave follows the sum of the drift")
	assert_eq(_act.attack_moves[-1]["to"], military.objective, "and is ordered there")
	assert_eq(_act.evacuated.size(), 1, "re-pointed, not relaunched: the bunker is left alone")


func test_a_new_structure_close_by_re_points_the_wave_at_it() -> void:
	# The objective's building fell and the next one stands a short step on: a new target, not
	# the old one drifted. Before, the wave kept the dead building's point and stood there.
	var military := SteeredMilitary.new(_bot, _act)
	_armed_unit(FakeBot.HOME)
	military.objective = OBJECTIVE
	military.objective_id = 1001
	military.tick()
	military.objective = OBJECTIVE + Vector3(BotMilitary.OBJECTIVE_EPSILON * 0.5, 0.0, 0.0)
	military.objective_id = 1002
	military.tick()
	var held: AssaultPolicy = military._main.policy as AssaultPolicy
	assert_eq(held.target_id, 1002, "aimed at the structure the bot now means")
	assert_eq(held.point, military.objective)
