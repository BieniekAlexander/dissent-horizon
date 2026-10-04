---
title: Attack runs
type: system-note
---

# Attack runs

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The attack run: a fixed wing never stops, and only a rammer dives


Three rules, and they were tangled together because two of them keyed off
`Movement.Mode.FLYING` when neither is really about locomotion.

**A ranged aircraft drops its payload at cruise altitude.** `Attack._dive_contact_made`
withholds a shot until the attacker has descended to within its own reach — right for a
drone that kills by flying INTO its victim, and wrong for everything else. It used to apply
to any FLYING attacker, so a rocket aircraft sitting at `AERIAL_HEIGHT` over its target
could never satisfy it — invisibly and totally, since `should_move` goes false the moment the
tall cylinder reports in-range, so the aircraft halted over its victim with the check false
forever and nothing to make it descend.

**The gate is the WEAPON'S REACH** (`Weapon.is_melee_ranged`): a weapon that only reaches as
far as the airframe's own body is one that kills by arriving. That REPLACED an authored
`Weapon.dive_attack` flag (`dive: true`), which said the same thing twice and could disagree
with itself. It is NOT inferred from "has no projectile": the kamikaze's bomb IS a projectile,
so that test would have switched the dive off for the only unit that needs it.

**A held post is LATCHED, not re-tested.** `Defend._on_station` is set the first time the unit reaches its post and cleared only if the post itself moves. A live "am I within arrival distance" test flickers for an aircraft, which circles rather than standing: the orbit carries it out, `should_move` goes true, the receiver drives it back at CRUISE speed, it arrives, the orbit pushes it out again. The unit ends up scything around its post at full speed instead of loitering over it. Latched, the orbit owns it from arrival and holds it at `orbit_speed` on `orbit_radius` — measured at 1.50 and 3.02, which is the same circuit an idle aircraft flies. A ground unit is unaffected: `should_move` false still means "stand still".

**A fixed wing does not stop, full stop — including when it is holding a post.** An actor
that acts with nowhere to go flies a circuit over the spot instead of halting on it
(`CommandReceiver`'s act branch, final `elif`), anchored on the command's own position. A
plain move already got this for free: it ENDS on arrival, so it falls through to the arrival
branch that sets the anchor and hands over to `compute_orbit_velocity`. `Defend` does not
end — that is the point of a post — and its `can_act` goes true the moment the unit arrives,
which is tested BEFORE `should_move`. So an aircraft on station fell between the two
branches and coasted to a halt in mid-air, while the same aircraft given a plain move to the
same point orbited it correctly. The orbit is safe for the docking states, which also act
without wanting movement: `compute_orbit_velocity` returns zero while a unit is not AIRBORNE
and `set_velocity` is ignored while it is landing or parked.

**A fixed wing does not stop to shoot.** `Movement.can_hold_still()` is false for FLYING and
true for everything else — a gunship holds station, an aeroplane cannot. Two places read it:
`Attack.should_move` returns true regardless of range for such an actor, and
`CommandReceiver` drives it onward instead of zeroing its velocity when it acts. So the
aircraft flies at its target, fires as it closes, passes over and comes around. The overshoot
IS the attack run.

**Those two together were a total, silent stall.** `should_move` went false the moment the
tall AttackRange cylinder reported "in range", so the aircraft halted; `_dive_contact_made`
was false because nothing was bringing it down; and with the clip empty it was in a state
that was neither acting nor moving, so nothing drove it at all. It sat over its victim,
loaded and facing it, forever. The reach happening to EQUAL `AERIAL_HEIGHT` made it worse
than a clean refusal: the comparison sat on a knife edge and tipped on a fractional scale
drift in the range shape's transform, so the same unit fired or did not depending on
rounding.

**An aerial unit on the ground cannot shoot at all.** `Commandable.can_use_weapons()` is
false for an aerial unit that is not `is_airborne()` — a helicopter set down in a field, a
jet parked on its pad or rolling down a runway, one still in its climb-out or its final.
None of them are fighting, and a parked aircraft cutting down whatever wandered past its
hangar reads as a turret rather than an aeroplane.

It is also the other half of a bargain the targeting rules already struck: a grounded
aircraft is shot at with a weapon's GROUND range (`Weapon.get_range_for_target`),
deliberately, so that it is not untouchable while it sits there. Being harmless in return is
what makes that fair.

Three places read it, so a grounded aircraft neither fires, retaliates, nor goes looking:
`Attack._own_weapon_can_fire`, `Commandable._get_vision_range_attack`, and the idle-aggro
pickup — which used to be gated on the narrower "parked" test and so missed a hover unit
landed in a field. Ground units and turrets are untouched: neither carries an `Aerial`.

## Pitch and roll go on the ART; only yaw goes on the body

`Aerial._attitude_node` returns the `MeshVisual`, not the owner, and that is deliberate.

The owner is the `CharacterBody3D`, and its children include `MovementBody`, `Hurtbox`,
the two aggro volumes, `VisionRange` and the Loadout's `AttackRange` — range shapes that are
100-unit-tall cylinders. **Leaning the owner swung their ground-level footprint several
world units away from the unit**: a Petrel at full nose-down displaced its aggro and vision
discs by ~2.8 units and its firing envelope by ~2.7, so a unit's reach shifted back and
forth with its own speed and turns.

**Yaw stays on the owner because facing is REAL** — `get_facing()`, weapon aiming and the
movement direction all read it. Pitch and roll are decoration. `MeshVisual` is a child of
the owner and so inherits yaw, which is why writing `rotation.x`/`.z` on it is still pitch
about the body's lateral axis and roll about its longitudinal one. A unit with no
`MeshVisual` (billboard art, a unit test) simply does not lean, which is right: there is no
model to lean.

## A dive commits on TIME, not on distance

`Aerial._dive_commit_distance` is the horizontal range at which a FLYING unit must nose
over to still reach its target's altitude in time. `dive_distance` alone is speed-blind — a
unit twice as fast gets half the seconds to shed the same altitude and arrives high — so the
distance returned is the ground the unit covers, at its CURRENT speed, during the descent a
full cruise altitude needs (the ramp into the rate cap, plus the run at it). `dive_distance`
is the authored FLOOR, so a slow unit still commits where it was authored to and a fast one
commits earlier instead of overshooting.

It is computed from `AERIAL_HEIGHT` rather than the CURRENT altitude deliberately, so the
answer does not shrink as the unit descends — a distance that moved under the unit mid-dive
would flip it in and out of the commit window. Overshooting past it for real (a miss) does
un-commit, which is what sends the unit climbing to come around again.

## A stationary attacker aims itself, and has to zero its own velocity to do it

`Attack._update_facing` turns the actor's body toward its target once `should_move()` goes
false. For a weapon without a turret (see [turrets](../turrets.md)), aiming IS `rotation.y` — the same value
`Movement.face_toward` / `get_facing()` drive. While the actor is still CLOSING, movement's
own turn-toward-heading owns that value instead, and letting both write it on one tick would
be redundant anyway: the two directions agree while approaching.

**It zeroes velocity explicitly, and that is the load-bearing half.** Once `should_move()` is
false, `CommandReceiver` stops calling `set_velocity` for the actor entirely — neither the
`should_move` branch nor the post-`fulfill_action` cleanup runs while it is merely waiting to
align. So without an explicit zero, the `NavigationAgent3D` avoidance sim keeps re-simulating
the LAST requested velocity — the approach velocity from before it arrived — every tick, and
`Movement._apply_grounded_turn` keeps rotating the body toward that stale heading, fighting
`face_toward`. That is what left units stuck mid-turn, never finishing their aim.

**A unit that AIMS BY FLYING shoots within an arc, not on a hair.** `Movement.is_facing()`
holds an attacker to `_FACING_ALIGNMENT_EPSILON` — 0.001 rad, about a twentieth of a degree
— which is fair for anything that turns to aim and then STOPS, because it converges exactly.
An aeroplane never stops turning: its facing is a by-product of the velocity it is being
steered along, so against a target that MOVES its nose lags the bearing permanently and
never converges at all. Measured on a Drake attacking a tank crossing its path, that lag sat
at **0.2°** the whole way in — dead-on to look at, four times the tolerance — and the
aircraft flew the entire run, in range and loaded, without firing a shot. `Attack` now asks
`_is_aimed_at_target`, which keeps the hair for anything that `can_hold_still()` and gives
everything else `FLYING_AIM_ARC_DEGREES` (20°): wide enough that steering lag never denies a
shot, narrow enough that the aircraft still visibly points at what it is shooting.

This was the LAST of the three things stopping aircraft firing, and the one that survived
the other two fixes — a straight-line run at a stationary target satisfies the strict test
trivially, which is exactly why it took a moving target to reproduce.

**A course reversal has no side to turn to, and `Vector3.slerp` cannot pick one.** Slerp
builds its rotation axis from the cross product of the two headings, which is ZERO for
exactly opposite vectors — so a unit asked to turn 180° got its own heading back and flew
straight on at full speed, forever. That is not a corner case: an aircraft that has just
overflown its target and is sent home to an airfield BEHIND it asks for precisely 180°,
every time, and the Drake flew off the map instead of coming around.
`Movement._turn_heading_toward` uses a SIGNED 2D angle on XZ instead, which is well defined
at PI (it reports +PI), so the reversal resolves to a definite bank. Which way it goes at
exactly 180° is arbitrary — there is no better side — but it is decided rather than left to
numerical noise. Tests: `tests/test_AerialAttackRun.gd`, `tests/test_AerialDocking.gd`.
