---
title: The simulation step
type: system-note
---

# The simulation step

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PLANNED, all of it** — scoped 2026-10-15 ([`gdd/tasks.md`](../../tasks.md) T-110), decisions
Alex's. Nothing here is built.

One tick of the simulation becomes a single step that the scenario drives, in two phases:
**decide**, where every piece reads the world as the previous tick left it and writes down what it
means to do, and **act**, where those intents are applied one at a time in spawn-serial order.
Two things motivate it, and the second outranks the first:

- **Tick cost.** Most of a tick is per-piece order processing (profiled 2026-10-15, a bot match:
  `Actor._update_state` and the command chain under it), spread over many small calls rather than
  one loop — there is no kernel to hand a thread. A decide phase that only reads can run on worker
  threads.
- **Rollback is a high priority** ([netplay](netplay.md) §Rollback, later). It needs the update
  order fixed by serial, every reference between pieces nameable in a snapshot, and a tick
  cheap enough to re-run several times in one frame. Each stage below is rollback groundwork
  whether or not threading pays.

## How a tick runs today, and what it costs this design

Read this as the list of things the design has to replace, not as documentation of the current
code.

- **Order between pieces is scene-tree order**: pieces are children of their commander, so they
  run grouped by commander, and a capture reparents a piece and moves it in that order. The shared
  random stream (`SU.rng` — aim error, emission jitter, wander) is drawn in that order.
- **A piece writes other pieces directly and at once**: damage, crush, capture, garrisoning,
  building, status effects, claims on pads, runways and beacons. Whoever runs first wins.
- **A piece dies on its own next update**, which falls this tick or the next by tree order.
- **Grounded pieces move after every script**, in the avoidance callback; aircraft move inside
  their own update.
- **Decisions query the physics server** — aggro, range and line of fire, crush, stealth
  detection, impact, blast victims — and Godot Physics answers every query from one shared result
  buffer, so those queries cannot run concurrently.
- **Pieces hold each other as node references** (`CommandMessage.target`, garrison lists, claims,
  `Payload.from`), never by serial; `FrostField` keys by instance id, which differs per machine.
- **Emissions have no spawn serial.**

## Decisions

Decided by Alex, 2026-10-15.

- **What decide sees: last tick's state, re-validated at apply.** Every read in the decide phase is
  of the state the previous tick left. The act phase checks each intent's precondition against the
  live state and drops one that no longer holds — two passengers cannot both take the last slot,
  two purchases cannot both spend the same energy. The usual lockstep pattern, and an intent
  re-applied under rollback validates the same way.
- **Conflicts: the lowest spawn serial wins**, which is simply what applying in serial order with
  re-validation does. Additive effects — damage, income, healing — do not conflict; they sum. A
  kind of conflict that reads badly can get its own rule later.
- **One stepper, in spawn-serial order.** The scenario steps every actor itself, sorted by
  `spawn_serial`, and per-piece `_physics_process` goes away for simulation work. This replaces
  netplay's "update order by serial" TODO, and it is the one place the two phases live.
- **The decide/act line follows the profile, not the class list.** The hot read-only work moves
  into decide — target acquisition, range and line-of-fire checks, path progress — and
  `fulfill_action` stays in act much as it is today. A command migrates further when it is next
  touched, rather than every command being rewritten at once.
- **Emissions join the serial order**: they get spawn serials and the stepper steps them. Rollback
  must snapshot them anyway, and their impacts write damage.
- **Deaths resolve in a step of their own, after act**, in serial order: teardown, refunds,
  freeing the footprint and the death triggers all happen there, so a death lands on the same tick
  whatever the order of the pieces involved.
- **Spatial queries in decide read our own index**, built once at the start of the tick from last
  tick's positions and read-only thereafter. It grows from the existing spatial partition grid,
  and hurtbox-exact range checks are ported onto it. Neither queueing queries to the main thread
  (no parallelism left) nor Jolt's thread-safe queries (cross-platform determinism unmeasured).
- **Path requests are intents**: decide asks, act calls the navigation server serially. Path
  queries are rare (under one per tick in the profile), so this costs nothing. Aircraft move in
  the act phase as well, so every piece's position changes at the same point in the tick.
- **Orders from bots, triggers and tactics land before decide**, the way player orders already
  do (`OrderStream` runs first). Bots stay serial and budgeted
  ([ai/think-scheduling](../ai/think-scheduling.md)); this design does not put a think on a
  thread.
- **References between pieces become spawn serials** — in intents and in every field that holds
  another piece: command messages, garrison lists, claims, payload sources, followed units. A
  rollback snapshot cannot hold a node reference, so doing it now avoids touching every command
  twice.
- **Replays recorded before this change are refused by build number.** The project sets no
  `application/config/version` today; it gets one when the stepper lands, and it is bumped again
  at each stage that changes how a match plays. TODO: the version stamp hashes no simulation
  script, so any change to how a match plays relies on someone bumping the number. Adding the
  scripts to `ReplayFile.VERSIONED_PATHS` would refuse replays on every refactor, which is its own
  decision.

## Stages

Each stage is gated on the determinism probe (`tools/netplay/determinism_probe`) agreeing bit for
bit between two runs of the same build, and is measured by simulated minute on the probe's recipe
(seed 20261014, two bots, 9000 ticks) on both development machines.

1. **The serial stepper.** One loop in spawn-serial order, emissions given serials, deaths in their
   own step. No threads. Matches play differently from here on.
2. **Decide and act, still serial.** The intent records, re-validation at apply, the spatial index,
   path requests as intents, references by serial.
3. **Worker threads for decide.** TODO: deferred by Alex (2026-10-15) until the first two stages
   are built and measured.

## Testing

- The intent and conflict rules are a pure core, unit-tested against fixtures built with
  `FakePieces`.
- A suite test runs the same short match with decide serial and threaded and requires identical
  digests every tick (stage 3).
- Netplay's forced-rollback harness, when rollback is built, is the check that the snapshot
  misses nothing.

## What it does not reach

- **Tick cost for rollback.** Rollback wants a tick roughly ten times cheaper
  ([netplay](netplay.md) §Rollback, later). Threads alone will not get there on a machine with two
  performance cores; staggering per-piece work and a slower simulation rate (T-062) are the other
  levers.
- **The engine phase** — the physics step and RVO avoidance — stays serial; multi-threaded
  avoidance plays a different match per process ([terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md)).
