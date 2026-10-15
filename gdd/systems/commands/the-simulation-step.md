---
title: The simulation step
type: system-note
---

# The simulation step

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Scoped 2026-10-15 ([`gdd/tasks.md`](../../tasks.md) T-110), decisions Alex's. **Built: stage 1,
the serial stepper, and the decide pass with its first tenant (2026-10-15). PLANNED: the rest of
stage 2, then sleepy updates, then stage 3 (§Stages).**

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

## The serial stepper

Built. `SimulationStepper`, made with the `Scenario`, steps every entity in play in spawn-serial
order once a tick, then resolves the tick's deaths in the same order. Every entity takes a serial
on entering a scenario — emissions too, though only pieces are looked up by one, since only pieces
are named by orders. An entity steps the nodes under it that define `simulation_step`, in tree
order; nothing in a scenario does simulation work in `_physics_process`
(`tests/test_SimulationStepper.gd` scans for it). Outside a scenario — a test fixture, a preview
tool — an entity steps itself.

- **The stepper runs after every priority-0 system** — the tick count, triggers, tactics, bots,
  fog — and before `Commander`, so orders those issue land before any piece acts on them.
- **A tick steps what was in play when it started.** An entity or node that arrives mid-tick is
  first stepped on the next one, as the engine's own process list behaves.
- **A piece at zero HP does not act**; it dies in the death step of the tick that dealt the damage,
  whichever of the pieces involved stepped first. A death that cannot wait (a flush, a crush)
  still happens at once through `Entity.kill`.
- **A node switched off with `PROCESS_MODE_DISABLED` is not stepped**, as the engine would not
  process it — how a test freezes one component.

## The decide pass

Built. Each tick runs three passes over the entities in play, each in serial order: every entity
**decides** (the nodes under it that define `simulation_decide`), then every entity **acts**
(`simulation_step`), then deaths resolve. A decision reads the world as the last tick left it and
writes nothing but itself; the act phase checks it still holds before applying it.

- **An idle piece's target pickup is decided** (`Actor.simulation_decide`): the aggro scan runs
  in the decide pass, and `Orders.tick` starts the attack in the act pass only if the target is
  still in play, alive and hostile — `Actor.take_decided_aggro`. A decision never outlives its
  tick.
- **A command decides through `MoveCommand.decide`**, run for the command each piece holds when
  the tick starts; one that becomes current mid-tick has not decided and works its tick out
  live. `AttackMove`'s scan for something to fight is the first: decided, then swapped to in
  `get_updated_state` only if `Actor.decided_attack_holds`. The base `MoveCommand` destination
  swap is planned in decide (`swap_trades`, pure) and each trade applied only if both units
  still hold the order and the destinations it was planned from.
- PLANNED — the commands whose "read" methods write today, and so must be split into a decided
  half and an applied half before more of their tick can move (audited 2026-10-15):
  - `Attack` and `FocusFire`: `get_updated_state` aims, stops and turns the unit; `can_act`
    holds the weapon's lock;
  - `Deploy` and `Undeploy`: `can_act` advances the deploy state machine;
  - `Occupy` and `Flush`: collision exceptions, avoidance layers and the host's pending list;
  - `Embark` (orders another unit), `Rearm` (claims a pad), `Evacuate` (lands the host),
    `Wander` (draws from `SU.rng`), `Build` (caches a preview node on the commander).
  The rest — Assemble, Defend, Interact, Patrol, Plant, Repair, Spot, TaskShelter, and the
  commands that only inherit the base swap — read only, apart from fields of their own.
- INVARIANT: a `simulation_decide` writes only its own piece's decision fields. Nothing in the
  language can stop it writing more, and a write there is seen by every piece deciding after it,
  which is the same-tick order dependence the pass exists to remove — and, once decide runs on
  threads, a data race.

## What the remaining stages replace

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

## Decisions

Decided by Alex, 2026-10-15. PLANNED, except the three stage 1 built: one stepper, emissions in
the serial order, and deaths in their own step.

- **What decide sees: last tick's state, re-validated at apply.** Every read in the decide phase is
  of the state the previous tick left. The act phase checks each intent's precondition against the
  live state and drops one that no longer holds — two passengers cannot both take the last slot,
  two purchases cannot both spend the same energy. The usual lockstep pattern, and an intent
  re-applied under rollback validates the same way.
- **Conflicts: the lowest spawn serial wins**, which is simply what applying in serial order with
  re-validation does. Additive effects — damage, income, healing — do not conflict; they sum. A
  kind of conflict that reads badly can get its own rule later.
- **One stepper, in spawn-serial order** — built (§The serial stepper). It is the one place the
  two phases will live.
- **The decide/act line follows the profile, not the class list.** The hot read-only work moves
  into decide — target acquisition, range and line-of-fire checks, path progress — and
  `fulfill_action` stays in act much as it is today. A command migrates further when it is next
  touched, rather than every command being rewritten at once.
- **Emissions join the serial order** — built. Rollback must snapshot them anyway, and their
  impacts write damage.
- **Deaths resolve in a step of their own**, after every entity has stepped — built. Under stage 2
  that step follows act.
- **Spatial queries in decide read our own index**, built once at the start of the tick from last
  tick's positions and read-only thereafter. It grows from the existing spatial partition grid,
  and hurtbox-exact range checks are ported onto it. Neither queueing queries to the main thread
  (no parallelism left) nor Jolt's thread-safe queries (cross-platform determinism unmeasured).
  Approved 2026-10-15 to go further: once every reader is on the index, the per-piece detection
  areas (aggro, vision, detection ranges) leave the physics server, whose broadphase now carries
  them every tick. This is what C&C Generals' PartitionManager is: a grid of map cells that
  every range query reads.
- **Path requests are intents**: decide asks, act calls the navigation server serially. Path
  queries are rare (under one per tick in the profile), so this costs nothing. Aircraft move in
  the act phase as well, so every piece's position changes at the same point in the tick.
- **Orders from bots, triggers and tactics land before decide**, the way player orders already
  do (`OrderStream` runs first). Bots stay serial and budgeted
  ([ai/think-scheduling](../ai/think-scheduling.md)); this design does not put a think on a
  thread.
- **References between pieces become spawn serials** — in intents and in every field that holds
  another piece: command messages, garrison lists, claims, payload sources, followed units. A
  rollback snapshot cannot hold a node reference. Built with the snapshot (§Stages): a field
  keeps its node for every read and gains the serial a snapshot writes, so no command's code
  changes and none is touched twice.
- **Replays recorded before a change to how a match plays are refused by build number**
  (`application/config/version`; 0.2.0 with the stepper, 0.3.0 with the decide pass, 0.4.0 with AttackMove deciding, 0.5.0 with the destination swap), bumped by hand at each such
  change. TODO: the version stamp hashes no simulation
  script, so any change to how a match plays relies on someone bumping the number. Adding the
  scripts to `ReplayFile.VERSIONED_PATHS` would refuse replays on every refactor, which is its own
  decision.

## Stages

Each stage is gated on the determinism probe (`tools/netplay/determinism_probe`) agreeing bit for
bit between two runs of the same build, and is measured by simulated minute on the probe's recipe
(seed 20261014, two bots, 9000 ticks) on both development machines.

1. **The serial stepper.** Built 2026-10-15. Two 9000-tick runs agreed to the bit — every digest
   and every sampled float — on Windows/x86_64; the match differs from the tree-ordered one from
   tick 1, as expected. Wall time was unchanged within this laptop's run-to-run noise (213–293 s
   against 282 s), which stage 1 never aimed to move. TODO: the same check on macOS/arm64.
2. **Decide and act, still serial.** Built: the decide pass, and idle target pickup in it
   (§The decide pass). PLANNED, in this order — each touches the code once, which Alex asked for
   over short-term speed (2026-10-15):
   1. The rest of the hot reads move into decide: a command's reactive swap
      (`get_updated_state`), `can_act`'s range and line-of-fire checks, and path progress, each
      applied in act with re-validation. Path requests become intents.
   2. **Sleepy updates** (§Sleepy updates): once every change one piece makes to another is
      applied in the act phase, "wake the piece it was applied to" lives there, not at every
      mutation site.
   3. **References by serial, with the rollback snapshot** — the state inventory, snapshot and
      restore of netplay's §Rollback, later. Serials matter only to a snapshot, so they are
      built with it.
   4. **The spatial index**, replacing the physics broad phase for decide's reads, and with it
      the per-piece detection areas. A serial decide pass reads the physics server safely — no
      piece writes during it — so the index is needed first by threads.
3. **Worker threads for decide**, on the spatial index. TODO: deferred by Alex (2026-10-15) until
   the first two stages are built and measured.

## Sleepy updates

PLANNED (approved by Alex 2026-10-15), after the hot reads move into decide (§Stages). Measured
2026-10-15: the pieces this would sleep — about half of them by minute four, idle unarmed
buildings — cost 1.3–1.5 ms of a ~20 ms tick, against ~7 ms for the ~30 moving units; Alex chose
the order that suits the rework over that short-term gain. C&C Generals runs no module it does not have to: every
update returns how many frames it may sleep, and the game keeps the modules in a min-heap by
wake frame, so a frame's cost is the modules due that frame, not every module in the world.
Here, about half the pieces are structures that are idle most ticks, yet each runs its whole
order tick every tick.

**The rule: sleeping never changes the match.** A piece or component sleeps only through ticks
whose outcome is already known — the same digests come out with sleeping on or off, and that
equality is the gate. So:

- **Physics and movement never sleep.** No staggering: a moving piece moves, steers and is
  avoided every tick, and an order is acted on the tick it lands (Alex, 2026-10-15 — for
  determinism and for units that respond at once).
- **A countdown sleeps until it ends** — reloads, ability recharges, shelter production,
  garrison sentences — by computing its wake tick exactly, rather than counting down each tick.
- **An idle piece's order layer sleeps** only while nothing could give it work: no command, no
  queue, and nothing it would acquire. Whatever can change that wakes it on the tick it happens
  — an order, damage, a change of owner. TODO: noticing an enemy that walks into range without
  polling needs the stage 2 grid to say who entered which cells; until then a piece with an
  aggro range keeps its idle scan every tick, and only pieces with none (economy buildings,
  walls) sleep.
- The stepper keeps sleepers in a min-heap by wake tick, tie-broken by serial, so the order
  pieces act in is still serial order.

## Later

PLANNED, approved by Alex 2026-10-15 to be revisited rather than built next:

- **Leaner movement.** Ground units integrate their own position along the navmesh and
  avoidance velocity, rather than resolving collisions with `move_and_slide` every tick — as
  C&C Generals' hand-written locomotors do.
- **Fewer nodes per piece.** About forty nodes each today (4,700 nodes and 19,000 objects at
  minute four of a bot match); visuals and detection shapes can move to the rendering and
  physics servers directly.

## Testing

- The intent and conflict rules are a pure core, unit-tested against fixtures built with
  `FakePieces`.
- A suite test runs the same short match with decide serial and threaded and requires identical
  digests every tick (stage 3).
- Netplay's forced-rollback harness, when rollback is built, is the check that the snapshot
  misses nothing.
- Sleepy updates: the determinism probe with sleeping on and off must agree digest for digest.

## What it does not reach

- **Tick cost for rollback.** Rollback wants a tick roughly ten times cheaper
  ([netplay](netplay.md) §Rollback, later). Threads alone will not get there on a machine with two
  performance cores; sleepy updates are the other lever. A slower simulation rate (T-062) is
  REJECTED for now.
- **The engine phase** — the physics step and RVO avoidance — stays serial; multi-threaded
  avoidance plays a different match per process ([terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md)).
