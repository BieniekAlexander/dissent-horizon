extends GutTest

## A command whose TARGET leaves the play space is dropped, rather than driving its actor at
## the world origin.
##
## The bug: `Garrison.garrison()` removes an occupant from the scene tree outright, so nothing
## can acquire it — but a command issued BEFORE it boarded still holds the reference, and an
## off-tree node reports `global_position` (0, 0, 0). `CommandMessage.position` reads the
## target's position whenever a target is set, so a perfectly valid-looking order silently
## becomes "go to the middle of the map".
##
## Found by the `spaced_antimech_vs_truck` simulation spec: a stock truck captures infantry by
## running them over, so it ran one down, took it aboard, and then set off for the origin.
## That is a SOFTWARE defect rather than a balance question, which is why the regression test
## for it lives here and not in `sims/`
## (gdd/systems/scenario-scripting/simulation-tests.md §A simulation test asks about DESIGN).
##
## `CommandReceiver._end_after_follow_target_died` is the same rule for a target that DIED;
## this is its missing other half.

## load() inside each test, never a file-scope preload: a preload of an entity scene runs at
## PARSE time and can fire Tool's static registry initialiser before the registry exists,
## which takes out every test after it (CLAUDE.md).
## A carrier with a cage.
const TRUCK_SCENE: Dictionary = {
	"speed": 2.0, "vision": 8.0, "garrison": {"capacity": 3, "bunker": false}
}
const TROOPER_SCENE: Dictionary = FakePieces.SOLDIER


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


func _entity(a_options: Dictionary, a_commander_id: int) -> Actor:
	var entity := FakePieces.make(a_options) as Actor
	add_child_autofree(entity)
	entity.ownership.commander = _commander(a_commander_id)
	return entity


## An actor holding a plain move order aimed at `a_target`, the shape an unarmed piece uses to
## run something down.
func _ordered_at(a_actor: Actor, a_target: Actor) -> void:
	var message := CommandMessage.new(null, a_target, null, a_target.global_position)
	a_actor.update_commands([MoveCommand.new(message)] as Array[MoveCommand])


func _tick(a_actor: Actor) -> void:
	a_actor.command_receiver._update_state()
	a_actor._process_commands()


#region The rule
func test_an_order_survives_while_its_target_is_in_the_world() -> void:
	# The control: nothing about this change may drop an ordinary order.
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var trooper: Actor = _entity(TROOPER_SCENE, 2)
	trooper.global_position = Vector3(8.0, 0.0, 0.0)
	_ordered_at(truck, trooper)
	_tick(truck)
	assert_true(truck.has_command(), "an order at a target standing in the world is kept")


func test_an_order_is_dropped_once_its_target_is_garrisoned() -> void:
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var trooper: Actor = _entity(TROOPER_SCENE, 2)
	trooper.global_position = Vector3(8.0, 0.0, 0.0)
	_ordered_at(truck, trooper)
	_tick(truck)
	assert_true(truck.has_command(), "precondition: the order is live before the capture")

	truck.garrison.garrison(trooper)
	_tick(truck)
	assert_false(
		truck.has_command(),
		"a target taken off the scene tree cannot be acted on, so the order goes"
	)


func test_the_actor_does_not_set_off_for_the_world_origin() -> void:
	# The symptom, asserted directly: it is the destination that was wrong, not just the
	# bookkeeping. A dropped command leaves the actor with no destination at all.
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var trooper: Actor = _entity(TROOPER_SCENE, 2)
	trooper.global_position = Vector3(8.0, 0.0, 0.0)
	_ordered_at(truck, trooper)
	_tick(truck)
	truck.garrison.garrison(trooper)
	_tick(truck)

	assert_null(truck.current_command(), "no command survives to name a destination")
	assert_true(trooper.is_garrisoned(), "and the target really did leave the world")


func test_the_next_queued_order_takes_over() -> void:
	# Dropping must not strand the actor: the truck in the spec that found this carries a
	# QUEUE of two moves, one per flank, and losing the first has to start the second.
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var first: Actor = _entity(TROOPER_SCENE, 2)
	var second: Actor = _entity(TROOPER_SCENE, 2)
	first.global_position = Vector3(8.0, 0.0, 0.0)
	second.global_position = Vector3(-8.0, 0.0, 0.0)
	var chain: Array[MoveCommand] = [
		MoveCommand.new(CommandMessage.new(null, first, null, first.global_position)),
		MoveCommand.new(CommandMessage.new(null, second, null, second.global_position)),
	]
	truck.update_commands(chain)
	_tick(truck)

	truck.garrison.garrison(first)
	_tick(truck)  # drops the first
	_tick(truck)  # promotes the second
	assert_true(truck.has_command(), "the queue advances")
	assert_eq(
		truck.current_command().message.target,
		second,
		"and it advances to the order that was behind it"
	)


#endregion


#region What it must NOT do
func test_a_dead_target_is_left_to_the_paths_that_already_handle_it() -> void:
	# Death is deliberately not reported as "left play": every command already handles a freed
	# target, and a FLYING actor's orbit-on-death anchoring lives in that path. Reporting it
	# here too would change how a death is handled, which is a separate behaviour.
	var message := CommandMessage.new(null, null, null, Vector3.ZERO)
	assert_false(
		CommandReceiver._target_has_left_play(message), "an absent target is not 'left play'"
	)


func test_a_command_with_no_target_at_all_is_unaffected() -> void:
	# A ground move — the overwhelmingly common order — names no entity and must never be
	# touched by this rule.
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var message := CommandMessage.new(null, null, null, Vector3(5.0, 0.0, 5.0))
	truck.update_commands([MoveCommand.new(message)] as Array[MoveCommand])
	_tick(truck)
	assert_true(truck.has_command(), "a positional order holds no entity and cannot lose one")


func test_a_structure_target_is_never_considered_off_the_field() -> void:
	# Only a Actor can be garrisoned; a non-Actor Entity target has no such state
	# and must always read as in play.
	var truck: Actor = _entity(TRUCK_SCENE, 1)
	var message := CommandMessage.new(null, truck, null, Vector3.ZERO)
	assert_false(
		CommandReceiver._target_has_left_play(message), "a target standing in the world is in play"
	)
#endregion
