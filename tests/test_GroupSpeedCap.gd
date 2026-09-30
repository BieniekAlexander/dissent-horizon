extends GutTest

## Group-move speed capping: a mixed-speed selection travels at its slowest member's
## pace (RTSController.assign_command_to_units -> Movement.speed_cap ->
## CommandReceiver's effective_max_speed).
##
## Regression guard on the ORDER of those two steps. Setting CommandReceiver._command
## resets speed_cap to 0 as its group-move cleanup, and issuing a new command replaces
## the outgoing one — synchronously. So capping BEFORE the handover lets the handover
## wipe the cap immediately afterwards, and every unit that already had an order (i.e.
## every re-order) would silently travel at its own speed.
##
## The cleanup used to live in MoveCommand's PREDELETE. It was moved to the _command
## setter because a destructor fires at an arbitrary moment — for a unit that dies while
## executing a command, during its own teardown — where reading actor.movement
## dereferenced a freed script instance and hard-crashed the process. See
## CommandReceiver._release_speed_cap.

var _unit: Node
var _movement: Movement


func before_each() -> void:
	_unit = FakePieces.unit({"speed": 3.0})
	add_child_autofree(_unit)
	_movement = _unit.movement


func _issue_command() -> void:
	_unit.command_receiver.update_commands(MoveCommand.new(CommandMessage.new(null, null, null)))


func test_uncapped_unit_travels_at_its_own_speed() -> void:
	assert_eq(_movement.speed_cap, 0.0, "no cap by default")
	assert_almost_eq(_movement.effective_max_speed(), _movement.speed, 0.001)


func test_cap_applied_after_the_command_survives() -> void:
	_issue_command()
	_issue_command()                      # the re-order that used to wipe the cap
	_movement.speed_cap = 1.0             # applied AFTER the handover
	assert_almost_eq(_movement.speed_cap, 1.0, 0.001, "cap not wiped by the outgoing command")
	assert_almost_eq(_movement.effective_max_speed(), 1.0, 0.001, "travel speed honours the cap")


func test_cap_is_what_limits_a_faster_unit() -> void:
	# The cap only means anything if it beats the unit's own speed.
	assert_gt(_movement.speed, 1.0, "fixture unit is faster than the cap under test")
	_issue_command()
	_movement.speed_cap = 1.0
	assert_almost_eq(_movement.effective_max_speed(), 1.0, 0.001)


func test_cap_applied_before_the_command_is_wiped_by_the_outgoing_one() -> void:
	# The trap itself, pinned down: whoever caps a unit MUST do it after handing over the
	# new command, because the handover releases the outgoing command's cap. Kept as
	# executable documentation of why RTSController.assign_command_to_units orders those
	# two steps as it does.
	_issue_command()
	_movement.speed_cap = 1.0             # capped BEFORE the handover...
	_issue_command()                      # ...which replaces the previous command
	assert_eq(_movement.speed_cap, 0.0,
		"the handover releases a cap applied before it")


func test_cap_clears_when_the_command_goes_away() -> void:
	_issue_command()
	_movement.speed_cap = 1.0
	_unit.command_receiver.update_commands(null)
	assert_eq(_movement.speed_cap, 0.0, "cleared when the command stops driving the unit")
	assert_almost_eq(_movement.effective_max_speed(), _movement.speed, 0.001)


func test_cap_survives_an_interrupt_that_queues_the_group_move() -> void:
	# An interrupt (e.g. aggro) PREPENDS itself and pushes the group move into the queue
	# rather than dropping it, so the pace must survive to be resumed. This is the case
	# the setter's queue check protects.
	_issue_command()
	_movement.speed_cap = 1.0
	_unit.command_receiver.update_commands(
		MoveCommand.new(CommandMessage.new(null, null, null)), true, true)
	assert_almost_eq(_movement.speed_cap, 1.0, 0.001,
		"a displaced (not dropped) command keeps its group pace")
