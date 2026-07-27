extends GutTest

## Tests for the commander's global production queue — PurchaseTransaction plus
## ProductionQueue (scripts/interface/commander/).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProductionQueue.gd -gexit
##
## Everything here is built out of tree: a Commander that was never added to the scene
## (so no _ready / blackboard / faction setup runs) plus bare Commandables carrying a
## Production component. That's enough for the queue, which only ever touches
## commander.energy / .dominion and producer.production. Transactions are priced explicitly
## via PurchaseTransaction.for_cost so the tests don't depend on gdd-authored costs.
##
## The BUILD side's placement/refund path (a builder walking to the site, laying the
## foundation, being killed en route) needs a live map and navmesh; only its bookkeeping
## — funding, holder counting, refund on abandonment — is covered here.

const IRREGULAR: StringName = &"an_bioLight_builder"
const VANGUARD: StringName = &"tc_bioLight_antiMech"


func _make_commander(a_energy: int = 0) -> Commander:
	var commander := autofree(Commander.new()) as Commander
	commander.energy = a_energy
	return commander


## A stand-in production structure: an out-of-tree Commandable with a Production
## component wired to its `production` field directly (the @onready never resolves
## outside the tree). Not in the "structure" group, so is_built reads true.
func _make_producer(a_types: Array[StringName]) -> Commandable:
	var producer := autofree(Commandable.new()) as Commandable
	var production := Production.new()
	production.producible_types = a_types
	producer.add_child(production)
	producer.production = production
	return producer


## A producer that is still under construction: in the "structure" group (which is what
## makes is_built consult build_progress at all) with partial progress.
func _make_unbuilt_producer(a_types: Array[StringName]) -> Commandable:
	var producer := _make_producer(a_types)
	producer.add_to_group("structure")
	producer.build_progress = 0.4
	return producer


func _make_tool(a_type: StringName) -> Tool:
	return Tool.new("command_tool_%s" % a_type, a_type, null, str(a_type), Vector2i.ZERO, 0, 0)


## A TRAIN purchase at an explicit price, so tests don't ride on authored costs.
func _train_purchase(
	a_commander: Commander, a_type: StringName, a_energy: int, a_producers: Array, a_ticks: int = 10
) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.for_cost(
		a_commander, PurchaseTransaction.Kind.TRAIN, _make_tool(a_type), a_energy
	)
	transaction.creation_time = a_ticks
	transaction.dispatch_filter.assign(a_producers)
	return transaction


## The same, flagged as a STANDING entry — the queue's lower tier, re-issued forever.
func _standing_purchase(
	a_commander: Commander, a_type: StringName, a_energy: int, a_producers: Array
) -> PurchaseTransaction:
	var transaction := _train_purchase(a_commander, a_type, a_energy, a_producers)
	transaction.standing = true
	return transaction


## --- affordable purchases fulfil immediately --------------------------------

func test_affordable_purchase_dispatches_on_submit() -> void:
	var commander := _make_commander(100)
	var producer := _make_producer([IRREGULAR])
	var transaction := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 40, [producer])
	)
	assert_eq(producer.production.job_count(), 1, "the job lands on the producer right away")
	assert_eq(commander.energy, 60, "the cost is deducted")
	assert_true(transaction.state == PurchaseTransaction.State.CONSUMED, "the purchase is settled")
	assert_true(commander.production_queue.is_empty(), "nothing is left queued")


## --- unaffordable purchases wait instead of being dropped -------------------

func test_unaffordable_purchase_waits_in_the_queue() -> void:
	var commander := _make_commander(10)
	var producer := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	assert_eq(producer.production.job_count(), 0, "nothing is produced yet")
	assert_eq(commander.energy, 10, "no energy is spent")
	assert_eq(commander.production_queue.queued().size(), 1, "the purchase is still queued")


func test_queued_purchase_fulfils_once_affordable() -> void:
	var commander := _make_commander(10)
	var producer := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	commander.add_energy(30)
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 1, "the job starts as soon as the energy is in")
	assert_eq(commander.energy, 0, "the cost is deducted on fulfilment, not on submission")


func test_queue_head_blocks_cheaper_purchases_behind_it() -> void:
	var commander := _make_commander(30)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 100, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 0,
		"the affordable purchase behind an unaffordable one waits its turn")
	assert_eq(commander.production_queue.queued().size(), 2, "both are still queued")


func test_queue_drains_only_as_fast_as_producers_free_up() -> void:
	# A structure builds ONE unit at a time, so affordability is no longer the only thing
	# holding the queue back: the other two purchases wait HERE, in the global queue, rather
	# than stacking up invisibly on the structure.
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	for i in 3:
		commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.add_energy(60)
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 1, "the producer takes one")
	assert_eq(commander.production_queue.queued().size(), 2, "the rest wait in the queue")
	assert_eq(commander.energy, 40, "and only the dispatched one is paid for")


func test_the_next_purchase_dispatches_once_the_producer_frees_up() -> void:
	var commander := _make_commander(100)
	var producer := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(commander.production_queue.queued().size(), 1, "the second one waits")
	# Stand-in for the unit popping: spawning one needs a live map and navmesh, and what is
	# under test is that a FREED producer is handed the next purchase, not how it was freed.
	producer.production.training_queue.clear()
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 1, "the waiting purchase starts")
	assert_true(commander.production_queue.is_empty(), "and the queue is clear")


## --- producer selection ------------------------------------------------------

func test_purchase_goes_to_a_free_producer() -> void:
	var commander := _make_commander(1000)
	var busy := _make_producer([IRREGULAR])
	var free := _make_producer([IRREGULAR])
	busy.production.enqueue(500, null, IRREGULAR)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [busy, free]))
	assert_eq(free.production.job_count(), 1, "the idle producer takes the job")
	assert_eq(busy.production.job_count(), 1, "the busy one is untouched")


func test_successive_purchases_spread_across_producers() -> void:
	var commander := _make_commander(1000)
	var a := _make_producer([IRREGULAR])
	var b := _make_producer([IRREGULAR])
	var c := _make_producer([IRREGULAR])
	for i in 5:
		commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [a, b, c]))
	# Five purchases over three producers: each one sees the previous structure busy, so
	# all three start together and the remaining two wait in the queue — never 5 piled
	# onto the lead structure, and never a structure left idle while work waits.
	assert_eq(a.production.job_count(), 1)
	assert_eq(b.production.job_count(), 1)
	assert_eq(c.production.job_count(), 1)
	assert_eq(commander.production_queue.queued().size(), 2, "the surplus waits in the queue")


func test_purchase_ignores_producers_that_cannot_make_it() -> void:
	var commander := _make_commander(1000)
	var wrong := _make_producer([VANGUARD])
	var right := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [wrong, right]))
	assert_eq(wrong.production.job_count(), 0, "a structure that can't train it is skipped")
	assert_eq(right.production.job_count(), 1)


func test_purchase_is_dropped_when_every_producer_is_gone() -> void:
	var commander := _make_commander(0)
	var producer := Commandable.new()
	var production := Production.new()
	production.producible_types = [IRREGULAR]
	producer.add_child(production)
	producer.production = production
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	producer.free()
	commander.add_energy(100)
	commander.production_queue.tick()
	assert_true(commander.production_queue.is_empty(),
		"a purchase nothing can fulfil is dropped rather than blocking the queue")
	assert_eq(commander.energy, 100, "and nothing is spent on it")


## --- structures still under construction --------------------------------------

func test_purchase_at_an_unbuilt_producer_waits_for_it() -> void:
	var commander := _make_commander(1000)
	var producer := _make_unbuilt_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(producer.production.job_count(), 0, "nothing is enqueued on a half-built structure")
	assert_eq(commander.production_queue.queued().size(), 1, "the purchase is held, not dropped")
	assert_eq(commander.energy, 980,
		"but it IS paid for — an affordable purchase is charged at request time, whether or "
		+ "not anything is free to start it")


func test_purchase_dispatches_when_construction_finishes() -> void:
	var commander := _make_commander(1000)
	var producer := _make_unbuilt_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	producer.build_progress = 1.0
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 1, "the queue hands the job over once it's built")
	assert_eq(commander.energy, 980,
		"having been charged at request time; finishing the structure takes nothing further")


func test_unbuilt_producer_is_skipped_while_a_finished_one_is_available() -> void:
	var commander := _make_commander(1000)
	var unbuilt := _make_unbuilt_producer([IRREGULAR])
	var finished := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [unbuilt, finished]))
	assert_eq(unbuilt.production.job_count(), 0)
	assert_eq(finished.production.job_count(), 1,
		"a mixed selection trains at whichever structure is actually ready")


func test_purchase_is_dropped_when_the_unbuilt_producer_is_destroyed() -> void:
	var commander := _make_commander(1000)
	var producer := Commandable.new()
	var production := Production.new()
	production.producible_types = [IRREGULAR]
	producer.add_child(production)
	producer.production = production
	producer.add_to_group("structure")
	producer.build_progress = 0.4
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(commander.production_queue.queued().size(), 1, "queued while it goes up")
	producer.free()
	commander.production_queue.tick()
	assert_true(commander.production_queue.is_empty(),
		"a structure destroyed mid-construction takes its queued units with it")


## --- pre-issued rally commands ------------------------------------------------
## A purchase captures each candidate producer's rally when it is SUBMITTED, then
## collapses that set to the one chain belonging to whichever structure builds it.
## The rally queue itself is covered in test_RallyQueue.gd.

func _rally(a_structure: Commandable, a_x: float, a_z: float, a_additive: bool = false) -> void:
	a_structure.command_receiver = CommandReceiver.new()
	a_structure.command_receiver.initialize(a_structure)
	a_structure.update_commands(
		MoveCommand.new(CommandMessage.new(null, null, null, Vector3(a_x, 0.0, a_z))), a_additive
	)


## The destinations of an arbitrary command chain, for asserting against a rally read live
## rather than against one stored on a job.
func _destinations(a_chain: Array) -> Array:
	var out: Array = []
	for command: MoveCommand in a_chain:
		out.append(command.message.position)
	return out


func _job_destinations(a_producer: Commandable, a_index: int) -> Array:
	var out: Array = []
	for command: MoveCommand in a_producer.production.training_queue[a_index][Production.JOB_COMMANDS]:
		out.append(command.message.position)
	return out


## THE RALLY IS READ AT SPAWN, NOT AT SUBMISSION. A job therefore carries NO chain of its own
## unless the player aimed one at that specific purchase; `Production._spawn_unit` reads the
## structure's rally as it stands when the unit appears. See
## gdd/systems/commands/construction.md §The rally is read at SPAWN.
func test_a_job_carries_no_rally_chain() -> void:
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR])
	_rally(producer, 3, 3)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(_job_destinations(producer, 0), [],
		"nothing is snapshot — the rally is the structure's to answer for at spawn")


## Which is the whole point of the change: re-aiming a rally re-aims every unit still queued
## behind it, rather than only the ones ordered after the move.
func test_moving_the_rally_re_aims_a_queued_unit() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	_rally(producer, 3, 3)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))

	# The rally moves while the purchase is still waiting on energy.
	_rally(producer, 40, 40)
	commander.add_energy(20)
	commander.production_queue.tick()

	assert_eq(_destinations(producer.rally_chain()), [Vector3(40, 0, 40)],
		"the unit will follow the rally as it stands now, not the one it was ordered under")
	assert_eq(_job_destinations(producer, 0), [],
		"and the job still holds nothing of its own")


## A player order aimed at the PURCHASE does travel with it — that is the one thing that
## overrides the producer's rally.
func test_a_player_order_travels_with_the_purchase() -> void:
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR])
	_rally(producer, 3, 3)
	var purchase: PurchaseTransaction = _train_purchase(commander, IRREGULAR, 20, [producer])
	purchase.queue_player_command(
		MoveCommand.new(CommandMessage.new(null, null, null, Vector3(9, 0, 9))), true)
	commander.production_queue.submit(purchase)
	assert_eq(_job_destinations(producer, 0), [Vector3(9, 0, 9)],
		"the player singled this unit out, so it ignores the rally")


func test_a_multi_leg_rally_is_still_whole_at_spawn() -> void:
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR])
	_rally(producer, 3, 3)
	_rally(producer, 6, 2, true)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(_destinations(producer.rally_chain()), [Vector3(3, 0, 3), Vector3(6, 0, 2)],
		"a chain is read whole, however many legs it has")


## --- pending_count_for (idle-producer bookkeeping) ---------------------------

func test_pending_count_tracks_queued_purchases() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	assert_eq(commander.production_queue.pending_count_for(producer), 0)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	assert_eq(commander.production_queue.pending_count_for(producer), 1,
		"a structure with a purchase waiting on it isn't idle")
	commander.add_energy(40)
	commander.production_queue.tick()
	assert_eq(commander.production_queue.pending_count_for(producer), 0,
		"once dispatched the job lives on the structure, not the queue")


## --- cancelling and clearing --------------------------------------------------

func test_cancel_removes_a_queued_purchase() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	var transaction := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 40, [producer])
	)
	assert_true(commander.production_queue.cancel(transaction))
	assert_true(commander.production_queue.is_empty())
	commander.add_energy(100)
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 0, "a cancelled purchase never fulfils")


func test_clear_queued_leaves_standing_entries_running() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 40, [producer]))
	commander.production_queue.clear_queued()
	assert_true(commander.production_queue.queued().is_empty(), "the one-off entries are gone")
	assert_eq(commander.production_queue.standing().size(), 1, "the standing order is untouched")


func test_standing_entry_is_dropped_when_nothing_can_produce_it() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 40, [producer]))
	commander.production_queue.tick()
	assert_true(commander.production_queue.standing().is_empty(),
		"a standing entry no structure can make is pruned rather than spinning forever")


func test_clear_all_empties_both_tiers() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 40, [producer]))
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 40, [producer]))
	commander.production_queue.clear_all()
	assert_true(commander.production_queue.is_empty())


func test_clearing_drops_a_build_that_is_still_waiting_on_energy() -> void:
	var commander := _make_commander(0)
	var transaction := commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	commander.production_queue.clear_all()
	assert_true(commander.production_queue.is_empty())
	commander.add_energy(100)
	commander.production_queue.tick()
	assert_false(transaction.is_funded(), "a cleared build is never funded afterwards")
	assert_eq(commander.energy, 100, "and costs nothing")


## A build whose cost is already RESERVED has left the queue — it belongs to its builders
## from that point on, and clearing the queue no longer reaches it. Cancelling it means
## re-ordering the builders, which refunds via the holder count (see the tests below).
func test_clearing_does_not_reach_an_already_funded_build() -> void:
	var commander := _make_commander(100)
	commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	assert_true(commander.production_queue.is_empty(), "a funded build isn't queued any more")
	commander.production_queue.clear_all()
	assert_eq(commander.energy, 40, "its reservation stands")


## --- the standing tier ---------------------------------------------------------

func test_standing_entries_wait_behind_every_one_off_purchase() -> void:
	var commander := _make_commander(20)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	# The expensive one-off purchase goes in FIRST, so it is already blocking the head of
	# the queue when the affordable standing entry is submitted behind it.
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 100, [producer]))
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.tick()
	assert_eq(producer.production.job_count(), 0,
		"the standing entry waits behind an unaffordable one-off purchase")
	assert_eq(commander.energy, 20, "and its energy is saved toward the queued purchase")


func test_a_standing_entry_outranked_by_a_later_one_off_purchase() -> void:
	# Tiers, not arrival order: a one-off submitted AFTER a standing entry still goes first,
	# which is what makes the starvation deliberate rather than accidental.
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 20, [producer]))
	commander.add_energy(20)
	commander.production_queue.tick()
	assert_eq(producer.production.job_type(0), VANGUARD, "the one-off purchase went first")


func test_standing_entry_re_issues_on_the_next_pass() -> void:
	var commander := _make_commander(20)
	var a := _make_producer([IRREGULAR])
	var b := _make_producer([IRREGULAR])
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 20, [a, b]))
	assert_eq(a.production.job_count(), 1, "the standing entry fires once on submission")
	assert_eq(commander.production_queue.standing().size(), 1, "and stays queued")
	commander.add_energy(20)
	commander.production_queue.tick()
	assert_eq(b.production.job_count(), 1, "it fires again on the next pass")


func test_standing_entries_rotate_between_themselves() -> void:
	var commander := _make_commander(0)
	var a := _make_producer([IRREGULAR, VANGUARD])
	var b := _make_producer([IRREGULAR, VANGUARD])
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 20, [a, b]))
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 20, [a, b]))
	commander.add_energy(40)
	commander.production_queue.tick()
	commander.production_queue.tick()
	assert_eq(a.production.job_type(0), IRREGULAR, "the first standing entry went first")
	assert_eq(b.production.job_type(0), VANGUARD, "then the second")


func test_a_dispatched_standing_entry_does_not_itself_repeat() -> void:
	# The TEMPLATE repeats; the copy it dispatches is one ordinary purchase. A copy that
	# repeated in its own right would double the entry on every pass.
	var commander := _make_commander(100)
	var producer := _make_producer([IRREGULAR])
	var template := _standing_purchase(commander, IRREGULAR, 20, [producer])
	commander.production_queue.submit(template)
	assert_eq(commander.production_queue.standing().size(), 1)
	assert_eq(commander.production_queue.standing()[0], template)


## --- BUILD bookkeeping ---------------------------------------------------------

func test_build_purchase_reserves_without_consuming() -> void:
	var commander := _make_commander(100)
	var transaction := commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	assert_true(transaction.is_funded(), "the cost is reserved ahead of the builder arriving")
	assert_eq(commander.energy, 40)
	assert_true(commander.production_queue.is_empty(),
		"a funded build leaves the queue — it no longer blocks anything behind it")


func test_abandoned_build_refunds_its_reservation() -> void:
	var commander := _make_commander(100)
	var transaction := commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	# Two builders were sent; both lose the order before either lays the foundation.
	transaction.retain_holder()
	transaction.retain_holder()
	transaction.release_holder()
	assert_eq(commander.energy, 40, "one builder dropping out doesn't cancel the order")
	transaction.release_holder()
	assert_eq(commander.energy, 100, "the last one dropping out refunds the reservation")


func test_consumed_build_is_not_refunded() -> void:
	var commander := _make_commander(100)
	var transaction := commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	transaction.retain_holder()
	transaction.consume()  # the builder laid the foundation
	transaction.release_holder()
	assert_eq(commander.energy, 40, "a structure that was actually placed stays paid for")


## --- Production.remaining_ticks ------------------------------------------------

func test_remaining_ticks_reports_the_active_job() -> void:
	var production := Production.new()
	autofree(production)
	assert_eq(production.remaining_ticks(), 0, "an idle producer is free now")
	production.enqueue(30, null, IRREGULAR)
	assert_eq(production.remaining_ticks(), 30)


func test_a_producer_takes_one_job_at_a_time() -> void:
	var production := Production.new()
	autofree(production)
	assert_true(production.is_free(), "an empty producer is free")
	assert_true(production.enqueue(30, null, IRREGULAR), "the first job is accepted")
	assert_false(production.is_free(), "and it is busy now")
	assert_false(production.enqueue(20, null, VANGUARD), "a second job is refused")
	assert_eq(production.job_count(), 1, "and changes nothing")


## --- entry ordering, ids and the completion path --------------------------------

## --- the global commitment order ---------------------------------------------
##
## Why these exist: gdd/systems/macroeconomics/requisition-as-a-modifier.md
## §Resources are committed in the order the player asked. Nothing can jump the funding
## queue any more — the front-of-tier flag that used to allow it is gone — so submission
## order IS commitment order, across every purchase the commander has made.

func test_nothing_can_jump_the_queue_within_a_tier() -> void:
	# The `to_front` flag is retired. Two one-offs submitted in order stay in that order,
	# whatever they are and whichever was cheaper.
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	var first := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 90, [producer])
	)
	var second := commander.production_queue.submit(
		_train_purchase(commander, VANGUARD, 10, [producer])
	)
	assert_eq(commander.production_queue.queued()[0], first, "the earlier order still leads")
	assert_eq(commander.production_queue.queued()[1], second, "and the later one follows it")


func test_a_later_build_waits_its_turn_for_funds_behind_an_earlier_one() -> void:
	# Alex's worked case: unit 1 is requisitioned to build A, then unit 2 to build B. Unit 2
	# may be standing on its site and ready to start, but B cannot take money before A has.
	var commander := _make_commander(0)
	var a := commander.production_queue.submit(_build_purchase(commander, 100))
	var b := commander.production_queue.submit(_build_purchase(commander, 10))
	assert_true(a.is_pending(), "neither is funded while the commander is broke")
	assert_true(b.is_pending())

	# Enough for B twice over, but not for A. B must NOT take it.
	commander.energy = 40
	commander.production_queue.tick()
	assert_true(b.is_pending(), "B cannot be funded ahead of A, even though it could afford to")
	assert_eq(commander.energy, 40, "and nothing was spent")

	# Once A can be paid for, both go through in order.
	commander.energy = 110
	commander.production_queue.tick()
	assert_true(a.is_funded(), "A takes its money first")
	assert_true(b.is_funded(), "and B follows in the same pass")
	assert_eq(commander.energy, 0, "both costs are committed")


func test_waiting_for_funds_is_not_waiting_for_completion() -> void:
	# The rule is a queue over COMMITMENT, not over construction: B waits for A's turn at
	# the purse, not for A's structure to be finished. A is still an un-consumed BUILD
	# reservation (its builder has not laid the foundation) when B is funded.
	var commander := _make_commander(100)
	var a := commander.production_queue.submit(_build_purchase(commander, 60))
	var b := commander.production_queue.submit(_build_purchase(commander, 40))
	assert_true(a.is_funded(), "A is funded")
	assert_true(b.is_funded(), "and B is funded in the same breath")
	assert_false(a.is_settled(), "even though A has not been built — nothing was waited on")


func test_an_unfunded_entry_blocks_a_later_affordable_one_at_submission_time() -> void:
	# The same rule at the OTHER end: charge-on-submit must not quietly pay for a purchase
	# made after one still owed money, or the queue's order would mean nothing.
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	var blocked := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 500, [producer])
	)
	commander.energy = 30
	var later := commander.production_queue.submit(
		_train_purchase(commander, VANGUARD, 20, [producer])
	)
	assert_true(blocked.is_pending(), "the expensive earlier order is still unpaid")
	assert_true(later.is_pending(), "so the cheap later one is not paid for either")
	assert_eq(commander.energy, 30, "the money is still the earlier order's to claim")


func test_a_standing_entry_still_cannot_reach_the_head() -> void:
	# The tiers are not negotiable and never were: every one-off outranks every standing
	# entry, and with front-insertion gone there is nothing that could argue otherwise.
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	var one_off := _train_purchase(commander, IRREGULAR, 20, [producer])
	commander.production_queue.submit(one_off)
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 20, [producer]))
	assert_eq(commander.production_queue.entries[0], one_off, "the one-off entry still leads")


func test_transactions_carry_unique_ids_and_are_addressable_by_them() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	var first := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 20, [producer])
	)
	var second := commander.production_queue.submit(
		_train_purchase(commander, VANGUARD, 20, [producer])
	)
	assert_ne(first.id, second.id, "ids are unique")
	assert_eq(commander.production_queue.find_by_id(second.id), second,
		"the queue is addressable by id, not only by position")
	commander.production_queue.cancel(first)
	assert_eq(commander.production_queue.find_by_id(second.id), second,
		"and the id survives everything ahead of it being dropped")


func test_completing_a_purchase_announces_the_product_before_retiring() -> void:
	var commander := _make_commander(0)
	var transaction := _train_purchase(commander, IRREGULAR, 20, [])
	var seen: Array = []
	transaction.fulfilled.connect(
		func(t: PurchaseTransaction, product: Node) -> void: seen.append([t, product])
	)
	var unit: Commandable = autofree(Commandable.new()) as Commandable
	transaction.complete(unit)
	assert_eq(seen.size(), 1, "the fulfilment is announced exactly once")
	assert_eq(seen[0][1], unit, "carrying the thing that was bought")
	assert_true(transaction.is_settled(), "and the transaction retires")


func test_a_cancelled_purchase_cannot_be_completed_afterwards() -> void:
	var commander := _make_commander(0)
	var transaction := _train_purchase(commander, IRREGULAR, 20, [])
	transaction.cancel()
	var seen: Array = []
	transaction.fulfilled.connect(
		func(_t: PurchaseTransaction, _p: Node) -> void: seen.append(true)
	)
	transaction.complete(null)
	assert_true(seen.is_empty(), "nothing is announced for a purchase that was dropped")


func test_refund_on_cancel_can_withhold_a_refund() -> void:
	# Refunds are always full TODAY (see PurchaseTransaction.refund_on_cancel); the flag is
	# the policy hook, and this pins that cancellation consults it rather than the mode that
	# created the entry.
	var commander := _make_commander(100)
	var transaction := commander.production_queue.submit(PurchaseTransaction.for_cost(
		commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), 60
	))
	transaction.refund_on_cancel = false
	transaction.cancel()
	assert_eq(commander.energy, 40, "the reservation is kept")


## --- the dispatch filter --------------------------------------------------------
## An EMPTY filter means "any applicable structure this commander owns", not "none". The
## filter is a genuine restriction, present so a purchase can EXCLUDE a producer, rather
## than something a purchase must fill in to be dispatchable at all.

func test_an_unfenced_purchase_dispatches_to_any_applicable_producer() -> void:
	var commander := _make_commander(100)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	# No producers named — the order was given with nothing selected.
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, []))
	assert_eq(producer.production.job_count(), 1, "it found the structure that can make it")


func test_an_unfenced_purchase_ignores_structures_that_cannot_make_it() -> void:
	var commander := _make_commander(100)
	var wrong := _make_producer([VANGUARD])
	var right := _make_producer([IRREGULAR])
	commander.add_child(wrong)
	commander.add_child(right)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, []))
	assert_eq(wrong.production.job_count(), 0)
	assert_eq(right.production.job_count(), 1)


func test_an_unfenced_purchase_is_orphaned_only_when_nothing_could_make_it() -> void:
	var commander := _make_commander(100)
	commander.add_child(_make_producer([VANGUARD]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, []))
	assert_true(commander.production_queue.is_empty(),
		"a commander who owns nothing that can make it drops the purchase")
	assert_eq(commander.energy, 100, "and is not charged")


func test_an_unfenced_purchase_reaches_a_producer_built_after_it_was_queued() -> void:
	# The filter resolves LIVE, not once at submission: a barracks finished after the order
	# was given is a legitimate producer for it.
	var commander := _make_commander(100)
	var early := _make_producer([VANGUARD])
	commander.add_child(early)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, []))
	assert_true(commander.production_queue.is_empty(), "nothing could make it yet")
	var later := _make_producer([IRREGULAR])
	commander.add_child(later)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, []))
	assert_eq(later.production.job_count(), 1, "the newer structure takes it")


func test_a_fenced_purchase_ignores_an_eligible_structure_outside_its_filter() -> void:
	var commander := _make_commander(100)
	var named := _make_producer([IRREGULAR])
	var unnamed := _make_producer([IRREGULAR])
	commander.add_child(named)
	commander.add_child(unnamed)
	named.production.enqueue(500, null, IRREGULAR)  # busy
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [named]))
	assert_eq(unnamed.production.job_count(), 0,
		"a purchase fenced to one structure waits for it rather than going elsewhere")
	assert_eq(commander.production_queue.queued().size(), 1)


## --- the standing ring holds its authored order ---------------------------------
##
## `entries` is DISPATCH order and rotates every time a standing template fires, which is
## correct for the queue and wrong for a readout: a ring authored as R R T would appear to
## shuffle into R T R and then T R R. standing_ring() is the stable view, and it works
## because _insert no longer restamps `sequence` on a rotation.

func _ring_types(a_ring: Array) -> Array:
	return a_ring.map(func(t: PurchaseTransaction) -> StringName: return t.type)


func test_standing_ring_keeps_its_authored_order_across_rotations() -> void:
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.add_child(producer)
	# A ring of two Irregulars then a Vanguard — the "three soldiers and a tank" shape.
	for type: StringName in [IRREGULAR, IRREGULAR, VANGUARD]:
		commander.production_queue.submit(_standing_purchase(commander, type, 10, [producer]))

	var authored: Array = _ring_types(commander.production_queue.standing_ring())
	assert_eq(authored, [IRREGULAR, IRREGULAR, VANGUARD], "the ring as it was built")

	# Rotate it several times. Each tick frees the producer first, so a template dispatches.
	for i in 4:
		producer.production.training_queue.clear()
		commander.production_queue.tick()

	assert_eq(_ring_types(commander.production_queue.standing_ring()), authored,
		"the ring still reads in submission order after rotating")


func test_standing_next_is_the_cursor_that_moves() -> void:
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.add_child(producer)
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 10, [producer]))
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 10, [producer]))

	assert_eq(commander.production_queue.standing_next().type, IRREGULAR,
		"the first template submitted runs first")
	producer.production.training_queue.clear()
	commander.production_queue.tick()
	assert_eq(commander.production_queue.standing_next().type, VANGUARD,
		"the cursor advances while the ring itself holds still")


func test_a_rotated_standing_entry_still_yields_to_a_one_off() -> void:
	# Preserving `sequence` across rotations must not disturb the two-tier rule: a rotated
	# template has an OLD sequence number, and tier still outranks it.
	var commander := _make_commander(1000)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.add_child(producer)
	commander.production_queue.submit(_standing_purchase(commander, IRREGULAR, 10, [producer]))
	producer.production.training_queue.clear()
	commander.production_queue.tick()

	producer.production.training_queue.clear()
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 10, [producer]))
	assert_eq(producer.production.job_type(0), VANGUARD,
		"the one-off goes first even though the standing template is older")


## --- a producer-blocked entry does not hold up the queue -------------------------
##
## Head-of-line blocking is about ENERGY. An entry waiting for a barracks to free up is not
## waiting for anything an entry behind it could consume, so it must not stop that entry —
## which is exactly the reported bug: two units queued at one barracks left a BUILD behind
## them stuck, with the energy banked and the builders standing at the site.

func _build_purchase(a_commander: Commander, a_energy: int) -> PurchaseTransaction:
	return PurchaseTransaction.for_cost(
		a_commander, PurchaseTransaction.Kind.BUILD, _make_tool(&"tc_armory"), a_energy
	)


func test_a_build_is_not_blocked_by_a_unit_waiting_on_a_busy_producer() -> void:
	var commander := _make_commander(500)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	# First unit takes the barracks; second has nowhere to go.
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(producer.production.job_count(), 1, "the barracks is building the first")
	assert_eq(commander.production_queue.queued().size(), 1, "the second is waiting on it")

	var build := commander.production_queue.submit(_build_purchase(commander, 60))
	assert_true(build.is_funded(),
		"the build reserves its cost rather than waiting behind a unit queued at a busy barracks")
	assert_eq(commander.production_queue.queued().size(), 1,
		"and the producer-blocked unit is still queued, in front of nothing")


func test_a_unit_for_a_free_producer_passes_one_waiting_on_a_busy_one() -> void:
	var commander := _make_commander(500)
	var busy := _make_producer([IRREGULAR])
	var free := _make_producer([VANGUARD])
	commander.add_child(busy)
	commander.add_child(free)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [busy]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [busy]))
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 20, [free]))
	assert_eq(free.production.job_count(), 1,
		"a purchase whose own producer is free is not held up by one whose producer is busy")


func test_fifo_survives_the_skip_when_the_producer_frees() -> void:
	# The scan restarts from the front every tick, so the entry that was skipped is reached
	# first the moment a candidate frees — nothing that passed it can jump the queue.
	var commander := _make_commander(500)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.add_child(producer)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 20, [producer]))

	producer.production.training_queue.clear()
	commander.production_queue.tick()
	assert_eq(producer.production.job_type(0), IRREGULAR,
		"the earlier of the two waiting purchases goes first")


func test_an_unaffordable_entry_still_blocks_everything_behind_it() -> void:
	# The other blocker is unchanged, and deliberately so: energy is fungible, so letting a
	# cheap purchase behind an expensive one spend it would starve the expensive one.
	var commander := _make_commander(50)
	var producer := _make_producer([IRREGULAR, VANGUARD])
	commander.add_child(producer)
	commander.production_queue.submit(_train_purchase(commander, VANGUARD, 200, [producer]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [producer]))
	assert_eq(producer.production.job_count(), 0, "nothing started")
	assert_eq(commander.production_queue.queued().size(), 2,
		"the affordable purchase waits behind the one saving up")


func test_a_producer_blocked_one_off_still_holds_off_the_standing_tier() -> void:
	# A standing entry soaks income nothing else wants, so it must not spend energy a queued
	# one-off is still owed — even one that is only waiting for a building to free up.
	var commander := _make_commander(500)
	var busy := _make_producer([IRREGULAR])
	var free := _make_producer([VANGUARD])
	commander.add_child(busy)
	commander.add_child(free)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [busy]))
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 20, [busy]))
	commander.production_queue.submit(_standing_purchase(commander, VANGUARD, 20, [free]))
	assert_eq(free.production.job_count(), 0,
		"the standing entry waits while a one-off is still outstanding")


## --- purchases are charged at REQUEST time ------------------------------------
##
## The debit used to happen at dispatch, so a purchase that couldn't start yet was never
## charged and the next order checked against energy already spoken for — you could commit the
## same 150 energy without limit. Charging on submit is what makes the check honest, and what
## keeps requisition mode meaning something.

func test_a_queued_purchase_is_charged_even_with_no_producer_free() -> void:
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 75, [producer]))
	assert_eq(commander.energy, 75, "the first is charged and started")
	var second := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_eq(commander.energy, 0, "the second is charged too, though it cannot start yet")
	assert_true(second.is_funded(), "it is paid for and waiting on the barracks, not pending")


func test_the_same_energy_cannot_be_committed_twice() -> void:
	# The reported bug: 150 energy and 75-energy units let you queue a third, and a fourth, and on
	# forever, because nothing after the first dispatch ever reduced the pool.
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	for i in 2:
		commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 75, [producer]))
	assert_eq(commander.energy, 0)
	var third := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_true(third.is_pending(), "a third is unaffordable now, not silently queued as paid")
	assert_eq(commander.energy, 0, "and nothing further was taken")


func test_a_funded_purchase_waiting_on_a_producer_still_names_its_blocker() -> void:
	# Being paid for is not being unblocked. Gating the blocker on PENDING would leave the
	# readout silent about the only thing holding a paid purchase up.
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 75, [producer]))
	var second := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_eq(commander.production_queue.blocker_for(second),
		ProductionQueue.Blocker.NO_FREE_PRODUCER)


func test_cancelling_a_queued_purchase_returns_what_was_charged() -> void:
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 75, [producer]))
	var second := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_true(commander.production_queue.cancel(second))
	assert_eq(commander.energy, 75, "the charge is refunded in full")


func test_a_standing_template_is_not_charged_until_it_issues() -> void:
	# A template re-issues forever, so there is no bounded amount to charge up front —
	# charging as it fires is what lets the ring soak resources that would otherwise float.
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	producer.production.enqueue(500, null, IRREGULAR)  # busy, so nothing dispatches
	var template := commander.production_queue.submit(
		_standing_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_true(template.is_pending(), "the template itself is never funded")
	assert_eq(commander.energy, 150, "and nothing is taken while it waits")


func test_an_unaffordable_requisition_is_charged_when_it_finally_dispatches() -> void:
	var commander := _make_commander(0)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	var queued := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)
	assert_true(queued.is_pending(), "nothing to charge yet")
	commander.energy = 75
	commander.production_queue.tick()
	assert_eq(commander.energy, 0, "charged at fulfilment, since it could not be charged at request")
	assert_eq(producer.production.job_count(), 1)


## --- request-time charging respects queue order ------------------------------

## Charging at SUBMIT must not repeal the head-of-line blocking tick() enforces. It used
## to: the money was taken before the scan ran, so a purchase behind an unaffordable one
## paid for itself first. The case that makes it plainly wrong is a unit ordered at a
## blueprint whose own BUILD is still unfunded — the unit cannot be produced until that
## build completes, so its reserved energy is dead capital starving the structure it waits on.
func test_a_purchase_is_not_charged_past_an_unfunded_entry_ahead_of_it() -> void:
	var commander := _make_commander(0)
	var build := _build_purchase(commander, 500)
	commander.production_queue.submit(build)
	assert_true(build.is_pending(), "the build is queued but unaffordable")

	# Income arrives: enough for a unit, nowhere near enough for the structure.
	commander.add_energy(60)
	var blueprint := _make_unbuilt_producer([IRREGULAR])
	commander.add_child(blueprint)
	var train := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 50, [blueprint])
	)

	assert_false(train.is_funded(), "the unit does not pay for itself ahead of the build")
	assert_eq(commander.energy, 60, "and the energy stays available to the build it is queued behind")
	assert_false(build.is_funded(), "the build is still waiting, at the head, for its own price")


## The flip side, which is what request-time charging exists for: with nothing unpaid ahead,
## every request still debits immediately, so successive orders can't all pass the same
## affordability check against the same untouched treasury.
func test_a_purchase_is_still_charged_immediately_when_nothing_ahead_is_unfunded() -> void:
	var commander := _make_commander(150)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	# Busy the producer so the purchases stay queued rather than dispatching and vanishing.
	commander.production_queue.submit(_train_purchase(commander, IRREGULAR, 75, [producer]))
	var second := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 75, [producer])
	)

	assert_true(second.is_funded(), "the second order is charged too — the check is honest")
	assert_eq(commander.energy, 0, "both are paid for")


## A FUNDED entry waiting only on a busy producer has already taken its money and reserves
## nothing further, so it must not stop the next request from being charged — the same
## reasoning DispatchResult.WAIT_PRODUCER is documented with.
func test_a_funded_producer_blocked_entry_does_not_hold_the_purse() -> void:
	var commander := _make_commander(200)
	var producer := _make_producer([IRREGULAR])
	commander.add_child(producer)
	var first := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 50, [producer])
	)
	var second := commander.production_queue.submit(
		_train_purchase(commander, IRREGULAR, 50, [producer])
	)

	# The first dispatches straight to the free producer, so it is CONSUMED rather than
	# left FUNDED; the second stays queued on the now-busy producer.
	assert_true(first.is_settled(), "the first was dispatched to the free producer")
	assert_true(second.is_funded(), "the one queued behind it on that producer is still paid for")
	assert_eq(commander.energy, 100, "both purchases debited")
