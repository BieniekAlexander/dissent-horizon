extends GutTest

## A garrison order exempts its two halves from RVO avoidance.
##
## The passenger walking into a hold must not steer around the thing it is climbing into,
## and the host driving out to meet it must not shove the passenger aside. Both sides state
## that themselves (MoveCommand.avoidance_exception), and CommandReceiver prefers what the
## order says over the generic follow rule — which asks a narrower question and drops the
## exemption exactly when the two are closest.
##
## Scenes are load()ed INSIDE the tests rather than preloaded at file scope — a file-scope
## preload of an entity scene runs at parse time and can fire Tool's static registry build
## before the registry exists, poisoning every test after it. See CLAUDE.md §Running and
## testing.

const TRANSPORT_PATH: Dictionary = FakePieces.PLAIN
const SOLDIER_PATH: Dictionary = FakePieces.SOLDIER
const OPEN_GARRISON_PATH: Dictionary = FakePieces.BUILDING


func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _entity(a_options: Dictionary, a_commander_id: int) -> Actor:
	var e := FakePieces.make(a_options) as Actor
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e


func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)


#region What each order names
func test_a_plain_move_names_nobody() -> void:
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	assert_null(
		MoveCommand.new(_message_for(_entity(TRANSPORT_PATH, 1))).avoidance_exception(soldier)
	)


func test_an_occupy_names_its_host() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	assert_eq(Occupy.new(_message_for(transport)).avoidance_exception(soldier), transport)


func test_an_embark_names_its_passenger() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	assert_eq(Embark.new(_message_for(soldier)).avoidance_exception(transport), soldier)


## The order outlives the thing it was aimed at by a tick or two; a freed host is nobody.
func test_a_host_that_has_gone_names_nobody() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	var command := Occupy.new(_message_for(transport))
	transport.free()
	assert_null(command.avoidance_exception(soldier))


#endregion


#region What the receiver does with it
## Reaches for the private resolver deliberately: precedence between the order's answer and
## the follow rule is the whole behaviour, and it has no other observable form short of a
## live physics tick.
func test_the_order_beats_the_follow_rule() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	soldier.update_commands(Occupy.new(_message_for(transport)))
	assert_eq(soldier.command_receiver._avoidance_exception_target(), transport)


## The case the follow rule cannot cover: a commanderless host is not a friendly unit, so
## nothing would have exempted the pair before.
func test_a_neutral_host_is_exempted_too() -> void:
	var shelter: Actor = _entity(OPEN_GARRISON_PATH, 0)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	soldier.update_commands(Occupy.new(_message_for(shelter)))
	assert_eq(soldier.command_receiver._avoidance_exception_target(), shelter)


func test_an_idle_unit_names_nobody() -> void:
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	assert_null(soldier.command_receiver._avoidance_exception_target())


## A plain move at a friendly unit still gets its exemption from the follow rule — the new
## hook adds a case, it does not replace one.
func test_the_follow_rule_still_answers_for_a_plain_move() -> void:
	var leader: Actor = _entity(SOLDIER_PATH, 1)
	var follower: Actor = _entity(SOLDIER_PATH, 1)
	follower.update_commands(MoveCommand.new(_message_for(leader)))
	assert_eq(follower.command_receiver._avoidance_exception_target(), leader)


#endregion


#region Teardown
## Regression: a unit taken prisoner in the middle of an Occupy still holds it, and a Compound
## sentence ending FREES the unit. The command's destructor then ran during the unit's own
## teardown and read its Movement — "Bad address index", then a crash. Cleanup is on_released
## now, and the destructor touches only the host. The old read was of memory mid-teardown, which
## faults or not depending on destruction order, so this test does NOT reproduce the crash on the
## old code; it pins the path and that the host is restored.
func test_a_unit_consumed_mid_occupy_tears_down_cleanly() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 2)
	var captive: Actor = _entity(SOLDIER_PATH, 2)
	captive.update_commands(Occupy.new(_message_for(transport)))
	captive.current_command().get_updated_state(captive)
	var hold := Garrison.new()
	hold.sentence_length = 1.0
	hold.bunker = false  # a prison, like the Compound
	add_child_autofree(hold)
	captive.get_parent().remove_child(captive)
	hold.garrison(captive)
	hold._physics_process(2.0)
	assert_false(is_instance_valid(captive), "the sentence consumed it")
	assert_eq(transport.movement._saved_avoidance_layers, 0, "and the host is back in avoidance")


## Re-ordered mid-approach, the actor's side is cleaned up while the actor is alive.
func test_a_replaced_occupy_releases_the_exceptions() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	soldier.update_commands(Occupy.new(_message_for(transport)))
	soldier.current_command().get_updated_state(soldier)
	assert_true(soldier.get_collision_exceptions().has(transport), "the approach exempts the host")
	soldier.update_commands(null)
	assert_false(soldier.get_collision_exceptions().has(transport), "released with the order")


#endregion


## The gap the queue hook closes: an Occupy pushed aside by an interrupt, then dropped with the
## queue, used to leave its unit's collision exception with the host behind.
func test_a_displaced_occupy_dropped_from_the_queue_releases_the_exceptions() -> void:
	var transport: Actor = _entity(TRANSPORT_PATH, 1)
	var soldier: Actor = _entity(SOLDIER_PATH, 1)
	soldier.update_commands(Occupy.new(_message_for(transport)))
	soldier.current_command().get_updated_state(soldier)
	soldier.update_commands(
		MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ONE)), false, true
	)
	assert_true(soldier.get_collision_exceptions().has(transport), "displaced, it will resume")
	soldier.update_commands(null)
	assert_false(soldier.get_collision_exceptions().has(transport), "dropped, it is released")
