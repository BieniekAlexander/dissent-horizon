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

**The model is a blackboard, and it holds STATE, never logs** (decided 2026-10-06). Two
rules, both from the compute budget being small:

- **Every signal is computed once, on its cadence, stored, and READ.** A manager that
  recomputes what the model already holds is the bug; a signal two managers want is a signal
  the model stores. This is the blackboard discipline the roadmap's utility arbitration
  already assumes, applied to perception.
- **The Markov property.** Where the past matters it is consolidated into a small number of
  present data points that overwrite themselves; where a past state stops mattering (a clip
  refilled, an ability recharged) its datum expires on its own. Nothing is appended to and
  searched later. No event log exists anywhere in the model.

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

### L0 — Sightings

What the fog delivers, each perception tick, for the pieces inside the bot's focus (§L4):
one `Sighting` per visible enemy or neutral piece — `{instance_id, type, owner, position,
tick, hp_fraction}` — plus, when a piece was seen to act, the ONE fact about the action that
outlives it: a weapon fired (so its clip is down), an ability used (so it is recharging).
Those become expiring state on the track (§L1); they are not kept as events.

Two gates sit on L0, both from the [ontology](ontology.md) §Time, both with starting values
to be retuned in testing:

- **the perception floor**, 1.0 s: nothing that exists for less is delivered at all — a lead
  round never enters the model;
- **reaction latency**, per tier: a sighting is delivered only once it has persisted that
  long. `EASY` 2.0 s · `MEDIUM` 1.0 s · `HARD` 0.5 s · `IMPOSSIBLE` one perception tick
  (0.2 s at the blackboard's 5 Hz).

**Negative evidence is a check, not a set** (decided 2026-10-06, replacing the first draft's
"cells seen empty"). Per track inside the focus, per tick, two lookups — is its last-known
position fog-clear now, and was it among this tick's sightings. Clear and absent is the
evidence: a structure track goes `LOST`, a unit track takes a sharp confidence cut. O(tracks)
with a pixel read each, and no spatial bookkeeping. The `sight_age` channel (§L2) is stamped
the same way, lattice cells against the fog's cleared set on a resumable sweep — which is
what replaces `BotScout`'s raycasts ([ontology](ontology.md) §Vision is unoccluded).

L0 is the ONLY code that touches `Commander.visible_enemies`, `visible_foreign_structures`,
`has_vision_at` and the fog. Everything above it is a function of sightings.

### L1 — Tracks: the blackboard with memory

`TrackTable` generalises `CommanderBlackboard.Entry`. Per piece:

| field | meaning |
|---|---|
| `type`, `owner`, `noun` | as today, plus the ACTIVE noun ([ontology](ontology.md) §Pieces) |
| `last_seen`, `last_position`, `last_hp_fraction` | the last sighting |
| `velocity` | from the last two sightings; zero for fixtures |
| `status` | `CONFIRMED` (in vision now) · `BELIEVED` (out of vision, confidence above floor) · `LOST` (negative evidence, or decayed out) · `DESTROYED` (death witnessed) |
| `confidence` | ∈ (0, 1]. Exponential decay in time since last seen, with a half-life per noun — units short, structures very long, features effectively none — cut sharply by the negative-evidence check. Decided 2026-10-06; the first draft's reachable-disc rule is REJECTED, since it was the one part that needed per-cell bookkeeping and the decay plus the last-position check gets most of the honesty |
| `ammo`, `ability` | EXPIRING STATE: `{empty, refills_at}` from `Weapon.reload_time_ticks` / `clip_size` / `charged`; `{id, ready_at}` from the ability catalog's cooldown. Written when the action was seen inside the focus, read until the time passes, then gone. This is the whole of a track's "history" |
| `affordances` | the type's derived capability set ([ontology](ontology.md) §Affordances), so higher layers reason without per-type code |

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
- **Enemy presence is an L1 read.** `believed_structure_count` is a count over the table;
  with the `sight_age` channel's unexplored fraction it is what separates "no structures
  left" from "not found yet" ([bot-engagement-fixes](bot-engagement-fixes.md) §The controlled
  comparison). L3 only combines the two.

**Per-commander knowledge** sits beside the table, for the few facts worth keeping for the
whole match: two MONOTONE sets that only grow and stay small — the enemy's inferred tech
(seen type X ⇒ owns what `technology_mapping` says produces and unlocks X) and the modifiers
observed (an upgrade seen in effect). This, and the expiring state above, is the entire
memory of the model.

**REJECTED (2026-10-06) — a ledger of own losses.** No mechanic makes a bot that had three
units and lost one play differently from one that always had two. The one consumer, momentum,
is served by the `combat` channel (§L2) instead.

The visual snapshot layer (remembered structure meshes) stays on `CommanderBlackboard` —
it is player-facing rendering, not belief — and reads L1 for what to show.

### L2 — Situation: relations and fields

Derived from L1 once per cadence and stored; a manager never recomputes it.

**Groups.** `enemy_clusters` over BELIEVED tracks, members weighted by confidence
([bot-roadmap](bot-roadmap.md) §The vision layer), bucketed on the lattice so grouping is
linear rather than O(n²) (same section). Own-side groups the same way, which is the
representation [squads-and-relations](squads-and-relations.md) needs for "leave half at
home".

**One lattice.** Today three quantisations of the same ground disagree: the scout grid (5
units, world-anchored with `roundi`, hence the mirror asymmetry at
[bot-architecture](bot-architecture.md) §What it was measured to fix), the dominion survey's
lattice (5 cells, centred on the base), and the build-spot search's disc. They become ONE
grid-geometry object — pitch 5 world units, origin at the map centre, world↔index — carrying
several CHANNELS, and every consumer reads it. The channels, each recomputed from tracks on
its cadence rather than accumulated, each piece stamping a disc bounded by its reach:

| channel | definition | reads it answers |
|---|---|---|
| `sight_age` | seconds since the cell was last fog-clear | stale, never seen; the unexplored fraction |
| `own_influence`, `enemy_influence` | Σ over pieces with lethality of energy value × confidence × falloff over (reach + speed·τ), τ the combat period | who controls here; the front, where own ≈ enemy and both are high |
| `threat` | Σ dps of enemy weapons that can REACH the cell, stored PER DAMAGE TYPE (a handful of channels); a unit reads its own threat as Σ_type dps × `DamageTable` multiplier against its armour — relational without a channel per armour class | standing here costs this much HP per second; retreat destinations |
| `tension`, `vulnerability` | own + enemy; tension − \|own − enemy\| | where fights happen; contested ground |
| `value` | resource sites, dominion sites, shelters, structures by energy value, per side | what is worth taking, holding, or hitting |
| `approach` | sampled paths from believed enemy groups to own base | approach coverage ([squads-and-relations](squads-and-relations.md) §Placement beyond open ground) |
| `avoid` | lingering area effects publish into it | the avoid-region signal ([bot-roadmap](bot-roadmap.md) §The gaps in the decision surface) |
| `combat` | witnessed damage stamped at its cell, decayed per period | engagements (§L3) |
| `reach_coverage` | for a candidate cell and a weapon reach: the fraction of the reach disc that is passable ground on an `approach` | whether a static defence placed here guards anything |

The derived reads over them, stored too: an **undefended approach** (high `approach`, low
`own_influence`); a **safe build spot** (low `threat`, high `own_influence`, high
`reach_coverage` for a defence); an **exposed enemy position** (high enemy `value`, low
enemy `threat`, low `enemy_influence` — many structures, no weapons, nothing defending);
and its mirror, the bot's **own exposure** — the same read over its own structures, which is
where units and static defences belong. The clustered turrets whose ranges covered cliffs
(observed 2026-10-06) score near zero on `reach_coverage`, which is the placement the read
rejects.

**Enemy income** is believed extractors × `EnergyExtractor.energy_rate`, with confidence —
the signal [objective-selection](objective-selection.md) §First: the signals is blocked on.
**REJECTED (2026-10-06) — an enemy dominion-rate estimate**: a `DominionGenerator` is a piece
with an income affordance and is priced as infrastructure worth killing through the ordinary
utility comparison, which removes the estimate entirely.

**Counter-demand** (`enemy_demand_map`) is computed from the believed composition and the
inferred tech, never from a live `rep` entity (`bot.gd:1395`).

### L3 — Assessment: what it means for me

Reads over L1 and L2, in energy-equivalent units where a value is a value, stored on the
model:

- **Per own asset**: `threat` at its cell and the survivability that follows — the
  per-structure read [bot-roadmap](bot-roadmap.md) §The gaps in the decision surface asks
  for when picking a producer.
- **Engagements and momentum.** An engagement is a connected region of the lattice where
  `combat` is above threshold; momentum is computed PER ENGAGEMENT, from value destroyed by
  each side inside it (two decaying scalars, overwritten as damage is witnessed). A costly
  winning fight reads as winning, "did that trade well" is a read of the region, and nothing
  is segmented in time ([bot-roadmap](bot-roadmap.md) §Reading the game).
- **Static-defence demand** (decided 2026-10-06; built on presence 2026-10-07,
  `BotEconomy._defence_demand`, lattice form pending): per own exposed region,
  `value × vulnerability`, in energy-equivalent. A static defence is placed lethality — an
  investment in one region that cannot be moved — so the decision to build one comes from
  this read exceeding the tower's cost, and never from a count. **REJECTED — a
  `defence_structure_target` default.** It made towers an opening purchase by construction
  (three early towers in a clump, observed 2026-10-06 on `main`); the economy's defence rung
  becomes an opportunity priced by this read, placement maximises `reach_coverage` over the
  region's `approach` rather than compactness, and a second tower must clear the demand
  REMAINING after the first's coverage. A tier knob, if wanted, is a propensity weight on the
  demand, not a count.
- **Standing is LOCAL** (decided 2026-10-06). Per own group: its value against the enemy
  influence within its reach. An army beside an exposed enemy position reads a strong standing
  there and a futile one at the base under attack across the map, and attacks where it is —
  no special rule. The global figures (army value, income, control fraction) are sums kept
  for the posture layer, and no decision about a group reads them.
- **Enemy presence**: the L1 count against the L2 unexplored fraction.

### L4 — Attention: what is worth looking at, and where the bot is looking

The model's own output back to itself: a ranked list of *questions*, each priced in
energy-equivalent as stakes × (1 − confidence) — "is the believed base still at X" (stakes:
the whole attack plan), "this resource site read empty three minutes ago" (stakes: its
`value`), "confirm this low-confidence group near my flank". `BotScout`'s
`INFORMATION_VALUE_ENERGY × stale_fraction` is the special case where every cell has equal
stakes. Two consumers read the one ranking: **scouting** (where to send a unit — `BotScout`
and the REVEAL sanction) and **focus** (where the bot looks).

**Focus, rudimentary** (decided 2026-10-06; tune in testing): `k` discs of radius `R` on the
lattice, centred on the top-`k` entries of the ranking, each moving at most one lattice hop
per scout period. L0 delivers sightings only inside a disc; outside, only commander-wide cues
and the coarse fields get through — something is THERE, as a blob on a minimap, without
composition or heading. Starting values: `EASY` k=1, `MEDIUM` k=2, `HARD` k=3, R = 15 world
units; `IMPOSSIBLE` has no discs, its focus is the lattice. The allowance is a
`BotDifficulty` parameter and a MODEL budget; the scheduler's work units are a COMPUTE
budget, and a tier's attention is never defined as what fits in the frame.

### Affordances: the signal the brief asked for

The brief wants a new piece's use to be a matter of data the bot reads, not code written for
it. **Affordances are DERIVED from the components a piece carries, not declared as tags** —
superseding this note's first draft, which proposed a `provides:` tag block (REJECTED
2026-10-06: a tag restates what the component already says, and drifts from it). Each is a
capability × scope × magnitude, and the relational ones (lethality against *this* target)
have a magnitude only once the other party is named. L1 attaches the type's affordance set
to every track; L2 and L3 reason over it, so an enemy sensing provider is worth more than its
cost and a dominion provider is what the dominion drive wants, whatever faction mechanism
produces it.
→ the kinds, the capability table with each derivation, time, attention and cues:
**[ontology.md](ontology.md)**

## The fog boundary

A rule, and a check at the earliest stage where its inputs are fixed (`~/.claude/CLAUDE.md`
§5.4): **only L0 may call the fog-dependent scene queries, and no manager may read enemy
state from the scene at all.** The check is a `tests/test_SuiteIntegrity.gd`-style scan over
file text: a list of forbidden identifiers (`visible_enemies`, `get_enemies_near`,
`get_nodes_in_group("piece")`, `is_instance_valid` on a track's entity, …) that may appear
only in the perception files. A leak then fails CI rather than surviving as an honest
mistake.

The scan is `tests/test_BotFogBoundary.gd` (built 2026-10-06): every `bot_*.gd` manager file
is checked, comments stripped, for the omniscient calls — `get_enemies_near`,
`get_all_enemies`, `get_enemy_units`, `get_enemy_structures`, `nearest_enemy_structure_to_base`,
`get_nodes_in_group("piece")` — and any hit fails the suite. The fog-limited radius query a
sense may use is `Commander.visible_enemies_near`.

Three leaks were found by survey on 2026-10-06, before the scan existed, and FIXED the same
day (migration step 1):

1. `Commander.get_enemies_near` is a physics overlap with no visibility filter, and drove
   `is_base_under_threat`, `most_threatened_structure` and `threatened_command_centre` — the
   DEFEND posture, `BotEconomy.safety()` and defensive sanction aiming. Those three senses,
   `BotSanction` and `BotTargeting` now read `visible_enemies_near`; `get_enemies_near` is
   documented as the omniscient primitive under `visible_enemies()` and nothing above
   perception calls it.
2. `believed_enemy_army_value` and `enemy_demand_map` dropped entries whose entity failed
   `is_instance_valid`, so an enemy that died out of sight left the estimate instantly. Every
   belief now counts; the demand map's live `rep` is borrowed as a type-level stat carrier
   (`Bot._any_instance_of_type`), null for an extinct type, with a `TODO` that type-level
   effectiveness removes it.
3. `BotMilitary._objective_is_standing` read the remembered objective's liveness. It now asks
   `CommanderBlackboard.believes(instance_id)` — a structure stands until the bot SEES its
   cell empty — and the node's validity is checked only at the Attack order, an actuation
   necessity that changes no decision. `Bot.belief_is_disproved` read a remembered unit's
   live position whatever its visibility, so a stealthed unit on the spot read as "still
   there"; the position is now read only for a piece the bot can see.

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

1. **Make the boundary explicit.** BUILT 2026-10-06: the three leaks route through visibility
   and belief status, the scout grid stamps from the fog, and the forbidden-identifier scan is
   `tests/test_BotFogBoundary.gd`.
2. **Extract `TrackTable`** from `CommanderBlackboard`, with status, decaying confidence, the
   negative-evidence check and expiring state; snapshots read it. The blackboard's open question
   ([bot-engagement-fixes](bot-engagement-fixes.md) §What this does NOT explain) is answered by negative evidence.
3. **One lattice**: move the scout grid into `BotFields`, anchored to the map centre, stamped
   from the fog's cleared set (the raycasts go); add `enemy_influence` and `threat`. `BotScout`
   reads `sight_age`; the dominion survey and the build-spot search read the same grid.
4. **Believed clusters** from tracks; the `combat` channel, engagements and per-engagement
   momentum.
5. **L3 local standing, exposure and enemy-presence reads**; the military's objective choice
   and the defence placement read them (`reach_coverage`).
6. **L4 attention and focus**; `BotScout` and REVEAL consume the ranking; L0 gates on the
   discs, the floor and the latency.
7. **Affordance derivation** per [ontology](ontology.md) §The capability vocabulary;
   `BotScout`'s scorer and the dominion drive read it.

Steps 1–3 remove code; 4–7 add what the roadmap already lists, on a representation that
exists.

## Open decisions

The decisions this note was written with are made (2026-10-06) and folded into the sections
above: the blackboard-and-Markov rule and where each layer lives (§The model), the gates and
the negative-evidence check (§L0), decaying confidence, expiring state, instance-keyed tracks
and discovered neutrals (§L1), the one lattice and its channels (§L2), per-engagement momentum
and local standing (§L3), the rudimentary focus (§L4), the 5-unit pitch and the performance
requirement (§Cadence and cost). The starting constants are arbitrary and to be retuned in
testing. One remains:

> **TODO — the capability vocabulary is to be revisited** as the ontology of what the model
> can signal develops; it is now a table of derivations in [ontology](ontology.md), and the
> piece-usage audit's "cannot signal" rows ([piece-usage-audit](piece-usage-audit.md)) are
> the test of whether a row is missing.
