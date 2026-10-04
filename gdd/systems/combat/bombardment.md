---
title: Bombardment
type: system-note
---

# Bombardment

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The Colonial bombardment system


A **Bombard** (`cl_defense_antiStructure`) is a siege gun whose reach is **not distance but VISION BY PROXY**: it can drop a shell anywhere on the map, provided its own side is SPOTTING the ground. That inversion is the whole design — the gun is worth nothing alone and everything beside a spotter, and the counter to a battery is to kill what is spotting for it rather than to out-range it.

### The Bombard has no weapon, and that is the point

It carries **no `Loadout` and `aggro: 0`**. It never picks a target and never fires on its own; every shot is a `command_bombard` order at a point the player chose. A `Weapon` would have brought an `AttackRange`, an aggro pickup and automatic firing with it — all three wrong for this piece.

### The battery is an ABILITY, not a component

It used to be a `Bombards` component whose whole content was a cooldown and a projectile scene, driven by one command. **That is what an ability already is**, so the component is gone: the reload is a pool of ONE charge on the gun (`abilities: [{cooldown: 5, grants: [bombard]}]`) and the shell is the ability's `emits:`. The charge still belongs to the GUN rather than to the command, which is what a charge pool is for — it keeps running while the structure is idle and is not reset by re-issuing the order.

**What did NOT fold in is `BombardTargeting`** — the spotting rule and its two solution sources, below. That is the interesting half of this system and it never depended on the battery being its own type.

The `bombard` ability is the worked example of an ability that is **not a sanction**. "Sanction" now means exactly one thing — unlocked with dominion, through the sanction grid — and this one is unlocked by nothing: owning the gun is the whole of it. See [the sanction grid](../macroeconomics/sanctions/sanction-grid.md).

**`command_bombard` survives as its own command-grid button**, and gaining an ability slot did not replace it. The two surfaces answer different questions: the command grid is what THIS SELECTION can be ordered to do, and the bar is what the COMMANDER can reach for without first finding a caster on the map. Folding the grid button away would have left a selected Bombard with no button and no hotkey, which is a regression rather than a simplification — so this fold is a refactor of the component, and the ability slot the gun also gains is the bar button that `hud_button: true` grants it.

### Two ways ground becomes bombardable

| | What it is | Lifetime | Spent by a shot? |
| --- | --- | --- | --- |
| **`Beacon`** (an Entity) | a firing solution someone placed — on the ground, or riding on a unit | until spent, or a timer | **yes** — claimed when fired on, dismissed when the shell lands |
| **`BeaconRange`** (a component) | a persistent bubble around a carrier | while the carrier lives | **no** |

`BombardTargeting` is the single place both are asked about, read by the command's precondition, by its firing, and by the cursor. Carriers today: the Bombard itself (r=20, so a lone battery covers its own approaches), the Watch Tower (`cl_defense_antiLight`, r=12 — cheap, low-tech spotting that makes the tower network the Bombard's eyes near home) and the Reverence spotter aircraft (r=5, a mobile solution flown to wherever the guns are needed).

Aiming at ground nobody spots fails with its own `PreconditionFailureCause.TARGET_NOT_SPOTTED` — not `INVALID_PLACEMENT`, which is about a structure's footprint and drives the build-preview ghost. Sharing that cause would have told the player their PLACEMENT was bad when the problem is that they have no eyes on the target. The cursor turns invalid and the error line reads "No eyes on that ground"; `tests/test_BombardCursor.gd` pins the whole chain, because a cause with no message entry, or a resolution that collapses to null, both end as a normal cursor over an illegal target.

**Ranges are preferred over beacons** (`source_at` returns null for range-covered ground). Spending a beacon the player walked a Recruit across the map to place, when a free solution already covered the spot, would silently burn the more expensive of the two resources.

`BeaconRange` is a plain radius rather than a `CollisionShape3D` like `VisionRange`/`AggroRange`: the only question ever asked is "is this point within r", which is one distance comparison, and it is measured **on XZ** so an aircraft spots the ground beneath it rather than a sphere.

### Spotting is a commitment, which is why it is a command

`Spot` (on any unit with a `Spotter`; the Recruit today) walks to within `target_range`, holds still for `channel_ticks`, raises a `Beacon` — and then **stays on it** until a Bombard spends it. Three consequences, each load-bearing:

- **It does not end when the beacon goes up** (`fulfill_action` returns self). A command that completed there would let the unit walk on to its next queued order while its solution still stood, which is exactly the commitment being sold.
- **Queued orders therefore wait for the SHOT**, not for the placement — "spot here, then fall back" is one order given once.
- **Being re-ordered withdraws the beacon** (`on_released`). A solution belongs to the unit holding it; leaving one behind would let a player place beacons for free by re-tasking the spotter.

**Spotting a unit tags it.** A Spot ordered onto an enemy that can carry a beacon (`Beacon.can_carry`: a grounded MECH unit — never BIO, never an aircraft, never a structure) walks after that unit, channels, and attaches the beacon to it. Any other target — a soldier, a friendly tank — gets an ordinary point beacon where it stood. **The leash:** a beacon riding on a unit stands only while the carrier stays within the spotter's `TARGET_RANGE`; a carrier that drives out of it drops the beacon (`Spot._hold_leash`). That is what makes tagging a fast target a breakable, stealth-adjacent game rather than a guaranteed hit.

`MoveCommand.on_released(actor)` was added for that last one. It fires from `CommandReceiver`'s `_command` setter at the same moment the group-move speed cap is released — when the command has genuinely LEFT the receiver, **not** when an interrupt has merely displaced it into the queue it will resume from. Deliberately not `_notification(PREDELETE)`: a destructor runs whenever the last reference happens to drop, which for a unit dying mid-command is during its own teardown, where reading the actor's components dereferences freed memory (see `_release_speed_cap` for the segfault that taught us).

**`Spot._beacon_raised` is not redundant with `_beacon != null`, and conflating them made the command immortal.** A FREED object compares equal to null in Godot, so once a shot spent the beacon the reference read as "never placed one" and the command fell back to its still-channelling branch forever. The flag records that the work happened; the reference records whether the beacon is still standing.

### Beacons

`Beacon` is an Entity rather than a marker Resource so it can be OWNED (the strike check is per-commander), can carry vision through the ordinary fog path, and can be found by a group scan with no registry to keep in step. Like `Scout` it has no `Defense`, `Selectable` or `Hurtbox`, so it cannot be shot, clicked or ordered — you kill a beacon by killing its spotter.

`dismiss()` is the one way out for every reason (spent, expired, cancelled), because every caller wants the same two things — the `spent` signal, then the free — and a second path would eventually forget one. It is idempotent, so a shot and an expiry on the same frame cannot double-notify.

Its look is a small team-tinted sphere on a `MeshVisual`, which is how every other piece is coloured: `Entity._apply_team_tint` finds that component off the `commander_changed` signal, so the beacon shows whose it is with no code of its own.

**A beacon is stealthed to opponents.** It carries a `Stealth` component and a `StealthBody` (a small `StaticBody3D` on the STEALTH layer only — a shape on the root would have made the beacon a movement obstruction), so an ordinary detector or a Radar Scan finds it the way it finds a stealthed unit. `Beacon` ticks the stealth itself, since a beacon is not a Commandable, and draws for the LOCAL player: hidden from an opponent while STEALTHED, faint while REVEALED, always drawn for its owner's side.

**Fog hides a beacon too.** An opponent sees it only when it is out of their fog AND not
stealthed, and a fogged beacon is untargetable by that opponent. See
[piece-vocabulary](../authoring/piece-vocabulary.md) §Where today's code disagrees.

**A heal takes it off.** Any heal that lands on a carrier — a repair, a heal aura, anything that goes through `Defense.restore` — dismisses every enemy beacon riding on it, even when the carrier is whole, so a heal on an undamaged unit still clears a beacon its owner cannot see. A staggered piece cannot be healed, so it cannot shed one either.

**Riding on a unit.** `attach_to` makes a beacon follow its carrier every physics tick. A carrier that dies, or leaves the map (garrisons), leaves the beacon standing where it last was, as an ordinary point beacon.

**Claimed, then spent.** A shot fired on a beacon MARKS it used (`mark_used`): `BombardTargeting.beacon_at` skips a used beacon, so a second battery cannot claim one a shell is already coming for, and the beacon stands for the whole flight so the shell can track it. It is dismissed when the shell hands over from its flight phase, or leaves play (`dismiss_on_landing`, method callables so a shell outliving its beacon never calls into a freed node). The owner's side sees the used state (`MeshVisual/UsedMarker`); an opponent sees no change at all.

The **Beacon Drop sanction** (`EventDeployBeacon`, Colonial column 3) places the same entity, so the Bombard never learns which route made a solution. A drop landing within `Beacon.ATTACH_RADIUS` of an enemy unit that can carry one attaches to the nearest such unit. The tiers differ only in lifespan and sight: 15s blind → 15s with sight radius 2 → permanent with sight. Sight is a `VisionRange` created by the event rather than shipped disabled, so a blind beacon genuinely has no vision node — the same reasoning as `EventRadarScan`'s detection shape.

### The shell follows its solution

Fired on a **beacon**, the shell is launched at the beacon ENTITY (`Emitter.launch` pursuing it) rather than at a point, and the `cannon_shell` flight phase authors `tracks_goal = true`: every tick the fall is left alone and the horizontal velocity is re-aimed so the shell crosses the beacon's height over the beacon (`EmissionPhase.tracked_velocity`). The flight time is solved from the live vertical velocity with the same integrator the flight uses, so re-aiming never lengthens the flight — the shell lands when it would have, wherever the beacon has got to. If the beacon leaves play first, the pursuit falls back to where it was last seen, and the shell lands there.

Fired on ground a **`BeaconRange`** covers, the shell is launched at the point: area spotting places no beacon, so nothing homes.

The re-aim is unbounded today — the quickest version that follows. TODO: how far a shell may turn, and so whether a fast carrier can out-drive a long shot, is the Bombard's open trajectory design ([static-defence](../../design-framework/static-defence.md) §The Bombard). Tests: `tests/test_BeaconOnUnits.gd`.

### The HUD button

`bombard` authors `hud_button: true`, and it is the archetype for that flag: **reach is what earns a bar button.** An ability whose effective range is global cannot be reached by finding its caster on the map, because the player has no reason to be looking there. The button selects every battery that can fire and arms `command_bombard`, leaving one right-click to aim — the same two steps every other bar button performs.

HUD presence used to follow from being dominion-unlocked, which is why this ability had no button before: it conflated the shop with the HUD, and the gun pays no dominion. The flag is authored now, and defaults to false.

### Authoring

Two component keys, each following an existing shape: `beacon: 20` (a radius, like `senses.detection:` — component created on demand) and `spotting: true` (presence is the capability). The gun half is not a component key at all: it is `abilities:`, the same block every other charge-bearing piece uses, and the shell is the ability doc's `emits:`.

Tests: `tests/test_BombardTargeting.gd` (the spotting rule and both sources), `tests/test_Spotting.gd` (the Spot lifecycle), `tests/test_BeaconOnUnits.gd` (carriers, the leash, claiming, secrecy, the tracking shell).

---
