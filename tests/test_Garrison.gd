extends GutTest

## Tests for garrison OCCUPANCY: who a garrison lets in, how much room each occupant
## takes, the closed hold (the Compound) that is filled only by deposit, the stock truck's
## cage that fills by capture and admits Servants by order, and the INTERNMENT the Compound
## performs on what is deposited there.
##
## Three questions, three methods (see Garrison):
##   admits()       — do the frame / armour / movement masks and the id allowlist let it in?
##   has_room_for() — does its occupancy_size still fit?
##   accepts()      — both, i.e. can it garrison right now?
## Involuntary custody (capture, deposit, scenario authoring) asks only has_room_for, so
## a hold with every mask cleared still fills — that is what makes it a cage rather
## than a shelter.

## The stock cage: three seats, servants only, banks prisoners.
const SUPPLY_TRUCK: Dictionary = {
	"speed": 2.0,
	"vision": 8.0,
	"crush": Movement.CrushClass.LARGE,
	"garrison": {"capacity": 3, "bunker": false, "captures": true, "ids": [&"fake_servant"]},
	"interactions": [Interaction.Type.DEPOSIT]
}
const COMPOUND: Dictionary = FakePieces.COMPOUND
## A structure with an OPEN garrison, as the counterpart to the Compound's closed one.
## This was the Anarchical safehouse; that piece became `an_infrastructure`, which no
## longer carries a Garrison at all, so these tests use the neutral building instead — still
## an open garrison, and the thing the safehouse conversion upgrades FROM (see Build's
## conversion path).
const OPEN_GARRISON: Dictionary = {"structure": true, "garrison": {"capacity": 4}}
## A transport that admits any grounded soldier.
const MERCURY: Dictionary = {"speed": 2.0, "garrison": {"capacity": 4}}
const RECRUIT: Dictionary = {"speed": 2.0, "vision": 8.0}
## The piece the truck's allowlist names: the same body as a recruit, another id.
const SERVANT: Dictionary = {"id": &"fake_servant", "speed": 2.0, "vision": 8.0}
const TERRESTRIAL: Dictionary = {"speed": 1.0}
## The size-2 occupant. Was `collective.tscn`, a scene that no longer exists — which made
## this whole FILE unparseable, and GUT skips (rather than fails) a test script it cannot
## parse, so every test here had been silently not running. See CLAUDE.md §6.4.
## The size-2 occupant: a machine, medium armour.
const COLLECTIVE: Dictionary = {
	"speed": 2.0,
	"frame": Defense.FrameType.MECH,
	"armour": Defense.ArmourType.MEDIUM,
	"occupancy": 2
}
const CLIPPER: Dictionary = FakePieces.AIRCRAFT


func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c


## A live entity instance owned by [a_commander_id]. Ownership is assigned directly (not
## through initialize) so no Map is needed, mirroring test_Interaction's helper.
func _entity(a_options: Dictionary, a_commander_id: int) -> Actor:
	var e := FakePieces.make(a_options) as Actor
	add_child_autofree(e)
	e.ownership.commander = _commanded(a_commander_id)
	return e


## A host-less Garrison with the given capacity, for the pure capacity/mask arithmetic.
func _garrison(a_capacity: int) -> Garrison:
	var g := Garrison.new()
	g.capacity = a_capacity
	return autofree(g)


func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)


## --- Occupancy masks -------------------------------------------------------


func test_default_masks_admit_a_grounded_soldier():
	# GROUNDED + any frame + any armour is the default, i.e. what every garrison
	# authored before the masks existed still means.
	var g: Garrison = _garrison(4)
	assert_true(g.admits(_entity(RECRUIT, 1)), "a grounded soldier is admitted by default")


func test_default_masks_reject_an_aerial_unit():
	var g: Garrison = _garrison(4)
	var clipper: Actor = _entity(CLIPPER, 1)
	assert_eq(clipper.movement.mode, Movement.Mode.HOVERING, "the clipper is a hovering unit")
	assert_false(g.admits(clipper), "hovering units are not admitted by default")
	g.occupiable_movements |= Garrison.MOVEMENT_HOVERING
	assert_true(g.admits(clipper), "a hangar-style garrison takes hovering units")


func test_frame_mask_rejects_the_wrong_frame():
	var g: Garrison = _garrison(4)
	g.occupiable_frames = Garrison.FRAME_BIO
	assert_true(g.admits(_entity(RECRUIT, 1)), "a biological unit fits a flesh-only hold")
	assert_false(g.admits(_entity(COLLECTIVE, 1)), "a metallic unit does not")


func test_armour_mask_rejects_heavier_armour():
	var g: Garrison = _garrison(4)
	g.occupiable_armours = Garrison.ARMOUR_LIGHT
	assert_true(g.admits(_entity(RECRUIT, 1)), "light armour fits a light-only hold")
	assert_false(g.admits(_entity(COLLECTIVE, 1)), "heavier armour does not")


func test_a_garrison_with_every_mask_cleared_admits_nobody():
	var g: Garrison = _garrison(4)
	g.occupiable_frames = 0
	g.occupiable_armours = 0
	g.occupiable_movements = 0
	assert_true(g.is_closed(), "all masks cleared reads as a closed hold")
	assert_false(g.admits(_entity(RECRUIT, 1)), "a closed hold admits nobody")
	assert_true(g.has_room_for(_entity(RECRUIT, 1)), "but it still has room to be filled")


## --- Occupancy size --------------------------------------------------------


func test_occupancy_size_defaults_to_one():
	assert_eq(_entity(RECRUIT, 1).occupancy_size, 1, "an ordinary soldier is size 1")


func test_a_collective_takes_two_slots():
	assert_eq(_entity(COLLECTIVE, 1).occupancy_size, 2, "a war wagon is size 2")


func test_capacity_is_spent_in_occupancy_size_not_head_count():
	var g: Garrison = _garrison(4)
	g.garrison(_entity(COLLECTIVE, 1))
	assert_eq(g.occupied_size(), 2, "one collective spends 2 of the capacity")
	assert_eq(g.garrisoned_count(), 1, "while still being a single occupant")
	g.garrison(_entity(COLLECTIVE, 1))
	assert_eq(g.occupied_size(), 4, "two collectives fill a capacity of 4")
	assert_eq(g.remaining_capacity(), 0)
	assert_false(g.has_room_for(_entity(RECRUIT, 1)), "not even a size-1 soldier fits now")
	assert_false(g.can_garrison(), "and the host reports itself full")


func test_a_bulky_unit_needs_two_free_slots():
	var g: Garrison = _garrison(4)
	g.garrison(_entity(RECRUIT, 1))
	g.garrison(_entity(RECRUIT, 1))
	g.garrison(_entity(RECRUIT, 1))
	assert_eq(g.remaining_capacity(), 1)
	assert_false(g.has_room_for(_entity(COLLECTIVE, 1)), "a size-2 occupant needs 2 free")
	assert_true(g.has_room_for(_entity(RECRUIT, 1)), "a size-1 occupant still fits")


## --- The stock truck / Compound holds -------------------------------


func test_the_stock_truck_cage_admits_servants_and_nobody_else_by_order():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var cage: Garrison = truck.get_node("Garrison") as Garrison
	assert_false(cage.is_closed(), "a Servant can be ordered in")
	assert_true(cage.admits(_entity(SERVANT, 1)), "a Servant rides the truck")
	assert_false(cage.admits(_entity(RECRUIT, 1)), "a Recruit, the same body, does not")
	assert_eq(cage.capacity, 3, "it holds three")
	assert_false(cage.bunker, "and prisoners never fire out of it")
	assert_null(truck.get_node_or_null("Inventory"), "the carried-items Inventory is gone")


func test_the_compound_is_a_closed_hold_that_sentences_what_is_deposited():
	var compound: Actor = FakePieces.make(COMPOUND)
	var hold: Garrison = compound.get_node("Garrison") as Garrison
	assert_true(hold.is_closed(), "deposit is the only way in — nothing may be ordered into it")
	assert_true(
		hold.occupiable_ids.is_empty(), "no allowlist: a captive is held as itself, never a Servant"
	)
	assert_gt(hold.capacity, 0, "it has room to hold what is deposited")
	assert_false(hold.bunker)
	assert_true(hold.can_intern(), "it takes deposited captives")
	assert_gt(hold.sentence_length, 0.0, "a captive serves a term before being consumed")
	assert_true(
		compound.get_node("DominionGenerator") is OccupantDominionGenerator,
		"its dominion is generated per occupant"
	)
	compound.free()


func test_the_allowlist_rejects_a_unit_the_masks_would_admit():
	# A Recruit is the same frame, armour and locomotion as a Servant — the masks cannot
	# tell them apart, which is the whole reason occupiable_ids exists.
	var g: Garrison = _garrison(4)
	g.occupiable_ids = [&"fake_servant"] as Array[StringName]
	assert_true(g.admits(_entity(SERVANT, 1)), "the named piece is admitted")
	assert_false(g.admits(_entity(RECRUIT, 1)), "an identical body with another id is not")


func test_an_empty_allowlist_restricts_nothing():
	var g: Garrison = _garrison(4)
	assert_true(g.occupiable_ids.is_empty(), "the default names nobody")
	assert_true(g.admits(_entity(RECRUIT, 1)), "which means everyone the masks allow")


func test_an_ordinary_garrison_is_not_closed():
	var shelter: Actor = FakePieces.make(OPEN_GARRISON)
	assert_false(
		(shelter.get_node("Garrison") as Garrison).is_closed(),
		"an ordinary garrison is shelter, not a prison"
	)
	shelter.free()


## --- The two directions of the door ----------------------------------------
##
## `is_closed()` is entry; `can_release()` is exit, and `can_release_occupant()` which of the
## occupants an order lets out — see gdd/systems/combat/garrison-and-transport.md.


func test_occupy_into_a_stock_truck_is_for_servants_only():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	assert_eq(
		Occupy.meets_precondition(_entity(SERVANT, 1), _message_for(truck)),
		MoveCommand.PreconditionFailureCause.NONE,
		"a Servant can be ordered into its own side's truck"
	)
	assert_eq(
		Occupy.meets_precondition(_entity(RECRUIT, 1), _message_for(truck)),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"no other piece can"
	)
	assert_eq(
		Occupy.meets_precondition(_entity(SERVANT, 2), _message_for(truck)),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"nor another side's Servant"
	)


func test_occupy_is_allowed_for_an_open_garrison():
	var recruit: Actor = _entity(RECRUIT, 1)
	var mercury: Actor = _entity(MERCURY, 1)
	assert_eq(
		Occupy.meets_precondition(recruit, _message_for(mercury)),
		MoveCommand.PreconditionFailureCause.NONE,
		"a transport still takes a grounded soldier"
	)


func test_occupy_is_refused_when_the_movement_mask_rejects_the_unit():
	var clipper: Actor = _entity(CLIPPER, 1)
	var mercury: Actor = _entity(MERCURY, 1)
	assert_eq(
		Occupy.meets_precondition(clipper, _message_for(mercury)),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"a hovering unit can't garrison a grounded-only transport"
	)
	(mercury.garrison as Garrison).occupiable_movements |= Garrison.MOVEMENT_HOVERING
	assert_eq(
		Occupy.meets_precondition(clipper, _message_for(mercury)),
		MoveCommand.PreconditionFailureCause.NONE,
		"widening the movement mask lets it in"
	)


## The Compound separates the two directions: closed to entry, open to exit.
func test_evacuate_is_allowed_for_a_closed_hold():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison as Garrison
	assert_true(hold.is_closed(), "nothing can be ordered into the Compound")
	assert_true(hold.can_release(), "and its Servants can still be let out")
	assert_eq(
		Evacuate.meets_precondition(compound, _message_for(null)),
		MoveCommand.PreconditionFailureCause.NONE
	)


## An order releases the host's own side and never a captive.
func test_an_order_releases_a_servant_and_never_a_captive():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var cage: Garrison = truck.garrison as Garrison
	var servant: Actor = _entity(SERVANT, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	cage.garrison(servant)
	cage.garrison(captive)
	assert_false(cage.is_captive(servant))
	assert_true(cage.is_captive(captive))
	assert_true(cage.can_release_occupant(servant), "the owner's Servant may be let out")
	assert_false(cage.can_release_occupant(captive), "the prisoner may not")


func test_evacuating_a_truck_turns_out_its_servants_and_keeps_its_captives():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var cage: Garrison = truck.garrison as Garrison
	var servant: Actor = _entity(SERVANT, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	cage.garrison(servant)
	cage.garrison(captive)
	cage.evacuate_by_order(null)
	assert_true(servant.is_inside_tree(), "the Servant is back in the world")
	assert_eq(cage.occupants(), [captive] as Array[Actor], "the prisoner stays")
	assert_false(captive.is_inside_tree())


func test_a_servant_let_out_of_a_compound_leaves_the_prisoners_serving():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison as Garrison
	var servant: Actor = _entity(SERVANT, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	hold.garrison(captive)
	hold.garrison(servant)
	hold._physics_process(1.0)
	hold.evacuate_by_order(null)
	assert_true(servant.is_inside_tree(), "released before its sentence ended, back in the game")
	assert_eq(hold.occupants(), [captive] as Array[Actor])
	assert_almost_eq(
		hold._sentence_remaining[captive],
		hold.sentence_length - 1.0,
		0.001,
		"the prisoner's term carries on where it was"
	)


func test_evacuating_only_captives_releases_nobody():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison as Garrison
	var captive: Actor = _entity(TERRESTRIAL, 0)
	hold.garrison(captive)
	hold.evacuate_by_order(null)
	assert_eq(hold.garrisoned_count(), 1)
	assert_true(hold._sentence_remaining.has(captive), "and its sentence is still running")


## The half a release must NOT do. Sentencing is the Compound's act, reached only through a
## DEPOSIT interaction, so a captive let out in the field goes back as itself.
func test_a_released_captive_is_not_sentenced():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var cage: Garrison = truck.garrison as Garrison
	assert_eq(cage.sentence_length, 0.0, "the cage sentences nothing")
	assert_false(cage.can_intern(), "only a Compound does that")


## Exit is its own statement, so it can be shut without shutting entry.
func test_a_garrison_can_be_authored_shut_in_the_exit_direction():
	var g: Garrison = _garrison(4)
	assert_true(g.can_release(), "an ordinary garrison lets its occupants out")
	g.releasable = false
	assert_false(g.can_release())
	assert_false(g.is_closed(), "which says nothing about who may enter")


func test_evacuate_is_allowed_for_an_open_garrison():
	var mercury: Actor = _entity(MERCURY, 1)
	assert_eq(
		Evacuate.meets_precondition(mercury, _message_for(null)),
		MoveCommand.PreconditionFailureCause.NONE,
		"a transport can still be told to unload"
	)


func test_nobody_may_be_ordered_into_a_compound():
	# Sentences reworked the camp back into a closed hold (2026-09-17): a captive is held as
	# itself, never converted into a Servant that could walk back out, so deposit is the only
	# way in for anyone — Servant and Recruit alike. See colonial-dominion.md §A captive
	# serves a sentence.
	var servant: Actor = _entity(SERVANT, 1)
	var recruit: Actor = _entity(RECRUIT, 1)
	var compound: Actor = _entity(COMPOUND, 1)
	assert_eq(
		Occupy.meets_precondition(servant, _message_for(compound)),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"not even the Compound's own commander's Servants"
	)
	assert_eq(
		Occupy.meets_precondition(recruit, _message_for(compound)),
		MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
		"nor anyone else"
	)
	assert_eq(
		Evacuate.meets_precondition(compound, _message_for(null)),
		MoveCommand.PreconditionFailureCause.NONE,
		"but the compound can still be told to let its own side out early"
	)


## --- Capture fills the cage ------------------------------------------------
## Who is capturable, and the contact that does it, live in test_CaptureByCrushing.gd; what
## is pinned here is the CAGE side — a closed hold filling up regardless of its own masks.


func test_capture_applies_while_the_cage_has_room():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	assert_true(
		Garrison.can_capture(truck, _entity(TERRESTRIAL, 0)), "an empty truck can take a prisoner"
	)


func test_capture_stops_applying_once_the_cage_is_full():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var cage: Garrison = truck.garrison
	for _i in range(cage.capacity):
		cage.garrison(_entity(TERRESTRIAL, 0))
	assert_eq(cage.garrisoned_count(), 3, "the cage holds its three")
	assert_false(
		Garrison.can_capture(truck, _entity(TERRESTRIAL, 0)), "a full truck can't take another"
	)


func test_a_captured_unit_leaves_the_world_but_stays_alive():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	truck.garrison.garrison(captive)
	assert_false(captive.is_inside_tree(), "the prisoner is out of the scene tree")
	assert_true(is_instance_valid(captive), "but not freed")
	assert_eq(truck.garrison.occupants(), [captive] as Array[Actor])


## --- Deposit moves the truck's captives into the compound, unconverted ----------


## A captor loaded with `a_count` neutral terrestrials.
func _loaded_truck(a_count: int) -> Actor:
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	for _i in range(a_count):
		truck.garrison.garrison(_entity(TERRESTRIAL, 0))
	return truck


func test_deposit_moves_prisoners_into_the_compound_unconverted():
	var truck: Actor = _loaded_truck(2)
	var captives: Array[Actor] = truck.garrison.occupants().duplicate()
	var compound: Actor = _entity(COMPOUND, 2)
	assert_eq(compound.garrison.deposit_from(truck.garrison), 2, "both captives are moved")
	assert_eq(truck.garrison.garrisoned_count(), 0, "the truck is empty again")
	assert_eq(compound.garrison.garrisoned_count(), 2, "the compound holds two")
	assert_eq(
		compound.garrison.occupants(), captives, "the SAME units — a transfer, not a conversion"
	)
	for occupant: Actor in compound.garrison.occupants():
		assert_eq(
			occupant.id,
			TERRESTRIAL.get("id", &"fake_unit"),
			"each stays what it was; the Compound no longer produces Servants"
		)
		assert_eq(
			occupant.commander.id,
			0,
			"ownership is untouched — still the side it was taken from, not the depositor's"
		)


func test_a_deposit_takes_the_servants_riding_along_and_sentences_them():
	var truck: Actor = _loaded_truck(1)
	var servant: Actor = _entity(SERVANT, 1)
	truck.garrison.garrison(servant)
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	assert_eq(hold.deposit_from(truck.garrison), 2, "the prisoner and the Servant")
	assert_true(servant in hold.occupants())
	assert_almost_eq(
		hold._sentence_remaining[servant],
		hold.sentence_length,
		0.001,
		"a Servant serves a sentence like a prisoner"
	)
	# Its turn comes after the prisoner's: one term, then a tick to start its own, then that.
	hold._physics_process(hold.sentence_length + 1.0)
	hold._physics_process(hold.sentence_length + 1.0)
	assert_false(is_instance_valid(servant), "and is consumed at the end of it")


func test_a_deposited_captive_serves_a_sentence():
	var truck: Actor = _loaded_truck(1)
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	hold.deposit_from(truck.garrison)
	var captive: Actor = hold.occupants()[0]
	assert_almost_eq(
		hold._sentence_remaining[captive],
		hold.sentence_length,
		0.001,
		"the term starts fresh on arrival"
	)


func test_a_finished_sentence_consumes_the_captive():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	hold.sentence_length = 1.0
	var captive: Actor = _entity(TERRESTRIAL, 0)
	hold.garrison(captive)
	hold._physics_process(1.5)
	assert_eq(hold.garrisoned_count(), 0, "the term is up — the captive leaves the hold")
	assert_false(is_instance_valid(captive), "and is consumed, not returned to the world")


func test_a_sentence_not_yet_finished_survives_a_tick():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	hold.sentence_length = 10.0
	var captive: Actor = _entity(TERRESTRIAL, 0)
	hold.garrison(captive)
	hold._physics_process(1.0)
	assert_eq(hold.garrisoned_count(), 1, "nine seconds still to serve")
	assert_true(is_instance_valid(captive))


func test_internment_is_partial_when_the_camp_is_nearly_full():
	var truck: Actor = _loaded_truck(2)
	var compound: Actor = _entity(COMPOUND, 1)
	compound.garrison.capacity = 1
	assert_eq(compound.garrison.deposit_from(truck.garrison), 1, "only what fits is taken")
	assert_eq(truck.garrison.garrisoned_count(), 1, "the truck keeps the rest")


func test_captives_serve_one_at_a_time_in_arrival_order():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	hold.sentence_length = 10.0
	var first: Actor = _entity(TERRESTRIAL, 0)
	var second: Actor = _entity(TERRESTRIAL, 0)
	hold.garrison(first)
	hold.garrison(second)
	hold._physics_process(4.0)
	assert_almost_eq(hold._sentence_remaining[first], 6.0, 0.001, "the first serves")
	assert_almost_eq(hold._sentence_remaining[second], 10.0, 0.001, "the second waits, untouched")
	hold._physics_process(7.0)
	assert_false(is_instance_valid(first), "the first is consumed at the end of its term")
	assert_almost_eq(
		hold._sentence_remaining[second], 10.0, 0.001, "the next term starts on the next tick"
	)
	hold._physics_process(1.0)
	assert_almost_eq(hold._sentence_remaining[second], 9.0, 0.001, "and then it serves")


func test_only_the_captive_serving_pays():
	var compound: Actor = _entity(COMPOUND, 1)
	var hold: Garrison = compound.garrison
	assert_eq(hold.paying_count(), 0, "an empty prison pays for nobody")
	hold.garrison(_entity(TERRESTRIAL, 0))
	hold.garrison(_entity(TERRESTRIAL, 0))
	hold.garrison(_entity(TERRESTRIAL, 0))
	assert_eq(hold.garrisoned_count(), 3)
	assert_eq(hold.paying_count(), Garrison.SENTENCES_AT_ONCE, "the rest wait their turn unpaid")


func test_an_ordinary_garrison_pays_for_every_occupant():
	var host: Actor = _entity(OPEN_GARRISON, 1)
	var garrison: Garrison = host.get_node("Garrison") as Garrison
	garrison.garrison(_entity(SERVANT, 1))
	garrison.garrison(_entity(SERVANT, 1))
	assert_eq(garrison.paying_count(), 2, "no sentences, so no queue")


func test_a_garrison_with_no_sentence_length_takes_no_deposit():
	var truck: Actor = _loaded_truck(1)
	var shelter: Actor = _entity(OPEN_GARRISON, 1)
	assert_false(
		(shelter.get_node("Garrison") as Garrison).can_intern(),
		"an ordinary garrison is shelter, not a camp"
	)
	assert_eq(
		(shelter.get_node("Garrison") as Garrison).deposit_from(truck.garrison),
		0,
		"and it takes nothing"
	)
	assert_eq(truck.garrison.garrisoned_count(), 1, "the truck still has its captive")


func test_deposit_applies_to_a_camp_and_not_to_a_safehouse():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	truck.garrison.garrison(_entity(TERRESTRIAL, 0))
	var compound: Actor = _entity(COMPOUND, 1)
	var resolved: Interaction = truck.interactor.applicable_interaction(
		truck, _message_for(compound)
	)
	assert_not_null(resolved, "a loaded truck can deposit at a compound")
	assert_eq(resolved.type, Interaction.Type.DEPOSIT)
	# An ordinary building is a garrison too, but one that interns nothing — it is shelter
	# for your own units, not a camp, so prisoners are never dropped off there.
	assert_null(
		truck.interactor.applicable_interaction(truck, _message_for(_entity(OPEN_GARRISON, 1))),
		"an open garrison is not a deposit target"
	)


func test_deposit_does_not_apply_to_an_empty_truck():
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	assert_null(
		truck.interactor.applicable_interaction(truck, _message_for(_entity(COMPOUND, 1))),
		"there is nothing to deposit"
	)


## --- Release ---------------------------------------------------------------


func test_destroying_the_holder_returns_prisoners_to_their_own_commander():
	# The release path a destroyed truck / compound takes (Actor._on_death →
	# Garrison.evacuate). No Map is stood up, which evacuate tolerates: the evacuees are
	# placed on a fallback ring and issued no follow-up commands.
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	var captor_commander: Commander = truck.commander
	var captive_commander: Commander = captive.commander
	truck.garrison.garrison(captive)
	truck.garrison.evacuate(null)
	assert_eq(
		captive.get_parent(),
		captive_commander,
		"a released prisoner goes back to its OWN commander, not its captor's"
	)
	assert_ne(captive.get_parent(), captor_commander)
	assert_eq(truck.garrison.garrisoned_count(), 0, "the cage is empty")


func test_a_prisoner_is_freed_when_it_has_no_commander_to_return_to():
	# A captive whose commander is gone can't be returned to the world; it must be freed
	# rather than left an orphan (what the old Inventory eject did).
	var truck: Actor = _entity(SUPPLY_TRUCK, 1)
	var captive: Actor = _entity(TERRESTRIAL, 0)
	truck.garrison.garrison(captive)
	captive.ownership.commander = null
	truck.garrison.evacuate(null)
	assert_false(is_instance_valid(captive), "the prisoner is freed, not orphaned")


func test_a_destroyed_camp_releases_its_prisoners_to_the_world():
	# The STRUCTURE release path (Garrison._evacuate_from_structure), which a destroyed
	# Compound takes — distinct from the unit path a destroyed truck takes, since a
	# structure seeds placement off its footprint. Run without a Map, which that path
	# tolerates: it anchors on the host and places the evacuees on the fallback ring.
	var compound: Actor = _entity(COMPOUND, 2)
	assert_true(compound.is_in_group("structure"), "the compound takes the structure release path")
	var captive_a: Actor = _entity(TERRESTRIAL, 1)
	var captive_b: Actor = _entity(TERRESTRIAL, 1)
	compound.garrison.garrison(captive_a)
	compound.garrison.garrison(captive_b)

	compound.garrison.evacuate(null)

	assert_eq(compound.garrison.garrisoned_count(), 0, "the compound is empty")
	assert_true(captive_a.is_inside_tree(), "the prisoner is back in the world")
	assert_eq(captive_a.get_parent(), captive_a.commander, "under its own commander")
	assert_true(captive_b.is_inside_tree())
	assert_eq(captive_b.get_parent(), captive_b.commander)


## --- Starting loads authored in the editor ----------------------------------


## A Map that answers placement queries without a navmesh (see test_PlannedStructures for
## the same idea): enough for Garrison's evacuation and for EventSpawnEntities to run.
class StubMap:
	extends Map

	func _ready() -> void:
		pass

	func grid_to_world(a_cell: Vector2i) -> Vector3:
		return Vector3(a_cell.x, 0.0, a_cell.y)

	func grid_coordinates_in_bounds(a_coords: Vector2i) -> bool:
		return a_coords.x >= 0 and a_coords.x < 17 and a_coords.y >= 0 and a_coords.y < 17

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


## A Scenario that skips its heavy boot; the manager only needs it for `map` and for
## get_commander() to resolve ids against `commanders`.
class StubScenario:
	extends Scenario

	func _ready() -> void:
		pass


## Map resolves its terrain collider and nav region through @onready node paths on tree
## entry, so the stub carries those children plus a heightmap (same rig as
## test_PlannedStructures). No navmesh is baked — spawning into a garrison never touches it.
func _stub_map() -> StubMap:
	var stub := StubMap.new()
	stub.name = "Map"
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	stub.add_child(region)
	var heights := HeightMapShape3D.new()
	heights.map_width = 17
	heights.map_depth = 17
	stub.height_map = heights
	return stub


func test_an_event_authored_under_a_host_loads_its_garrison_at_scenario_start():
	# What scene authoring looks like for a starting load: an EventSpawnEntities dropped
	# straight under the host (garrison_host = "..") — no trigger, no condition. The
	# manager runs it once at scenario start (ScenarioTriggerManager.run_starting_events).
	var scenario: StubScenario = StubScenario.new()
	var map: StubMap = _stub_map()
	scenario.add_child(map)
	var prisoner_commander: Commander = Commander.new()
	prisoner_commander.id = 1
	scenario.add_child(prisoner_commander)
	var camp_commander: Commander = Commander.new()
	camp_commander.id = 2
	scenario.add_child(camp_commander)
	scenario.commanders = [prisoner_commander, camp_commander]
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	scenario.add_child(manager)
	add_child_autofree(scenario)

	var compound: Actor = FakePieces.make(COMPOUND)
	camp_commander.add_child(compound)
	compound.map = map
	compound.ownership.commander = camp_commander

	var event := EventSpawnEntities.new()
	event.commander_id = prisoner_commander.id
	event.entity_scenes = [FakePieces.scene_of(TERRESTRIAL)]
	event.count = 3
	event.garrison_host = compound
	compound.add_child(event)

	manager.run_starting_events()

	assert_eq(
		compound.garrison.garrisoned_count(), 3, "the authored units start inside the compound"
	)
	for occupant: Actor in compound.garrison.occupants():
		assert_eq(
			occupant.commander,
			prisoner_commander,
			"each is owned by the event's commander, not the compound's"
		)
		assert_false(occupant.is_inside_tree(), "and is held out of the world")


func test_a_starting_event_under_a_host_is_not_run_twice():
	# Guards the double-spawn: the pass is a one-time scenario-start step, so a second
	# call is only ever the test's own — but the count must still be what was authored.
	var scenario: StubScenario = StubScenario.new()
	var map: StubMap = _stub_map()
	scenario.add_child(map)
	var commander: Commander = Commander.new()
	commander.id = 1
	scenario.add_child(commander)
	scenario.commanders = [commander]
	var manager := ScenarioTriggerManager.new()
	manager.name = "ScenarioTriggerManager"
	scenario.add_child(manager)
	add_child_autofree(scenario)

	var truck: Actor = FakePieces.make(SUPPLY_TRUCK)
	commander.add_child(truck)
	truck.map = map
	truck.ownership.commander = commander

	var event := EventSpawnEntities.new()
	event.commander_id = commander.id
	event.entity_scenes = [FakePieces.scene_of(TERRESTRIAL)]
	event.count = 2
	event.garrison_host = truck
	truck.add_child(event)

	manager.run_starting_events()
	assert_eq(truck.garrison.garrisoned_count(), 2, "the authored load, once")


## --- Dominion per prisoner -------------------------------------------------


func test_the_camp_banks_dominion_for_the_prisoner_serving():
	var compound: Actor = _entity(COMPOUND, 1)
	var generator: OccupantDominionGenerator = compound.get_node("DominionGenerator")
	compound.garrison.garrison(_entity(TERRESTRIAL, 0))
	compound.garrison.garrison(_entity(TERRESTRIAL, 0))
	var before: int = compound.commander.dominion
	generator.ticks_elapsed = DominionGenerator.TICK_RATE - 1
	generator.tick()
	assert_eq(
		compound.commander.dominion - before,
		Garrison.SENTENCES_AT_ONCE * generator.dominion_per_unit,
		"the prisoner serving banks its dominion; the one waiting its turn banks nothing"
	)


func test_an_empty_camp_banks_nothing():
	var compound: Actor = _entity(COMPOUND, 1)
	var generator: OccupantDominionGenerator = compound.get_node("DominionGenerator")
	var before: int = compound.commander.dominion
	generator.ticks_elapsed = DominionGenerator.TICK_RATE - 1
	generator.tick()
	assert_eq(compound.commander.dominion, before, "no prisoners, no dominion")


## A held unit is off the tree and has no position of its own; where it is in the world is its
## host's — what a waypoint line starts from.
func test_a_held_unit_is_where_its_host_is():
	var host: Actor = _entity(OPEN_GARRISON, 1)
	host.global_position = Vector3(7.0, 0.0, 3.0)
	var soldier: Actor = _entity(RECRUIT, 1)
	soldier.global_position = Vector3(1.0, 0.0, 1.0)
	assert_eq(soldier.world_position(), Vector3(1.0, 0.0, 1.0), "standing, it is where it is")
	host.get_node("Garrison").garrison(soldier)
	assert_true(soldier.is_garrisoned())
	assert_eq(soldier.world_position(), host.global_position, "held, it is where its host is")
