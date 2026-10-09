---
title: Unresolved crashes
type: system-note
---

# Unresolved crashes

*Design note for [Dissent Horizon](../../../CLAUDE.md). A log of crashes and runtime errors
whose ROOT CAUSE is not yet known, kept so they can be revisited when they recur.*

An entry stays here while its cause is unknown, even after its symptom is patched: the patch
is often a guard at the point of failure, and the fault that reached it is still loose. Each
entry records when it was seen, the evidence, what was done, and where to start looking. When
a cause is found and fixed, the entry is deleted in that change (the fix and its reasoning
belong in the note that owns the mechanic).

## TODO: A freed fixture left in `Map.structure_cell_map`

**Seen:** 2026-10-06, in play (Alex), at 9:05 into a game. What was happening at the time is
not known.

```
E 0:09:05:871   Minimap._rebuild_layer: Trying to assign invalid previously freed instance.
  <GDScript Source>minimap.gd:405 @ Minimap._rebuild_layer()
  <Stack Trace> minimap.gd:405 @ _rebuild_layer()
                minimap.gd:257 @ _process()
```

**The symptom, fixed:** the minimap iterated `structure_cell_map` with a typed `Entity` loop
variable, and a freed key fails that assignment before the `is_instance_valid` check can run.
It now reads the map untyped (`Minimap.neutral_fixtures`, tested by
`tests/test_MinimapFixtures.gd`), as `LibertarianDominion._allied_fixture_cells` already did.

**The cause, open:** some fixture was FREED without `Map.remove_structure` being called, so its
entry outlived it. Death (`Entity._on_death`) and undeploying (`Entity.undeploy`) both remove
it; some other path — one of roughly 30 direct `queue_free` calls on pieces — does not. A stale
entry may also leave `cell_grid` and the terrain grid holding the dead piece, keeping its cells
blocked and its navmesh hole open; nobody has checked.

**Where to start:**
- Find the path: assert in `Map` (debug-only) that no key of `structure_cell_map` is freed, or
  log the id of each fixture that leaves the tree while still registered, and play until it fires.
- Or remove the class of bug: have `Map.add_structure` connect the fixture's `tree_exiting` (or
  its predelete) to `remove_structure`, so any departure releases the cells. Changes how Map and
  pieces interact, so it wants Alex's approval first.

## TODO: GUT shard crash with the 12:45 skirmish map

**Seen:** 2026-10-06, in the test suite. Roughly half of `gut_shards.py` runs lost one shard
(signal 11, bus error or SIGKILL) at a DIFFERENT test each time — memory corrupted earlier in
the process and tripped over later. Each file passed alone, and neither half of a crashing
batch crashed, so it needed a long run in one process.

**Bisected** (a detached worktree at HEAD, adding working-tree changes one group at a time,
several runs each): scripts, tests and resources ran clean; scenes crashed; narrowed to
`scenes/scenarios/skirmish.tscn` + `skirmish_map_terrain.tres` as saved at 12:45–12:46 that day
(230×230, play size 110×118). Alex's map at 17:10 ran clean four full suites in a row, so it is
not reproducing — but which property of that map triggered an engine-level fault is unknown.

**Where to start if it recurs:** the three tests that load the skirmish scene —
`test_DebugPlayerSwap`, `test_ScenarioEventHost`, `test_WaterPlacement` — each run after a long
prefix of other files, to find which one corrupts memory. Crash reports in
`~/Library/Logs/DiagnosticReports/Godot-*.ips` carry no symbols; the shard log's
`handle_crash` backtrace is the better lead. Whether it can happen in a game, not just in GUT,
is unknown.

## TODO: GUT shards crash at random tests, at HEAD too

**Seen:** 2026-10-08, in about half of `gut_shards.py` runs. One shard dies at a different test
each time (a fog test, a map-generation shelter test, …), sometimes with signal 11 (once with
the backtrace in MoltenVK's `SPIRVToMSLConverter::convert`, a shader compile under the headless
renderer) and sometimes with exit -9, a SIGKILL. Four runs at HEAD (f64d14b6) in a detached
worktree crashed all four times, so no working-tree change caused it. Every test that ran passed,
and each crashed file passes alone. No editor was open. The machine had about 2 GB free while
four Godot processes ran, so memory pressure is a suspect for the SIGKILLs at least.

**Where to start if it recurs:** run with fewer shards (does two crash?), and watch memory while
the suite runs. The shard log (`.godot/gut_shards/shard_N.log`) has the backtrace.

**Recurred 2026-10-08 (evening, spatial-model session):** six of eight full runs lost one shard,
each at a different test (`test_VisualOptOut`, `test_WeaponTurret`, `test_WorkDetail`,
`test_WeaponReachAcrossTheAirLine`, twice more), signal 11 with the same deep, repeating C++
backtrace; the last three with the Godot editor CLOSED, so an open editor is not the whole
story. Every file a shard lost passes alone (the one a shard died in, `test_DefendLeash`,
three runs of three). Reruns eventually report all four shards.
**A/B'd in place the same evening:** with the bot's new `fields` job stubbed out (the one
new per-tick job of that session), two of three runs still lost a shard; with it on, five of
six. The job is not the cause. The rate has risen from about half to most runs since the
morning; what changed in between is unknown.
