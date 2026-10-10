---
title: Menus
type: system-note
---

# Menus

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PARTLY BUILT.** The title screen's pages and the skirmish lobby work end to end; every
visual is a placeholder. Open decisions → [`gdd/tasks.md`](../../../tasks.md) T-103.

---

## The title screen is one page at a time

`MainMenu` (`scripts/interface/menu/main_menu.gd`, `scenes/menu/main_menu.tscn`) shows exactly
one page, `MainMenu.page`:

| Page | What it is |
|---|---|
| MAIN | Campaign · Arcade (WIP) · Skirmish · Replays · Options · Quit |
| CAMPAIGN | one button per authored mission (`scenarios`, ScenarioEntry rows): the three prologue missions |
| SKIRMISH | the lobby, `SkirmishLobby` — below |
| REPLAYS | every replay under `user://replays/`, newest first; an unplayable one is refused with the reason |
| OPTIONS | master volume, not saved — there is no settings system yet (`TODO`) |

- **Arcade** is a disabled button labelled WIP: the mode is not built.
- **Back** on every page, and Escape, return to MAIN. The lobby's Back is its own (it must stay
  locked while a map is generating).
- **Quit** goes through `SceneManager.quit_game`, which announces `quit_requested` before
  closing — the one exit, like the one way in and out of a scenario.
- Showing a page focuses its first enabled button, so keyboard and gamepad always start
  somewhere.

## Skirmish

The lobby is state first: `SkirmishSetup` (`scripts/interface/menu/skirmish_setup.gd`) holds
the choices and validates them; `SkirmishLobby` only draws and edits it.

**Choices.** 2–8 players (`Commander.NUM_MAX_COMMANDERS`). Each slot: a faction or Random, and
No team or Team 1–7 (`PlayerSlot.alliance`). The first slot carries a **You** checkbox: ticked,
the player plays slot 1; unticked, every slot is a bot and the player spectates. Every other
slot is a bot. Teamless players are each an alliance of their own, so all teamless is a
free-for-all.

**Validation.** Everyone in one alliance cannot be played (Play is disabled and the reason
shown).

**Factions offered.** Anarchists and Haustoria only — the two with a sanction grid and bots that
play them. `TODO`: Libertarian and Technocratic have command centres but stub sanction grids
(T-103).

**The match is always HEGEMONY**, built from the `skirmish.tscn` template: its root script
(`Skirmish`), HUD rig and trigger host, and its first PlayerSlot as every player's base
(starting energy, bot difficulty — HARD today). Its authored map is replaced.

### The recipe

Play freezes the setup into a **recipe** (`SkirmishSetup.recipe`): Random resolved to a real
faction, a map seed and a simulation seed drawn. `SkirmishLauncher`
(`scripts/scenario/skirmish_launcher.gd`) builds the match from that dictionary alone, and the
scenario keeps it (`Scenario.skirmish_recipe`) with the map seed actually played. The replay
header records it (`"skirmish"`), and `ReplayLibrary.prepare_playback` rebuilds the match from
it — a generated map exists in no file, so the scene path alone would replay on the template's
map.

### Map parameters from players and alliances

No generation parameter is exposed. `SkirmishLauncher.params_for` derives them:

- **One generator alliance per team**, a teamless player being a team of one.
- **Starts per alliance = the largest team's size.** The generator gives every alliance the same
  count (`MapGenerationParams.starts_per_alliance`), so uneven teams leave the smaller teams
  spare starts, which are removed after generation. Pitfall accepted: in a 2v1 the lone player
  has the room and resources of a two-start alliance.
- **Size grows with the start count**: the 2-start range (100–120 per side) scaled by
  √(starts / 2), so each start keeps about the same area. `TODO`: untuned — map-generation.md
  §Parameters still has only the 2-start range.
- **Starts go to slots by alliance.** The generator places an alliance's starts together and
  numbers alliances in the same order `Scenario.alliance_indices` does, so slot i takes a free
  start of its alliance, and the marker is renamed `StartPoint<i+1>` — the name Skirmish pairs
  with slot i. Commander ids therefore stay the lobby's slot numbers and colours.

### Generation runs off the main thread

A map takes 10–25 s to generate in the cloud test container (1v1 to 2v2). The lobby runs
`SkirmishLauncher.generate` — pure, scene-free — on a `Thread`, shows "Generating map…" with
every control locked, then builds the scenario on the main thread and hands it to
`SceneManager.go_to_node`. A seed that yields an invalid map is retried at the next seed, up to
eight. `TODO`: a replay of a lobby skirmish regenerates its map BLOCKING (`SkirmishLauncher.launch`).
