# Saved games

Decided 2026-10-18 (Alex); the snapshot 2026-10-27 (Alex). A save puts the player back exactly
where they left off: the match after a load is the match that would have been played. Code:
`scripts/save/`, the snapshot in `scripts/save/snapshot/`.

## What a save is

A save is a POINT-IN-TIME SNAPSHOT of the whole simulation (`SimulationSnapshot`), written by the
running game when it saves, plus the match's replay so far and three header fields (`SaveGame`):

- `save_tick`: the tick it was saved on;
- `save_digest`: a `SimulationDigest` of the state on that tick, which a load checks against;
- `camera` and `control_groups`: where the player's camera looked, and their groups by serial.

The bytes are a replay's (`ReplayFile`: gzipped JSON lines, the snapshot the last record), saved
as `<name>.sav` under `user://saves/`. Like a replay, a save from another version of the game is
refused, and so is a match debug mode changed (`recording-and-replay.md` §Debug mode).

**A save still carries its order log, as cargo the load never plays.** A load hands it to the
replay recorder, so a recording or later save of a loaded match still holds the whole match from
tick 0, and the replay format is unchanged.

**A save is taken BETWEEN ticks**, at the point the replay recorder digests: the start of a tick,
before its orders. The pause menu saves while the world is held, which is already between ticks.
An autosave trigger fires in the middle of a tick, so it only asks (`Scenario.request_save`), and
the recorder writes the save at the start of the next one.

**Accepted:** saving costs a hitch while the state is written. TODO: no budget is set for it or
for the load; neither has been measured on a late-game state.

## Loading

`SceneManager.load_save` builds the save's scenario as a replay would
(`ReplayLibrary.build_scenario_for`) and hands it the save (`Scenario.save_to_resume`). The
scene boots as any match does; then `SaveResume`, behind a loading screen:

1. on the first frame after the navmesh's first build (when everything that deploys or arms on
   it has run), holds the world and lays down the save's STRUCTURE (`SimulationSnapshot.prepare`);
2. waits `SaveResume.SETTLE_FRAMES`, held, for the navigation server to take up the agents it
   spawned;
3. at the start of the next frame, before anything else in it, lays the save's STATE over that
   (`SimulationSnapshot.restore`), checks it against the saved digest (reporting a difference but
   carrying on), carries the save's recording on, points the camera where it was, gives back the
   control groups and hands the match to the player.

Loading by re-simulating the order log was removed with the snapshot (2026-10-27).

A trigger that would autosave while the save is still loading is skipped
(`SaveGame.refusal_to_save`).

## Autosaves

There is ONE autosave, `autosave.sav`. `EventAutosave` writes it, and each autosave overwrites
the last. A player keeps one by renaming the file, and a save cannot be given the autosave's name
from the menu. Nothing is written in a headless run unless `EventAutosave.directory` points
somewhere else: the suite and self-play would otherwise overwrite a player's autosave.

A mission autosaves where its author puts an `EventAutosave`, and nowhere else: there is no timed
or automatic autosave. Prologue mission 1's three are listed in its note.

## Menus

- **Pause menu** (`SavesPanel` with `can_save`): a name field and Save, which asks before
  overwriting a save of the same name; then the saves, newest first, each loading when pressed.
  Save is greyed out with the reason when the match cannot be saved: a replay, a networked
  match, debug mode, still loading, or the match is over.
- **Title screen**: Load Game, the same list without saving.
- **Defeat** (`DefeatOptions`, on the end-of-match summary): Restart Mission
  (`SceneManager.restart`, same difficulty; greyed for a lobby-built skirmish, which has no scene
  to restart), Load Last Autosave (greyed when there is none), and Main Menu.

## The snapshot

Built 2026-10-27. It is also rollback netplay's snapshot (`netplay.md`
§Rollback, later; `the-simulation-step.md` §Stages, 2.3), built once for both.

**It is REFLECTIVE** (Alex, 2026-10-27): `StateCodec` carries every script variable an object
declares, so a field added later is saved without anyone remembering to. A class declares only its
exceptions — `snapshot_skip()` for derived caches and accessors, `snapshot_fields()` for an object
that is mostly wiring (the Scenario), `snapshot_extra()`/`restore_snapshot_extra()` for what
reflection cannot carry, `finish_snapshot_restore()` for what needs the whole world in place
first. Anything it cannot encode — a lambda, a Signal, an RID — fails an assertion rather than
being left out. A piece is named by its spawn serial, a node in a piece by serial and path, any
other node by its path under the scenario; every other object goes in an object table by id, so
two fields that shared an object share it again. Floats are written as their bits, because
Godot's JSON reader rounds some doubles.

REJECTED: an explicit save/load pair per class — about 800 fields by hand, and a field added
later silently left out.

**Engine state the tree does not hold** goes in too: transforms, body velocities, collision layers
and shapes made in play, every avoidance agent's and obstacle's engine properties, and the
navigation server's own position and current velocity for each. The navigation mesh is rebuilt
from the grid; its change history (what a unit compares to decide when to re-plan) is saved.

**The server's avoidance list is kept in spawn-serial order** (`AvoidanceAgent3D.settle_order`),
re-sorted at the start of any frame after an agent joined, left or was switched. The server steps
avoidance one agent at a time, writing each agent's new velocity before computing the next, so the
list's order decides what neighbours do — and it is kept by appending and by swap-removal, and can
be neither read nor set. In a canonical order it is the same on every run and a restore can rebuild
it. This changed seeded outcomes once.

**A load rebuilds the scenario scene as a replay build does, then lays the snapshot over it**
(Alex, 2026-10-27). Pieces are matched to the snapshot by spawn serial: one in the snapshot but
not the scene is spawned from its scene, one in the scene but not the snapshot is freed, and then
every match takes its saved state. The map, its terrain and the scene-authored triggers, objective
chains and dialog pages come from the scene; only their run-time state (`GlobalTrigger.has_fired`,
`fire_count`, `enabled`, an objective chain's step, the clock's holds) comes from the snapshot.
REJECTED: spawning every piece onto a bare map, which would make every scene-authored node
something to serialize.

### What it holds

- **Every entity in play**, from the stepper's list: on the tree or held off it (a garrison's
  occupant), with its scene, commander, grid cells, groups, child order among its parent's
  entities, and every node of its own — not its presentation components (`MeshVisual`,
  `StatusVisuals`, `Selectable` and kin), whose look follows from its state. A node made in play
  (an effect applied) says how to make it again; a bunker's hold on an occupant's Loadout is
  handed over again by name (`Garrison.hoisted_loadout_name`).
- **Every other scripted node under the scenario** that is simulation: the commanders, their
  factions, bot brains and dominion routes, the trigger manager, triggers and tactics. The map,
  the interface, the recorder and the order stream are not walked.
- **Static state**: `SU.rng`, `PurchaseTransaction`'s next id, the stepper's round,
  `SimulationClock`'s frame count (rebased on load), `AvoidanceAgent3D`'s free exception bits.
  **Godot's global generator**, which authored expressions draw from, cannot be read, so it is
  re-seeded at the start of every frame from the scenario seed and the tick (Alex, 2026-10-27) and
  needs no carrying. REJECTED: pre-drawn expression inputs from `SU.rng`, which rewrites every
  authored random expression.
- **Each commander's fog, whole**: what it has explored, and its sight — the per-pixel counts and
  each vision source's stamp, by serial (`FogRaster.set_sight_state`). Re-stamping from the pieces
  would not do: the bots think before the fog updates in a tick, so what they read is the sight
  of the tick before, and a load must hand them that.
- **An open scripted dialog**, raised again under its serial by the event that raised it. Saving is
  not refused while a dialog is up, so a mission's autosave can sit at a story beat beside one.
  The pause menu's hold is the viewer's and is not saved.
- **Viewer state, inside a save but outside rollback's snapshot**: the camera and the control
  groups. The selection is not saved: it is cheap to remake.

**Keys are spawn serials, not instance ids** (`Entity.identity_key`): a bot's claims, its squads'
members, its blackboard, its scouts, the frost field's exposure. An instance id differs per run,
so a loaded save could not match one — nor could a networked peer.

**Engine state the server hides**: an agent the server took off its map (a garrisoned occupant)
keeps a velocity it takes back up as what it wants when it rejoins, so a restore hands a held
agent that too. A bot's jobs are matched to the rebuilt brain's by brain and name
(`BotJob.snapshot_identity_fields`), and a brain builds its managers before the state is laid
over it (`BotBrain.prepare_snapshot_restore`).

**The physics server is handed every restored transform at once**
(`SimulationSnapshot._sync_physics_transforms`). A node passes a moved transform to the server
only when the tree next flushes its transform notifications, at the start of a physics frame; the
restore runs inside one, so a radius query in the first tick after a load found a piece where the
rebuilt scene had put it.

**A hook one piece put on another in play is made again** by the class that made it
(`finish_snapshot_restore`, through `Entity.reconnect`): a shelter's on its residents, a structure's
on its builders, a garrison's on its pending occupants, a planted charge's on its planter and
carrier, a beacon's on its shell and spotter. The rebuilt scene makes only the connections its own
`_ready`s make. INVARIANT: a new connection made between pieces in play needs the same — no check
can find one a class forgot, since a signal's connections are not state the snapshot sees.

**INVARIANT: no two simulation fields hold the same Array or Dictionary.** The codec saves a
container by value, so two fields sharing one load as two, and a write through one stops showing
in the other. Objects keep their identity (the object table); containers have none GDScript can
read cheaply, which is why this cannot be checked. Hand a container over by moving it, not by
keeping both holds (`BotFields.advance` keeps only its stage once a rebuild is swapped in). The
save-and-load probe finds a breach as a field that differs some ticks after a load.

**Presentation must not move the simulation**: a node that steps nothing joining a piece no
longer wakes it (`SimulationStepper._on_tree_changed`), since a load rebuilds its presentation.

### What is not done

- TODO: a loaded save loses the remembered image of a structure destroyed out of sight, until its
  cell is scouted again (`CommanderBlackboard.finish_snapshot_restore`).
- TODO: `tools/snapshot/save_load_probe.tscn` is the check that a snapshot holds everything, and it
  is not in the suite: a 9000-tick bot match saved every 1000 ticks (each checkpoint before the
  match ends; later ones are skipped), and prologue mission 1 (`--scene=`) saved every 500, both
  restore exactly and play the same match for the 300 ticks compared (2026-10-27). A later change
  can break that silently until someone runs it.
- TODO: the save hitch and the load time are unmeasured, and no budget is set for either.
