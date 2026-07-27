---
title: Conditions and regions
type: system-note
---

# Conditions and regions

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## A Condition outlives the session it ran in


A `Condition` is a **Resource**, and a sub-resource authored inside a `.tscn` is SHARED by every instantiation of that scene rather than copied into each one. Leaving a scenario and re-entering it from the menu (`SceneManager.go_to_packed`, the same `PackedScene` every time) therefore hands the new session the OLD session's condition objects, still holding the state they were left in. `ScenarioTriggerManager._reset_session_conditions()` runs `reset()` over every authored condition once at scenario start; without it three separate things go wrong, and all three are silent:

- **`ConditionTimer` counts from the wrong zero.** `_start_frame` is a frame number from a scenario whose clock has since restarted at 0, so a COUNTDOWN waits out the difference; `_target_frames` is the previous run's resolved interval, so an expression like `15 + randi_range(0, 10)` never re-rolls.
- **`ConditionEntityKilled` fires on the first tick.** It keeps a FREED reference to the entity it watched, which reads as "that entity is gone".
- **Any condition can fire its trigger on a stale `true`.** `_aggregate_met()` reads each condition's cached `_last` directly, so a trigger whose OTHER condition changes first sees residue rather than a fresh evaluation — the timer never gets counted at all.

`reset()` already exists as the per-fire hook a repeating trigger uses, and every stateful condition implements it, so the session pass is just "run it once more, at the start". It is deliberately **not** folded into `GlobalTrigger.arm()`: arm() also runs mid-session when an `EventChainTrigger` switches a trigger back on, and state accumulated up to that point (a `ConditionOccurrenceTally`'s running count) is meant to survive being re-armed. `ScenarioTactic.reset_conditions()` covers tactic rules the same way, and `SimulationScenario` resets its expectations' conditions before arming them.

The general rule this is an instance of: **a Resource is session-scoped only if something makes it so.** Anything authored as a sub-resource and mutated at runtime needs an explicit per-session clear — `PlayerSlot.commander` is the other one in this codebase (self-healing, because `Scenario._build_commanders` overwrites it). Tests: `tests/test_ConditionResidue.gd`, whose first case pins the engine behaviour the rest depends on.

## Regions are always shape NODES


Every spatial condition scopes itself through `RegionAwareCondition`: a `region_shape_path` NodePath, authored **relative to the owning trigger**, resolved to a live `CollisionShape3D` by `GlobalTrigger.arm()` (a `Condition` is a Resource, so it can't resolve a path itself). Don't add inline numeric geometry to a condition — `ConditionUnitsInRegion` used to carry world-space `rect_min`/`circle_center` exports and it was a trap: the numbers were invisible in the viewport and did NOT follow the trigger marker, so dragging the marker silently detached the region from it. A child shape node is visible, draggable, moves with its trigger, and is what `EventHighlight` paints.

`ConditionStructureBuilt.grid_cell` is the deliberate exception — it indexes `Map.cell_grid` directly, so a cell index is the right abstraction, not a shape.

**An unresolved region matches EVERYWHERE, it does not fail.** That is the silent misconfiguration this layer is most prone to, so `GlobalTrigger.arm()` calls `RegionAwareCondition.warn_about_missing_region()` and pushes a warning naming the trigger when (a) `region_shape_path` is set but doesn't resolve, or (b) the condition overrides `_region_is_required()` (i.e. `ConditionUnitsInRegion`) and no region is bound. An *optional* region left unset — `ConditionUnitCount` counting map-wide — is legitimate and stays quiet.

Prefer `ConditionUnitCount` (`AT_LEAST 1` + region) for "get a unit here". Reach for `ConditionUnitsInRegion` only when you need its `check` modes: `ALL_INSIDE`, or the falling edge `ANY_EXIT`. `ANY_INSIDE` on a one-shot trigger already means "when a unit first arrives", because `GlobalTrigger` fires on the rising edge of its aggregate.

`EventHighlight` has two lifetimes:
- **`follow_trigger_lifetime = true` (default)** — as a child of the trigger it describes. `GlobalTrigger.arm()` raises it, `fire()`/`disarm()` drops it, so an objective's marks are up exactly while that objective is live. `execute()` is deliberately INERT in this mode, because `fire()` runs every child event and a highlight turning ON at completion would be backwards.
- **`follow_trigger_lifetime = false`** — an ordinary fired event with a `target_trigger` and an `enable` flag, mirroring `EventChainTrigger`. Use it to mark a LATER objective from an earlier one's completion.

For things no condition can name — "train a unit from THAT barracks", where the check is a unit count and the thing to point at is a building — add `EntitySelector` children to the `EventHighlight`. Same pipeline `EventIssueCommand` uses, seeded with the `"piece"` group (not `"unit"`, precisely so structures can be marked), unioned with the condition-derived set.

`ScenarioHighlight` (`scripts/interface/scenario_highlight.gd`) is the painter: one `ImmediateMesh` under the Map, unshaded and depth-test-free like `WaypointIndicator`. It pulls its targets through a `Callable` on a ~0.2s cadence, so marks track a LIVE set, and drapes footprints over terrain by sampling `Map.terrain_height_at`.

## Resetting conditions between sessions

*Moved out of `scenario_trigger_manager.gd::_reset_session_conditions`.*

A Condition is a RESOURCE, and a sub-resource authored inside a .tscn is SHARED by every
instantiation of that scene rather than copied into each one. Leaving a scenario and
re-entering it from the menu therefore hands the new session the OLD session's condition
objects, still holding the state they were left in:
  * ConditionTimer keeps `_start_frame` (a frame number from a scenario whose clock has
    since restarted at 0) and the deadline it resolved, so the second run's timer counts
    from the wrong zero — the reported bug.
  * ConditionEntityKilled keeps a FREED reference to the entity it watched, which reads
    as "that entity is gone" and fires its trigger on the first tick of the new run.
  * Every condition keeps its cached `_last` truth, which the AND/OR aggregate reads
    directly (_aggregate_met), so a trigger can fire on a stale `true` in the window
    before the poller re-evaluates it.

reset() is the existing per-fire hook a repeating trigger already uses and every stateful
condition implements, so re-running it here is exactly "start with nothing carried over".

Deliberately NOT folded into GlobalTrigger.arm(): arm() also runs mid-session when an
EventChainTrigger switches a trigger back on, and state accumulated up to that point (a
ConditionOccurrenceTally's running count) is meant to survive being re-armed.
