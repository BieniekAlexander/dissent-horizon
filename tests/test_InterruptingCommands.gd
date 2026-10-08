extends GutTest

## Two edge cases in how an order lands on an actor.
##
## **An INTERRUPT keeps the queue.** An ordinary order given without `modifier_additive`
## clears what the actor was doing — the player has said "forget that, do this". A few orders
## are not a change of plan but a thing to do ON THE WAY, and for those the queue survives:
## the order takes over now, whatever was running goes to the FRONT of the queue, and the
## actor picks it back up. `Evacuate` is the case that prompted it.
##
## **A position-less order never stays armed.** Holding `modifier_additive` normally keeps a
## sub-mode or tool armed for the next click, but an order that fires the moment it is pressed
## has nothing to stay armed for.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_InterruptingCommands.gd -gexit


func _receiver() -> CommandReceiver:
	# Never given an owner: none of the queue arithmetic below reads one.
	return CommandReceiver.new()


func _order(a_xz: Vector2) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, VU.from_xz(a_xz)))


## A TYPED chain. `_command_queue` is `Array[MoveCommand]`, and the non-prepend array branch
## assigns a slice of the argument straight into it — so an untyped literal fails the
## assignment. Real callers hand over `rally_chain()`, which is typed.
func _chain(a_orders: Array[MoveCommand]) -> Array[MoveCommand]:
	return a_orders


func _destinations(a_chain: Array) -> Array:
	var out: Array = []
	for command: MoveCommand in a_chain:
		out.append(VU.in_xz(command.message.position))
	return out


#region Which commands interrupt
func test_an_ordinary_command_replaces() -> void:
	assert_false(MoveCommand.is_interrupt(), "the default, so nothing existing changes")
	assert_false(Attack.is_interrupt())
	assert_false(Stop.is_interrupt(), "Stop IS a change of plan — it means drop everything")


func test_evacuate_interrupts() -> void:
	assert_true(
		Evacuate.is_interrupt(), "turning the garrison out is an aside, not a change of plan"
	)


#endregion


#region What an interrupt does to the queue
## The shape the receiver implements: the new order becomes current, the running one goes to
## the FRONT of the queue, and everything already queued keeps its place behind it.
func test_an_interrupt_pushes_the_running_order_to_the_front() -> void:
	var receiver: CommandReceiver = autofree(_receiver()) as CommandReceiver
	receiver.update_commands(_chain([_order(Vector2(1, 1)), _order(Vector2(2, 2))]))
	assert_eq(_destinations(receiver.get_command_chain())[0], Vector2(1, 1))

	receiver.update_commands(_order(Vector2(9, 9)), false, true)

	assert_eq(
		_destinations(receiver.get_command_chain())[0],
		Vector2(9, 9),
		"the interrupt takes over now"
	)
	assert_eq(
		_destinations(receiver.get_command_chain()),
		[Vector2(9, 9), Vector2(1, 1), Vector2(2, 2)],
		"and the whole previous plan is still there, in order, behind it"
	)


## Non-additive and non-interrupting is unchanged: the queue is cleared.
func test_an_ordinary_order_still_clears_the_queue() -> void:
	var receiver: CommandReceiver = autofree(_receiver()) as CommandReceiver
	receiver.update_commands(_chain([_order(Vector2(1, 1)), _order(Vector2(2, 2))]))
	receiver.update_commands(_order(Vector2(9, 9)), false, false)
	assert_eq(_destinations(receiver.get_command_chain()), [Vector2(9, 9)])


## An interrupt with nothing running is just an order.
func test_interrupting_an_idle_actor_is_ordinary() -> void:
	var receiver: CommandReceiver = autofree(_receiver()) as CommandReceiver
	receiver.update_commands(_order(Vector2(9, 9)), false, true)
	assert_eq(_destinations(receiver.get_command_chain()), [Vector2(9, 9)])


## Appending is still appending — an interrupt is the NON-additive version of "keep the
## queue", so holding the modifier is unaffected.
func test_appending_still_goes_to_the_back() -> void:
	var receiver: CommandReceiver = autofree(_receiver()) as CommandReceiver
	receiver.update_commands(_order(Vector2(1, 1)))
	receiver.update_commands(_order(Vector2(9, 9)), true, false)
	assert_eq(_destinations(receiver.get_command_chain()), [Vector2(1, 1), Vector2(9, 9)])


## The same rule for a whole chain handed over at once.
func test_a_chain_interrupt_keeps_the_running_order_behind_it() -> void:
	var receiver: CommandReceiver = autofree(_receiver()) as CommandReceiver
	receiver.update_commands(_order(Vector2(1, 1)))
	receiver.update_commands(_chain([_order(Vector2(8, 8)), _order(Vector2(9, 9))]), false, true)
	assert_eq(
		_destinations(receiver.get_command_chain()), [Vector2(8, 8), Vector2(9, 9), Vector2(1, 1)]
	)


#endregion


#region Arming ends for a position-less command
## `_arming_should_end` is the whole rule: a command that WAITS for a click may stay armed
## while the modifier is held; one that fires on the press has nothing to wait for.
func test_a_positional_command_stays_armed_while_additive_is_held() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	assert_true(Build.requires_position())
	assert_false(
		controller._arming_should_end(Build, true),
		"holding the modifier keeps the tool armed, so five sites take five clicks"
	)


func test_a_positional_command_disarms_without_the_modifier() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	assert_true(controller._arming_should_end(Build, false))


## Stop, Evacuate and Train all fire on the press. Leaving one armed would leave the
## controller in a sub-mode the next right-click would re-fire instead of resolving normally.
func test_a_position_less_command_disarms_even_when_additive_is_held() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	for command_type: Script in [Stop, Evacuate, Train]:
		assert_false(command_type.requires_position(), "%s fires on the press" % command_type)
		assert_true(
			controller._arming_should_end(command_type, true),
			"%s has nothing to stay armed for" % command_type
		)


#endregion


#region Releasing what a command held
## Counts how often it is told it has left its receiver.
class ReleaseCounter:
	extends MoveCommand
	var releases: int = 0

	func _init() -> void:
		super(CommandMessage.new(null))

	func on_released(_a_actor: Actor) -> void:
		releases += 1


func test_a_replaced_active_command_is_released_once() -> void:
	var receiver: CommandReceiver = _receiver()
	var first := ReleaseCounter.new()
	receiver.update_commands(first)
	receiver.update_commands(_order(Vector2.ONE))
	assert_eq(first.releases, 1)


func test_a_displaced_command_is_not_released_until_it_is_dropped() -> void:
	var receiver: CommandReceiver = _receiver()
	var first := ReleaseCounter.new()
	receiver.update_commands(first)
	receiver.update_commands(_order(Vector2.ONE), false, true)
	assert_eq(first.releases, 0, "pushed into the queue by an interrupt, it will resume")
	receiver.update_commands(null)
	assert_eq(first.releases, 1, "dropped from the queue, it is released")


func test_a_command_that_only_ever_queued_is_not_released() -> void:
	var receiver: CommandReceiver = _receiver()
	var queued := ReleaseCounter.new()
	receiver.update_commands(_order(Vector2.ONE))
	receiver.update_commands(queued, true)
	receiver.update_commands(null)
	assert_eq(queued.releases, 0, "it never ran, so it holds nothing to release")


func test_a_displaced_command_that_resumes_is_released_once_it_ends() -> void:
	var receiver: CommandReceiver = _receiver()
	var first := ReleaseCounter.new()
	receiver.update_commands(first)
	receiver.update_commands(_order(Vector2.ONE), false, true)
	receiver._command = receiver._command_queue.pop_front()
	assert_eq(first.releases, 0, "back in the active slot")
	receiver.update_commands(null)
	assert_eq(first.releases, 1)
#endregion
