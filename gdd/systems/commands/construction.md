---
title: Construction
type: system-note
---

# Construction

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Build → Assemble, and Repair beside them


Three commands, and the axis is **what the target IS**, not what the worker does to it:

| Command | Target | Actor gate | Ends when |
| --- | --- | --- | --- |
| `Build` | a SITE (grid cells) | `Builds.can_build(tool.type)` | the foundation is laid |
| `Assemble` | a PLACED, unfinished structure | `Builds.can_build(target.id)` | `build_progress` hits 1.0 |
| `Repair` | a FINISHED, damaged, friendly MECH entity | the `Repairs` component exists | `hp` hits `hp_max` |

**`Assemble` and `Repair` are two commands over one action, split at the precondition.** Construction is always two commands — Build lays the foundation and hands off, and `Assemble` is what every co-builder converges on — and mending is a third thing again. One command cannot answer both, because "may I work on this?" has *opposite* answers for a half-built barracks and a dented tank. Below the precondition they are identical: the same channeled action, the same `ends_on_arrival() == false`, the same builder registration and AOE2 crowding formula.

**A unit that can repair says so with a component, and presence is the whole check.** `Repairs` (`scripts/entities/components/repairs.gd`) is created by a bare `repairs: true` in the piece's doc (Kobold and Sapper today). It carries a node rather than a bool on `Commandable` so the capability has somewhere to grow — a target filter, a cost, a rate that varies — and it is deliberately unlike `Builds`, whose capability was never presence alone: WHICH structures a unit may place is data, so `Builds` carried a list from the day it existed. Repairers do NOT diminish each other the way builders do; each applies its own `repair_rate` every tick, because construction is one job several units crowd around while repair is several units each working on the same patient.

**What may be repaired is stated once, in `Repair.repairable_cause`**, and the precondition, `can_act`, `get_updated_state` and the controller's right-click ladder all read it. Four gates, each earning its place:

- **MECH frame, not armour type.** The armour axis here is LIGHT/MEDIUM/STRONG (how hard you are to hurt); the frame axis is BIO/MECH (what you are made of), and "a mechanic mends machines" is the second. Biological units are mended by `HealAOE`. Structures are included and need no special case — a structure is a `Commandable` with a `Defense` like any other.
- **Same commander, not merely non-hostile.** A derelict neutral (commander 0) building is nobody's to mend.
- **Finished and not planned.** An unfinished structure reads as "hp below max" — `advance_build_progress` scales hp with progress — so without this gate a repairer would silently build it to completion, bypassing Assemble's builder registration and XP.
- **Actually damaged**, so a right-click on an intact friendly falls through the ladder instead of issuing an order with nothing to do.

**Repair sits ABOVE Occupy in `_resolve_command_class`, and the damage gate is what makes that safe.** Plenty of repairable things are also garrisons (a safehouse, a transport), and "right-click a transport to board it" is too strong an idiom to give up — but so is "right-click your burning barracks to fix it", and most buildings garrison. Since Repair only ever takes the click on a target that is actually hurt, an intact transport still loads and a damaged one gets mended. The accepted cost: boarding a *damaged* transport needs the Occupy button rather than a right-click.

Neither command has a grid button yet — both are right-click-resolved only, and `CommandGrid.binding_for` returning null for a command name is already the supported case (so is `command_move`, `command_attack`, `command_occupy`). Tests: `tests/test_Repair.gd`, and `tests/test_CoBuild.gd` for Assemble.

**`CommandMessage`** is the context bundle passed everywhere:
- `target: Entity` — the entity under the cursor (may be null)
- `tool: Tool` — for Build/Train commands
- `world_position: Vector3` — raw raycast hit
- `map: Map`
- `xz_position: Vector2` — computed from world_position
- Reference-counted: `retain()` / `release()` in MoveCommand `_init` / `_notification(PREDELETE)`. `deep_copy()` when snapshotting for waypoint indicators.

**`CommandReceiver`** owns the queue (`_command: MoveCommand` + `_command_queue: Array[MoveCommand]`). Key method: `update_commands(a_commands, add_to_queue, prepend)` — accepts a `MoveCommand`, an `Array[MoveCommand]`, or `null` (clears queue).

**`CommandContextParser`** (static class) is the single source of truth for which command names are available to a given entity or selection:
- `commands_for(entity)` — predicate table → list of command name strings
- `commands_for_selection(entities)` — union across selection
- `tools_for(entity, context)` — tool command names available in a `Tool.ControlContext` (BUILD/TRAIN); gates BUILD tools via `Build.tool_applies_to()`, TRAIN tools via `Production.producible_types`. The controller's `current_context()` supplies the context.

**Command preconditions** — every command subclass implements:
```gdscript
static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause
static func requires_position() -> bool
static func tool_applies_to(command_tool_name: String, entity_type: Entity.Type) -> bool
```
`PreconditionFailureCause.COMMAND_PENDING_TOOL` is not a failure — it means "armed but waiting on tool selection."

**Structure-flavored routing**: `Commandable._process_commands()` intercepts `Train`, routing it into the commander's production queue, before it reaches `CommandReceiver._process_commands()`. A bare `MoveCommand` aimed at a stationary `can_rally()` commandable is intercepted earlier still — in `Commandable.update_commands()`, by `_absorb_rally_commands()` — because that is the only place the additive (shift) flag still exists; by the time the receiver has stored a command, "replace" vs "extend" is no longer knowable.

**Rally / release destinations** (`Commandable.can_rally()` / `rally_commands` / `rally_chain()`): any commandable that trains units (`Production`) or holds occupants (`Garrison`) can rally. A stationary one (no `Movement`) holds `rally_commands` — a QUEUE of PRE-ISSUED commands, not a single point — fed by `_absorb_rally_commands()` as above: a plain right-click REPLACES the queue, a shift right-click APPENDS to it. A mobile one (e.g. a transport) has no queue and hands on its own active movement command instead. Only exact `MoveCommand`s are absorbed today (an `Attack` aimed at a structure stays an order for the structure), but the queue holds commands rather than points precisely so richer pre-issued orders — attack-move, defend, a patrol route — can be stacked later.

**What the rally LINE draws is the rally as CONFIGURED, not the job in progress.** `RTSController._rally_commands_to_draw` reads `rally_commands` for a selected structure, and reads a specific unit's own pre-issued chain only while the player is hovering that unit's production card (`InfoView.hovered_training_target`) — overriding just the structure being hovered. It used to draw the head job's captured chain unhovered, which meant the line a player saw while merely selecting a barracks described a unit already being built rather than the rally they were about to set, and it changed under them silently whenever a job started or finished. The default view now answers "where will my units go"; the card hover is the only way to ask the other question. A hovered job's stored chain can be empty — it falls back to the structure's rally at spawn (`Production._spawn_unit`) — so the drawing falls back the same way, and the line always matches what that unit will actually receive.

### Where a builder walks: an OVERLAY build aims beside its host, not at it

**A `Build` walks to `message.position` — the site centre — except an OVERLAY build, which
walks to its host's nearest passable approach cell** (`Build.movement_destination`, resolved
through `SU.nearest_footprint_adjacent_cell`, the same helper
`CommandReceiver._resolve_movement_target` uses for any structure-targeted order).

The centre is fine for an ordinary build: the placement rule requires those cells to be
empty, so the builder can stand on the exact spot it is aiming at. An Extractor's target
cells are the ExtractionSite it binds onto — occupied, impassable, and **occupied from the
moment the order is given rather than from the moment somebody places something**. So the
agent paths as close to that centre as the navmesh allows and reports the path finished
wherever that lands, which is not necessarily inside `can_act`'s footprint-adjacency ring.

When it lands outside that ring the builder is stuck for good, and nothing in the tick loop
breaks the tie: `should_move` stays true because `can_act` is false, the agent is already at
the end of its path, and `CommandReceiver._arrive` re-pins the target to the builder's own
position every tick. `ends_on_arrival() == false` — the thing that stops an approaching
builder losing its order — is what makes the stall permanent rather than merely wasteful.

This is the **third** distinct failure the overlay case has produced, and the shape repeats:
a rule written against "empty cells the builder is about to fill" is asked about cells that
are permanently full. The other two were the co-build scan
(`Build._structure_on_target_footprint` asks "is one of OURS bound to that host", not "is
anything on these cells") and the approach-cell lookup (`SU._passable_footprint_neighbors`
resolves through `structure_footprint`, so an overlay reports its host's cells). **All three
are the same repair: ask the HOST.**

Symptom to recognise: a builder standing a couple of cells from an extraction site, not
moving, holding a Build it never completes. It is nearly invisible to a player, who issues
the order from nearby and is inside the ring on the first tick; it shows up in bot-vs-bot
play, where the builder is dispatched from across the base.

**The bot's watchdog hid it and made it worse.** `BotEconomy.CONSTRUCTION_JOB_TIMEOUT_SECONDS`
(90 s) exists so that a build which can never finish does not freeze the whole economy — and
it works, so the visible damage was a builder idling rather than a bot standing still. But
releasing the job also records the target in `_abandoned_spots`, so the bot writes the
extraction site off permanently and never returns to a site that was always buildable. The
watchdog stays: it is the right safety net for a genuinely unreachable order. It is not a fix
for an order that was reachable all along.

Tests: `tests/test_BuildApproach.gd`.

### The rally is read at SPAWN, not captured at submission

**Nothing snapshots a rally when a purchase is made.** `Production._spawn_unit` reads the
producing structure's `rally_chain()` at the moment the unit appears, so **re-aiming a rally
re-aims every unit still queued behind it** — which is what a player moving a rally point
plainly means.

It used to be the other way: `PurchaseTransaction` captured each candidate producer's chain
at submission, so five units ordered under the old rally kept walking to it after the flag
moved, and only units ordered afterwards used the new one. Nothing said so on screen, and the
queue is exactly where a player cannot see which is which.

**The one thing that does travel with a purchase is `player_commands`** — an order the player
aimed at THAT unit by selecting its queue entry on the production rail
([ui/control-matrices](../ux/ui/control-matrices.md) §Selecting a unit that does not exist yet).
So the two never have to be merged:

| the unit was | it does |
|---|---|
| singled out by the player | what the player told it |
| not | the producer's rally, as it stands when the unit appears |

The same precedence, in the same words, governs a garrison occupant: `Garrison`'s release
chain prefers the occupant's own orders over the host's rally
([combat/garrison-and-transport](../combat/garrison-and-transport.md)).

`rally_commands` are TEMPLATES and are never handed out directly. `rally_chain()` returns fresh copies via `MoveCommand.duplicated()` (deep-copied message, `origin` token dropped so inheritors aren't treated as siblings of the order that set the rally), so two units off one rally can never share a command instance. `rally_destination()` still returns the first leg uncopied, for the readers that only want a heading (`Production`'s spawn-side bias, `Garrison`'s exit-cell seed). `Garrison.evacuate()` chains the whole `rally_chain()` on after each evacuee's immediate exit-point move.

**A rally template can outlive its own target, because nothing invalidates it.** A rally set by right-clicking ON an entity (not empty ground) carries that entity as `message.target`, and the template sits in `rally_commands` untouched until the player re-authors it — there is no hook that clears or scrubs it when the targeted entity dies. If the HOST holding that stale template also dies later — with occupants still garrisoned, so `Garrison.evacuate()` calls `rally_chain()` — `MoveCommand.duplicated()` → `CommandMessage.deep_copy()` tries to copy the now-FREED target into a fresh `CommandMessage`, which crashes outright (`Invalid type in function 'new'... previously freed`) rather than degrading to null the way a plain `is_instance_valid()` check elsewhere would. `CommandMessage.deep_copy()` now scrubs a freed `target` to null before constructing the copy (`position` already falls back to `world_position` when `target` is null, so the copy still points somewhere sensible) — the fix lives at the copy boundary rather than at every place a rally could theoretically go stale, since `deep_copy()` is the one place ALL of them funnel through. Tests: `tests/test_CommandMessageDeepCopy.gd`.

**A job still carries a command slot** (`Production.JOB_COMMANDS`), and it is now nearly always
EMPTY. It exists for the callers that hand a chain in directly — scenario events, tests — and
for nothing else; a purchase made through the HUD leaves it blank and `_spawn_unit` falls
through to the transaction's `player_commands`, then to the producer's live `rally_chain()`.
The job also keeps a back-pointer to its purchase (`JOB_TRANSACTION` / `job_transaction()`),
which is what lets a unit ALREADY BEING TRAINED still be selected and ordered — the
transaction is the thing the order is stored on, and the job is how the info panel finds it.

---

## A piece built from another piece's form, and conversion

**Some pieces are built FROM a neutral building.** The Anarchical `an_infrastructure` lists `variants:` in its doc — today a square and a long neutral building, default first — and each is a whole underlying piece with its own footprint, HP, price, build time and infrastructure (published as that piece's *template*; see [`piece-vocabulary.md`](../authoring/piece-vocabulary.md)). Building the piece means building one of those forms: the structure is instanced from the FORM's scene, so it has the form's footprint and HP, and then takes everything else from `an_infrastructure`'s own doc — its id, armour and frame, garrison masks and range bonus, vision. Its infrastructure is the form's, not the piece's.

**Which form is a property of the ORDER.** A build order carries a tool bound to one form: the tool still names `an_infrastructure` (so the tech tree, the commander's structure accounting, the build card and the hotkey are untouched) but its scene, footprint, price and build time are the form's. An order that names the piece and no form means the first one, so the CPU commander and any scenario event get the default without knowing forms exist. Placement validity, the blueprint, the site reservation and the builder's approach all read the form's footprint; the price is the form's, including when the purchase is queued and waits for funds; a finished structure is timed by the form that made it, never by the piece's own (default-form) entry. Prerequisites stay the piece's.

**One routine makes a node the piece, and a new build and a conversion both use it.** Which properties it copies is read off the TARGET piece's scene, restricted to its gameplay components; footprint, HP and infrastructure always stay the underlying form's. Retuning `an_infrastructure`'s doc therefore needs no code change, and the two routes cannot drift apart. The routine does not touch the commander: a fresh node has none yet, and a converted one has its books re-keyed by the conversion, in an order it depends on.

**A neutral building grants infrastructure to nobody.** Its scene carries none — its number lives only in its template — so neither standing on the map nor adopting a commander through a garrison credits anything. Infrastructure is conferred once, by becoming an `an_infrastructure`, and is credited to whoever owns it from then on, so losing it withdraws exactly that.

### Conversion

**Building an `an_infrastructure` on a neutral building converts it in place.** The target is the neutral (commander 0) building of the `neutral_building` family whose FOOTPRINT holds the aimed cell — any member, whichever form the tool is armed with. It used to be the building the armed form's own footprint would land squarely on, which made a conversion depend on the armed variant; a shack can now be converted with the long form armed. The node keeps its footprint, HP, garrison and occupants, and gains ownership plus the routine above. Aiming at a building lays no new structure and raises no blueprint.

**A conversion costs the target's own listed energy price times `ENERGY_DISCOUNT` and takes its own listed build time times `BUILD_TIME_DISCOUNT`**, both one half. Converting is priced off the building the player is actually taking, not off a flat figure, because buildings now differ in size and worth; the discount is the reward for finding a building rather than building one. Funding and deferral are the ordinary build rules: with the additive modifier an unaffordable conversion queues, and the builder waits at the building for the money.

**Accepted:** a conversion does not check the piece's prerequisites, as before.

## An unfinished structure exists, accepts orders, and cannot act


One rule, and it is the one training already followed: a structure under construction is
selectable, orderable and a legal target — it just **cannot act**. Orders given while it
goes up are KEPT and carried out the moment it finishes, which is what makes "queue work
at this building while it builds" mean anything.

`CommandReceiver._process_commands` refuses to act for an owner that is `not is_built`,
alongside the stun gate and for the same reason: no `get_updated_state`, no `can_act`, no
`fulfill_action`, no movement — but the queue is untouched. `Commandable._update_state`
additionally skips the idle-aggro pickup while unbuilt, or the structure would latch onto
a target it cannot shoot and then open fire on whatever happened to be nearest the instant
it completed, rather than waiting to be told.

**A `cl_defense_antiAircraft` shooting down aircraft at 10% health is the bug this fixes.**
`Production.tick` had been gated on `is_built` since training was written; nothing else
was.

`Garrison.admits` refuses an unfinished host too — a building still going up has no inside
to stand in. That check lives on the component rather than only in
`Occupy.meets_precondition` so the mechanics that put units in WITHOUT consent (capture,
deposit) agree with the one that asks. Tests: `tests/test_UnfinishedConstruction.gd`.

### It is not COVER either

The same rule read from the other side: a finished building blocks line of fire, and a
foundation does not. A site with materials on it is not something a bullet hits, so
`Attack`'s line-of-fire raycast — which queries `CollisionLayers.Mask.STRUCTURE_BLOCKER` —
finds nothing there, and units shoot straight through the plot until the building is up.

**Everything else about it is unchanged, and that is the point.** It keeps its grid cells
(so the navmesh hole and the units walking around it are as before), it keeps
`TARGETABLE_GROUND` (so it can still be shot at, which is what makes attacking a building
site worthwhile), and only the blocker bit waits.

`Entity.blocks_line_of_fire` is the predicate — true for a structure, overridden on
`Commandable` to require `is_built` — and `Entity._apply_targetable_layers` is the one
place that writes the layer from it. The bit is added on the completing tick by
`Commandable.advance_build_progress`, NOT by `Assemble`, so every route that finishes a
structure (a captured one, a scenario event) agrees without each having to remember.

> **TODO — building things that are NOT structures.** `is_built` is group-keyed
> (`not is_in_group("structure") or build_progress >= 1.0`), so a unit is always built and
> the gate above is inert for one. Constructing UNITS the same way — a vehicle on a pad
> that accepts orders while it is assembled — wants exactly this rule, but the build system
> currently assumes everything it raises registers on the terrain grid
> (`Build.fulfill_action` → `Map.add_structure` → `TerrainGrid.place_building`, and
> `Build.valid_placement` reasons in footprint cells). Generalising means separating "what
> is under construction" from "what occupies grid cells" first; do that before reusing
> Build for units.

## Planned structures (blueprints)


A blueprint is **the structure itself in a PLANNED state** (`Entity.is_planned`), not a decorative ghost — which is what lets the player select it and queue units at a building that hasn't been started. Issuing a build order creates ONE (`Build.plan_structure`), shared by every builder in the order via `CommandMessage.planned_structure`.

What it has: ownership + team tint, its `Selectable`, its `Production`, and 0.2 opacity. What it does NOT have until placement: grid cells, collision (`refresh_movement_collision` / `_apply_targetable_layers` bail out on `is_planned`), line of sight, infrastructure upkeep, a place in the commander's `structure_type_map`, and `_physics_process`. It is invisible to every commander but its owner (`fog.gd`, `Commander.visible_foreign_structures`).

`Commandable.commit_construction` is the transition: the builder arriving turns that same node into the real structure (`Build._place_structure`) — nothing is re-instantiated, so a selection or queued order survives placement.

**Lifetime belongs to the BUILD purchase** (`PurchaseTransaction.planned_structure`): `consume()` (placement) releases it, `cancel()` (order abandoned, queue pruned) frees it. Units queued at a freed blueprint lose their only candidate producer, so `ProductionQueue._prune` drops and refunds them; a destroyed producer refunds its own queued jobs in `Commandable._on_death`.

**A blueprint whose purchase is still queued is drawn darker** than one that is funded and merely waiting for its builder to walk over — see §Construction opacity for the shade channel and `Commandable.awaiting_funds`. Without it the two states are indistinguishable, and a player has no way to tell "the builder is on its way" from "this is stuck behind everything else in the queue".

It also carries an awaiting-funds badge ([condition-visuals](../ux/ui/condition-visuals.md)).

Tests: `tests/test_ConstructionOpacity.gd`, `tests/test_PlannedStructures.gd`, `tests/test_PurchaseGating.gd`.

### A plan claims its site

A blueprint holds no grid cells, but its footprint is spoken for. **A second plan overlapping a
site our side has already planned is refused** (`SITE_PLANNED`, "Already planned there"): the
ground is free, but something has claimed it. This replaced overlapping plans being accepted and
then sorted out by whichever builder arrived first.

Only our side's plans count, because only they are known. An enemy's plans are invisible, and
an enemy standing on the site is not checked when the order is given. **When the builder
arrives and is about to lay the foundation, a hostile unit on the footprint ends the order.**
Airborne and garrisoned units do not count. A friendly unit there steps aside after placement,
as before.

TODO — co-building a PLANNED site: a second Build at the same site used to be the way to send
another builder, and it is now refused as SITE_PLANNED. Repair refuses a blueprint, so there is
no longer a way to add a builder before the foundation is laid. Deployment drops and two-form
deploys do not check planned sites either.

---

## Placing and turning a structure

With a Build tool armed, `command_issue` is a gesture rather than a click
(`RTSController._begin_placing_structure` / `_finish_placing_structure`):

1. **Press** sets the structure DOWN — the placement point is frozen where the press landed, so the
   cursor stops moving the structure — and orders nothing.
2. **Drag** turns it. The cursor's direction from the press point picks the nearest of the four axes
   (`Structure.quarter_turns_facing`), and the ghost, the placement grid and the order all follow. A
   drag shorter than `RTSController.PLACEMENT_ROTATE_DEADZONE` (one cell) changes nothing, so a plain
   click keeps whatever facing the keys gave it. The `rotate_left` / `rotate_right` keys (`[` and
   `]`) turn it a quarter step at any time, held or not.
3. **Release** orders the build with the turn it ended on. If that turn made the footprint illegal
   (`Build.meets_precondition` refuses the placement), nothing is submitted and the tool STAYS armed
   with the same facing, so the player can turn it back or aim elsewhere. Otherwise the order is issued
   as a click used to be: the tool is put down, or kept under the additive modifier.
4. A left click (`world_select`) while a tool is armed still disarms it and changes the selection not
   at all — pressed part-way through a placement press, it cancels the placement, and the release then
   builds nothing.

**Front is +Z.** A piece's model faces +Z at rotation 0 — the direction `Movement.get_facing` already
treats as forward — and a quarter turn is 90° counter-clockwise seen from above, so count 1 faces +X,
2 faces -Z and 3 faces -X. Art is authored to that convention; the whole piece (model, selection shape,
hull) turns because they are children of the root. The count lives on `Structure.quarter_turns`, travels
on `CommandMessage.quarter_turns`, and is what the blueprint and `Map.add_structure` register.

Rotation does not apply to a conversion (an upgrade in place, nothing new is laid) or to an extractor
(it takes the site or pond it lies on); both are placed as before, at the press position, on release.
The preview and the tool state reset to 0 whenever the tool is put down. Design and the rest of the plan:
[footprint-rotation](../terrain-and-navigation/footprint-rotation.md).

## Placement keeps navigation intact

`Structure.valid_placement` answers geometry alone — in bounds, unoccupied, flat, dry enough.
It says nothing about what the footprint does to the units already on the map, which is a
separate question `NavPlacement` (`scripts/maps/nav_placement.gd`) answers and
`Build.meets_precondition` now asks of every ordinary placement, human or bot:

1. **A footprint may not split the walkable surface.** Applies regardless of what is being
   built — a wall-in strands whatever was on the far side, the placing builder included.
2. **A structure with a `Production` component must keep a whole side on walkable ground.**
   Scoped to producers rather than every structure: a unit finishing training needs somewhere
   to appear, and that is the case a real match hit — a bot's barracks with all four sides
   walled, training units into nowhere. Narrower than the bot's OWN placement rule, which
   applies rule 2 to everything it builds for a different reason (a building nothing can walk
   to cannot be repaired or garrisoned either) — see
   [bot-architecture](../ai/bot-architecture.md) §Where a building goes.

Both rules were bot-only until now (`BotEconomy._placement_ok`); `Build._placement_keeps_navmesh_access`
is the same two rules asked in world terms, refusing with `INVALID_PLACEMENT` exactly as the
geometric check does. Rule 3 (`NavPlacement.accepts_for_class`, the wide-unit-agent check) stays
bot-only — the bot keeps its own base passable for the widest class any faction fields, which
is a policy rather than a fact every player placement must obey.

**Placement closes off the common case, not every case.** A structure already standing can
still end up with no navmesh side — terrain changing under it, or one scene-authored into a
pocket — so `Commandable.has_navmesh_access()` asks the same question of an already-registered
footprint, and `Train.meets_precondition` refuses with `NO_NAVMESH_ACCESS` when it says no. The
training button greys out exactly as an unaffordable purchase does; nothing spawns into a
sealed room.

Tests: `tests/test_NavmeshAccessGating.gd`.

---

## PLANNED — Placement is judged against what the commander knows

Decided 2026-09-24. Today `Build.meets_precondition` judges a footprint against the TRUE grid,
so a refused placement leaks what is standing in the fog. The rule instead:

- **Explored ground is judged by what the commander last saw.** If the fogged view shows the
  spot placeable, the order is accepted. If the builder arrives and the spot proves invalid (a
  building went up in the meantime), the order aborts — the arrival re-check in `Build` already
  does this half.
- **Unexplored ground refuses the order outright.**

This applies to extractors and to every other placement, except the debug spawner's, which
judges the true grid ([debug-mode](../ux/ui/debug-mode.md) §The piece spawner). It came out of the aggro-fog
question; aggro itself is fog-gated already ([target-acquisition](../combat/target-acquisition.md)).

---

## Hijack: taking an occupied vehicle

*Moved out of `interact.gd::_hijack`.*

Three things happen, and the ORDER is load-bearing:

1. **The target's orders are dropped.** It is mid-execution of its previous owner's
   command queue — a hijacked tank that kept its old attack order would immediately
   turn on its new owner. Cleared BEFORE the handover, while it is still nobody's.
2. **Ownership moves.** Assigning `commander` runs Commandable._on_commander_changed,
   which reparents the unit under its new commander and re-points its RVO avoidance
   layers at the new team — so it stops steering around its old allies and starts
   steering around its new ones. The structure-registry / infrastructure branch there is gated
   on the "structure" group and correctly does nothing for a unit.
3. **The hijacker dies.** Via `defense.kill()` rather than queue_free(), for the reason
   SuicideStatusEffect gives: the normal death path (Commandable._update_state ->
   _on_death) owns the teardown — spatial-partition removal, garrison release,
   production refunds, queue_free — and skipping it would leave stale grid entries.
   Killing LAST means a hijack that somehow fails partway leaves the actor alive.

Accepted consequence of using the death path: this fires the ON_DEATH occurrence and
plays the death sound, so a scenario counting hijacker deaths counts a successful
hijack too. The Kamikaze is expended the same way and has the same property.

Known gap: a hijacked unit stays in its former owner's HUD selection until they
reselect — RTSController prunes its selection on validity, not on ownership. Nothing
could change hands before this, so the case has never arisen.
