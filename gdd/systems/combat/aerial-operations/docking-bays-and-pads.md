---
title: Docking bays and pads
type: system-note
---

# Docking bays and pads

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## The airfield half: `DockingBay` + `DockingPad`


**Not a `Garrison`, and the reason is visibility.** A garrison holds occupants as orphaned nodes — out of the tree, out of rendering, out of physics — which is right for infantry in a bunker and wrong for a parked aircraft, which must stay visible on its pad, selectable, and contributing its own vision. The two mechanics share nothing but the word "capacity", and a structure may carry both.

**Capacity is the pad count, never a typed number**: `DockingBay.capacity()` is how many `DockingPad` children the airfield's scene carries, so the number and the visible parking spaces cannot disagree. A pad also carries `deck_height` — the resting height offset — so a raised deck is authored rather than special-cased.

**The markers have to agree with the ART, which is why the Sky Port's mesh is generated to its footprint.** `cl_airField` is 6x4 cells and `sky_port()` in `assets/meshes/generate_colonial_meshes.py` occupies exactly 6 x 4 in Godot's XZ with nothing overhanging — a building whose art spills past its grid cells reads as though it should block ground the game says is walkable. The apron draws one runway down the long axis with two parking squares either side of it, and the scene's `Runway` and `Pad1..4` markers sit on those squares. Once the taxi is real, a marker that does not land on the art is a jet driving across bare tarmac.

`admits` / `has_free_pad` / `accepts` mirror `Garrison`'s trio under the same names, so there is one shape for "may it, is there room, can it now". `admits` requires a piece that docks (a `Docking` component, which only an aircraft may have), the SAME commander (an airfield is a service, and unlike a garrison it does not take neutral hosts), and a FINISHED structure. Room is excluded from `admits` on purpose — **a full bay is a queue, not a refusal**.

**An airfield will not START what it cannot park, but it will happily QUEUE it.** `Train.has_free_pad_for` is asked at DISPATCH, from `ProductionQueue._free_producer`, which treats a producer with no free pad as busy — `DispatchResult.WAIT_PRODUCER`, so the purchase holds without blocking anything behind it, exactly as a barracks mid-job does. Ordering ten aircraft at a four-pad airfield is a perfectly reasonable thing to ask for; they come out as space frees up. Asking at ORDER time instead was the wrong end: it refused the eleventh outright while cheerfully accepting the first ten, which is the same question answered two different ways depending on when you asked it.

That is the PRODUCER'S bay, a harder and more local question than the commander-wide soft tint below: an aircraft is rolled out onto a pad and holds it, so an airfield whose every pad is spoken for has nowhere to put another one.

**Pads are unowned**, claimed from the moment an aircraft sets off until it takes off again. The rejected alternative is Generals' model, where a pad belongs for life to the aircraft the airfield built: that makes the airfield a hard cap on the air force and strands a pad every time an aircraft dies far from home. What survives of it is the **soft gate** — `Commander.has_spare_docking_capacity()` tints the train button `NO_PAD` when charged aircraft already equal total pads, and nothing is refused. Ordered pieces count on both sides: an aircraft already ordered will take a pad, and an airfield already ordered will add them ([UX](../../ux/README.md) §Pending pieces are shown, as pending). It is a fourth button state rather than a variant of the price warnings because the remedy is a building rather than money.

A claim is dropped when its claimant is freed (`DockingPad.is_free()` checks validity), so an aircraft shot down on final approach does not strand its space; and `release` is a no-op for a unit that no longer holds the pad, so a stale release from a torn-down command cannot evict a newcomer.

`DockingBay.tick_recharge()` runs from the **structure's** `_update_state`, not from each docked aircraft's, so `charge_rate` is applied in one place. It charges only pads whose claimant `is_docked_at` them — holding a pad is not standing on it, and charging on the claim alone would let a unit refill in mid-air.

## An aircraft lives on its airfield


Two halves of the same idea: the pad is where an aircraft IS when it is not flying, not a
place it visits.

**It is rolled out onto a pad, not spawned in the air.** `Production._spawn_on_pad` asks the
producing structure's bay whether it `admits` the new unit and, if a pad is free, puts it
there with `Aerial.park_on_deck` — the end state of `land_at`, entered directly. A ground
unit built at the same airfield, or an aircraft the bay would turn away, takes the ordinary
navigable-ground spawn.

**It stays parked until something asks it to move.** A completed `Rearm` ends AT the pad
rather than taxiing out and climbing to no purpose (`_finished_docked`), and the aircraft
holds the deck — `compute_orbit_velocity` returns zero while not airborne, so it does not
taxi in circles. `CommandReceiver._drive_movement` calls `Docking.leave_dock()` before
driving anything, so the first order that actually wants the unit somewhere lifts it. In the
common case that order is the one the auto-rearm interrupted, resumed off the queue.

**The pad belongs to the UNIT from the moment it reaches it** (`Rearm._park` hands
`Docking.docked_pad` over on touchdown at the space, not when the clip is full), and not
to the command that put it there. Everything that asks "is this aircraft standing on a pad"
reads that field — releasing the runway, turning to face the taxiway, leaving through
`leave_dock` — so holding it on the command meant a refuelling aircraft owned the runway and
faced the way it landed for the whole length of a reload. A completed Rearm does NOT release
the pad — the aircraft is still standing on it, and handing the space over would land a
second one on top. It goes back in `leave_dock()`.

**The runway goes back on reaching the PAD, not on touching down.** `Docking.release_runway` asks
`is_docked_on_pad()` rather than `is_on_deck()`: a bare "on the ground" test fires on the
single touchdown tick before the taxi in even starts, freeing the strip with an aircraft
still rolling down it.

## Landing on a building: `Aerial.land_at`


An airfield's cells are BUILDING cells, so they are impassable by construction — and both of `land()`'s navmesh safeguards are therefore exactly wrong for a pad. `_compute_landing_correction` would steer the aircraft AWAY to the nearest navigable ground, and `_snap_to_navmesh` would teleport it off the deck the instant it touched down. `land_at(pad_position, deck_offset, on_complete)` supplies its own target and keeps it, flagged by `_pad_landing`. `_landing_deck_offset` is what lets a pad rest above ground level. Both take-off paths clear the flag — an aircraft off the deck is an ordinary aerial unit again, and a stale deck offset would raise its resting height the next time it set down in a field.

**Both aerial modes dock**, unlike `land()` and the `Land` command, which stay HOVERING-only (setting down in a field is a hover manoeuvre; landing on a deck is not).

## Docking is declared: `docking: true`


Flying is not the same as wanting an airfield. A piece docks when its doc says `docking: true`,
which gives it a `Docking` component — the unit-side half of the airfield, holding its pad and
its runway (`scripts/entities/components/docking.gd`). Presence is the whole rule, so every
caller asks the same thing (`piece.docking != null`) and no one can let a unit in on half of it.
The importer refuses `docking:` without `aerial:` (TODO: a ground unit that docks is planned,
and needs an arrival of its own — every dock today is a deck an aircraft lands on).

The Anarchical **kamikaze drone** is the piece that simply does not declare it. It is FLYING,
but it is expended on its first attack run and there is nothing about an airfield it could
want. With no `Docking` it is ineligible everywhere at once rather than merely unmotivated:
`Aerial.land_at` refuses to ground it (the last line of its "spawns airborne, stays airborne"
guarantee), `DockingBay.admits` turns it away, the Rearm button never appears, it has no
auto-rearm, and — the one that would otherwise be a live bug — `Commander.charged_aircraft_count`
excludes it, so a swarm of drones can't report the air force as short of pads it will never
occupy.

**A charged weapon on a piece that does not dock is an import error**
(`SpecRegistry._validate_charged_can_rearm`). Such a unit fires its clip once and is unarmed
for the rest of its life, with nothing in the game able to fix it. This is the one place the
two mechanics are joined: `charged` says the clip is refilled from outside, and `docking: true`
says the piece has somewhere to go for it — see [charged ammunition](charged-ammunition.md).
The kamikaze's weapon is deliberately uncharged.

## Docking a FLYING unit suspends flight


`FLYING` had no landing regime at all before this: it was unconditionally airborne, `_update_flying_height` owned the altitude and pushed it back to `AERIAL_HEIGHT` every tick, and an idle one orbited rather than stopping. So grounding one is not a matter of reusing the hover landing — it is a matter of **suspending normal flight**, which is what `_landing_state != AIRBORNE` now means for this mode too. `_physics_process` routes to `_tick_flying_landing` instead of `_update_flying_height` while that holds, so the two never fight over `_current_height_offset`.

Four consequences, each with the place it lives:

- **`is_airborne()` stopped being unconditional for FLYING** and now runs the same landing-state test as HOVERING. Its one consumer is `Weapon.get_range_for_target`, so this is what makes a parked aeroplane shot at with a weapon's GROUND range: a plane on a deck immune to everything that could not shoot upward would be a considerable exploit.
- **`compute_orbit_velocity()` returns zero while not AIRBORNE.** `CommandReceiver` feeds it to any idle FLYING unit every tick, so without the gate a plane whose docking order ended — or was interrupted while it sat on the deck — would taxi off its pad in a circle.
- **The climb-out is FLOWN, not levitated.** `_tick_flying_landing` drives the unit forward along its facing during `TAKING_OFF` (`_accelerate_along_facing`), and `set_velocity` is suppressed for FLYING through that state alone so command-driven velocity does not fight it. A fixed wing has to be moving to be flying; one that rose vertically to cruise altitude and only then set off would look nothing like an aeroplane. HOVERING keeps command control through its ascent, where `_cap_xz_for_ascent` already handles rising in place.
- **`Actor.update_commands`'s take-off branch covers any piece with an `Aerial`**, not only HOVERING. A jet re-ordered off a pad without it would try to carry out the order by taxiing along the deck.

**Where the descent BEGINS is the one thing the two modes genuinely differ on** (`Rearm._approach_radius`). A helicopter arrives overhead and sinks, so `APPROACH_RADIUS` is deliberately tight — it comes down on its own pad rather than drifting in from across the airfield. A jet cannot do that at all, so it commits from `Aerial.descent_run_distance`: the ground it covers at cruise speed while shedding the altitude, which works out as a shallow glide touching down exactly on the pad. Derived from the unit's own speed rather than authored, so a faster airframe commits earlier instead of arriving high — the same reasoning as `_dive_commit_distance`, and for the same reason (a descent is TIME-limited, so a constant distance is speed-blind).

`_steer_during_descent` / `_brake_during_descent` are the shared halves both modes fly, factored out of the old HOVERING-only LANDING block. The speed cap — arrive horizontally exactly as you touch down — is what makes a landing read as an approach rather than a drop, and for a FLYING unit it *is* the approach.

## `land_at`: landing on a building deck

*Moved out of `aerial.gd::land_at`.*

Unlike land(), this never consults the navmesh: the caller has named an exact spot and
that spot is on a building footprint, which the navmesh calls impassable. The descent
still steers horizontally toward it — that is the existing LANDING branch, which brakes
so the aircraft arrives exactly as it touches down — so the approach reads as a real
landing rather than a drop from a hover.

BOTH aerial modes, unlike land(), which stays HOVERING-only. A FLYING unit has no hover
to sink from, so its descent is flown: _steer_during_descent caps horizontal speed to
arrive exactly at touchdown, which turns the descent into an approach. What differs
between the modes is only WHERE the descent begins — see Rearm's approach radius, which
starts a fixed-wing's much further out so it flies a shallow glide rather than sinking
from directly overhead.

A unit with no `Docking` gets the completion callback and nothing else, so it reports itself arrived and stays
exactly where it was. That is the last line of the kamikaze's "never lands" guarantee:
even a caller that reached this without checking cannot put such a unit on the ground.

## A pad must be free before an aircraft is trained

*Moved out of `train.gd::has_free_pad_for`.*

An aircraft that rearms is rolled out ONTO a pad and holds it until it flies
(Docking.docked_pad), so an airfield whose every pad is spoken for has literally
nowhere to put another one — and building it anyway would either stack two aircraft on
one space or strand the new one in the air over its own hangar.

ASKED AT DISPATCH, NOT WHEN THE ORDER IS GIVEN. Queuing ten aircraft at a four-pad
airfield is a perfectly reasonable thing to ask for — they come out as space frees up —
so the queue accepts them all and this decides only whether the NEXT one may start
building now. `ProductionQueue._free_producer` therefore treats a producer with no free
pad as busy, which is `DispatchResult.WAIT_PRODUCER`: it holds that purchase without
blocking anything behind it, exactly as a barracks mid-job does.

THE PRODUCER'S OWN BAY, not the commander's total. The soft commander-wide tint
(Commander.has_spare_docking_capacity, TOOL_TINT_NO_PAD) still says "your air force has
outgrown your airfields" and refuses nothing; this is the harder, local question of
whether THIS building can hand the thing it is about to build a place to stand.

True for everything else: a producer with no bay, or a piece that never docks, is not
the business of this rule. `Tool.needs_docking` is derived at import, so no unit scene
has to be instantiated to ask.

## Losing the deck under you

An airfield can be destroyed with aircraft standing on it. Its `DockingPad` children go with
it, so what a parked unit is holding becomes a **freed reference** — which is not the same
thing as holding nothing, and the difference used to be fatal in both directions.

**It crashed.** `Rearm` reaches its airfield through `message.target`, and the helper that
resolves the bay took a typed `Entity`. Godot type-checks an Object argument against the
parameter's class BEFORE the body runs, so the freed airfield failed the check and the
`is_instance_valid` guard one line inside was unreachable. The general rule this is an
instance of is in [CLAUDE.md](../../../../CLAUDE.md) — *a freed object cannot be passed to a
typed parameter*.

**Then it froze.** Past the crash the aircraft was left `GROUNDED_TEMP` with no pad: it is
not `is_docked_on_pad()` any more, so `CommandReceiver._drive_movement` never calls
`leave_dock()` for it — and a commanded velocity is suppressed outright while a unit is on a
deck (`Aerial.suppresses_commanded_velocity`). The result is an aircraft nothing can move, sitting on a patch of ground where its
airfield used to be, ignoring every order.

The rule: **a docked unit must be standing on a pad that claims it, and the tick that stops
being true is the tick it leaves.** `Docking.release_lost_dock` gives up the space and
the runway, takes off, and then either

- **goes somewhere else** — `Commander.nearest_docking_bay_for` picks another airfield and
  the unit is issued a `Rearm` to it, PREPENDED so whatever it was going to do next survives;
- **or holds over the wreck** — with no airfield left it anchors on the spot its pad occupied
  and orbits there. It is where the player last saw it and where they will come looking; an
  aircraft that instead flew off to a corner of the map would read as lost.

**"Holding a pad" is asked of the AIRFIELDS, not of `docked_pad`.** `docked_pad` is null for
the whole descent and taxi — the `Rearm` holds the reservation until `_park` hands it over —
so "no `docked_pad`" alone is indistinguishable from "my deck was destroyed", and reading it
that way would lift an aircraft on short final. `_holds_a_live_pad` therefore also asks each
of the commander's bays whether any pad claims this unit. It walks a handful of pads on a
handful of airfields, and only ever for a unit that is already standing on a deck.

Tests: `tests/test_DockingBay.gd` §Losing the deck under you.
