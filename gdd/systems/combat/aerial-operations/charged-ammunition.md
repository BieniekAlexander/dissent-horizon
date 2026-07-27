---
title: Charged ammunition
type: system-note
---

# Charged ammunition

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*


Some weapons do not reload on their own: they empty and stay empty until something recharges them. Today that something is an airfield, and the aircraft flies there itself — the Command & Conquer loop. The mechanic is **two independent halves**, and keeping them independent is the point: the ammo model does not know an airfield exists, so a later non-airfield resupply (a supply truck, a repair drone, an ability) reuses it unchanged.

**Where the two halves meet is the piece, not the weapon.** `charged` says only that the clip is
refilled from outside; nothing on the weapon names the source. The source is the piece's
`Docking` component (`docking: true` in its doc), and three things join them: the importer
refuses a charged weapon on a piece without `docking: true`
(`SpecRegistry._validate_charged_can_rearm`); `Docking.maybe_auto_rearm` takes a dry piece home;
and `DockingBay.tick_recharge` refills whatever is parked on its pads. A second resupply source
would widen the first of those to "`docking: true` or the other source" rather than touch the
weapon.

## The ammo half: `Weapon.charged`


`charged` (a bool on `Weapon`) means "this clip is refilled from outside, never by the passage of time". `Weapon._physics_process` simply does not run the reload countdown for one, so `is_ready()` stays false once the clip is spent and `Attack._own_weapon_can_fire` fails — the attack command stays live and the unit holds, which is what gives the auto-rearm below something to notice.

**The rate is the SAME `reload_time` an ordinary weapon uses, meaning the same thing: ticks for a full clip.** So both kinds of weapon are balanced against one number, and setting `charged` changes WHERE the reload happens rather than how long it takes. What being charged actually costs is the flight home, which is the mechanic. `_validate_property` therefore stops pinning `reload_time` to `split_time` for a single-round clip when `charged` is set — that pin would make such an aircraft rearm instantly.

`recharge(ticks)` banks **TICKS, not fractional rounds**, and that is not a style choice. Accumulating `clip_size / reload_time` per tick drifts: sixty additions of 10/60 sum to 9.999999, which floors to nine and leaves the weapon permanently one round short of full while it sits on the pad. Adding 1.0 sixty times is exact in binary floating point, and the single division to `ticks_per_round` happens once. `CHARGE_EPSILON` absorbs the residue from a rate that does not divide evenly (a bay `charge_rate` of 1.5).

`Loadout` asks the two questions the rest of the system needs, and they are **deliberately different strengths**:

| | True when | Read by |
| --- | --- | --- |
| `needs_recharge()` | ANY charged weapon is below a full clip | the docking sequence — how long to sit on the pad |
| `is_out_of_ammo()` | EVERY charged weapon is dry (and there is one) | auto-rearm — when to break off |

A unit that can still shoot something finishes its order, so only a fully dry one sends itself home; but a partly-empty one the player ORDERED to an airfield still has something worth topping up. Both report false for a loadout with nothing charged, which is what keeps the per-tick auto-rearm check off every ordinary unit in the game.

## `_split_timer` is clamped at zero, and `is_ready()` is why


`Weapon.is_ready()` asks for `_split_timer == 0` — EXACTLY zero — so the countdown must
stop there rather than running on into negatives. A weapon that comes up ready and has
nothing to shoot at has to STAY ready.

An ordinary weapon survived an unclamped countdown by accident: its reload branch resets
`_split_timer = 0` every `reload_time` ticks, so it recovered on its own within a clip and
the fault showed only as an occasional delay before opening fire. **A CHARGED weapon never
reaches that branch** — `_physics_process` returns two lines above it, because a charged
clip must not refill on a timer — so its timer went negative once and never came back. The
Drake sat holding four rockets it could not fire: full clip, no projectile, no ammo spent,
and nothing anywhere reporting a problem. It looked like a targeting bug, or like the bot
not issuing attack orders, and it was neither.

The clamp lives at the decrement, so it is true every tick for every weapon.
`recharge()` used to raise the timer to zero itself for exactly this reason; that line is
gone, and the rule it was standing in for is now stated once. Tests:
`test_ChargedAmmo.gd::test_a_charged_weapon_stays_ready_while_it_waits_for_a_target`.
