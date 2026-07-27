extends GutTest

## HIJACK — the Hijacker's whole kit. Walk up to a MECH-frame UNIT, work on it, and it
## changes hands to the hijacker's commander while the hijacker itself is expended.
##
## Two halves, tested separately because they fail differently:
##   * APPLICABILITY — Interaction.Type.HIJACK's evaluator: which targets it accepts.
##     Pure logic over actor/target, so no Map is needed.
##   * COMPLETION — Interact._hijack: ownership moves, the prize's orders are dropped,
##     and the actor dies. Driven by calling _complete through fulfill_action.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HijackInteraction.gd -gexit

const HIJACKER := preload("res://scenes/entities/units/an/an_bioMedium_support.tscn")
## MECH unit.
const MATILDA := preload("res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn")
## BIO unit.
const RECRUIT := preload("res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn")
const BUILDING := preload("res://scenes/entities/structures/nt/nt_building.tscn") # MECH structure

const OWNER: int = 1
const ENEMY: int = 2
const NEUTRAL: int = 0

func _commanded(a_id: int) -> Commander:
	var c := Commander.new()
	c.id = a_id
	add_child_autofree(c)
	return c

## A live entity owned by [a_commander_id]. Ownership is assigned directly rather than
## through initialize(), so no Map is needed — the fixture test_Interaction uses.
func _unit(a_scene: PackedScene, a_commander_id: int) -> Commandable:
	var u := a_scene.instantiate() as Commandable
	add_child_autofree(u)
	u.ownership.commander = _commanded(a_commander_id)
	return u

func _message_for(a_target: Entity) -> CommandMessage:
	return CommandMessage.new(null, a_target)

func _applies(a_actor: Commandable, a_target: Entity) -> bool:
	return a_actor.interactor != null \
		and a_actor.interactor.can_interact(a_actor, _message_for(a_target))

## --- The unit carries the interaction at all --------------------------------

func test_the_hijacker_has_a_hijack_interaction() -> void:
	var hijacker := _unit(HIJACKER, OWNER)
	assert_not_null(hijacker.interactor, "the Hijacker has an Interactor component")
	var types: Array = hijacker.interactor.interactions.map(func(i: Interaction): return i.type)
	assert_eq(types, [Interaction.Type.HIJACK], "carrying exactly the hijack interaction")

func test_its_reach_is_a_shape_not_a_touch() -> void:
	# A HIJACK target MOVES, and RVO keeps bodies apart — with the default near-touch
	# reach the hijacker would chase a tank forever without ever arriving. Same reason
	# ABDUCT carries one.
	var hijacker := _unit(HIJACKER, OWNER)
	assert_not_null(hijacker.interactor.interactions[0].interact_shape,
		"hijack declares an interact_shape")

## --- Applicability ----------------------------------------------------------

func test_applies_to_an_enemy_mech_unit() -> void:
	assert_true(_applies(_unit(HIJACKER, OWNER), _unit(MATILDA, ENEMY)))

func test_applies_to_a_neutral_mech_unit() -> void:
	# Non-friendly rather than enemy-only, matching ABDUCT: a derelict is a fair prize.
	assert_true(_applies(_unit(HIJACKER, OWNER), _unit(MATILDA, NEUTRAL)))

func test_does_not_apply_to_a_friendly_mech_unit() -> void:
	assert_false(_applies(_unit(HIJACKER, OWNER), _unit(MATILDA, OWNER)))

func test_does_not_apply_to_a_biological_unit() -> void:
	# The frame axis is the whole point: ABDUCT takes the crew, HIJACK takes the machine.
	assert_false(_applies(_unit(HIJACKER, OWNER), _unit(RECRUIT, ENEMY)))

func test_does_not_apply_to_a_structure() -> void:
	# Even a MECH-frame one. A building changing hands is Capture's job, with completely
	# different bookkeeping (structure registry, infrastructure, terrain grid).
	var building := _unit(BUILDING, ENEMY)
	assert_eq(building.defense.frame_type, Defense.FrameType.MECH,
		"precondition: the building really is MECH-framed, so only the structure rule excludes it")
	assert_false(_applies(_unit(HIJACKER, OWNER), building))

## --- Completion -------------------------------------------------------------

## Run the interaction to completion: fulfill_action accrues one tick per call and fires
## the effect once required_ticks is reached.
func _run_to_completion(a_actor: Commandable, a_target: Entity) -> void:
	var command := Interact.new(_message_for(a_target))
	var interaction: Interaction = a_actor.interactor.applicable_interaction(a_actor, command.message)
	var budget: int = int(interaction.required_ticks(a_target)) + 2
	for i in budget:
		if command.fulfill_action(a_actor) == null:
			return
	fail_test("the hijack never completed within %d ticks" % budget)

func test_the_prize_changes_hands() -> void:
	var hijacker := _unit(HIJACKER, OWNER)
	var prize := _unit(MATILDA, ENEMY)
	_run_to_completion(hijacker, prize)
	assert_eq(prize.commander_id, OWNER, "the vehicle now belongs to the hijacker's commander")

func test_the_hijacker_is_expended() -> void:
	var hijacker := _unit(HIJACKER, OWNER)
	_run_to_completion(hijacker, _unit(MATILDA, ENEMY))
	assert_eq(hijacker.defense.hp, 0.0,
		"the hijacker is dropped to 0 hp, so the normal death path tears it down")

func test_the_prize_loses_its_old_orders() -> void:
	# A hijacked tank that kept its previous owner's attack order would immediately turn
	# on its new owner.
	var hijacker := _unit(HIJACKER, OWNER)
	var prize := _unit(MATILDA, ENEMY)
	prize.update_commands(MoveCommand.new(CommandMessage.new(null, null)))
	assert_true(prize.has_command(), "precondition: the prize is under orders")
	_run_to_completion(hijacker, prize)
	assert_false(prize.has_command(), "its old owner's orders are dropped")

func test_completion_is_a_no_op_when_the_prize_died_first() -> void:
	# fulfill_action can land on a target destroyed during the 1.5s channel.
	var hijacker := _unit(HIJACKER, OWNER)
	var prize := _unit(MATILDA, ENEMY)
	var command := Interact.new(_message_for(prize))
	prize.free()
	command._hijack(hijacker)   # must not crash on a freed target
	assert_gt(hijacker.defense.hp, 0.0, "and the hijacker is not spent on a failed attempt")

## --- Stagger ----------------------------------------------------------------

func test_hijacking_is_blocked_by_stagger() -> void:
	# Channeled and vulnerable, like Plant: a hijacker under fire holds at the vehicle
	# instead of completing, so shooting it is the counterplay.
	var hijacker := _unit(HIJACKER, OWNER)
	assert_true(hijacker.interactor.interactions[0].blocks_while_staggered())
