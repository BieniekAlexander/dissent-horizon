extends GutTest

## Tests for the Interactor / Interaction mechanic: a unit's list of interactions and
## the per-type precondition each is gated by.
##
## Applicability is decided by the interaction type's mapped evaluation function. DEPOSIT is
## the one exercised here — it is the type the Stock Truck still carries, and its rule is a
## real one: the target must be a structure whose garrison INTERNS, and the actor must
## actually be holding somebody.
##
## Capture is no longer an interaction at all: a truck takes prisoners by driving over them
## (see test_CaptureByCrushing.gd). HIJACK has its own file.

const SUPPLY_TRUCK := preload("res://scenes/entities/units/cl/cl_mechLight_dominionGen.tscn")
const TERRESTRIAL := preload("res://scenes/entities/units/nt/nt_bioLight_terrestrial.tscn")
const COMPOUND := preload("res://scenes/entities/structures/cl/cl_infrastructure.tscn")
## A structure with an OPEN garrison — one that holds units but interns nobody.
const OPEN_GARRISON := preload("res://scenes/entities/structures/nt/nt_building.tscn")

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

## A live unit instance owned by [a_commander_id]. Ownership is assigned directly (not
## through initialize) so no Map is needed.
func _unit(a_scene: PackedScene, a_commander_id: int) -> Commandable:
	var u := a_scene.instantiate() as Commandable
	add_child_autofree(u)
	u.ownership.commander = _commanded(a_commander_id)
	return u

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func _interaction_of(a_unit: Commandable, a_type: Interaction.Type) -> Interaction:
	if a_unit.interactor == null:
		return null
	for i: Interaction in a_unit.interactor.interactions:
		if i.type == a_type:
			return i
	return null

## --- DEPOSIT applicability -------------------------------------------------

func test_deposit_applies_to_a_camp_when_the_truck_is_loaded():
	var truck := _unit(SUPPLY_TRUCK, 1)
	truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var camp := _unit(COMPOUND, 1)
	var resolved: Interaction = truck.interactor.applicable_interaction(truck, _message_for(camp))
	assert_not_null(resolved, "a loaded truck can deposit at a compound")
	assert_eq(resolved.type, Interaction.Type.DEPOSIT)

func test_deposit_does_not_apply_to_an_empty_truck():
	var truck := _unit(SUPPLY_TRUCK, 1)
	assert_null(
		truck.interactor.applicable_interaction(truck, _message_for(_unit(COMPOUND, 1))),
		"there is nothing to hand over"
	)

func test_deposit_does_not_apply_to_a_structure_that_does_not_intern():
	var truck := _unit(SUPPLY_TRUCK, 1)
	truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	assert_null(
		truck.interactor.applicable_interaction(truck, _message_for(_unit(OPEN_GARRISON, 1))),
		"an open safehouse is not a prison camp"
	)

func test_deposit_evaluation_returns_failure_cause():
	var truck := _unit(SUPPLY_TRUCK, 1)
	var deposit: Interaction = _interaction_of(truck, Interaction.Type.DEPOSIT)
	assert_not_null(deposit, "the truck carries a DEPOSIT interaction")
	assert_eq(
		deposit.meets_precondition(truck, _message_for(_unit(COMPOUND, 1))),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"empty: nothing to deposit"
	)
	truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	assert_eq(
		deposit.meets_precondition(truck, _message_for(_unit(COMPOUND, 1))),
		MoveCommand.PreconditionFailureCause.NONE
	)

## --- The truck's interaction list ------------------------------------------

func test_supply_truck_carries_only_deposit():
	# Both of the errands it used to carry are gone from this list: the shelter COLLECT
	# errand, and then ABDUCT, which became a contact mechanic (Garrison.can_capture).
	var truck := _unit(SUPPLY_TRUCK, 1)
	var types: Array = truck.interactor.interactions.map(func(i: Interaction) -> int: return i.type)
	assert_eq(types, [Interaction.Type.DEPOSIT])

## --- Interact travels in order to ACT, and arriving is not the point ---------
##
## `Interact` inherited `ends_on_arrival()`'s default `true`, which is wrong for every
## interaction it drives (DEPOSIT, HIJACK): a unit that had to WALK to its target
## dropped the whole order the tick navigation reported "arrived", if that happened even one
## tick before `_in_reach` agreed — leaving a loaded truck standing at a Compound, cargo
## intact, doing nothing forever. Same bug, same fix, as Build/Assemble/Repair.

func test_interact_does_not_end_on_arrival():
	var truck := _unit(SUPPLY_TRUCK, 1)
	truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var order := Interact.new(_message_for(_unit(COMPOUND, 1)))
	assert_false(order.ends_on_arrival(),
		"arriving is not the point — depositing is, and only can_act/fulfill_action decide that")
