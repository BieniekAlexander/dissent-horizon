extends GutTest

## What the player is told when a bombardment is aimed at ground nobody is spotting.
##
## The whole chain, because the failure it was written for could have been anywhere in it:
## the command has to RESOLVE for the selection, its precondition has to name a cause, and
## that cause has to reach `precondition_message_map` — a cause with no entry, or a
## resolution that collapses to null, both end as a normal cursor over an illegal target
## and the player learns nothing.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BombardCursor.gd -gexit

## A gun that spots the ground around itself and carries a charge of the bombard ability.
const GUN: Dictionary = {"structure": true, "dimensions": Vector2i(2, 2), "beacon_range": 30.0,
	"abilities": [{"grants": [Bombard.ABILITY_ID], "cooldown_ticks": 100}]}

var _commander: Commander


func after_each() -> void:
	FakePieces.restore_abilities()


func before_each() -> void:
	FakePieces.install_ability(Bombard.ABILITY_ID, {"range": 30.0})
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func _bombard() -> Commandable:
	# The gun costs 75 infrastructure of upkeep, and a commander with only
	# BASE_INFRASTRUCTURE cannot cover two of them — an unpowered building casts nothing
	# (see tests/test_InfrastructureStrain.gd), which is not what is under test here.
	_commander.add_infrastructure(1000)
	var gun: Commandable = FakePieces.structure(GUN)
	_commander.add_child(gun)
	autofree(gun)
	gun.top_level = true
	gun.ownership.commander = _commander
	gun.global_position = Vector3.ZERO
	gun.build_progress = 1.0
	return gun


func _aim(a_at: Vector2) -> CommandMessage:
	return CommandMessage.new(null, null, null, Vector3(a_at.x, 0.0, a_at.y))


# --- The precondition ------------------------------------------------------------

func test_ground_inside_the_guns_own_range_is_legal() -> void:
	var gun := _bombard()
	assert_true(gun.is_built, "the fixture is a finished gun")
	assert_eq(Bombard.meets_precondition(gun, _aim(Vector2(10, 0))),
		MoveCommand.PreconditionFailureCause.NONE)


func test_unspotted_ground_names_a_cause() -> void:
	var gun := _bombard()
	var cause := Bombard.meets_precondition(gun, _aim(Vector2(200, 200)))
	assert_eq(cause, MoveCommand.PreconditionFailureCause.TARGET_NOT_SPOTTED)


func test_the_cause_has_a_message_for_the_player() -> void:
	# The point of the map: a cause with no entry reaches the error line as "".
	assert_true(MoveCommand.precondition_message_map.has(
		MoveCommand.PreconditionFailureCause.TARGET_NOT_SPOTTED))
	assert_false(String(MoveCommand.precondition_message_map[
		MoveCommand.PreconditionFailureCause.TARGET_NOT_SPOTTED]).is_empty())


# --- The controller's chain ------------------------------------------------------

func test_the_armed_command_resolves_even_when_it_cannot_execute() -> void:
	# resolve_command_class_for_selection falls back to the lead unit's resolution when
	# nobody can act. If it returned null instead, selection_precondition would answer
	# NONE and the cursor would stay normal over ground the gun cannot reach.
	var gun := _bombard()
	assert_eq(RTSController.resolve_command_class_for_selection(
		"command_bombard", [gun], _aim(Vector2(200, 200))), Bombard)


func test_the_selection_reports_the_cause_for_unspotted_ground() -> void:
	var gun := _bombard()
	assert_eq(
		RTSController.selection_precondition(Bombard, [gun], _aim(Vector2(200, 200))),
		MoveCommand.PreconditionFailureCause.TARGET_NOT_SPOTTED)


func test_the_selection_reports_nothing_wrong_inside_range() -> void:
	var gun := _bombard()
	assert_eq(
		RTSController.selection_precondition(Bombard, [gun], _aim(Vector2(10, 0))),
		MoveCommand.PreconditionFailureCause.NONE)


func test_one_loaded_gun_in_a_pair_keeps_the_order_legal() -> void:
	# selection_precondition's rule: available as soon as ANYBODY can act. A gun 200 units
	# away covers nothing here, but the one standing on the target does.
	var near := _bombard()
	var far := _bombard()
	far.global_position = Vector3(500.0, 0.0, 500.0)
	assert_eq(
		RTSController.selection_precondition(Bombard, [far, near], _aim(Vector2(10, 0))),
		MoveCommand.PreconditionFailureCause.NONE)
