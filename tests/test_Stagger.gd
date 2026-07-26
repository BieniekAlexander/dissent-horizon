extends GutTest

## Tests for the stagger mechanic: taking damage staggers a unit, which suppresses
## certain channeled actions (Build, Repair, LIBERATE/PLANT interactions — but NOT
## ABDUCT) until the stagger wears off. Movement and most actions are never blocked.
##
## The per-command "is this action stagger-blocked?" rules are pure logic, so these
## drive the command / interaction classes directly without standing up a scene.

## --- Which interaction types are stagger-blocked -----------------------------
## The allow-set is the core spec: LIBERATE and PLANT wait out a stagger; the others
## (ABDUCT, COLLECT, DEPOSIT) proceed regardless.

func _interaction(a_type: Interaction.Type) -> Interaction:
	var ix := Interaction.new()
	ix.type = a_type
	return ix

func test_liberate_is_blocked_while_staggered():
	assert_true(_interaction(Interaction.Type.LIBERATE).blocks_while_staggered())

func test_plant_is_blocked_while_staggered():
	assert_true(_interaction(Interaction.Type.PLANT).blocks_while_staggered())

func test_abduct_is_not_blocked_while_staggered():
	assert_false(_interaction(Interaction.Type.ABDUCT).blocks_while_staggered())

func test_collect_and_deposit_are_not_blocked_while_staggered():
	assert_false(_interaction(Interaction.Type.COLLECT).blocks_while_staggered())
	assert_false(_interaction(Interaction.Type.DEPOSIT).blocks_while_staggered())

## --- Which commands opt into stagger blocking --------------------------------

func _message() -> CommandMessage:
	return CommandMessage.new(null, null)

func test_plain_move_is_not_blocked_by_stagger():
	# The default: most actions ignore stagger.
	assert_false(MoveCommand.new(_message()).blocked_by_stagger(null))

func test_build_is_blocked_by_stagger():
	assert_true(Build.new(_message()).blocked_by_stagger(null))

func test_repair_is_blocked_by_stagger():
	assert_true(Repair.new(_message()).blocked_by_stagger(null))

## Interact itself has no fixed answer — it defers to the resolved interaction's
## blocks_while_staggered (see the Interaction.Type tests above), so a staggered actor
## waits out a LIBERATE/PLANT but proceeds with an ABDUCT.
