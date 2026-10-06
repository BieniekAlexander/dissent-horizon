---
title: Off-map abilities
type: system-note
---

# Off-map abilities

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## An ability that originates from beyond the play space

Almost every ability in the game originates **about the piece that produces it** — a
Bombard's shell leaves the Bombard's muzzle, a Spot's beacon is planted where the Recruit
is standing. A second shape exists alongside it: an ability whose payload comes from
**off the map**, called in rather than fired. The model is Command & Conquer: Generals'
promotions — the caster is a radio, not a weapon.

Three are built. **Mortar** (Anarchist, three tiers) simply produces projectiles from that
origin. **Drop** (Colonial, three tiers) produces a piece that then plays out a whole
flight inside the game. They are the two ends of the same idea, and were built together
deliberately so the entry rule is shared rather than reinvented at each scale. **Gunship**
(Colonial) reuses the Drop's flight for a piece the player can then order.

## The origin is derived from the CASTER, and this is the whole rule

`OffMapArrival` (`scripts/scenario/off_map_arrival.gd`) is the one place "off the board"
becomes a world position:

1. Take the **caster's** position.
2. Find the point on the **play-area perimeter** nearest it (`PlayArea.nearest_perimeter_point`).
3. Go `EXTERIOR_MARGIN` (10 world units) further along the ray from the caster through that
   point (`PlayArea.exterior_point`).

**Keyed to the caster rather than to the target, and that is a design decision, not an
implementation convenience.** The alternative — nearest perimeter point to the *target* —
would have made the caster's position mean nothing, and every delivery would arrive from
whichever edge happened to be closest to the enemy. Keying it to the caster is what makes a
forward Operations Center play differently from a home one: the run-in comes over your own
side of the field, crosses whatever is between, and the player can read the line.

The same 10 units is the **despawn threshold** on the way out (`OffMapArrival.has_left`), so
a transport enters and leaves at the same remove from the board — and so a piece that has
just spawned is never immediately judged to have left.

**The play area is not axis-aligned**, which is why the geometry lives on `PlayArea` rather
than on a `Rect2`: `TerrainData` authors play bounds in the screen-aligned (s, t) frame, a
45°-rotated rectangle in world XZ, and its four dead corners are exactly what a bounding box
would wrongly include. Working in the rectangle's own frame makes the perimeter query a
clamp.

**Degenerate cases are handled, not asserted** (§5.1). A caster standing *on* the perimeter
makes the ray through it zero-length, so the edge's outward normal stands in — and a caster
against the map edge is exactly where a player puts a building. A map with no play area at
all (a bare test harness, a scene with no heightmap) falls back to the caster's own
position: the ability fires from the caster, which is the ordinary shape every other ability
already has. Degraded, not broken.

## Projectiles and events were NOT unified behind one interface

The obvious generalisation — make an emission and `AbstractEvent` comport with one
"thing that can be produced from an origin" interface — was considered and rejected. They
already share the only thing they need to: **a sanction's payload is an event**, and an
event may produce projectiles, pieces, both, or neither. `EventMortarBarrage` produces four
to sixteen projectiles; `EventAirDrop` produces one commandable and hands it an order. A
shared base class between the projectile and the event would have had one member (a world
position the caller already has) and would have put a type hierarchy in the way of the
thing that actually varies, which is what the event *does*.

What IS shared is `OffMapArrival`, and that is the right size for the commonality: three
static functions over a `PlayArea`.

## The caster reaches the event through `Sanction.activate`

`Sanction.activate(position, manager, commander, caster)` sets `caster` on the instantiated
event with the same optional-property idiom `commander_id` and `sanction_name` already use —
only an event that declares the field takes it, and today only the off-map events do.
`caster` is optional so a scripted or test deployment with no building is still expressible;
an event with no caster falls back to the target point, which still enters from off the map,
just no longer keyed to the caster's side.

Both deployment paths pass it: the player's order (`UseSanction.fulfill_action`, which has
the acting building) and the bot (`BotSanction`, which already picks a ready caster before
firing).

## Mortar: the simple end

`EventMortarBarrage` throws `shell_count` shells from the entry point at the clicked point.
All three tiers are **one event with a different `shell_count`** (4 / 8 / 16), because that
is the only thing that differs — a tier is authored data, exactly as
[payloads](payloads.md) establishes for every other family.

Each shell's launch point is displaced by a random XZ direction at `1 + 2·randf()` world
units. **The muzzles are scattered; the aim is not** — every shell is launched at the same
target point, so the barrage converges rather than pattern-bombs. What the spread buys is
that sixteen shells read as sixteen separate arcs instead of one thick line. XZ only: an
off-map launch *altitude* is not something the player can see or reason about.

The shell is the Colonial Bombard's `cannon_shell`, a stand-in until the Anarchists have one
of their own.

## Drop: the delivery run

`EventAirDrop` puts a [[nt_aircraftMedium_transport]] in the air at the entry point, already pointed at the
target, loads the shipment into its **garrison**, and gives it one `AirDropRun` order.

**The shipment rides in a `Garrison`, not in a list the event keeps.** That is what an
entity carrying other entities already is, and it buys the whole delivery: occupants leave
the scene tree (invisible, unshootable, unpathed in transit), they come back under their own
commander, and `Garrison.evacuate`'s release placement already spreads them onto free ground
around the host. Nothing about the transit had to be written.

`AirDropRun` (`scripts/interface/commands/air_drop_run.gd`) is **one command across two
phases**, not a queued pair, because the second leg's destination is not known until the
first one ends — the transport leaves along the heading it arrived on, which is a fact about
where it actually was when it let go:

| Phase | Flies to | `can_act` when | `fulfill_action` |
|---|---|---|---|
| APPROACH | the drop point | within `DROP_RADIUS` of it | release the cargo, compute the egress point, return `self` |
| EGRESS | past the far edge | `OffMapArrival.has_left` | `queue_free()` the transport, return `null` |

It is a **command** rather than a behaviour script on the transport because the run
genuinely is a sequence of orders — fly here, act, fly on — and `CommandReceiver` already
drives that shape, including the "a fixed wing does not stop to shoot" handling that keeps
the aircraft moving through the moment it acts. It overrides `ends_on_arrival()` to false:
without that, the receiver's arrival branch would throw the order away the tick the aircraft
reached the target and leave it orbiting with its cargo still aboard.

`DROP_RADIUS` is deliberately generous (2 units). The transport is flying at cruise speed
and cannot stop, so a tight radius would be crossed inside one physics tick and missed; the
cargo is spread onto free ground around the release point anyway.

Nothing offers `AirDropRun` on the command grid and `CommandContextParser` does not know its
name — like Wander, it is issued to a piece the player never selects.

### The transport is killable, and killing it is the counterplay

[[nt_aircraftMedium_transport]] is FLYING, so it sits on the anti-air targeting layer for the whole run-in,
and its hold sets **`preserve_occupants: false`**: the shipment dies with it. Releasing the
cargo from a dying aircraft would mean the drop landed anyway, wherever the wreck happened
to be, and the interception would have bought nothing. It also avoids evacuating units over
ground that may be off the map entirely.

`bunker: false` for the matching reason: the shipment is cargo, not a gun crew, and a
transport whose passengers fired out of it on the way in would be a gunship.

A tier that ships more than `capacity` holds is an **authoring error**, and `EventAirDrop`
reports it loudly rather than short-shipping the drop.

## Parachute descent is a STATE on GROUNDED, not a fourth movement mode

A unit tipped out of the transport falls under a canopy: it starts at zero vertical speed,
accelerates at `PARACHUTE_GRAVITY` (4 u/s², a canopy rather than Earth's g) to a terminal
`PARACHUTE_TERMINAL_SPEED` of 2 u/s, and resumes ordinary grounded movement where it touches
down. From the transport's cruise altitude that is a little over three seconds.

**`Movement.Mode` was deliberately NOT given a fourth member for this.** The mode is read
well outside the locomotion — `Garrison`'s occupancy masks, `Entity`'s targetable-layer
choice, `Aerial`'s altitude model, the orbit, dive and docking logic — and every
one of those already gives the right answer for a soldier under a canopy: it is grounded
cargo with no airfield life. A fourth mode would have had to be
taught to all of them to arrive back where it started, and `Garrison.MOVEMENT_BITS` would
have needed a bit for a mode no garrison can ever admit. "Swap back to `GROUNDED` on
landing" then costs nothing, because the unit never left it.

**TARGETING IS THE ONE READER THAT DOES NOT FOLLOW `mode`**, and this note used to say it
did — that a parachutist is "shot at from the ground". It is not. Targeting asks ALTITUDE
(`Entity.is_air_target`), so a unit under a canopy is an AIR target until it falls past
`AIR_TARGET_ALTITUDE`, and only anti-air can touch it for the first half of the drop. That
is the deliberate consequence of having ONE definition of airborne rather than one per
subsystem — see [combat/target-acquisition](../../combat/target-acquisition.md).

What the state does change is the two things that genuinely differ while falling:

- **`Entity.height_offset()` reports the remaining altitude** (`Movement.descent_altitude`:
  the canopy stays on the ground unit's locomotion, since a piece that falls has no `Aerial`).
  `Commandable`'s per-tick Y snap is already `terrain_height + height_offset()`, so the descent
  needs no second code path — and `Garrison.evacuate` places each evacuee at exactly that height, which is why
  `AirDropRun` starts the descent *before* it evacuates. The units appear at the
  transport's cruising height and float down from there, using the garrison's ordinary
  spread-onto-free-ground placement rather than a second copy of it.
- **Commands are suppressed until touchdown**, at the same gate in
  `CommandReceiver._process_commands` that stops a stunned unit and an unfinished building.
  Orders it is GIVEN are kept, not refused, so a squad dropped onto a rally point walks off
  the instant it lands.

`begin_parachute_descent` **refuses anything that is not GROUNDED**: an aircraft
tipped out of a transport flies away, it does not fall, and a canopy would fight its own
altitude model. The callback still fires immediately in that case, so a caller's cleanup
never has to ask which kind of unit it just released.

### The canopy is a prop, and the command owns it

`scenes/entities/parachute.tscn` is a scriptless `Node3D` — a hemisphere canopy and a
shroud line. `AirDropRun` hangs one on each unit at the drop and frees it from the
descent's touchdown callback, and it frees any still outstanding in `on_released` so a
transport destroyed mid-run leaves nothing behind.

It is parented to the **unit**, not to the unit's `MeshVisual`, so it plays no part in the
team tint, the construction and status shading, or `MeshVisual.model_top_offset()` — which
decides where floating badges sit and would otherwise put them above the parachute instead
of above the soldier.

## Gunship: a sortie the player can steer, but not move

`EventGunship` launches a [[cl_aircraftMedium_gunship]] from the same caster-keyed entry point
and hands it a `Sortie` (`scripts/entities/components/sortie.gd`): **in** with its weapon
disabled, **on station** over the target point for `station_seconds` (20) circling it with its
weapon live, then **out** past the point it entered at, where it removes itself on
`OffMapArrival.has_left`.

**The run is a component, not a command, and that is the difference from `AirDropRun`.** The
gunship is selectable and takes the player's Attack orders while on station, and it picks up
targets on its own (idle aggro). Any of those replaces the active order, so a run held as one
order would be thrown away by the first target. The sortie sits beside the queue instead:

- **It flies the transit legs as `SortieLeg` orders**, and re-issues one if anything takes it
  away — a cleared queue arrives as a null order, which nothing can refuse.
- **It gates admission** (`Sortie.admit`, called from `Commandable.update_commands` beside
  `Deployable.admit`): in transit only its own leg; on station only Attack, FocusFire and Stop.
  A piece carrying a sortie is ON RAILS (`Commandable.is_on_rails`): Move, Patrol and Defend
  are not on its card, and a right-click on ground resolves to a move and is silently refused.
  Attack-move stays on the card as the way to attack a chosen target — a friendly included —
  since clicked on a target it resolves to Attack; clicked on ground it is refused with the
  refusal cursor (`AttackMove.meets_precondition`).
- **It keeps the weapon cold off station** through `Commandable.can_use_weapons`, which every
  firing path already asks — so idle aggro, retaliation and Attack all stand down together.
- **Its targets never move it.** Its weapon measures reach from the centre of its orbit
  (`range_from: orbit`), so an Attack — ordered or picked up — changes only what it shoots at;
  it keeps circling the station, picks up and lets go of targets by the range shape standing
  there, and cannot be drawn off the point. → [combat/range-buckets](../../combat/range-buckets.md)
  §Where a reach is measured from.
- **Idle on station circles the station.** Anything else that ends with the orbit anchored
  elsewhere (a Stop settles where it was given) is re-anchored by the sortie.

## Adding another off-map ability

1. Write the event under `scripts/scenario/events/`, declare `commander_id` and `caster`,
   and get the entry point from `OffMapArrival.entry_xz(map, caster_xz)`.
2. Author one scene per tier under `scenes/scenario_events/`, differing only in exports.
3. Point the faction scene's `Sanction.event_scene` at them by hand — the payload is the
   half of a cell the importer deliberately does not own (see [sanction-grid](sanction-grid.md)).
4. Write the tier copy in the sanction's gdd doc and re-run the importer, which syncs the
   descriptions into the faction scene.

## Tests
`tests/test_OffMapArrival.gd` (the entry/exit geometry, including the on-perimeter and
no-play-area cases) and `tests/test_ParachuteDescent.gd` (the fall, the touchdown callback,
the command suppression, and the refusal for aerial units).
