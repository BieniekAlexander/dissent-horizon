---
title: Rearm and resupply
type: system-note
---

# Rearm and resupply

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The flight: `Rearm`


One command owns the whole sequence, because every stage is conditional on the one before and there is only one thing driving the aircraft. `Rearm.DockState` is that sequence:

`APPROACH → DESCEND → TAXI_IN → DOCKED → TAXI_OUT → ASCEND`

## Breaking off and resuming


Running dry is handled in TWO steps, per tick, ahead of the idle-aggro check. Splitting them is the point: what an empty unit must GIVE UP is a different question from where it should GO.

**`Commandable._defer_unshootable_orders` — stand down what you cannot do.** An order that exists in order to shoot (`MoveCommand.requires_ammo()`: `Attack`, `AttackMove`, `Defend`) is pushed to the FRONT of the queue by `CommandReceiver.defer_ammo_dependent_commands` and stops being driven.

**DEFERRED, NOT DISCARDED**, and that distinction is the whole design: an Attack or a Defend the player gave is still what they want done, it is just not something this unit can do this minute. Pushing it into the queue BEFORE clearing `_command` is what makes it an interrupt rather than a release — the `_command` setter only fires `on_released` for a command that is NOT in the queue, which is exactly the line it draws. Only the ACTIVE order is stood down; anything already queued was never being driven. This runs **unconditionally**, before any question of where to rearm: an order it cannot carry out is worth stopping whether or not it owns an airfield to go home to. Ordinary units never notice, since `is_out_of_ammo()` is false for a loadout with nothing CHARGED in it.

**`Docking.maybe_auto_rearm` — go home only when there is nothing else worth doing.** It PREPENDS a `Rearm` when the loadout is dry and `CommandReceiver.awaiting_only_ammo_dependent_work()` holds. Prepending is what makes the resume free: the order just stood down sits behind it, so when the rearm ends the receiver pops it straight back — a Defend interrupted for want of ammunition flies home, refills, and returns to its post with the player having ordered only the first thing.

`awaiting_only_ammo_dependent_work()` is deliberately neither of the two obvious tests. Not `is_idle()`: a just-deferred order IS in the queue, so the unit is not idle and must still rearm. Not "no active command": a plain move waiting to be popped is real work, and a Rearm in front of it would override an order the player gave. **A plain move is kept and obeyed** — that is the line `requires_ammo()` draws, an order that assumes an attack against one that merely goes somewhere — and the aircraft takes itself home when it gets there. Three further gates keep the rearm from misfiring: not already rearming, a bay that admits us, and not already parked on one.

**A PARKED unit picks up no aggro and orders no rearm.** It is sitting on its own airfield with its vision still live, so without the gate (`Docking.is_on_deck()`) it would latch onto anything that wandered past and take off after it — which is not what "stays in its dock until ordered" means.

Manual orders come from the grid button at cell (1, 2) — beside Land, the other airframe ability — or from right-clicking a friendly airfield. In the right-click ladder `Rearm` sits **above `Occupy`** (an airfield may also garrison, and an aircraft clicking its own airfield means "go and reload") and **below `Repair`**, on the same reasoning that puts Repair above Occupy.

## Authoring


`dive: true` on a weapon marks the ramming airframe (`Weapon.dive_attack`); everything else shoots from cruise altitude. `charged: true` on a weapon in the piece's gdd doc; the importer syncs it to the scene and derives `needs_docking` on the tool from it, which is what lets the HUD run the capacity gate every frame without instantiating unit scenes. The unit needs `docking: true` (and so `aerial:`, either mode) — the importer refuses a charged weapon without it — and its `reload_time` is now a DOCKED time rather than a between-clips time, which is usually worth rebalancing when the flag goes on.

Tests: `tests/test_ChargedAmmo.gd` (the ammo model), `tests/test_AerialAttackRun.gd` (the attack run, the aim arc, and the empty-loadout policy), `tests/test_DockingBay.gd` (pads, admission, capacity, rolling out onto a pad, and the taxi steps driven directly), `tests/test_AerialDocking.gd` (the landing regime for both modes, driven by calling `_physics_process` directly — the state machine is pure altitude bookkeeping and consults no Map). `Rearm`'s sequence END TO END still has no GUT coverage: it needs a live NavigationServer and a real Map. **`tools/rearm_probe.gd` and `tools/attack_probe.gd` are what exercise it** — the second flies a whole attack run and prints every term `Attack.can_act` is built from, with `--moving-target` for the case a stationary one cannot reproduce (see the aim arc above). `rearm_probe` — it boots a flat test scenario, drops an airfield and one aircraft on it, and prints the whole flight tick by tick (DockState, LandingState, height, distance to pad, clip). Reach for it before changing anything in this section; it is how the taxi was built and how the split-timer bug below was seen from the outside.

---
