extends GutTest

## What a structure that is still going up may and may not do.
##
## The rule, borrowed from how training already behaved: it EXISTS — selectable, orderable,
## a legal target — but it cannot ACT. Orders given while it builds are kept and carried
## out the moment it finishes, which is what makes "queue work at this building while it
## goes up" mean anything.
##
## The bug this was written for: an anti-aircraft turret shot down aircraft while it
## was still a 10%-health foundation.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_UnfinishedConstruction.gd
## -gexit

## A gun-carrying structure that sees.
const SAM: Dictionary = {"structure": true, "vision": 10.0, "weapon": {"air": 8.0}}


func _sam(a_built: bool) -> Actor:
	var turret: Actor = FakePieces.make(SAM)
	add_child_autofree(turret)
	turret.top_level = true
	turret.build_progress = 1.0 if a_built else Actor.INITIAL_BUILD_PROGRESS
	return turret


# --- is_built is the gate ---------------------------------------------------------


func test_a_structure_under_construction_is_not_built() -> void:
	assert_false(_sam(false).is_built)
	assert_true(_sam(true).is_built)


func test_a_unit_is_always_built() -> void:
	# is_built is group-keyed: only members of "structure" have construction to finish, so
	# the gate is inert for everything else — including a unit whose build_progress was
	# never touched.
	var unit: Actor = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(unit)
	assert_true(unit.is_built)


# --- It cannot see ----------------------------------------------------------------


func test_a_foundation_grants_no_vision() -> void:
	# A foundation is not a watchtower: fog and the commander's sight checks both ask this.
	assert_false(_sam(false).grants_vision())


func test_finishing_construction_turns_its_vision_on() -> void:
	var turret := _sam(false)
	turret.build_progress = 1.0
	assert_true(turret.grants_vision())


func test_a_commander_counts_only_finished_structures_as_eyes() -> void:
	var commander := Commander.new()
	add_child_autofree(commander)
	var foundation: Actor = FakePieces.make(SAM)
	foundation.build_progress = Actor.INITIAL_BUILD_PROGRESS
	commander.add_child(foundation)
	var finished: Actor = FakePieces.make(SAM)
	commander.add_child(finished)
	assert_false(foundation.grants_vision(), "a foundation is not a watchtower yet")
	assert_true(finished.grants_vision())


# --- It cannot act ----------------------------------------------------------------


func test_an_unfinished_structure_processes_no_commands() -> void:
	# The same total stop a stun applies, and for the same reason: no get_updated_state,
	# no can_act, no fulfill_action. A half-built SAM firing was the reported bug.
	var turret := _sam(false)
	var message := CommandMessage.new(null, null, null, Vector3(5.0, 0.0, 0.0))
	turret.update_commands(MoveCommand.new(message), false)
	turret._process_commands()
	assert_false(
		turret.command_receiver.is_idle(),
		"the order is HELD, not dropped — it runs when construction finishes"
	)


func test_a_finished_structure_processes_commands_again() -> void:
	var turret := _sam(true)
	assert_true(turret.is_built, "so the receiver's gate is open")


# --- It still accepts orders ------------------------------------------------------


func test_an_unfinished_structure_still_takes_orders() -> void:
	# The precedent this follows: a half-built barracks accepts training orders and works
	# through them once it is up. Every other command behaves the same way now.
	var turret := _sam(false)
	var message := CommandMessage.new(null, null, null, Vector3(5.0, 0.0, 0.0))
	turret.update_commands(MoveCommand.new(message), false)
	assert_true(
		turret.command_receiver.has_pending_work(),
		"the order is queued against the unfinished structure"
	)


# --- It cannot be entered ---------------------------------------------------------


func test_an_unfinished_garrison_admits_nobody() -> void:
	# A building still going up has no inside to stand in. Checked on the Garrison rather
	# than only in Occupy, so capture and deposit — which put units in WITHOUT consent —
	# agree with the command that asks.
	var host: Actor = FakePieces.structure({"garrison": {"capacity": 4}})
	add_child_autofree(host)
	var occupant: Actor = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(occupant)
	host.build_progress = Actor.INITIAL_BUILD_PROGRESS
	assert_false(host.garrison.admits(occupant), "not while it is a foundation")
	host.build_progress = 1.0
	assert_true(host.garrison.admits(occupant), "once it is up")


# --- It is not cover ---------------------------------------------------------------


func _hurtbox(a_turret: Actor) -> StaticBody3D:
	return a_turret.get_node_or_null("Hurtbox") as StaticBody3D


func test_a_foundation_is_shootable_but_is_not_cover() -> void:
	# A site with materials on it stops nothing: Attack's line-of-fire raycast queries
	# STRUCTURE_BLOCKER, and until the building is up there is nothing standing there for
	# a bullet to hit. It stays a legal TARGET, and it still holds its grid cells.
	var turret := _sam(false)
	turret._apply_targetable_layers()
	var body := _hurtbox(turret)
	assert_not_null(body, "the SAM has a Hurtbox to carry the layers")
	assert_eq(
		body.collision_layer & CollisionLayers.Mask.STRUCTURE_BLOCKER,
		0,
		"a foundation is not cover"
	)
	assert_ne(
		body.collision_layer & CollisionLayers.Mask.TARGETABLE_GROUND,
		0,
		"but it can still be shot at"
	)


func test_finishing_construction_makes_it_cover() -> void:
	# The layer is applied on the completing tick by advance_build_progress, so every
	# route that finishes a structure agrees rather than only the Assemble command.
	var turret := _sam(false)
	turret._apply_targetable_layers()
	assert_true(turret.advance_build_progress(1.0), "the completing tick")
	assert_ne(
		_hurtbox(turret).collision_layer & CollisionLayers.Mask.STRUCTURE_BLOCKER,
		0,
		"a finished building blocks line of fire"
	)


# --- Infrastructure follows FINISHING, not starting ---------------------------------
##
## The SAM costs 30 infrastructure upkeep once it is actually running
## (gdd/factions/colonial/structures/cl_defense_antiAircraft.md). A foundation draws no
## power yet, so it must not be charged for it — same "exists but does not act" idiom the
## rest of this file covers, applied to the economy rather than to commands.


func _owned_sam(a_built: bool, a_commander: Commander) -> Actor:
	var turret := _sam(a_built)
	turret.commander = a_commander
	return turret


func test_a_foundation_credits_no_infrastructure() -> void:
	var commander := autofree(Commander.new()) as Commander
	add_child_autofree(commander)
	var before: int = commander.infrastructure
	_owned_sam(false, commander)
	assert_eq(commander.infrastructure, before, "laying the foundation charges nothing yet")


func test_finishing_construction_credits_infrastructure() -> void:
	var commander := autofree(Commander.new()) as Commander
	add_child_autofree(commander)
	var turret := _owned_sam(false, commander)
	var before: int = commander.infrastructure
	assert_true(turret.advance_build_progress(1.0), "the completing tick")
	assert_eq(
		commander.infrastructure,
		before + turret.infrastructure,
		"credited exactly on the tick construction finishes, not before"
	)


func test_a_structure_placed_already_built_credits_infrastructure_immediately() -> void:
	# Editor-placed / scenario-authored structures default to build_progress = 1.0 and never
	# pass through commit_construction or advance_build_progress at all — they are already
	# working the moment they are owned, so is_built gates the credit correctly either way.
	var commander := autofree(Commander.new()) as Commander
	add_child_autofree(commander)
	var before: int = commander.infrastructure
	var turret := _owned_sam(true, commander)
	assert_eq(commander.infrastructure, before + turret.infrastructure)


func test_killing_an_unfinished_structure_refunds_nothing_it_was_never_charged() -> void:
	var commander := autofree(Commander.new()) as Commander
	add_child_autofree(commander)
	var turret := _owned_sam(false, commander)
	var before: int = commander.infrastructure
	turret._on_death()
	assert_eq(
		commander.infrastructure,
		before,
		"nothing was ever debited, so nothing should be credited back"
	)


func test_killing_a_finished_structure_returns_its_infrastructure() -> void:
	var commander := autofree(Commander.new()) as Commander
	add_child_autofree(commander)
	var turret := _owned_sam(true, commander)
	var before: int = commander.infrastructure
	turret._on_death()
	assert_eq(commander.infrastructure, before - turret.infrastructure)


func test_transferring_an_unfinished_structure_moves_no_infrastructure() -> void:
	var old_commander := autofree(Commander.new()) as Commander
	var new_commander := autofree(Commander.new()) as Commander
	add_child_autofree(old_commander)
	add_child_autofree(new_commander)
	var turret := _owned_sam(false, old_commander)
	var old_before: int = old_commander.infrastructure
	var new_before: int = new_commander.infrastructure
	turret.commander = new_commander
	assert_eq(old_commander.infrastructure, old_before, "never charged, so nothing to refund")
	assert_eq(new_commander.infrastructure, new_before, "not built yet, so nothing to charge")


func test_transferring_a_finished_structure_moves_its_infrastructure() -> void:
	var old_commander := autofree(Commander.new()) as Commander
	var new_commander := autofree(Commander.new()) as Commander
	add_child_autofree(old_commander)
	add_child_autofree(new_commander)
	var turret := _owned_sam(true, old_commander)
	var old_before: int = old_commander.infrastructure
	var new_before: int = new_commander.infrastructure
	turret.commander = new_commander
	assert_eq(old_commander.infrastructure, old_before - turret.infrastructure)
	assert_eq(new_commander.infrastructure, new_before + turret.infrastructure)


# --- It earns nothing -------------------------------------------------------------


## A flat DominionGenerator (the Technocratic Lab) used to tick from the moment its blueprint
## went down, earning through its whole construction. Income is gated on is_built, as the
## EnergyExtractor's always was.
func _generator_on(a_piece: Actor) -> DominionGenerator:
	var generator: DominionGenerator = DominionGenerator.new()
	generator.name = "DominionGenerator"
	a_piece.add_child(generator)
	a_piece.dominion_generator = generator
	return generator


func test_a_foundation_generates_no_dominion() -> void:
	var foundation: Actor = _sam(false)
	var generator: DominionGenerator = _generator_on(foundation)
	foundation.tick_collection()
	assert_eq(generator.ticks_elapsed, 0, "a structure still going up does not run its generator")


func test_a_finished_structure_runs_its_generator() -> void:
	var finished: Actor = _sam(true)
	var generator: DominionGenerator = _generator_on(finished)
	finished.tick_collection()
	assert_eq(generator.ticks_elapsed, 1, "the control: a built one does")
