extends GutTest

## Tests for how an AERIAL unit prosecutes an attack — the three rules that separate a
## fixed wing's attack run from a ground unit standing still and trading fire.
##
## The dive is the odd one out and is covered here too, because the three interact: whether
## a unit may fire (`_dive_contact_made`) and whether it should still be moving
## (`should_move`) were both keyed off `Movement.Mode.FLYING`, and together they froze every
## aeroplane in the game over its target.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_AerialAttackRun.gd -gexit

## Every piece is a fake (tests/_fake_pieces.gd).
## A fixed wing: flies, shoots ground and air from range, carries a charged clip, docks.
const DRAKE: Dictionary = {
	"aerial": true,
	"flying": true,
	"vision": 10.0,
	"docking": true,
	"weapon": {"ground": 12.0, "air": 12.0, "clip_size": 4, "charged": true}
}
## Rams: a flier whose reach is next to nothing.
const KAMIKAZE: Dictionary = {
	"aerial": true, "flying": true, "vision": 10.0, "weapon": {"ground": 0.5, "air": 0.5}
}
const TANK: Dictionary = {
	"speed": 2.0, "vision": 8.0, "frame": Defense.FrameType.MECH, "weapon": {"ground": 6.0}
}
## A gunship: hovers, holds station to shoot.
const CLIPPER: Dictionary = {"aerial": true, "vision": 10.0, "weapon": {"ground": 6.0}}
const SAM: Dictionary = {"structure": true, "weapon": {"air": 8.0}}


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _entity(a_options: Dictionary, a_commander: Commander) -> Commandable:
	var e := FakePieces.make(a_options) as Commandable
	add_child_autofree(e)
	e.ownership.commander = a_commander
	return e


func _attack(_a_actor: Commandable, a_target: Commandable) -> Attack:
	return Attack.new(CommandMessage.new(null, a_target, null, a_target.global_position))


## Point `a_actor` exactly at `a_point`, then swing its nose `a_degrees_off` past it.
## face_toward is RATE LIMITED (it turns one tick's worth per call), so a single call would
## leave the body wherever the turn had got to rather than where the test means it to be.
func _aim(a_actor: Commandable, a_point: Vector3, a_degrees_off: float) -> void:
	for _i: int in 400:
		if a_actor.movement.is_facing(a_point):
			break
		a_actor.movement.face_toward(a_point)
	assert_true(a_actor.movement.is_facing(a_point), "the body reached exact alignment")
	a_actor.rotation.y += deg_to_rad(a_degrees_off)


#region The dive is opt-in
## A ROCKET AIRCRAFT DROPS ITS PAYLOAD FROM CRUISE ALTITUDE. The gate used to apply to any
## FLYING attacker, which meant a Drake sitting at cruise height over its target could never
## satisfy it — and since `should_move` had already gone false the moment the tall
## AttackRange cylinder reported "in range", nothing was left to bring it down. It hung
## there, loaded and facing its victim, indefinitely.
func test_a_ranged_aircraft_never_waits_to_descend() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	var weapon: Weapon = plane.weapon_inventory.get_weapons()[0]
	assert_false(weapon.is_melee_ranged(tank), "the Drake shoots, it does not ram")
	assert_eq(plane.aerial.height_offset(), Aerial.AERIAL_HEIGHT, "and it is up at cruise")
	assert_true(
		_attack(plane, tank)._dive_contact_made(plane, weapon),
		"which is no reason at all to withhold its rockets"
	)


## The airframe the gate exists for still has it.
func test_a_ramming_aircraft_must_come_down_first() -> void:
	var cmd: Commander = _commander(1)
	var drone: Commandable = _entity(KAMIKAZE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	var weapon: Weapon = drone.weapon_inventory.get_weapons()[0]
	assert_true(
		weapon.is_melee_ranged(tank),
		"the kamikaze rams — which its REACH says, rather than a flag beside it"
	)
	var order: Attack = _attack(drone, tank)
	assert_false(
		order._dive_contact_made(drone, weapon),
		"six units up is not contact, however close it is horizontally"
	)
	drone.aerial._current_height_offset = 0.1
	assert_true(order._dive_contact_made(drone, weapon), "on the deck it connects")


## Air-to-air is fought at altitude whatever the weapon declares — there is no ground to
## come down to.
func test_a_ramming_aircraft_does_not_dive_at_an_air_target() -> void:
	var cmd: Commander = _commander(1)
	var drone: Commandable = _entity(KAMIKAZE, cmd)
	var other: Commandable = _entity(DRAKE, _commander(2))
	var weapon: Weapon = drone.weapon_inventory.get_weapons()[0]
	assert_true(_attack(drone, other)._dive_contact_made(drone, weapon))


#endregion


#region A fixed wing never stops
## Being in range is not a reason for an aeroplane to stop being driven: it has no hover to
## stop in. Without this it fell into the hole between the receiver's two branches the
## moment its clip ran dry — unable to act, not supposed to move — and coasted to a dead
## stop in mid-air.
func test_a_fixed_wing_keeps_closing_even_in_range() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	var weapon: Weapon = plane.weapon_inventory.get_weapons()[0]
	assert_true(SU.is_in_attack_range(weapon, plane, tank), "stacked on top of each other")
	assert_true(_attack(plane, tank).should_move(plane), "and it flies on regardless")


## A gunship holds station to shoot, exactly as it always did.
func test_a_gunship_still_stops_to_shoot() -> void:
	var cmd: Commander = _commander(1)
	var heli: Commandable = _entity(CLIPPER, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	var weapon: Weapon = heli.weapon_inventory.get_weapons()[0]
	assert_true(SU.is_in_attack_range(weapon, heli, tank))
	assert_false(
		_attack(heli, tank).should_move(heli), "HOVERING can hold station, so in range means stop"
	)


#endregion


#region Aiming by flying
## THE BUG THIS PINS. A unit that turns to aim and then stops converges exactly on its
## target, so holding it to a hair is fair. An aeroplane never stops turning — its facing is
## a by-product of the velocity it is being steered along — so against anything that MOVES
## its nose lags the bearing permanently. Measured on a Drake attacking a tank crossing its
## path, that lag was 0.2 degrees the whole way in: dead-on to look at, four times the
## default tolerance, and the aircraft flew the entire run without firing a shot.
func test_a_fixed_wing_shoots_within_an_arc_not_on_a_hair() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	tank.global_position = Vector3(0.0, 0.0, 0.0)
	plane.global_position = Vector3(10.0, Aerial.AERIAL_HEIGHT, 0.0)
	# Nose a fifth of a degree off the bearing — the lag actually measured in flight.
	_aim(plane, tank.global_position, 0.2)

	var order: Attack = _attack(plane, tank)
	assert_false(
		plane.movement.is_facing(tank.global_position),
		"the strict test refuses it — this is what grounded the whole mechanic"
	)
	assert_true(
		order._is_aimed_at_target(plane),
		"but an aeroplane aims by flying, and 0.2 degrees is pointing straight at it"
	)


## The arc is not a licence to shoot sideways: it still has to be pointing at the thing.
func test_a_fixed_wing_still_will_not_shoot_off_its_beam() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	plane.global_position = Vector3(10.0, Aerial.AERIAL_HEIGHT, 0.0)
	_aim(plane, tank.global_position, Attack.FLYING_AIM_ARC_DEGREES + 15.0)
	assert_false(_attack(plane, tank)._is_aimed_at_target(plane))


## A unit that CAN stop is still held to the hair — it turns to aim, so it can converge.
func test_a_unit_that_can_stop_is_still_held_to_exact_alignment() -> void:
	var cmd: Commander = _commander(1)
	var heli: Commandable = _entity(CLIPPER, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	heli.global_position = Vector3(4.0, Aerial.AERIAL_HEIGHT, 0.0)
	_aim(heli, tank.global_position, 5.0)
	assert_false(
		_attack(heli, tank)._is_aimed_at_target(heli),
		"a gunship turns to aim, so it waits until the turn has caught up"
	)


## A structure has no facing to wait on at all.
func test_a_turret_with_no_movement_is_always_aimed() -> void:
	var cmd: Commander = _commander(1)
	var turret: Commandable = _entity(SAM, cmd)
	var plane: Commandable = _entity(DRAKE, _commander(2))
	assert_null(turret.movement)
	assert_true(_attack(turret, plane)._is_aimed_at_target(turret))


#endregion


#region Running dry
func _empty(a_unit: Commandable) -> void:
	for w: Weapon in a_unit.weapon_inventory.charged_weapons():
		while w.ammo() > 0:
			w.consume_round()
	assert_true(a_unit.weapon_inventory.is_out_of_ammo())


func _move_order(a_to: Vector3) -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(null, null, null, a_to))


## The orders that only make sense with something to shoot are marked; the one that does
## not, is not.
func test_the_orders_that_assume_a_shot_declare_themselves() -> void:
	var at := CommandMessage.new(null, null, null, Vector3.ZERO)
	assert_true(Attack.new(at).requires_ammo(), "Attack")
	assert_true(
		AttackMove.new(at).requires_ammo(),
		"AttackMove — it is looking for something to shoot on the way"
	)
	assert_true(
		Defend.new(at).requires_ammo(), "Defend — holding a post means shooting what comes to it"
	)
	assert_false(_move_order(Vector3.ZERO).requires_ammo(), "a plain move is just a move")


## DEFERRED, NOT DISCARDED: the order goes to the FRONT of the queue, so the unit stops
## trying to prosecute an attack it has nothing to prosecute it with, rearms, and then picks
## the same order straight back up.
func test_an_undoable_order_is_stood_down_into_the_queue() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	plane.update_commands(_attack(plane, tank))
	plane.update_commands(_move_order(Vector3(20.0, 0.0, 0.0)), true)
	_empty(plane)

	assert_true(plane.command_receiver.defer_ammo_dependent_commands(), "it stood down")
	var chain: Array[MoveCommand] = plane.command_receiver.get_command_chain()
	assert_eq(chain.size(), 2, "nothing was thrown away")
	assert_true(chain[0] is Attack, "the attack is first in the queue, waiting its turn")
	assert_false(chain[1].requires_ammo(), "with the move behind it, untouched")


## Anything already queued was never being driven, so there is nothing to stand down.
func test_only_the_active_order_is_stood_down() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	plane.update_commands(_move_order(Vector3(20.0, 0.0, 0.0)))
	plane.update_commands(_attack(plane, tank), true)
	_empty(plane)
	assert_false(
		plane.command_receiver.defer_ammo_dependent_commands(),
		"the live order is a move, which needs no ammunition"
	)
	assert_eq(plane.command_receiver.get_command_chain().size(), 2)


## A player who sends an empty aircraft somewhere means it. The auto-return used to PREPEND
## a Rearm regardless, which overrode the order — an empty aircraft could not be sent
## anywhere but back to its airfield.
func test_an_empty_aircraft_still_obeys_a_move_order() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	_empty(plane)
	plane.update_commands(_move_order(Vector3(30.0, 0.0, 0.0)))
	plane._defer_unshootable_orders()
	plane.docking.maybe_auto_rearm()
	var chain: Array[MoveCommand] = plane.command_receiver.get_command_chain()
	assert_eq(chain.size(), 1, "nothing was pushed in front of it")
	assert_false(chain[0] is Rearm, "and it is still the move the player gave")


## Standing down happens whether or not there is anywhere to go home to: an Attack it cannot
## carry out is worth stopping on its own account.
func test_an_attack_is_stood_down_even_with_no_airfield_to_return_to() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	_empty(plane)
	plane.update_commands(_attack(plane, tank))
	plane._defer_unshootable_orders()
	assert_true(
		plane.command_receiver.awaiting_only_ammo_dependent_work(),
		"nothing left that it could usefully be doing instead of flying home"
	)


## The gate on flying home is not is_idle(): a just-deferred order is sitting in the queue,
## so the unit is not idle and must still go and rearm — but a plain move waiting to be
## popped IS real work, and a Rearm must not be put in front of it.
func test_a_queued_move_still_counts_as_work_worth_doing() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	_empty(plane)
	plane.update_commands(_move_order(Vector3(30.0, 0.0, 0.0)))
	plane.update_commands(_move_order(Vector3(40.0, 0.0, 0.0)), true)
	plane.command_receiver._command = null  # as though the first had just finished
	assert_false(plane.command_receiver.is_idle(), "the second move is still queued")
	assert_false(
		plane.command_receiver.awaiting_only_ammo_dependent_work(),
		"and it is work, so nothing goes in front of it"
	)


## A unit with rounds left keeps everything — this is about being EMPTY, not about being low.
func test_a_loaded_aircraft_keeps_its_attack() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	plane.update_commands(_attack(plane, tank))
	plane._defer_unshootable_orders()
	assert_false(plane.command_receiver.is_idle())


#endregion


#region Parked units keep to themselves
## A parked aircraft is sitting on its own airfield with its vision still live. Without this
## gate it would latch onto anything that wandered past and take off after it, which is not
## what "stays in its dock until ordered" means.
func test_a_parked_aircraft_reports_itself_parked() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	assert_false(plane.docking.is_on_deck(), "airborne to start with")
	plane.aerial.park_on_deck(0.0)
	assert_true(plane.docking.is_on_deck())
	plane.aerial.take_off()
	assert_false(plane.docking.is_on_deck(), "and no longer once it lifts")


## Nor does a parked unit send itself home — it is already there, and the bay is refilling it
## where it stands.
func test_a_parked_empty_aircraft_does_not_order_itself_home() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	_empty(plane)
	plane.aerial.park_on_deck(0.0)
	plane.docking.maybe_auto_rearm()
	assert_true(plane.command_receiver.is_idle(), "no Rearm ordered from the pad it is on")


#endregion


#region Grounded aircraft do not shoot
## AN AERIAL UNIT ON THE GROUND CANNOT SHOOT. A jet parked on its pad or rolling down a
## runway is not fighting, and one cutting down whatever wandered past its hangar reads as
## a turret rather than an aeroplane.
##
## It is also the other half of a bargain the targeting rules already struck: a grounded
## aircraft is shot at with a weapon's GROUND range, deliberately, so that it is not
## untouchable while it sits there. Being harmless in return is what makes that fair.
func test_a_parked_aircraft_cannot_fire() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var tank: Commandable = _entity(TANK, _commander(2))
	assert_true(plane.can_use_weapons(), "airborne, so it may shoot")

	plane.aerial.park_on_deck(0.0)
	assert_false(plane.can_use_weapons(), "on the deck, it may not")
	assert_false(
		_attack(plane, tank)._own_weapon_can_fire(plane),
		"and the attack refuses to pull the trigger"
	)


## The windows either side count as grounded too: an aircraft on its takeoff roll or its
## final approach has something else to be doing.
func test_an_aircraft_cannot_fire_while_climbing_out() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	plane.aerial.park_on_deck(0.0)
	plane.aerial.take_off()
	assert_false(plane.can_use_weapons(), "still on its way up")

	for _i: int in 2000:
		plane.aerial._physics_process(0.0)
		if plane.aerial.is_airborne():
			break
	assert_true(plane.can_use_weapons(), "and free to fight once it is up")


## A helicopter set down in a field is grounded by a different route and must obey the
## same rule.
func test_a_landed_gunship_cannot_fire() -> void:
	var cmd: Commander = _commander(1)
	var heli: Commandable = _entity(CLIPPER, cmd)
	assert_true(heli.can_use_weapons())
	heli.aerial.land(Callable())
	for _i: int in 2000:
		heli.aerial._physics_process(0.0)
		if not heli.aerial.is_airborne():
			break
	assert_false(heli.aerial.is_airborne(), "it is on the ground")
	assert_false(heli.can_use_weapons())


## Ground units and turrets are untouched — they have no flight state to be wrong about.
func test_ground_units_and_turrets_are_unaffected() -> void:
	var cmd: Commander = _commander(1)
	assert_true(_entity(TANK, cmd).can_use_weapons(), "a tank shoots from the ground")
	var turret: Commandable = _entity(SAM, cmd)
	assert_null(turret.movement)
	assert_true(turret.can_use_weapons(), "and a turret has no flight state at all")


## Nor does a grounded aircraft shoot BACK, or go looking for something to shoot: it would
## only be given an order it cannot carry out, and a parked one would chase off its pad.
func test_a_parked_aircraft_does_not_retaliate() -> void:
	var cmd: Commander = _commander(1)
	var plane: Commandable = _entity(DRAKE, cmd)
	var enemy: Commandable = _entity(TANK, _commander(2))
	plane.aerial.park_on_deck(0.0)
	assert_null(plane._retaliation_against(enemy))
#endregion
