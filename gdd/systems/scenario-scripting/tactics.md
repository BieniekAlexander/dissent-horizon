---
title: Tactics
type: system-note
---

# Tactics

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Tactics: ongoing behaviour for one cluster (`ScenarioTactic` / `TacticRule`)


`EventIssueCommand` fires once and is done — no supervision, no fallback. That's fine for a plain waypoint, but an `AttackMove` from `EventCommandTarget` targets a live enemy cluster's centroid, and once that cluster is destroyed or moves away the unit arrives, finds nothing, and (per `ends_on_arrival()`) drops to an empty command queue with nothing left to revisit it except `Actor`'s short-range idle-aggro check — a unit standing where an enemy USED to be just freezes there forever. The `Bot`/`BotBrain` doesn't help either: it's a whole-commander skirmish AI (§Commander and economy), the wrong granularity for "these specific scripted units should keep re-engaging" and deliberately left untouched by this mechanism.

`ScenarioTactic` (`scripts/scenario/scenario_tactic.gd`) is the answer: ongoing, hand-authored behaviour for one CLUSTER of units, added as a sibling of `GlobalTrigger` under a `ScenarioTriggerManager`. A cluster is node-group membership (`unit_group`) — the same `spawn_groups` label `EventSpawnEntities` already stamps for `ConditionGroupCount` — fixed for the cluster's lifetime, and synced into a `Squad` — the object the Bot's military runs on too ([ai/squads-and-relations](../ai/squads-and-relations.md) §Squads).

Children are `TacticRule` nodes (`scripts/scenario/tactic_rule.gd`), evaluated in authored order each time the tactic decides (§Trigger-decided mission commanders) — first whose `condition` (an ordinary `Condition` Resource, reused rather than inventing a second predicate language) holds wins, and a rule with **no condition at all** always matches, the same "nothing to wait for" idiom `GlobalTrigger` gives an empty `conditions` array — so a rule with no condition, placed last, is the cluster's default. `TacticRule` **extends `EventIssueCommand`** rather than wrapping one, purely to reuse its existing chain-building for the COMMANDS action (`EventCommand` children, per-unit formation offsets, the `Defend` aggro-shape override) — `ScenarioTactic` calls `issue_commands_to()` directly, never `execute()`, the same bypass `EventSpawnEntities` already relies on for a nested `EventIssueCommand`.

**Re-issuing is split two ways, and this is the load-bearing part** — naively "reissue whenever the winning rule is still true" would spam every member's command every tick, but "reissue only when the winning rule changes" doesn't fix the freeze bug at all, because a dynamically-targeted rule (`EventCommandTarget`) can keep winning while its OWN target has gone stale:
- The rule **changing** redirects every current member unconditionally — a real change of posture (e.g. "defend" → "attack") overrides whatever any individual unit was doing.
- The rule **staying the same** but a member going **idle** (`CommandReceiver.is_idle()` — its queue ran dry: an `Attack` whose target died, an `AttackMove` that arrived and found nothing) re-runs that SAME rule for that member ALONE, so `EventCommandTarget` re-clusters and picks a fresh live target instead of the unit standing still forever. Members still actively executing their order are left completely alone — reissuing to the whole cluster on every idle member would interrupt units mid-fight for no reason.

Two of the three gaps the design discussion's worked examples found (sweep-and-destroy-neutrals, defend-then-relocate, rebuild-and-flee) are now `PLANNED` as shared verbs, in §Trigger-decided mission commanders below: a `Build`-issuing rule action (today's `EventCommand` vocabulary only produces `MoveCommand`/`AttackMove`/`Defend`) and a flee/retreat verb (no such command exists at all). REJECTED — a target-selection primitive for the cluster's OWN commander's structures or for NEUTRAL (commander 0) targets (`EventCommandTarget._enemy_candidates` excludes both by design): the bot has no use for it, and the action vocabulary is shared (Alex, 2026-10-10). Tests: `tests/test_ScenarioTactic.gd`.

`EventCommandTarget.frame_filter` (an int, -1 = no filter, matching `Defense.FrameType`'s int values otherwise) narrows which enemy candidates cluster at all — e.g. `ARMY` + `BIO` is "infantry only," not any enemy unit. A plain int rather than `Defense.FrameType` itself so "unset" doesn't collide with `BIO` being value 0. Tests: `tests/test_EventCommandTarget.gd` (covers `_enemy_candidates()` only — `to_command()`'s nav-map lookup has no test fixture in this suite yet, for either the old code or this addition).

`s3.tscn`'s three enemy waves (`WaveRecruits`/`WavePetrel`/`WaveCarronade`, under `ScenarioTriggerManager`) are the first real usage: each `Spawn` (`EventSpawnEntities`) now carries a `spawn_groups` label instead of a nested one-shot `EventIssueCommand`, and a sibling `ScenarioTactic` (`RecruitsTactic`/`PetrelTactic`/`CarronadeTactic`) watches that label with a single unconditional `TacticRule` — the "no branching, just keep re-engaging" case row 1 of the table above describes. Recruits and Petrel target `ARMY`; Petrel adds `frame_filter = BIO` (hunt infantry specifically, the motivating "roam and re-engage" case); Carronade targets `BASE` (structures) instead of `ARMY` — a deliberate behavior change from what the wave used to do, since beelining for buildings while ignoring units was never expressible with the old one-shot chain.

**`EventCommandTarget.to_command()` diverges by `type` past cluster selection, and this is load-bearing for Carronade.** `Type.ARMY` still issues an `AttackMove` to the selected cluster's centroid — units move, so a chase-the-area order fits, and `AttackMove.get_updated_state()` opportunistically picking up a closer enemy via `get_aggro_near_position()` while travelling is exactly "fight anything encountered en route" (Recruits' and Petrel's intended behavior). `Type.BASE` instead locks an `Attack` onto ONE specific structure (`_closest_in` the selected cluster) rather than AttackMoving to the cluster's averaged centroid. Two problems drove this split, both first observed as "the tank wave is broken" after the initial `AttackMove`-for-everything version shipped: a structure doesn't move and can't be stood inside, so a nav-snapped point near several buildings' centroid can land just outside anyone's short aggro/attack range — the tank arrives, finds nothing under `AttackMove`'s own logic, and idles, only recovering once the (unrelated) 20s+ re-cluster/idle-reissue cycle happened to shift the centroid enough to matter; and `AttackMove`'s en-route aggro pickup is exactly what a "beeline for structures, IGNORE units" order must not do, so the tanks kept peeling off onto the nearest enemy soldier instead of the base. `Attack.get_updated_state()` has no equivalent re-acquisition — it only ever re-checks the SAME target — and `Attack.should_move()` closes distance until `SU.is_in_attack_range()` is actually true, the same range check that already works correctly for a player's own structure-attack orders. Tests: `tests/test_EventCommandTarget.gd` (the `to_command()`/`Type.BASE` cases — `Type.ARMY`'s `to_command()` still has no coverage, same nav-fixture gap as before).

## Trigger-decided mission commanders

A mission's enemy commander DECIDES with triggers and tactic rules, but PERCEIVES and ACTS the way
the skirmish Bot does, so the two differ only where
[ai/squads-and-relations](../ai/squads-and-relations.md) §The boundary says they must: who
chooses the policy (decided 2026-10-10, Alex). Before it, every condition read the live scene and
a tactic's orders bypassed `BotActuator`, so a scripted enemy saw through fog without anyone
having chosen that, and nothing audited what it ordered.

### Perception: a check reads the live scene or an alliance's beliefs

`Condition.perspective` is OMNISCIENT (the default, and every shipped mission) or ALLIANCE, read
through `AlliancePerspective`; `EventCommandTarget.perspective` is the same switch for a target
pick. **By alliance, not commander,** so a scenario with several commanders on one side reads what
that side knows: own and allied pieces where they stand, a piece any member's blackboard believes
at its last-known spot, anything else only while a member sees it. **Fog-limited is a choice the
author makes per check** — a scripted wave is usually meant to find the player.

A perception condition must read only what the bot stores or derives cheaply
([ai/debug-signals](../ai/debug-signals.md)'s cost column): a pull condition is polled every
frame, so a heavy read there costs a sweep per frame. A check that cannot honour a perspective
(a timer, a resource threshold) says so in the Scene dock rather than silently reading the scene.

### Decision: authored, and paced like the bot

- A tactic decides on its commander's combat period, as a `BotScheduler` job, so reaction
  latency is the difficulty knob for a scripted enemy as for a bot. A commander with no running
  brain (the human's slot, neutral, a brain switched off) uses the trigger manager's own fixed
  cadence instead, which is copied from MEDIUM's rather than read from it, so retuning the bot
  does not retime missions.
- `EventSetBotJobs` switches named `BotBrain` jobs on and off mid-mission — the runtime form of
  `PlayerSlot.disabled_bot_jobs`. **No event sets what a job READS** (a posture dial, the
  military objective): an authored value inside a scored decision is the merge the boundary rule
  forbids.
- **One mission difficulty**, picked on the Campaign page from EASY, MEDIUM and HARD only: the
  `difficulty` a `ScenarioExpression` reads (1, 2, 3), recorded in a replay, and nothing else.
  **A mission is made harder by triggers authored against it, never by its bots** — every bot
  slot keeps its authored tier, so a mission plays the same at every difficulty until its
  triggers read the value (Alex, 2026-10-11; it supersedes the first build, which also set every
  bot slot's tier and so turned the prologue's PASSIVE enemies into active bots). A whole
  trigger or tactic rule is gated with a `ConditionExpression` ("difficulty >= 2"), composed with
  the other conditions, rather than with a field on every trigger class. A scenario nobody picked
  for (a skirmish, a mission run from the editor) reads MEDIUM.

### Action: the bot's verbs and its actuator

- **Every mission order goes through a `BotActuator`** — the manager's own, so a mission's
  orders keep a ledger apart from the bot's decisions. A scripted route is still a chain:
  `issue_chain` is the one verb that queues, and it is mission-only, because the bot's no-queue
  rule is about not *deciding* a queue's length and an authored chain is decided already.
  Orders an ABILITY's effect gives (an air drop's run, Dignify carrying orders over) are the
  mechanic's, not a mission decision, and do not go through it.
- A `TacticRule` names its action: COMMANDS (its own `EventCommand` chain), or one of the shared
  policies — HOLD, STAGE, ASSAULT, ESCORT, RETREAT, BUILD — at the point a `Node3D` under the rule
  gives. RETREAT (cover, else walk home or to the point) is the one definition the bot's
  preservation also uses; BUILD keeps a structure standing at a point. An authored ASSAULT has no
  believed structure behind it, so it attack-moves on the point and razes nothing it is not shown.
- A tactic claims its members at EXCLUSIVE in its bot's `BotClaims`, so a slot can run the bot's
  own military beside a scripted squad. **Authored squads do not count against `squad_cap`**: the
  cap is the bot's own steering handicap, and how many scripted squads exist is the author's
  design.
- The bot overlay's Army category draws a tactic's squad beside the military's, with the rule it
  is running.
