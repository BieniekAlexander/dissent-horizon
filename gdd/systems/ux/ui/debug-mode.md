---
title: Debug mode
type: system-note
---

# Debug mode

A developer surface, not a player feature. Everything here is gated twice: the scenario must
allow it (`Scenario.debug_allowed`, off by default) and the player must have toggled it on
(`show_debug_info`, `;`). `DebugMode.is_active()` is the one question every debug surface
asks.

PLANNED: using debug mode ends a match's recording and marks the replay invalid — see
[commands/recording-and-replay](../../commands/recording-and-replay.md) §Debug mode.

## The debug view

While active: commandables show their current command, the bot overlay draws for the bot
being viewed, and the cursor readout is up. While allowed and not active, a line above the
testing-info hint names the key.

**The debug view lifts the fog**: in the world and on the minimap, with everything pointable
(`Fog.is_lifted`). Lowering the view restores the viewer's fog; nothing the view revealed is
remembered. A spectator also has a fog toggle of their own, which the view overrides while up
([hud-layout](hud-layout.md) §The look-only HUD).

REJECTED (2026-10-09): a **Fog** picker in the debug menu and the spectator HUD, choosing
between lifted and "as the viewer sees it", beside a spectator's omniscient **No fog** view —
two controls for one fact. Reading a bot's signals against what that bot sees is now done with
the view down: the spectator's fog toggle on, the bot's view chosen.

The bot overlay shows one category of the viewed bot's signals at a time, chosen from the
spectator HUD's **Bot overlay** picker (shown only while the view is up): world marks, plus a
readout in the top-right corner. The categories and what each carries:
[ai/debug-signals](../../ai/debug-signals.md).

## The debug menu

`DebugPanel` (`scenes/interface/debug_panel.tscn`, in the player rig) is up exactly while the
debug view is, anchored top-right, and folds to its title bar. It REPLACES the top-right HUD:
the objective checklist, the scenario timer and the command-error line are hidden while it is
up, folded or not. It is not a command-grid card and does not interact with `card_ordnance` /
`card_toggle_family`.

A second menu, top-left, tunes the shared libraries and saves edited docs; it and the
editable readouts are [debug-tuning](debug-tuning.md).

It carries five things, independent of each other: the **player** setting (§Playing as
another commander), the **playback speed** while playing (§Playback speed), a **difficulty**
picker per bot, an **energy and dominion** field per commander, and the **piece card** (§The
piece spawner). While spectating, the speed is the spectator panel's and the piece card is
hidden (§Sessions); in a playback the menu is not offered at all, since nothing may change a
recorded match.

The resource fields accept digits only. Each shows the live amount until it is focused; Enter,
or leaving the field, sets the commander's stockpile to what it holds, through
`Commander.add_energy` / `add_dominion` so the economy bars hear it. Enter also hands the
keyboard back, since a focused field swallows every hotkey.

## Playback speed

Under `debug_allowed`, and in every replay, the playback controls (`PlaybackControls`) offer a
speed from 0.25× to 4× of real time, a pause, and "max speed", which runs the simulation as fast
as the machine allows. They live in the spectator panel while spectating, and in the debug menu
while playing — never in the pause menu, which stops the world they would be speeding. The
scenario timer names any speed but 1×, and a pause, so a stopped or racing clock reads as
deliberate. Leaving the scenario restores real time.

**A tick never changes meaning.** The simulation is 30 ticks per GAME second at every speed;
playback changes how many run per REAL second. It raises the engine's tick rate and its time
scale together, so the delta each step receives is still exactly one game tick, and physics,
navigation and every `delta`-integrating script advance by the same amount per tick at any
speed. The pitfall it exists to avoid: either knob alone changes the game. More steps at the
old delta move every body a fraction as far per tick; a scaled delta at the old rate makes
each tick cover more ground. Everything that converts between ticks and seconds goes through
`TimeUtils`, which reads the project setting and never the live engine rate. A seeded
self-play match produces identical digests at 0.27×, 1×, 4× and max speed.

Pitfalls accepted:

- **The rate is a whole number**, so speed moves in steps of 1/30: the slow end is 8 ticks a
  second, ≈0.27×, not 0.25×.
- **Frame-driven code speeds up too.** `_process` deltas are scaled, so HUD fades and tweens
  run fast at high speeds; at max speed they are near-instant. The camera reads real seconds
  (`PlaybackSpeed.real_seconds`) because it moves at the player's pace, not the game's.
- **Max speed is bounded by drawing**, not by a number: the engine runs up to a fixed number
  of ticks per frame drawn, so the screen updates a few times a second while it races.
- **The pause is its own hold.** It is its own `SimulationClock` reason, so it composes
  with dialog and pause-menu holds; the world stays stopped until the toggle is cleared.

## The piece spawner

Places any piece in the world, free, for any commander.

**What it offers.** Every unit, structure and feature — anything placeable on its own. Tokens
are out: their governing logic (an emitter, a Lifespan, a caster) is what makes them mean
anything, so one standing alone is not a meaningful state. Abstract bases are out.

**Where the list comes from.** `resources/generated/debug_roster.json`, written by the spec
importer beside `tools.json` rather than into it: `tools.json` drives real production cards,
and a producer-less entry there could surface on a real builder's card. A card carries the
piece's production button's label and tooltips where it has one, so the neutral pieces with
no production button still get a card.

Scenes that no spec tracks are listed too, under the faction their folder code names
(`tc/` → Technocracy), and under Neutral when the folder names none. An untracked scene
whose `Entity.id` repeats a specced piece's (`units/an/mercury.tscn` is
`an_aircraftLight_transport`) is not listed: the id is how every registry finds a piece, so it
would run under the specced piece's name and technology.

**The faction dropdown** picks the roster, any faction regardless of the player's own. The
faction and the owner are independent: any faction's piece can be given to anyone. The first
time debug mode opens, it shows the faction the player STARTED the game as, found by matching
that seat's starting units (and any pieces it owns) against the roster's scenes
(`DebugRoster.faction_of_scenes`) — the roster's faction keys (`anarchists`, `technocracy`) are
not the Faction scenes' names, so a name lookup would miss. First opening only: a faction
browsed since stays put, and playing as another commander does not move it.

**Layout.** Fixtures in one group; below it, units grouped by producer, then the units nothing
trains. A unit with several producers appears under each. The groups flow and scroll; there is
no positional layout and no cell hotkey.

**Placing.** Choosing a piece arms it the way a BUILD tool is armed
([control-matrices](control-matrices.md) §Context 1a): the world command places, left click
cancels, and `modifier_additive` keeps it armed for the next one. Hiding the debug view puts it
down.

- A **fixture** shows the build ghost and follows the footprint rule `Build` does — grid bounds,
  occupancy, an overlay's host — against the TRUE grid. Cost and technology are not checked,
  and neither is the fog-knowledge rule
  ([construction](../../commands/construction.md) §Placement is judged against what the
  commander knows): the debug view has lifted the fog.
- A **ground unit** is placed only where its OWN size class's navmesh reaches. Elsewhere the
  click does nothing: no preview, no message.
- A **flier** may go anywhere on the map.

**What a placed piece is.**

- A structure arrives finished, unlocking technology and paying upkeep at once.
- The owner's population cap is ignored.
- An aircraft that docks is sent to its owner's nearest airfield with a free pad. With none,
  it holds over the spot it was placed, as an aircraft whose deck was destroyed does
  ([docking-bays-and-pads](../../combat/aerial-operations/docking-bays-and-pads.md) §Losing
  the deck under you).
- It is a real piece to everything else: triggers, occurrence tallies and the elimination rule
  see it as they would a trained one, and a bot owner takes it up as one of its own.

**Sessions.** While playing only: a placed piece is the player's, and a spectator is nobody, so
the card is hidden while spectating (Alex, 2026-10-09). To give a bot a piece, attach to it
first.

## Debug delete

`debug_delete_selection` (Delete), only while the debug view is up, kills everything selected,
whoever owns it. A delete is a DEATH — death reactions, tallies, garrison occupants killed with
their host — because `Entity._on_death` is the only complete teardown (grid, commander
bookkeeping); `expire()` is a bare `queue_free` and would leave both behind.

## Commanding any piece

While the debug view is up, `RTSController.is_player_commandable` answers true for anyone's
piece, so box select, `modifier_additive`, double-click, the selectors and control groups take
them all, and orders go to them. A piece keeps its commander, so an attack-move through two
armies makes them fight each other.

- **The bot keeps its units.** An order to a bot's piece stands until the bot re-tasks it. To
  have a bot leave its pieces alone, set it to PASSIVE.
- **A purchase is paid by the piece's owner**: an order through another commander's producer
  or builder draws on that commander's queue, resources and technology.
- **Neutral pieces can be commanded, and nothing more is promised.** Neutral is the world, not a
  player: how a neutral piece behaves under an order meant for a player (aggro, attack-move)
  is undefined, and is not to be designed around.

Outside the debug view, selection is unchanged
([selection-and-input](selection-and-input.md) §Selecting a piece you do not own).

## Playing as another commander

The debug menu's player setting lists **Spectator** and commanders 1..N, and starts at the
session's human slot, or at Spectator in a session with none. It names who the player is, and so
who owns a placed piece. Neutral is the world, not a player, so it is not listed.

REJECTED (2026-10-09): a **Neutral** entry that gave placed pieces to commander 0 and left the
player as they were. It read as a seat to sit in and did nothing visible from one.

Choosing a commander swaps the player (`Scenario.play_as`), from another commander or from
spectating — which turns a spectator session into play:

- The controller drives the scenario's local player rather than the commander it is a child
  of, and re-binds every panel bound at startup — resource bars, production rail, sanction
  surfaces.
- Selection, control groups, an armed order and any pending purchase are cleared.
- The displayed fog is the new commander's. The rig's own `Fog` is pinned to the commander it
  was built for, as a bot's is, so every commander keeps its own exploration.
- From spectating, the HUD stops being look-only: the spectator panel and the spectator's
  top-left labels are put away, and the panels hidden for it come back.
- The camera stays where it is.
- **The slot left behind is handed to its bot, and the slot taken over has its bot put down.**
- **The elimination rule judges whoever the player is now.** Swapping to a commander with
  nothing deployed can lose the match on the spot; that is accepted.

Choosing **Spectator** detaches the player (`Scenario.spectate`), turning play into a spectator
session: the slot is handed to its bot, the HUD turns look-only
([hud-layout](hud-layout.md) §The look-only HUD), the spectator's top-left labels are built, and
the view stays on the commander just left. With nobody played, the elimination rule judges no
one and HEGEMONY ends the match as a spectator session's does.

**A playback refuses both.** Its local player is the recording's, which the simulation reads;
changing it would play a different match.

## A bot for every slot

Every slot's commander is a `Bot` with a `BotBrain` — the player rig's root is a `Bot` too — and
a human slot's brain starts switched off, which the scheduler already honours.
`Bot.is_ai_controlled()` is the question "does its bot decide"; `is Bot` no longer answers it.

- **Waking a brain rebuilds it from scratch** (`Scenario.set_ai_control`), keeping its
  difficulty: its claims, build plans and beliefs about the enemy went stale while it was off.
  A stutter on the rebuild is accepted.
- **Difficulty can change mid-match** (`Scenario.set_bot_difficulty`); the new tier's
  parameters reach the managers at once.
- **None of this is deterministic, and need not be.** Toggling a brain or changing a
  difficulty mid-match breaks a reproducible run; a debug session is not one.
