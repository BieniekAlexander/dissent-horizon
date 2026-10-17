---
title: Production and economy
type: system-note
---

# Production and economy

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Commander and economy


`Commander` (`@tool`) tracks:
- `energy: int`, infrastructure (capacity/upkeep), `dominion: int`
- `technology_mapping: Dictionary[StringName piece id → TechnologySpec]` — LOADED at startup from the generated `resources/generated/technology.json` (edit the gdd docs + re-run the spec importer, not the code). Ability gates ride in the same map under int `Ability.Type` keys.
- `structure_type_map: Dictionary[StringName piece id → Set]` — all owned structures of each id; entries appear lazily (use `has_built_structure` / `_structures_of`)

`proc_technology()` must be called whenever structures are added or removed (handled automatically via `add_structure` / `remove_structure`).

`TechnologySpec.get_unmet_need(commander)` returns the first blocking reason (NOT_ENOUGH_ENERGY, MISSING_STRUCTURE, etc.). `MoveCommand.unmet_need_to_precondition` maps those to `PreconditionFailureCause` values. Note the split introduced by the production queue: `Commander.get_blocking_need()` / `can_order()` filter the *resource* reasons out of that result, because a purchase the commander can't afford is QUEUED rather than refused. Only a tech reason (MISSING_STRUCTURE) still fails a command precondition.

### Global production queue

Every PURCHASE — training a unit, placing a structure — goes through the buying commander's `ProductionQueue` (`scripts/interface/commander/production_queue.gd`), ticked once per physics frame from `Commander._physics_process`. Nothing is refused for lack of resources any more; it waits. A purchase is one `PurchaseTransaction` (`purchase_transaction.gd`) carrying a cost snapshot (energy OR dominion — never both, and never infrastructure, which is upkeep and never blocks a purchase) plus a PENDING → FUNDED → CONSUMED/CANCELLED state.

**ONE queue, two tiers.** `entries` is a single list kept in dispatch order; what used to be two structures selected between by a held modifier is now FLAGS on the entry:
- `standing` — re-enqueued at the tail on dispatch instead of being consumed, so it re-issues forever and idle income always has a sink. Standing entries are the LOWER tier: every non-standing entry outranks every standing one, whenever it was submitted. TRAIN-only (a repeating build has no meaningful site, so `submit` demotes one). One standing dispatch per tick. Set by RIGHT-CLICKING the grid button.
- `to_front` — where in its OWN tier the entry lands (Shift at purchase time). Front is front of the tier; it can never promote a standing entry past a one-off.
- `on_precondition_failure` — REJECT (refuse the order) or WAIT (queue it). Stamped from the additive modifier held when the purchase is issued. Affordability is one precondition among several — once the policy is a field, "queue this build until the tech structure finishes" is the same mechanism.

**Debit timing: an affordable purchase is charged at REQUEST time, modifier or not.** `ProductionQueue._charge_on_submit` funds it on submission, whether or not a producer is free — so a unit queued behind a busy barracks is PAID and waiting, not promised. The modifier therefore decides only what happens when you *can't* afford something; it never delays a purchase you could already pay for.

**But request-time charging still obeys QUEUE ORDER.** `_charge_on_submit` skips the debit when any entry ahead is still unpaid (`_unfunded_entry_ahead_of`) — otherwise it quietly repealed the head-of-line blocking `tick()` exists to enforce, because the money was gone before the scan ever ran. That let an entry behind an unaffordable one pay for itself first; the case that makes it plainly wrong is a unit ordered at a blueprint whose own BUILD is still unfunded, since that unit CANNOT be produced until the build completes, so its reserved energy became dead capital starving the very structure it was waiting for. `tick()` runs immediately after and funds entries in order anyway, so nothing is lost by deferring to it. The check asks `is_pending()`, not `blocker_for()`: an entry that is FUNDED and only waiting on a producer has already taken its money and reserves nothing further — exactly the case `DispatchResult.WAIT_PRODUCER` is documented to let others past.

**Ordering a unit at an UNFUNDED blueprint is itself a deferral**, and a deeper one than an unaffordable price — nothing about it can happen until that structure is funded, built and finished. `Train.meets_precondition` refuses it with no modifier held (gating on `Actor.awaiting_funds`, the same flag that draws the blueprint darker) and queues it with one. A blueprint whose build IS funded stays orderable either way: queuing units at a building the builder is still walking to is the deliberate feature.

That is the fix for a real bug: the debit used to happen at DISPATCH, so a purchase that couldn't start yet was never charged and the next order checked against energy an earlier one had already spoken for. With 150 energy and 75-energy units you could order two — one charged, one queued — and then a third, and a fourth, without limit. Every one-off behaved like a requisition regardless of the mode, which is exactly the distinction the mode exists to draw.

**STANDING templates are the exception and keep fulfilment-time debit**, charged per ISSUANCE. A template re-issues forever, so there is no bounded amount to charge up front — and charging as it fires is precisely what lets the ring soak resources that would otherwise float. Over-committing through the ring (cheap units eating the energy you were saving for a building) is a known, accepted pitfall: you have to opt into a standing order to reach it, and floating resources are the worse failure.
- `refund_on_cancel` — refunds are always FULL. The flag is the policy hook; what was actually taken is `state == FUNDED`.

Within a tier the order is strict FIFO by `sequence`. Ordering is maintained by insertion (`_insert`), never by sorting — a heap over equal priorities is not stable and would scramble submission order, and arbitrary priorities are never wanted.

**Head-of-line blocking is about ENERGY, not about everything.** An entry blocks the queue only while it waits for something an entry behind it could CONSUME. Waiting on energy blocks — energy is fungible, and a cheap purchase spending what an expensive one is saving for would starve it, which is what makes the queue an order of intent. Waiting on a free PRODUCER does not: an entry is producer-blocked exactly when none of its candidates is free, so any producer another entry can reach is one the blocked entry could not have used anyway, and nothing that passes it can delay it. FIFO within a contention set survives because `tick()` always rescans from the front, so the blocked entry is reached first the moment a candidate frees.

That split (`ProductionQueue.DispatchResult`) fixed a real bug: two units queued at one barracks left the second waiting on the barracks, and a BUILD behind it — needing no producer at all, energy banked, builders idle at the site — waited on that too. Cancelling the second unit was the only way to release it. The knowing trade-off is that a purchase passing a producer-blocked entry may spend energy that entry wanted, so it can go on to wait for funds once its producer frees; that state is visible via `blocker_for()` and the rail's glyph rather than silent, and the alternative (reserving energy for work that cannot start) drains the treasury for a queue one building will take minutes to make.

A one-off entry that has not dispatched — for EITHER reason — still holds off the standing tier: a standing entry is meant to soak income nothing else wants, so it must not spend energy a queued one-off is still owed. That starvation is the feature, and is why the name is `standing` rather than `repeat` — a repeat implies a timer.

Each transaction carries a stable, unique `id` and the queue is addressable by it (`find_by_id`), because positions shift under every dispatch and cancellation. `dependencies` is a first-class (today empty) edge list, and `fulfilled` is the single choke point announcing "the thing this purchase bought now exists" — emitted from `Production._spawn_unit` and `Build._place_structure` via `complete()`. None of those three has a consumer yet; they exist because retrofitting them is expensive and adding them now costs nothing.

`submit()` drains synchronously, so an affordable purchase with an empty queue is fulfilled in the frame it was ordered — the queue adds no latency to the normal case.

#### Requisition: the additive modifier, not a mode

Nothing is refused for lack of resources **only when the player has asked for that**, and
asking is holding `modifier_additive` as the order is issued: with it, an unaffordable
purchase is submitted and waits; without it, the purchase fails its precondition like any
other blocked order. The full rule, what it replaced (a sticky toggle on
`purchase_requisition`) and what was given up to free the key are in
[requisition-as-a-modifier](requisition-as-a-modifier.md). What is queue-side belongs here:

**It also waits out a missing PREREQUISITE — but only one that is already on its way.** In most RTS games a building cannot be ordered until its prerequisite stands, which means watching that prerequisite finish and only then clicking. Holding the modifier, the downstream building can be ordered while its dependency is still going up, and the builder walks to the site and waits there.

The distinction the feature turns on is `Commander.has_incoming_structure`: **"I have not built the war factory" is a refusal; "the war factory is going up right now" is a queue.** Without that line a player could order the entire tech tree from an empty base and watch nothing happen. Incoming means a blueprint, a structure placed and still building, or a BUILD purchase still in the queue — **all three, because a build passes through all three states and no one of them spans the trip.**

The BLUEPRINT check is what makes prerequisite CHAINS work, and it cannot come from the commander's structure registry: a planned structure is deliberately kept out of it (it contributes no infrastructure and is not a building the tech tree counts), so `Commander.has_planned_structure` scans the owned children instead. Without it a chain of A <- B <- C broke at C the moment B's purchase was FUNDED — which for an affordable order is the same tick it was made. B was then a blueprint standing on its site with a builder walking toward it, out of the queue and out of the registry, and reported as not coming at all. The symptom was precise and confusing: A then B could be ordered, B then C could not. `missing_prerequisites_are_incoming` requires ALL of them — a piece waiting on two buildings is only genuinely on its way once both are, and letting it through on one would strand a builder at a site indefinitely.

`Build.fulfill_action` then waits at the site exactly as it waits for funding, holding position until the prerequisites actually stand. That wait is **scoped to builds that went through the purchase pipeline** (`message.transaction != null`), the same distinction `_is_funded` draws: a directly-issued build — a scenario event, the bot's actuator, a test — never consulted the tech gate at order time either, and making it wait would strand orders that used to place immediately. The button tints amber rather than grey in this state, since clicking it queues rather than being refused. Tests: `tests/test_RequisitionPrerequisites.gd`.

The feature exists because the queue's strength is also its hazard — in a fast game a player can load it with commitments they never consciously made and lose track of what they have spent ahead. Supreme Commander is the cautionary case (its streaming economy is why SupCom 2 shipped without unaffordable queuing, then patched it back seven months later). Requiring a held key for it means a purchase only ever waits when the player asked for it to.

The plumbing is one flag with a permissive default:
- `CommandMessage.defer_if_unaffordable` (**defaults to `true`**) carries the reading. The controller stamps it every frame in `_process` and re-stamps in `process_command` / `issue_command_at_world_position`; `deep_copy` carries it, so every builder in a multi-select build order agrees.

#### Economy readouts

Three figures on `Commander`, and they PARTITION the economy — which is the whole point, since any overlap between them misleads in both directions:

| Figure | Reads | Covers |
| --- | --- | --- |
| `energy_committed()` / `dominion_committed()` | PENDING entries in the queue | what has been promised but not paid |
| `energy_collection_rate()` / `dominion_collection_rate()` | live `EnergyExtractor` / `DominionGenerator` components | steady income, per second |
| `energy_spend_rate()` | each producer's ACTIVE job, cost spread over its build time | what is being paid out right now |

Committed energy covers the queue side and spend rate covers the in-progress side, so a purchase leaves the first exactly when it enters the second. Deliberately **not** sampled from energy deltas over a rolling window: deriving from the components is exact and responds the instant an extractor is finished or destroyed. Blueprints are excluded — a plan neither collects nor spends. Faction-specific one-off acquisitions are out of scope; this is the STEADY rate, which is what a clearance estimate can be computed against.

Committed energy also fixes the mixed debit semantics above: a reject-mode purchase has already taken its energy out of the pool and a wait-mode one hasn't, so without a figure naming what is promised the resource display means different things depending on which mode made the entries behind it. `ProductionQueue.blocker_for()` is the matching legibility piece — a blocked entry NAMES what it is waiting on (energy, or a free producer), because the two have completely different remedies.

Each rate carries an ATTRIBUTION count, because "+14/s" is trivia and "+14/s · 4 extractors" is actionable. `energy_source_count()` counts over the same set `energy_collection_rate()` sums over, so the two can never disagree. Dominion's is faction-varying and lives on the generator SUBCLASS rather than on `Faction`, because that is where the mechanic already differs: `DominionGenerator.contributor_count()` returns `NO_ATTRIBUTION` by default (a flat rate has nothing feeding it), and `OccupantDominionGenerator` returns its prisoner head count.

**`dominion_collection_rate()` reads `DominionGenerator.payout()`, never the bare `dominion_rate` field.** The two agree for a flat generator (`payout()` IS `dominion_rate`), but `OccupantDominionGenerator` (the Colonial Compound) overrides `payout()` to scale with its LIVE occupant count — `dominion_per_unit * contributor_count()` — and leaves the inherited `dominion_rate` field at its unused script default. Reading the field directly reported a rate that never moved with how many prisoners were actually held: effectively always the class default, which read as "the Compound is already full" regardless of its true occupancy. `payout()` exists on the base class specifically so the HUD and the actual per-cycle `tick()` payout can never disagree about the number — see its own doc comment. Tests: `tests/test_EconomyReadouts.gd` §The Compound's rate follows LIVE occupancy, not the inherited flat default.

**A faction whose dominion is event-driven needs no special case.** Awarded for damage dealt rather than per tick, such a commander owns no `DominionGenerator` at all — so `dominion_source_count()` is 0, and the readout omits the rate line rather than printing a "+0/s" that asserts something false. An instantaneous rate sampled off combat damage would spike and flatline rather than describe anything, so not reporting one is the correct answer, and it falls out of the count.

`energy_clearance_seconds()` measures against NET income (collection minus what training already draws), and returns -1.0 when net income is non-positive — reported as "not clearing" rather than as an enormous number, since a commitment that is not being paid down at all is the state worth flagging. Tests: `tests/test_EconomyReadouts.gd`.

**Build preview instances**: `Commander.get_build_preview_instance(tool)` returns a cached, out-of-tree entity instance used for placement-preview art. These are **never added to the SceneTree** — they never trigger `_ready`, physics, fog visibility, or auto-init. They're freed in `Commander._notification(PREDELETE)`.

---

## Infrastructure, and what a shortfall costs

**"Infrastructure" is the power resource** — the C&C Power analogue: a commander builds
capacity and its buildings consume it, and running short is a penalty rather than a wall.

Each `Actor` carries ONE signed `infrastructure` int — positive provides capacity,
negative consumes it — and the commander tallies those into `infrastructure_provided` and
`infrastructure_required`. Every commander starts with `Commander.BASE_INFRASTRUCTURE`
capacity. It is UPKEEP, not a price: it never refuses a purchase (see
`Commander.is_deferrable_need`), it only makes the shortfall hurt afterwards.

**Any piece may carry it, not only structures.** Whether something contributes is its
`infrastructure` value, never whether it is a structure; the default is 0, so today only
structures author a non-zero value, but a unit that provides or draws infrastructure needs no
special case. A two-form piece therefore contributes in both of its forms.

**It counts while the piece is built and not merely planned**, for whoever owns it then.
`Actor._sync_infrastructure` is the one place that decides, and it remembers which
commander holds the credit so the debit reaches the same one:

- **Credited on FINISHING construction, not on starting it.** A foundation is not a working
  relay or a load-bearing upkeep, so a capture mid-build credits the piece to its finisher.
  A unit is built from the moment it exists.
- **Moved on ownership change**, and never moved for a piece still under construction.
- **Withdrawn when the piece leaves play**, including exits that are not deaths — a consumed
  captive, occupants killed with their host, an expiry — so the withdrawal runs when the
  object is freed as well as on death.

Tests: `tests/test_InfrastructureContribution.gd`, `tests/test_UnfinishedConstruction.gd`
§Infrastructure follows FINISHING, not starting.

### Insufficient infrastructure

`Commander.is_infrastructure_strained()` — upkeep exceeds capacity — has three effects,
and the first predates the other two:

1. **Production runs slow.** `Production.tick` applies a reduced rate while strained.
2. **Buildings lose their weapons.** `Actor.can_use_weapons` is false for a
   structure whose commander is strained, so defences go quiet.
3. **Buildings lose their abilities, active and passive alike.**
   `Abilities.is_operational` is false on one, which refuses `is_ready` and `spend` and is
   what turns off a positional passive like the Compound's Work Detail.

`Actor.is_unpowered()` is the single predicate all three read, and it is deliberately
narrow:

- **Only STRUCTURES go dark.** Strain is a fact about buildings drawing more than the
  network supplies; an army in the field does not stop shooting because a power plant was
  lost. A unit's own ability pool is untouched.
- **The building is otherwise unaffected.** It stands, holds its grid cells, is still a
  target, and still produces at the reduced rate. Going dark is what the shortfall costs;
  demolition is not.

**It is refused, never deferred.** A cast blocked this way reports
`PreconditionFailureCause.UNPOWERED` rather than `ABILITY_NO_CHARGES`, and the additive
modifier does not queue it — the two failures have different remedies, and only one of them
is cleared by waiting. The HUD says so with its own blocker and tint
(`CommandButtonState.Blocker.UNPOWERED` — see
[command card and hotkeys](../ux/ui/command-card-and-hotkeys.md) §What a darkened button
means). Tests: `tests/test_InfrastructureStrain.gd`.

---

## Debit timing: charging on submit

*Moved out of `production_queue.gd::_charge_on_submit`.*

This is what makes the affordability check honest. The debit used to happen at DISPATCH,
so a purchase that couldn't start yet was never charged, and the next order checked
against energy that was already spoken for: with 150 energy and 75-energy units you could order
two, see one charged and one queued, and then order a THIRD, and a fourth, forever. Every
request passed the same check against the same untouched 150. That made every one-off
behave like a requisition whether or not the modifier was held, which is precisely the
distinction the mode exists to draw.

STANDING templates are the deliberate exception and keep fulfilment-time debit. A
template is not a commitment to buy one thing — it is a standing instruction to buy
whenever there is spare income, re-issuing forever — so there is no bounded amount to
charge at request time. Charging per ISSUANCE is what lets the ring soak floating
resources, which is its whole purpose.
Charging at request time must still respect the queue's ORDER, or it quietly repeals the
head-of-line blocking tick() exists to enforce: the money is gone before the scan runs, so
WAIT_FUNDS never gets a say. That let a purchase behind an unaffordable one pay for itself
first — including a unit ordered at a blueprint whose own BUILD was still unfunded, which
is worse than out-of-order, because the unit CANNOT be produced until that build completes.
Its reserved energy became dead capital starving the very structure it was waiting for.

So: charge only when nothing ahead is still waiting to be paid for. tick() runs
immediately after this and funds entries in order anyway, so nothing is lost by deferring
to it — the affordability check stays honest (every request still debits when it legally
can), it just can no longer jump the queue.
