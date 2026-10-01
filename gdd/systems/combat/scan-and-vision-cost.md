---
title: Scan and vision cost
type: system-note
---

# Scan and vision cost

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

The two per-tick costs that grow with army size: the aggro scan every idle armed piece runs,
and the fog-of-war reveal. **The fog work and the aggro query's allegiance filter are built
(2026-09-26); the staggered aggro re-acquire was rejected** (§The aggro scan). The WHAT of
both — what may be acquired, what a side can see — belongs to
[target-acquisition](target-acquisition.md), and this note changes none of it. It is only about
how often the answers are recomputed, and how much of each answer is recomputed.

Measured on the 261×261 skirmish map ([ai/bot-performance](../ai/bot-performance.md)): the
entity layer goes from 7 to 18 ms per tick as units go from 28 to 83, and the aggro scan is its
main per-unit term. Fog cost 5.9 ms per tick for two commanders, whether anything moved or not,
before it was made incremental (§The fog of war).

## How other RTS engines do it

**StarCraft II is closed source, and its scan cadence is not public.** What is public:

- The simulation runs at **16 game loops per game second** (22.4 per real second at *Faster*),
  and rendering is interpolated between loops
  ([Liquipedia: Game Speed](https://liquipedia.net/starcraft2/Game_Speed),
  [StarCraft AI: Frame Rate](https://starcraftai.com/wiki/Frame_Rate)). Every per-tick cost
  is paid 22 times a second, where this game pays 30.
- A unit keeps its target until the target stops being valid or leaves range, or until a
  higher-priority target enters its scan range
  ([Liquipedia: Automatic Targeting](https://liquipedia.net/starcraft2/Automatic_Targeting)).
  Holding a target is what makes an infrequent re-scan acceptable.
- Blizzard's GDC talk on the engine's performance is behind the GDC Vault paywall and was not
  read ([Designing for Performance, Scalability & Reliability: StarCraft II's Approach](https://www.gdcvault.com/play/1012369/Designing-for-Performance-Scalability-Reliability)).

The open-source engines show the mechanisms directly:

- **Spring / Beyond All Reason, aggro.** A weapon re-acquires in `SlowUpdate`, every 15 frames
  of a 30 fps sim (0.5 s), spread evenly across units; it re-acquires at once only when
  its current target dies (`fastAutoRetargeting`)
  ([Weapon.cpp](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Sim/Weapons/Weapon.cpp),
  [UnitHandler.cpp](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Sim/Units/UnitHandler.cpp)).
  Candidates come from the engine's own spatial grid (`quadField`), whose quads list units
  per allied team, so friendly units are skipped by the bucket, never visited
  ([GameHelper.cpp](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Game/GameHelper.cpp)).
- **0 A.D., aggro.** Range queries run once per turn over a spatial subdivision, filtered by an
  owner mask BEFORE any distance test. They return *deltas*, entities that entered or left
  range, so a unit reacts to an enemy arriving rather than re-scanning for one
  ([CCmpRangeManager.cpp](https://raw.githubusercontent.com/0ad/0ad/master/source/simulation2/components/CCmpRangeManager.cpp)).
- **Vision, in all of them: reference counts, updated only on change.** 0 A.D. keeps a
  per-player `u16` count per LOS vertex, touched by `LosAdd` / `LosRemove` / `LosMove`
  when a unit moves or its vision changes, with an incremental path for "mostly-overlapping
  circles" (same file). Spring shares one reference-counted LOS instance among units with the
  same position and radius, stores LOS at a lower resolution than the terrain (a mip level),
  and batches updates per frame
  ([LosHandler.cpp](https://raw.githubusercontent.com/beyond-all-reason/spring/master/rts/Sim/Misc/LosHandler.cpp)).
  The same pattern is written up for hobbyist RTS work: a count per cell, re-stamped only when
  a unit crosses a cell boundary, so most frames do no fog work at all
  ([jdxdev: RTS Fog of War](https://www.jdxdev.com/blog/2022/06/08/rts-fog-of-war/)).

## The aggro scan

**Filtering allegiance in the query is built** (2026-09-26): see
[target-acquisition](target-acquisition.md) §Aggro filters allegiance in the physics query —
Spring's per-team buckets, expressed as Godot layer bits. Measured afterwards, the aggro scan
costs **0.27 ms per tick** across a whole match (~3 µs per call); it is no longer a
significant term.

- **REJECTED (2026-09-26) — re-acquiring on a staggered cadence** (an idle piece scanning every
  0.1–0.5 s, with immediate scans on going idle, being hit or losing its target). Alex declined
  to change how quickly an idle unit notices an enemy, and once allegiance was filtered in the
  query it would have saved only ~0.2 ms per tick.
- **TODO — only if aggro grows costly again: our own spatial hash per side**, replacing
  Godot's shape query for aggro and the bot's enemy scans, like Spring's `quadField` or
  0 A.D.'s subdivision.

## The fog of war

Built 2026-09-26. Each commander's fog keeps a count per pixel of the vision sources covering
it, and each source the stamp it last added (its pixel and footprint). A tick walks the `los`
group, re-stamps (−old, +new) only a source whose stamp changed, and withdraws the stamp of
any source that no longer counts. The texture is uploaded only for the fog being displayed,
and only when its bytes changed. `fog_clear_at` reads the same bytes as before, so every
gameplay reader (`is_visible_to`, aggro, target release) gets the answer it always got;
`tests/test_FogIncrementalSight.gd` holds it byte-equal to a from-scratch rebuild through
random moves, captures, removals and footprint changes.

**Diff the sources each tick; do not hook every change.** Capture, a reach upgrade, death,
garrisoning, stealth, construction: each changes vision, and a design that hooks each event
misses the one nobody remembered. Walking the group is O(sources) and cheap; only the
re-stamps touch pixels.

**The entity-visibility pass was the larger half, not the cheap one.** The proposal assumed
it was cheap next to stamping. Once stamping was incremental it was ~80% of what was left:
`structure_in_vision` resolved every footprint cell through `Map.grid_to_world` on every tick,
~22 µs per structure. A structure's footprint pixels are now memoized, keyed by the cells array
Map holds (which Map replaces rather than edits).

Measured on the skirmish map, headless ([ai/bot-performance](../ai/bot-performance.md)'s
probe), fog for both commanders per tick:

| | Before | After |
|---|---|---|
| bot-vs-bot match, p50 | 7.5 ms | **1.0 ms** |
| same, p99 | 11.3 ms | 2.9 ms |
| unit sweep at 280–319 units, p50 | 38.3 ms | 5.7 ms |

What still grows with army size is re-stamping units that move: a moving unit re-stamps its
whole disc (twice) each time it crosses a pixel. An incremental edge-only update for a small
move ("mostly-overlapping circles", as 0 A.D. does) is the next step if that shows up.

**TODO — Alex to decide: should fog resolution drop below one pixel per cell?** Spring stores
LOS coarser than the terrain. At two cells per fog pixel there are 4× fewer pixels to stamp
and upload; the shader's filtering hides the blockiness.

1. **Keep one pixel per cell.** Vision edges and `structure_in_vision`'s per-cell test stay
   exact; the count grid alone already removes most of the cost.
2. **Two cells per pixel.** 4× cheaper again, but a vision edge is only accurate to two cells,
   and a structure counts as seen when a coarse pixel touching its footprint is.

**Leaning:** 1. The count grid makes the stationary case free, and moving units stamp a few
hundred pixels each, so the coarse grid buys little and costs precision the gameplay reads.

**TODO — follow-on:** `BotScout` raycasts its own line of sight from every unit to every
scout-grid point. Once fog is incremental, the scout could read the bot's own fog counts
instead. That is cheaper, and it would agree with what the fog actually shows. It would drop
the scout's stricter terrain occlusion, which is a behaviour change, so it is a separate
decision.

**TODO — the scout and the fog disagree about terrain.** The scout's raycasts stop on terrain;
the fog ignores it. So ground behind a ridge, or behind a mountain once
[obstacle regions](../terrain-and-navigation/map-generation.md) §Obstacle regions are built,
is never counted as scouted, though the bot's fog shows it as seen. Whether terrain blocks
sight at all is open ([target-acquisition](target-acquisition.md) §Line of fire); this resolves
with it, or with the follow-on above.

## Beyond both: the simulation rate

**TODO — Alex to decide, not proposed.** SC2 pays its per-tick costs 22.4 times a real
second; this game pays them 30 times. Godot 4 has built-in physics interpolation, so a 20 Hz
simulation with interpolated rendering would cut every per-tick cost by a third without
touching any system. It is recorded here because it is the largest lever this research turned
up, not because it is recommended now. It changes input latency, projectile tunnelling
margins, RVO behaviour and every value still authored in ticks.
