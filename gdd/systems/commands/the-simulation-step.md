---
title: The simulation step
type: system-note
---

# The simulation step

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Scoped 2026-10-15 ([`gdd/tasks.md`](../../tasks.md) T-110), decisions Alex's. **Built: stage 1,
the serial stepper; the decide pass with the hot reads it holds so far; pure command reads with
writes in `apply_state`; and sleepy updates for idle buildings (all 2026-10-15). PLANNED:
references by serial with the rollback snapshot, the spatial index, then stage 3 (§Stages).**

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
  live. The aggro scans of `AttackMove`, `Patrol` and `Defend` are decided
  (`MoveCommand._decide_aggro`) and swapped to in `get_updated_state` only if
  `Actor.decided_attack_holds` (`_take_aggro`). The base `MoveCommand` destination
  swap is planned in decide (`swap_trades`, pure) and each trade applied only if both units
  still hold the order and the destinations it was planned from. `Attack` decides whether to keep
  the attack (sight, leash) and, for the weapon it would fire, range and line of fire;
  `FocusFire` decides its weapon's reach. Both aim, turn and fire in the act phase, with the aim
  itself checked live there, so a unit still fires the tick it lines up.
- **A decision counts only in the round that made it** (`SimulationStepper.current_round`, one
  per tick): a command or piece whose decision is from an earlier round works the tick out live,
  so nothing decided is ever read a tick late.
- **A command's reads are reads; its writes are `apply_state`.** `get_updated_state`, `can_act`
  and `should_move` only read (apart from the command's own fields), so any of them can move
  into decide. What a command changes in the world each tick is `MoveCommand.apply_state`, which
  the receiver runs once, after `get_updated_state` keeps the command and before `can_act` — the
  same point in the tick those writes held when they lived in the reads, so moving them changed
  no match (the probe agreed to the bit with the build before, each time). The commands that
  wrote from their reads, audited 2026-10-15, all moved: the base destination swap, `Attack`,
  `FocusFire`, `Deploy`, `Undeploy`, `Occupy` (and `Flush`), `Embark`, `Rearm`, `Evacuate` and
  `Wander`. `fulfill_action` is still the act it always was.
- TODO: `Build`'s reads fill the commander's preview-instance cache on first use
  (`Commander.get_build_preview_instance`) — a memo of derived data, harmless serially and
  normally filled already by the order's precondition check, but a race once decide runs on
  threads. Warm it when the order is given.
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
  (`application/config/version`; 0.2.0 with the stepper, 0.3.0 with the decide pass, 0.4.0 with AttackMove deciding, 0.5.0 with the destination swap, 0.6.0 with Attack and FocusFire deciding, 0.7.0 with Patrol and Defend deciding), bumped by hand at each such
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
2. **Decide and act, still serial.** In this order — each touches the code once, which Alex
   asked for over short-term speed (2026-10-15):
   1. **The hot reads move into decide** — built (§The decide pass): idle pickup, the aggro
      scans of AttackMove, Patrol and Defend, the destination swap, and Attack's and FocusFire's
      keep, range and line-of-fire checks; every command's reads are pure, its writes in
      `apply_state`. Path requests already happen only in the act phase (`Movement.tick`), and
      path progress is a read of the unit's navigation agent, so nothing there needed moving
      (checked 2026-10-16).
   2. **Sleepy updates** (§Sleepy updates) — built for idle buildings; their wakes live at the
      handful of places an idle building can be given work.
   3. **References by serial, with the rollback snapshot** — the state inventory, snapshot and
      restore of netplay's §Rollback, later. Serials matter only to a snapshot, so they are
      built with it.
   4. **The spatial index** (§The spatial index) — built for decide's aggro scans, and armed
      idle pieces sleep on it. The per-piece aggro, vision and detection shapes turned out to be
      disabled already (2026-10-16): only ever read as shapes, never in the physics server, so
      there is nothing to remove. Two range shapes on one unit are live by mistake — T-112.
3. **Worker threads for decide**, on the spatial index. TODO: deferred by Alex (2026-10-15) until
   the first two stages are built and measured.

## The spatial index

Built 2026-10-16. `SpatialIndex` holds every piece's Hurtbox — footprint (`Hull`), collision
layers with side bits, and vertical span — on a grid of 8-unit cells, brought up to date by the
stepper at the start of each tick from the world as the last tick left it. After one full scan
it touches only the pieces marked dirty since the last update (`Entity.mark_spatial_dirty`): a
piece's transform-changed notice, its entering or leaving the tree, and every write to its
Hurtbox's layers mark it. Godot delivers transform notices between physics steps — even several
steps to one frame — so every move of one tick reaches the next tick's update (measured
2026-10-16).

- INVARIANT: every write to a Hurtbox's layers, shape or local transform marks its piece. Only
  `Entity._apply_targetable_layers` and `Liberatable` write layers today, and nothing changes a
  Hurtbox's shape or local transform at run time. No type can enforce it; `--verify-index` on
  the determinism probe rebuilds a fresh index every tick and asserts the marked one matches —
  zero mismatches over the 9000-tick bot match — and the stepper's tests run with it on. While the decide pass runs
it is `SpatialIndex.reading`, and `SU.entities_within` answers from it for any mask a Hurtbox
carries (`SpatialIndex.answers`) — the aggro scans of idle pieces, AttackMove, Patrol and
Defend. C&C Generals' `PartitionManager` is the same idea.

- **Its answer is the physics broad phase's, with the exact footprint test after it**: a
  Hurtbox layer in the mask, the scan volume's height overlapping the Hurtbox's span, and
  `Hull.gap` within the radius. The 9000-tick probe match agreed to the bit with the
  physics-backed build.
- **In serial order, and uncapped.** The physics query was cut at `max_results` (10 for aggro)
  in arbitrary order before the footprint test, so a crowd could hide the target that
  mattered; the index returns every match.
- TODO: still on the physics server in the decide pass — an orbit weapon's range
  (`SU.entities_touched_by`, a shape-against-hurtbox overlap) and Attack's line-of-fire ray.
  Both must move before decide can run on threads.
- TODO: act-phase queries (crush, stealth detection, liberation, blast victims) stay on the
  physics server; they read live positions mid-tick, which a tick-start index does not hold.
- **What the update costs**, timed in the bot match on an i5-1245U (2026-10-16): 0.22–0.53 ms a
  tick by minute three with dirty marks, against 0.34–0.68 ms checking every piece for a move
  and 0.78–1.25 ms rebuilding — what is left is measuring the ~26 pieces a tick that moved or
  changed layers. A native grid beside `TerrainCells` is the next lever if it is wanted.


Built 2026-10-15 (approved by Alex). C&C Generals runs no module it does not have to: every
update returns how many frames it may sleep, so a frame's cost is the modules due that frame,
not every module in the world. Here an entity sleeps whole: after it steps, it sleeps as many
ticks as every node it steps promises (`sleep_ticks()`), and on waking the nodes that count
time are handed the ticks they slept (`catch_up`). A node that cannot promise keeps its entity
awake, so sleeping is opt-in per component.

**The rule: sleeping never changes the match.** An entity sleeps only through ticks whose
outcome is already known. `SimulationStepper.is_sleep_enabled` turns it off, and the
determinism probe run with `--sleep=off` must agree with a run without it, digest for digest —
the gate, met for 9000 ticks of a bot match.

- **Physics and movement never sleep.** No staggering: a moving piece moves, steers and is
  avoided every tick, and an order is acted on the tick it lands (Alex, 2026-10-15 — for
  determinism and for units that respond at once).
- **What sleeps today: idle unmoving pieces** (`Actor.sleep_ticks`) — built, not detecting,
  liberating, docking, stealthed or a manned bunker, with no orders and nothing in production.
  An armed one sleeps too, watching its widest aggro radius: each tick, before anything decides,
  the stepper asks the spatial index whether any hostile footprint is that close
  (`SpatialIndex.has_hostile_near`) and wakes it if so — a superset of what its idle scan could
  find, so it decides that tick exactly as awake. A `Weapon` promises sleep once its turret is
  at rest, and counts its rest, split and reload ticks on waking. An income building sleeps until the tick before its payout and counts the slept
  ticks on waking (`EnergyExtractor`, `DominionGenerator`); a body `VisionRange`, an empty
  `Garrison` and an `Abilities` with no pools promise forever.
- **`Entity.wake()` is called wherever an idle building can be given work**: an order
  (`CommandReceiver.update_commands`), a production job (`Production.enqueue`), damage, a change
  of owner, construction progress, a change of form, an occupant arriving (`Garrison.garrison`),
  and any node joining or leaving the entity. A piece woken before its turn acts that tick, as
  it would have awake.
- INVARIANT: a new way to give an idle building work must wake it. Nothing can check that a
  change reached a sleeper; a missed wake shows only as the probe's sleep-on and sleep-off runs
  parting, and only if the match exercises it.
- TODO: countdowns beyond income and weapons — ability recharges, shelter production,
  sentences — keep their entity awake; each could promise its remaining ticks the way income does.
- TODO: a rollback snapshot of a sleeping entity must include its slept ticks
  (`Entity._slept_ticks`), or its counters restore short.
- Measured on an i5-1245U, the bot match's script phase, sleeping off against on, two
  interleaved runs each: unarmed buildings only (2026-10-15), 14.4 ms against 13.5–13.7 ms;
  armed pieces too (2026-10-16), 15.5–15.6 ms against 14.6–14.9 ms. About 0.8 ms either way —
  the bot match has few idle armed pieces — and the same match both ways.

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
