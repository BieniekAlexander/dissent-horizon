---
title: Payloads
type: system-note
---

# Payloads

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## A transformation carries the unit's orders


When one piece becomes another (Dignify: an Irregular becomes a Warlord), the player's standing orders come with it. `CommandReceiver.portable_chain_for(recipient)` returns the part of the chain the new piece can carry, as fresh copies.

**It TRUNCATES at the first command the recipient cannot perform rather than filtering that command out**, and that is the whole design: a queue is a SEQUENCE, and the commands after a dropped one were issued in the expectation that it had happened. "Build a redoubt here, then go and hold that hill" becomes a Warlord that cannot build; keeping the second order would send it to hold a hill next to a building that was never raised. Stopping at the gap leaves a unit that visibly did part of what was asked — easier to notice and correct than one that quietly skipped a step.

**Capability is asked of `CommandContextParser`, not of `meets_precondition`.** The precondition answers "could this succeed right now", which is the wrong question: a command whose target has wandered off is still one this unit can perform. `CommandContextParser.name_for(command)` is the inverse of the parser's predicate table — the only place a live command becomes the name those predicates are keyed by — and `actor_can_perform` looks that name up in `commands_for(actor)`. It lives on the parser rather than as a static on each command class because the parser is already the single source of truth for the command set a unit supports, and a name declared on the class would be a second, drifting copy of it. A command absent from the table (Wander, Capture) is nobody's advertised capability, so it is treated as portable.

The commands are DUPLICATED rather than handed over, the same treatment rally templates get: the old actor is about to be freed, and its teardown releases whatever its live command instances were holding. Tests: `tests/test_UnitTransformation.gd`.

## Payloads: three shapes, and mostly authored rather than coded


Every built payload is one of three things, and which one it is follows from what the sanction DOES rather than from which faction owns it:

| Shape | Script | Authored per cell as | Cells |
| --- | --- | --- | --- |
| **spawn** | `EventSpawnEntities` (already existed) | `entity_scenes` + `count_expression` | Drop 1/2/3, Ambush 1/2/3 |
| **single target** | an `EventTargetUnit` subclass | `scope` + the subclass's own exports | Promotion, Dignify, Informant 1/2/3, Freeze 1/2, Overcharge |
| **standing** | none — no payload at all | the ABILITY's `passive` + the per-cell benefit | Scavenge 1/2/3 |

plus two one-offs: `EventRadarScan` (the whole Scan family) and `EventGlobalEmp`.

**A TIER is authored data, not a subclass.** Drop 1 and Drop 3 differ by one `PackedScene` reference; Freeze 1 and Freeze 2 differ by one enum; Informant 1/2/3 differ by one enum; Scan 1/2/3 differ by three numbers. Writing a script per cell would have meant fifteen near-identical files whose differences were invisible without opening each one — instead the tier ladder is legible in the inspector, and rebalancing one is an edit to a `.tscn`. This is the same reasoning as `Sanction` being "the one and only Sanction class".

**`EventTargetUnit` carries two knobs, and they are deliberately different questions.** `scope` (OWN / ANY) is WHOSE units may be picked — authored per sanction scene, which is exactly what lets one `EventFreeze` serve Freeze 1 (your own, a save) and Freeze 2 (anyone). `_qualifies()` is WHAT ELSE must be true, overridden by the subclass for conditions only it knows about.

**A single-target cast is aimed at a UNIT, not at a point.** While one is armed the cursor looks
for the unit under it — the same selection-shape raycast that picks units for selection — and
takes the first one along the ray the sanction ACCEPTS (`EventTargetUnit.accepts`: a live unit,
inside `scope`, passing `_qualifies`). That unit wears a `TargetIndicator`, and it is the unit
the order names (`EventTargetUnit.target_unit`). No area is drawn: there is nothing an area
would describe. Pointing at nothing it accepts gives nothing to cast on, so the order is not
issued, the sanction stays armed, and **no charge is spent** — `UseSanction` refuses it
(`NO_VALID_TARGET`), and `Sanction.activate` refuses again at landing if the unit has died or
stopped qualifying since.

This SUPERSEDES the radius search that used to resolve the cast: the event took the nearest
qualifying unit within 3 of the click. Two things were wrong with it. The armed cursor drew a
circle for it (the sanction's `effect_radius`, which for these was the bot's scoring default
and not even the 3), so the player saw a reach that did not exist; and a click that found
nobody still spent the charge. "An ineligible unit is not a candidate" survives unchanged —
it is now the cursor's filter rather than the event's search, so pointing into a mixed group
still lands on the unit the sanction can act on. Tests: `tests/test_SingleUnitCast.gd`,
`tests/test_SanctionPayloads.gd`.

**What a single-target cast is, is DERIVED:** a sanction whose event is an `EventTargetUnit`
(`Sanction.targets_one_unit`). A later single-target ability joins by extending that class, and
gets the cursor, the marker, the refusal and the missing ring with no further wiring. Casts
that could affect several units are out of scope; nothing here generalises to them yet.

**The bot cannot cast these yet.** `BotSanction` aims every sanction at a POINT, and a point
names no unit, so `UseSanction` now refuses its Promotion and Freeze orders outright — which at
least stops the charges it used to waste on enemy clusters. TODO: a bot policy that names a
unit (see `gdd/systems/ai/bot-roadmap.md` §The gaps in the decision surface).

## Freeze is a stun with a shield

`FreezeStatusEffect` extends `StunStatusEffect` rather than reimplementing the stop, because the stop IS a stun: `Actor.is_stunned()` looks for that class. What it adds is a CRYO shield of ice; the rules are [combat/shields](../../combat/shields.md) §Freeze.

`can_freeze()` is a STATIC so the sanction can ask exactly the question the effect will ask, which is what keeps "not a candidate" and "refused on apply" from disagreeing. The Freeze event admits structures as well as units (`EventTargetUnit._admits_structures`).

## Two sanctions that break the usual shape


- **Global EMP ignores its aim point entirely.** It stuns every MECH unit on the map, both sides included, and the asymmetry IS the mechanic: a stun only takes hold on a MECH frame, and the Anarchists are the infantry faction, so the side firing it pays almost nothing while a vehicle-heavy opponent stops dead. Sparing the caster's own machines would hand them that for free and erase the one real cost of fielding vehicles as this faction. It is also the one sanction whose `needs_vision` gate is meaningless, so it authors it off. Units only, not structures — widening it would silence turrets and production at once.
- **Overcharge is worth nothing on its own.** Being already disabled is an admission test on the CANDIDATE, not a damage bonus, so pointing at a unit that is not EMP'd targets nothing at all. `EmpStatusEffect.is_emped()` is the test, not `is_stunned()`: a frozen or bio-stunned unit is just as helpless, but Overcharge is the EMP's follow-through and nothing else's (decided 2026-10-05). Flat damage rather than a fraction of max HP: the pairing already guarantees the target cannot escape, so scaling to its size would make the combination an unconditional kill on anything.

## Scan 3 needed no new entity, and Scout grew one tick


The Scan family is one event (`EventRadarScan`) with three sets of exports. Scan 3's "hovering unit that floats above the designated position indefinitely ... uncommandable" is a `Scout` with `lifespan_frames < 0`.

**The Scout is a real, attackable piece** (`gdd/factions/neutral/units/nt_aircraftLight_recon.md` — 50 HP, LIGHT armour, MECH frame, HOVERING). It used to be a bare `Entity` with no `Defense` and no `Hurtbox`, which made it UNKILLABLE: aggro filters on `t is Actor`, so nothing could ever shoot one and a permanent Scan 3 eye was an unanswerable, cost-free reveal. Three things carry that:

- **HOVERING is not about travel** — it is what puts the drone on the `TARGETABLE_AIR` layer (see `Entity._apply_targetable_layers`), so it needs a `Movement` to be shootable at all. `speed: ZERO` is what keeps it where the sanction put it.
- **It cannot be ordered because it cannot be SELECTED** — `Selectable.selectable_by_player = false`. Godot cannot remove a node inherited from a base scene, so the component is unavoidable; the flag switches it off, refused at `select()`, the one choke point both the click path (`RTSController.set_selection`) and the box drag go through.

  **Doing this by clearing the Selectable's `collision_layer` instead is wrong twice over**, and both ways bit. The SELECTION layer is what the CURSOR picks against (`get_cursor_target`), so a layerless Selectable also became impossible to RIGHT-CLICK — the drone could not be attacked, which was the entire point of giving it hit points. And it did not even achieve the goal: box-select reads the `"selectables"` GROUP rather than the layer, so a drag still caught it. An unselectable piece must stay pickable.
- **`Commander.has_anything_in_play()` skips unreachable pieces.** The old rule excluded the Scout for being a non-Actor; the exclusion moved to what was doing the real work — a piece the player cannot command cannot be what is keeping them in the game. Otherwise a drone in a far corner would force the opponent to hunt it to finish a decided match. Tests: `tests/test_ReconDrone.gd`.

What DID have to be built is stealth detection. The detection tick lives in `Actor._update_state`, and a `Scout` is an `Entity`, so a `DetectionRange` child alone would sit inert — `Scout._detect_stealthed_units` mirrors it against the same STEALTH collision layer, so a scan reveals precisely what a unit standing there would. The shape is CREATED by the event rather than shipped disabled on `scout.tscn`, so Scan 1 genuinely has no detector and skips the query entirely rather than running a disabled one.

**A new cell is priced at a placeholder 500 dominion; a cell that already had a hand-set price KEEPS it.** Every Colonial cell is 500 because the whole grid was new. The Anarchists' three real payloads predate the grid, are reachable in the shipped prologue scenarios, and stayed at 100 / 100 / 250 — repricing a working, playable sanction is a balance change, not stubbing, and stubbing is what filling in a grid is. The result is deliberately uneven between the factions, and the placeholder is the thing to fix: neither grid is balanced yet.

---
