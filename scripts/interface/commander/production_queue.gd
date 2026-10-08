class_name ProductionQueue
extends RefCounted

## The commander's GLOBAL production queue — the single place every purchase passes
## through. A purchase (train a unit, place a structure) can be submitted whether or not
## the commander can afford it: it is fulfilled the moment the resources exist.
##
## ONE queue, not two. The immediate queue and the repeating ring used to be separate
## structures selected between by a held modifier; they are now one ordered list whose
## entries carry the difference as FLAGS (see PurchaseTransaction's entry attributes):
##
##   * standing — re-enqueued at the tail on dispatch instead of being consumed, so it
##     re-issues forever and idle income always has somewhere to go.
##   * on_precondition_failure — reject the order outright, or queue and wait.
##
## Ordering is TWO-TIER: every non-standing entry outranks every standing one, and within
## a tier the order is strict FIFO. Nothing else is ever needed — arbitrary priorities are
## not wanted, and a heap over equal priorities would not be stable, so the order is
## maintained by insertion (see _insert) rather than by sorting.
##
## Head-of-line blocking is deliberate, but it is about ENERGY, not about everything. An entry
## blocks the queue only while it waits for something an entry behind it could CONSUME:
##
##   * waiting on energy blocks, because energy is fungible — a cheap purchase spending what an
##     expensive one is saving for would starve it, and not starving it is what makes this
##     an order of intent;
##   * waiting on a free PRODUCER does not, because an entry is producer-blocked exactly
##     when none of its candidates is free, so any producer another entry can reach is one
##     this entry could not have used anyway.
##
## See DispatchResult for the full argument and the bug that motivated splitting the two.
##
## A one-off entry that has not dispatched — for either reason — still holds off the
## standing tier. A standing entry is meant to soak income nothing else wants, so it must
## not spend energy a queued one-off is still owed.
##
## Dispatch by kind:
##   * TRAIN — pick a FREE producer from the transaction's eligible set, deduct the cost,
##     and hand the job to that structure. A structure builds ONE unit at a time: there is
##     no per-structure queue any more, and units waiting to be built wait HERE, where the
##     commander can see and reorder them. Five irregulars queued against three strongholds
##     start three now and two as the first two finish.
##   * BUILD — deduct the cost and leave the transaction FUNDED (reserved). The builder
##     may still be walking; it lays the foundation on arrival and consumes the
##     reservation then. Abandoning the order refunds it (see PurchaseTransaction).
##
## Ticked once per physics frame from Commander._physics_process, and drained again
## synchronously on submit() so an affordable purchase issued with an empty queue is
## fulfilled in the same frame it was ordered — the queue adds no latency to the
## common case.

#region Constants
## Standing dispatches allowed per tick. One keeps a standing entry from spending a whole
## treasury in a single frame, so the non-standing tier (which the player is actively
## filling) still wins the next tick's income.
const MAX_STANDING_DISPATCHES_PER_TICK: int = 1
#endregion

#region Properties
## Every queued purchase, in dispatch order: non-standing entries first (FIFO), then
## standing ones (FIFO). Maintained sorted by _insert; never re-sorted.
var entries: Array[PurchaseTransaction] = []

## Monotonic submission counter handing out PurchaseTransaction.sequence. Never reset, so
## sequence numbers are unique for the life of the commander.
var _next_sequence: int = 1

var _commander: Commander
#endregion


#region Lifecycle
func _init(a_commander: Commander) -> void:
	_commander = a_commander


#endregion


#region Submission
## Queue a purchase, in the position its own flags call for. Drains immediately so an
## affordable purchase at the head of an empty queue is fulfilled right away. Returns the
## transaction so callers can hold or cancel it.
func submit(a_transaction: PurchaseTransaction) -> PurchaseTransaction:
	if a_transaction == null:
		return null
	# NOTHING IS SNAPSHOT HERE. A producer's rally is read off the structure when the unit
	# SPAWNS, not when the purchase is made, so re-aiming a rally re-aims every unit still
	# queued behind it. See gdd/systems/commands/construction.md §The rally is read at SPAWN.
	#
	# A repeating BUILD has no meaningful site or builder, so a build asking to be standing
	# is demoted to an ordinary one-off rather than refused.
	# An upgrade is bought once, so a standing research would have nothing to repeat: demoted the
	# same way.
	if (
		a_transaction.kind == PurchaseTransaction.Kind.BUILD
		or UpgradeCatalog.is_upgrade(a_transaction.type)
	):
		a_transaction.standing = false
	_insert(a_transaction)
	_charge_on_submit(a_transaction)
	tick()
	return a_transaction


## Take the money NOW, at request time, for any one-off purchase the commander can afford —
## whether or not anything is free to start on it yet.
##
## Why it works this way: gdd/systems/macroeconomics/production-and-economy.md §Debit timing:
## charging on submit.
func _charge_on_submit(a_transaction: PurchaseTransaction) -> void:
	if a_transaction.standing or not a_transaction.is_pending():
		return
	if _unfunded_entry_ahead_of(a_transaction):
		return
	if a_transaction.can_fund():
		a_transaction.fund()


## True when some entry AHEAD of `a_transaction` in dispatch order has not been paid for yet.
##
## Deliberately asks is_pending() rather than blocker_for(): an entry that is FUNDED and only
## waiting on a producer has already taken its money and reserves nothing further, which is
## exactly the case DispatchResult.WAIT_PRODUCER is documented to let others past. Only an
## unpaid entry ahead holds the purse.
func _unfunded_entry_ahead_of(a_transaction: PurchaseTransaction) -> bool:
	for entry: PurchaseTransaction in entries:
		if entry == a_transaction:
			return false
		# Standing templates are charged per ISSUANCE, never up front, so one sitting ahead is
		# not owed anything and cannot block a one-off's debit. (Tiering means this can't
		# actually happen today — standing entries sort behind every one-off — but the rule is
		# about what the entry is, not where it landed.)
		if entry.standing:
			continue
		if entry.is_pending():
			return true
	return false


## Queue a unit purchase. `a_dispatch_filter` restricts which structures may fulfil it —
## normally the production structures that were selected when the order was issued. An
## EMPTY filter is not "nowhere" but "anywhere the commander can make it"; see
## PurchaseTransaction.dispatch_filter.
func submit_train(
	a_tool: Tool, a_dispatch_filter: Array, a_standing: bool = false
) -> PurchaseTransaction:
	if a_tool == null:
		return null
	var transaction: PurchaseTransaction = PurchaseTransaction.for_tool(
		_commander, PurchaseTransaction.Kind.TRAIN, a_tool
	)
	transaction.dispatch_filter.assign(a_dispatch_filter)
	transaction.standing = a_standing
	return submit(transaction)


## Place `a_transaction` in tier order, stamping its sequence number. Front-insertion is
## within the entry's OWN tier: a standing entry asking for the front still sits behind
## every non-standing one, because the tiers are not negotiable.
##
## `a_assign_sequence` is false for the one caller that RE-inserts an entry already in the
## queue — the standing rotation in tick(). Restamping there would destroy the only record
## of the ring's AUTHORED order: `entries` rotates as each standing template dispatches, so
## a ring submitted as R R R T becomes R R T R and then R T R R, and a readout drawing
## `entries` order shows the ring shuffling. Keeping the original sequence lets the HUD sort
## the standing tier back into submission order and mark the head separately (see
## ProductionRail), while `entries` stays the DISPATCH order it has always been.
func _insert(a_transaction: PurchaseTransaction, a_assign_sequence: bool = true) -> void:
	if a_assign_sequence:
		a_transaction.sequence = _next_sequence
		_next_sequence += 1
	var tier: int = a_transaction.tier()
	var index: int = 0
	while index < entries.size() and entries[index].tier() <= tier:
		index += 1
	entries.insert(index, a_transaction)


## Drop `a_transaction` from the queue, refunding any reserved cost. Returns whether it
## was found. A dispatched TRAIN purchase is no longer here — cancel that through the
## producer it was handed to (Production.cancel), which refunds it.
func cancel(a_transaction: PurchaseTransaction) -> bool:
	var index: int = entries.find(a_transaction)
	if index == -1:
		return false
	entries.remove_at(index)
	a_transaction.cancel()
	return true


## The queued purchase with this id, or null. The queue is addressable by ID rather than
## by position because positions shift under every dispatch and cancellation.
func find_by_id(a_id: int) -> PurchaseTransaction:
	for transaction: PurchaseTransaction in entries:
		if transaction.id == a_id:
			return transaction
	return null


## Cancel every ONE-OFF purchase, refunding anything reserved. Standing entries are left
## alone, so standing production resumes from them on the next tick.
func clear_queued() -> void:
	_clear(func(t: PurchaseTransaction) -> bool: return not t.standing)


## Cancel every STANDING entry, refunding anything reserved.
func clear_standing() -> void:
	_clear(func(t: PurchaseTransaction) -> bool: return t.standing)


## Cancel everything the commander has committed to buying.
func clear_all() -> void:
	_clear(func(_t: PurchaseTransaction) -> bool: return true)


func _clear(a_predicate: Callable) -> void:
	for i: int in range(entries.size() - 1, -1, -1):
		var transaction: PurchaseTransaction = entries[i]
		if a_predicate.call(transaction):
			entries.remove_at(i)
			transaction.cancel()


#endregion


#region Queries
## Every queued purchase, in dispatch order — what the HUD lists.
func pending() -> Array[PurchaseTransaction]:
	return entries.duplicate()


## The one-off entries, in order. The queue's first tier.
func queued() -> Array[PurchaseTransaction]:
	return entries.filter(func(t: PurchaseTransaction) -> bool: return not t.standing)


## The standing entries in DISPATCH order — the queue's second tier, as `entries` holds it.
## Its front is whichever template dispatches next, which rotates every cycle.
func standing() -> Array[PurchaseTransaction]:
	return entries.filter(func(t: PurchaseTransaction) -> bool: return t.standing)


## The standing entries in AUTHORED order: the ring as the player built it, sorted by the
## submission `sequence` that _insert now preserves across rotations.
##
## A separate query from standing() because the two answer different questions, and a
## readout that used dispatch order would show the ring shuffling every cycle rather than
## holding still with a moving cursor. Pair it with standing_next() for that cursor.
func standing_ring() -> Array[PurchaseTransaction]:
	var ring: Array[PurchaseTransaction] = standing()
	ring.sort_custom(
		func(a: PurchaseTransaction, b: PurchaseTransaction) -> bool: return a.sequence < b.sequence
	)
	return ring


## The standing template that dispatches next, or null when the ring is empty. This is the
## cursor into standing_ring() — the ring itself never reorders, this moves.
func standing_next() -> PurchaseTransaction:
	var dispatch_order: Array[PurchaseTransaction] = standing()
	return dispatch_order.front() if not dispatch_order.is_empty() else null


func is_empty() -> bool:
	return entries.is_empty()


## Why a queued purchase hasn't been dispatched yet. A blocked entry has to NAME what it
## is waiting on rather than just reading "waiting": the two blockers have completely
## different remedies (find energy vs. free up or build a producer), and a queue that holds
## resources without saying why is the failure mode this whole readout exists against.
enum Blocker {
	## Dispatchable as far as the queue is concerned — it is only waiting its turn.
	NONE,
	## The commander can't pay for it yet.
	UNAFFORDABLE,
	## Every eligible producer is busy or still under construction.
	NO_FREE_PRODUCER,
}


func blocker_for(a_transaction: PurchaseTransaction) -> Blocker:
	if a_transaction == null or a_transaction.is_settled():
		return Blocker.NONE
	# Producer availability is asked of FUNDED entries too. Since purchases are charged at
	# request time (see _charge_on_submit), the normal state of a unit waiting for a busy
	# barracks is PAID-and-waiting — gating this on is_pending() would report such an entry as
	# unblocked and leave the readout silent about the only thing actually holding it up.
	if (
		a_transaction.kind == PurchaseTransaction.Kind.TRAIN
		and _free_producer(a_transaction) == null
	):
		return Blocker.NO_FREE_PRODUCER
	if a_transaction.is_pending() and not a_transaction.can_fund():
		return Blocker.UNAFFORDABLE
	return Blocker.NONE


## How many queued purchases could still land on `a_producer`. A structure with pending
## work isn't idle even though it isn't training anything yet, so the "select an idle
## producer" HUD command and the bot's production manager both consult this before
## treating a building as wasted throughput.
## Whether a BUILD purchase for `a_id` is still queued. Read by
## Commander.has_incoming_structure, which decides whether a downstream piece whose
## prerequisite is missing may nevertheless be ordered (see get_blocking_need).
func has_pending_build(a_id: StringName) -> bool:
	for transaction: PurchaseTransaction in entries:
		if transaction.kind == PurchaseTransaction.Kind.BUILD and transaction.type == a_id:
			return true
	return false


## Whether a TRAIN purchase for `a_id` is still queued. Read by Commander.is_research_taken, so
## an upgrade waiting in the queue cannot be ordered a second time.
func has_pending_train(a_id: StringName) -> bool:
	for transaction: PurchaseTransaction in entries:
		if (
			transaction.kind == PurchaseTransaction.Kind.TRAIN
			and transaction.type == a_id
			and not transaction.is_settled()
		):
			return true
	return false


func pending_count_for(a_producer: Actor) -> int:
	var count: int = 0
	for transaction: PurchaseTransaction in entries:
		if (
			transaction.kind == PurchaseTransaction.Kind.TRAIN
			and transaction.candidate_producers().has(a_producer)
		):
			count += 1
	return count


#endregion

#region Ticking
## What happened when the queue tried to fulfil an entry, and — crucially — whether the
## entries BEHIND it have to wait.
##
## Head-of-line blocking is deliberate, but only for the blocker it was reasoned about.
## The rule is: **an entry blocks the queue only while it waits for something an entry
## behind it could consume.**
##
##   * ENERGY is fungible and shared. Letting a cheap purchase behind an expensive one spend
##     the energy it is saving for would starve it indefinitely, which is exactly the "order
##     of intent" the queue exists to be. WAIT_FUNDS therefore stops the scan.
##   * PRODUCER CAPACITY is not. An entry is producer-blocked precisely when none of its
##     candidates is free — so any producer another entry can dispatch to is, by
##     definition, not one this entry could have taken. Nothing that passes it can delay
##     it, and when a candidate frees up the next scan reaches it first (the scan always
##     restarts from the front, which is what keeps FIFO intact within a contention set).
##
## WAIT_PRODUCER used to stop the scan too, and that was the bug: two units queued at one
## barracks left the second waiting on the barracks, and a BUILD behind it — needing no
## producer at all, with the energy already banked and idle builders standing at the site —
## waited on that. Cancelling the second unit was the only way to release it.
##
## The trade-off taken knowingly: a purchase that passes a producer-blocked entry may spend
## energy that entry wanted, so the blocked entry can go on to wait for funds once its producer
## frees. That state is visible (`blocker_for`, and the rail's glyph) rather than silent, and
## it is the lesser of the two — the alternative reserves energy for work that cannot start,
## which drains the treasury for a queue of units one building will take minutes to make.
enum DispatchResult {
	## Dispatched, or dead and to be dropped — either way the queue moves past it.
	ADVANCE,
	## Viable, but no candidate producer is free. Skipped; does not hold up the queue.
	WAIT_PRODUCER,
	## Viable, but not yet affordable. Holds the queue, deliberately.
	WAIT_FUNDS,
}


## Advance the queue. Walks entries in tier order, dispatching what it can, skipping past
## what is only waiting on a producer, and stopping at the first entry that cannot be paid
## for yet.
func tick() -> void:
	_prune()

	var standing_dispatches: int = 0
	var index: int = 0
	## Set once a one-off entry has been passed over without dispatching. The standing tier
	## runs only when the one-off tier is genuinely EMPTY — a standing entry is meant to soak
	## income nothing else wants, so it must not spend energy a queued one-off is still owed,
	## even one that is only waiting for a building to free up.
	var one_off_outstanding: bool = false
	# Bounded: every iteration either removes an entry, advances the index, or returns, and
	# the index only grows while `entries` only shrinks. The extra allowance covers the
	# standing rotations, which remove and re-insert without advancing the index.
	var budget: int = entries.size() + MAX_STANDING_DISPATCHES_PER_TICK
	while budget > 0 and index < entries.size():
		budget -= 1
		var transaction: PurchaseTransaction = entries[index]
		if transaction.standing:
			if one_off_outstanding or standing_dispatches >= MAX_STANDING_DISPATCHES_PER_TICK:
				return
			# The template stays queued and rotates to the back of its tier, so the standing
			# entries keep re-issuing in order for as long as income allows. A copy is what
			# actually gets dispatched.
			if _dispatch(transaction.clone()) != DispatchResult.ADVANCE:
				return
			standing_dispatches += 1
			entries.remove_at(index)
			# Keep the original sequence: this template is already in the ring, and its
			# submission order is what the HUD sorts the standing tier back into.
			_insert(transaction, false)
			continue
		match _dispatch(transaction):
			DispatchResult.ADVANCE:
				entries.remove_at(index)
			DispatchResult.WAIT_PRODUCER:
				one_off_outstanding = true
				index += 1
			DispatchResult.WAIT_FUNDS:
				return


## Try to fulfil `a_transaction`, reporting what the queue should do next — see
## DispatchResult, which is where the two WAIT reasons are distinguished and why.
func _dispatch(a_transaction: PurchaseTransaction) -> DispatchResult:
	match a_transaction.kind:
		PurchaseTransaction.Kind.TRAIN:
			if a_transaction.candidate_producers().is_empty():
				# Every structure that could have made this is gone — drop the purchase
				# rather than block the queue on something nothing can fulfil.
				a_transaction.cancel()
				return DispatchResult.ADVANCE
			var producer: Actor = _free_producer(a_transaction)
			if producer == null:
				# Candidates exist but none is free: still under construction, or already
				# building its one unit. The purchase waits — that wait is what replaced the
				# per-structure queues — but the queue behind it does NOT.
				return DispatchResult.WAIT_PRODUCER
			# Already paid for in the normal case — _charge_on_submit took the money at request
			# time. Funding here covers the two that reach dispatch still PENDING: a requisitioned
			# purchase that was unaffordable when ordered, and a standing template's clone.
			if not a_transaction.is_funded():
				if not a_transaction.can_fund():
					return DispatchResult.WAIT_FUNDS
				a_transaction.fund()
			# The job carries the player's own orders for this purchase, and NOTHING otherwise —
			# an empty chain is what tells _spawn_unit to read the producer's rally as it stands at
			# the moment the unit appears.
			producer.production.enqueue(
				a_transaction.creation_time,
				a_transaction.tool.packed_scene,
				a_transaction.type,
				a_transaction.player_commands,
				a_transaction
			)
			a_transaction.consume()
			return DispatchResult.ADVANCE
		PurchaseTransaction.Kind.BUILD:
			if a_transaction.is_abandoned():
				a_transaction.cancel()
				return DispatchResult.ADVANCE
			if not a_transaction.is_funded():
				if not a_transaction.can_fund():
					return DispatchResult.WAIT_FUNDS
				a_transaction.fund()
			# Reserve only. The builder consumes this when it lays the foundation, and
			# releasing the last Build command without that refunds it. A build needs no
			# producer, so it is never WAIT_PRODUCER — which is the whole point of the skip:
			# a build has no business waiting on a barracks.
			return DispatchResult.ADVANCE
	return DispatchResult.ADVANCE


## An eligible producer that can start this purchase RIGHT NOW: finished building, and
## not already training something. Ties go to the earliest in the transaction's producer
## list (the selection order), so a selection of idle strongholds fills in that order as
## each successive purchase sees the previous one busy. Null when every candidate is
## occupied or unfinished — "wait", not "give up".
## A producer that could START this purchase right now. "Free" is two questions, not one:
## it must not already be building something, and — for an aircraft that lives on a pad —
## it must have a pad to put the result on. An airfield with all four spaces occupied is
## busy in exactly the way a barracks mid-job is busy, so the purchase waits here rather
## than being refused when the player asked for it.
func _free_producer(a_transaction: PurchaseTransaction) -> Actor:
	var tool: Tool = (
		a_transaction.tool if a_transaction.tool != null else Tool.for_id(a_transaction.type)
	)
	for producer: Actor in a_transaction.ready_producers():
		if producer.production.is_free() and Train.has_free_pad_for(producer, tool):
			return producer
	return null


## Drop transactions that can no longer be fulfilled, so they neither block the head of
## the queue nor keep reserved resources tied up.
func _prune() -> void:
	for i: int in range(entries.size() - 1, -1, -1):
		if not _is_live(entries[i]):
			entries.remove_at(i)


func _is_live(a_transaction: PurchaseTransaction) -> bool:
	if a_transaction.is_settled():
		return false
	if a_transaction.is_abandoned():
		a_transaction.cancel()
		return false
	# Candidates, not free producers: a purchase waiting on a structure that is still under
	# construction or merely busy is alive, not orphaned.
	if (
		a_transaction.kind == PurchaseTransaction.Kind.TRAIN
		and a_transaction.candidate_producers().is_empty()
	):
		a_transaction.cancel()
		return false
	return true
#endregion
