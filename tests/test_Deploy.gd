extends GutTest

## Deploy and Undeploy: the timed transition, what a planted unit gains and gives up, and which
## orders it takes while planting, planted and packing up. See
## gdd/systems/commands/deploying.md.
##
## The soldier scene is only a HARNESS — a Commandable with Movement and Defense. The test gives
## it a Deployable of its own, so nothing here depends on which pieces deploy or how long for.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Deploy.gd \
##       -gdir=res://tests/none -gexit

const SOLDIER_PATH: Dictionary = FakePieces.SOLDIER
const DEPLOY_TICKS: int = 3
const UNDEPLOY_TICKS: int = 2


func _unit(a_is_cancellable: bool = false) -> Commandable:
	var unit := FakePieces.make(SOLDIER_PATH) as Commandable
	var deployable := Deployable.new()
	deployable.name = "Deployable"
	deployable.deploy_ticks = DEPLOY_TICKS
	deployable.undeploy_ticks = UNDEPLOY_TICKS
	deployable.is_cancellable = a_is_cancellable
	unit.add_child(deployable)
	add_child_autofree(unit)
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	unit.ownership.commander = commander
	unit.defense.armour_type = Defense.ArmourType.LIGHT
	return unit


func _tick(a_unit: Commandable, a_times: int) -> void:
	for _i: int in a_times:
		a_unit.command_receiver._process_commands()


func _message() -> CommandMessage:
	return CommandMessage.new(null, null, null, Vector3(5.0, 0.0, 5.0))


func _move() -> MoveCommand:
	return MoveCommand.new(_message())


func _deployed(a_unit: Commandable) -> Commandable:
	a_unit.update_commands(Deploy.new(_message()))
	_tick(a_unit, DEPLOY_TICKS + 1)
	return a_unit


func _chain_names(a_unit: Commandable) -> Array:
	return a_unit.command_receiver.get_command_chain().map(
		func(command: MoveCommand) -> String: return str(command))


#region The transition
func test_a_deploy_plants_the_unit_after_its_time() -> void:
	var unit: Commandable = _unit()
	var deployable: Deployable = unit.deployable
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, DEPLOY_TICKS - 1)
	assert_eq(deployable.stance, Deployable.Stance.DEPLOYING, "one tick short")
	assert_null(unit.live_movement(), "a deploying unit cannot move")
	assert_eq(unit.defense.armour_type, Defense.ArmourType.LIGHT, "no bonus until planted")
	_tick(unit, 1)
	assert_eq(deployable.stance, Deployable.Stance.DEPLOYED)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.MEDIUM, "one armour class up")
	assert_null(unit.live_movement(), "a deployed unit cannot move")
	assert_eq(unit.movement_component.avoidance_obstacle.avoidance_layers,
		AvoidanceAgent3D.STANDING_OBSTACLE_BIT, "every team steers round it")


func test_weapons_are_offline_only_mid_transition() -> void:
	var unit: Commandable = _unit()
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	assert_false(unit.deployable.can_use_weapons())
	assert_null(unit.get_aggro_near_position(), "a transitioning unit picks no fights")
	_tick(unit, DEPLOY_TICKS)
	assert_true(unit.deployable.can_use_weapons(), "a deployed unit fires")


func test_an_undeploy_gives_the_armour_back_at_once_and_frees_the_unit_after() -> void:
	var unit: Commandable = _deployed(_unit())
	var layers_before: int = AvoidanceAgent3D.obstacle_bit(1)
	unit.update_commands(Undeploy.new(_message()))
	_tick(unit, 1)
	assert_eq(unit.deployable.stance, Deployable.Stance.UNDEPLOYING)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.LIGHT, "the bonus goes as it leaves")
	assert_false(unit.deployable.can_use_weapons())
	_tick(unit, UNDEPLOY_TICKS)
	assert_eq(unit.deployable.stance, Deployable.Stance.MOBILE)
	assert_not_null(unit.live_movement(), "free to move again")
	assert_eq(unit.movement_component.avoidance_obstacle.avoidance_layers, layers_before,
		"back on its own team's obstacle channel")


func test_armour_never_steps_past_the_top_class() -> void:
	var unit: Commandable = _unit()
	unit.defense.armour_type = Defense.ArmourType.STRONG
	_deployed(unit)
	assert_eq(unit.defense.armour_type, Defense.ArmourType.STRONG)


func test_a_unit_torn_down_mid_deploy_stands_back_up() -> void:
	var unit: Commandable = _unit()
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	unit.update_commands(null)
	assert_eq(unit.deployable.stance, Deployable.Stance.MOBILE)
#endregion


#region Orders while deploying
func test_an_uncancellable_deploy_ignores_a_move() -> void:
	var unit: Commandable = _unit(false)
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	unit.update_commands(_move())
	assert_eq(_chain_names(unit), ["Deploy"], "the move is dumped, the deploy runs on")
	_tick(unit, DEPLOY_TICKS)
	assert_eq(unit.deployable.stance, Deployable.Stance.DEPLOYED)


func test_a_cancellable_deploy_gives_way_to_a_move() -> void:
	var unit: Commandable = _unit(true)
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	var move: MoveCommand = _move()
	unit.update_commands(move)
	assert_eq(unit.deployable.stance, Deployable.Stance.MOBILE, "the deploy is abandoned")
	assert_eq(unit.command_receiver.get_command_chain(), [move] as Array[MoveCommand])
	assert_not_null(unit.live_movement())


func test_a_cancellable_deploy_gives_way_to_an_attack_move() -> void:
	var unit: Commandable = _unit(true)
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	unit.update_commands(AttackMove.new(_message()))
	assert_eq(unit.deployable.stance, Deployable.Stance.MOBILE)


func test_a_queued_move_does_not_cancel_a_deploy() -> void:
	var unit: Commandable = _unit(true)
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	unit.update_commands(_move(), true)
	assert_eq(unit.deployable.stance, Deployable.Stance.DEPLOYING)
	assert_eq(_chain_names(unit), ["Deploy"], "and a move queued behind a deploy is dumped")


## Anything else given plainly waits behind the transition, judged against the planted form.
func test_a_plain_stop_waits_behind_a_deploy() -> void:
	var unit: Commandable = _unit(true)
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	unit.update_commands(Stop.new(_message()))
	assert_eq(unit.deployable.stance, Deployable.Stance.DEPLOYING, "a stop cancels nothing")
	assert_eq(_chain_names(unit)[0], "Deploy")
#endregion


#region Orders once deployed
func test_a_deployed_unit_ignores_moves_plain_or_queued() -> void:
	var unit: Commandable = _deployed(_unit())
	unit.update_commands(_move())
	unit.update_commands(_move(), true)
	unit.update_commands(AttackMove.new(_message()), true)
	assert_true(unit.command_receiver.get_command_chain().is_empty())
	assert_eq(unit.deployable.stance, Deployable.Stance.DEPLOYED)


func test_a_move_queued_after_an_undeploy_is_kept() -> void:
	var unit: Commandable = _deployed(_unit())
	unit.update_commands(Undeploy.new(_message()))
	unit.update_commands(_move(), true)
	assert_eq(_chain_names(unit).size(), 2, "the unit will be mobile by then")


func test_a_plain_move_during_an_undeploy_follows_it() -> void:
	var unit: Commandable = _deployed(_unit())
	unit.update_commands(Undeploy.new(_message()))
	_tick(unit, 1)
	var move: MoveCommand = _move()
	unit.update_commands(move)
	assert_eq(_chain_names(unit)[0], "Undeploy", "the undeploy runs on")
	assert_true(unit.command_receiver.get_command_chain().has(move), "and the move waits")
	_tick(unit, UNDEPLOY_TICKS)
	assert_eq(unit.deployable.stance, Deployable.Stance.MOBILE)
	assert_same(unit.command_receiver.get_command_chain().front(), move)


func test_a_move_queued_behind_a_queued_deploy_is_dumped() -> void:
	var unit: Commandable = _unit()
	unit.update_commands(_move())
	unit.update_commands(Deploy.new(_message()), true)
	unit.update_commands(_move(), true)
	assert_eq(_chain_names(unit).size(), 2, "the second move would meet a planted unit")
#endregion


#region The command card
func test_a_unit_offers_the_command_for_the_form_it_is_heading_for() -> void:
	var unit: Commandable = _unit()
	assert_true(CommandContextParser.commands_for(unit).has("command_deploy"))
	assert_false(CommandContextParser.commands_for(unit).has("command_undeploy"))
	unit.update_commands(Deploy.new(_message()))
	_tick(unit, 1)
	assert_true(CommandContextParser.commands_for(unit).has("command_undeploy"),
		"a deploying unit is already heading for the planted form")
	assert_false(CommandContextParser.commands_for(unit).has("command_deploy"))


func test_only_mobile_units_take_deploy_and_only_deployed_ones_undeploy() -> void:
	var mobile: Commandable = _unit()
	var planted: Commandable = _deployed(_unit())
	var none := MoveCommand.PreconditionFailureCause.NONE
	assert_eq(Deploy.meets_precondition(mobile, _message()), none)
	assert_ne(Deploy.meets_precondition(planted, _message()), none)
	assert_eq(Undeploy.meets_precondition(planted, _message()), none)
	assert_ne(Undeploy.meets_precondition(mobile, _message()), none)


## The cell is drawn by the first binding the selection offers, so the order of the bindings
## IS the precedence: Deploy, then Undeploy, then Land.
func test_deploy_then_undeploy_outrank_land_in_their_cell() -> void:
	var order: Array = []
	var cell: Vector2i = CommandGrid.binding_for("command_land").grid_position
	for binding: ControlBinding in CommandGrid.bindings():
		if binding.grid_position == cell and binding.command_name in [
				"command_deploy", "command_undeploy", "command_land"]:
			order.append(binding.command_name)
	assert_eq(order, ["command_deploy", "command_undeploy", "command_land"])
	for collision: String in ControlBinding.grid_collisions(CommandGrid.bindings()):
		assert_false(collision.contains("deploy"), "not reported as ambiguous: %s" % collision)
#endregion


#region The doc key
const SpecRegistry := preload("res://tools/spec_import/spec_registry.gd")


func _deploys_errors(a_deploys: Variant, a_has_movement: bool = true) -> Array:
	var registry := SpecRegistry.new()
	var spec: Dictionary = {"_doc_path": "doc.md", "id": "tank", "deploys": a_deploys}
	if a_has_movement:
		spec["movement"] = {}
	registry._validate_deploys(spec, a_deploys)
	return registry.errors


func test_a_complete_deploys_key_imports() -> void:
	assert_eq(_deploys_errors({"time": 3, "undeploy_time": 1, "cancellable": false}), [])
	assert_eq(_deploys_errors(false), [], "false removes it")


func test_every_deploys_sub_key_is_required() -> void:
	assert_eq(_deploys_errors({"time": 3, "undeploy_time": 1}).size(), 1,
		"cancellable is a per-unit decision, never a default")
	assert_eq(_deploys_errors({"time": 0, "undeploy_time": 1, "cancellable": true}).size(), 1)
	assert_eq(_deploys_errors({"time": 3, "undeploy_time": 1, "cancellable": true,
		"bonus": 2}).size(), 1, "an unknown sub-key is refused")


func test_only_a_moving_piece_deploys() -> void:
	assert_eq(_deploys_errors({"time": 3, "undeploy_time": 1, "cancellable": false},
		false).size(), 1)
#endregion
