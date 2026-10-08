---
title: Runways
type: system-note
---

# Runways

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Runways are LINES, and direction is the whole point


A `Runway` (`scripts/entities/components/runway.gd`) is a `Marker3D` child of a `DockingBay`. Its **own position is the takeoff point** — the threshold an aircraft climbs out from and touches down on — and the strip runs from there along the marker's forward axis for `length`. Placing one is "drop a marker at the end of the tarmac and point it down the strip", the same gesture as placing a `DockingPad`. An airfield may carry several; `runway_for(pad)` picks the one whose line passes closest to that pad, so the roll out and the roll back use the same strip and the shortest.

Everything is stated relative to the threshold, which is why it is the marker rather than the middle:

| | Path |
| --- | --- |
| **Departing** | pad → `nearest_point(pad)` on the strip → `takeoff_point()` → climb |
| **Arriving** | `approach_point(run)` on the extended centreline → descend along the strip → `takeoff_point()` → `nearest_point(pad)` → pad |

**The approach fix is what makes an arrival an approach.** `Rearm._approach_position` returns a point out BEYOND the threshold on the extended centreline, and the APPROACH flies there rather than at the airfield. Only then does the descent start, so the aircraft is already lined up and comes down ALONG the strip. Aiming the descent at the threshold from wherever the aircraft happened to be let it cross the runway, or meet it back to front.

**The fix is a LINEUP LEG, not a glide budget** (`_lineup_distance`: a couple of turn radii, floored). It used to be a full descent run — the ground covered while shedding cruise altitude at a fixed sink rate — which put it twenty-odd units outside the field and sent anything arriving from the far side on a huge loop around the airfield just to get behind the numbers.

**Committing to the descent is about HEADING, not proximity** (`_is_established_on_final`).
The aircraft may start down only when the threshold is ahead of it along the strip's own
axis, it is inside a corridor either side of the centreline, and it is POINTED down the
strip. Testing distance to the fix alone let one arriving from the far side fly through the
fix at cruise heading directly AWAY from the runway and commit anyway; the descent then had
to turn it 180° while it sank, which is the wide, repeated swinging that reads as an
aircraft unable to find the field. Refused, it simply stays in APPROACH — level, at speed,
with its destination behind it — and comes round in one clean circuit.

**The corridor is scaled to the TURNING CIRCLE** (`FINAL_CORRIDOR_TURNS`), and that is what
makes the gate passable at all. An aircraft that has just come round 180° rolls out a full
turn DIAMETER off the line it started on, so a fixed narrow corridor is one no arrival from
the far side can ever satisfy — it flies past, turns, misses again, and circles forever.
Inside the corridor does not mean "lined up", it means "close enough that the descent can
converge the rest", which it does by steering at the threshold all the way down. Measured
from six directions including directly behind the field: every one touches down within 0.1
units of the threshold.

**It can be short because the DESCENT RATE adapts** (`Aerial._descend_to_touchdown`). The sink rate is derived from the ground still to run — at the current closing speed the aircraft is `dist / speed` seconds from the mark, so it sheds `height / that` per second — recomputed every tick. A slower or faster final changes the glide ANGLE instead of moving the touchdown point, which is what "land at the end of the runway" has to mean. The old model did it the other way round, capping horizontal speed to match a fixed sink rate, and any mismatch came out as touching down early, on open ground short of the tarmac. Measured on the Sky Port: touchdown within 0.1 units of the threshold, on the centreline. Setting down in a FIELD keeps the old cap, since there is no mark to hit.

`MoveCommand.movement_destination()` is the seam that allows it: a command may name a destination its `message.target` does not imply, and `CommandReceiver._resolve_movement_target` asks before doing anything else.

**The taxi is `Aerial.taxi_along(path, on_complete)`** — one ground drive, used by both halves so they cannot drift apart, with `LandingState.TAXIING` while it runs. It writes POSITION, not velocity: a commanded velocity is suppressed outright while a unit is on the deck, so a velocity handed to a taxiing aircraft goes nowhere. Y is left alone — `Actor` rewrites it from the terrain every tick.

**Turning and rolling are separate actions.** On the ground an aircraft is a vehicle with a nosewheel: it stops, swings the nose round to point at the next waypoint (`TAXI_FACING_EPSILON`), and only then drives. Doing both at once slid it diagonally across the apron, which is the one thing an aeroplane cannot do. A parked, idle aircraft meanwhile points itself at its taxiway (`Docking.aim_parked_at_runway`), so that turn is already made when an order arrives.

**The apron is a crawl; the last leg of a DEPARTURE is a takeoff roll.** `taxi_along`'s `roll_from` marks the legs where the aircraft opens up toward flight speed instead of taxi speed, eased under `max_acceleration`. One that trundled to the threshold at taxi speed and then jumped into the air is not taking off; measured, it now leaves the ground at cruise rather than at a third of it.

**But the taxi still carries a VELOCITY**, even though the roll is written as position — because it is what the aircraft is actually doing, and the climb-out reads it as the heading to turn FROM. Without it the turn-rate clamp saw a standing start (`_current_velocity.is_zero_approx()` skips the clamp entirely), took the first commanded direction whole, and a jet leaving the runway snapped through 180°. `_finish_taxi` deliberately does NOT zero it for the same reason.

**One aircraft per strip.** `Runway` carries a claim exactly as `DockingPad` does, and `Docking.release_runway` gives it back once the unit is airborne or parked — one place, covering both directions, so no torn-down order has to remember to clean up. A busy strip is a WAIT, not a refusal: a departing aircraft holds its pad and tries again next tick, an arriving one keeps flying its approach. Deliberately a claim rather than collision — the taxi is a scripted drive along an authored line, so the line settles the question — and it scales the way the airfield does, since a second strip is exactly what lets two aircraft move at once.

**The claim is taken when the aircraft COMMITS to the strip, never while it is still in the air over it.** A departure takes it in `leave_dock`, an arrival at the APPROACH → DESCEND transition. Claiming from the approach instead took the strip while the aircraft was still airborne, and the release rule above handed it straight back on the next tick — so the two fought every frame and a third aircraft could walk off with a strip somebody was landing on. `can_act` therefore only ASKS (`is_free() or claimed_by() == actor`) during the approach.

**A unit waiting for the strip is NOT a unit that has arrived.** `Movement.is_navigation_finished()` reports true for anything `GROUNDED_TEMP`, so `_drive_movement`'s arrival branch would read a parked aircraft that could not roll as having reached its destination and throw its order away. Ordering a flight of four off one strip lost three of them exactly that way; the drive now returns early while the unit is still on its pad.

**A REARM CUT SHORT hands its pad to the unit and leaves the aircraft standing there** (`Rearm.on_released`), rather than lifting it. Whatever order replaced the rearm then takes it off through `leave_dock`, which taxis. Taking off there instead is what made a PART-CHARGED aircraft rise vertically off its parking space and skip the runway, while a fully-charged one — whose rearm had COMPLETED, so that path never ran — taxied out correctly. Interrupted in the air or mid-roll it must still be lifted, since nothing else knows to.

**A departure leaves through `Docking.leave_dock()`, and that is the ONLY way off a pad.** It gives the pad back, then taxis. `update_commands`' take-off branch routes through it too (`is_docked_on_pad()`), because taking off in place there would skip the roll-out entirely — which is exactly what the runways exist to stop.

**A bay with NO runway keeps the old behaviour**: descend straight onto the pad, lift straight off it. That is what every airfield did before the Sky Port's apron gave the drive somewhere to happen, and it is what a HOVERING dock would want in any case — a helicopter has no roll-out to fly. Only `cl_airField` authors a strip today; the other factions' airfields are placeholder art and take the fallback.

**The climb-out may be steered from the first tick.** A commanded velocity is not suppressed during `TAKING_OFF`, and `_tick_flying_landing` only supplies its own heading when nothing else did (`_velocity_commanded`). So a departure under orders turns as soon as it is off the ground rather than holding the runway heading all the way to cruise altitude, while a commandless one still flies rather than stalling.

Three things about it are load-bearing:

- **`ends_on_arrival()` is false.** Arriving is where a rearm starts, not what finishes it — the same override `Build` and `Assemble` need, and without it the receiver drops the command the tick the approach completes, leaving the aircraft hanging over the airfield with nothing to do.
- **`should_move` is not gated on holding a pad.** An aircraft sent to a full airfield has none to reserve yet; standing where the order was given would leave it nowhere near a space when one freed, and would read as the order having been ignored. With no pad it flies at the airfield and waits overhead until `get_updated_state` latches onto one.
- **`_hold_on_pad` pins POSITION, not velocity.** `Movement.set_velocity` is suppressed outright while `GROUNDED_TEMP`, so a zeroed velocity is a no-op in exactly the state that needs holding.
- **Teardown that touches the AIRCRAFT lives in `on_released`, never in `_notification(PREDELETE)`.** Lifting an aircraft off its pad when the order ends is the obvious thing to do in a destructor and it is a SEGFAULT: a RefCounted's destructor fires whenever its last reference drops, which for a unit dying mid-command is inside that unit's own teardown, where `is_instance_valid()` still reports true while the script instance behind `actor.movement` is already gone. `MoveCommand._notification` documents this trap for the group-move speed cap; `Rearm` was the second thing to fall into it, and it took the whole test process down with no GDScript error. PREDELETE now releases the PAD alone — which passes the actor as a plain reference and only compares it (`DockingPad.release`), never dereferencing its script.

## Releasing a runway is one place, both directions

*Moved out of `commandable.gd::_release_runway`.*

The Rearm is PREPENDED, which is what makes the resume free: prepending pushes the
interrupted order onto the front of the queue, so when the rearm ends by returning null
the receiver pops that order straight back. An attack run therefore reads as attack →
fly home → rearm → attack, with the player having ordered only the first of those.

Three gates, and each rules out a distinct way this could misfire:
  * is_out_of_ammo(), not needs_recharge() — a unit that can still shoot SOMETHING
    finishes its order. Only a unit with nothing left to fire breaks off, so a partial
    clip never pulls an aircraft out of a fight it was winning.
  * not already rearming — the check runs every tick, and without this it would prepend
    a fresh Rearm on top of the one currently flying the aircraft home, every tick,
    forever.
  * a bay that admits us — with no airfield standing there is nowhere to go, and
    issuing the order anyway would leave the unit flying at a destroyed building.

An aircraft that does not dock has no `Docking` and so never reaches any of that: a dry
expendable drone simply carries on rather than looking for an airfield it would have no use
for.
Give back a runway once this unit is done with it: airborne (it departed) or parked (it
arrived). ONE PLACE, covering both directions and every way an order can end — an
abandoned approach simply leaves the aircraft in the air, which releases on the next
tick, so no torn-down command has to remember to clean up.
