---
title: The world model
type: system-note
---

# The world model

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**TODO — an unapproved proposal, in parts.** A single, fog-limited, layered model of the game state
that every decision module reads INSTEAD of the scene tree. What exists is
[bot-architecture](../bot-architecture.md) §Perception; the gaps it would close are the
perception items in [bot-roadmap](../bot-roadmap.md) and the economy signals
[objective-selection](../objective-selection.md) is blocked on. The lattice and topology half
is approved and `PLANNED` ([lattice-and-topology](lattice-and-topology.md), 2026-10-08); the
rest is to be built in the order [migration](migration.md) gives, as each part is approved.

| Note | Covers |
|---|---|
| this file | the problem, the frameworks the model adapts, and what is still open |
| [layers.md](layers.md) | the model itself: L0 sightings, L1 tracks, L2 situation, L3 assessment, L4 attention, and affordances |
| [lattice-and-topology.md](lattice-and-topology.md) | `PLANNED`: the one lattice and its channels, distance fields over passable ground, approaches, arrival time, and defending assets across space |
| [fog-boundary.md](fog-boundary.md) | the rule that only L0 reads the fog, the scan that enforces it, and the three leaks it closed |
| [migration.md](migration.md) | cadence and cost, testing, and the build order |

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
   ([bot-architecture](../bot-architecture.md) §What it was measured to fix).

The brief ([brief.md](../brief.md)) asks for the opposite: decisions derived from signals, with
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
[objective-selection](../objective-selection.md)) and **intentions** (committed plans: a launched
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
([bot-roadmap](../bot-roadmap.md) §The currency). The world model feeds that; it does not
replace it.

## Open decisions

The decisions this note was written with are made (2026-10-06) and folded into the sections
above: the blackboard-and-Markov rule and where each layer lives ([layers](layers.md) §The model), the gates and
the negative-evidence check ([layers](layers.md) §L0), decaying confidence, expiring state, instance-keyed tracks
and discovered neutrals ([layers](layers.md) §L1), the one lattice and its channels ([lattice-and-topology](lattice-and-topology.md)), per-engagement momentum
and local standing ([layers](layers.md) §L3), the rudimentary focus ([layers](layers.md) §L4), the 5-unit pitch and the performance
requirement ([migration](migration.md) §Cadence and cost). The starting constants are arbitrary and to be retuned in
testing. One remains:

> **TODO — the capability vocabulary is to be revisited** as the ontology of what the model
> can signal develops; it is now a table of derivations in [ontology](../ontology.md), and the
> piece-usage audit's "cannot signal" rows ([piece-usage-audit](../piece-usage-audit.md)) are
> the test of whether a row is missing.
