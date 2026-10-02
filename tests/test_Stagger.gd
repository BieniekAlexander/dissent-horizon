extends GutTest

## Tests for the stagger mechanic: taking damage staggers a unit, which suppresses
## certain channeled actions (Build, Assemble, Repair, Plant, HIJACK interactions — but NOT
## DEPOSIT)
## until the stagger wears off. Movement and most actions are never blocked.
##
## The per-command "is this action stagger-blocked?" rules are pure logic, so these
## drive the command / interaction classes directly without standing up a scene.

## --- Which interaction types are stagger-blocked -----------------------------
## The allow-set is the core spec: HIJACK waits out a stagger; DEPOSIT proceeds
## regardless.


func _interaction(a_type: Interaction.Type) -> Interaction:
	var ix := Interaction.new()
	ix.type = a_type
	return ix


func test_plant_is_blocked_while_staggered():
	var plant := Plant.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	assert_true(plant.blocked_by_stagger(null))


func test_hijack_is_blocked_while_staggered():
	assert_true(_interaction(Interaction.Type.HIJACK).blocks_while_staggered())


func test_deposit_is_not_blocked_while_staggered():
	assert_false(_interaction(Interaction.Type.DEPOSIT).blocks_while_staggered())


## --- Which commands opt into stagger blocking --------------------------------


func _message() -> CommandMessage:
	return CommandMessage.new(null, null)


func test_plain_move_is_not_blocked_by_stagger():
	# The default: most actions ignore stagger.
	assert_false(MoveCommand.new(_message()).blocked_by_stagger(null))


func test_build_is_blocked_by_stagger():
	assert_true(Build.new(_message()).blocked_by_stagger(null))


func test_assemble_is_blocked_by_stagger():
	assert_true(Assemble.new(_message()).blocked_by_stagger(null))


func test_repair_is_blocked_by_stagger():
	assert_true(Repair.new(_message()).blocked_by_stagger(null))


## Interact itself has no fixed answer — it defers to the resolved interaction's
## blocks_while_staggered (see the Interaction.Type tests above), so a staggered actor
## waits out a HIJACK but proceeds with a DEPOSIT.

## --- A staggered piece cannot be healed --------------------------------------
## Enforced on Defense.restore, the one door every mender goes through, so the Repair
## command and the heal aura cannot disagree. Construction is NOT healing and is not
## affected — advance_build_progress writes hp directly.


func _wounded_patient() -> Commandable:
	var patient: Commandable = FakePieces.unit({"hp": 80.0})
	add_child_autofree(patient)
	patient.defense.hp = patient.defense.hp_max * 0.5
	return patient


func test_restore_is_refused_while_staggered():
	var patient := _wounded_patient()
	patient.receive_damage(Damage.new(1.0))
	assert_true(patient.is_staggered(), "the hit staggered it")
	var after_hit: float = patient.defense.hp
	assert_false(patient.defense.restore(10.0), "reports not-full, so a mender stands by")
	assert_almost_eq(patient.defense.hp, after_hit, 0.001, "no hp was restored")


func test_restore_resumes_once_the_stagger_wears_off():
	# Cleared directly rather than by ticking out STAGGER_SECONDS of physics: the countdown
	# itself is Commandable's, and what is under test here is the gate on restore.
	var patient := _wounded_patient()
	patient.receive_damage(Damage.new(1.0))
	patient._stagger_ticks = 0
	assert_false(patient.is_staggered(), "the stagger has worn off")
	var before: float = patient.defense.hp
	patient.defense.restore(10.0)
	assert_almost_eq(patient.defense.hp, before + 10.0, 0.001, "mending resumes")
