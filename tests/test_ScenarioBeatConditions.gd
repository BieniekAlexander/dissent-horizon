extends GutTest

## The conditions and spawn anchor a mission's beats are built from (prologue mission 1,
## 2026-10-18): ConditionTriggerFired (a beat has happened), ConditionGarrisonOccupied (the
## player has taken cover in a named building) and EventSpawnEntities.follow_group (spawn beside
## a squad wherever it walked). Synthetic fixtures throughout.

const UNIT: Dictionary = {"speed": 2.0}
const HOST: Dictionary = {"structure": true, "garrison": {"capacity": 4}}
const SQUAD: StringName = &"test_beat_squad"

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


func _piece(a_options: Dictionary, a_commander_id: int, a_name: String = "") -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	if not a_name.is_empty():
		piece.name = a_name
	add_child_autofree(piece)
	var commander := Commander.new()
	commander.id = a_commander_id
	add_child_autofree(commander)
	piece.ownership.commander = commander
	return piece


# --- ConditionTriggerFired ---------------------------------------------------------------


func test_a_trigger_fired_check_follows_its_trigger() -> void:
	var trigger := GlobalTrigger.new()
	trigger.name = "PrisonersFreed"
	_manager.add_child(trigger)
	var condition := ConditionTriggerFired.new()
	condition.trigger_name = "PrisonersFreed"
	assert_false(condition.evaluate(_manager), "not yet")
	trigger.has_fired = true
	assert_true(condition.evaluate(_manager), "the beat has happened")


func test_an_until_fired_check_holds_only_before_its_trigger() -> void:
	var trigger := GlobalTrigger.new()
	trigger.name = "RendezvousReached"
	_manager.add_child(trigger)
	var condition := ConditionTriggerFired.new()
	condition.trigger_name = "RendezvousReached"
	condition.is_until_fired = true
	assert_true(condition.evaluate(_manager), "still waiting")
	trigger.has_fired = true
	assert_false(condition.evaluate(_manager), "the beat has happened")


func test_a_missing_trigger_never_fires_and_says_so() -> void:
	var condition := ConditionTriggerFired.new()
	condition.trigger_name = "NoSuchTrigger"
	assert_false(condition.evaluate(_manager))
	assert_push_warning("no GlobalTrigger named 'NoSuchTrigger'")


# --- ConditionGarrisonOccupied ------------------------------------------------------------


func test_a_garrison_check_marks_its_host() -> void:
	var host: Actor = _piece(HOST, 0, "Farmhouse")
	assert_eq(_occupied(1).highlight_entities(_manager), [host] as Array[Entity])


func _occupied(a_count: int, a_commander_id: int = 1) -> ConditionGarrisonOccupied:
	var condition := ConditionGarrisonOccupied.new()
	condition.host_name = "Farmhouse"
	condition.commander_id = a_commander_id
	condition.count = a_count
	return condition


func test_a_garrison_check_counts_the_commanders_units_inside() -> void:
	var host: Actor = _piece(HOST, 0, "Farmhouse")
	var condition := _occupied(2)
	assert_false(condition.evaluate(_manager), "empty")
	host.garrison.garrison(_piece(UNIT, 1))
	assert_false(condition.evaluate(_manager), "one of two")
	host.garrison.garrison(_piece(UNIT, 1))
	assert_true(condition.evaluate(_manager), "two inside")


func test_a_garrison_check_ignores_another_commanders_units() -> void:
	var host: Actor = _piece(HOST, 0, "Farmhouse")
	host.garrison.garrison(_piece(UNIT, 2))
	assert_false(_occupied(1).evaluate(_manager), "someone else's soldier")
	assert_true(_occupied(1, -1).evaluate(_manager), "unless anyone's will do")


func test_an_everyone_inside_check_waits_for_the_last_unit() -> void:
	var host: Actor = _piece(HOST, 0, "Farmhouse")
	var condition := _occupied(1)
	condition.should_hold_every_unit = true
	host.garrison.garrison(_piece(UNIT, 1))
	var straggler: Actor = _piece(UNIT, 1)
	_piece(UNIT, 2)
	assert_false(condition.evaluate(_manager), "one of ours is still outside")
	host.garrison.garrison(straggler)
	assert_true(condition.evaluate(_manager), "everyone in; another commander's unit is not ours")


# --- ConditionUnitCount.should_count_carried ----------------------------------------------


func test_carried_units_are_the_hosts_own_through_any_nesting() -> void:
	var transport: Actor = _piece(HOST, 1)
	var house: Actor = _piece(HOST, 1)
	var rider: Actor = _piece(UNIT, 1)
	var captive: Actor = _piece(UNIT, 2)
	house.garrison.garrison(rider)
	house.garrison.garrison(captive)
	transport.garrison.garrison(house)
	assert_eq(
		ConditionUnitCount.carried_units(transport),
		[house, rider] as Array[Actor],
		"what it carries, and what that carries; not another commander's captive"
	)


# --- TacticRule.holds_fire ---------------------------------------------------------------


func _tactic_with(a_rules: Array[bool]) -> Array:
	var tactic := ScenarioTactic.new()
	add_child_autofree(tactic)
	var rules: Array[TacticRule] = []
	for holds: bool in a_rules:
		var rule := TacticRule.new()
		rule.holds_fire = holds
		tactic.add_child(rule)
		rules.append(rule)
	return [tactic, rules]


func test_a_rule_that_holds_fire_holds_the_cluster_until_another_takes_over() -> void:
	var made: Array = _tactic_with([true, false])
	var tactic: ScenarioTactic = made[0]
	var members: Array[Actor] = [_piece(UNIT, 2), _piece(UNIT, 2)]
	tactic._hold_fire(members, made[1][0])
	assert_true(members.all(func(m: Actor) -> bool: return m.is_holding_fire), "held")
	tactic._hold_fire(members, made[1][1])
	assert_true(members.all(func(m: Actor) -> bool: return not m.is_holding_fire), "released")


func test_a_rule_without_hold_fire_leaves_a_pieces_own_hold_alone() -> void:
	var made: Array = _tactic_with([false])
	var member: Actor = _piece(UNIT, 2)
	member.is_holding_fire = true
	(made[0] as ScenarioTactic)._hold_fire([member] as Array[Actor], made[1][0])
	assert_true(member.is_holding_fire, "a stealthy piece keeps its own hold")


func test_a_missing_host_holds_nobody() -> void:
	assert_false(_occupied(1).evaluate(_manager))
	assert_push_warning("no piece named 'Farmhouse'")


# --- EventSpawnEntities.follow_group --------------------------------------------------------


func _spawner() -> EventSpawnEntities:
	var event := EventSpawnEntities.new()
	add_child_autofree(event)
	event.global_position = Vector3(-50, 0, -50)
	event.follow_group = SQUAD
	return event


func _member(a_xz: Vector2) -> void:
	var piece: Actor = _piece(UNIT, 2)
	piece.add_to_group(SQUAD)
	piece.global_position = VU.from_xz(a_xz)


func test_a_follow_anchor_is_the_squads_centre_plus_the_offset() -> void:
	_member(Vector2(10, 0))
	_member(Vector2(20, 4))
	var event := _spawner()
	event.follow_offset = Vector2(1, -2)
	var anchor: Vector3 = event.resolve_spawn_anchor()
	assert_almost_eq(anchor.x, 16.0, 0.001)
	assert_almost_eq(anchor.z, 0.0, 0.001)


func test_a_follow_anchor_runs_away_from_its_reference() -> void:
	_member(Vector2(10, 0))
	var building := Node3D.new()
	add_child_autofree(building)
	var event := _spawner()
	event.follow_away_from = building
	event.follow_offset = Vector2(5, 0)
	var anchor: Vector3 = event.resolve_spawn_anchor()
	assert_almost_eq(anchor.x, 15.0, 0.001, "5 further from the building than the squad")
	assert_almost_eq(anchor.z, 0.0, 0.001)
	event.follow_offset = Vector2(0, 3)
	anchor = event.resolve_spawn_anchor()
	assert_almost_eq(VU.in_xz(anchor).distance_to(Vector2(10, 0)), 3.0, 0.001, "beside it")
	assert_almost_eq(anchor.x, 10.0, 0.001, "across the line, not along it")


func test_a_follow_anchor_falls_back_when_the_squad_is_gone() -> void:
	var event := _spawner()
	event.follow_offset = Vector2(5, 0)
	assert_almost_eq(event.resolve_spawn_anchor().x, -50.0, 0.001, "the event's own place")


# --- EventTransferOwnership -----------------------------------------------------------------


func test_a_transfer_hands_the_labelled_pieces_over_and_nothing_else() -> void:
	var receiver := Commander.new()
	receiver.id = 1
	add_child_autofree(receiver)
	var scenario := Scenario.new()
	scenario.commanders = [receiver]
	autofree(scenario)
	_manager.scenario = scenario
	var labelled: Actor = _piece(UNIT, 2)
	labelled.add_to_group(SQUAD)
	var other: Actor = _piece(UNIT, 2)
	var event := EventTransferOwnership.new()
	event.group = SQUAD
	event.commander_id = 1
	autofree(event)
	event.execute(_manager)
	assert_eq(labelled.commander, receiver, "the labelled piece changes hands")
	assert_eq(other.commander_id, 2, "the rest stay where they were")


# --- Aerial.land_in_place -------------------------------------------------------------------


func test_an_aircraft_landed_in_place_is_down_and_stays_down() -> void:
	var raven := _piece({"aerial": true, "speed": 4.0}, 2)
	raven.aerial.land_in_place()
	assert_true(raven.aerial.is_grounded_temp(), "on the ground from its first frame")
	assert_false(raven.aerial.is_airborne())
	assert_true(raven.aerial.is_permanently_grounded(), "and kept there until an order lifts it")
	assert_false(raven.aerial.is_docked(), "in a field, not on a pad")


# --- EventCommandPoint: land, and aiming at a commander's nearest unit -----------------------


func test_a_land_point_makes_a_land_order() -> void:
	var point := EventCommandPoint.new()
	point.command_type = "land"
	add_child_autofree(point)
	assert_true(point.to_command(_manager) is Land)


func test_a_point_near_a_commander_aims_beside_its_nearest_unit() -> void:
	var player := Commander.new()
	player.id = 1
	add_child_autofree(player)
	var scenario := Scenario.new()
	scenario.commanders = [player]
	autofree(scenario)
	_manager.scenario = scenario
	var near: Actor = _piece(UNIT, 1)
	near.ownership.commander = player
	near.add_to_group("unit")
	near.global_position = Vector3(10, 0, 0)
	var far: Actor = _piece(UNIT, 1)
	far.ownership.commander = player
	far.add_to_group("unit")
	far.global_position = Vector3(40, 0, 0)
	var point := EventCommandPoint.new()
	point.near_commander_id = 1
	add_child_autofree(point)
	point.global_position = Vector3(0, 0, 0)
	assert_almost_eq(point.destination(_manager).x, 10.0, 0.001, "the nearest unit's place")
	point.near_standoff = 4.0
	assert_almost_eq(point.destination(_manager).x, 6.0, 0.001, "4 short of it, toward the point")
