---
title: Objective selection
type: system-note
---

# Objective selection

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**TODO — an unapproved proposal.** The layer above every decision the bot currently makes. What exists
is [bot-architecture](bot-architecture.md); the other gaps are in
[bot-roadmap](bot-roadmap.md).

## The problem

The bot decides what to buy, what to build, where to send a unit and when to attack — and it
decides each of them **on its own merits, against the present instant**. There is nothing
above them saying what the bot is TRYING TO DO, so nothing that could make a set of
individually reasonable decisions add up to a plan.

The vocabulary players use for this is strategic: *all-in*, *booming*, *turtling*, *teching*.
None of those is an action. Each is a **posture that biases every action at once**:

- **All-in** means income goes to units rather than to infrastructure, the army commits at a
  lower bar, expansions are not taken, and scouting is worth less because the plan does not
  depend on what is found. It buys a short-term power spike at the cost of everything later.
- **Booming** is the same dials the other way: income into capacity, a higher commit bar,
  expansions taken early, and a short window of real vulnerability accepted in exchange for a
  larger long-term position.

**They are the same decisions with different weights, not different decisions.** That is the
whole design constraint: whatever represents strategy must sit ABOVE the existing decisions
and tilt them, rather than replacing them or standing beside them as a fourth mechanism.

## The requirement, stated as constraints

1. **Not categorical.** "I am rushing" as a mode is the scripted bot the whole project is
   trying to avoid — a player who identifies the mode has read the plan. Postures must come
   in gradations, and a bot must be able to be mostly-booming-but-nervous.
2. **Computed from game signals**, not authored per match — otherwise it is a build order.
3. **Gradations along real axes**: long-term against short-term investment, aggressive
   against defensive.
4. **Searchable.** The mapping from signals to posture is the thing self-play should tune, so
   it has to be parameters rather than branches (the same argument as
   [bot-roadmap](bot-roadmap.md) §Difficulty first).

## Three representations

### (a) A posture vector that modulates the existing parameters — RECOMMENDED

A handful of continuous dials, recomputed each think from the bot's signals, which multiply
the parameters the decision modules already read. The strategy layer **decides nothing
directly**; it changes what every lower decision concludes.

| Dial | Runs from | What it multiplies |
|---|---|---|
| `commitment` | booming ←→ all-in | the split of income between capacity and units; `army_commit_threshold` |
| `aggression` | defensive ←→ offensive | posture bias, the attack ratio, how far from home the bot will fight |
| `risk` | cautious ←→ greedy | `economy_reserve`, expansion distance, how thin it will run |
| `curiosity` | blind ←→ informed | `INFORMATION_VALUE_ENERGY`, so scouting competes harder when the plan depends on what is out there |

**The dials are also the bot's disposition where INFORMATION is missing** (Alex, 2026-10-08):
what the bot assumes about an enemy it has not seen is a posture, not a derivation. The first
consumer is spatial — the threat clock's arrival time before any sighting, when there is no
believed source to measure from, read off `risk` and `aggression` rather than off new
`BotDifficulty` fields ([world-model/lattice-and-topology](world-model/lattice-and-topology.md)
§Passability is relative). The humility prior `assumed_enemy_parity` is the same kind of
assumption for the enemy's unseen size, and is a candidate to fold in when this layer is built.

All-in is then `commitment` high and `risk` high; booming is `commitment` low and `risk`
high; turtling is `aggression` low and `risk` low. **None of those is written down anywhere**
— they are regions a player would recognise, which is the test the representation has to
pass.

**Why this one.** Every decision in the bot is already a comparison against parameters, and
[the currency](bot-roadmap.md) is already settled, so this is a multiplication rather than a
rewrite. It also unifies three things that are currently separate ideas:
**`BotDifficulty` is a fixed parameter set, the posture vector is a time-varying modulation
of one, and throttling is a third member of the same family.** One mechanism, three uses.

The RL fit is the clean part: the posture vector is a small continuous action space, the
signals are the observation, and — because the vector modulates rather than acts — credit
assignment does not have to reach through individual orders. Episode reward is the match
result or the resource differential.

**What it costs.** A dial that multiplies six parameters is six coupled behaviours changing
at once, which is hard to debug and harder to attribute in a search. Mitigation: keep the
dials few, and make the modulation visible in the debug overlay.

### (b) Scored objectives in energy-equivalent

The bot maintains candidate objectives — take that expansion, kill that army, raid there,
reach that tech — each priced in energy over a horizon, and commits to the best. Closer to
classic utility AI, and it reuses the currency directly.

**Why not, as the primary model.** It answers "what should I go for" but not "how should I be
playing", and booming is not an objective — it is a *disposition* toward every objective.
This is better read as the thing that fills the CURRENT objective-selection gap (which enemy
thing to attack, which site to expand to) sitting UNDER (a), not as a replacement for it.

### (c) A blend over named archetypes

A simplex over authored strategies: 0.6 boom, 0.4 turtle. Legible, and gradations fall out of
the blend.

**Why not.** The archetypes are authored, so this is the categorical model with interpolation
— and the archetype set becomes the thing a player learns. It also has no natural way to
express a posture nobody named.

## The decision (SETTLED 2026-09-04)

**(a) as the strategy layer, with (b) underneath it as objective selection.** The posture
vector says how to play; scored objectives say what to go for; the existing modules say how
to do it. Three levels, each a comparison, each searchable.

## First: the signals, because one of them is missing

The note's own first check was whether the postures are *decidable* from what the bot can
currently sense. Mostly yes — and the gap is specific.

| What a posture turns on | Sensed today? |
|---|---|
| Do I have a timing advantage right now | **Yes** — `army_resource_value` against `believed_enemy_army_value`, under the humility prior |
| Am I winning or losing | **Yes** — `BotMomentum` |
| How exposed am I | **Yes** — `relative_threat_level`, `is_base_under_threat` |
| How much do I know | **Yes** — `BotScout.stale_fraction` |
| How far along is the game | **Yes** — `game_phase`, `seconds_elapsed` |
| **Am I ahead or behind on ECONOMY** | **No** |

**There is no income sense at all, for either side.** `extractor_count()` counts our own
extractors and nothing counts theirs, nothing reports an income RATE, and the blackboard
remembers enemy structures without asking what they produce.

That single absence is disqualifying for both of the postures this note is named after:

- **Booming is a response to being behind on economy** (or to being safe enough to get
  ahead). Without an income comparison the bot can only boom on a timer, which is a build
  order — the exact thing being designed away.
- **All-in is a response to the opponent being ahead on economy** — spend now, because later
  is worse. Read only from army values, the bot cannot tell "they out-produce me" from
  "they happen to have fewer units on the field right now", and those call for opposite play.

> **TODO — build the economy signals before the posture layer.** Own income rate is
> arithmetic over `EnergyExtractor` components. The enemy's is an ESTIMATE from the
> blackboard: count believed enemy extractors and production structures and price their
> output. It is fog-limited and will be wrong, which is correct — being wrong about the
> opponent's economy is a thing players are, and it is what makes scouting pay.

> **TODO — a posture that changes every think is not a strategy.** Whatever the
> representation, it needs hysteresis: a strategy the bot abandons the moment a signal wobbles
> is noise, and the talk's criticism of a bot that hard-commits has a mirror image in a bot
> that never commits to anything. Commitment over time is what makes a posture legible to the
> player, which is what makes beating it satisfying.
