---
title: Bot standards
type: system-note
---

# Bot standards: the behaviours the bot is meant to express

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.*

Alex's standards for the CPU commander (chat, 2026-10-30), each read against what is built and
what the last ladder run shows the bot doing. A standard is a behaviour the bot should be able
to EXPRESS; each one below names the rule that would express it, where that rule lives today or
does not, the evidence from play, and the test that would pin it. The evidence is the choice and
action ledgers of `exec_h` (180 Colonial seats, 30 per tier pair, 2026-10-30;
[piece-usage-audit](piece-usage-audit.md) is the instrument) — measured before the
reachability fix and the three builds of the same day, so a count may already have moved.

Verdicts: **BUILT** (the rule exists and the ledger shows it acting), **PARTIAL** (a rule exists
and misses a case this standard names), **MISSING** (no rule; the ledger shows the behaviour
absent). Every PARTIAL and MISSING carries a `TODO` with its open questions; none is started
until Alex names it (~/.claude/CLAUDE.md §13.1).

## Macro

### M1 — The bot explores the whole tree it is offered

**Standard.** Over a corpus of matches every unit, structure, upgrade and sanction the faction
offers is bought somewhere, and when one never is, the reason is one of four with an owner:
not worth it (balance, or the scorer), cannot actuate, cannot signal, game bug.

**What exists.** The instrument is BUILT: `BotUsageLog` records every scored choice and every
order, `piece_usage.py` puts each piece in one of ten verdicts, and the four-cause table is
[piece-usage-audit](piece-usage-audit.md). "Does the bot know it is reasonable" is answered by
`CONSIDERED_NOT_CHOSEN` with its score ratio against the winner; "is the piece reasonable" is
then a balance question with the number attached.

**What the ledger shows (Colonials, `exec_h`).**

| piece | verdict | evidence |
|---|---|---|
| Recruit, Badger, Sloop, Matilda, Clipper, Drake, Sleeper, barracks, war factory, airfield, Compound, Watch Tower, Bombard, Operations Center | USED | fielded in every tier |
| Constable | USED, rare | 1,505 of 2,544 learned choices once offered; 20 fielded in 180 seats — offered seldom because the Academy (7 built) is behind the war factory |
| Academy (`cl_tech2`) | CONSIDERED_NOT_CHOSEN | chosen 326 of 15,675; the tech rung's margin against the best trainable unit |
| Operations Center (`cl_tech1`) | bought by the SIEGE rung, never by the tech rung | 0 of 38,626 tech-rung choices, 80 built: `_unlocking_structure_for` buys it as the Bombard's prerequisite |
| SAM | CONSIDERED_NOT_CHOSEN | 498 of 7,722; 6 built against ~300 enemy combat aircraft fielded ([bot-engagement-fixes](bot-engagement-fixes.md) §An unanswerable threat, TODO) |
| Avalanche | CONSIDERED_NOT_CHOSEN | 0 of 1,637 learned choices at 0.12 of the best — the model prices a support vehicle on no fight |
| Caravel, Reverence | never a candidate | unarmed utility types: wanted only by demand (`BotProduction._utility_demand_for`), and the demand never fired or was capped (M4, I1) |
| Annex, Supply Beacon, Storm Cell | NEVER_CONSIDERED | a structure a tech building unlocks scores nothing to the tech rung ([bot-architecture](bot-architecture.md) §The tech rung) |
| Cell Activation, Rapid Rearmament | CONSIDERED, value 0 | priced on fielded pieces (`BotResearch`); the Sleeper and the Drake are rarely fielded when the rung looks |
| Reinforced Hulls, Gun Drill | chosen 1,865 / 228 of ~11,000 / 2,280; 4 and 0 bought | chosen and then held by the margin or the reserve |
| Promotion, Scan, Gunship (IMPOSSIBLE only) | USED | 1,271 / 62 / 9 casts |

**Verdict: PARTIAL.** The instrument answers the question; the tree has three dark regions
with three causes — the support buildings (no rung values a structure for what it unlocks),
the synergy units (demand that does not fire, M4/I1), and the Academy (a margin on units alone).

> **TODO — the three dark regions of the Colonial tree.**
> - [ ] The support buildings: does the tech rung value a structure by the structures it
>   unlocks too, or do the support buildings get a demand rule of their own (what work does
>   each do, and when does nothing owned do it)?
> - [ ] The Academy: is 1.3 the right margin for a tech building that unlocks a unit AND the
>   Storm Cell, or does the Constable need to be worth it alone (a balance question the ratio
>   0.99 says is close)?
> - [ ] Should `piece_usage.py` be run over every ladder batch and its table kept beside the
>   ladder report, so the dark regions are watched rather than found?

### M2 — Short-term army against long-term investment

**Standard.** The bot banks for an extractor, a tech building or an upgrade when the long
return beats more army now, and spends on army when it does not — one currency.

**What exists.** PARTIAL by design, and the design says so: three scales with no exchange rate
([macro-learning](macro-learning.md) §3 A state value is the PLANNED fix). What is built is a
set of RUNGS that each decide one trade: the income rung buys an extractor while the bot owns
fewer than its target and is safe enough (`BotEconomy._decide`, [bot-architecture](bot-architecture.md)
§The opening's income rung); the tech rung buys a building when its best unit beats the best
trainable by `tech_value_margin`; the research rung buys an upgrade when Σ (factor − 1) × the
fielded cost it touches clears the same margin; and `BotSavings` holds the bank for the best
of every manager's proposal so a dear purchase is reachable at all. The posture layer tilts
the whole ladder ([objective-selection](objective-selection.md): the commitment dial reads own
income against the enemy estimate).

**What the ledger shows.** The savings goal is honoured: 80 Operations Centers and 128 war
factories were bought in 180 seats. But the goal sits unbuilt for minutes when the economy's
spot search is budget-starved (7100: a war factory wanted and affordable from 150 s, placed
never; [bot-engagement-fixes](bot-engagement-fixes.md) §The objective nobody could reach), and
the hold is released under any answerable threat, so the bank drains into units in a long
fight.

**Verdict: PARTIAL.** Each trade has a rule; no rule compares the trades.

> **TODO — one currency for the three scales.** The approved shape is a learned state value
> (macro-learning.md §3). Until it exists, two cheaper things would make the rungs honest:
> - [ ] A spot search that survives a savings-goal flip and a budget share the economy is owed
>   in a built-up game (the 7100 finding).
> - [ ] Does the savings hold release under ANY answerable threat, or only one the bank's
>   goal would not itself answer (a SAM goal under aircraft is the counter-example)?

### M3 — Prerequisites of an answer

**Standard.** Believing an enemy threat the bot cannot yet produce the answer to, it buys the
chain that leads to the answer: the producer, the tech, then the unit.

**What exists (built 2026-10-31 on Alex's ruling of 2026-10-30: an unowned prerequisite is
part of the price).** One price for every purchase, per energy of the CHAIN
(`Bot.prerequisite_chain`, `Bot.chain_price_factor`; [bot-architecture](bot-architecture.md)
§Valuing a unit, and saving for it):

- Tech → unit: a unit behind a structure is a candidate at every producer, priced at its own
  cost plus every unowned prerequisite's, recursively; when it beats the trainable best by
  the tech margin, the chain's first link is the savings goal and the goal rung builds it,
  while the producer trains what it can under the claim.
- Tech → turret: the SAM behind a building the bot lacks is a defence candidate at its chain
  cost; the demand must clear the chain, and the first link goes up.
- Producer → unit: `producer_values` prices a producer by its locked units too, at their
  chain cost — a factory whose good unit sits behind tech2 scores it.
- The siege rung and the tech rung read the same chain: a tech candidate is credited with
  every unit whose chain passes through it, and a gun two links deep is started at the first.

Not expressed: a unit's PRODUCER is not in `required_structures`, so an airfield is not in
the Caravel's chain — the producer rung buys it on its units' value, with its own price in no
per-energy figure. Decided by cost alone; the margin stands in for build time (both open in
the architecture note's TODO under that section).

**Verdict: BUILT** as a rule; the ledger's reading waits on `exec_j`
([bot-roadmap](bot-roadmap.md) §Difficulty first).

> **TODO — measure it.** `exec_j`'s choice ledger: SAMs chosen and built under enemy aircraft
> with no factory standing (P4's time-to-first-answer), the Academy chosen by the tech rung at
> chain-priced Constables, and whether a goal rung build is ever refunded (P2).
> - [ ] Sim: a bot owning a barracks that believes three Clippers and no anti-air buys the
>   chain to one (SAM or airfield → Clipper) within N seconds — which answer should it prefer?

## Interactions

### I1 — Multi-unit operations: transport

**Standard.** Slow units with a long way to go are carried by a fast transport.

**What exists.** BUILT as a mechanism: `BotEscort` claims a transport for the squad with the
longest walk when the lift saves `EscortPolicy.MIN_SAVING_SECONDS` (8 s) at the carrier's
pace, and `EscortPolicy` runs load, fly, unload as a sequence read off the world each think
([squads-and-relations](squads-and-relations.md) §A multi-piece action). The transport is
WANTED by `_utility_demand_for` while `lift_wanted` and none is owned. Pinned by
`sims/bot/escort/lift_the_slow_squad` and `tests/test_BotEscort.gd`.

**What the ledger shows.** No Caravel was ever produced in 180 seats, so the escort never ran
in a match. The demand it depends on is capped by `utility_unit_cap` (1 at MEDIUM and HARD in
the ladder's draws, 3 by default), which builders and Stock Trucks already fill; and
`lift_wanted` needs a squad whose destination is far, which a MASS army at its station is not.

**Verdict: PARTIAL — built and starved.**

> **TODO — a transport the bot actually buys.**
> - [ ] Is the utility cap the right place to hold a transport, or is a transport a SQUAD
>   purchase (wanted by the military's squads, outside the utility count)?
> - [ ] Does `lift_wanted` read the right walk — the wave's march to its objective, not the
>   station — and does a wave WAIT for its lift (squads-and-relations.md §Relations, item 1,
>   PLANNED)?
> - [ ] Ladder check: Caravels produced per seat, and escort orders issued, in `exec_i`.

### I2 — Multi-unit operations: the Bombard and its spotters

**Standard.** A Bombard is bought when the bot can spot for it, Recruits spot for it, and
Spot is never used without a gun to use it.

**What exists.** BUILT: the siege rung wants a gun while an enemy structure is believed and a
mobile spotter is owned (`Bot.wants_siege_gun`); `BotAbilities` sends a spotter to call a
solution on the nearest believed structure only while a LOADED gun waits ("one spotter out per
loaded gun"), so Spot without a gun is not issued; the gun fires on its own at held or
spotted ground (`BotActuator.bombard`). Pinned by `sims/bot/siege/spot_for_the_gun`,
`tests/test_BotSiegeRung.gd`, `tests/test_BotBombardShot.gd`.

**What the ledger shows.** 22 Bombards built, 113 Spot orders, 28 bot-aimed shots across 180
seats; HARD fired 24 of the 28. The loop runs where it is bought; the Reverence is never
bought because a Recruit's Spot already counts as a mobile spotter.

**Verdict: BUILT.** What is not: the corollary's converse — Recruits valued MORE because a
gun stands (I3).

### I3 — The value of a purchase depends on what is owned

**Standard.** A Recruit is worth more beside a Bombard; a transport is worth more beside a
slow army; a unit worth having only beside another is priced beside it.

**What exists.** MISSING as a price, decided so: `Relation.value` is unbuilt and synergy pieces
are bought on DEMAND instead (Alex, 2026-10-10; [squads-and-relations](squads-and-relations.md)
§What a relation is worth). The read model is BUILT — `Relation.all()` knows `spotting_call`,
`spotting_range`, `transport` and `cover`, `Bot.providers_of` and `consumers_of` list the live
pairs — so the term can be computed; nothing reads it into a valuation. The combat model is
fitted on counts and has no pairwise own-side term either (macro-learning.md §1, TODO
"support and control").

**Verdict: MISSING, by an explicit decision that can now be revisited.**

> **TODO — a relation term in the purchase valuation.** `purchase_values_per_energy` already
> has one gate on the enemy side (`answerable_share`); the own side is the mirror: a
> consumer's value × (1 + Σ provider terms owned), a provider's value as the Σ of what it
> enables for owned consumers.
> - [ ] Per effect kind, as the approved shape names: ENABLES = the enabled action's value
>   (a shot's expected damage), MOVES = the consumer's cost × travel time saved, PROTECTS = ?
> - [ ] Or learn it: an own-side pairwise term in the combat model's corpus (the fights would
>   have to include guns and spotters, which the duel sims do not).
> - [ ] Sim: a bot owning a loaded Bombard and no spotter values the Recruit above the Badger
>   against an army the Badger counters.

## Micro

### X1 — Positioning: effective and safe

**Standard.** Units stand where they can act and are not needlessly exposed: in front of
what is threatened, in cover, out of a fight they cannot win.

**What exists.** PARTIAL: the army stands `STAGING_OFFSET` in front of the frontmost structure
on the threat axis (`_station_point`, with `BotFields.approach_post` on the approach band when
fields exist); idle armed units take cover in neutral buildings (`BotOpportunist`, §Cover);
a hurt unit with no effective target retreats to cover or home (`_tick_preservation`,
`RetreatPolicy`); the guard sizes itself against a raid by arrival time; placement weighs a
safety field for buildings. A TARGETED retreat — a unit at full health kiting a counter it
cannot beat, a crusher pulling out before contact — exists only as the run-over's
survivability gate (X2). No unit holds range, flanks, or screens another: the
"which positions matter" list is PLANNED ([world-model/lattice-and-topology](world-model/lattice-and-topology.md)).

**Verdict: PARTIAL.**

> **TODO — positioning beyond the station.** Each is one policy on a squad, priced by the
> fields the lattice already sweeps:
> - [ ] Range holding: a ranged unit keeps its reach between itself and a melee or shorter
>   threat (the kite the duel sims measure as `jinking`).
> - [ ] A retreat that is not preservation: a squad whose fight the combat model predicts
>   lost falls back to the guard or a tower before it is hurt.
> - [ ] Sim: a Sloop at full health beside two Badgers backs off toward a Watch Tower rather
>   than trading.

### X2 — Several micro options: shooting against running over

**Standard.** A unit with two ways to hurt a target picks the better one in the moment.

**What exists.** BUILT for crush against shoot: `BotTargeting` scores a run-over on the
effectiveness signal (`CRUSH_EFFECTIVENESS_SIGNAL` 2.0, above a counter's multiplier) with
two gates — survivable (incoming dps over the drive ≤ half the crusher's hp) and clumped
(bonus per crushable within one body width) — and the actuator issues a Move at the target
(`sims/bot/targeting/crush_a_counter`). The capture-and-deposit loop is the Stock Truck's own
version (`BotOpportunist`). An ability strike against a clump replaces an Attack for one order
(`BotAbilities`, `sims/bot/ability/strike_a_clump`).

**What is not.** Three options a unit can hold today and the bot never weighs: an ability
against a shot for the same unit (the strike is thrown whenever a clump exists, never
withheld), the Sloop's crush-to-CAPTURE against crush-to-kill (one Move; the outcome is the
hold's), and kiting (X1).

**Verdict: PARTIAL.**

> **TODO — the micro options as one choice.** The targeting scorer is additive signals; an
> option is a candidate with its own signals.
> - [ ] Should the strike be priced against the shot it replaces (expected damage of each),
>   with the brief's "save an offensive ability for the impactful moment" as a threshold?
> - [ ] Sim: a Sloop beside one Badger and a clump of Recruits runs the clump over rather
>   than shooting the Badger, and does the reverse when the clump is under a tower.

## How a standard becomes a test

Each `TODO` above ends in a simulation the way the built ones have one
(`sims/bot/<domain>/<name>.sim.yaml`; [decision-sims](decision-sims.md)): a controlled pair of
situations that differ in the one fact the rule reads, with `ordered` / `chosen` / `posture`
checks on the bot's decision and an outcome check behind it. A standard is MET when its sims
pass and the ladder's ledger shows the behaviour in play; the ledger table in M1 is the form
that report takes.
