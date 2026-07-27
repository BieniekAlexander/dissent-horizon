# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Terminology

**Garrison (verb / noun)** — the mechanic by which one entity is *inside* another: a unit enters a Commandable that has a `Garrison` component. The `Garrison` component is the host; `Occupy` is the command issued by the entering unit, and `Embark` is the order given to the HOST that hands one out (it never puts a unit inside anything itself). Which units may enter is three per-host bitmasks (frame / armour / locomotion), and how much of the host each one fills is the occupant's own `Entity.occupancy_size` — see §Garrison occupancy.

**Closed garrison (noun)** — a garrison with every occupancy mask cleared, so nothing can be ordered INTO it. A HOLD, filled only by capture, deposit, or scenario authoring: the Compound (again, as of 2026-09-17). The stock truck's cage is NOT closed: it admits Servants by order, and fills with prisoners by capture. `Garrison.is_closed()`. Closure says nothing about getting OUT: that is `Garrison.can_release()`, true by default even for a hold, and an order only ever releases the host's own side, never a captive (`Garrison.can_release_occupant`) — see §Garrison occupancy.

**Intern (verb) / internment (noun) / sentence (noun)** — what a garrison naming a positive `sentence_length` does to a captive deposited in it: the captive is held AS ITSELF, off the tree, for that many seconds — paying dominion per cycle like any other occupant — and then CONSUMED. `Garrison.can_intern()` is what marks a deposit target, and it is the Compound's whole role in the Colonial POW loop — see §Garrison occupancy.

**Actor / fixture / structure / feature / unit / token / obstruction / emission** are defined terms. An **Actor** takes orders (today's `Commandable`); a **fixture** claims terrain-grid cells. structure = Actor fixture, feature = uncommandable fixture, a **figure** is any non-fixture: unit = Actor figure, token = uncommandable figure. An **obstruction** is a fixture that blocks navigation, and an **emission** is anything an emitter put into the world. "Building" is one specific piece, not a category. Each noun is a conjunction of component facets, and code tests the facets, never the noun. → [`gdd/systems/authoring/piece-vocabulary.md`](gdd/systems/authoring/piece-vocabulary.md)

**Shelter (noun)** — a specific game structure with resource significance (distinct from the generic garrison mechanic). Do not use "shelter" as a synonym for a garrison host.

---

## Project overview

Dissent Horizon is a Godot 4.7 RTS game written in GDScript. Isometric perspective, 3D world with 2D sprites on `CharacterBody3D` nodes. The game has fog of war, a build/train economy, multiple unit types, and an AI opponent. The main scene is `scenes/scenarios/s1.tscn`. Physics runs at 30 ticks/second.

Current state: playable prototype. Terrain is a single `TerrainData` resource holding per-corner heights + a per-cell ground-material layer (see `gdd/systems/terrain-and-navigation/map-composition.md`), authored in-editor with the `terrain_brush` plugin (paint materials; raise/lower/smooth/set height). Unit/Structure class hierarchy was recently collapsed into a single `Commandable` class using component children (see §Entity hierarchy below).

---

## Design notes

**The mechanics are written up in `gdd/systems/`, not here.** This file carries the
project-wide invariants — terminology, testing, conventions, the command lifecycle, the
things not to break — plus a pointer to each system. Everything else is one directory away
and costs nothing until it is needed.

| System | Covers |
|---|---|
| [Terrain and Navigation](gdd/systems/terrain-and-navigation/) | the ground, cell passability, navmesh, pathing, terrain authoring |
| [Combat](gdd/systems/combat/) | weapons, damage, targeting, garrisoning, aerial operations |
| [Commands](gdd/systems/commands/) | command families, construction, precondition policy |
| [Macroeconomics](gdd/systems/macroeconomics/) | resources, the production queue, technology and unlock trees |
| [UX](gdd/systems/ux/) | the interface (selection, input, HUD, command grid, entity visuals), asset slots, aesthetics |
| [Scenario scripting](gdd/systems/scenario-scripting/) | triggers, objectives, dialogs, highlights, tactics |
| [Authoring](gdd/systems/authoring/) | the gdd-doc → scene pipeline and code-level audits |
| [AI](gdd/systems/ai/) | the CPU commander: perception, the think pass, difficulty as parameters |

### What is deliberately NOT done

**Anything not stable and finished carries a status marker** — `TODO`, `PLANNED`,
`WIP <UTC timestamp> <session>`, `REJECTED` or `INVARIANT` — in code and in design notes alike;
the vocabulary and what each one obliges are `~/.claude/CLAUDE.md` §13.1. Unmarked means
stable and finished. [`gdd/deferred.md`](gdd/deferred.md) indexes the `TODO`s that are
DECISIONS and the `PLANNED` work rather than local chores — what the question is and which note owns it, never the write-up itself.

### Where a new write-up goes

A design decision still gets written down as a rule, with its reasoning, the alternative it
superseded and the pitfalls it accepts — that has not changed, and an undocumented rule is
still a bug. **What changed is the destination.**

1. **A mechanic's rules go in its system note**, under `gdd/systems/`. Start at
   [`gdd/systems/README.md`](gdd/systems/README.md) — each folder's `README.md` states its
   scope boundary, and the filing rule covers splitting and cross-system cases.
2. **This file gets the pointer, never the write-up.** A section here is a heading, one line
   of blurb and a link. If you find yourself adding a third paragraph to CLAUDE.md, it
   belongs in a system note.
3. **Only a genuinely project-wide invariant is written here** — something true of every
   file, that an agent must know before reading any code. Everything else is a system note.

This file grew from 23 KB to 273 KB in three months by taking every write-up directly. The
pointer discipline is what keeps it small.

---

## Running and testing

No CLI build script. Open the project in Godot 4.7 by pointing the editor at `project.godot`.

Tests use the [GUT](https://github.com/bitwes/Gut) addon. Run all tests headlessly:
```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**`-gexit` is required.** Without it GUT finishes the run and then waits for you to
close its window — and `--headless` has no window, so the process spins in its main
loop forever after printing the summary. `-gdir` is required too: bare `gut_cmdln.gd`
exits with "You do not have any directories configured". The exit code is non-zero
when any test fails, so this form is what CI should call.

Run a single test file:
```
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HexUtils.gd -gexit
```

Tests live in `tests/` and extend `GutTest`.

### A unit test does not assert facts about authored content

**Authored content is expected to change.** A scenario's camp count, the shipped menu's
scenario list, a piece's stats — these are content, not mechanics, and a test that pins them
fails on every honest edit while isolating no logic. When such a test goes red the reflex is
to update the number, which is the wrong repair: it treats content drift as a regression.

Two rules follow:

- **Test the mechanic against a fixture you built.** `test_EventRevealRegion` is the model —
  eleven tests drive the event against a synthetic group it creates itself. The one test that
  reached into `s1.tscn` to count camps was deleted; it told you nothing the eleven did not.
- **An authored scene may be a HARNESS, never the subject.** Instantiating `main_menu.tscn`
  to get a `MainMenu` and then feeding it synthetic entries is fine. Asserting how many
  scenarios the shipped menu ships is not.

**A simulation test is not a unit test and does not run in GUT.** It asks whether the game is
balanced and behaves as designed — an answer allowed to move when a stat moves. A check on the
software's continued correctness is a REGRESSION test and belongs in the suite, whatever
environment it needs. Simulation scenarios live outside `tests/` and are run from
`tools/simulation/` (`run_scenarios.tscn`); the authored-spec grammar is planned, not built.
→ **[`gdd/systems/scenario-scripting/simulation-tests.md`](gdd/systems/scenario-scripting/simulation-tests.md)**

Spec docs are the same argument, one layer up — see below.

### The spec importer is NOT part of the test loop

GUT is what you run to check a change. **The importer is run only when the work is
doc-facing** — a piece added/removed/renamed, spec frontmatter edited, or the schema,
validation rules, generators or scene sync changed. It rewrites scenes and regenerates
`scripts/generated/` + `resources/generated/`, so running it on gameplay, UI, terrain or
test-only work pulls every unrelated doc edit since the last run into the diff.
→ **[`tools/spec_import/README.md`](tools/spec_import/README.md)** §Running

### A file-scope `preload` of an entity scene in a test can poison the whole run

`Tool`'s registry is a STATIC built on first reference, and referencing it loads every
tool scene named in the generated registry. A test file's `const X = preload("…some
entity scene…")` runs at PARSE time — before GUT has run anything — so if that file sorts
early in the directory listing, the static initialiser fires before the registry is ready
and `Tool.for_name` returns null **for every test after it**.

Use `load(...)` INSIDE the test instead. A preload is fine in a file that does not sort
first, which is why several existing tests get away with it — that is luck, not a rule.

### A skipped test file is invisible, so a test watches for one

GUT cannot run a file that does not PARSE, and it reports the run green anyway — the tests
inside simply stop existing.

`tests/test_SuiteIntegrity.gd` is the guard. It asserts over FILE TEXT rather than over loaded
scripts, and that is the whole design — a file that cannot be parsed cannot be loaded, so
anything that inspects it by loading it is blind to precisely this case. It checks that every
literal `res://` path named under `tests/` resolves, that the file count has not gone DOWN
(a ratchet, not a pin), and that any script in `tests/` which is not a `GutTest` is prefixed
with `_` so a deliberate non-collection cannot be confused with an accidental one.

**Never take a baseline by COUNT alone** — take it by file and test name. A count that matches
is exactly what a silent skip looks like.

### Seeing the HUD without a screen

GUT covers no layout: a panel can size to zero, anchor its children outside itself, or draw a
blank card and every test still passes. `--headless` can't help — it uses a dummy renderer.

Render frames offscreen instead:
```
godot res://scenes/scenarios/skirmish.tscn --write-movie /tmp/shot.png --fixed-fps 30 --quit-after 300 --resolution 1400x790
```
(no `--headless`) writes `shot00000000.png`, `shot00000001.png`, … which can be read directly.
`--quit-after` counts FRAMES, so pick a number past the scenario's opening dialog and its
deferred spawns — the first frames show an empty world.

This is worth reaching for on any HUD change.

To see a HUD state a scenario doesn't reach on its own (a loaded production queue, say),
drive it from a throwaway scene under `res://` that builds a Commander and the panel directly
— just remember Godot only registers a new `class_name` after `godot --headless --import`.

---

## AFK task sessions

<!-- PORTABLE: this section is self-contained. To reuse it in another repo, copy from this
     heading down to the next `---` and change the task file path and test command. -->

**Task file: `gdd/tasks.md`** — an Obsidian note. Each `##` heading is one task; its body is the spec I wrote for it. I kick a session off with `/tasks`, walk away, and read the file when I'm back. That file is the entire interface between us: anything you need to tell me goes in it, at the task it belongs to.

Edit the task file by **appending only**. Never delete, reword, or reorder my task text.

### Task status

State is a tag on the `##` heading. No tag means ready to work.

| Tag | Meaning |
|---|---|
| *(none)* | Ready — fair game for an unattended session |
| `#wip` | Started and unfinished; carries a Progress note saying where you stopped |
| `#needs-input` | Has an unanswered question; that part of the task is parked |
| `#done` | Finished. Leave it in place; I archive it |

`#wip` and `#needs-input` can both apply: part built, part parked on a question.

### Ask rather than assume

**When my spec doesn't determine something that changes what gets built, ask — don't pick.** I would rather come back to a question than to code I have to unpick. Unanswered means unwritten: never write speculative code to be helpful, and never bury a decision in an implementation and mention it afterwards.

That applies to decisions about **behaviour, scope, or architecture**. It is not licence to interview me about ordinary craft — naming, file placement, which existing helper to reuse, how to structure a test, anything §Key conventions or the surrounding code already answers. Those are yours to make, silently.

If I want a decision to be yours, I'll say so when I answer.

### Raising a question

Append a question callout to the task. Don't ask me in chat.

> [!question] Q — 2026-08-06
> Should the see-through silhouette cover units inside a garrison?
> **Why it matters:** `Garrison` hides occupant meshes entirely, so covering occupants means adding a way to reach those meshes; skipping them touches `Garrison` not at all.
> **Options:**
> 1. Skip garrisoned units — silhouette only free-standing entities.
> 2. Silhouette the host, tinted while it holds occupants.
> 3. Expose occupant meshes to the silhouette pass — needs a new `Garrison` accessor.
>
> **Leaning:** 1 — smallest change, and consistent with the task's "only entities without a `Structure` component" note.
>
> **Answer:**

- **One decision per block.** Several open decisions on a task means several blocks.
- First line is `> [!question] Q — <YYYY-MM-DD>`.
- **Why it matters** is stated in terms of this codebase — what actually changes depending on the answer. Not "please advise".
- **Options** are 2–4 genuinely different approaches, not rewordings of one, each named concretely enough that I can pick by number from my phone. Never list an option you'd argue against building. "Something else" is always implicitly available — don't spell it out.
- **Leaning** is mandatory: one option, one clause of reasoning. It is what you build if I hand the decision back to you, so mean it.
- End with a bare `> **Answer:**`. That's where I type. Leave it empty.

### While a question is open

Do every part of the task the spec *does* determine, and leave the part the question covers unbuilt. Then move to the next task — a parked question is never a reason to sit idle.

- Question covers the task's whole direction → tag `#needs-input`, build nothing on it.
- Question covers one sub-part → build the rest, tag `#wip #needs-input`, and say in the Progress note exactly which piece is waiting.

### Returning to answered questions

`/tasks` both starts and resumes; there is no separate resume command. Every run, before anything else, read the whole task file and handle answered questions first — a question I bothered to answer is the highest-value work in the file.

A question is answered iff there is text after `> **Answer:**` — on that line or on the `>` lines beneath it. My answer may be a bare option number, an option with modifications, prose describing something you didn't list, or a handback ("your call", "up to you", "whatever's simplest") — a handback means build your stated **Leaning**. Then:

1. Do the work the answer implies.
2. Rewrite the first line to `> [!done] Q — resolved — <YYYY-MM-DD>` and append `> **Resolved:** <one line, with file paths; name the option taken>`. Keep my answer text intact.
3. Clear `#needs-input` from the heading once no unanswered question remains on it.

If my answer is ambiguous or opens a new decision, don't re-ask inside the same block — do what it clearly licenses and add a fresh `[!question]` below it.

### Progress notes

When you stop work on a task, append one:

> [!check] Progress — 2026-08-06
> Silhouette pass in `scripts/shaders/see_through.gdshader`, wired into `commandable.tscn`.
> Tests: 214 passing, `test_Fog.gd::test_snapshot_tint` failing (pre-existing).
> **Not done:** garrison handling — parked on Q above.

One block per session per task, appended below that task's questions. State what is **not** done as plainly as what is, and name any piece left unbuilt because a question is open — I'm reading this instead of watching you work. Run the test suite (§Running and testing) before writing the note and report failures in it.

**Keep them short, because the task file is a work queue and not a record.** I delete tasks once they are in the project, so nothing written there survives — a note is a handover I read once, not an archive. Anything durable (a rule, a rationale, a decision and what it superseded) belongs in THIS file or in a `gdd/` design note, and the progress note should just say what changed, what is not done, and where the real write-up lives. A note long enough to be worth keeping is a note written in the wrong file.

### The task file moves on its own

The task file is an Obsidian vault note under **Obsidian Sync**, so it is not yours exclusively while you work. I answer questions from my phone, and Sync can rewrite the file on disk mid-session — last writer wins, silently, with no conflict marker.

- **Re-read the task file immediately before every append.** Never write it from a copy you read earlier in the session; you would erase whatever Sync delivered in between.
- Append and save promptly — a block held back until the end of a session is a block that can be lost.
- If a re-read shows my text changed under you, my version wins. Fold your pending block into the new content rather than overwriting.
- If an answer appears on a question you already parked, pick it up right then. It's the freshest thing in the file.

Sessions run locally on this machine, against the working tree — that is the whole delivery path, and it is why nothing here needs pushing.

### Starting a session from my phone

`/tasks` is the entry point at a terminal or in the Desktop **Code** tab. It does **not** resolve in **Cowork/Dispatch**, which loads skills from my claude.ai account rather than from `~/.claude/`. From the phone I message Dispatch in prose instead, and it spawns a local Code session that does see this file:

> Open a Claude Code session in ~/personal/dissent-horizon and run an AFK task session: follow the "AFK task sessions" section of CLAUDE.md against gdd/tasks.md.

Either route ends in a local session reading the working tree, so the rules above are unchanged. If you were spawned this way and the protocol is unclear, re-read this section rather than guessing at it from the prompt alone.

### Session rules

- **Don't commit.** Leave the working tree dirty so I can read the diff myself. Don't stash, reset, or switch branches either. This goes double for the task file: committing a Sync-owned note invites a conflict later.
- Work order: answered questions → untagged tasks → `#wip` tasks. Skip `#needs-input` unless its question got answered.
- If you think a task is wrong, obsolete, or already done, say so in a `[!question]` — don't act on that judgement.

---

## Tech stack

- **Godot 4.7**, GDScript only
- **Addons**: `gut` (testing), `csv-data-importer` (terrain grid CSVs), `godot-improved-json` (JSON serialization), `terrain_brush` (in-editor terrain painting/sculpting), `map_generator` (the map-generation dock), `terrain_snap` (drag-snap entities to the grid/height), `editor_camera_angle`, `scene_visibility_tools`
- Collision layers are centralised in `scripts/collision_layers.gd` (`CollisionLayers.Mask.*`)

---

## Folder / file structure

```
scripts/
  scenario.gd                     — root node for a game session
  entities/
	entity.gd                     — base class (CharacterBody3D)
	commandable.gd                 — entity that accepts commands (units + structures)
	command_receiver.gd            — manages the command queue (RefCounted)
	hit_box.gd
	components/                   — optional node-children bolted onto entities
	  defense.gd                  — hp, hp_max, armor
	  loadout.gd                — holds Weapon children
	  locomotion.gd               — goal-based movement interface; strategies subclass it
	  movement.gd                 — the navigated Locomotion strategy; wraps NavigationAgent3D
	  phased_locomotion.gd        — the phased Locomotion strategy: runs an emission's phase list
	  aerial.gd                   — flight and height: mode, landing, deck, taxi, dive, orbit
	  docking.gd                  — the unit-side half of an airfield: its pad, runway, rearm trips
	  payload.gd                  — an emission's damage, aiming and status effects
	  tracer.gd                   — draws an emission's beam
	  obstruction.gd              — declares footprint dimensions for structures
	  energy_extractor.gd
	  ownership.gd                — commander relationship + team tint signal
	  production.gd               — training queue; also has producible_types
	  garrison.gd                 — holds occupants; Occupy enters, Evacuate releases; occupancy masks + sizes
	  repairs.gd                  — marks a unit able to repair (doc key `repairs: true`); presence is the check
	  selectable.gd
	  dominion_generator.gd
	  command_line_indicator.gd
	  mesh_visual.gd              — the model: team tint, construction + status channels, facing
	  status_visuals.gd           — condition → look: stealth fade, effect shade, floating badges
	structures/
	  lab.gd, extractor.gd, extraction_site.gd, footprint_visualizer.gd
	units/
	  vanguard.gd
	tools/
	  tool.gd                     — Tool class; command_tool_map loads from resources/generated/tools.json
	  weapon.gd                   — Weapon node; AttackRange child = ranged, null = melee
	  emitter.gd                  — Emitter.launch: puts an emission into play (payload, goal, tracer)
	  emission_phase.gd           — one phase of an emission's motion, end clauses and payload cadence
	items/
	  star.gd
  interface/
	rts_controller.gd             — CanvasLayer: selection, input, HUD, build preview
	command_context_parser.gd     — maps entity predicates → available command names
	command_message.gd            — context bundle passed to commands
	commands/                     — one file per command type
	  move_command.gd              — base class; static meets_precondition/requires_position/tool_applies_to
	  assemble.gd — finish a PLACED structure (the second half of a build order)
	  attack.gd, attack_move.gd, build.gd, capture.gd, collect.gd
	  defend.gd, drop_off.gd, launch.gd, pick_up.gd, repair.gd, stop.gd, train.gd
	commander/
	  commander.gd                — tracks energy/infrastructure/dominion + technology_mapping
	  production_queue.gd         — the global purchase queue (one list, two tiers)
	  purchase_transaction.gd     — one queued purchase: cost snapshot, state, producers/holders
	  bot.gd                      — AI subclass of Commander
	  bot_scheduler.gd            — paces every bot's jobs against one per-tick work-unit budget
	  bot_claims.gd               — which bot manager owns which unit
	  cost_spec.gd
	hud/
	  button_spec.gd, command_grid.gd, static_grid_button.gd, static_grid_container.gd
	  scenario_dialog_view.gd     — pop-up panel + help button (built in code; PROCESS_MODE_ALWAYS)
	  dialog_page.gd              — one page of pop-up copy; authored as scenes/dialogs/*.tscn
    help_book.gd                — the scenario's help-button page list
    objective_view.gd           — objective checklist; layout authored in scenes/interface/
  rts_camera_3d.gd
  waypoint_indicator.gd
  scenario_highlight.gd         — ImmediateMesh painter for objective marks/regions
  input_prompt.gd               — {{ action }} → current key binding, for player-facing copy
  scenario/
  scenario_trigger_manager.gd   — trigger host; owns the poller + the SimulationClock
  global_trigger.gd             — conditions + inline child events; arms/fires
  simulation_clock.gd           — reason-counted holds driving SceneTree.paused
  scenario_dialog.gd            — one acknowledge request, carrying a page scene (RefCounted)
  highlight_shape.gd            — circle / rotated-rect XZ footprint (RefCounted)
  objective_chain.gd            — runs its GlobalTrigger children one at a time
  conditions/                   — one Condition subclass per check
  events/                       — one AbstractEvent subclass per effect
  maps/
  map.gd                        — @tool; owns terrain, navmesh, cell_grid, coordinate helpers
  generation/                   — pure map generator (MapGenerator); addons/map_generator is its editor dock
  minimap_layer.gd              — the minimap's per-cell map layer (pure); minimap.gd draws it through fog
  fog.gd                        — MeshInstance3D fog-of-war shader driver
  terrain/
    terrain_data.gd             — @tool Resource; the authored source: heights + per-cell tile_types + catalog
    tile_type.gd                — @tool Resource; one ground material (art only; never passability)
    terrain_tile_catalog.gd     — @tool Resource; the tile-type palette (byte index → TileType)
    terrain_grid.gd             — tracks per-cell passability (steep / building / blocked bitmask)
    nav_manager.gd              — builds NavigationMesh from passable cells
    heightmap_mesh_generator.gd — @tool; generates ArrayMesh from the derived HeightMapShape3D
  utils/
  vector_utils.gd               — VU alias (VectorUtils)
  array_utils.gd                — AU alias (ArrayUtils)
  space_utils.gd                — SU alias (SpaceUtils)
  hull.gd                       — a piece's XZ footprint; every piece-to-piece range is the gap between two
  collision_utils.gd
  evaluator.gd
  function_utils.gd
  node_utils.gd
  set.gd
  rendering/
  priority.gd                   — RenderPriority constants (FOG_PRIORITY etc.)
  shaders/fog.gdshader
  collision_layers.gd
  nav_grid.gd
scenes/
  dialogs/                        — DialogPage scenes: reusable pop-up copy
  interface/                      — authored HUD pieces instanced into player.tscn
  scenarios/s1.tscn               — main scene
  player.tscn                     — Commander id=1 with RTSController + Camera
  map/terrain.tscn
  components/                     — the component library: one scene per component with children or defaults
  entities/                       — all game entities, grouped by category then faction; none inherits another
    units/                        — per-faction subfolders
      tc/vanguard.tscn
      an/technician.tscn, b_irregular.tscn, warlord.tscn, b_kamikaze.tscn
      cl/h_recruit.tscn, h_badger.tscn
    structures/                   — per-faction subfolders
      nt/building.tscn, extractor.tscn, extraction_site.tscn, shelter.tscn
      tc/dwelling.tscn, lab.tscn, compound.tscn, armory.tscn
      an/b_redoubt.tscn
      cl/h_sam.tscn, h_cannon.tscn
    projectiles/                  — projectile.tscn, bullet.tscn, lazer.tscn, radiation.tscn (base/generic) at root
      an/irregular_bullet.tscn, warlord_rocket.tscn, b_kamikaze_bomb.tscn
      cl/h_badger_rocket.tscn, h_cannon_shell.tscn, h_recruit_bullet.tscn, h_sam_missile.tscn
  # faction-code dirs are organizational only: nt=neutral, tc=technocracy, an=anarchists/baladians,
  # cl=collective/colonials, lb=libertarian, th=theocratic, mr=marxist
scenes/entities/status_effects/       — standalone status-effect scenes (instanced under projectile EffectApplicators)
scripts/generated/                    — AUTO-GENERATED EntityIds / StatusEffectIds (spec importer)
resources/generated/                  — AUTO-GENERATED technology.json / tools.json (spec importer)
tools/spec_import/                    — the gdd-doc importer (see its README)
gdd/                                  — design docs; a file is an importable spec iff its frontmatter names a `kind` (location is free; the FILE NAME is the piece id)
configs/
  scenarios/scenario1/, scenario2/
  init.json    — per-commander starting entities (scene path + grid location)
  events.json  — timed spawn waves
tests/
addons/
assets/
gdd/
  systems/                            — DESIGN NOTES: one folder per system, README states its scope
  factions/, projectiles/, shapes/, setting/   — spec docs (importable iff frontmatter names a `kind`)
  tasks.md                            — the AFK work queue
```

---

## High-level architecture

### Session root: `Scenario`

`Scenario` (`scripts/scenario.gd`) is the scene root. It creates the commanders: id 0 = neutral/world, then one `Bot` per player slot — a human slot's is the `scenes/player.tscn` rig, with its brain switched off. Entities live as children of their commander in the scene tree; reparenting happens automatically via the `Ownership.commander_changed` signal.

### Entity hierarchy (flat, component-based)

```
Entity (CharacterBody3D)           — type enum, @export default_commander_id, auto-init from scene
  @onready ownership: Ownership    — commander ref; emits commander_changed
  @onready defense: Defense        — hp, hp_max, armor (get_node_or_null)
  @onready locomotion_component: Locomotion — the "Locomotion" node, any strategy (null = immobile)
  movement: Movement               — the LIVE navigated strategy; wraps NavigationAgent3D
  can_move()                       — "can this move at all?"; ask this, not movement != null
  @onready weapon_inventory: Loadout   — holds Weapon children (get_node_or_null; null = unarmed)
  @onready vision_range_shape: CollisionShape3D
  @onready aggro_shape_ground / aggro_shape_air: CollisionShape3D   — derived from reach (RangeShapes)

  └── Commandable (Entity)         — command queue, HP bar, aggro logic, _physics_process
    @onready command_receiver: CommandReceiver   (RefCounted, not a Node)
    @onready selectable: Selectable
    @onready production: Production    (get_node_or_null; null = can't train)
        @onready energy_extractor: EnergyExtractor
        @onready dominion_generator: DominionGenerator
```

**Units** and **Structures** are no longer separate classes, and no piece scene inherits another:
each is COMPOSED from its doc (`tools/spec_import/composition.gd`), with groups the importer derives
and writes on the root:
- `"unit"` — a mobile piece that takes orders; gates movement/aggro logic
- `"fixture"` — a piece that claims terrain-grid cells, features included; gates grid registration/teardown and footprint reach
- `"structure"` — a fixture that takes orders (a subset of `"fixture"`); gates production, rally, construction state
- `"piece"` — every Actor and feature; used by fog.gd, scenario iteration (it was `"commandable"`, which features were never)

Use `entity.is_in_group("unit")` / `is_in_group("fixture")` / `is_in_group("structure")` rather than `is Unit` / `is Structure` (those classes don't exist anymore). A placed instance must not store these groups itself — the piece scene supplies them (`tests/test_DerivedGroupsStayOnPieces.gd`).

### Piece ids (`Entity.id` — the old `Entity.Type` enum is gone)

Every game piece is identified by a snake_case StringName `Entity.id` (e.g. `&"warlord"`), which is the id of its spec doc in `gdd/` (see §Spec importer). Hand-written code references ids through the GENERATED `EntityIds` constants (`EntityIds.WARLORD`) — never raw strings. An empty id marks an abstract inheritance-base scene (`Entity.is_abstract()`). Unit-vs-structure is group membership / the `Structure` component, never the id.
- Commander id `0` = neutral/world-owned (unchanged)

### Component attachment pattern

All optional components are node-children resolved with `get_node_or_null` in `@onready` vars. The pattern throughout the codebase:
```gdscript
@onready var production: Production = get_node_or_null("Production") as Production
# then: if production != null: ...
```
Required nodes use `$NodeName` directly or assert. See `gdd/systems/authoring/get-node-or-null-audit.md` for the full audit of which are legitimately optional vs. likely bugs.

---

## Command system

Commands are the primary game-action abstraction. Each command is a `RefCounted`-subclass instance. The per-tick lifecycle (driven by `CommandReceiver._update_state()` → `Commandable._process_commands()`):

1. `get_updated_state(actor)` — may reactively swap to a new command (e.g., interrupt with attack)
2. `can_act(actor)` — checks if the action is ready (in range, timer elapsed, etc.)
3. `fulfill_action(actor)` — performs the action, returns a follow-up command or `null`
4. If not acting and `should_move()`: set the actor's `Locomotion` goal to `message.position` and tick it
5. On arrival (`Locomotion.tick()` reports `ARRIVED`), the command is dropped — but ONLY if `ends_on_arrival()` says arriving was the point of it

**`ends_on_arrival()` (defaults true) is what separates "go there" from "go there and then do something".** A plain move is finished by arriving. `Build`, `Assemble`, `Repair` and `Interact` travel in order to act in range, so they return false and `can_act` — not the navigation agent — decides when they are done.

**A unit wider than a cell reaches a building differently.** Its class navmesh is eroded back from every wall, so it can neither stand in a cell touching a footprint nor path through a one-cell gap — which is why "close to a structure" allows a size-class standoff, and why the approach cell is chosen by a real path rather than by distance. → [`gdd/systems/terrain-and-navigation/agent-size-classes.md`](gdd/systems/terrain-and-navigation/agent-size-classes.md) §Reaching a building

Build, Assemble and Repair — the construction and repair command family.
→ **[`gdd/systems/commands/construction.md`](gdd/systems/commands/construction.md)**

Go and Fire — the plain move and the shot at a place the click ladder could not express.
→ **[`gdd/systems/commands/saying-it-plainly.md`](gdd/systems/commands/saying-it-plainly.md)**

## Garrison occupancy

How one entity is held *inside* another: occupancy masks, closed holds, capture and deposit,
and `Embark` — the host's side of a garrison order.
→ **[`gdd/systems/combat/garrison-and-transport.md`](gdd/systems/combat/garrison-and-transport.md)**

## Projectiles and emitted objects

An emission is an ordered list of phases — motion, end clauses, payload cadence, events — and
nothing collides in flight unless a phase asks to.
→ **[`gdd/systems/combat/projectiles.md`](gdd/systems/combat/projectiles.md)**

## Charged ammunition and airfield docking

Charged clips, airfields, pads, runways, attack runs and rearming.

- [`gdd/systems/combat/aerial-operations/charged-ammunition.md`](gdd/systems/combat/aerial-operations/charged-ammunition.md)
- [`gdd/systems/combat/aerial-operations/docking-bays-and-pads.md`](gdd/systems/combat/aerial-operations/docking-bays-and-pads.md)
- [`gdd/systems/combat/aerial-operations/runways.md`](gdd/systems/combat/aerial-operations/runways.md)
- [`gdd/systems/combat/aerial-operations/attack-runs.md`](gdd/systems/combat/aerial-operations/attack-runs.md)
- [`gdd/systems/combat/aerial-operations/rearm-and-resupply.md`](gdd/systems/combat/aerial-operations/rearm-and-resupply.md)

## Input and HUD (`RTSController`)

Selection, control groups, input actions, the command grid, HUD panels and construction visuals.

- [`gdd/systems/ux/ui/selection-and-input.md`](gdd/systems/ux/ui/selection-and-input.md)
- [`gdd/systems/ux/ui/hud-layout.md`](gdd/systems/ux/ui/hud-layout.md)
- [`gdd/systems/ux/ui/economy-bars.md`](gdd/systems/ux/ui/economy-bars.md)
- [`gdd/systems/ux/ui/command-card-and-hotkeys.md`](gdd/systems/ux/ui/command-card-and-hotkeys.md)
- [`gdd/systems/ux/ui/control-matrices.md`](gdd/systems/ux/ui/control-matrices.md)
- [`gdd/systems/ux/ui/input-action-naming.md`](gdd/systems/ux/ui/input-action-naming.md)
- [`gdd/systems/ux/ui/construction-visuals.md`](gdd/systems/ux/ui/construction-visuals.md)
- [`gdd/systems/commands/construction.md`](gdd/systems/commands/construction.md)

## Map, terrain, and navmesh

Map, terrain grid, navmesh, pathing, terrain authoring, mesh baking and water.

- [`gdd/systems/terrain-and-navigation/map-and-terrain-grid.md`](gdd/systems/terrain-and-navigation/map-and-terrain-grid.md)
- [`gdd/systems/terrain-and-navigation/navigation-and-pathing.md`](gdd/systems/terrain-and-navigation/navigation-and-pathing.md)
- [`gdd/systems/terrain-and-navigation/incremental-navmesh.md`](gdd/systems/terrain-and-navigation/incremental-navmesh.md) — staggered navmesh chunks: a change rebuilds only the chunks it reaches
- [`gdd/systems/terrain-and-navigation/terrain-authoring.md`](gdd/systems/terrain-and-navigation/terrain-authoring.md)
- [`gdd/systems/terrain-and-navigation/mesh-baked-terrain.md`](gdd/systems/terrain-and-navigation/mesh-baked-terrain.md)
- [`gdd/systems/terrain-and-navigation/water-bodies.md`](gdd/systems/terrain-and-navigation/water-bodies.md)
- [`gdd/systems/terrain-and-navigation/map-composition.md`](gdd/systems/terrain-and-navigation/map-composition.md)
- [`gdd/systems/terrain-and-navigation/map-generation.md`](gdd/systems/terrain-and-navigation/map-generation.md) — passes 1–6 built, 7 TODO

## Scripted scenarios: objectives, dialogs, pause, highlights

Mission scripting: triggers, conditions, objectives, dialogs, pause, highlights and tactics.

- [`gdd/systems/scenario-scripting/triggers-and-events.md`](gdd/systems/scenario-scripting/triggers-and-events.md)
- [`gdd/systems/scenario-scripting/conditions-and-regions.md`](gdd/systems/scenario-scripting/conditions-and-regions.md)
- [`gdd/systems/scenario-scripting/objectives-and-completion.md`](gdd/systems/scenario-scripting/objectives-and-completion.md)
- [`gdd/systems/scenario-scripting/dialogs-and-pause.md`](gdd/systems/scenario-scripting/dialogs-and-pause.md)
- [`gdd/systems/scenario-scripting/highlights-and-fog-reveal.md`](gdd/systems/scenario-scripting/highlights-and-fog-reveal.md)
- [`gdd/systems/scenario-scripting/tactics.md`](gdd/systems/scenario-scripting/tactics.md)
- [`gdd/systems/scenario-scripting/starting-formations.md`](gdd/systems/scenario-scripting/starting-formations.md)

## The cursor

Its five images, which one shows when, and why the OS keeps replacing it with its own.
→ **[`gdd/systems/ux/ui/cursor.md`](gdd/systems/ux/ui/cursor.md)**

## Why a command button is dark

One vocabulary for every grid button — train tools, build tools, verbs and abilities alike:
the blocker, its colour, the charge pips and the cooldown countdown.
→ **[`gdd/systems/ux/ui/command-card-and-hotkeys.md`](gdd/systems/ux/ui/command-card-and-hotkeys.md)** §What a darkened button means

## Debug mode

`Scenario.debug_allowed` and the `;` toggle; the debug menu: piece spawner, debug delete, commanding any piece, playing as another commander, bot difficulty.
→ **[`gdd/systems/ux/ui/debug-mode.md`](gdd/systems/ux/ui/debug-mode.md)**

## Condition visuals (`StatusVisuals`)

How a unit's condition is drawn: effect tints, floating badges, veterancy and capacity pips.
→ **[`gdd/systems/ux/ui/condition-visuals.md`](gdd/systems/ux/ui/condition-visuals.md)**

## Unit animation (`ActionTracker`, `AnimationRig`)

What a piece is doing, as reported by the command tick; per-kind profiles that turn it into
clips; the action badges that stand in until models animate.
→ **[`gdd/systems/ux/unit-animation.md`](gdd/systems/ux/unit-animation.md)**

## Generated visual defaults

Placeholder meshes per piece class, plus derived selection shapes and HP bars, baked into
scenes by the spec importer. **It never overwrites a value that is already there — clearing
a slot is what asks for a fresh bake** (the one exception is the `--rebake-visuals` migration
flag, which replaces values the importer does not own). `tools/ui_audit.gd` reports what is
still wearing a stand-in.
→ **[`gdd/systems/ux/ui/generated-visual-defaults.md`](gdd/systems/ux/ui/generated-visual-defaults.md)**

## Asset slots: a missing asset is reported, never raised

Every model, voice line and other asset a piece is expected to carry is a SLOT, judged by an
`ASSET` rule in the spec importer: `FILLED`, `PLACEHOLDER`, `MISSING`, or `EXEMPT` by a doc
waiver. The importer's summary is the one place an unfilled slot is surfaced — never
`push_error` at runtime for an asset nobody has made yet.
→ **[`gdd/systems/ux/README.md`](gdd/systems/ux/README.md)** §Asset slots

## Fog of war (`scripts/maps/fog.gd`)

One `Fog` per commander, kept INCREMENTALLY: a per-pixel count of the vision sources covering
it, re-stamped only for a source whose pixel or footprint changed, with the texture uploaded
only for the displayed fog when its bytes changed. Vision sources are the **`"los"` group**
(every `Entity` with a `VisionRange` shape, added in `Entity._ready`, independent of
`"piece"`); hiding enemy pieces is a separate pass over `"piece"`, and over beacons and
emissions (`Fog._apply_figure_visibility`) — fog hides everything under it.
→ **[`gdd/systems/combat/scan-and-vision-cost.md`](gdd/systems/combat/scan-and-vision-cost.md)** §The fog of war

Anything with a `VisionRange` reveals fog — a sighted Beacon, the Recon Drone — — it lands in `"los"` automatically. Do NOT assume the vision shape is a cylinder: `_vision_offsets()` must stay shape-agnostic.

`POINTS_PER_UNIT = 1.0 / Map.CELL_SIZE` (set in `_initialize`). The fog plane is scaled to cover the terrain plus one cell margin.

Hide fog for debugging: toggle the debug view with `;` (`show_debug_info`), in a scenario with `debug_allowed` set (see `DebugMode`).

**What a commander can SEE, and what that gates** — one `Fog` per commander id, why an
out-of-play pixel is not vision, and why acquiring a target and releasing one have to measure
the same region.
→ **[`gdd/systems/combat/target-acquisition.md`](gdd/systems/combat/target-acquisition.md)**

---

## Commander and economy

Commander resources, technology gating, the global production queue and requisition mode.
→ **[`gdd/systems/macroeconomics/production-and-economy.md`](gdd/systems/macroeconomics/production-and-economy.md)**
(the requisition toggle was replaced by the additive modifier —
[`requisition-as-a-modifier.md`](gdd/systems/macroeconomics/requisition-as-a-modifier.md))

## A spent charge is refused; the modifier is what queues it

Why an ability with no charge is refused like an unaffordable purchase, and what greys the button.
→ **[`gdd/systems/commands/cooldowns-and-preconditions.md`](gdd/systems/commands/cooldowns-and-preconditions.md)**

## The Colonial bombardment system

Siege guns whose reach is vision-by-proxy: beacons, spotters, bombard targeting, and the
battery as an ability.
→ **[`gdd/systems/combat/bombardment.md`](gdd/systems/combat/bombardment.md)**

## The sanction grid

**"Sanction" means one thing: an ability unlocked with dominion, through this grid.** It is
an unlock route, not a kind of thing — abilities also arrive free or bought at a structure,
and HUD presence is authored per ability (`hud_button:`) rather than following the route.
The word is always the VERB's sense — *to authorise* — never the punitive plural.

- [`gdd/systems/macroeconomics/sanctions/sanction-grid.md`](gdd/systems/macroeconomics/sanctions/sanction-grid.md)
- [`gdd/systems/macroeconomics/sanctions/payloads.md`](gdd/systems/macroeconomics/sanctions/payloads.md)
- [`gdd/systems/macroeconomics/sanctions/off-map-abilities.md`](gdd/systems/macroeconomics/sanctions/off-map-abilities.md)

## The composition rework (steps 0–3 and 5 built, 4 mostly built)

The doc declares a piece's component set: `kind:` names only the class a spec loads, emissions
are phase lists, and piece scenes are composed from a component library rather than inherited.
One plan for the entity model and the projectile redesign.
→ **[`gdd/systems/authoring/composition-rework.md`](gdd/systems/authoring/composition-rework.md)**

## The ability module fold

There is ONE ability system — a `kind: AbilityDefinition` doc, an `Abilities` pool, `AbilityCatalog` —
and `Bombards`, `Ability.Type`/`Inventory`/`ToolSpec` and `Spotter` were the exceptions to it.
→ **[`gdd/systems/authoring/ability-module-fold.md`](gdd/systems/authoring/ability-module-fold.md)**

## `Tool` wiring and the spec importer

The gdd-doc → scene/data pipeline: Tool registry, doc schema, and what stays editor work.
→ **[`gdd/systems/authoring/spec-importer.md`](gdd/systems/authoring/spec-importer.md)**

## Unit calibration: rules the importer enforces

The importer's second validation pass: physics-facing numbers, the three verdicts, and which exports earn a doc key.
→ **[`gdd/systems/authoring/calibration-rules.md`](gdd/systems/authoring/calibration-rules.md)**

---


## Key conventions and patterns

### Variable typing

- Prefer specifying variable types rather than impling them, e.g. `var i: int = 0` rather than `var i := 0`

### `@onready` and optional components

- Required nodes: use `$NodeName` directly or `assert()`. Don't silently accept null for nodes that must exist.
- Optional components: `get_node_or_null("NodeName") as TypeName` stored in `@onready` var; all callers gate on `!= null`.
- Out-of-tree instances (build previews): `@onready` never resolves; use `get_node_or_null` inline instead of relying on `@onready` fields.

### Entity scenes are composed, never inherited

A piece is a root plus its components; a component with children or defaults is an instance of
a scene under `scenes/components/`. Two rules follow from Godot's instancing:

**Overriding a node INSIDE a component instance needs `[editable path="…"]`** in the piece's
file, or the editor drops the override on its next save. The importer writes it
(`TscnDoc.ensure_editable`).

**A node inside a component instance cannot be removed by the piece**, and a second declaration
of any node under one parent leaks and **segfaults the process during engine teardown**, long
after the code that caused it. `tests/test_EntitySceneHierarchy.gd` scans for both inheritance
and duplicate sibling declarations.

Verify a structural change by diffing INSTANTIATED layouts (`tools/scene_layout_dump.tscn`, with
`deep` for every stored property), never by reading files.
→ **[`gdd/systems/authoring/entity-scene-hierarchy.md`](gdd/systems/authoring/entity-scene-hierarchy.md)**

`MeshVisual.model_top_offset()` skips hidden meshes, so a mesh kept around but switched off
does not push the floating badges clear of a box nobody can see.

### A freed object cannot be passed to a typed parameter

Godot type-checks an Object argument against the parameter's declared class BEFORE the callee
runs, and a freed object fails that check — so an `is_instance_valid()` guard on the first line
of the callee is unreachable. The same applies to ASSIGNMENT: `var x: Fog = dict.get(k)` errors
outright if the stored value has been freed.

So the guard belongs at the CALL SITE, or the parameter/local must be untyped `Variant` and
validate before use — which is why `Fog.for_commander` reads its registry into a `Variant`.

Remember too that `freed_object == null` is TRUE while `is_instance_valid(freed_object)` is
false — so `!= null` is not a validity test, and a nullable field holding a freed reference
will silently take the "there is nothing here" branch.

### Component pattern for entity behavior

Behavior is composed by adding component nodes as children, not by subclassing. To check if an entity has a capability:
```gdscript
entity.has_node("Production")     # can train
entity.can_move()                 # can move at all, by any strategy
entity.movement != null           # has a live NAVIGATED locomotion (nav agent, modes)
entity.is_in_group("unit")        # unit-flavored (not "is Unit")
```

### Coordinate system

- Grid indices: `Vector2i(x, z)` — origin at top-left (min-x/min-z corner)
- World space: Y is terrain height; XZ is the horizontal plane
- `VU.inXZ(v3)` → `Vector2(v3.x, v3.z)`, `VU.fromXZ(v2)` → `Vector3(v2.x, 0, v2.y)`

### Utility aliases

- `VU` = `VectorUtils` — `inXZ`, `fromXZ`, `onXZ` for Vector3↔Vector2
- `AU` = `ArrayUtils` — sort/filter helpers
- `SU` = `SpaceUtils` — collision/placement helpers, `linf_distance`, `unit_is_close_to_structure`

### Structure placement flow

1. Player selects Build, picks tool → `command_message.tool` set
2. `RTSController._resolve_command_class()` returns `Build`
3. `Build.meets_precondition()` checks: resources, tech prereqs, `Structure.valid_placement(msg, dims)` (all cells in the `Structure.dimensions` footprint are in-bounds and unoccupied)
4. On right-click: `Build.fulfill_action()` → `map.add_entity()` → `map.add_structure()` → `TerrainGrid.place_building()` → `cells_changed` → `NavManager` rebuilds navmesh

### Terrain height snapping for units

Units snap to terrain Y every physics tick in two places:
1. `Commandable._on_velocity_computed()` — after `move_and_slide()`, snaps to `map.terrain_height_at(xz)`
2. `Commandable._physics_process()` — unconditional snap at the end of each tick

Velocity sent to `NavigationAgent3D` is XZ-only (Y zeroed) to keep RVO avoidance stable. Terrain tracking is handled separately.

---

## Regenerating data: write the PRIMARY, re-derive the rest, then prove it

**When a task modifies generated content, change the PRIMARY source and regenerate everything
derived from it. Never patch a derived artifact alone — and verify by re-deriving: if running
the generator again changes the result, the edit was in the wrong place.**

### The terrain pipeline, primary and derived

**TODO — one surface has two authored sources of truth, which is a design fault rather than an
invariant: one of the two should be derived.** Which one is undecided — see
[`gdd/deferred.md`](gdd/deferred.md) 1.19. Until then, the rules below are how to live with it.

A map's terrain is FOUR artifacts describing one surface. Which of them is primary depends on
how the map was authored, and that is the whole trap:

| artifact | what it is |
|---|---|
| `resources/terrain/<map>_surface.res` | the brushable grid `ArrayMesh` — one vertex per grid corner. `Map.terrain_source_mesh`, and what `TerrainSurface` DRAWS. |
| `TerrainData.heights` (in `<map>.tres`) | per-corner heights. What the game plays on. |
| `TerrainData.tile_types`, `void_cells` | per-cell ground materials, brush-painted and authored; and the cells with no ground, which are the bake's output. |
| `Map.height_map`, `blocked_mask()`, `cell_data_texture()`, the navmesh | strictly derived, rebuilt at load. Never edit these. |

The first two are **the same data in two representations**, and the arrows run BOTH ways:

- `Map.bake_terrain_from_mesh` → `TerrainData.bake_source_mesh` rasterizes the MESH into `heights`.
  Mesh is primary.
- The terrain brush writes `heights`, then `Map.sync_source_mesh_heights` pushes them back into
  the mesh's vertices. Heights are primary.

**`sync_source_mesh_heights` mutates the mesh IN MEMORY and never saves it.** The `.res` on disk
is written only by `Map.create_terrain_mesh` (which lays down a FLAT grid) or by an explicit
editor resource save. So a sculpted map can ship a `.tres` full of hills and a `_surface.res`
that is still flat — which is what `mesh_plateau_terrain_surface.res` is today. You do not see
it until someone presses **Bake Terrain From Mesh**, at which point the stale flat mesh
overwrites the good heights and the map goes flat. The mesh is not cosmetic: it is the other
half of the same fact.

### What to do instead

Write both, from one computation, in one pass, and then **re-derive and compare**:

```
godot --headless --path . -s res://tools/terrain/make_symmetric_terrain.gd
```

`tools/terrain/make_symmetric_terrain.gd` is the worked example. It symmetrizes the heights,
writes the surface mesh from them, bakes the mesh back into the resource, and refuses to report
success unless the bake reproduces what it wrote to the byte (`residual rebaked-vs-computed
0.000000000`). **A rebake being a NO-OP is the property that says the two artifacts agree.** Any terrain-generating tool should end with it.

Symmetry itself is verified separately and numerically by
`python3 tools/selfplay/results/verify_symmetry.py <scene.tscn> <terrain.tres>`.

---

## Things NOT to break

**An editor TRIGGER must never be serializable.** `Map`'s inspector buttons —
`create_terrain_mesh`, `bake_terrain_from_mesh`, `generate_visual_mesh`, `mirror_map`,
`shift_map` — are `@export var … : bool` whose setter does the work. Two things make that a
loaded gun: the inspector writes `false` back into a bool during its own construction and on
revert, and a value SAVED INTO A SCENE is assigned at load time — so a stored `true` fires the
trigger on every open of the scene, `--headless --import` included.

Three guards, and a new trigger needs all three: `Map.TRIGGER_PROPERTIES` lists them,
`_validate_property` strips `PROPERTY_USAGE_STORAGE` so they cannot be written into a scene,
and `_fire_trigger` refuses anything but a `true` tick arriving after `_ready` (`_triggers_armed`).
`create_terrain_mesh` also confirms first — it is the one editor action that destroys authored
work rather than deriving something.

**Derived terrain data**: `TerrainData.heights` and the map's `_surface.res` mesh are the same surface twice, and `Map.sync_source_mesh_heights` keeps them in step in MEMORY ONLY. Editing one without regenerating the other arms a landmine for whoever next presses Bake Terrain From Mesh — see §Regenerating data.

**Navmesh cell-exclusion approach**: `NavManager._build_chunk()` builds one quad per cell from `TerrainGrid.navigable_mask`, which starts from passability (`_cell_state == 0`: in bounds, no building, not steep, not blocked, not submerged). Do not replace this with Godot's geometry-bake path — it's too slow and doesn't encode terrain heights correctly.

**`Map.CELL_SIZE` const**: fog, NavManager, and coordinate helpers all derive from this. It's `1.0` and encoded as Map's scale. Don't add a separate `cell_size` export that could diverge.

**`get_node_or_null` for optional components**: the `@onready` optional-component pattern is intentional. Don't change optional components to hard `$` references without checking all call sites gate on null. See `gdd/systems/authoring/get-node-or-null-audit.md` for verdicts on each occurrence.

**`Commandable._process_commands()` routing**: structures intercept `Train`, and stationary `can_rally()` commandables intercept base `MoveCommand` (rally), here before they reach `CommandReceiver._process_commands()`. Calling `command_receiver._process_commands()` directly (bypassing `Commandable._process_commands()`) breaks structure training and rally points.

**Commander_id = 0 is neutral/world**: fog hides enemies (id != player_id), aggro checks gate on `commander_id > 0 and != self.commander_id`. Don't conflate "unowned" with "player-owned."

**Entity groups are for entities**: `Scenario._ready` iterates `get_nodes_in_group("piece")` with a typed `for entity: Entity in ...`, so a non-Entity node in that group raises a type error that ABORTS the rest of scenario boot — trigger wiring, the scenario HUD, camera framing — silently. `fog.gd` and `minimap.gd` do the same per frame. `colonial.tscn`'s Faction root shipped in an entity group and cost exactly that. **TODO: this is now UNGUARDED.** `tests/test_FactionRosters.gd` caught it and was cut as an authored-content test; if a guard is wanted back it has to be one that tests the RULE (a non-Entity in an entity group aborts boot) against a fixture, not one that inspects the shipped faction scenes.

**The CLEARED HP bar and selection shape in `scenes/components/`**: `hp_bar.tscn` deliberately
ships a transform with a ZERO origin and `selectable.tscn` a SelectionShape with no shape. That is
the "nobody has decided this" signal the importer bakes into (see Generated visual defaults) —
putting a real value back on the component makes every piece read as hand-authored, and
silently stops the pass writing anything ever again.

**`Commander.get_build_preview_instances`**: these out-of-tree entity instances must never be added to the SceneTree. They skip `_ready`, physics, and auto-init intentionally.

**`Entity._auto_initialize`**: scene-placed entities (not spawned by Scenario) call this deferred to find their `Map` and `Commander`. It then calls `map.add_structure()` with a centroid-offset correction. If you add new structures to the scene in the editor, they rely on this path.

---
