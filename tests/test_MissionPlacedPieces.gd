extends GutTest

## The scripting pieces prologue mission 1 added on 2026-10-21, when its start-time pieces were
## placed in the scene rather than spawned and an allied relief was flown in on defection:
## ConditionCommanderInDefection, EntitySelectorGroup, EventIssueCommand.should_post_in_place,
## the `evacuate` and `leave_map` command points, Aerial.should_start_landed and
## EventSpawnEntities.spawn_in_flight. Synthetic fixtures throughout.

const UNIT: Dictionary = {"speed": 2.0}
const AIRCRAFT: Dictionary = {"aerial": true, "speed": 4.0}
const LABEL: StringName = &"test_placed_label"

var _manager: ScenarioTriggerManager


## A map whose ground is flat at zero everywhere, which is all the in-flight spawn reads.
class FlatMap:
	extends Map

	func terrain_height_at(_a_xz: Vector2) -> float:
		return 0.0


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	var scenario := Scenario.new()
	scenario.commanders = [commander]
	autofree(scenario)
	_manager.scenario = scenario
	return commander


func _piece(a_options: Dictionary, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.global_position = a_at
	return piece


# --- ConditionCommanderInDefection ---------------------------------------------------------


func test_a_defection_check_follows_the_commanders_shortfall() -> void:
	var commander: Commander = _commander(3)
	var condition := ConditionCommanderInDefection.new()
	condition.commander_id = 3
	commander.infrastructure_required = commander.infrastructure_provided
	assert_false(condition.evaluate(_manager), "supplied exactly: not in defection")
	commander.infrastructure_required = commander.infrastructure_provided + 1
	assert_true(condition.evaluate(_manager), "one short: in defection")


func test_a_defection_check_on_a_missing_commander_is_false() -> void:
	var condition := ConditionCommanderInDefection.new()
	condition.commander_id = 9
	assert_false(condition.evaluate(_manager))


# --- EntitySelectorGroup -------------------------------------------------------------------


func test_a_group_selector_keeps_only_the_labelled() -> void:
	var labelled: Actor = _piece(UNIT)
	labelled.add_to_group(LABEL)
	var other: Actor = _piece(UNIT)
	var selector := EntitySelectorGroup.new()
	selector.group = LABEL
	autofree(selector)
	var kept: Array[Entity] = selector.filter([labelled, other] as Array[Entity], _manager)
	assert_eq(kept, [labelled] as Array[Entity])


func test_a_group_selector_with_no_group_keeps_nothing() -> void:
	var selector := EntitySelectorGroup.new()
	autofree(selector)
	assert_true(selector.filter([_piece(UNIT)] as Array[Entity], _manager).is_empty())


# --- EventIssueCommand.should_post_in_place -------------------------------------------------


func test_posting_in_place_puts_each_post_where_its_unit_stands() -> void:
	var issue := EventIssueCommand.new()
	issue.should_post_in_place = true
	add_child_autofree(issue)
	var defend := EventCommandPoint.new()
	defend.command_type = "defend"
	issue.add_child(defend)
	defend.global_position = Vector3(10, 0, 10)
	var units: Array[Actor] = [_piece(UNIT, Vector3(3, 0, 4)), _piece(UNIT, Vector3(12, 0, 9))]
	var offsets: Array[Vector3] = issue._formation_offsets(units, _manager, [defend])
	for i: int in units.size():
		assert_almost_eq(
			VU.in_xz(defend.global_position + offsets[i]),
			VU.in_xz(units[i].global_position),
			Vector2(0.001, 0.001),
			"unit %d's post is its own position" % i
		)


# --- the evacuate command point, and the move before it ------------------------------------


func test_an_evacuate_point_makes_an_evacuate_order() -> void:
	var point := EventCommandPoint.new()
	point.command_type = "evacuate"
	add_child_autofree(point)
	assert_true(point.to_command(_manager) is Evacuate)


func test_a_move_before_an_evacuate_stops_at_its_goal() -> void:
	var evacuate := Evacuate.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	assert_false(evacuate.continues_movement(), "a transport sets down where the move ended")


func test_a_leave_map_point_makes_a_leave_map_order_at_its_own_position() -> void:
	var point := EventCommandPoint.new()
	point.command_type = "leave_map"
	add_child_autofree(point)
	point.global_position = Vector3(500, 0, -500)
	var order: MoveCommand = point.to_command(_manager)
	assert_true(order is LeaveMap)
	assert_eq(order.message.position, Vector3(500, 0, -500), "not pulled back onto the navmesh")
	assert_false(order.ends_on_arrival(), "arriving is not leaving")


# --- Aerial.should_start_landed ------------------------------------------------------------


func test_a_placed_aircraft_can_start_on_the_ground() -> void:
	var raven := FakePieces.make(AIRCRAFT) as Actor
	(raven.get_node("Aerial") as Aerial).should_start_landed = true
	add_child_autofree(raven)
	assert_true(raven.aerial.is_grounded_temp(), "down from its first frame")
	assert_true(raven.aerial.is_permanently_grounded(), "and kept there until an order lifts it")


func test_a_placed_aircraft_flies_by_default() -> void:
	var raven: Actor = _piece(AIRCRAFT)
	assert_false(raven.aerial.is_grounded_temp())


# --- EventSpawnEntities.spawn_in_flight -----------------------------------------------------


func test_aircraft_spawned_in_flight_stand_in_a_row_at_the_anchor() -> void:
	var commander: Commander = _commander(2)
	var map := FlatMap.new()
	autofree(map)
	var spawner := EventSpawnEntities.new()
	autofree(spawner)
	var aircraft: Array[Actor] = [
		FakePieces.make(AIRCRAFT) as Actor, FakePieces.make(AIRCRAFT) as Actor
	]
	var walkers: Array[Actor] = [FakePieces.make(UNIT) as Actor]
	autofree(walkers[0])
	var rest: Array[Actor] = spawner._launch_aircraft(
		aircraft + walkers, map, commander, Vector2(100, -50)
	)
	assert_eq(rest, walkers, "a piece that does not fly is left for ground placement")
	var mid: Vector2 = (
		(VU.in_xz(aircraft[0].global_position) + VU.in_xz(aircraft[1].global_position)) * 0.5
	)
	assert_almost_eq(mid, Vector2(100, -50), Vector2(0.001, 0.001), "centred on the anchor")
	assert_ne(aircraft[0].global_position, aircraft[1].global_position, "not stacked")
	assert_eq(aircraft[0].commander, commander, "owned by the spawner's commander")
