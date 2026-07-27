# Dissent Horizon

An isometric real-time strategy game — 3D world, 2D sprites, fog of war, a build/train economy
and an AI opponent.

This README is a map, not a manual: each section is a short orientation and a pointer to the
document that actually owns the subject.

## Getting started

It is a **[Godot](https://godotengine.org/) 4.7** project in GDScript. Download the engine from
**<https://godotengine.org/download>**, then point it at `project.godot` in the repository root
— there is no build script and nothing to install first.

New to Godot? Start with the engine's own
**[Step by step guide](https://docs.godotengine.org/en/stable/getting_started/step_by_step/index.html)**.
Scenes, nodes and signals are the three ideas the rest of this project assumes you have.

The main scene is `scenes/scenarios/s1.tscn`; `scenes/scenarios/skirmish.tscn` is the
bot-versus-bot map most development happens against.

## Game pieces are specced in YAML

**Every game piece — unit, structure, projectile, status effect, faction — is defined by a
markdown document in `gdd/`, not in the editor.** The document's YAML frontmatter is the spec,
and the importer applies it to the Godot project:

```yaml
---
kind: unit
title: Recruit
scene: res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn
defense:
  hp: 120
  armour: LIGHT
  frame: BIO
---
```

Two rules carry most of the weight: **a file is a spec if and only if its frontmatter names a
`kind`**, and **the file name is the piece's id** (`cl_bioLight_antiLight.md` is the piece
`cl_bioLight_antiLight`). Folder location is purely organisational. Hand-written code refers to
pieces through the generated `EntityIds` constants, never raw strings.

The importer rewrites scenes and regenerates `scripts/generated/` and `resources/generated/`,
so **run it only when your change is doc-facing** — a piece added, renamed or re-statted, or the
schema itself. It is not part of the test loop.

→ **[`tools/spec_import/README.md`](tools/spec_import/README.md)** — running it, the schema,
validation rules
→ **[`gdd/systems/authoring/spec-importer.md`](gdd/systems/authoring/spec-importer.md)** — why
the pipeline is shaped this way, and what stays editor work

## Maps are authored in the editor

Terrain is a single `TerrainData` resource holding per-corner heights and a per-cell tile-type
layer, painted and sculpted in-editor with the `terrain_brush` plugin. Passability, the navmesh
and the fog grid are all **derived** from it at load — never edited directly.

Two things are worth knowing before you touch a map:

- **A map's heights and its surface mesh are the same surface in two representations**, and
  editing one without regenerating the other is how a map silently goes flat. There is a
  procedure, and a check that proves it worked.
- **Water is a level and a seed cell**; everything else about a body — which cells it covers,
  how deep each is, what leaves the navmesh — is derived from those two numbers.

→ **[`gdd/systems/terrain-and-navigation/terrain-authoring.md`](gdd/systems/terrain-and-navigation/terrain-authoring.md)**
— the brush, the tile-type palette, the authoring loop
→ **[`gdd/systems/terrain-and-navigation/water-bodies.md`](gdd/systems/terrain-and-navigation/water-bodies.md)**
— ponds, depth, and what may be built in water
→ **[`CLAUDE.md`](CLAUDE.md)** §Regenerating data — the primary/derived rule and the check that
enforces it. Read this one before regenerating anything.

## Testing

Three kinds of test, deliberately kept apart because they answer different questions and a red
result means something different in each.

### Unit and regression tests — is the software correct?

[GUT](https://github.com/bitwes/Gut), in `tests/`. This is the gate: its answer must not move
unless something broke. A "regression test" here just means one that needs a live scenario
rather than a bare object — it still belongs in this suite.

```bash
# one file
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Movement.gd -gexit

# the whole directory
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

`-gexit` is required — without it the run finishes and then waits forever for a window that
`--headless` never created. The whole-directory run is currently unreliable and can die before
printing totals; looping over the files individually is the dependable way to get counts.

### Simulation tests — is the game balanced and behaving as designed?

Authored as YAML specs in `sims/`, run by their own tool. **These never run in GUT**, because a
balance answer is allowed to change when a stat changes and a gate that goes red for that stops
being trusted.

```bash
# every spec once
godot --headless --path . --fixed-fps 30 tools/simulation/run_sims.tscn

# one spec, ten seeds, JSON out
godot --headless --path . --fixed-fps 30 tools/simulation/run_sims.tscn -- \
    spec=duel_builder_mirror trials=10 seed=1 out=/tmp/sims.json

# watch one play out: drop --headless AND --fixed-fps
godot --path . tools/simulation/run_sims.tscn -- spec=antimech_vs_truck hold=5
```

An expectation coming out false is a **finding**, not a failure — the runner exits non-zero only
when a spec cannot be parsed or built.

→ **[`gdd/systems/scenario-scripting/simulation-tests.md`](gdd/systems/scenario-scripting/simulation-tests.md)**
— the grammar, the runner, and the reasoning behind the split

### Linting

```bash
./tools/lint.sh
```

`gdlint` plus a hand-rolled indentation check. The tree is **tab**-indented; the extra check
exists because Godot can silently reindent files it merely has open, which `gdlint` cannot
detect on its own.

→ **[`gdd/systems/authoring/linting.md`](gdd/systems/authoring/linting.md)**

## Bots: initialising them, and "training" them

**A bot has no learned model.** It is a set of hand-written decision modules — economy,
production, military, scouting, targeting — driven by a flat bag of numbers, `BotDifficulty`.
"Training" here means **searching those numbers by adversarial self-play**, not fitting weights.
Nothing in the repository loads or produces a neural network.

### Initialising a bot

A bot is initialised from its slot's difficulty tier and nothing else:

```
PlayerSlot.difficulty  →  BotDifficulty.for_tier()  →  BotBrain  →  the manager modules
```

`BotDifficulty` is deliberately flat — plain `int` / `float` / `bool` fields, no arrays or
resources — because that is what lets a whole configuration be a JSON object a search can write.
The tier values are hand-made placeholders; the *knobs* and the *direction* each one means are
the settled part, and a tier that inverted one would be a bug (`tests/test_ScenarioPlayerSlots.gd`
pins the ramp).

Two traps worth knowing before you put a bot in a scenario:

- **`PASSIVE` does not mean inert.** It means "minimally active, and never attacks" — a passive
  bot still builds, trains, defends itself and re-tasks its idle units. `BotBrain.active = false`
  is the only thing that genuinely freezes a commander.
- Several fields carry **sentinels** rather than being continuous (`-1` meaning "uncapped" or
  "never"). Read them through the named helpers, not as raw numbers.

### Running a training campaign

Self-play runs headless, two bots, one map, one seed per match, JSON out:

```bash
# one match
godot --headless --path . --fixed-fps 30 tools/selfplay/run_match.tscn -- \
    config=/abs/path/match.json out=/abs/path/result.json

# a batch (see tools/selfplay/example_batch.json for the config shape)
GODOT=/path/to/godot python3 tools/selfplay/run_batch.py matches.json \
    --out results.jsonl --jobs 2
```

**`--fixed-fps 30` is not optional** — without it Godot paces physics to the wall clock and a
20-minute match takes 20 minutes. With it, a `--jobs 2` batch gets through roughly one match per
105 wall-seconds, so **a 200-match sweep is about six hours**. Budget accordingly.

A run never edits the shipped difficulty tiers: a tier is the starting point, and the config's
`config` block overrides fields on the live object afterwards.

### What the search can and cannot do today

Stated here because it changes what a campaign is worth running for, and both results are
measured rather than suspected:

- **The parameter space is largely flat.** Of 29 one-at-a-time perturbations from MEDIUM, eight
  changed the simulation not at all (bit-identical digests) and eleven more moved it less than
  the harness's own run-to-run noise. Every finite-difference slope had a confidence interval
  spanning zero. Gradient descent over these parameters is not yet meaningful, and sample size
  is not the reason.
- **The harness is not reproducible.** The same config and seed can take different trajectories
  across processes. Determinism is a deferred question, not a flag to flip — so read a campaign
  as a distribution, never as a single trial.

→ **[`gdd/systems/ai/selfplay-harness.md`](gdd/systems/ai/selfplay-harness.md)** — input/output
schemas, termination rules, throughput figures, known limits
→ **[`gdd/systems/ai/bot-parameter-space.md`](gdd/systems/ai/bot-parameter-space.md)** — every
knob, its range, and which ones are coupled
→ **[`gdd/systems/ai/bot-architecture.md`](gdd/systems/ai/bot-architecture.md)** — what the
modules actually decide
→ **[`gdd/systems/ai/bot-roadmap.md`](gdd/systems/ai/bot-roadmap.md)** — the gaps in the decision
surface, and what a training harness needs next
→ `gdd/systems/ai/selfplay-results-*.md` — write-ups of campaigns already run

## Where the design lives

Mechanics are written up as rules, with their reasoning, under **[`gdd/systems/`](gdd/systems/)**
— one folder per system, each with a `README.md` stating its scope. Start at
[`gdd/systems/README.md`](gdd/systems/README.md).

[`CLAUDE.md`](CLAUDE.md) carries the project-wide invariants: terminology, the command
lifecycle, conventions, and a list of things not to break.
[`gdd/deferred.md`](gdd/deferred.md) indexes the open decisions and the plans not yet built.
