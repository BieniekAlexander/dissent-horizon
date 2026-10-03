---
title: Bot roadmap
type: system-note
---

# Bot roadmap

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

What exists is [bot-architecture.md](bot-architecture.md). Everything
unbuilt below is a `TODO` with a stated cost, in the order it is worth doing.

## The one-line diagnosis

The perception layer is strong and the arbitration layer is thin. `Bot` exposes ~60 senses
and `BotProduction` already makes a genuinely derived decision from them — but **almost every
other choice the bot makes is a fixed ladder or a fixed call order, not a comparison.** The
economy builds in a set sequence; the scout wins over the military because it is called
first. Nothing anywhere asks *is scouting worth more than attacking right now*.

Two decisions are honourable exceptions and are the models for the rest: `BotProduction`
picks a unit by composition value, and `BotMilitary._committing_to_attack` decides to attack
by comparing army values under a humility prior. `BotScout` joined them — WHICH unit scouts
is now a score (2026-09-04, below).

That is also the exploitable surface: a ladder is a script, and a script is what a player
learns.

## Difficulty first, because everything else is calibration

Until difficulty was a real knob there was nowhere to PUT the outcome of any tuning work, and
every improvement below had to ship at one strength for everybody. It was read in exactly two
places.

**`BotDifficulty` (2026-09-04)** — one resource per tier holding the parameters the
managers already wanted, handed to `BotBrain` by `Scenario._attach_brain`. It is a data
object with no behaviour, deliberately: the tiers must differ by numbers a training run can
search, not by branches a training run cannot.

What it carries, and what each is FOR:

| Field | The handicap it expresses |
|---|---|
| `combat_period_seconds`, `strategy_period_seconds`, `scout_period_seconds` | REACTION TIME, per kind of decision. A slow bot notices late — the most human-feeling handicap there is, and the one a player cannot see being applied |
| `army_commit_threshold` | how large an army it wants before attacking; the aggression dial |
| `preserve_min_cost` | which units it bothers to save (−1 = never, 0 = always) |
| `retarget_switch_margin` | COMMITMENT. A high margin means it will not micro away from a bad trade |
| `scout_unit_budget` | how many units it is willing to have away from the fight |
| `economy_reserve` | how greedily it banks before expanding |
| `may_attack` | PASSIVE's whole definition |

**PASSIVE is now minimally active rather than inert.** It was `active = false` — the brain did
not run at all — which is not what "should be minimally active, and should never attack the
player" asks for. It now thinks, builds and trains, and `may_attack` is what stops it: the
military may DEFEND and MASS but never ATTACK, and `BotSanction` never strikes. A passive
opponent that still grows is a sparring partner; an inert one is scenery.

> **TODO — the tiers between EASY and IMPOSSIBLE are placeholders.** The values shipped are a
> monotone ramp chosen by hand, not measured. They are the thing §The training harness exists
> to search, and nothing should be balanced against them until it has been.

> **TODO — IMPOSSIBLE has no supernatural half yet.** The brief is "a human will never
> realistically beat it", which needs frame-perfect micro (a per-unit tick rather than the
> shared think cadence) and economic execution the tiers cannot express as parameters. Decide
> whether that is a separate execution layer or simply `think_interval_ticks = 1` plus a
> targeting signal mix — and note the stated caution that two IMPOSSIBLE bots must not
> deadlock into a stalemate, which argues against making DEFEND cheap at that tier.

## Then: arbitration, not sequence

The Opportunist already has the right shape — gatherers return scored candidates in a common
currency (energy-equivalent value) and the best are executed. **The plan is to widen that
currency until it covers the decisions the call order currently arbitrates**, rather than to
add a fourth mechanism beside the ladder and the FSM.

Concretely, in the order they are worth converting:

1. **The economy ladder → scored options.** "Build an extractor" and "build a barracks" are
   both energy-equivalent gains over a horizon; the ladder is a hand-ordering of a comparison
   the bot could make. This is the single biggest predictability win, because the opening is
   what a player learns first.
2. **Scouting → a scored option.** The value of a scout is the value of the information
   against the cost of the unit being away — which is exactly the trade-off the user named
   ("n = infinity is obviously ideal, so the question is a trade-off"). It cannot be answered
   by a call order.
3. **The military posture → scored postures.** Three states become three scores, and MASS
   stops being "otherwise".

### The currency is ENERGY-EQUIVALENT (SETTLED 2026-09-04)

**Every option the bot compares is priced in energy**, with an authored constant wherever a
thing has value but no price. The alternative considered and rejected was a unitless utility
in [0, 1] per option — the classic utility-AI shape, and the one this note previously leaned
toward. Energy won on three arguments, all of which are about the currency doing work
*outside* the decision it was introduced for:

- **It is already the right answer in the place the bot reasons best.** "Will this blast
  destroy more than the drone costs" is a subtraction in energy and nothing else. A unitless
  utility would have had to launder that back into a comparison it already makes correctly.
- **It reads back into balance.** If a unit is not worth its price to the bot, that is a
  finding about the unit, not about the bot. A normalised utility cannot say that — every
  option scores 0 to 1 by construction, so nothing is ever revealed as overpriced.
- **`BotOpportunist` needs no conversion**, and the existing scored decisions stay comparable
  with the new ones rather than living in a second scale.

**WITHHOLDING stays a threshold for now, deliberately.** "Should I buy this cheap unit or
save for the expensive one" is a genuine option the currency could price, and it is NOT being
modelled: `economy_reserve` exists to stop the bot spending down to zero so that it can
always afford something, and that crude guarantee is worth more today than a rigorous model
of saving. Revisit alongside the energy-versus-dominion trade below — they are the same
short-term-against-long-term question.

The cost accepted: **anything without a price needs one authored**, and that number is a
judgement rather than a derivation. There is exactly one so far —
`BotScout.INFORMATION_VALUE_ENERGY`, what knowing the whole map is worth. Keep them few,
named, and defensible in a line each; a formula with a hidden rate in it is the failure mode.

> **TODO — energy against DOMINION is the open half.** Both are real resources and the bot
> will eventually have to trade one for the other ("should I take another extractor or push
> the dominion route"), which energy-equivalent pricing does not answer on its own. Deferred
> deliberately as a modelling exercise of its own. **The practical consequence is that the
> economy ladder cannot be converted yet** — a dominion structure and an extractor are not
> comparable until it is settled, which is why §1 below is not the first conversion despite
> being the biggest win.

**Conversion 2, scouting (2026-09-04).** `BotScout._scouting_is_worth_it` compares
`INFORMATION_VALUE_ENERGY × stale_fraction ÷ (scouts already out + 1)` against
`unit_cost × ABSENCE_RISK`. The divisor is the answer to "why not scout with everything": the
second scout buys half what the first did at the same price. `scout_unit_budget` survives as
a CEILING rather than as the decision — a cap says what is permitted, not what is wise — so
the difficulty knob still means something, and a budget above 1 now does something, which it
previously did not.

## What has to be modelled, and what may stay hardcoded

The user's rule: signal what a thing is FOR, so the bot works it out; hardcode only where
modelling would cost more than it returns.

**Already derived — do not regress these.** Unit counter-effectiveness (the damage matchup
table), what a structure is for (component presence), what an AOE-suicide unit is (its
projectile), whether a piece can build/repair/produce (its components). A new piece needs no
bot change today and that must stay true.

**Should be derived and is not:**

- **What makes a good scout: `BotScout._scout_score` (2026-09-04).** It picked
  the fastest free unit; it now scores speed, vision, replacement cost (energy + build time)
  and how many of the unit's OTHER jobs are currently live — one per manager that would
  otherwise claim it, counted only when that manager has work. That last term is what makes
  the Stock Truck the right opening scout without naming it: unarmed, cannot build, and its
  capture errand has no target until enemy infantry is in sight. The WEIGHTS are placeholders
  on the same footing as the difficulty ramp; the terms are settled. `tests/test_BotScout.gd`.
  Deliberately a COUNT rather than a value — pricing "this unit's other job" against "seeing
  the enemy base" is the currency question below, and a count needs no answer to it because
  every candidate is being asked the same single question.
- **Whether an ability is worth using now.** `BotSanction` is a policy (defend, else strike,
  else hold). The stated model is better: an economic ability is used as often as possible; an
  offensive one is worth saving for an impactful moment. That is a value-over-time question,
  not a policy.

**Accepted as hardcoded, for now:** the ERRANDS of each faction's dominion route. Colonial
capture-and-deposit and Anarchical Warlord-colocation are separate gatherers; keep them as
gatherers so the cost stays one function each. Which STRUCTURES a route is built from is no
longer hardcoded — see [bot-architecture](bot-architecture.md) §Dominion routes.

## The training harness

The user wants adversarial self-play to search the parameters. Two things have to exist
first, and both are worth having anyway:

1. **A seeded simulation.** Nothing can be measured while the sim diverges from the first
   shot — see the seeded-pseudo-randomness task, which is a prerequisite rather than a
   neighbour.
2. **Focused scenarios**, one per question, so a run measures one parameter. The user's own
   examples are exactly right: a duel scene for "unit set X against unit set Y", a map for
   "how many scouts". `tools/simulation/run_scenarios.gd` and `scenes/scenarios/test/` are the
   beginnings of this.

**The parameter-search discipline the user stated is the important part:** hold every other
behaviour's parameters equal while searching one. That is an argument for the flat
`BotDifficulty` data object above — a tier that differs by BRANCHES cannot be held equal.

> **TODO — a human-versus-bot harness is not planned.** The user is interested and doubts it
> is feasible ("infeasible to model the apparent decision-making of the human player").
> Agreed for now: recording matches is cheap and worth doing once replays exist, but
> attributing a loss to a parameter needs the counterfactual, which a human opponent cannot
> supply. Revisit only if replays make batch re-simulation cheap.

## The gaps in the decision surface

The surface itself is enumerated in [bot-architecture](bot-architecture.md) §The decision
surface. What follows is only the holes, in the order they are worth filling.

**1. Own-side grouping — the army is one undifferentiated set.** `BotMilitary` points every
combat unit at one position because there is no object in which "half the army" is a thing.
`Bot.enemy_clusters()` groups the ENEMY; nothing groups us.

> **PLANNED — the squad: an army object with merge and split, and a per-difficulty cap on
> how many the bot runs at once.** Approved 2026-10-03 and written up, with the mission
> tactics sharing the same object, in [squads-and-relations](squads-and-relations.md)
> §Squads. Attention — groups managed, decisions per think, reaction time — remains one
> family; what its units are is still [objective-selection](objective-selection.md)'s
> question.

> **TODO — NOBODY FINISHES A BEATEN OPPONENT OFF.** `_objective_for(ATTACK)` sends the whole
> army to one remembered position and re-tasks only when that position moves more than
> `OBJECTIVE_EPSILON`, so a side reduced to a handful of scattered survivors is never hunted
> down: measured, the winner sat in ATTACK posture with several units idle while the loser
> rode the clock (`gdd/systems/ai/bot-engagement-fixes.md`). Changing the elimination rule
> stopped that mis-scoring a match, and deliberately did not fix the behaviour — a bot that
> cannot close out a won game is still a bot that cannot close out a won game, and it is the
> same missing primitive as gap 1: with no way to split the army there is nothing to send
> after two survivors in opposite corners.

**2. Standing behaviour — the bot has no way to leave a unit somewhere.** `Defend`, `Patrol`
and rally points are all unissued, so idleness is only ever a fallback that the military's
sweep picks up. The user wants idleness to be *possible and sometimes correct* (a unit
holding a region), and wants it without command queues. Standing orders are exactly that
answer: one decision that keeps a unit busy indefinitely.

> **TODO — issue `Defend` for a held region, and set rally points on production
> structures.** Cheap, and it removes the two commonest causes of a unit doing something
> stupid because it went idle at a bad moment.

**The default for a unit with nothing to do is to SCOUT** — it is the one job that is always
available and always worth something, and `BotScout` already prices it. But that default is
subject to the same throttling as everything else: a bot permitted only a few managed groups
should be *allowed* to leave a unit standing, and an idle unit is not automatically a bug.
Deliberate idleness (a unit holding a region) and throttled idleness (a unit the bot has no
attention left for) look identical on screen, and both are wanted.

**3. Unit abilities are unreachable.** `Ability` is not an actuator verb and `Abilities` is
read only by `BotSanction`, so Dignify — the user's own example — cannot be used by a bot at
any difficulty.

**An ability is cast by a STRUCTURE**, which collapses the modelling: "should I cast this"
is not a separate question at all, it is "what should this structure do", with the ability as
one of the options available to that actor. A structure is then a commandable with an action
set like any other, and abilities stop needing a module of their own.

> **TODO — an `ability` verb on the actuator, and a usage hint on the ability doc.**
> `Sanction.targeting` / `min_targets` is the pattern to copy onto `kind: AbilityDefinition`; the
> user's model (economic → use as often as possible, offensive → worth saving for an
> impactful moment) is a field, not a module. What remains is folding it into the actor's
> action set rather than leaving it as a manager that runs last.
>
> **`BotSanction`'s actuator bypass is FIXED (2026-09-04)** — it issues `UseSanction` through
> `BotActuator.use_sanction` now, so a commander ability already travels the player's route
> and only unit abilities are unreachable. `tests/test_BotCommandCoverage.gd` is what keeps
> the two routes from parting again.

**4. Aerial operations are entirely outside the surface.** No bot module mentions aircraft,
docking, runways or charged ammunition. A bot that trains an aircraft flies it until the clip
is empty and then keeps flying it, because it can issue neither `Land` nor `Rearm`.

> **TODO — decide whether a bot may field aircraft at all before fixing this.** The cheap
> interim is honest: keep aircraft out of `BotProduction`'s candidate set so the bot does not
> buy what it cannot operate. The real fix is a docking/rearm manager, which is a whole
> subsystem — see [aerial-operations](../combat/aerial-operations/).

**5. Repair is not a decision the bot can make**, so a damaged structure stays damaged and
`Repairs`-carrying units never use the component they were given.

**5b. "What to make" and "where to make it" are one decision, and the bot only makes the
first.** `BotProduction` walks the idle production structures and trains each one's best
unit, so WHICH structure builds a wanted unit is decided by iteration order. The case that
shows it: the bot needs anti-infantry, one structure trains it, and that structure is about
to be destroyed — training there is the wrong call even though the unit is the right one.

> **TODO — pick the producer as part of picking the product.** Needs a per-structure
> survivability read (`Bot.most_threatened_structure` is the beginning of one) and a
> tie-break on queue depth, so a want is placed where it will actually arrive.

**5c. Reload time belongs in a unit's decisions, and is absent.** Three tiers, and only the
first is free:

- **Short reload** — no decision at all; the unit fights and reloads inside the fight.
- **Long recharge** — the unit is defenceless for a meaningful window, so it should
  REPOSITION while it is vulnerable rather than stand in the open waiting.
- **Must dock to recharge** — the sharpest case, and the useful reframing: **a unit that
  cannot rearm in the field is a unit WITHOUT AN ATTACK until it has docked.** It should stop
  reading as army strength, stop being retargeted, and be claimed by whatever sends it home.

For aircraft this composes with scouting: a spent aircraft may as well look at what it passes
over on the way, but **docking is the correct ultimate decision** and scouting must not defer
it. See [aerial-operations](../combat/aerial-operations/) and gap 4 above.

**5d. REJECTED 2026-09-17 — a spare Servant has nowhere to be, and now genuinely doesn't.**
This used to describe a real gap: the Compound admitted Servants by order and paid dominion
per occupant, so a spare builder parked there was a standing income option the bot could not
reach (`BotOpportunist._bunker_garrison_candidates` filters on `u.weapon_inventory.has_weapons()`,
excluding an unarmed Servant before the host was even considered). The Colonial dominion
refactor ([combat/colonial-dominion](../combat/colonial-dominion.md)) closed the Compound's
garrison for a different reason — a captive it holds is sentenced and consumed, never
converted into a Servant that could walk back out — so there is no longer a Servant-shaped
slot to fill at all. The value-over-time question this used to compete with `build_concurrency`
over (§What has to be modelled, for abilities) is unaffected; it simply lost this one consumer.

**6. Objective selection is a fixed rule, and there is no layer above it.** "Which enemy
thing do we go for" is `nearest_enemy_structure_to_base()`; "which site do we expand to" is
buried in the economy ladder.

**The important half is the layer that does not exist at all.** Buying and commanding are LOW
-level decisions that should sit under a statement of what the bot is trying to do — all-in,
booming, turtling — which is not another decision beside them but a disposition that tilts
all of them at once. Without it, individually reasonable choices cannot add up to a plan.
Written up as a proposal, with three candidate representations and a recommendation:
→ **[objective-selection.md](objective-selection.md)**

> **TODO — the low half is unblocked and could be built first.**
> `EnemyCluster.energy_value` prices a force and `Bot.unit_cost` prices a structure, so "what
> is worth attacking" is already a comparison the bot could make. Worth doing only if it does
> not prejudge the layer above it.

## Tactics and the Bot

`ScenarioTactic` / `TacticRule` (see
[scenario-scripting/tactics](../scenario-scripting/tactics.md)) is a rule engine a scenario
author points at a group of units. The Bot is a commander deciding for itself. They overlap
in obvious ways and are deliberately separate.

**The boundary is settled (2026-10-03): share the action side, keep the decision side
separate.** A squad and its policies are one mechanism used by both; which policy a squad
runs is a `TacticRule` in a mission and a scored comparison in the Bot, and the two never
merge. See [squads-and-relations](squads-and-relations.md) §The boundary.

## What the referenced talk contributes

The comparison against ZeroSpace's framework is written up separately —
**[three-layer-comparison.md](three-layer-comparison.md)** — because it is research rather
than plan. The three gaps it found are below, in the order they are worth doing.

## The vision layer

**Clustering is missing from perception**, and the comparison argues it is the primitive
everything else should be reading: a handful of threat objects carrying strength, speed and
direction, instead of either one unit or the whole army. The consequence here is concrete —
`BotMilitary` commits everything to one objective position because one position is all its
inputs can express, and it cannot say "leave four home and take the rest" for want of a
representation in which "the rest" is a thing.

The pieces already exist: `ClusteringUtils.get_nodes_clustered` is a general implementation
that no bot code calls, and `BotSanction._densest_cluster` / `Bot._aoe_hit_value` are two
ad-hoc reimplementations of the idea in the two places that could not proceed without it.

Perception now answers TWO cluster questions, and keeping them apart
is the part worth remembering — **a group's centroid does not answer the coverage question**,
because a long chain of units is one group whose centre may sit within reach of none of them:

- **Grouping** — `Bot.enemy_clusters()` returns `EnemyCluster`s (members, centroid, summed
  strength, energy value, mean heading), strongest first. This is the primitive the military
  work needs: it is what makes "the smaller of two threats" or "leave half at home" sayable
  at all, where before there was nothing between one unit and the whole army.
- **Coverage** — `Bot.best_covered_point(candidates, radius, weight)` answers "where should a
  radius-R effect land". `BotSanction`'s aiming (weight = 1 per body) and `BotKamikaze`'s
  blast valuation (weight = damage × price) are now the same scan asked two questions, where
  they were two independent O(n²) reimplementations of it.

`Bot.entity_strength` came out of the same pass: `estimate_army_strength`,
`relative_threat_level` and a cluster's strength were three copies of "damage × remaining HP
fraction" and are now one, so they cannot drift.

> **TODO — clusters are of LIVE visible units, not of remembered ones.** Strategic planning
> wants the believed set (attacking a force you remember), which needs the grouping to work
> on positions rather than on nodes. Not built.

> **TODO — the grouping is O(n²) single-linkage on the think cadence.** Fine for the handful
> of visible enemies it runs over today; measure before pointing it at a larger set.

## Reading the game

**Nothing in this bot knows whether it is winning.** `relative_threat_level()` computes an
instantaneous strength ratio and no module reads it; the blackboard records what exists and
where, never what CHANGED. Both of the talk's headline behaviours are consumers of that one
missing signal:

- **Retreat**, which the talk singles out as the thing that reads as human. We retreat in one
  narrow case — `BotBrain._tick_preservation`, below 25% HP and unable to damage anything in
  range, i.e. a HOPELESS MATCHUP rather than a losing fight. There is no army-level retreat at
  all: `BotMilitary`'s wave runs until spent to 35% of its launch value whatever is happening
  to it. That is precisely the hard-commit the talk opens by criticising. The wave rule is
  there for a real reason (it fixed a bot that dribbled its army in), so the remedy is a wave
  that retreats TOGETHER, not one that cannot retreat.
- **Reacting to a counter** — noticing that the enemy's composition moved against ours, which
  needs the blackboard to carry history rather than only a present snapshot.

**`BotMomentum` (2026-09-04)** — the army-value trend, sampled on the think cadence
and read as a loss rate (fraction of the army bled per second) over an 8-second window.
Chosen over a fuller position score (army + income + territory) and over per-engagement
outcome because it is ONE sampled value, it unblocks the retreat in the same change, and the
richer version grows out of it by adding terms rather than by replacing it.

**Army-level retreat (2026-09-04).** `BotMilitary` calls a wave off when the army has
lost 30% of its launch value **and** momentum says it is still bleeding. Both halves are
load-bearing, and the second one is the whole design: heavy losses ALONE are not a reason to
leave — a wave that spends a third of itself to destroy the enemy's army has won — and a bot
that pulls back on damage is the dribbling bot the wave rule was written to stop. A called-off
wave regroups at home for 20 seconds, which the army-size posture branch honours; without that
window the retreat was re-ordered as an attack the same think it was decided.

> **TODO — momentum is blind to the enemy's losses, and that is a real limitation rather
> than an oversight.** Belief ratchets UP as an attack reveals more of the enemy, so any
> trend over believed enemy value reads a successful push as a disaster; the only honest
> signal available is our own. The consequence is that a costly-but-winning fight can read as
> losing. Per-engagement outcome — "did that trade well" — is the fix, and it needs an
> engagement to have a beginning and an end, which nothing currently defines.

> **TODO — a HISTORY of the opponent is still missing.** The blackboard records what exists
> and where, never what changed, so the bot cannot notice that the enemy's composition moved
> against its own. That is the other consumer named above and it is not built.

## What the talk changes about the ability plan

`Sanction.targeting` / `effect_radius` / `min_targets` turn out to be exactly the talk's
per-ability "drop-down of how the AI is supposed to use this", authored on the ability's own
data. That is the shape to extend rather than replace — but it exists only for SANCTIONS, and
the bot never uses a unit's own ability at all (`Abilities` appears in `BotSanction` and
nowhere else in any bot module). The user's stated model — economic abilities used as often as
possible, offensive ones saved for an impactful moment — is a field on a `kind: AbilityDefinition` doc,
not a new bot module. Recorded under §What has to be modelled above.

## Waves versus a steady stream

The talk reports a playtest result that contradicted its own expectation: collecting units
into waves gave players breathing room they converted into an advantage, while a semi-steady
stream from several directions was harder to hold and more fun at high level. **We are a wave
bot** at two levels (`events.json` spawn waves; `BotMilitary`'s mass-then-commit). That is a
claim about his game's balance rather than a law, so it is not a defect — but it is a cheap
experiment once the harness exists, and it is one parameter.
