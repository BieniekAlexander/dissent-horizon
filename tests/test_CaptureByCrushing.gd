extends GutTest

## Capture is a crush. A Stock Truck takes prisoners by DRIVING OVER them: there is no
## capture order and no interaction — the truck outsizes light infantry, and running one
## over puts it in the cage instead of killing it.
##
## The rule this file pins hardest: CAPACITY GATES THE CAPTURE, NEVER THE CRUSH. A full
## truck still flattens the enemy soldier it drives over.
##
## Two predicates, tested directly because both are pure:
##   Garrison.can_capture(captor, captive) — would this contact take a prisoner?
##   Commandable._can_run_over(other)      — would driving into it come to anything at all?
## The contact itself needs a physics tick and is not covered here.
##
## Scenes are load()ed INSIDE the tests rather than preloaded at file scope — a file-scope
## preload of an entity scene runs at parse time and can fire Tool's static registry build
## before the registry exists, poisoning every test after it. See CLAUDE.md §Running and
## testing.

## A crusher with a cage; light infantry; a machine as big as the crusher; a structure.
const TRUCK_PATH: Dictionary = {
	"speed": 2.0, "crush": Movement.CrushClass.LARGE, "garrison": {"capacity": 3, "bunker": false}
}
const TERRESTRIAL_PATH: Dictionary = {"speed": 1.0}
const RECRUIT_PATH: Dictionary = {"speed": 1.0, "weapon": {"ground": 6.0}}
## A MECH-frame vehicle of the truck's own crush class — too big to run over, and not flesh.
const VEHICLE_PATH: Dictionary = {
	"speed": 1.0,
	"frame": Defense.FrameType.MECH,
	"armour": Defense.ArmourType.MEDIUM,
	"crush": Movement.CrushClass.LARGE
}
const COMPOUND_PATH: Dictionary = {"structure": true}

const PLAYER: int = 1
const ENEMY: int = 2
const NEUTRAL: int = 0


func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


func _entity(a_options: Dictionary, a_commander_id: int) -> Commandable:
	var e: Commandable = (
		FakePieces.structure(a_options)
		if a_options.has("structure")
		else FakePieces.unit(a_options)
	)
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e


## A truck whose cage is already full of prisoners.
func _full_truck() -> Commandable:
	var truck: Commandable = _entity(TRUCK_PATH, PLAYER)
	for _i in range(truck.garrison.capacity):
		truck.garrison.garrison(_entity(TERRESTRIAL_PATH, NEUTRAL))
	assert_eq(truck.garrison.remaining_capacity(), 0, "the cage is full")
	return truck


#region Who is capturable
func test_a_neutral_terrestrial_is_prey() -> void:
	assert_true(
		Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), _entity(TERRESTRIAL_PATH, NEUTRAL))
	)


func test_an_enemy_soldier_is_prey() -> void:
	assert_true(Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), _entity(RECRUIT_PATH, ENEMY)))


func test_our_own_soldiers_are_not() -> void:
	assert_false(Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), _entity(RECRUIT_PATH, PLAYER)))


func test_a_vehicle_is_not_prey() -> void:
	assert_false(
		Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), _entity(VEHICLE_PATH, ENEMY)),
		"capture takes the crew, not the machine"
	)


func test_a_structure_is_not_prey() -> void:
	assert_false(Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), _entity(COMPOUND_PATH, ENEMY)))


func test_heavier_armour_is_not_prey() -> void:
	var soldier: Commandable = _entity(RECRUIT_PATH, ENEMY)
	soldier.defense.armour_type = Defense.ArmourType.MEDIUM
	assert_false(
		Garrison.can_capture(_entity(TRUCK_PATH, PLAYER), soldier), "the cage is for light infantry"
	)


func test_a_unit_with_no_hold_captures_nobody() -> void:
	assert_false(Garrison.can_capture(_entity(RECRUIT_PATH, PLAYER), _entity(RECRUIT_PATH, ENEMY)))


func test_a_full_truck_captures_nobody() -> void:
	assert_false(Garrison.can_capture(_full_truck(), _entity(RECRUIT_PATH, ENEMY)))


#endregion


#region What contact comes to
func test_the_truck_outsizes_infantry() -> void:
	var truck: Commandable = _entity(TRUCK_PATH, PLAYER)
	assert_true(
		truck.movement.can_crush(_entity(RECRUIT_PATH, ENEMY).movement),
		"the whole mechanic rests on the truck being a crusher"
	)


func test_driving_at_prey_comes_to_something() -> void:
	var truck: Commandable = _entity(TRUCK_PATH, PLAYER)
	assert_true(truck._can_run_over(_entity(RECRUIT_PATH, ENEMY)))
	assert_true(
		truck._can_run_over(_entity(TERRESTRIAL_PATH, NEUTRAL)),
		"a neutral is reached through the capture arm alone"
	)


## THE RULE. A full cage is a reason not to take a prisoner; it is not a reason to drive
## politely around the enemy soldier in front of the wheels.
func test_a_full_truck_still_crushes_an_enemy() -> void:
	assert_true(_full_truck()._can_run_over(_entity(RECRUIT_PATH, ENEMY)))


## The other side of it: a neutral was never crushable, and a truck that cannot take one
## has no business ploughing through it either.
func test_a_full_truck_leaves_a_neutral_alone() -> void:
	assert_false(_full_truck()._can_run_over(_entity(TERRESTRIAL_PATH, NEUTRAL)))


func test_our_own_units_are_never_run_over() -> void:
	var truck: Commandable = _entity(TRUCK_PATH, PLAYER)
	assert_false(truck._can_run_over(_entity(RECRUIT_PATH, PLAYER)))


func test_something_its_own_size_is_not_run_over() -> void:
	var truck: Commandable = _entity(TRUCK_PATH, PLAYER)
	assert_false(truck._can_run_over(_entity(VEHICLE_PATH, ENEMY)))
#endregion
