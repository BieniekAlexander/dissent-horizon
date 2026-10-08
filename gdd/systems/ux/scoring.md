---
title: Scoring — the arcade grade
type: design-note
---

# Scoring — the arcade grade

PLANNED: the design below is agreed but not built. What is still undecided is marked `TODO`
where it applies.

The score answers one question:

> **How quickly, how continuously and how economically did the player turn their start into
> a win?**

It is an **arcade grade**, not a fair measure of how sound a strategy was. A slow, defensive
win that hoards resources still clears the mission. It just scores badly. The grade is meant to
be absurdly hard to max out.

**It is calculated for every scenario.** In some scenarios it will mean nothing, and that is
dealt with by how much of it the player is shown, not by skipping the calculation.
TODO — which scenarios present the grade, and how prominently, is undecided.

---

## Settled

- **Three axes: Alacrity, Diligence, Precision.** Nothing else is shown to the player.
- **Fast wins are preferred on purpose.** A slow match never blocks progress. It only earns a
  bad grade, which is the soft pressure against drawing a game out.
- **Alacrity is the clock, with no game-specific terms.** Winning within a fixed time earns
  full points, and every second beyond it costs points. The score does not try to detect a
  decisive lead or tempo; offensive, non-idle play is Diligence's job.
- **Idleness and a defensive posture are punished.** The score does not try to tell whether an
  idle army was sensibly defending. A player who micromanages and scouts well has no need to
  turtle, so the bar is set there on purpose.
- **Scouting is the one allowed reason for a unit to be idle.**
- **Banked resources are judged by intent, not by the size of the bank.** A bank of 5,000
  followed by a 500 purchase is neglect. The same bank followed by a 5,000 purchase is saving.
- **Banked dominion counts as float** once it exceeds the price of the player's most expensive
  option for longer than a grace period.
- **Every loss costs Precision.** The ideal performance loses nothing.
- **An easy component is acceptable.** Requisition still needs real-time attention, so the
  spending half of Precision is not trivial; and there are enough components that one being
  fairly easy does not flatten the grade.

**REJECTED** as separate axes:

- **Combat efficacy.** Redundant with Diligence, and a separate score would reward farming damage.
- **Initiative.** Redundant with Precision. Its one useful signal, scouting, is now the Diligence
  exemption.
- **Objective mastery.** Redundant with Alacrity. Finishing the objective sooner already means
  winning sooner.
- **Adaptability.** It cannot be measured without guessing what would have happened otherwise.
- **APM or order count as an input.** Issuing orders is not the same as producing value.
  Diligence credits the state a unit is in, not how often it was clicked.
- **A penalty for lingering after a decisive lead.** G17 buffers leads, so a lead is rarely
  decisive and a detector would be guessing. The clock already charges for every extra minute.
- **Tempo as the Alacrity signal.** Tempo is what Diligence measures; scoring it twice would
  leave nothing scoring the finish.

---

## Structure: the score is computed after the match, from a log

**Every question of the form "was this intentional?" is answered by looking ahead in a log, not
guessed during the match.** The match records events. The grade is computed once, at game over,
by a pure function over that record:

- A bank is judged by the **next purchase** that actually happened.
- A move order is judged by **what the unit did when it arrived**.
- A queued purchase that shields a bank is judged by **whether it was later cancelled**.

It also fits the layering rule in `~/.claude/CLAUDE.md` §7. The recorder is thin and tied to the
engine. The scoring function has no engine types, so the whole grade can be unit-tested against
hand-built logs.

---

## Alacrity — how fast the win came

    A = 100                                  if T_win ≤ T_full
    A = 100 · T_full / T_win                 otherwise

`T_win` is the time the verdict latched, in seconds. `T_full` is the time within which a win
earns full points: **300 seconds (5 minutes), static for every scenario.** The falloff is
smooth, so there is no second threshold to rush against: 10 minutes scores 50, 20 minutes 25.

TODO — a more rigorous `T_full` (authored per scenario, derived from the map, or measured from
selfplay) is deferred. The falloff curve is a placeholder too, to be tuned with the rest.

Missions whose primary objectives are not elimination need no special case. Completing the
objectives *is* the win (`ScenarioTriggerManager.all_objectives_complete`).

---

## Diligence — keeping everything working

The share of the player's owned value that was **doing something** over the match, weighted by
cost:

    D = Σᵢ ∫ costᵢ · creditᵢ(t) dt  /  Σᵢ ∫ costᵢ · eligibleᵢ(t) dt

Weighting by cost means an idle late-game army counts for far more than an idle early scout.
It also means mass-producing cheap units cannot pad the score.

**Only pieces that can be idle are eligible.** An extractor or a dominion generator has no
idle state, so it is left out of both the numerator and the denominator.

### Units: credit follows the current order

| State | Credit |
|---|---|
| `Attack`, `AttackMove`, `FocusFire`, `Capture`, `Bombard`, `Spot`, `UseSanction`, `AirDropRun` | full |
| `Build`, `Assemble`, `Repair`, `Rearm`, `Occupy`/`Embark` into a host that then acts | full |
| Travelling (`MoveCommand`, `Land`) | **decided retroactively.** Full if the unit arrives and moves into a credited state within a short grace window. Zero if it arrives and sits. |
| **Scouting**, whatever its order | full while the unit's vision is supplying **novel** fog pixels (below) |
| No order, `Stop`, `Defend`, `Patrol`, `Wander`, an aircraft circling idle | zero |
| Garrisoned in its own structure | zero, unless the host is itself credited (a Shelter being tasked, a garrisoned bunker firing) |

`Defend` and `Patrol` get zero on purpose. That is what "defensive posture is punished" means in
practice. A defender earns credit when it actually fights, because an engagement turns into an
attack.

TODO — **Patrol**, and a `Defend` post placed forward on enemy approaches, could be argued as
area control. Leaning: keep both at zero until play shows that holding a forward position needs
separate credit. Scouting already rewards the vision such a post gives.

### Scouting is measured on the fog, not guessed

A unit counts as scouting while its vision covers pixels that are **unexplored, or explored but
not currently seen by any other piece of its owner's**. Parking a scout in a corner already
covered, or on ground seen a moment ago, earns nothing. It keeps earning only while it shows
the player something they would otherwise not see.

`Fog` already has the explored buffer. Freshness needs one more thing: a per-pixel last-seen
time, so that ground not seen for a while counts as novel again.

### Structures: credit follows the production job

| State | Credit |
|---|---|
| Producing (`Production` has an active job) | full |
| Idle, with energy that is not reserved (see Precision) | zero |
| Idle because the commander is broke | **not eligible**. Being broke is Precision's concern, and should not be charged twice. |
| Dark (`Actor.is_unpowered()`) | zero, and it also counts against Precision |

A standing order keeps a producer credited indefinitely. That is intended. The design already
wants idle income to always have somewhere to go.

---

## Precision — spending promptly and losing nothing

    P = w_spend · SpendingDiscipline + w_loss · LossDiscipline

### Energy: the queue already records intent

A purchase submitted with the additive modifier sits `PENDING` until it is affordable, and
head-of-line blocking guarantees that energy banked behind it cannot be spent by anything
behind it. So the queue *records* what the original draft had to infer:

    reserved(t) = energy_committed(t)          — PENDING entries, already a Commander readout
    float(t)    = max(0, energy(t) − reserved(t))

- **5,000 banked, no pending entry, then a 500 purchase:** the 5,000 was float for the whole
  time it sat there.
- **5,000 banked behind a pending 5,000 purchase:** reserved, so no penalty. The player said
  what the money was for, and the queue held it for them.
- **Buying something big without queuing it:** float that ends in a single purchase costing
  most of the bank, within a short window, is forgiven. A fallback, not the main route.

**Shielding the bank with a fake order is caught afterwards.** Cancelling refunds the full cost,
so a player could queue a 5,000 purchase, bank against it and cancel it later. Rule: **when a
PENDING transaction is `CANCELLED`, its whole reserved interval is re-scored as float.** Saving
only counts if the purchase actually happens.

Normalise by income: `∫ float dt / ∫ income dt`, the fraction of what was earned that sat idle.
A raw figure would punish a big late-game economy for carrying the same *habit* as a small one.

Also counted against spending discipline:

- **Time spent strained** (`Commander.is_infrastructure_strained()`), weighted by the cost of
  the structures that went dark. Buying buildings the grid cannot power is bought value thrown away.
- TODO — `FUNDED` entries left waiting on a busy producer: the money is spent but produces
  nothing. Leaning: count it lightly, since a lack of production capacity is mostly Diligence's.

### Dominion: float above the most expensive option

Dominion is meant to be banked towards sanction tiers, so holding it is not float by itself.
It becomes float when it is more than the player could spend in one go:

    ceiling(t)       = cost of the most expensive dominion purchase open to the player at t
    dominion_float(t) = max(0, dominion(t) − ceiling(t))   once that excess has lasted 30 s

Saving up for the priciest thing is free. Sitting on more than it costs, for more than 30
seconds, is charged for the whole excess from the moment the grace period runs out. It is
normalised by dominion income, as energy is.

TODO — "open to the player" is read here as *unlocked and usable now*, so a tier behind an
unmet prerequisite does not raise the ceiling. The other reading (the most expensive option
anywhere in the faction's grid) would make dominion float almost impossible early on.

### Loss discipline

Every loss counts: `∫ cost lost / ∫ cost bought`, over units and structures alike, including
construction destroyed before it finished. A scout that dies after scouting is still a loss.
The ideal performance loses nothing, and the score says so.

This deliberately cuts against G7 (nothing non-universal punishes hard use of each unit): a
player who falls behind and has to trade will score worse. That is accepted, because the grade
is not a balance mechanism, and the ranks that matter need a win anyway.

---

## Combining the axes

TODO — the formula and thresholds below are arbitrary samples, to be tuned against gameplay
metrics that are still in development.

**Victory gate plus the weakest axis.** A weighted sum would let one excellent axis make up for
a poor one, which is exactly the "busy but wasteful" or "tidy but passive" play the three axes
are there to catch.

| Rank | Needs |
|---|---|
| S | victory, and every axis ≥ 90 |
| A | victory, every axis ≥ 75 |
| B | victory, every axis ≥ 55 |
| C | victory |
| D | defeat, and the mean of the axes ≥ 50 |
| E | defeat |

Inside each axis the sample weights are equal (`w_spend = w_loss = 0.5`).

### What the player sees

The number matters less than the reason given for it. Each axis reports its single biggest cost,
in the game's own terms:

> **VICTORY — Rank B** · 7:10 (full marks under 5:00)
> **Alacrity 70** — finished 2:10 over
> **Diligence 74** — 1,900 energy of army idle at home for 3:05; Barracks idle 1:32 with energy free
> **Precision 58** — 3,250 energy unreserved for 2:40; 1,100 energy of units lost

---

## Exploits, and which axis catches each

| Exploit | Caught by |
|---|---|
| Walking units back and forth to look busy | Diligence: travel is only credited if the unit acts on arrival |
| Parking a scout in a known corner | Diligence: novelty and freshness of vision |
| Throwing away cheap units constantly | Precision: every loss counts. Diligence: cost weighting |
| Queuing a fake big purchase to shelter the bank | Precision: cancelled PENDING intervals re-scored as float |
| Hoarding dominion "for later" | Precision: dominion above the most expensive option is float after 30 s |
| Rushing an unsafe finish | Defeat caps the rank at D |
| Turtling into a deathball | Alacrity (clock) and Diligence (Defend earns zero) |
| Mass standing orders of cheap units to zero out float | **Not caught, and accepted.** It spends the money. Whether the units were any use shows up in Diligence and losses. |

---

## Implementation sketch

- **`ScoreLedger` recorder** (engine side, thin). It samples each owned piece's credit state at
  a low fixed rate in seconds, not every physics tick. It subscribes to the transaction lifecycle
  (`PurchaseTransaction.fulfilled` has no consumer yet, and this would be its first), to deaths,
  and to the verdict. It also samples the dominion ceiling, since what is open to the player
  changes as tech is built and lost.
- **`score_match(ledger) -> MatchScore`** is pure. It takes the log and returns the three axes,
  the rank and the explanation lines. Unit-tested against hand-built ledgers (§6.1).
- **Calibration** of `T_full`, the falloff, the weights and the rank thresholds comes from
  selfplay runs and belongs in simulation tests, not GUT. It is content, and it is expected to move.
