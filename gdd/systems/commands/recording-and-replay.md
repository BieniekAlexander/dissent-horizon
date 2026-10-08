---
title: Recording and replay
type: system-note
---

# Recording and replay

**PLANNED** — scoped 2026-09-29, awaiting the go-ahead to build. Step 4 of "Seeded
pseudo-randomness, for deterministic replay" (`gdd/tasks.md`). Steps 1–3 are built: one seed
makes one match, tick for tick ([ai/selfplay-harness](../ai/selfplay-harness.md) §Determinism,
[terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md)
§Navigation is synchronous, for replay).

A replay is the scenario, its seed and slots, and the stream of **orders the human players
gave**. Playback re-runs the simulation from the seed and feeds the orders back in on the ticks
they landed. Bots are not recorded: they re-derive their orders from the same seed.

## The plan

### The order stream (Commands)

- **What is recorded: player orders**, not raw input. An order is what the simulation consumes
  — a command with its target and actors, a purchase, a cast, the hold-fire toggle, a start-of-
  round drop, a dialog choice. Camera, selection and window size never reach the simulation.
- **Human slots only.** A bot's orders are re-derived on playback.
- **An order names a piece by a spawn serial**: a number every piece gets on entering play, in
  a deterministic order, so the same piece has the same serial on every run. Nothing carries one
  today — this is a new field on every piece.
- **Every order lands at the start of a tick, live and replayed alike.** The controller works at
  frame rate, between ticks; its orders are queued and applied at the next tick's start. Live
  play gains up to one tick of latency, and in exchange a replay cannot differ from the match it
  recorded.
- **The boundary is a selection-level order** — the command, its message, the actors' serials
  and the modifiers held (requisition, bulk, narrow) — applied by a simulation-side function.
  That moves the non-UI half of `RTSController.assign_command_to_units` (and the purchase, cast
  and toggle paths beside it) out of the controller. Approved as a restructure (§9) on
  2026-09-29.
- **The stream is shaped for networking** — tick-stamped, per commander, serializable — though
  no networking is built. See §Networking.

### The file (Persistence)

- **JSON lines, compressed with a standard codec** — readable by ordinary tools once
  decompressed, never a Godot-specific container. TODO: which codec; gzip is the default reach.
  Godot's `PackedByteArray.compress(COMPRESSION_GZIP)` does write a stream plain `gunzip` and
  Python's `gzip` read (checked 2026-10-07; the match event log ships in it,
  [scenario-scripting/match-log](../scenario-scripting/match-log.md)).
  `FileAccess.open_compressed` is Godot's own block format and is ruled out.
- **Kept under `user://replays/`.** Nothing in the game writes to `user://` yet: this is the
  first persistence.
- **The header** names the scenario, its map scene, the seed, every slot (faction, difficulty,
  human or bot, start point), and a **version stamp**: the game build plus a hash of the
  generated data and scenes (`scripts/generated/`, `resources/generated/`, the piece scenes).
- **A replay from another version is refused**, with a message. A simulation change cannot be
  migrated.

### Detecting drift (Determinism)

- **Every second, the file records a hash of the simulation state**, and playback compares it,
  reporting the first tick that differs. The hash moves from `tools/selfplay/run_match.gd`
  (`_state_digest`) into game code, so the harness and replay use the one instrument.
- **Across platforms is unmeasured.** TODO: measure one seed on two platforms before promising
  a replay plays anywhere but where it was made.
- The source scan in `tests/test_SeededRandomness.gd` extends to wall-clock reads in simulation
  code, with an allow-list for the UI ones (double-click timing, pulsing highlights, the bot
  scheduler's diagnostic timing).

### Debug mode

**Using debug mode ends the recording and marks the replay invalid.** Spawning, deleting,
commanding any piece and playing as another commander all change the simulation, and are not
orders a player can give.

### Watching (UX)

- **Every match records**, as an AUTOSAVE, and every scenario can be recorded.
- **Three autosaves are kept.** When a new one is written while three exist, the oldest is
  deleted. An autosave is recognised by its file name alone —
  `autosaved_replay_<timestamp>.<extension>`, with the timestamp in UTC
  (`20260929T221500Z`, safe in a file name on every platform) — and "oldest" is read from that
  timestamp. A file whose name lacks the prefix, or whose timestamp does not parse, is not an
  autosave, and is never deleted by the rotation.
- **"Save replay" on every end-of-scenario dialog** — victory and defeat alike — writes the
  match's recording under a name that is not an autosave's, so it is kept until the player deletes
  it. **The player names it**: the button opens a name field prefilled with
  `<scenario>_<timestamp>`, which they may edit before saving. Characters a file name cannot hold
  are refused as typed; a name beginning `autosaved_replay_` is refused, since it would join the
  rotation; and a name already taken asks before overwriting.
- **The start screen has a replay panel**: a scrolling list of every replay file under
  `user://replays/`, autosaves and kept ones alike. Choosing one plays it; a replay from another
  version is listed but refused on opening (§The file). Leaving playback is the pause menu's
  return to the title screen, as leaving a match is.
- **The perspective is switchable**: each player's fog, or everything — the existing spectator
  and play-as machinery. Alerts and voice lines follow the perspective on show.
- **The HUD is for looking**: selection and the info panel work; the command grid is hidden.
- **Pause and speed only** at first.
- **Dialogs** show, and each is dismissed on the tick it was dismissed in the recording.
- **Keys**: a replay-only set of actions — pause, faster, slower, switch view — which may use the
  grid's positional keys, since the grid is not drawn.

### Testing

- Unit tests for the pure parts: encoding and decoding an order, tick-stamping, validating a
  header and refusing a mismatched version; recognising an autosave by its name (a bad
  timestamp is not one), and choosing which autosave the rotation deletes.
- A regression test in the GUT suite: record a short scripted match (about 60 simulated
  seconds), replay it, and require every state hash to match. Long matches stay in the self-play
  harness.

## Deferred goals

- **Seeking** by re-running from the start at full speed, and later by **periodic snapshots**.
  Snapshots need the simulation state to be saved and restored whole — a save system the game
  does not have.
- **Networking, by rollback.** The goal is for players to send each other their inputs — this
  order stream — and each machine to keep its own simulation in step. Rollback also needs the
  snapshot-and-restore above, and a simulation that can re-run several ticks inside one frame.
  Out of scope for now; the only requirement it places today is the stream's shape.
- Taking control mid-replay ("play from here") is out of scope.

## Known work the plan depends on

- Anything that iterates a Dictionary before drawing a random number has to iterate in a stable
  order (noted with the task).
