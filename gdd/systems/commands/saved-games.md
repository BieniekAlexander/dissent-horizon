# Saved games

Decided 2026-10-18 (Alex). A save puts the player back exactly where they left off. It is built
on the replay: the match's record of inputs is the save. Code: `scripts/save/`.

## What a save is

A save is the match's REPLAY so far, plus three things in its header (`SaveGame`):

- `save_tick`: the tick it was saved on;
- `save_digest`: a `SimulationDigest` of the state on that tick;
- `camera`: where the player's camera looked.

The bytes are a replay's (`ReplayFile`: gzipped JSON lines), saved as `<name>.sav` under
`user://saves/`. Like a replay, a save from another version of the game is refused, and so is a
match debug mode changed (`recording-and-replay.md` §Debug mode).

**A save is taken BETWEEN ticks**, at the point the replay recorder digests: the start of a tick,
before its orders. The pause menu saves while the world is held, which is already between ticks.
An autosave trigger fires in the middle of a tick, so it only asks (`Scenario.request_save`), and
the recorder writes the save at the start of the next one.

**Saving costs only writing the order log**, a few kilobytes. Nothing is held and nothing runs on
another thread, at an autosave or a manual save alike.

## Loading

Loading re-simulates. `SceneManager.load_save` builds the save's scenario as a replay would
(`ReplayLibrary.build_scenario_for`) and hands it the save (`Scenario.save_to_resume`). The
scenario then:

1. seeds itself from the save and plays its orders back from tick 0 (`OrderStream.play_back`);
2. runs uncapped (`PlaybackSpeed`) behind a loading screen that shows progress (`SaveResume`);
3. on the saved tick, before anything else in it runs:
   - checks the state against the saved digest, reporting a difference but carrying on;
   - switches the stream to live play (`OrderStream.go_live`);
   - puts the speed back;
   - points the camera where it was;
   - hands the match to the player.

The recorder records the re-simulation as it would a live match, so the recording, and any later
save, ends up holding the whole match again.

**How long a load takes grows with the match.** Uncapped runs up to 32 ticks per drawn frame,
which is 64× real time at 60 Hz, or less on a machine that cannot keep up. Ten minutes of play
loads in about ten seconds at best.

Scripted dialogs during the re-simulation open and are resolved by their recorded orders, exactly
as in a replay. **That needs every trigger to arm on the same tick in the match and in its
re-simulation.** Triggers arm on `NavManager.navmesh_ready`, after the navmesh's first build, and
that build is deferred, so how many physics frames ran before it used to depend on how the scene
entered the tree: a mission played from the editor raised its opening dialogs on tick 2, its
reload on tick 1, and the reload stood at 0% for good, held by dialogs whose recorded answers
were stamped for a tick it could not reach (2026-10-26). A scenario now holds the world from its
first frame until that build (`SimulationClock.REASON_BOOT`), so no tick is counted before it,
however the scene was entered. Saves made before this do not load. A trigger that would autosave during it is skipped: the save is still loading
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

## The snapshot, later

PLANNED, gdd/tasks.md T-115. A load should not have to re-simulate. Alex's design: the save keeps
its handle on the order log, and a background process re-simulates it once to build a
POINT-IN-TIME SNAPSHOT of the whole state. A load uses the snapshot when it is ready, and waits for
the re-simulation when it is not. Once the snapshot exists, its order log can be discarded.

What it needs, and why it is a phase of its own:

- **A separate process.** The simulation keeps global state (`SU.rng`, `SimulationClock`'s frame
  counts, `PurchaseTransaction`'s ids), so a second copy cannot re-simulate inside the running
  game. The game would be launched headless on the save, write the snapshot, and exit.
- **A state inventory and its serialization.** About 49 piece components, 29 bot scripts, the
  commanders, the random streams and the clocks, with every reference between pieces held as a
  serial. This is the same work rollback netplay plans (`netplay.md` §Rollback, later;
  `the-simulation-step.md` §References as serials), and should be done once, for both.
- **Restoring engine-side state** the tree does not hold: navigation paths, RVO agents, physics
  bodies.

**Accepted until then:** a long match takes a while to load, and loading always waits for the
re-simulation.
