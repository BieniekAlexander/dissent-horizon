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

## A carrier with a hold and a DEPOSIT errand.
const SUPPLY_TRUCK: Dictionary = {
	"speed": 2.0, "garrison": {"capacity": 3}, "interactions": [Interaction.Type.DEPOSIT]
}
const TERRESTRIAL: Dictionary = {"speed": 1.0}
## A closed hold that sentences what is deposited in it.
const COMPOUND: Dictionary = {
	"structure": true,
	"garrison": {"capacity": 6, "sentence_length": 30.0, "frames": 0, "armours": 0, "movements": 0}
}
## A structure with an OPEN garrison — one that holds units but interns nobody.
## An ordinary garrison: holds occupants, sentences nobody.
const OPEN_GARRISON: Dictionary = {"structure": true, "garrison": {"capacity": 4}}


func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


## A live unit instance owned by [a_commander_id]. Ownership is assigned directly (not
## through initialize) so no Map is needed.
func _unit(a_options: Dictionary, a_commander_id: int) -> Actor:
	var u: Actor = (
		FakePieces.structure(a_options)
		if a_options.has("structure")
		else FakePieces.unit(a_options)
	)
	add_child_autofree(u)
	u.ownership.commander = _commanded(a_commander_id)
	return u


func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)


func _interaction_of(a_unit: Actor, a_type: Interaction.Type) -> Interaction:
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


func test_interact_does_not_end_on_arrival():
	var truck := _unit(SUPPLY_TRUCK, 1)
	truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var order := Interact.new(_message_for(_unit(COMPOUND, 1)))
	assert_false(
		order.ends_on_arrival(),
		"arriving is not the point — depositing is, and only can_act/fulfill_action decide that"
	)


## --- Unloading one captive at a time ---------------------------------------


## Run `a_order` on `a_truck` until it ends, returning the tick each captive reached the
## Compound, counted from the first fulfilled tick. Bounded so a stuck order fails the test.
func _unload(a_truck: Actor, a_order: Interact, a_compound: Actor) -> Array[int]:
	var arrivals: Array[int] = []
	var held: int = a_compound.garrison.garrisoned_count()
	for tick: int in 10000:
		var next: Variant = a_order.fulfill_action(a_truck)
		var now_held: int = a_compound.garrison.garrisoned_count()
		for _i: int in now_held - held:
			arrivals.append(tick)
		held = now_held
		if next == null:
			break
	return arrivals


func test_a_truck_with_an_unload_time_hands_captives_over_one_interval_apart():
	var truck := _unit(
		{
			"speed": 2.0,
			"garrison": {"capacity": 3, "unload_time": 1.0},
			"interactions": [Interaction.Type.DEPOSIT]
		},
		1
	)
	for _i: int in 3:
		truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var compound := _unit(COMPOUND, 1)
	var arrivals: Array[int] = _unload(truck, Interact.new(_message_for(compound)), compound)
	var interval: int = TimeUtils.ticks_from_seconds(1.0)
	assert_eq(arrivals.size(), 3, "every captive is handed over")
	assert_eq(arrivals[1] - arrivals[0], interval)
	assert_eq(arrivals[2] - arrivals[1], interval)
	assert_eq(truck.garrison.garrisoned_count(), 0)


func test_an_unload_stops_when_the_compound_is_full():
	var truck := _unit(
		{
			"speed": 2.0,
			"garrison": {"capacity": 3, "unload_time": 1.0},
			"interactions": [Interaction.Type.DEPOSIT]
		},
		1
	)
	for _i: int in 3:
		truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var small_compound := _unit(
		{
			"structure": true,
			"garrison":
			{"capacity": 2, "sentence_length": 30.0, "frames": 0, "armours": 0, "movements": 0}
		},
		1
	)
	var arrivals: Array[int] = _unload(
		truck, Interact.new(_message_for(small_compound)), small_compound
	)
	assert_eq(arrivals.size(), 2, "only what fits")
	assert_eq(truck.garrison.garrisoned_count(), 1, "the rest stays with the truck")


func test_without_an_unload_time_the_whole_load_goes_at_once():
	var truck := _unit(SUPPLY_TRUCK, 1)
	for _i: int in 3:
		truck.garrison.garrison(_unit(TERRESTRIAL, 0))
	var compound := _unit(COMPOUND, 1)
	var arrivals: Array[int] = _unload(truck, Interact.new(_message_for(compound)), compound)
	assert_eq(arrivals.size(), 3)
	assert_eq(arrivals[0], arrivals[2], "on one tick")
