extends GutTest

## RETALIATION, AND LETTING GO OF WHAT YOUR SIDE CAN NO LONGER SEE.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Retaliation.gd -gexit
##
## An idle piece hit from past its aggro answers the attacker — unless it is holding fire, is
## busy, or its side cannot see the attacker. A piece that cannot move answers only what it
## already reaches. And an attack whose target, once seen, drops out of the side's vision is
## dropped. Why: gdd/systems/combat/target-acquisition.md §Retaliation answers fire from past aggro.
##
## PATHS, not preloads (see CLAUDE.md). Every scene is a HARNESS: distances are set against
## reach buckets the test reads back, never against a number pinned here.

const RECRUIT: Dictionary = FakePieces.SOLDIER
const IRREGULAR: Dictionary = FakePieces.BUILDER
const TURRET: Dictionary = FakePieces.BUILDING
const BADGER: Dictionary = FakePieces.SOLDIER
const SHELTER: Dictionary = FakePieces.BUILDING
const OWN: int = 7
const ENEMY: int = 8

## Past every reach and aggro a harness piece has, so "out of range" does not depend on
## the current bucket radii.
const FAR: float = 60.0


func before_each() -> void:
	Fog._fogs_by_commander.clear()


func after_each() -> void:
	Fog._fogs_by_commander.clear()


func _commander(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _piece(a_options: Dictionary, a_commander: Commander, a_at: Vector3) -> Commandable:
	var p := FakePieces.make(a_options) as Commandable
	add_child_autofree(p)
	p.ownership.commander = a_commander
	p.global_position = a_at
	return p


## A fog for [a_id] with no Map to initialise against: it has revealed nothing, so every
## enemy is out of that commander's vision.
func _blind(a_id: int) -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = a_id
	add_child_autofree(fog)
	return fog


## A recruit and an enemy standing `a_gap` apart, both settled into physics.
func _pair(a_gap: float) -> Array:
	var shooter: Commandable = _piece(RECRUIT, _commander(OWN), Vector3.ZERO)
	var attacker: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(a_gap, 0.0, 0.0))
	await wait_physics_frames(2)
	return [shooter, attacker]


func _is_attack_on(a_command: MoveCommand, a_target: Entity) -> bool:
	return a_command is Attack and a_command.message.target == a_target


#region Who answers
func test_an_idle_unit_answers_an_attacker_past_its_aggro() -> void:
	var pair: Array = await _pair(FAR)
	var shooter: Commandable = pair[0]
	assert_gt(VU.inXZ(shooter.global_position).distance_to(VU.inXZ(pair[1].global_position)),
		shooter.aggro_radius(), "guards the fixture: the attacker is past aggro")
	shooter.receive_damage(Damage.new(1.0), pair[1])
	assert_true(_is_attack_on(shooter.current_command(), pair[1]))


func test_a_unit_holding_fire_does_not_answer() -> void:
	var pair: Array = await _pair(FAR)
	var shooter: Commandable = pair[0]
	shooter.is_holding_fire = true
	shooter.receive_damage(Damage.new(1.0), pair[1])
	assert_null(shooter.current_command())


func test_a_busy_unit_keeps_its_order() -> void:
	var pair: Array = await _pair(FAR)
	var shooter: Commandable = pair[0]
	var other: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(0.0, 0.0, 3.0))
	shooter.update_commands(Attack.new(CommandMessage.new(null, other, null)))
	shooter.receive_damage(Damage.new(1.0), pair[1])
	assert_true(_is_attack_on(shooter.current_command(), other), "its own order stands")


func test_an_attacker_out_of_the_side_s_vision_is_not_answered() -> void:
	var pair: Array = await _pair(FAR)
	_blind(OWN)
	assert_null((pair[0] as Commandable)._retaliation_against(pair[1]))


func test_a_friendly_hit_is_not_answered() -> void:
	var shooter: Commandable = _piece(RECRUIT, _commander(OWN), Vector3.ZERO)
	var friend: Commandable = _piece(IRREGULAR, shooter.ownership.commander, Vector3(FAR, 0, 0))
	await wait_physics_frames(2)
	assert_null(shooter._retaliation_against(friend))
#endregion


#region A piece that cannot move
func test_a_turret_answers_an_attacker_it_reaches() -> void:
	var turret: Commandable = _piece(TURRET, _commander(OWN), Vector3.ZERO)
	var reach: float = turret.weapon_inventory.get_weapons()[0].ground_reach()
	var attacker: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(reach * 0.5, 0, 0))
	await wait_physics_frames(2)
	assert_false(turret.can_move(), "guards the fixture")
	assert_true(_is_attack_on(turret._retaliation_against(attacker), attacker))


func test_a_turret_ignores_an_attacker_out_of_its_reach() -> void:
	var turret: Commandable = _piece(TURRET, _commander(OWN), Vector3.ZERO)
	var attacker: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(FAR, 0, 0))
	await wait_physics_frames(2)
	assert_null(turret._retaliation_against(attacker))


## An unarmed shelter answers through its occupants, at their reach plus its bonus.
func _manned_shelter(a_occupant: String = RECRUIT) -> Commandable:
	var shelter: Commandable = _piece(SHELTER, _commander(OWN), Vector3.ZERO)
	var occupant: Commandable = _piece(a_occupant, shelter.ownership.commander, Vector3(0, 0, FAR))
	await wait_physics_frames(2)  # let the occupant's deferred initialisation run in the tree
	shelter.garrison.garrison(occupant)
	autofree(occupant)
	return shelter


func test_a_manned_shelter_answers_through_its_occupants() -> void:
	var shelter: Commandable = await _manned_shelter()
	var attacker: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(3.0, 0, 3.0))
	await wait_physics_frames(2)
	assert_true(_is_attack_on(shelter._retaliation_against(attacker), attacker))


func test_a_manned_shelter_ignores_what_its_occupants_cannot_reach() -> void:
	var shelter: Commandable = await _manned_shelter()
	var attacker: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(FAR, 0, 0))
	await wait_physics_frames(2)
	assert_null(shelter._retaliation_against(attacker))
#endregion


#region A bunker's order
## A bunker has no weapon of its own, so its leash is its occupants' reach. It was its aggro,
## which is capped below long reach: an order on an enemy standing at the occupants' full
## reach was dropped on its first tick.
func test_a_bunker_keeps_an_order_on_a_target_its_occupants_reach() -> void:
	var shelter: Commandable = await _manned_shelter(BADGER)
	var reach: float = shelter.reach_on_layer(CollisionLayers.Mask.TARGETABLE_GROUND)
	var at: float = reach - 1.0
	assert_gt(at, shelter.aggro_radius() * Attack._LEASH_HYSTERESIS,
		"guards the fixture: past where an aggro-based leash would let go")
	var foe: Commandable = _piece(IRREGULAR, _commander(ENEMY), Vector3(at, 0, 0))
	await wait_physics_frames(2)
	assert_true(shelter.garrison.can_reach(shelter, foe), "guards the fixture: within reach")
	var attack := Attack.new(CommandMessage.new(null, foe, null))
	assert_same(attack.get_updated_state(shelter), attack)
#endregion


#region Losing sight of a target
func test_an_attack_is_dropped_when_its_target_leaves_vision() -> void:
	var pair: Array = await _pair(FAR)
	var attack := Attack.new(CommandMessage.new(null, pair[1], null))
	assert_same(attack.get_updated_state(pair[0]), attack, "guards the fixture: seen, so kept")
	_blind(OWN)
	assert_null(attack.get_updated_state(pair[0]), "it ran into the fog, so the order goes")


func test_an_attack_on_a_target_never_seen_is_kept() -> void:
	var pair: Array = await _pair(FAR)
	_blind(OWN)
	var attack := Attack.new(CommandMessage.new(null, pair[1], null))
	assert_same(attack.get_updated_state(pair[0]), attack,
		"an order on a fogged target is pursued until the target is first seen")
#endregion
