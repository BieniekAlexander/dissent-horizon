---
title: Recording and replay
type: system-note
---

# Recording and replay

Scoped 2026-09-29; the recording side and the order boundary are built (2026-10-08), and so is
watching (2026-10-08): the start screen's replay panel, Save replay at a match's end, and a
playback watched as a spectator session. What is left is `TODO` or deferred below (`gdd/tasks.md`
T-037). One seed makes one match, tick for tick ([ai/selfplay-harness](../ai/selfplay-harness.md)
§Determinism, [terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md)
§Navigation is synchronous, for replay).

## What is built

- **Orders are `PlayerOrder`s, applied by `OrderDispatcher` at the start of a tick.** The
  controller builds an order from the selection, the message and the modifiers held, and submits
  it to the scenario's `OrderStream`, which applies it at the start of the next tick, live and
  replayed alike. With no stream (a bare controller in a test) the dispatcher applies it at once.
  The controller previews through the dispatcher's own rules (`recipients`, `narrowed`,
  `line_destinations`), so what it shows and what is applied agree. Every way a player changes
  the simulation is a kind: COMMAND (everything through `assign_command_to_units`: moves,
  attacks, builds, training purchases, casts and sanctions), HOLD_FIRE, AUTOCAST,
  CANCEL_PURCHASE and CANCEL_JOB (the cards and the rail), RELEASE_OCCUPANT, UNLOCK_SANCTION,
  DROP (the start-of-round drop; its pieces are selected when it lands), PENDING_COMMAND (an
  order stored on a purchase whose unit does not exist yet) and DIALOG.
- **A dialog's order applies through a pause**, since a dialog is what pauses the world: the
  stream runs while paused and applies DIALOG orders alone, everything else waiting for the
  world to resume. A dialog is named by the serial the trigger manager gives it when raised
  (`ScenarioTriggerManager.raise_dialog`), and the view closes it whenever it resolves.
- **Purchase ids restart at 1 each match** (`PurchaseTransaction.reset_ids`), so a replay in the
  same session names its purchases as the recording did.
- **Spawn serials**: `Entity.spawn_serial`, taken from `Scenario.register_piece` as a piece first
  enters the tree; `Scenario.piece_by_serial` finds a piece, garrisoned or not.
- **The file**: `ReplayFile` (header, JSON lines in gzip, version stamp, refusal of another
  version), `ReplayNames` (autosave names and the keep-three rotation, kept-name rules).
- **The recorder**: `ReplayRecorder` keeps every applied order and a `SimulationDigest` every
  second, taken at the start of a tick before its orders; in playback it compares and reports the
  first differing tick. It writes the autosave when the match ends or the scenario is left —
  except in a headless run (the test suite, self-play), which would otherwise rotate a player's
  own autosaves out of `user://`.
- **Debug mode ends the recording** (`Scenario.note_debug_change`): a debug piece, debug delete,
  a bot switched or retuned, a piece retuned, or an order to another commander's piece.
- **Playback**: a scenario given `replay_to_play` before entering the tree takes the recording's
  seed and its orders, and ignores anything submitted. `tests/test_ReplayRoundTrip.gd` records a
  minute of play and requires the playback to match every digest — and a playback with an order
  removed to report drift.
- **The wall-clock scan** in `tests/test_SeededRandomness.gd`, with its allow-list.
- **Opening a replay**: `ReplayLibrary.prepare_playback` reads the file, refuses it (not a replay,
  another version, a recording debug mode ended — `ReplayFile.playback_refusal` — or a scenario
  this build lacks), and otherwise instances the header's scenario with `replay_to_play` set;
  `SceneManager.play_replay` swaps the tree to it (`change_scene_to_node`, so it enters at idle
  time, as a scenario always does) or hands the refusal back.
- **The start screen's replay panel** (`MainMenu`, `scenes/menu/main_menu.tscn`): every file under
  `user://replays/`, newest first by modification time (`ReplayLibrary.entries`); a kept replay
  reads as its name, an autosave as when it was written. Choosing one plays it; a refused one stays
  listed and its reason is shown under the list.
- **Save replay** (`ReplaySaveForm`) at the foot of the end-of-match summary, which every end of a
  match raises — victory, defeat, and a spectator's verdict alike; a mission's EventWinLose ends
  the match through the same summary. Not offered once debug mode has ended the recording. A
  character no file name holds is taken back out of the field as typed, an autosave name is
  refused on saving, and a name already taken turns Save into Overwrite until the name changes.
  Written by `ReplayRecorder.write_kept`, which a headless run does not suppress (the player asked).
- **A playback is a spectator session.** No slot gets the human rig (`player.tscn`): every slot
  builds a `Bot`, its brain on only for a bot slot, and the watcher gets the spectator camera and
  the look-only HUD — selection, the info panel, the minimap, and the view and replay buttons in
  the command grid's slot (a human slot's view reads "Player N") — with every commander's
  resources at the top left.
  The human slot still names the local player (`RTSController.PLAYER_COMMANDER_ID`), because the
  simulation reads it — the implicit elimination rule and HEGEMONY's verdict — and the recorded
  match was judged against it. The view opens on that player's fog; the end-of-match summary
  names the winner, as a spectator's does. `test_ReplayRoundTrip` records a skirmish with the
  human's rig present and requires the spectator playback to match it digest for digest.
- **What a playback replays is orders, never the interface.** A COMMAND order carries the command
  script, the serials of the whole selection, the modifiers held and the message (target serial,
  tool and variant, position, ability, sanction, quarter turns, deferral); which actors take it is
  decided when it is applied (`OrderDispatcher.recipients`). No grid button, hotkey or panel is
  recorded or consulted, which is why a playback needs no player HUD at all.
- **Nothing the interface does may draw from the simulation's generators.** Godot's global
  generator is seeded with the match, and `Array.pick_random` / `Array.shuffle` draw from it as
  `randi` does: a voice line picked that way on a live click moved every later draw, and the
  playback — where nobody clicks — drifted. Audio picks with its own generator; simulation code
  uses `AU.pick_random` / `AU.shuffle` with `SU.rng`; `test_SeededRandomness` now flags both
  methods.
- **The viewer** (`ReplayViewer`, created by `Scenario` for a playback only): a banner — speed,
  paused, whose view — and the replay keys: `replay_pause` Q, `replay_slower` W, `replay_faster` E,
  `replay_switch_view` R, the grid's top row by position. Speed steps along 0.25× – 4×; pause is the
  `REASON_PLAYBACK_PAUSE` hold, so the spectator panel's playback toggle agrees with it, and the
  panel offers its playback controls in every playback whatever `debug_allowed` says.
- **The view is the displayed fog, never the local player.** Switching cycles each commander that
  keeps a Fog; the spectator panel's fog toggle lifts the fog over it, and the banner says so. `RTSController.PLAYER_COMMANDER_ID`
  is not touched: the simulation reads it (`Scenario`'s implicit elimination rule), so changing
  it would play a different match. `Scenario._ready` resets the displayed fog to the local
  player's, so neither a replay's view nor a spectator session's carries into the next session.
- **Dialogs in a playback** show, with their buttons disabled; each is resolved by the recorded
  order on its tick. A recorded "Return to Main Menu" choice resolves the dialog without leaving
  (`EventShowDialog` does not bind the navigation in a playback); the viewer leaves through the
  pause menu.
- **The header's start point** per slot: `Scenario.slot_start_point` — the start point's name and
  XZ for a Skirmish, empty for a scenario that places its slots by authoring. Informational: a
  playback re-derives where each slot starts from the scene, as the match did.

A replay is the scenario, its seed and slots, and the stream of **orders the human players
gave**. Playback re-runs the simulation from the seed and feeds the orders back in on the ticks
they landed. Bots are not recorded: they re-derive their orders from the same seed.

## The plan

Everything below is built unless marked `TODO`; it is kept as the statement of what each part
is for.

- TODO: **alerts and voice lines following the perspective.** There is no alert system yet, and
  the only voice lines are the barks a player's own selection and orders play — in a playback the
  viewer's selection barks, and no order is issued through the controller, so none are heard for
  the recorded player's orders. Revisit when alerts exist.

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
- **The perspective is switchable**: each player's fog, lifted or not — the existing spectator
  machinery (the displayed fog). Not play-as, which a playback refuses: that changes the local player, which the
  simulation reads. Alerts and voice lines follow the perspective on show (TODO above: there are
  no alerts yet).
- **The HUD is for looking**: the spectator session's. Superseded 2026-10-09: the first build kept
  the player's rig with its grid hidden; reusing the spectator session instead means a playback
  carries no player interface that could reach the simulation. The spectator session's HUD is
  the player's HUD scene built look-only — selection, the info panel and the minimap where they
  are in a match, the watcher's buttons in the command grid's slot
  ([ux/ui/hud-layout](../../ux/ui/hud-layout.md) §The look-only HUD).
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
