---
title: The world model
type: system-note
---

# The world model

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**TODO — an unapproved proposal.** A single, fog-limited, layered model of the game state
that every decision module reads INSTEAD of the scene tree. What exists is
[bot-architecture](bot-architecture.md) §Perception; the gaps it would close are the
perception items in [bot-roadmap](bot-roadmap.md) and the economy signals
[objective-selection](objective-selection.md) is blocked on. Open decisions are the `TODO`s
at the end; nothing below is to be built until they are answered.

## The problem

The bot's "senses" are about 130 read-only query functions on `Bot` (`bot.gd`, 1 600 lines)
plus the `CommanderBlackboard` (a flat `instance_id → Entry` dictionary, snapshot not history)
and a scout grid that only `BotScout` can see. Each manager calls whatever senses it needs, on
its own cadence. Three things follow, and together they are the ceiling on decision quality:

1. **There is no intermediate representation.** A manager gets either raw entity lists or a
   bespoke answer to one question (`most_threatened_structure`, `threat_direction`,
   `enemy_demand_map`). Every new decision needs a new sense, written against the scene, and
   the senses cannot be composed: "the smaller of two threats", "an undefended approach",
   "am I ahead on income", "is the enemy base gone or just unfound" are each a fresh function
   rather than a read of something already known.
2. **The fog boundary is not structural, so it leaks.** Three senses read hidden state today
   — see §The fog boundary. Each was written honestly and leaked anyway, because nothing
   separates "what the bot may know" from "what the engine knows".
3. **Perception has no memory beyond last-seen.** The blackboard keeps one position and one
   timestamp per enemy. Momentum cannot see enemy losses, nothing notices a composition shift,
   a believed unit is counted in the army estimate but not trusted as a destination, and the
   scout's grid, the dominion survey's lattice and the build-spot search are three spatial
   quantisations of the same ground, one of which is not mirror-symmetric
   ([bot-architecture](bot-architecture.md) §What it was measured to fix).

The brief ([brief.md](brief.md)) asks for the opposite: decisions derived from signals, with
hard-coding confined to "the most minute details", and a model generic enough that a new
dominion method or a retuned scout unit changes the bot's play without changing its code.

## Frameworks adapted

Four established frameworks fit this bot; the model below is their intersection, named in the
repo's own vocabulary. Each is cited so the reasoning can be checked, and none is adopted
wholesale.

**The JDL data-fusion model** (Steinberg, Bowman & White, 1999; the standard model in
sensor fusion) is the closest thing to a "signal processing" ontology for a perceiving agent.
It defines levels: **L0** signal assessment (raw detections), **L1** object assessment
(*tracks*: identity, state and history per object), **L2** situation assessment (relations
among objects — groups, regions, who covers what), **L3** impact assessment (what the
situation means for one's own goals and assets), and **L4** process refinement (*sensor
management*: deciding where to look next). The mapping onto this bot is unusually tight —
the blackboard is a degenerate L1, `enemy_clusters` is L2, `BotMomentum` is L3, and
`BotScout`'s information-value scoring is already L4 — which is the argument for using its
levels as the model's layers.

**OODA** (Boyd) names the step the bot lacks: between *Observe* and *Decide* sits
*Orient*, where observations are fused into a picture. Today Orient is done ad hoc inside
every decision, which is why it is done many times, inconsistently, against the live scene.
The model makes Orient a materialised, cached object refreshed on cadence.

**BDI** (Bratman; Rao & Georgeff) supplies the vocabulary the repo already half-uses:
**beliefs** (the model, fog-limited and uncertain), **desires** (postures and objectives —
[objective-selection](objective-selection.md)) and **intentions** (committed plans: a launched
wave, a `PLANNED` build, a claim). Its one lesson worth importing is that intentions
*persist* — commitment is what turns reasonable instants into a plan, and is the answer to
"a posture that changes every think is not a strategy".

**Influence maps** (Tozour, *Game Programming Gems 2*, 2001; Mark, "Modular Tactical
Influence Maps", *Game AI Pro 2*, 2015; the Total Annihilation / Supreme Commander lineage)
are the standard L2 spatial representation for RTS AI: a coarse lattice carrying several
channels — own influence, enemy influence, threat (weapon reach), *tension* (their sum) and
*vulnerability* (tension minus the absolute difference) — from which front line, undefended
approach, safe build spot and avoid-region are all reads rather than searches.

Two further sources inform specific layers. The StarCraft AI research survey (Ontañón et
al., 2013) names partial observability, opponent modelling and spatial reasoning as the open
problems, and the convention of ONE information-manager module owning all enemy knowledge
is what §The fog boundary enforces; Synnaeve & Bessière's Bayesian opponent modelling
(2011) is the pattern for §L2 Tech inference — infer what is unseen from what was seen,
rather than read it. AlphaStar's observation encoding (Vinyals et al., *Nature* 2019) — an
**entity list**, **spatial layers** and **scalar features** — is what L1, L2-fields and L3
reduce to; the model is shaped so that a learned policy could later consume it unchanged,
which is the brief's adversarial-training ambition.

**REJECTED — a planner (GOAP, HTN) as the model.** Those are decision architectures, and the
roadmap has settled on utility arbitration in energy-equivalent units
([bot-roadmap](bot-roadmap.md) §The currency). The world model feeds that; it does not
replace it.

## The model

One world model per commander-and-bot pair, refreshed by perception jobs that run before
every decision job, read by every manager. **A manager reads the model and the config and
nothing else.** Each layer is a pure `RefCounted` that takes the layer below as input, so each
is unit-testable from a fixture with no scene (`~/.claude/CLAUDE.md` §7).

**Which half lives where is decided by one test (2026-10-06): is this information part of a
human player's own perception of the game?** If the game presents it to the player, or a
player naturally holds it, it is a `Commander` fact and the bot reads the SAME signal the HUD
does. If it is a construct made for the bot — a quantisation, a heat map, a derived group —
it is the bot's alone, and it is tracked only to the extent it mirrors what a player would
hold in their head rather than to exceed it.

| information | lives on | why |
|---|---|---|
| fog of war; what is visible now (L0) | `Commander` | presented to the player; already per commander |
| remembered pieces (L1 tracks) | `Commander` | the blackboard's precedent — the snapshot meshes are the player-facing face of the same memory |
| the sight-age lattice, fields, groups (L2) | bot | a human reads the minimap; the heat map and the clusters are the bot's stand-in for that reading |
| assessment and attention (L3, L4) | bot | a commander's judgement |

The JDL levels are a sound skeleton for this bot, and the line above is the intentional part:
each new signal is placed by asking whether a player has it, not by which level it is on.

```
scene / fog ──L0 sightings──▶ L1 tracks ──▶ L2 situation ──▶ L3 assessment ──▶ managers
                                 ▲                                │
                                 └──────── L4 attention ◀─────────┘   (what to look at next)
```

### L0 — Sightings: events, not state

What the fog delivers, as a stream. One `Sighting` per enemy or neutral piece in vision per
perception tick: `{instance_id, type, owner, position, tick, hp_fraction, is_structure}`,
plus a `facing`/velocity hint where the piece moved since the last tick. Two kinds of
evidence the blackboard does not record today:

- **Negative evidence.** The set of lattice cells in vision this tick, with no sighting in
  them. This is what *disproves* a belief, and it is what the bot walks to the objective to
  discover today ([bot-engagement-fixes](bot-engagement-fixes.md) §What this does NOT explain).
- **Own-side events.** An own piece died (where, to which type), damage taken (where from),
  a kill witnessed. The ledger L3 needs.

L0 is the ONLY code that touches `Commander.visible_enemies`, `visible_foreign_structures`,
`has_vision_at` and the fog. Everything above it is a function of sightings.

### L1 — Tracks: the blackboard with memory

`TrackTable` generalises `CommanderBlackboard.Entry`. Per piece:

| field | meaning |
|---|---|
| `type`, `owner`, `is_structure` | as today |
| `first_seen`, `last_seen`, `last_position`, `last_hp_fraction` | history, not just last |
| `velocity` | from consecutive sightings; zero for structures |
| `status` | `CONFIRMED` (in vision now) · `BELIEVED` (out of vision, confidence above floor) · `LOST` (disproved by negative evidence, or expired) · `DESTROYED` (death witnessed) |
| `confidence` | ∈ (0, 1]. Structures: 1 until negative evidence at their cell. Units: decays with time AND with the fraction of their *reachable disc* (speed × time since seen) that has since been seen empty — a unit that could only have gone somewhere the bot has looked is more likely gone. Decided 2026-10-06, on one condition: the disc check is a lattice read per track per perception tick, budgeted and measured like every other channel (§Cadence and cost) |
| `affordances` | the type's provider/consumer tags (§Affordances), so higher layers reason without per-type code |

Rules, replacing today's leaks:

- **Never `is_instance_valid`.** The live reference is kept only to re-identify a piece on
  re-sighting; it is never consulted for liveness. A track leaves the table by negative
  evidence, witnessed death, or confidence falling below the floor.
- **Tracks are keyed by instance, and that is a known concession.** A player who sees a
  soldier vanish into fog and another appear five seconds later cannot say whether it is the
  same soldier; the bot can, because the table re-identifies by instance id. Decided
  2026-10-06: keep the identity, since it is what makes re-sighting cheap and no decision
  gains meaningfully from it — the advantage it confers is a slightly better count, not a
  better plan. Revisit only if a decision is found to lean on it.
- **Own pieces and neutral features are tracks too**, uniformly — and neutral features are
  DISCOVERED like everything else. Decided 2026-10-06: the fog's unexplored and shaded states
  are the one thing that determines whether the bot is aware of a piece. This retires today's
  deliberate exception for loose Terrestrials, neutral extractors and bunker hosts
  (`bot.gd:989`); liberation, capture, scouting responsibility and the extractor survey read
  tracks instead. Difficulty tiers get no extra information: a very hard bot is tuned, not
  told.
- **A ledger**: witnessed enemy losses and own losses, by type, time and place. The input
  momentum lacks ([bot-roadmap](bot-roadmap.md) §Reading the game).

The visual snapshot layer (remembered structure meshes) stays on `CommanderBlackboard` —
it is player-facing rendering, not belief — and reads L1 for what to show.

### L2 — Situation: relations and fields

Derived from L1 once per cadence and cached; a manager never recomputes it.

**Groups.** `enemy_clusters` over BELIEVED tracks, members weighted by confidence
([bot-roadmap](bot-roadmap.md) §The vision layer), bucketed on the lattice so grouping is linear rather
than O(n²) (same section). Own-side groups the same way, which is the representation
[squads-and-relations](squads-and-relations.md) needs for "leave half at home".

**Fields.** ONE lattice, replacing the scout grid, the dominion survey's lattice and the
build-spot search's disc as the bot's spatial quantisation. Anchored to the map centre so a
reflected map reflects the lattice (closing the asymmetry at
[bot-architecture](bot-architecture.md) §What it was measured to fix). Channels:

| channel | from | reads it answers |
|---|---|---|
| `sight_age` | L0 negative evidence | the scout grid's role: stale, never seen |
| `own_influence`, `enemy_influence` | tracks × strength, decayed by confidence, spread by speed | front line, control fraction |
| `threat` | weapon reach of believed enemies | "can a unit stand here", retreat destinations |
| `tension` / `vulnerability` | influence sums and differences | undefended approach, where to defend, where to raid |
| `avoid` | lingering area effects (emissions publish into it) | the avoid-region signal ([bot-roadmap](bot-roadmap.md) §The gaps in the decision surface) |
| `value` | resource sites, dominion sites, shelters | expansion and dominion surveys |
| `approach` | sampled paths from believed enemy groups to own base | approach coverage ([squads-and-relations](squads-and-relations.md) §Placement beyond open ground) |

**Composition and tech inference.** Believed enemy counts by type; and — the one inference
step — the enemy's tech: having seen type X implies the enemy owns whatever
`technology_mapping` says produces and unlocks X. Reading the enemy's structures through the
units it fields is how a player scouts, and it is what the counter-demand map should be
computed from rather than from a live `rep` entity (`bot.gd:1395`).

**Economy estimate**, both sides: own income is arithmetic over `EnergyExtractor`
components; the enemy's is believed extractors × rate, with confidence. The signal
[objective-selection](objective-selection.md) §First: the signals is blocked on.

### L3 — Assessment: what it means for me

Scalars and per-asset reads, in energy-equivalent units where a value is a value:

- **Per own asset**: threat exposure (field read at its cell) and survivability — the
  per-structure read [bot-roadmap](bot-roadmap.md) §The gaps in the decision surface asks for when picking a producer.
- **Momentum** from BOTH sides' ledgers, so a costly winning fight reads as winning
  (§Reading the game); engagements segmented by the ledger's time gaps, which is also the per-engagement
  "did that trade well" `BotMomentum` names as the missing measure.
- **Standing**: army value ahead/behind (believed), income ahead/behind, control fraction —
  the posture inputs.
- **Enemy presence**: `KNOWN_STRUCTURES = 0` is distinguished from `UNEXPLORED_FRACTION` —
  the "no structures left" versus "not found yet" distinction whose absence produces ghost
  marches ([bot-engagement-fixes](bot-engagement-fixes.md) §The controlled comparison). Each is a number already in
  L1/L2; the distinction is just reading both.
- **Counter-demand** (`enemy_demand_map`), moved here, computed from L2 composition.

### L4 — Attention: what is worth looking at

The model's own output back to itself: a ranked list of *questions*, each priced in
energy-equivalent — "is the believed base still at X" (stakes: the whole attack plan),
"what is at this never-seen high-`value` cell", "confirm or disprove this low-confidence
group near my flank" — with value = stakes × uncertainty, as `BotScout`'s
`INFORMATION_VALUE_ENERGY × stale_fraction` already prices the undifferentiated case.
`BotScout` and the REVEAL sanction consume this list instead of owning a grid. Scouting
becomes sensor management in the JDL sense: the decision side chooses WHO looks; the model
says WHAT is worth seeing.

### Affordances: the signal the brief asked for

The brief wants a new piece's use to be a matter of data the bot reads, not code written for
it. Piece docs already drive scenes through the importer; they would carry an **affordance**
block the importer validates and L1 attaches to every track of that type:

```
affordances:
  provides: [vision, income, dominion, infrastructure, production, defence, transport, spotting]
  consumes: [infrastructure]
```

L2 and L3 then reason over tags: an enemy `spotting` provider is worth more than its cost
(the fourth relation in [squads-and-relations](squads-and-relations.md) §Relations); a `vision`
provider with high speed is a scout candidate; a `dominion` provider is what the dominion
drive wants more of, whatever faction mechanism produces it. Hard-coding is confined to the
tag vocabulary — "the most minute details" — and a new piece reaches the bot by being
annotated.

## The fog boundary

A rule, and a check at the earliest stage where its inputs are fixed (`~/.claude/CLAUDE.md`
§5.4): **only L0 may call the fog-dependent scene queries, and no manager may read enemy
state from the scene at all.** The check is a `tests/test_SuiteIntegrity.gd`-style scan over
file text: a list of forbidden identifiers (`visible_enemies`, `get_enemies_near`,
`get_nodes_in_group("piece")`, `is_instance_valid` on a track's entity, …) that may appear
only in the perception files. A leak then fails CI rather than surviving as an honest
mistake.

The three leaks it would have caught, found 2026-10-06 while surveying for this note. Each is
a bug today, listed here so the design accounts for them structurally; none is fixed yet:

1. `Commander.get_enemies_near` (`commander.gd:1305`) has no visibility filter. It drives
   `is_base_under_threat`, `most_threatened_structure` and `threatened_command_centre`
   (`bot.gd:252–290, 526`), and through them the DEFEND posture (`bot_military.gd:448`),
   `BotEconomy.safety()` (`bot_economy.gd:698`) and defensive sanction aiming
   (`bot_sanction.gd:188`). Only `BotTargeting` adds its own `is_visible_to`.
2. `believed_enemy_army_value` (`bot.gd:1462`) and `enemy_demand_map` (`bot.gd:1390`) drop
   entries whose entity fails `is_instance_valid` — an enemy that dies out of sight leaves
   the estimate instantly, against the blackboard's own rule (`commander_blackboard.gd:13`).
3. `BotMilitary._objective_is_standing` (`bot_military.gd:323`) checks the remembered
   objective's liveness, so a wave knows its target fell before any unit could see it.

In L1 terms each is one status read: (1) threat is a field over CONFIRMED tracks, (2) sums
run over BELIEVED tracks whatever happened to the node, (3) an objective stands until its
track is LOST or DESTROYED.

## Cadence and cost

Perception is jobs on the shared `BotScheduler` budget like everything else
([think-scheduling](think-scheduling.md)), at priorities above `momentum`: L0/L1 on the
blackboard's existing ~5 Hz, L2 fields on the combat period, L3 on the strategy period, L4 on
the scout period. Field updates are resumable sweeps with a cursor — a lattice at the scout
grid's 5-unit pitch is a few thousand cells, and influence spreading is bounded by
reach, so the cost is bounded and measurable per channel. Determinism holds as today: every
input is the bot's own sightings, and the lattice is symmetric by construction.

**Performance is a requirement of this design, not a follow-up** (decided 2026-10-06): the
piece count is what the signal processing scales with, so each channel's cost is measured on
the self-play harness against [bot-performance](bot-performance.md)'s tick budget before the
next channel lands, and the lattice pitch is a single constant — 5 world units, coarser if
measurement says so — never finer than the scout grid is today.

## Testing

Every layer is a pure function of the layer below, so each has fixture-driven GUT tests with
no scene: a sighting stream in, tracks out; tracks in, fields out. Two properties are worth a
test each: **confidence is calibrated** — over a seeded match, the fraction of BELIEVED tracks
that are actually present on re-sighting should track their confidence (the one number that
says the model is honest rather than merely fog-respecting) — and **the lattice is
mirror-exact** on a symmetric map. The fog-boundary scan is a third.

## Migration

Incremental, one landable change each, in the order that pays earliest:

1. **Make the boundary explicit.** Route the three leaks through visibility and belief status
   (fixes the bugs above with no new machinery); add the forbidden-identifier scan.
2. **Extract `TrackTable`** from `CommanderBlackboard`, with status, confidence and the
   ledger; snapshots read it. The blackboard's open question
   ([bot-engagement-fixes](bot-engagement-fixes.md) §What this does NOT explain) is answered by negative evidence.
3. **One lattice**: move the scout grid into `BotFields`, anchored to the map centre; add
   `enemy_influence` and `threat`. `BotScout` reads `sight_age`.
4. **Believed clusters** from tracks; **momentum** from both ledgers.
5. **L3 standing and enemy-presence reads**; the military's objective choice reads them.
6. **L4 attention**; `BotScout` and REVEAL consume it.
7. **Affordance tags** in docs and the importer; `BotScout`'s scorer and the dominion drive
   read them.

Steps 1–3 remove code; 4–7 add what the roadmap already lists, on a representation that
exists.

## Open decisions

Four of the five decisions this note was written with are made (2026-10-06) and folded into
the sections above: where each layer lives (§The model), the reachable-disc confidence and
instance-keyed tracks (§L1), the 5-unit pitch and the performance requirement (§Cadence and
cost), and neutral features discovered rather than known (§L1). One remains:

> **TODO — tag vocabulary for affordances.** The list above is a first cut from what the
> managers already distinguish. It is to be revisited as the ontology of what the model can
> signal develops — fixed from the piece-usage audit's "cannot signal" rows
> ([piece-usage-audit](piece-usage-audit.md)) before the importer validates it, and not before.
