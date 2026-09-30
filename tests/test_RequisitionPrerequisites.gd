extends GutTest

## Requisition mode and a missing PREREQUISITE.
##
## The mode was built so a player can commit to something they cannot pay for yet. The
## same argument applies to tech: in most RTS games you may not order a building until its
## prerequisite stands, which means watching the prerequisite finish and only then
## clicking. With requisition on, you can order the downstream building while its
## dependency is still going up, and the builder waits at the site.
##
## The distinction the whole feature turns on: "I have not built the war factory" is a
## REFUSAL; "the war factory is going up right now" is a QUEUE. Without that line a player
## could order the entire tech tree from an empty base.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_RequisitionPrerequisites.gd -gexit

## A fake tech tree: DOWNSTREAM requires PREREQUISITE, and a three-deep chain A <- B <- C.
const DOWNSTREAM: StringName = &"fake_downstream"
const PREREQUISITE: StringName = &"fake_prerequisite"

var _commander: Commander


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)
	_commander.add_energy(100000)
	_commander.set_physics_process(false)
	_commander.technology_mapping = {
		PREREQUISITE: FakePieces.tech(), DOWNSTREAM: FakePieces.tech(0, 0, 0, 30, [PREREQUISITE]),
		CHAIN_B: FakePieces.tech(0, 0, 0, 30, [CHAIN_A]),
		CHAIN_C: FakePieces.tech(0, 0, 0, 30, [CHAIN_B])}
	_commander.proc_technology()


## A war factory owned by the commander, either finished or still going up.
func _prerequisite(a_built: bool) -> Commandable:
	var structure: Commandable = FakePieces.structure({"id": PREREQUISITE})
	_commander.add_child(structure)
	autofree(structure)
	structure.ownership.commander = _commander
	structure.build_progress = 1.0 if a_built else Commandable.INITIAL_BUILD_PROGRESS
	_commander.add_structure(structure)
	_commander.proc_technology()
	return structure


## A queued purchase for the prerequisite piece, of the given kind.
func _queued(a_kind: PurchaseTransaction.Kind) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.new()
	transaction.commander = _commander
	transaction.kind = a_kind
	transaction.type = PREREQUISITE
	return transaction


# --- The tech gate itself ---------------------------------------------------------

func test_the_downstream_piece_requires_the_prerequisite() -> void:
	# Guards the fixture: if the roster ever drops this dependency these tests say nothing.
	assert_true(_commander.technology_mapping[DOWNSTREAM].required_structures.has(PREREQUISITE))


func test_with_nothing_built_the_order_is_refused() -> void:
	# Even in requisition mode. Nothing is on its way, so waiting cannot resolve it.
	assert_eq(_commander.get_blocking_need(DOWNSTREAM, true),
		TechnologySpec.UnmetNeed.MISSING_STRUCTURE)
	assert_false(_commander.missing_prerequisites_are_incoming(DOWNSTREAM))


func test_with_the_prerequisite_built_the_order_is_legal() -> void:
	_prerequisite(true)
	assert_eq(_commander.get_blocking_need(DOWNSTREAM, true),
		TechnologySpec.UnmetNeed.NONE)


# --- The feature ------------------------------------------------------------------

func test_a_prerequisite_under_construction_counts_as_incoming() -> void:
	_prerequisite(false)
	assert_true(_commander.has_incoming_structure(PREREQUISITE))
	assert_true(_commander.missing_prerequisites_are_incoming(DOWNSTREAM))


func test_requisition_lets_the_downstream_order_through() -> void:
	_prerequisite(false)
	assert_eq(_commander.get_blocking_need(DOWNSTREAM, true),
		TechnologySpec.UnmetNeed.NONE, "queued, because the dependency is on its way")


func test_without_requisition_it_is_still_refused() -> void:
	# allow_deferral false is what the controller passes with the mode OFF. The prerequisite
	# being on its way changes nothing: the player has not asked to commit ahead.
	_prerequisite(false)
	assert_eq(_commander.get_blocking_need(DOWNSTREAM, false),
		TechnologySpec.UnmetNeed.MISSING_STRUCTURE)


func test_a_finished_prerequisite_is_not_incoming() -> void:
	# "Incoming" means still on its way. A finished one satisfies the gate outright, and
	# reporting it as incoming would blur the two.
	_prerequisite(true)
	assert_false(_commander.has_incoming_structure(PREREQUISITE))


func test_every_missing_prerequisite_must_be_incoming() -> void:
	# All, not any: a piece waiting on two buildings is only on its way once both are.
	# Faked by adding a second requirement nothing is building.
	_prerequisite(false)
	_commander.technology_mapping[DOWNSTREAM].required_structures = \
		[PREREQUISITE, &"fake_never_built"]
	assert_false(_commander.missing_prerequisites_are_incoming(DOWNSTREAM),
		"one of the two is not coming, so the order would strand its builder")


# --- The queue counts too ---------------------------------------------------------

func test_a_queued_build_purchase_counts_as_incoming() -> void:
	# A build is committed the moment it is ordered. In practice its blueprint exists from
	# that instant; the queue scan is what keeps this honest before one is raised.
	_commander.production_queue.entries.append(_queued(PurchaseTransaction.Kind.BUILD))
	assert_true(_commander.production_queue.has_pending_build(PREREQUISITE))
	assert_true(_commander.has_incoming_structure(PREREQUISITE))


func test_a_queued_TRAIN_purchase_does_not_count() -> void:
	# Only a build puts a structure on the field.
	_commander.production_queue.entries.append(_queued(PurchaseTransaction.Kind.TRAIN))
	assert_false(_commander.production_queue.has_pending_build(PREREQUISITE))


# --- CHAINED prerequisites ---------------------------------------------------------
##
## A ← B ← C. Ordering A then B works because A is registered the moment a builder lays its
## foundation; ordering C after B did NOT, and that is the regression these pin.
##
## A BLUEPRINT is the state the chain broke in. A structure that is merely PLANNED is
## deliberately kept out of the commander's structure registry (it contributes no infrastructure and
## is not a building the tech tree counts), and its purchase leaves the production queue the
## moment it is FUNDED — which for an affordable order is immediately. So between "ordered"
## and "a builder has walked over and laid it", B was on its way by every ordinary meaning
## of the words and invisible to both of the checks that existed.

const CHAIN_A: StringName = PREREQUISITE
const CHAIN_B: StringName = &"fake_chain_b"        # requires A
const CHAIN_C: StringName = &"fake_chain_c"        # requires B


## A BLUEPRINT of `a_id`: ordered and standing on its site, with no foundation laid.
## plan_construction() runs before ownership for the reason Build.plan_structure documents —
## _on_commander_changed reads is_planned to decide what registration to skip.
func _blueprint(a_type: StringName) -> Commandable:
	var structure: Commandable = FakePieces.structure({"id": a_type})
	structure.plan_construction()
	_commander.add_child(structure)
	autofree(structure)
	structure.ownership.commander = _commander
	_commander.proc_technology()
	return structure


func test_the_chain_fixture_is_three_deep() -> void:
	# Guards the fixture: if the roster flattens this chain these tests say nothing.
	assert_true(_commander.technology_mapping[CHAIN_C].required_structures.has(CHAIN_B))
	assert_true(_commander.technology_mapping[CHAIN_B].required_structures.has(CHAIN_A))


func test_a_blueprint_counts_as_incoming() -> void:
	_blueprint(CHAIN_B)
	assert_true(_commander.has_planned_structure(CHAIN_B), "the blueprint is standing")
	assert_true(_commander.has_incoming_structure(CHAIN_B))


func test_a_blueprint_is_not_a_BUILT_structure() -> void:
	# The two must stay distinct: a blueprint satisfies "on its way", never "you have one".
	_blueprint(CHAIN_B)
	assert_false(_commander.has_built_structure(CHAIN_B))
	assert_eq(_commander.get_blocking_need(CHAIN_C, false),
		TechnologySpec.UnmetNeed.MISSING_STRUCTURE,
		"without requisition, a blueprint is still not a building")


func test_the_third_link_may_be_ordered_once_the_second_is() -> void:
	# The reported case: A under construction, B ordered (a blueprint, its purchase already
	# funded and gone from the queue), C refused.
	_prerequisite(false)
	_blueprint(CHAIN_B)
	assert_eq(_commander.get_blocking_need(CHAIN_C, true), TechnologySpec.UnmetNeed.NONE,
		"C is queued, because B is on its way")


func test_the_third_link_is_still_refused_when_the_second_was_never_ordered() -> void:
	# The line the whole feature turns on has to survive the fix: nothing incoming is a
	# refusal, however deep in the tree the request sits.
	_prerequisite(false)
	assert_eq(_commander.get_blocking_need(CHAIN_C, true),
		TechnologySpec.UnmetNeed.MISSING_STRUCTURE)
