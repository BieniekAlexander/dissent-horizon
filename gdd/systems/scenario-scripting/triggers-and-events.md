---
title: Triggers and events
type: system-note
---

# Triggers and events

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*


The tutorial/mission layer. All of it is built ON the trigger system rather than beside it — an objective IS a `GlobalTrigger`, so AND/OR composition, region scoping and chaining come for free. Reference scenario: `scenes/scenarios/tutorial.tscn` (four steps: select a unit → move to a region → move to a second region → clear an area). Its contents are authored, so nothing unit-tests them.

## The three ways an event runs


An `AbstractEvent` never runs itself; something has to call it, and **where you park the event node is what decides which of the three does**:

| Authoring | Runs when | Driver |
| --- | --- | --- |
| Child of a `GlobalTrigger` (under the `ScenarioTriggerManager`) | its conditions become satisfied — immediately, if it declares none | `GlobalTrigger.fire()` |
| Child of an `EntityTrigger` (under an entity's `#####TRIGGERS#####`) | that `occurrence` fires on the owning entity | `EntityTrigger.fire()` |
| **Direct child of a commandable** in the scenario scene | once, at scenario start | `ScenarioTriggerManager.run_starting_events()` |

The third is for state that simply IS so from the first frame — no condition, no lifecycle moment. The motivating case is a **starting garrison load**: drop an `EventSpawnEntities` under a Compound or a stock truck, point `garrison_host` at the host (`".."`), and its units are inside before the player's first order (see §Garrison occupancy). It runs after the navmesh's first sync (same gate the triggers wait on) and after editor-placed entities have auto-initialized, so each host already has its map and commander.

Only entities in the `"piece"` group are scanned, since a starting event belongs to a piece, and that loop is deliberately UNTYPED so a stray non-Entity node in the group is skipped rather than aborting scenario boot (see CLAUDE.md §Entity groups are for entities).

An event parked anywhere else — under a plain `Node`, under a non-commandable entity — has no driver and **silently never runs**. That is the failure mode this table exists to prevent.

## A trigger with no conditions fires immediately


**Leaving `conditions` empty is how you say "unconditionally, at the start of the scenario"** — an opening defensive garrison, a wave that is simply there on frame one. It is the first row of the table above with nothing to wait for, so the events stay where events live and nothing else about authoring changes. Prefer it to a `ConditionTimer` with a zero interval, which says the same thing less directly (s1/s2/s3 pre-date this and still use that form).

The alternative — never firing — was strictly worse: a trigger that can never fire is one that might as well not exist, and it fails **silently**, the same way a mis-parked event does.

Two mechanics make it work, and both are easy to get wrong if this is ever rewritten:

- **It needs a driver.** `fire()` is only ever reached from a `Condition`'s `state_changed`, so a truthy aggregate over an empty set would never be consulted. `GlobalTrigger._watched()` supplies a `ConditionAlways` stand-in instead, which registers with the `ConditionPoller` like any pull condition and reports its rising edge on the **first physics frame after arming**. That timing matters: firing inline from `arm()` would run during `ScenarioTriggerManager._ready`, which is *before* `Scenario._ready` builds `commanders`, and `EventSpawnEntities` would find no commander and skip.
- **It is always one-shot**, whatever `one_shot` says (`is_unconditional()` in `fire()`). Honouring a `false` would re-fire it every other frame forever, since `reset()` makes the stand-in true again — a runaway for a spawn event. Nothing is lost: an `EventChainTrigger` re-arming it fires it again, which is the on-demand case that flag would have served. Authoring `one_shot = false` with no conditions is a Scene-dock warning rather than a silent override.

`_watched()` also drops blank rows, as `prerequisites_satisfied()` does, since an Array export grows an empty row whenever you extend it. The corollary is worth knowing: **a trigger whose only condition row is blank counts as unconditional and fires at once**, so a half-authored trigger runs its payload rather than stalling.

## Dependencies are declared on the DEPENDENT (`prerequisites`)


`GlobalTrigger.prerequisites: Array[GlobalTrigger]` + `prerequisite_mode` (`ALL_OF` default, `ANY_OF`) is the objective DAG. A trigger arms once its prerequisites have fired; `ScenarioTriggerManager._arm_satisfied_triggers` is connected to every trigger's `fired` and walks the graph forward.

Declared on the dependent rather than pushed by the predecessor **on purpose**: adding a step means pointing the new node at what it waits for, instead of remembering to add an `EventChainTrigger` child to everything upstream. A forgotten edge is then a visibly empty field on the thing that doesn't run, rather than a missing child node elsewhere in the tree — which is exactly how `s1`'s chain silently broke before this existed.

Edges are shared node references; Godot serializes them as node paths and re-resolves on instantiate, so joins and fan-outs survive the round trip. `SanctionUnlock` used to share this any-of `prerequisites` idiom and deliberately no longer does — see §The sanction grid for why a sanction's one dependency is a single `parent` instead.

**One gate.** A trigger is in the opening round unless something it depends on hasn't happened yet. There is no separate `starts_disabled` flag — it was removed once prerequisites existed, because "starts switched off" and "waiting for X" were the same state expressed two ways, and only one of them records *why*.

`EventChainTrigger` remains for imperative flips a dependency edge can't express: arming a trigger whose prerequisites are unmet, disabling a running one, re-enabling a repeating one. Those override the declarative gate deliberately — vetoing them would make the two mechanisms fight.

`_arm_satisfied_triggers` only considers triggers that actually **declare** prerequisites, and that guard is load-bearing: an ungated trigger switched OFF by an `EventChainTrigger` has nothing outstanding, so without it the next fire anywhere in the scenario would silently switch it back on.

`_report_prerequisite_cycles` runs at `_ready` (three-state DFS) and names the loop. A cycle isn't a crash, it's a silence — every trigger in it waits on another, so none arms and the mission stops with nothing in the log.

## Groups label a WAVE (`ConditionGroupCount` + `spawn_groups`)


The count conditions select by what a thing IS — a commander's units, a structure type. `ConditionGroupCount` selects by what an author LABELLED, which is how a check names one specific wave. "The units commander 2 owns" is a type the engine already knows; "the three irregulars this ambush dropped" is not, and without a label a later check can only approximate it.

`EventSpawnEntities.spawn_groups: Array[StringName]` stamps groups onto everything one event spawns, applied in `_instantiate_all` before any routing so it lands on commandables, plain Entities and bare VFX nodes alike (and before they enter the tree). `ConditionGroupCount` reads it back. Blank rows are skipped — an Array export grows with an empty row, and joining the `""` group would pollute every check that forgets to name its own.

It counts **Nodes**, not Entities, since a group may hold anything; `highlight_entities` narrows to Entity, because only those have a position to mark. Two behaviours worth knowing:
- An **unset `group` never matches**, including `AT_MOST`. Counting zero would make an un-authored check fire on the first tick, which is worse than one that never fires.
- Nodes **already queued for deletion don't count**. `get_nodes_in_group` still returns a `queue_free`d node until the end of the frame, so a "wipe out the wave" check would otherwise resolve a tick late.

Note that `AT_MOST 0` is true *before the wave exists*, so a "clear the ambush" objective must be gated behind the spawning trigger — `prerequisites` is exactly that.
