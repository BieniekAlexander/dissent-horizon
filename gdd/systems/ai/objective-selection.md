---
title: Objective selection
type: system-note
---

# Objective selection

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

The layer above every decision the bot makes — built 2026-10-09 as `BotPosture`, with its
signals in `BotIncome` and `BotFirstContact` and its wiring in `BotBrain` (§The build below).
What it sits on is [bot-architecture](bot-architecture.md); the other gaps are in
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

## The build (2026-10-09)

Five decisions, each answered by Alex on 2026-10-09 and recorded here; what each
superseded is kept so it is not proposed again.

### The mapping

**Each dial reads the one or two signals named for it, with a gain per pair and a bias per
dial** (decided over a full linear map of every signal to every dial — 28 fields nobody could
read in the overlay — and over an authored, unsearched mapping). A dial's target is its bias
plus gain × signal, clamped to [0, 1]; the gains and biases are `BotDifficulty` fields, every
one searched (`bot-parameter-space.md` §The posture layer):

| Dial | Signal(s) | Each in | Read from |
|---|---|---|---|
| `commitment` | economy lead | [−1, 1] | `BotIncome.economy_lead` — own income against the enemy estimate below |
| `aggression` | army lead; exposure | [−1, 1]; {0, 1} | own army value against `BotMilitary.enemy_value_estimate` (the humility prior applied); `Bot.is_base_under_threat` |
| `risk` | momentum; threat | [0, 1]; [0, 1] | `BotMomentum.loss_rate` over its losing threshold; how soon the nearest believed enemy could be at the base, against the fields' quiet horizon |
| `curiosity` | stale fraction | [0, 1] | `BotScout.stale_fraction` |

**A dial DIVIDES the parameters it reaches by 2^(2d − 1)**, so 0.5 is neutral, 1 halves and 0
doubles, each result clamped to the field's search range (the range is what the field means)
and a sentinel left alone, exactly as the personality draw leaves it. `commitment` reaches
`income_structure_target` and `army_commit_threshold`; `aggression` reaches
`attack_value_ratio` and `guard_strength_ratio`; `risk` reaches `economy_reserve` and the
opening prior below; `curiosity` scales `BotScout`'s information price. `BotBrain._apply_config`
pushes the MODULATED copy (`BotPosture.applied_to`) into the managers, so `config` stays
what the bot was given and the managers play by what the posture makes of it. **Every gain
ships at 0 and every bias at 0.5** — a tier plays exactly as it did until a search or a
personality draw moves them, the same position every other searched field took.

**A finding worth keeping:** nothing is believed on a bot's FIRST think (the blackboard has not
run), so the army lead then reads the humility prior's own optimism — nothing seen is
"slightly ahead", by (1 − parity) / (1 + parity) ≈ 0.08 — and a large `aggression_army_gain`
commits a blind bot in its first second. The decision sim `sims/bot/posture/
ahead_on_army_attacks_at_once` is tuned under that ceiling.

### Hysteresis

**A dead band and a minimum hold, then a snap** (decided over exponential smoothing, and over
smoothing plus a hold): a dial moves only once its target has stood more than
`posture_dead_band` from the held value for `posture_hold_seconds` without returning, and
then takes the target outright. Smoothing reads as drift; a hold and a snap read as a
decision, which is what makes a posture legible — and beatable — for the player. The first
update snaps, there being no history to hold against. Both fields are shared by the four
dials and searched.

### The economy signals

Own income is `Commander.energy_collection_rate`, the steady rate of standing extractors. The
enemy's is **a prior that observation replaces piecewise** (decided 2026-10-09 over a bare
count of believed extractors, and over pricing every believed structure: both read "they have
nothing" to a bot that stayed home, and Alex's concern was that a count's variance makes it
useless). The enemy is assumed to earn `assumed_enemy_income_parity` × the bot's own income
— the economy twin of `assumed_enemy_parity`; that prior is spread evenly over the SHELTER
BANDS the enemy could have started in (every shelter but the bot's own: generation puts a
start's shelter inside a band around it, and the shelters are shown from match start —
[map-generation](../terrain-and-navigation/map-generation.md) §3); and for each band, as far
as the scout grid has freshly seen it, that share is replaced by the income structures the
bot believes stand there, priced by type (an extractor's rate, a pond's multiple). A believed
income structure outside every band counts whole. Low variance by construction — the
estimate moves with the bot's own income and one band at a time — and the gap between a
band's prior and its observation is what scouting that band is worth. On a map with no
shelters, the scout grid's stale fraction scales the prior instead. `BotIncome`; the band's
radius is the generator's `shelter_start_band_max_cells`, from the generator's defaults since
a map does not carry its parameters (TODO, noted there).

### The opening prior

**Before any sighting the threat clock reads an estimated first-contact time** (decided
2026-10-09; the lattice-walked alternative — the enemy assumed at every start point the bot
does not hold, walked along the fields — was declined as more complexity than it is worth):
the start separation the map's dimensions and the start placement parameters imply, walked
in a straight line at the fastest ground speed in the opposing faction's starting units,
`BotFirstContact`. It is the one place the dials fill missing information: `risk` scales it —
a greedy bot assumes it has time, a cautious one that the raid is near — and it counts down
from match start. `BotFields.arrival_seconds_at` answers with it while nothing is believed, so
`is_quiet_at` and the Fields overlay read it; nothing else asks the clock before a sighting.

**What the prior weighs on is a PHANTOM OPENING FORCE** (decided 2026-10-09, over the prior
as the economy's safety term only, and over leaving it a read): the enemy factions' starting
units — a public roster — assumed to be walking at the base, weighed in the demand map and
the clocked composition at the opening prior exactly as a believed unit is at its measured
arrival (`Bot.phantom_force`, `Bot.phantom_force_clocked`). The unseen base was already
proxied by a structure; this is the same move for the opening army. It lapses for good at the
first enemy unit the blackboard ever records (`CommanderBlackboard.has_believed_unit`): a
belief that later expires does not un-see the opening, and a prior that counted down to zero
would otherwise press in full for the rest of the match whenever nothing was in view. The
guard's arrival term is not fed: it sizes a guard against a threat at a structure, and a
phantom stands nowhere.

### Parity stays its own field

`assumed_enemy_parity` is not folded into `risk` (decided 2026-10-09: one moving part at a
time, and the rosters already carry a parity each). TODO: revisit the fold once the layer has
been measured on its own.

### What a player sees

The **Posture** category of the bot debug overlay ([debug-signals](debug-signals.md) §Posture)
shows each dial's held value, target and factor, when a held-out target will snap, the six
signals, the income estimate's terms band by band, and the opening prior. The self-play brain
sample carries the dials and the two income figures ([selfplay-harness](selfplay-harness.md)).
Decision sims: `sims/bot/posture/`.
