---
title: Debug tuning
type: system-note
---

# Debug tuning

Tuning a piece while the game runs, and saving the result to its spec doc. A developer
surface under [debug-mode](debug-mode.md): it exists only while `DebugMode.is_active()`.

## The doc stays primary; the game becomes a second editor of it

**A spec doc's frontmatter is still the one source of truth for a piece's numbers.** What
changed (2026-10-04) is who may write it: until now only a person editing text did, and the
importer carried the result into scenes one way. The tuning editor is a second writer of the
same doc, the way the terrain brush is a second writer of `TerrainData.heights`. It edits the
doc's values in memory, previews them on the live pieces, and on Save writes them back into the
frontmatter. **The importer is then run as before**, and is what carries the values into scenes
and generated data. Nothing here writes a scene.

Superseded: "the docs govern numeric data one-way" (spec-importer §`Tool` wiring). Rejected
alternatives, both because they make a derived artifact primary:

- REJECTED: Save patches scenes directly and the importer stops governing tuning numbers — two
  writers of the scene, and the calibration rules would no longer see the numbers.
- REJECTED: scenes primary for tuning numbers, docs regenerated from them — the doc's comments,
  ordering and waivers would not survive a regeneration.

## What can be tuned

**Libraries** — a value many pieces NAME. Editing the entry retunes every piece naming it.

- The speed ladder (`kind: SpeedLibrary`). The ladder stays strictly increasing: an edit that
  would break it is refused in the field, as the importer would refuse the doc.
- The shape library (`kind: ShapeLibrary`): each bucket's radius.

**A piece** — the fields of its own doc:

- `defense`, `senses`, `body`, `movement` (not the mode), `aerial.orbit_*`, `garrison`
  (not its `pieces:` / `reach_by_piece:` lists), the ability pools' charges and cooldowns.
- Every weapon, and the projectile each fires, reached through the weapon: its payload, the
  status effects it applies, and the whole phase list — adding, removing, reordering and renaming
  phases included. A phase's `speed` and `coast_speed` name speed classes, as the importer
  requires.

TODO: which emission a weapon fires (`emits:` as a reference) is not editable — the phase list
inside an emission is, but swapping the emission itself is not built.

TODO: a phase's own `emits:` (a second emission it launches on a cadence) is neither shown nor
editable; no doc uses one yet.

TODO: the damage-multiplier table (`resources/damage/damage_vs_armour.tsv`,
`damage_vs_frame.tsv`) is shown in the verbose weapon popup but is not tunable. It is a library
in every sense above, and authored as TSV rather than as a doc; whether it should be tunable
here, and so whether Save should write TSV, is undecided.

**Not tuned here:** what a piece trains, builds, researches or requires, its cost and build
time, its mode, deploy keys, root properties (`infrastructure`, `occupancy_size`, `footprint`,
`beacon`), presence keys, copy and HUD placement; ability, status-effect and upgrade docs;
tuning that has no doc key (`Repairs.repair_rate`, the generator rates, the dive settings).

A value that names a library entry is edited AS THE NAME: a piece's speed is SLOW, never 1.65.
That a unit is SLOW is a fact only its doc records — the importer resolves the name to a number
before anything reaches a scene — so **the editor reads the docs at runtime** and the game's
live values are never the source of what it shows.

## An edit is to the piece TYPE

An edit reaches every live piece with that id, whoever owns it, and every one spawned after it
for the rest of the session. A library edit reaches every piece naming the entry. Nothing is
per-instance.

- **A maximum keeps the fraction.** Raising `hp` from 100 to 150 takes a unit at 50 to 75; the
  same holds for anything with a current value under a cap. A speed held down by a slow keeps
  its slow: the new speed is scaled by what the live one was to the old.
- **`body.radius` and `body.hurtbox` are saved, never applied live.** The radius decides a
  unit's navigation size class; the field says that nothing changes until a re-import and
  restart.
- **The simulation keeps running while a field is edited**, so a change to acceleration can be
  watched. Typing into a field never reaches the game's input actions.
- **An emission is retuned as it is fired**, status effects included (instanced from the scene
  each status-effect doc names), not in flight: one already in the air finishes as
  it was launched. An emission whose phase list the importer would refuse is not previewed;
  pieces keep firing its last valid form, and the popup lists what is wrong.
- **The bot is not told.** What it computed from the generated data stays as it was until a
  re-import and restart.

## Where the editor is

**On a piece: its HUD readout.** In debug mode the readout's widgets and popups
([piece-readouts](piece-readouts.md)) are the same nodes, with their values made editable.
Clicking a widget toggles its popup; clicking outside closes it. Holding `ui_verbose` shows the
deeper fields, in debug as outside it — and is never typed into a field. While a field naming a
shape has focus, that shape is drawn on the selected piece as Godot's own collision outline
(the range rings players see on the terrain are a different, derived drawing). A range cylinder
is drawn two units tall rather than its full height: range volumes are far taller than the
world on purpose, so at full height the rims would be off-screen and only the radius matters.

**For libraries and saving: the top-left debug menu**, which takes the resource bars' place for
as long as debug mode is on. A debug session has already broken the match's economy, so the
bars have nothing to say there.

## Saving

**Save writes every edited doc**, changing only the lines whose values changed. A doc keeps its
comments, its flow maps and its order; a key it did not have is added and the canonical order
(`SpecSchema.reorder_frontmatter`) places it. A rewritten PHASE LIST is the exception: it is
written fresh, and comments inside it are lost.

**Then the docs are validated** — the importer's own scan, which writes nothing. A piece whose
doc fails is restored to what it was before the save, and the menu shows the importer's
message. For a calibration rule, the menu offers a box for a reason: given one, the save
writes it as that rule's waiver under `exceptions:` and validates again.

**It does not import.** Run the importer afterwards; until then the scenes still hold the old
numbers, and a restart loses the live preview.
