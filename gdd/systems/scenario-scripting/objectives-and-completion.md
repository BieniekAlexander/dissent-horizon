---
title: Objectives and completion
type: system-note
---

# Objectives and completion

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Objectives are a SCOPE on `GlobalTrigger`, not a subclass


Any trigger can be player-facing: `@export var scope: ObjectiveScope` (`NONE` by default) plus a `description`. There is no `Objective` class — it existed briefly and was folded into the base, because once the field lives on `GlobalTrigger` a subclass adds nothing but a second, competing `description` field. Most triggers are machinery (spawn waves, ambushes, chaining) and must stay out of the checklist, which is why the default is `NONE`.

**`scope` is a DISPLAY decision.** Nothing in arming, firing, chaining or prerequisites reads it; win/lose is still authored with `prerequisites` + `EventWinLose`. Its one non-visual consumer is `all_objectives_complete()`, below.

| Scope | Colour | Row | Struck when fired |
| --- | --- | --- | --- |
| `NONE` | — | not shown at all | — |
| `PRIMARY` | green | checkbox | yes |
| `SECONDARY` | amber | checkbox | yes |
| `FAILURE` | red | **bullet** | **no** |

A `FAILURE` gets a bullet rather than a checkbox because it is a way to LOSE, not a task: a box would invite the player to read it as something to go and do, and a fired failure ends the scenario anyway, so it has no "done" reading worth showing. Colour comes from the scope and the strike comes from the state — the two are independent, so a completed `PRIMARY` is a struck-through *green* line, not a differently-coloured one.

**State is derived, never stored** — `GlobalTrigger.objective_state()`:

| State | Condition | Shown as |
| --- | --- | --- |
| `PENDING` | `not enabled and not has_fired` | hidden (an unrevealed step would spoil what's coming) |
| `ACTIVE` | `enabled and not has_fired` | unchecked |
| `COMPLETE` | `has_fired` | struck through |

`has_fired` exists because `enabled` alone can't separate PENDING from COMPLETE (a one-shot disables itself on firing). `has_fired` wins over `enabled` so a REPEATING objective ticks off on its first completion instead of sitting unchecked forever. There is no fallback for a blank `description` — the trigger's inspector name is not player-facing copy, and a row that quietly showed it would ship a node name to the player.

Transitions announce themselves via `objective_state_changed`, emitted from the three places that can move the state: `arm()`, `disarm()`, `fire()`. Nothing polls.

## Scenario completion


`ScenarioTriggerManager.all_objectives_complete()` is true once every **PRIMARY** trigger has fired (`GlobalTrigger.counts_toward_completion()`); the manager emits `scenario_completed` once (latched by `_completion_announced`). **A scenario with zero primary objectives is never complete** — vacuous truth would finish every plain skirmish on frame one.

`SECONDARY` and `FAILURE` are excluded, and not arbitrarily: a secondary is optional by definition, and requiring a failure condition would mean the scenario could only be won by losing.

`Scenario._on_scenario_completed` routes into `_on_game_over(true)`, and `Scenario._game_over_seen` latches so whichever verdict lands first stands: a scenario can also carry an authored `EventWinLose` (s1's `Victory` trigger does), and objectives completing moments after a scripted loss must not overwrite the loss with a win.

## Win conditions

**`Scenario.win_condition` says how a scenario ends**, as an enum export on the root
(decided 2026-10-03):

| Value | What ends the match |
|---|---|
| `NONE` | nothing implicit; it runs until something external stops it (a probe, a sim) |
| `MISSION` | the authored triggers — `EventWinLose`, objectives completing — plus the implicit wipe-out loss below for the local player. The default, so an authored scenario keeps the behaviour it was written against |
| `HEGEMONY` | a commander is **removed from the match** when it has no command centre left, once it has placed one; the local player's ALLIANCE loses when every member is removed, and wins when it is armed and every rival alliance is removed. Every skirmish scene sets it |

**HEGEMONY, the rules.** Every non-neutral commander is judged each tick
(`Scenario._check_hegemony`), not only the local player, because a rival's removal is what
the player's win is made of. A commander is ARMED the first tick it owns a command centre in
play — a blueprint is a plan, not a centre — and never before: every slot deploys by drop and
owns no centre for the opening seconds, and that is the opening, not a defeat. Removal frees
every piece the commander still owns (`Commander.eliminate`) and switches its brain off;
nothing is paid out for them. A command centre is identified by piece id,
`Deployment.command_centre_ids()`, derived from the scenes each faction drops — so a new
faction's entry there is the whole declaration. A session with no rival never wins.

**Removal is per player; the verdict is per alliance** (Alex, 2026-10-08). In a team game a
player who loses every centre is removed alone, and only under HEGEMONY. The local player
loses when every member of its alliance is removed — until then it keeps watching through its
allies' shared vision — and wins when any member is armed and every commander outside the
alliance is removed; a teammate is never a rival. The end-of-match summary marks the whole
winning alliance (`MatchLog.end`'s `winners`), and a spectator session ends once commanders of
two or more alliances have deployed and only one alliance is left standing.
[combat/target-acquisition](../combat/target-acquisition.md) §Alliances. The
self-play harness reads the verdict off `Commander.is_eliminated` under HEGEMONY and keeps
its own MISSION-era adjudication otherwise.

**What it asks of the content.** Under HEGEMONY the bot's attack objective is a believed
enemy command centre and its own is its first defensive priority
([ai/bot-architecture](../ai/bot-architecture.md) §The attack objective is a belief). WHEN it
goes is still the commit gates' decision, so the intended tuning is that a centre's health and
cost make an early beeline a premature commitment — the defender's army kills the attacker's
before the centre falls — and the bot refuses the wave; a centre not tuned that way is one the
bot will simply snipe, which is the readout that the tuning is off.

**HEGEMONY opens by showing every shelter** (Alex, 2026-10-05). At boot every player commander
gets vision of radius `Scenario.SHELTER_REVEAL_RADIUS` (6) around every shelter for
`SHELTER_REVEAL_SECONDS` (5), then the fog closes; what remains is each shelter's fog-of-war
snapshot, so its position stays known and its state does not
([terrain-and-navigation/map-generation](../terrain-and-navigation/map-generation.md) §Shelters).
The vision sources are `EventRevealRegion.spawn_vision` Scouts, the same ones an authored reveal
uses. Other win conditions reveal nothing: a mission decides what its player knows.

TODO — the BOT does not need this reveal and does not use it. Its shelter knowledge is omniscient
today: `Bot.get_neutral_terrestrials` lists every neutral Terrestrial on the map, fog or not, so
liberation and capture errands are found without scouting. Making that fog-limited — remembering
shelters the bot has seen, which the reveal would then supply — is a separate change.

TODO — whether `MISSION` should keep the implicit wipe-out loss, or leave every verdict to the
authored triggers as the spec read literally. Built as KEEP, since every shipped mission was
written against it; see `gdd/tasks.md` T-082.

## The MISSION loss is implicit, and lives on `Scenario`


Under `MISSION`, owning no units and no structures is a defeat, with **no trigger to author and no row in the checklist** — `Scenario._check_player_eliminated()`, polled from `_physics_process`. Deliberately not a `FAILURE`-scoped `GlobalTrigger`: it applies to plain skirmishes as much as to missions, it needs no authoring, and telling the player "don't lose everything" is noise. It routes through `_on_game_over(false)`, so it composes with authored verdicts under the same first-one-wins latch.

It lives on `Scenario` rather than `ScenarioTriggerManager` because `Scenario` already owns the verdict and the commander list, and because everything in the manager is a node someone placed and can reach through `global_triggers`.

**Polled, not driven off the `ON_DEATH` bus**, and that's not laziness — the bus is the wrong signal twice over. `Entity._on_death` runs *before* its `queue_free()` takes effect, so a count taken there is off by one; and a commander can lose its last entity with no death at all (a capture puts a unit into an enemy garrison, and `Garrison` orphans occupants out of the tree). The poll is one filtered `get_children()` on a single commander and stops once a verdict lands.

**`_player_has_deployed` arms it, and is load-bearing.** `Skirmish._spawn_initial_entities` defers the opening force to `NavManager.navmesh_ready`, so every commander genuinely owns nothing for the first frames of a match — an unarmed check loses the game before it starts. Arming also makes the rule self-disabling exactly where it should be: a spectator session, or a scripted scenario whose player is handed their first unit by a trigger, simply never arms it, so no opt-out export is needed.

What `Commander.has_anything_in_play()` counts is three exclusions:

| Not counted | Why |
| --- | --- |
| `is_queued_for_deletion()` nodes | `queue_free()` is end-of-frame; without this the check resolves a frame late (same reason `ConditionGroupCount` skips them) |
| Blueprints (`Entity.is_planned`) | a plan needs a builder, and a commander with a builder has a unit — counting one means "you are alive because you have a plan" |
| non-`Actor` entities | a `Scout` (`EventRevealRegion` with `clears_fog`, `EventRadarScan`) is an `Entity` parented to the commander; widening this to `Entity` would let a permanent reveal make its owner immortal |

Garrisoned units don't count either, and that falls out of the mechanic rather than a rule here: `Garrison` holds occupants as orphaned nodes, so a unit in an enemy Compound has left its commander's subtree. **Being reduced to POWs is being eliminated** — they aren't yours to command until something frees them.

Only the local human is checked (`Scenario.local_player()`, null in a spectator session). A bot being wiped out is deliberately NOT an automatic win — with multiple bots or a neutral-heavy map, "the last enemy died" isn't obviously one. Tests: `tests/test_Elimination.gd`.

## `ObjectiveChain` sequences; the scope decides visibility


`ObjectiveChain` is a `Node` child of the `ScenarioTriggerManager` whose `GlobalTrigger` children run **one at a time in scene-tree order**. It is pure sugar over `prerequisites`: in its own `_ready` (children ready before parents, so the manager's later collection, cycle check and arming all see them) it APPENDS an edge from each step to its predecessor — appends, not assigns, so a step may also depend on something outside the chain. Advancing is then the manager's ordinary DAG walk, not chain-specific code; the chain only announces `chain_completed`. The manager collects a chain's `steps` into `global_triggers`, so they arm exactly like hand-authored triggers and appear in the checklist inline at the chain's position.

Chaining and being player-facing are **orthogonal**: a chain step left at `ObjectiveScope.NONE` still sequences, it just isn't shown. Declaring `prerequisites` by hand is the way to express branching, joins and fan-out — a chain deliberately only does the linear case.

`ObjectiveView` renders the checklist from `manager.visible_objective_triggers()`, repainting off `objectives_changed`. `rows()` is its testable plain-text view of itself.

**Ordering is the manager's, not the view's.** `visible_objective_triggers()` groups by `SCOPE_DISPLAY_ORDER` — FAILURE, then PRIMARY, then SECONDARY — and keeps scene-tree order *within* each group (so chain steps still read in authored sequence). It lives there so the view's two readers (`rows()` and `refresh()`) can't disagree, and so a test can assert the order without instantiating a HUD. Failure conditions go first deliberately: one the player scrolls past is one they don't know about.

Unlike the rest of this game's HUD it is an **authored scene** — `scenes/interface/objective_view.tscn`, instanced into `scenes/player.tscn` under `Controller` — so it can be positioned and restyled in the editor. The script only decides which rows exist; it looks everything up by scene-unique name (`%Panel`, `%Rows`, `%Title`), so the tree inside can be rearranged freely. Rows are duplicated from a hidden `%RowTemplate` rather than built in code, which makes restyling a row an edit to one node instead of to a function; it's a `RichTextLabel` so a completed line gets a real `[s]` strikethrough.

`Scenario` finds it by group (`ObjectiveView.GROUP`) and binds it, rather than creating it — so a session with no player rig has no checklist, which is right, since nobody is reading it. Contrast `ScenarioDialogView`, which Scenario still CREATES: a spectator or headless test scenario has no HUD but can still raise scripted dialogs, so that one can't depend on the rig existing.

## What counts as still being in play

*Moved out of `commander.gd::has_anything_in_play`.*

* Nodes already queued for deletion. Entity._on_death calls queue_free(), which is
   end-of-frame, so a commander whose last unit just died is still its parent for the
   rest of this frame. Without this the check resolves a frame late — the same reason
   ConditionGroupCount skips them.
 * Blueprints (Entity.is_planned). A planned structure needs a builder to become real,
   and a commander with a builder still has a unit; counting one would mean "you are
   alive because you have a plan".
 * Non-Actor entities. Actor, not Entity, and that is load-bearing: a Scout
   (EventRevealRegion with clears_fog, EventRadarScan) is an Entity parented here, so
   widening this would let a permanent reveal keep a wiped-out commander alive forever.

Note that garrisoned units do not count either, and that follows from the mechanic rather
than from a rule here: Garrison holds occupants as ORPHANED nodes, so a unit inside an
enemy Compound has left this commander's subtree. Being reduced to POWs is being
eliminated — they are not yours to command until something frees them.
