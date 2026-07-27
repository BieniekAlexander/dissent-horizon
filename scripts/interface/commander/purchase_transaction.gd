class_name PurchaseTransaction
extends RefCounted

## One PURCHASE the commander has committed to: a unit to train or a structure to
## place, together with the energy/dominion it costs and the producers that may fulfil
## it. Transactions live in the commander's ProductionQueue (see production_queue.gd)
## until the commander can afford them — a purchase is never rejected for lack of
## resources, it waits.
##
## Cost is SNAPSHOT at construction from the commander's technology_mapping (or given
## explicitly, for ad-hoc prices like the safehouse conversion). Infrastructure is deliberately
## NOT part of a transaction: it is upkeep, adjusted when things are built or lost, and
## never blocks a purchase. A purchase costs energy OR dominion, never both, but both are
## carried so the two paths need no special-casing.
##
## Lifecycle:
##   PENDING  — queued, not yet affordable (nothing has been deducted)
##   FUNDED   — the cost has been deducted from the commander and is RESERVED for this
##              purchase. A TRAIN transaction is enqueued on its producer in the same
##              step and goes straight to CONSUMED; a BUILD transaction sits FUNDED
##              while its builder walks to the site.
##   CONSUMED — the purchase has been handed to the thing that produces it: a producer
##              has started training it, or a builder has laid the foundation.
##   COMPLETED — the thing bought EXISTS. Terminal, and reached through complete(), which
##              emits `fulfilled` first so anything waiting on this purchase hears about
##              it before the transaction is let go.
##   CANCELLED — dropped before completion; any reserved cost was refunded. Terminal.

#region Constants
enum Kind {
	## Training a unit at a Production structure.
	TRAIN,
	## Placing a structure with a builder unit.
	BUILD,
}

enum State { PENDING, FUNDED, CONSUMED, CANCELLED, COMPLETED }

## What a queued entry does when a precondition it needs isn't met yet — today that
## precondition is affordability, but `locked` (a missing prerequisite structure) is
## another, and once the policy is a FIELD on the entry rather than a mode read at issue
## time, "queue this build until the tech structure finishes" is the same mechanism.
##
##   REJECT — refuse the order outright.
##   WAIT   — queue and fulfil when the precondition is met ("spend when you can").
##
## The additive modifier, read at issue time (RTSController._purchase_defers), is what picks between them, per
## purchase, at issue time.
##
## **The policy decides what happens when you CAN'T afford it, and nothing else.** An
## affordable purchase is debited at REQUEST time either way — see
## ProductionQueue._charge_on_submit — so the modifier never delays a purchase you could
## already pay for; it only adds the ability to order one you can't. Deferring the debit for
## affordable purchases is what made every entry behave like a requisition regardless of the
## mode: each new order checked against energy an earlier queued order had already spoken for,
## so the same 150 energy could be committed without limit.
##
## STANDING templates are the exception and are debited per ISSUANCE, at fulfilment. A
## template re-issues forever, so there is no bounded amount to charge up front, and
## charging as it fires is exactly what lets it soak resources that would otherwise float.
enum FailurePolicy { REJECT, WAIT }
#endregion

#region Signals
## The single fulfilment choke point: emitted once, from complete(), with the thing this
## purchase bought — the trained unit, or the structure the builder laid down. "A unit
## spawned from transaction T" has to be an OBSERVABLE event rather than a spawn call
## buried inside the producer, because that is where a handle (a command issued against a
## unit that doesn't exist yet) would bind. Nothing binds here today; the event exists so
## that when something does, the transaction doesn't have to be restructured for it.
signal fulfilled(transaction: PurchaseTransaction, product: Node)
#endregion

#region Properties
## Monotonic, unique, and never reused. The queue is addressable BY ID rather than by
## position, which is what lets one transaction refer to another (a command attached to a
## unit that is still being trained names the transaction producing it). Positions shift
## every time anything ahead is dispatched or cancelled, so they can't carry a reference.
static var _next_id: int = 1
var id: int = 0

var kind: Kind
var commander: Commander

## The piece id being purchased, and the Tool that carries its PackedScene.
var type: StringName = &""
var tool: Tool = null

## Snapshot cost. Infrastructure is excluded by design (see the class doc).
var energy_cost: int = 0
var dominion_cost: int = 0

## Training duration in ticks, snapshot alongside the cost so the job enqueued on
## fulfilment matches what the purchase was priced against.
var creation_time: int = 0

var state: State = State.PENDING

#region Entry attributes
## The three things that distinguish one queue entry from another. They used to be two
## separate queues plus a global mode; carrying them as fields on the entry is what
## collapses the immediate queue and the repeating ring into one structure.

## STANDING entries are re-enqueued at the tail on completion instead of being consumed,
## so they re-issue forever and idle income always has somewhere to go. They are also the
## LOWER of the queue's two tiers, always: a player who queues five tanks and one standing
## scout does not see the scout until the tanks are done. That starvation is the feature —
## a standing entry runs only when nothing else wants the producer, which is why the field
## is called `standing` and not `repeat` (a repeat implies a timer, and would mislead).
var standing: bool = false

## What to do when a precondition isn't met yet — see FailurePolicy. Stamped from the
## additive modifier held when the purchase is issued.
var on_precondition_failure: FailurePolicy = FailurePolicy.WAIT

## Whether cancelling returns the cost. Refunds are ALWAYS FULL — cancelling refunds the
## entire cost regardless of progress, which is simpler than any percentage rule and hard
## to abuse when the unit does not exist until complete. The flag is carried so
## cancellation never has to ask which mode created the entry; it is the policy hook, not
## the record of what was taken. What was actually taken is `state == FUNDED`, which is
## why a WAIT-mode BUILD still refunds its reservation when the order is abandoned.
var refund_on_cancel: bool = true
#endregion

## Order within a tier, assigned by the queue on submission. Strict FIFO within a tier
## means the pair (tier, sequence) totally orders the queue — and it has to be a sequence
## rather than a priority, because a heap over equal priorities is NOT stable and would
## scramble submission order. Arbitrary priorities are never wanted; only the two tiers.
var sequence: int = 0

## What this purchase is waiting on, as a first-class edge list. EMPTY today — the only
## dependency the queue expresses is "no eligible producer yet", which falls out of the
## dispatch filter rather than being written down here. It exists now because adding the
## second kind of edge later should be a variant rather than a schema change:
##
##   * PREDICATE edges ("some completed Lab exists") are satisfied by GAME STATE, not by a
##     particular transaction. They track a witness but must re-resolve rather than
##     cascade when it is cancelled — otherwise cancelling one Lab would abort builds a
##     second, already-finishing Lab has legitimately unlocked.
##   * IDENTITY edges ("my actor is the output of that transaction") do cascade, because
##     aborting the parent makes the child meaningless.
var dependencies: Array = []

## TRAIN only — the DISPATCH FILTER: the production structures this purchase may be
## fulfilled at, seeded from the selection that issued it. Dispatch hands the job to
## whichever of them is free first (see ProductionQueue._free_producer).
##
## **An EMPTY filter means every applicable structure**, not "none" — a purchase queued
## with nothing selected is eligible at anything the commander owns that can make it. So
## the filter is a genuine restriction: present because a purchase may want to EXCLUDE a
## producer (one under attack, one being kept free), not because a purchase has to name
## its producers to be dispatchable.
##
## The distinction matters for the rally scopes too: broadening a rally reaches every
## pending transaction whose filter admits a selected structure, and only a transaction
## deliberately fenced to a DIFFERENT producer is out of reach.
var dispatch_filter: Array[Commandable] = []

## THE ORDERS THE PLAYER AIMED AT THIS PURCHASE — given by selecting the pending entry on the
## production rail and issuing a command to it. The unit does not exist yet, so nothing acts
## on them; they are replayed the moment it does.
##
## **THE ONLY THING THIS PURCHASE CARRIES ABOUT WHERE ITS UNIT GOES**, and empty for almost
## every purchase. A producer's RALLY is deliberately not captured here — it is read off the
## structure when the unit spawns (`Production._spawn_unit`), so changing a rally re-aims
## every unit still queued behind it. See
## gdd/systems/commands/construction.md §The rally is read at SPAWN.
##
## So the two statements never have to be merged: a unit follows its producer's rally UNLESS
## the player aimed this purchase somewhere, in which case that is what it does. Keyed by
## nothing, because whichever producer takes the job the order was about the unit.
var player_commands: Array[MoveCommand] = []

## BUILD only — how many live Build commands still reference this transaction. Every
## builder in a multi-select build order holds the SAME transaction, so the structure
## is paid for once no matter how many units walk to the site. When the last holder
## goes away (order cancelled, builders killed, replaced by another command) without
## the purchase having been consumed, the reserved cost is refunded.
var _holders: int = 0
var _ever_held: bool = false

## BUILD only — the blueprint raised at the site when the order was issued (see
## Commandable.plan_construction). It is a real, selectable node, so its lifetime has to
## end somewhere: this purchase owns it. consume() hands it over to the builder that
## lays it down; cancel() — an abandoned order, a pruned queue, a refund — frees it, and
## any unit purchases queued against that blueprint lose their only producer and are
## refunded in turn by ProductionQueue's prune.
var planned_structure: Commandable = null
#endregion

#region Construction
## A purchase priced from the commander's technology_mapping — the normal path for
## anything with a gdd doc (every trainable unit and buildable structure).
static func for_tool(
	commander: Commander,
	kind: Kind,
	tool: Tool
) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.new()
	transaction.id = _take_id()
	transaction.commander = commander
	transaction.kind = kind
	transaction.tool = tool
	transaction.type = tool.type if tool != null else &""
	var spec: TechnologySpec = commander.technology_mapping.get(transaction.type) \
		if commander != null else null
	if spec != null:
		transaction.energy_cost = spec.energy_cost
		transaction.dominion_cost = spec.dominion_cost
		transaction.creation_time = spec.creation_time
	return transaction

## A purchase with an AD-HOC price — one that isn't a technology_mapping entry, such as
## the safehouse conversion's flat energy cost.
static func for_cost(
	commander: Commander,
	kind: Kind,
	tool: Tool,
	energy_cost: int,
	dominion_cost: int = 0
) -> PurchaseTransaction:
	var transaction := PurchaseTransaction.new()
	transaction.id = _take_id()
	transaction.commander = commander
	transaction.kind = kind
	transaction.tool = tool
	transaction.type = tool.type if tool != null else &""
	transaction.energy_cost = energy_cost
	transaction.dominion_cost = dominion_cost
	return transaction

## A fresh PENDING copy of this transaction, sharing its cost, type and producers, with
## an id of its own. A STANDING entry re-issues itself this way: the queued entry stays a
## template and each pass dispatches a new copy of it.
##
## The copy is deliberately NOT standing. The template is the thing that repeats; the copy
## is one ordinary purchase it produced, and a copy that repeated in its own right would
## double the entry every pass.
func clone() -> PurchaseTransaction:
	var copy := PurchaseTransaction.new()
	copy.id = _take_id()
	copy.commander = commander
	copy.kind = kind
	copy.tool = tool
	copy.type = type
	copy.energy_cost = energy_cost
	copy.dominion_cost = dominion_cost
	copy.creation_time = creation_time
	copy.on_precondition_failure = on_precondition_failure
	copy.refund_on_cancel = refund_on_cancel
	copy.dispatch_filter = dispatch_filter.duplicate()
	# Shared, not re-snapshotted: a standing template keeps re-issuing the orders the player
	# aimed at it. The chains are templates and every spawned unit gets its own copies (see
	# Production._spawn_unit), so sharing them across passes is safe.
	copy.player_commands = player_commands.duplicate()
	return copy

static func _take_id() -> int:
	var next: int = _next_id
	_next_id += 1
	return next
#endregion

#region Ordering
## Which of the queue's two tiers this entry sits in. Non-standing entries always outrank
## standing ones; within a tier the order is strict FIFO by `sequence`. Lower sorts first.
func tier() -> int:
	return 1 if standing else 0
#endregion

#region Funding
## True when the commander can pay for this purchase right now. Only the spendable
## pools are consulted — tech prerequisites are enforced when the order is ISSUED
## (see Build/Train.meets_precondition); queuing can wait out a resource shortfall,
## not a missing structure.
func can_fund() -> bool:
	if commander == null:
		return false
	return commander.energy >= energy_cost and commander.dominion >= dominion_cost

## Deduct the cost and reserve it for this purchase. Caller must have checked can_fund().
func fund() -> void:
	if state != State.PENDING:
		return
	commander.add_energy(-energy_cost)
	commander.add_dominion(-dominion_cost)
	state = State.FUNDED
	# The blueprint stops being drawn as merely-queued the moment its cost is reserved.
	# Done here rather than in the queue because this is the ONE place the money is
	# committed, whichever path got us here — a same-frame dispatch or a shortfall waited
	# out over many ticks.
	if planned_structure != null and is_instance_valid(planned_structure):
		planned_structure.set_awaiting_funds(false)

## Mark the reserved cost as spent — the purchase has been handed to whatever produces
## it (a Production queue, or a structure actually placed on the map). Terminal: no
## refund can follow.
func consume() -> void:
	if state == State.FUNDED:
		state = State.CONSUMED
	# The blueprint has become the real structure — it outlives this purchase now, so
	# drop the reference rather than leaving cancel() able to free a placed building.
	planned_structure = null

## Retire this purchase: the thing it bought now EXISTS. The completion path, rather than
## the transaction simply being dropped at fulfilment — `fulfilled` fires before the state
## goes terminal, so anything holding this transaction is told about the product while the
## transaction is still there to be asked about it.
##
## Called from the one place each kind of purchase actually produces something: a producer
## finishing a unit (Production._spawn_unit), and a builder laying a foundation
## (Build._place_structure).
func complete(a_product: Node = null) -> void:
	if state == State.CANCELLED or state == State.COMPLETED:
		return
	fulfilled.emit(self, a_product)
	state = State.COMPLETED
	planned_structure = null

## Drop this purchase, returning any reserved cost to the commander. Safe to call more
## than once and on an already-completed transaction (a no-op then).
##
## Refunds are always FULL (see refund_on_cancel), and are owed only for what was actually
## taken: a FUNDED purchase reserved its cost, a PENDING one never had anything deducted,
## so a wait-mode entry that never got funded cancels for free with no special case.
##
## A refund owed to a commander that no longer exists is owed to nobody. That only happens at
## teardown: commanders are freed one after another, and a unit held in a LATER commander's
## garrison releases its build order after its own commander is gone.
func cancel() -> void:
	if state == State.FUNDED and refund_on_cancel and is_instance_valid(commander):
		commander.add_energy(energy_cost)
		commander.add_dominion(dominion_cost)
	if state == State.PENDING or state == State.FUNDED:
		state = State.CANCELLED
	discard_planned_structure()

## Take down the blueprint this purchase raised, if it hasn't been placed. Safe to call
## repeatedly. Called on cancel, and available to anything that abandons a build order
## before a builder reaches the site.
func discard_planned_structure() -> void:
	# Untyped: at teardown the blueprint may already be freed, and assigning a freed object
	# to a typed local errors before the validity check below could run.
	var blueprint: Variant = planned_structure
	planned_structure = null
	if is_instance_valid(blueprint) and (blueprint as Commandable).is_planned:
		(blueprint as Commandable).queue_free()

func is_pending() -> bool:
	return state == State.PENDING

func is_funded() -> bool:
	return state == State.FUNDED

## True once the queue has no further business with this purchase — it has been handed to
## a producer, finished, or dropped. What distinguishes CONSUMED from COMPLETED is that
## the thing bought does not exist yet at CONSUMED; both are past the queue.
func is_settled() -> bool:
	return state == State.CONSUMED or state == State.CANCELLED or state == State.COMPLETED

func is_cancelled() -> bool:
	return state == State.CANCELLED
#endregion

#region Producers (TRAIN)
## The producers that could still fulfil this purchase EVENTUALLY: alive and able to
## train the type. Deliberately includes structures still under construction — a unit
## ordered at a half-built barracks waits for it to finish rather than being dropped.
## A transaction with no candidates left is dead (see ProductionQueue), so a queued unit
## doesn't outlive every building that could have made it.
##
## An empty dispatch_filter resolves against everything the commander owns, and does so
## LIVE rather than being expanded once at submission: a barracks finished after the order
## was given is a legitimate producer for it, and a purchase is orphaned only when the
## commander genuinely owns nothing that could ever make the thing.
func candidate_producers() -> Array[Commandable]:
	var out: Array[Commandable] = []
	# Validity is checked on the raw element, BEFORE it is typed: a freed instance still sits
	# in the filter until something prunes it, and coercing one to Commandable is itself an
	# error — so `for producer: Commandable in ...` would fail before reaching the check.
	for candidate: Variant in _eligible_producers():
		if not is_instance_valid(candidate):
			continue
		var producer := candidate as Commandable
		if producer != null and producer.production != null \
				and producer.production.can_produce(type):
			out.append(producer)
	return out

## The structures the filter admits, before the can-produce test: whatever it names, or
## every commandable the commander owns when it names nothing.
func _eligible_producers() -> Array:
	if not dispatch_filter.is_empty():
		return dispatch_filter
	return commander.owned_producers() if commander != null else []

## Whether the unit this purchase bought does not exist YET — waiting in the queue, funded,
## or actively being built by a producer. The window in which a phantom is selectable and
## orderable, and it deliberately runs all the way to the moment the unit appears.
##
## CONSUMED is in it, which is the whole point: a purchase handed to a producer has left the
## queue and is being trained, and that is exactly when a player watching the progress bar
## reaches for it. Stopping at FUNDED made the training unit the one thing on screen that
## could not be ordered.
##
## CANCELLED and COMPLETED are out — nothing is coming, or it has already arrived and is a
## unit you select in the world like any other.
func awaits_its_unit() -> bool:
	return state == State.PENDING or state == State.FUNDED or state == State.CONSUMED


## Aim an order at the unit this purchase will produce. `a_replace` drops whatever was
## already queued, which is what a plain right-click means everywhere else; false appends,
## which is what the additive modifier means everywhere else.
##
## Refused once the unit EXISTS (or is never coming): past that an order given here would
## silently never arrive, and the unit is one you order in the world instead. The caller sees
## false and can say so.
func queue_player_command(a_command: MoveCommand, a_replace: bool) -> bool:
	if a_command == null or not awaits_its_unit():
		return false
	if a_replace:
		player_commands.clear()
	player_commands.append(a_command)
	return true


## The candidates that can take the job RIGHT NOW — those that have finished
## construction. Dispatch only ever hands a job to one of these; an empty result with a
## non-empty candidate list means "still building, wait", not "give up".
func ready_producers() -> Array[Commandable]:
	var out: Array[Commandable] = []
	for producer: Commandable in candidate_producers():
		if producer.is_built:
			out.append(producer)
	return out
#endregion

#region Holders (BUILD)
## Register a live Build command against this purchase. Called from MoveCommand._init
## for any command whose message carries a transaction.
func retain_holder() -> void:
	_holders += 1
	_ever_held = true

## Drop a live Build command. When the last one goes and the purchase was never
## consumed, its reserved cost is refunded — this is what returns the energy when a
## builder is killed or re-ordered before it lays the foundation.
func release_holder() -> void:
	_holders -= 1
	if _holders <= 0 and not is_settled():
		cancel()

## True once every Build command that referenced this purchase is gone. False before
## the first one registers, so a transaction dispatched in the same frame it was
## submitted (its commands not yet constructed) isn't mistaken for an abandoned one.
func is_abandoned() -> bool:
	return kind == Kind.BUILD and _ever_held and _holders <= 0
#endregion

#region Debug
func _to_string() -> String:
	return "PurchaseTransaction(#%d %s %s%s, energy=%d, dominion=%d, state=%d)" % [
		id, "TRAIN" if kind == Kind.TRAIN else "BUILD", type,
		" standing" if standing else "", energy_cost, dominion_cost, state
	]
#endregion
