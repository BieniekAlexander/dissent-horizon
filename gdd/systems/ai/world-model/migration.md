---
title: Cadence, testing and migration
type: system-note
---

# Cadence, testing and migration

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Cadence and cost

Perception is jobs on the shared `BotScheduler` budget like everything else
([think-scheduling](../think-scheduling.md)), at priorities above `momentum`: L0/L1 on the
blackboard's existing ~5 Hz, L2 fields on the combat period, L3 on the strategy period, L4 on
the scout period. Field updates are resumable sweeps with a cursor — a lattice at the scout
grid's 5-unit pitch is a few thousand cells, and influence spreading is bounded by
reach, so the cost is bounded and measurable per channel. Determinism holds as today: every
input is the bot's own sightings, and the lattice is symmetric by construction.

**Performance is a requirement of this design, not a follow-up** (decided 2026-10-06): the
piece count is what the signal processing scales with, so each channel's cost is measured on
the self-play harness against [bot-performance](../bot-performance.md)'s tick budget before the
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
   ([bot-engagement-fixes](../bot-engagement-fixes.md) §What this does NOT explain) is answered by negative evidence.
3. **One lattice**: move the scout grid into `BotFields`, anchored to the map centre, stamped
   from the fog's cleared set (the raycasts go); add `enemy_influence` and `threat`. `BotScout`
   reads `sight_age`; the dominion survey and the build-spot search read the same grid.
4. **Believed clusters** from tracks; the `combat` channel, engagements and per-engagement
   momentum.
5. **L3 local standing, exposure and enemy-presence reads**; the military's objective choice
   and the defence placement read them (`reach_coverage`).
6. **L4 attention and focus**; `BotScout` and REVEAL consume the ranking; L0 gates on the
   discs, the floor and the latency.
7. **Affordance derivation** per [ontology](../ontology.md) §The capability vocabulary;
   `BotScout`'s scorer and the dominion drive read it.

Steps 1–3 remove code; 4–7 add what the roadmap already lists, on a representation that
exists.
