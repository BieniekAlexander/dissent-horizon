extends GutTest

## A Sapper's planted charge: what holds the Sapper's Plant charge, what sets the charge off,
## what removes it quietly, and how the card offers Plant and Detonate. See
## gdd/systems/combat/planted-explosives.md.
##
## Authored scenes are HARNESSES here — a Sapper for a planter, a tank for a MECH carrier. No
## map is built, so a detonation's blast is not thrown; what is checked is which way the charge
## left play.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_PlantedCharge.gd \
##       -gdir=res://tests/none -gexit

const SAPPER_PATH: Dictionary = FakePieces.SOLDIER
const TANK_PATH: Dictionary = FakePieces.SOLDIER
const SOLDIER_PATH: Dictionary = FakePieces.SOLDIER
var _commanders: Dictionary = {}


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func before_each() -> void:
	_commanders = {}


func _piece(a_options: Dictionary, a_commander_id: int) -> Commandable:
	var piece := FakePieces.make(a_options) as Commandable
	add_child_autofree(piece)
	piece.ownership.commander = _commander(a_commander_id)
	return piece


## A charge planted by `a_planter`, riding on `a_carrier` or standing on the ground (null) —
## what Plant does on completion, minus the walk and the map.
func _plant(a_planter: Commandable, a_carrier: Commandable = null) -> PlantedCharge:
	var piece := (load(Plant.CHARGE_SCENE_PATH) as PackedScene).instantiate() as Commandable
	add_child_autofree(piece)
	piece.ownership.commander = a_planter.commander
	(a_planter.get_node("Abilities") as Abilities).spend(Plant.ABILITY_ID)
	var charge: PlantedCharge = PlantedCharge.of(piece)
	charge.arm(a_planter, a_carrier)
	return charge


func _pool(a_piece: Commandable) -> Abilities:
	return a_piece.get_node("Abilities") as Abilities


func _tick_pool(a_pool: Abilities, a_ticks: int) -> void:
	for _i: int in a_ticks:
		a_pool._physics_process(0.0)


func _message(a_target: Variant = null) -> CommandMessage:
	return CommandMessage.new(null, a_target, null, Vector3.ZERO)


#region The Sapper's charge is held
func test_the_plant_charge_does_not_recharge_while_the_charge_is_in_play() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	var charge: PlantedCharge = _plant(sapper)
	var pool: Abilities = _pool(sapper)
	var cooldown: int = int(pool.groups[0]["cooldown_ticks"])
	_tick_pool(pool, cooldown * 2)
	assert_false(pool.is_ready(Plant.ABILITY_ID), "held while the charge stands")
	assert_true(pool.is_recharge_held(Plant.ABILITY_ID))
	charge.host().free()
	_tick_pool(pool, cooldown - 1)
	assert_false(pool.is_ready(Plant.ABILITY_ID), "the full cooldown runs from its going")
	_tick_pool(pool, 1)
	assert_true(pool.is_ready(Plant.ABILITY_ID))


func test_a_sapper_with_no_charge_ready_cannot_plant() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	assert_eq(Plant.meets_precondition(sapper, _message()), MoveCommand.PreconditionFailureCause.NONE)
	_plant(sapper)
	assert_eq(Plant.meets_precondition(sapper, _message()),
		MoveCommand.PreconditionFailureCause.ABILITY_NO_CHARGES)
#endregion


#region Leaving play
func test_the_sapper_dying_removes_its_charge_quietly() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	var charge: PlantedCharge = _plant(sapper)
	sapper.die()
	assert_true(charge.is_resolved())
	assert_true(charge.host().is_queued_for_deletion())


func test_a_charge_rides_its_carrier_and_is_not_a_target_of_its_own() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	tank.global_position = Vector3(4.0, 0.0, 7.0)
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1), tank)
	assert_eq(charge.host().global_position, tank.global_position)
	assert_eq(charge.host().targetable_layers(), 0, "shooting it is shooting its carrier")
	tank.global_position = Vector3(9.0, 0.0, 1.0)
	charge._physics_process(0.0)
	assert_eq(charge.host().global_position, tank.global_position)


func test_a_charge_on_the_ground_can_be_shot() -> void:
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1))
	assert_true(charge.host().is_attackable())


func test_the_carrier_dying_sets_its_charge_off() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1), tank)
	tank.die()
	assert_true(charge.is_resolved())
	assert_true(charge.host().is_queued_for_deletion())


func test_a_charge_destroyed_where_it_stands_goes_off() -> void:
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1))
	charge.host().die()
	assert_true(charge.is_resolved(), "resolved by its own death, not a second one")
#endregion


#region Detonate
func test_detonate_is_for_a_charge_or_its_planter() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	var none := MoveCommand.PreconditionFailureCause.NONE
	assert_ne(Detonate.meets_precondition(sapper, _message()), none, "nothing to set off yet")
	var charge: PlantedCharge = _plant(sapper)
	assert_eq(Detonate.meets_precondition(sapper, _message()), none, "its planter can")
	assert_eq(Detonate.meets_precondition(charge.host(), _message()), none, "and so can it")
	Detonate.new(_message()).fulfill_action(sapper)
	assert_true(charge.is_resolved())
#endregion


#region Repairing it away
func test_an_opponent_repairs_a_ground_charge_away() -> void:
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1))
	var mender: Commandable = _piece(SAPPER_PATH, 2)
	assert_true(Repair.can_repair(mender, charge.host()))
	Repair.new(_message(charge.host())).fulfill_action(mender)
	assert_true(charge.is_resolved())
	assert_true(charge.host().is_queued_for_deletion())


func test_mending_a_carrier_strips_an_enemy_charge_even_when_whole() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1), tank)
	var mender: Commandable = _piece(SAPPER_PATH, 2)
	assert_eq(tank.defense.hp, tank.defense.hp_max, "guards the fixture: undamaged")
	assert_true(Repair.can_repair(mender, tank))
	Repair.new(_message(tank)).fulfill_action(mender)
	assert_true(charge.is_resolved())
	assert_false(Repair.can_repair(mender, tank), "nothing left to do on a whole tank")


func test_the_planter_side_does_not_strip_its_own_charge() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	_plant(_piece(SAPPER_PATH, 2), tank)
	assert_false(Repair.can_repair(_piece(SAPPER_PATH, 2), tank))


func test_its_owner_repairs_a_ground_charge_back() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	var charge: PlantedCharge = _plant(sapper)
	var mender: Commandable = _piece(SAPPER_PATH, 1)
	assert_true(Repair.can_repair(mender, charge.host()), "however whole it is")
	Repair.new(_message(charge.host())).fulfill_action(mender)
	assert_true(charge.is_resolved())
	charge.host().free()
	assert_false(_pool(sapper).is_recharge_held(Plant.ABILITY_ID), "the recharge starts")


## Any heal sheds what an enemy stuck on the piece — a charge and a beacon alike — not only a
## Repair order, and even on a whole piece.
func test_any_heal_sheds_enemy_charges_and_beacons() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1), tank)
	var beacon_piece: Entity = Beacon.SCENE.instantiate()
	add_child_autofree(beacon_piece)
	beacon_piece.ownership.commander = _commander(1)
	var beacon: Beacon = Beacon.of(beacon_piece)
	assert_true(beacon.attach_to(tank), "guards the fixture")
	assert_true(tank.has_hostile_markers())
	tank.defense.restore(1.0)
	assert_true(charge.is_resolved(), "the charge comes off without going off")
	assert_true(beacon.is_leaving(), "and so does the beacon")
	assert_false(tank.has_hostile_markers())


func test_a_staggered_piece_sheds_nothing() -> void:
	var tank: Commandable = _piece(TANK_PATH, 2)
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1), tank)
	tank.receive_damage(Damage.new(1.0))
	assert_true(tank.is_staggered(), "guards the fixture")
	assert_false(tank.defense.restore(1.0), "a mender stands by")
	assert_false(charge.is_resolved())
#endregion


#region What may carry one
func test_only_a_mech_piece_carries_a_charge() -> void:
	assert_true(PlantedCharge.can_carry(_piece(TANK_PATH, 2)))
	assert_true(PlantedCharge.can_carry(_piece(TANK_PATH, 1)), "a friendly vehicle too")
	assert_false(PlantedCharge.can_carry(_piece(SOLDIER_PATH, 2)), "never a BIO piece")


func test_a_charge_cannot_be_hijacked() -> void:
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, 1))
	var hijack := Interaction.new()
	hijack.type = Interaction.Type.HIJACK
	assert_ne(hijack.meets_precondition(_piece(SAPPER_PATH, 2), _message(charge.host())),
		MoveCommand.PreconditionFailureCause.NONE)
#endregion


#region The card
func test_a_sapper_offers_plant_until_it_has_a_charge_in_play() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	assert_true(CommandContextParser.commands_for(sapper).has("command_plant"))
	assert_false(CommandContextParser.commands_for(sapper).has("command_detonate"))
	var charge: PlantedCharge = _plant(sapper)
	assert_false(CommandContextParser.commands_for(sapper).has("command_plant"))
	assert_true(CommandContextParser.commands_for(sapper).has("command_detonate"))
	assert_true(CommandContextParser.commands_for(charge.host()).has("command_detonate"))


func test_plant_holds_the_cell_while_any_sapper_can_plant() -> void:
	var ready: Commandable = _piece(SAPPER_PATH, 1)
	var spent: Commandable = _piece(SAPPER_PATH, 1)
	_plant(spent)
	var names: Array = RTSController.selection_commands([ready, spent])
	assert_true(names.has("command_plant"))
	assert_true(names.has("command_detonate"), "the shared cell draws Plant, placed first")


func test_detonate_takes_the_cell_once_no_sapper_can_plant() -> void:
	var recharging: Commandable = _piece(SAPPER_PATH, 1)
	var spent: Commandable = _piece(SAPPER_PATH, 1)
	var charge: PlantedCharge = _plant(recharging)
	charge.host().free()  # gone off: the charge is recharging, with nothing in play
	_plant(spent)
	var names: Array = RTSController.selection_commands([recharging, spent])
	assert_false(names.has("command_plant"))
	assert_true(names.has("command_detonate"))


func test_a_recharging_sapper_alone_still_draws_plant() -> void:
	var sapper: Commandable = _piece(SAPPER_PATH, 1)
	_plant(sapper).host().free()
	assert_true(RTSController.selection_commands([sapper]).has("command_plant"),
		"drawn dark, recharging — there is nothing to detonate")


func test_plant_outranks_detonate_in_their_cell() -> void:
	var plant: ControlBinding = CommandGrid.binding_for("command_plant")
	var detonate: ControlBinding = CommandGrid.binding_for("command_detonate")
	assert_eq(plant.grid_position, detonate.grid_position)
	var names: Array = CommandGrid.bindings().map(
		func(binding: ControlBinding) -> String: return binding.command_name)
	assert_lt(names.find("command_plant"), names.find("command_detonate"))


func test_each_stance_has_its_badge() -> void:
	assert_eq(StatusVisuals.stance_badge(Deployable.Stance.MOBILE), [])
	for stance: Deployable.Stance in [Deployable.Stance.DEPLOYING, Deployable.Stance.DEPLOYED,
			Deployable.Stance.UNDEPLOYING]:
		assert_eq(StatusVisuals.stance_badge(stance).size(), 2, "a badge for %s" % stance)
	assert_eq(StatusVisuals.stance_badge(Deployable.Stance.DEPLOYED)[1], 0.0,
		"the settled stance holds steady; the transitions flash")
	assert_gt(StatusVisuals.stance_badge(Deployable.Stance.DEPLOYING)[1], 0.0)


func test_its_owner_cannot_pick_out_a_charge_it_cannot_see() -> void:
	var charge: PlantedCharge = _plant(_piece(SAPPER_PATH, RTSController.PLAYER_COMMANDER_ID))
	charge.host().visible = false
	assert_false(RTSController._is_perceptible(charge.host()))
	charge.host().visible = true
	assert_true(RTSController._is_perceptible(charge.host()))
#endregion
