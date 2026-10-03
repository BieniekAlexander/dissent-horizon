---
title: Projectiles and emitted objects
type: system-note
---

# Projectiles and emitted objects

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

An *emission* is a game object put into the world by something else — a weapon, an ability,
a sanction event, another emission — which exists for a bounded time and applies a payload of
damage and status effects to some set of entities. Rockets, shells and bullets are the obvious
members; lasers, poison clouds and radiation fields are members too. There is no emission
class: an emission is an ordinary `Entity` composed of a `PhasedLocomotion` (its motion), a
`Payload` (what it does to what it reaches) and, for a beam, a `Tracer`. Its doc says
`kind: Entity`, and emission keys (`phases:`, `damage:`, `hitscan:`, …) are what make the importer
treat it as one. Every emitter puts one into play through `Emitter.launch`.

## Phases

**An emission is an ordered list of phases**, its `EmissionPhase` children, run in tree order.
Each phase carries:

- a **motion** — how the emission moves while the phase lasts;
- **end clauses** — arrival, a lifespan, the swept impact test; any that holds ends the phase;
- a **payload schedule** — whether the payload is applied during the phase, and how often;
- **events** — `AbstractEvent` children run on the phase's own cadence, at the emission's
  position, as the emission's owner's.

**The phase list is run by the emission's LOCOMOTION** (`PhasedLocomotion`, the phased strategy
of [composition-rework](../authoring/composition-rework.md) §Locomotion is bigger than `Movement`):
it owns which phase is live, the motion, the end clauses, the phase's events and its visuals, and it
announces each tick and each contact. The `Payload` listens: it pays out on the live phase's
cadence, and decides what a contact means.

When a phase ends it hands over to the next at the start of the following tick, and the next
phase runs that same tick. A last phase that runs out expires on its final tick. "Impact" is
not a concept the class knows: it is the name of one common shape, a flight ending by arrival
into a one-tick phase that applies the payload. A phase always runs at least one tick.

**Consecutive moving phases are one flight in stages** (built 2026-10-03):

- **A stage hands on its motion.** When a moving phase's lifespan ends and the next phase also
  moves, the next one takes over the position and heading as they are. It is not relaunched
  (so `launch_speed_ratio` and `launch_pitch` mean nothing on a later stage), and the emission
  does not settle onto its destination's height. What happens to the speed depends on the
  stage:
  - a straight stage flies at its own `speed` from its first tick;
  - a steered stage starts from the inherited speed and works it toward its own under its
    `acceleration` and `turn_bleed`, so a rocket can run a different guidance law in each stage;
  - a falling stage keeps the motion it was handed and falls.
- **A contact ends the whole flight, not just the stage.** It skips every moving phase after
  the live one, straight to the next phase that does not move (the burst). With none left, the
  emission is spent.

So the cases that used to need special handling are just lists:

| Piece | Phases |
|---|---|
| bullet, shell | flight → one tick of payload |
| radiation, toxin field | flight → a lifespan of payload on a cadence |
| laser | a motionless flight with a lifespan → one tick of payload |
| sonic sweep | one phase: moving, not ending on arrival, paying out on a cadence, then expiring |
| poison trail | one phase: moving, with an event that drops a cloud every second |

### The doc grammar

A doc either writes the list out or uses the **shorthand**, which stands for the common
two-phase shape: `speed:` and `trajectory:` describe a flight that ends on arrival, followed by
one tick that applies the payload. `tools/spec_import/emission_phases.gd` owns the grammar, its
validation and its expansion; the importer writes one `EmissionPhase` node per item.

```yaml
phases:
  - name: Flight                 # optional; Flight, Impact, then Phase2, Phase3…
    motion: {preset: HOMING, speed: HYPER}   # speed names a class (movement/speed_classes);
                                             # or a bare preset name; absent = stationary
    ends_on_arrival: true        # defaults to whether the phase moves
    lifespan: 2                  # seconds; absent = unbounded
    impact_mask: [terrain, structures]    # also ground, air; absent = none
    payload: once                # or seconds between applications, 0 = every tick
    emits: {id: toxin_cloud, every: 1}    # an emission dropped where this one is
    visuals: [InFlightSprite]    # optional; a moving phase (and the first) gets the in-flight
                                 # set, a motionless later one the post-impact set
```

`speed:`/`trajectory:` beside `phases:` is refused — a doc says its motion in one place. So
is a steered motion without a lifespan (a homer whose target dies would fly forever), a launch
pitch without gravity, and any key the grammar does not recognise. An `emits:` phase gets an
`EventSpawnEmission` child, which puts the named emission down where this one is, aimed at
that same spot.

### Motion: scalars, with four named presets

| Scalar | Unit | Effect |
|---|---|---|
| `speed` | u/s | travel speed; under gravity, the horizontal speed |
| `gravity` | u/s² | downward acceleration — a ballistic arc, with the launch angle solved to land on the destination |
| `launch_pitch` | degrees | a lob: the launch angle is fixed and the speed solved instead |
| `turn_rate` | degrees/s | steering toward a live target |
| `launch_speed_ratio` | — | fraction of `speed` it launches at |
| `acceleration` | u/s² | while steering: gained toward `speed` facing the target, lost toward `min_speed` facing away |
| `min_speed` | u/s | the floor it slows to |
| `turn_bleed` | u/s² per radian | while steering: speed lost for each radian the steering goal is off the nose. Replaces the facing rule: the emission gains `acceleration − turn_bleed × angle` each second, between `min_speed` and `speed`. Needs a `turn_rate` |
| `lead` | 0–1 | while steering: how far ahead of its target it aims, as a fraction of the target's predicted motion until the intercept. Predicted once per phase and held. Needs a `turn_rate` |
| `burn` | seconds | when the motor burns out, counted from the start of the phase; zero never burns out |
| `coast_speed` | a speed class | the speed it is held to after `burn`. Comes paired with `burn`, and a falling motion cannot have either |

Every default describes a straight, constant-speed flight, so a motion names only what it adds.

**`tracks_goal`** (a scene property on `EmissionPhase`, not yet a doc key — its only user,
`cannon_shell`, has no doc) makes a FALLING phase re-aim at a pursued piece every tick: the fall
is untouched and the horizontal velocity is re-solved so the emission crosses the piece's height
over it, on the same schedule the arc already had. It is how a Bombard shell follows a beacon
riding on a unit — [bombardment](bombardment.md) §The shell follows its solution.
The four old trajectory names survive as **import-time presets** (`EmissionPhase.PRESETS`):
LINEAR is the empty set, BALLISTIC adds gravity, LOFTED adds a pitch, and HOMING adds the
steering set that reproduces the homers' old flight. Nothing at runtime reads a name. The
homing parameterisation is deliberately minimal and expected to be revisited.

Arrival depends on the motion: a steered phase arrives within half a unit of its live target
and never without one; a falling one lands on crossing its destination's height on the way
down; anything else arrives within one step of the destination. A GUIDED flight that ends by
arriving snaps onto a live target it was chasing, so it can hit a target it geometrically
missed, and any guided flight that ends other than by impact settles at its destination's
height. A FREE flight never arrives at a piece, never snaps, and settles only when it arrived
at a place (§Free flight).

TODO: whether a non-constant speed needs more than `acceleration` and `min_speed`. A Godot
`Curve` cannot be written in YAML but could be baked at import from an expression in `t`;
nothing in the roster wants one yet.

### Turn bleed and lead

Two steering knobs for a rocket that **rewards a target for reacting**: holding course gets you
hit, and dodging well, with the speed to use it, gets you away (Alex, 2026-10-03). Both are off
at zero, and both act only on a steered phase.

- **`turn_bleed`: hard turns cost speed.** A rocket flying straight at its goal keeps
  accelerating to its top speed; one whose goal is far off its nose sheds speed in proportion
  to the angle, down to `min_speed`, and climbs back once it is pointed again. That lets a
  rocket be fast without being inescapable: a target that forces it into a sharp turn takes
  its speed away, and a fast target can then outrun it.
- **`lead`: aim where the target is going.** As the phase begins, the emission predicts where
  its target will be when they meet, from the target's motion, and steers at that point,
  advanced by `lead` (a fraction: 1 is the full intercept, 0.5 halfway). The point is
  predicted ONCE and held for the phase:
  - a target that keeps its course flies into the shot;
  - one that changes course after it is fired draws the rocket to an empty point;
  - once that point is behind the rocket, it flies straight for the rest of the phase.

  The target's motion is MEASURED: `PhasedLocomotion` samples the pursued piece's position on
  the emission's own consecutive ticks, so it holds for any way a piece moves (navigation
  agent, aerial drive, another emission). The prediction is made on the phase's second tick,
  the first with two samples; until then the phase steers at the target itself.

**Phases combine them.** A leading stage followed by a homing stage, both bleeding, is
predict, then chase: a target that holds course is hit by the first stage; one that jukes
forces the second stage into a hard turn that bleeds its speed, so a fast juker escapes and a
slow one is run down. The Warlord is written that way (§Rocket calibration).

### Losing the lock

**A steered phase can LOSE ITS LOCK on its target** (Alex, 2026-10-03), by either of two motion
keys, both off at zero and both needing a `turn_rate`:

| Key | Unit | Lost when |
|---|---|---|
| `lock_cone` | degrees, at most 180 | the target is farther off the nose than this. 180 is lost only dead astern |
| `lock_range` | u | the target is farther away than this |

**Losing the lock is permanent and cuts the motor** (`PhasedLocomotion._fall`). The emission
stops steering and thrusting, keeps the velocity it had, and falls under
`EmissionPhase.LOST_LOCK_GRAVITY_MPS2` (the shells' 4.5). Its stages' lifespans no longer end
it: it falls rather than expiring, and bursts where it strikes. A contact, or the
`LOST_LOCK_FALL_SECONDS` (5 s) backstop for a fall with nothing beneath it, skips any
remaining moving stages straight to the burst. A later stage never relights it. The lock is
tested against the target itself (its hitbox centre), not against a leading stage's aim point.

### A rocket aims at the hitbox

**A steered phase steers at, leads, and arrives at the centre of its target's hitbox**
(`Entity.aim_point`, the global position of `TargetBody/TargetShape`; the piece's origin when it
has none) (Alex, 2026-10-03). **And every hitbox stands ON its piece's base**: `Entity._ready`
raises the TargetShape until its bottom is at the origin (`_seat_target_shape`). A shape authored
higher is left where it is.

- **Why both:** a shape is centred on its node, and every piece's hitbox was authored at its
  origin, its feet. Half of it was underground, so "aim at the centre" was "aim at the ground",
  and a slightly short rocket struck the terrain in front of a ground target.
- **What else moves:** every weapon and blast now meets the hitbox above the ground rather than
  straddling it. Range is unaffected (`Hull` reads the footprint on XZ only), and a shell
  bursting at ground level still reaches the hitbox's bottom.
- **Only steered phases aim at the centre.** A launch still sets off toward the target's
  position, and unsteered shells and bullets still aim at the ground under it. A beacon has no
  hitbox, so a Bombard shell tracking one is unchanged.

### A lost pursuit loops

**A phased emission cannot stop.** When the piece a steered phase pursues leaves the game, it
keeps steering at the last place that piece was, which loops it round that point until its
lifespan ends or it strikes something. It does not arrive: a guided flight's arrival needs a live
target, and a free flight has none. Before
this it flew on along its last heading. A goal dead astern is nudged a degree to one side, since
a turn toward a point directly behind has no axis. Test:
`tests/test_EmissionPhaseRuntime.gd::test_a_homing_shot_that_loses_its_target_circles_where_it_was`.

### Free flight: a shot that can miss

**Every non-hitscan emission flies FREE, and a free flight ends only on striking something:
the piece it was aimed at, or the ground.** Each tick it casts a ray along its move
(`PhasedLocomotion._test_contact`) against terrain, the targetable layers when it was aimed at
a piece, and its phase's `impact_mask`. Any other piece the ray meets is flown straight
through, so a rocket fired at one tank does not burst on the soldier in front of it. Aimed at a
place, it strikes only the ground. Where it stops is where it bursts. WHO the burst reaches is
the Payload's blast, a separate question, so the burst can hurt pieces it was never aimed at.

A free flight at a piece has **no arrival test**. It does not end by coming within a radius of
its target and is never snapped onto it, so a shot can miss. A homing phase's `turn_rate`, the
target's size, the shot's speed and its lifespan together decide how often it lands, and all
of them are balance levers. A free flight whose lifespan runs out bursts where it is, in the
air if it is in the air. A free flight at a place keeps its arrival test as a fallback beside
the ground ray.

**A shot at a BIO piece is aimed at the ground under it** when its Payload says
`bio_ground_aim` (`Payload.aims_at_ground_under`, applied in `Emitter.launch`). The destination
becomes the terrain under the piece's feet at the moment of firing, and nothing is pursued, so
homing does nothing and the shot lands where the soldier stood. It hurts the soldier only if
they are still inside its blast. A MECH piece is pursued as usual. All five rockets carry it.
It is **deliberately a MISS mechanic**, stacked on top of the damage table's armour penalty and
not replacing it: rocket fire against infantry rewards moving, and a small blast (the Badger's is
0.1 units) makes it rarely land against a soldier at all.

A HITSCAN emission flies GUIDED as it always has. It ends by arriving, snaps onto its target,
and pays that target whatever it passed through. Its `impact_mask` can still end it early on
those layers, where a single-target shot lands on what it struck *as if that were its target*.

Line of fire is still decided once, at order time, by `Attack`'s `STRUCTURE_BLOCKER` raycast
([target-acquisition](target-acquisition.md) §Line of fire): structures are not terrain, so a
free flight passes through them unless a phase's `impact_mask` names them.

TODO: a shot to or from an aircraft is not blocked by buildings, so its emission can be seen
flying through one. Bending the launch trajectory around the building is deferred (decided
2026-09-29).

TODO: the contact test is a ray, the emission's path and not its body, because no emission has
an in-flight volume. A shape sweep is the change if a shot should ever graze.

### The tick-of-flight rule

**A phase never hands over on the physics frame the emission was launched.** An emission whose
flight would end at once — a point-blank shot, a lifespan already spent — holds where it is and
hands over next tick, so no payload is ever applied on the tick of creation. That is what lets
two units that open fire on the same tick both resolve their shots and kill each other
symmetrically. Motion is untouched: an emission launched before node processing still moves on
its launch frame. Godot's ordering (a node added during physics processing is not ticked until
the next frame) used to be the only thing keeping this true;
`tests/test_EmissionTickOfFlight.gd` has a case that removes that luck.

## `hitscan` is the aiming rule, and nothing else

`hitscan: true` does not mean "resolves in the launch frame" — such a shot still flies, and at
30 u/s crosses five units of range in five ticks. What it selects is where the payload lands:

| `hitscan` | payload lands on | flight |
|---|---|---|
| `true` | the entity the shot was fired at, whatever the emission's actual position | guided |
| `false` | every targetable entity inside the `HitShape`, wherever the emission is | free (§Free flight) |

A `true` shot additionally gets a small random launch yaw from the seeded gameplay generator,
which is purely cosmetic — the payload ignores where the visible shot went. The flag also selects how
the flight ends, since a shot that lands on its target wherever it goes has no reason to fly
free.

### The shape's presence is the blast

`Payload.has_blast()` is simply "the emission carries a `HitShape`", and only a non-hitscan
emission does: the importer removes a hitscan emission's shape. A `Payload` whose `hitscan` and
shape disagree reports it at `_ready` — a hand-edited scene, since the importer keeps the two in
step.

REJECTED — reading the shape's `disabled` flag, with `hitscan` authoritative over it. That was
the answer while every emission inherited a `HitShape` it could not remove, when presence could
never be a predicate; asserting on presence then crashed six shipped pieces on their first
shot. Composed scenes can remove the node, so presence is the predicate again.

TODO: `HitShape` is the blast volume and nothing else, and could be renamed to say so; the
importer's renamed-component table would carry the scenes.

### The payload is one set, resolved once

`blast:` is one number governing what is damaged and what is status-affected alike:
`Payload.apply` resolves the overlapping entities once and both damages that set and seeds its
`EffectApplicator` children with it. The two can never drift apart, and area weapons
friendly-fire by construction (the query is `TARGETABLE_ANY`) rather than by a flag. See
[authoring/spec-importer](../authoring/spec-importer.md) for the import side.

### The blast is measured at the contact

**When a free flight strikes something, who is in its blast is decided on the CONTACT's tick**
(Alex, 2026-10-03). The burst phase still pays out a tick later, by the phase rule, but on the
set measured at the contact (`Payload._on_struck` snapshots `_blast_victims()`; the next
`apply` takes it).

- **Why:** measured at the payout, the blast stood where the rocket stopped while the world had
  moved on a tick. A target moving faster than the blast is wide had already left it, so a rocket
  could strike a piece and leave it unharmed. The Warlord rocket (a 0.1 blast) struck a QUICK
  truck with 8 rockets of 10 and damaged it with about 5, and the faster the target, the worse.
- **Only the first payout after a contact** uses the snapshot. A phase that pays out on a cadence
  afterwards (a lingering field) measures the world as it is at each payout.
- A victim freed or taken out of the world (garrisoned) between the contact and the payout is
  spared, as a single-target shot's is.
- A flight that ends WITHOUT a contact (lifespan out, or arriving at a place) measures at the
  payout, as before.

## What the framework should and should not absorb

**In:** rockets, bullets, shells, lasers, poison clouds, radiation fields, sweeps and trails —
every bounded-lifetime object with a motion and a payload schedule.

**Out: units.** A weapon or ability that emits a *unit* (the Brood Lord case) must not be
modelled by widening this class until it grows a command queue, an owner, grid registration and
a selection shape — that is a `Commandable`, and it already exists. The generalisation belongs
on the **emitter** side: every spawn site (`Weapon.fire`, `Bombard`, `Ability`, `Interact`, the
scenario events, `EventSpawnEmission`) does the same three steps — instantiate, initialise
against the owner, hand it its initial intent. `Emitter.launch` is that interface for an
emission. TODO: an emitted UNIT, handed a command rather than a goal, is not built — see the
[composition rework](../authoring/composition-rework.md) §The emitted unit.

## What this accepts

- **Emissions pass through obstructions** unless a phase opts into an impact mask. A shot fired
  at a target behind a building hits the target: orders mean what the player asked for, and
  line of fire is enforced once, at order time.
- **A hitscan shot can hit a target it geometrically missed.** The cosmetic launch yaw exists so
  a volley does not draw one line, and it can never cause a miss.
- **A free flight can miss, and the misses are random.** They come from seeded motion, so they
  replay exactly, but rocket damage is now a distribution shaped by range, speed, turn rate,
  target size and blast, not a fixed number per hit.
- **Area weapons friendly-fire**, and one number governs damage and status reach together.
- **The roster keeps the four trajectory names** as presets, so two vocabularies describe one
  motion for as long as the presets live.
- **Lifespans are authored in seconds and rounded to ticks**, so a phase lasts a whole number of
  ticks and never less than one.

## Rocket calibration: the no-escape zone

**TODO — research. Only items marked Decided are settled.** A paper calculation (2D pursuit, no
jitter or terrain, hit radius 0.7 for vehicles and 0.8 for aircraft), not self-play. Every number
is a starting point to check in play.

### What is wanted (Alex, 2026-10-02)

- **Badger rockets keep up with almost every ground target.** Only the fastest grounded class
  (QUICK, `vehicle_light`) may outmanoeuvre one, and **whether it can depends on how far away it
  was when the rocket was fired.**
- **Warlord rockets are slower than the Badger's but live longer**, because they must also hit
  aircraft.
- Turn rate and acceleration are part of the model.

### The model: escape distance

Missile design calls this the **no-escape zone**: inside some firing distance a target cannot
escape whatever it does; beyond it, a target that turns away early enough outruns the rocket.
Measure it per target class as

```
d_esc   the shortest firing distance from which the target escapes
```

with the target starting across the line of fire at full speed and evading in either of two
ways: holding its course, or turning (at its own turn rate) to flee directly away. Wanted: for
the Badger, `d_esc` beyond its reach (12) for STEADY and BRISK and somewhere inside it for QUICK.

Each knob shapes `d_esc` differently:

| Knob | What it sets |
|---|---|
| speed while closing | how fast the rocket covers the distance: flight time, so how far a target gets before it arrives |
| speed late in flight | whether a long shot can be outrun at all. A target faster than it escapes a tail chase |
| `turn_rate` | close-range reliability. The rocket's turning circle is `speed / turn_rate`, and a target that can turn inside it dodges at close range, which is the opposite of the distance rule wanted |
| lifespan | the hard ceiling on a chase |
| `acceleration`, `min_speed` | an overshoot penalty: speed is lost while the target is behind the rocket and regained once it is ahead |
| `launch_speed_ratio` | a slow launch. At close range the target may outrun the rocket before it is up to speed |

**One speed cannot separate QUICK from BRISK.** With a single flight speed `s` and lifespan `L`,
a fleeing target escapes from about `(s − v) · L`, and BRISK's and QUICK's escape distances
differ only by the ratio `(s − 3) / (s − 4)`. Any useful rocket speed puts them almost
together. Faster, briefer rockets cut both off at the edge of reach; slower ones let QUICK dodge
at *close* range by turning inside the rocket's circle:

| Badger rocket, one phase | STEADY | BRISK | QUICK | flight to 12 |
|---|---|---|---|---|
| today: 15, unsteered, 2 s | 5 | 4 | 3 | misses a crossing target |
| 15, turn 45°/s, 2 s | never | never | never | 0.77 s |
| 15, turn 60°/s, 0.9 s | never | never | 12 | 0.77 s |
| 7.2, turn 60°/s, 2.2 s | never | 10.5 | 2 (dodged up close) | 1.83 s |
| 5.25, turn 90°/s, 4 s | never | 10.5 | 6.5 | 3.07 s |

**Boost, then coast, separates them.** A rocket that flies fast for a moment and then slows to
a sustained speed covers short distances before anything can react, and leaves a long shot
outrunnable only by a target faster than the sustained speed allows for:

| Badger rocket | STEADY | BRISK | QUICK | flight to 12 |
|---|---|---|---|---|
| **boost 15 for 0.4 s → 7.2, turn 60°/s, 2.2 s** | never | never | **7.5** | 1.27 s |
| boost 15 for 0.4 s → 5.25, turn 60°/s, 2.4 s | never | 8.5 | 8.5 | 1.80 s |

The first row is the shape wanted: STEADY and BRISK never escape, and a QUICK vehicle fired on
from beyond about 7.5 can escape by turning away at once, while one fired on from closer cannot.
The boost time moves that threshold (a longer boost pushes it out), and the coast speed sets
which classes can use it.

### A slow ignition (Alex, 2026-10-02: wanted if it fits)

A rocket that leaves the tube slowly and then accelerates hard. **Existing knobs already express
it**: `launch_speed_ratio` sets the launch speed, and `acceleration` builds speed while the target
is ahead. Launching at about 2 u/s with an acceleration of 40 u/s² reaches 15 in about 0.33 s.

**It fits, provided the turn rate is at least 60°/s.** A slow rocket that turns slowly gives a
QUICK vehicle a dodge *up close*, the opposite of the distance rule. At 60°/s the slow start costs
nothing, because a slow rocket also has a tight turning circle:

| Badger rocket (launch 2 u/s, acceleration 40, coast 7.2 after the burn, 2.2 s) | STEADY | BRISK | QUICK | flight to 12 |
|---|---|---|---|---|
| burn 0.5 s, turn 45°/s | never | 9 | 2 (dodged up close) | 1.47 s |
| **burn 0.5 s, turn 60°/s** | never | never | **7** | 1.43 s |
| burn 0.6 s, turn 60°/s | never | never | 8 | 1.33 s |
| burn 0.8 s, turn 60°/s | never | never | 11.5 | 1.00 s |
| slow ignition alone, no coast (15, turn 45°/s, 2 s) | never | never | 2 (dodged up close) | 0.90 s |

The burn time, counted from launch and including the ramp, is now the knob that places QUICK's
escape distance. The ignition adds about 0.13 s to every flight (a 2-unit shot takes 0.2 s
against 0.07 s), and the visible pop before the rocket takes off is a readable tell.

### The Warlord

Against aircraft (QUICK `flyer_heavy`, FAST `flyer_medium`, BLAZING `flyer_light`) and ground,
with its reach 12:

| Warlord rocket | QUICK air | FAST air | BLAZING air | ground (all) | flight to 12, FAST air |
|---|---|---|---|---|---|
| today (the SAM missile): 7.2, turn 75°/s, launch at half speed, 5 s | 1.5 | 1.0 | 1.0 | BRISK 1.5, QUICK 1.0 | 4.1 s |
| **7.2, turn 120°/s, launch at half speed, 5 s** | never | **9.5** | 1.0 | never | 4.1 s |
| 10, turn 120°/s, launch at half speed, 4 s | never | never | 1.0 | never | 1.9 s |

- **Today's missile can be escaped from any distance by a crossing aircraft.** It launches at
  half speed and turns at 75°/s, so its turning circle (about 5.5 units at full speed) is wider
  than a close target's path. The SAM fires the same missile, so this applies to it too.
  Model-predicted; worth checking in play.
- **The middle row is the shape wanted.** It needs no new knob: slower than the Badger's boost,
  a 5 s life against the Badger's 2.2, no escape for QUICK aircraft or anything on the ground, a
  distance-dependent escape for FAST aircraft, and BLAZING aircraft always escape, as the speed
  ladder intends.
- **The Warlord needs its own emission before this is tuned.** It fires `sam_missile` today, so
  any change moves the SAM too, and the planned salvo upgrade would as well.

### What boost-then-coast needs from the engine

Both are code changes, not authoring. **Both built 2026-10-03** (§Phases: consecutive moving
phases are one flight in stages), so a boost → coast → burst rocket can now be written as
phases; the `burn` knob below stays as the one-phase way to say it.

1. **A contact in a flight phase hands over to the NEXT phase, not the payload phase.**
   `_end_by_contact` ends the live phase only. A rocket written as boost → coast → burst that
   strikes during the boost enters the coast phase, so the payload never fires and the rocket
   flies on from the contact point.
2. **A new phase re-aims at the original destination.** `_enter_next_phase` relaunches with
   `launch_velocity(position, goal_position)` instead of keeping the flight's heading and speed.

**Built (2026-10-02): a burn knob on one phase's motion**, `burn:` and `coast_speed:` (a speed
class), after which the speed is held to the coast speed (`EmissionPhase.burnt_velocity`,
applied after steering, so a steered phase's own acceleration rule still runs under the cap).
The drop is immediate. One phase
keeps contact handling and heading as they are, and the boost-then-coast rows above are exactly
this knob. **Applied (2026-10-02):** the Badger rocket is **launch 2 u/s, acceleration 40, BLAZING, coast
to RAPID after 0.5 s, turn 60°/s, 2.2 s** (min speed 2), and the Warlord fires its own
`warlord_rocket` (**RAPID, turn 120°/s, half-speed launch, 5 s**) instead of the SAM's missile.
Both are starting points for play. Before the knob existed, **15, turn 45°/s, 2 s** fixed the misses with existing knobs, with no
distance dependence yet.

### Retuned for the new speed ladder (2026-10-03)

**This supersedes the 2026-10-02 targets above** where they differ; the tables above are kept
because the model and the knobs still apply. Aircraft were raised 2–4× (to RAPID–HYPER, see
[speed_classes](../../movement/speed_classes.md)), which left every rocket slower than most of
what it was fired at. What is wanted now (Alex, 2026-10-03):

- **The Badger rocket is faster than every ground class in play.** The ground class that may
  escape it is one about as fast as a slow aircraft, and none exists yet. This replaces "a
  QUICK vehicle fired on from far enough away can escape".
- **The Warlord rocket is slower, with strong homing**, so it eventually reaches ground targets
  and a fast vehicle can drive away until it expires.
- **Projectile physics is still being explored.** Manoeuvrability (turn rate, acceleration,
  interception geometry) is the intended lever for dodging, and is deferred until there are
  more projectiles. For now, low-tier projectiles are fast enough to hit most of their targets.

Applied, from the same paper model, now `tools/projectiles/rocket_escape_model.py` (run it to
reproduce these):

| Rocket | Motion | STEADY | BRISK | QUICK | FAST 5.25 | aircraft | flight to reach |
|---|---|---|---|---|---|---|---|
| Badger | launch 2 u/s, accel 40, SCORCHING, coast to SWIFT after 0.5 s, turn 60°/s, 2.2 s | never | never | never | dodges at 1.0+ | (ground only) | 1.07 s to 12 |
| SAM | HOMING, SCORCHING, turn 180°/s, accel 20, half-speed launch, 5 s | — | — | — | — | RAPID, SWIFT, BLAZING never; HYPER always | 1.27 s to 20 |

- **The Warlord was first slowed to FAST (turn 180°/s), which no moving aircraft had to
  dodge.** It was rebuilt the same day as below.

### The Warlord: predict, then chase (2026-10-03)

Wanted (Alex, 2026-10-03): fast, but slowing a lot in sharp turns, and aimed where a moving
target is going, so a target that holds its course is hit and one that reroutes after the shot
is away can escape: "mechanical elasticity". It is written as two flight stages and a burst
(§Phases: consecutive moving phases are one flight in stages; §Turn bleed and lead):

| Stage | Motion | Lifespan |
|---|---|---|
| Predict | HOMING from a half-speed launch, FLEET (8.5; was SCORCHING until the retune below), turn 90°/s, acceleration 10, min speed 2, `turn_bleed: 120`, `lead: 1` | 0.5 s |
| Chase | the same, without `lead` | 3 s |
| Impact | the burst | 1.6 s |

Escape distances from the model, fired from 0.5 to 12 (reach 12). "Reverses at T" is a target
that turns back on its course T seconds after the shot:

| Target | holds course | flees at once | reverses at 0.3 s | reverses at 0.5 s | reverses at 1 s |
|---|---|---|---|---|---|
| STEADY, BRISK | never | never | never | never | never |
| QUICK (ground) | never | never | 1 of 24 | 7 of 24 | 12 of 24 |
| FAST 5.25 (ground) | never | never | never | 10 of 24 | 10 of 24 |
| RAPID aircraft | never | never | 23 of 24 | 23 of 24 | 10 of 24 |
| SWIFT aircraft | never | beyond 7.5 | 11 of 24 | 23 of 24 | 23 of 24 |
| BLAZING aircraft | almost always | almost always | almost always | almost always | almost always |

Flight to 12 at a standing target: 0.9 s.

- **Holding course is fatal to everything slower than BLAZING**, and slow targets are run down
  whatever they do.
- **A reroute is what saves a fast target**, and when it rerouted matters: the moment and
  the distance both move the outcome. That is the reaction window the design asks for.
- Settled by scanning top speed (SWIFT to SCORCHING), turn rate (90 or 180°/s), bleed (40 or
  120), acceleration (5 to 20), lifespan (2.5 to 5 s) and the predict stage's length (0.3 to
  0.8 s) for the shape above. A higher turn rate, or faster re-acceleration, makes it
  inescapable. A longer predict stage starts to let SWIFT aircraft escape while holding course.
- It keeps `hits: [ground, air]` with its anti-air role back: an aircraft that holds course is
  hit.

### Checked in the arena (2026-10-03)

**TODO — the arena disagrees with the paper model; the Warlord's elasticity is not achieved in
the engine yet.** Specs in `sims/` (`warlord_vs_{truck,wagon,raven}_{holding_course,jinking}`,
`badger_vs_collective_jinking`); "jinking" reverses 0.4 s after each rocket leaves. Ten seeds
each:

| Spec | Claim | Met | + contact fix | + hitbox aim |
|---|---|---|---|---|
| truck (QUICK), holding course | dies | 0 of 10 | 6 of 10 | 10 of 10 |
| truck, jinking | survives | 0 of 10 | 0 of 10 | 0 of 10 |
| War Wagon (STEADY), holding course | dies | 8 of 10 | 8 of 10 | 10 of 10 |
| War Wagon, jinking | dies | 10 of 10 | 10 of 10 | 10 of 10 |
| Raven (SWIFT, hover), holding course | dies | 10 of 10 | 10 of 10 | 10 of 10 |
| Raven, jinking | survives | 0 of 10 | 0 of 10 | 0 of 10 |
| Badger vs Collective (QUICK), jinking | at least half damaged | 10 of 10 | 10 of 10 | 10 of 10 |

The two fixes are the first two causes below; with both, holding course is fatal, as designed.
**TODO — still open: no fast target dodges yet**, so the elasticity the Warlord was designed for
is not there. See the retune below.

**Retune, 2026-10-03: measured by HIT RATE, not kills** (Alex: tuning a projectile is about how
often it hits; whether one cheap shooter kills its target before it escapes is the damage
rate, out of scope). Every Warlord spec now claims a fraction of rockets fired that hit
(`hit_rate`, simulation-tests.md §Counting shots): **at least 75%** against a target holding
course and against the slow War Wagon whatever it does, **at most 50%** against a fast target
(truck, Raven) that flees or jinks. Three seeds each; numbers are the share of rockets that
hit, with the rockets fired in brackets:

| Top speed, chase | truck hold / jink / flee | wagon hold / jink / flee | Raven hold / jink / flee | Claims met |
|---|---|---|---|---|
| 16.5 (as shipped), 3 s | 100 / 96 / 100 | 100 / 100 / 100 | 100 / 100 / 100 | 5 of 9 |
| 9.3, 3 s | 100 / 100 / 100 | 100 / 100 / 100 | 75 / 80 / 100 | 4 of 9 |
| 8.5, 3 s | 96 / 100 / 100 | 100 / 100 / 100 | 100 / 80 / 0 | 6 of 9 |
| 7, 3 s | 75 / 96 / 50 | 100 / 100 / 100 | 58 / 80 / 0 | 6 of 9 |
| 7, 3 s, turn 180 | 100 / 100 / 50 | 100 / 100 / 100 | 58 / 80 / 0 | 6 of 9 |
| 16.5, chase 0.3 s | 22 / 63 / 50 | 85 / 100 / 67 | 0 / 22 / 0 | 4 of 9 |

Lock cones from 10° to 120°, and a 10-unit lock range, changed little or made holding course
escapable (§Losing the lock is built and tested, and unused by the Warlord so far).

- **One top speed cannot satisfy both fast targets.** A fleeing truck (QUICK, 4 u/s) outpaces
  only a rocket at about 7 or slower; a Raven crossing the Warlord's front is hit reliably only
  by one at 8.5 or faster. Which wins is a design choice.
- **Jinking never helps at 8 units, at any setting**: the rocket arrives in about 0.8 s, and a
  vehicle that reverses 0.4 s after launch is back near where the rocket was first aimed.
- **The fleeing specs fire few rockets** (one to three a run, since the target leaves reach),
  so their rates are coarse; more seeds before trusting a threshold there.
- **Chosen (Alex, 2026-10-03): the Raven.** Both Warlord stages fly at FLEET, a rung added at
  8.5 for it. Five seeds: a crossing Raven is hit 20 of 20, a fleeing one 0 of 5; a truck
  holding course 37 of 40; the War Wagon whatever it does 100%. A fleeing truck is still hit
  10 of 10, and jinking still never helps (truck 40 of 40, Raven 20 of 25): 6 of 9 claims.
  **TODO — separating fleeing from crossing by the rocket's RANGE rather than its speed** (a
  boost that runs out and falls, §Losing the lock) is to be revisited by Alex.

Three causes, found by tracing contacts (the first two since fixed):

- **A contact could deal no damage — FIXED 2026-10-03** (§The blast is measured at the
  contact). The blast was measured on the payout's tick, a tick after the contact, by which
  time a fast target had left the Warlord rocket's 0.1 sphere: a QUICK truck holding course was
  struck by 8 of 10 rockets and damaged by about 5. It favoured exactly the target that holds
  course, which inverts the design.
- **Steered emissions aimed at the target's ORIGIN, at ground level — FIXED 2026-10-03**
  (§A rocket aims at the hitbox): a slightly short rocket dived into the terrain in front of a
  ground target (2 of 10 rockets in one run).
- **A hovering aircraft reverses by backing off at `reverse_speed_ratio`** rather than turning,
  so a reroute makes it slower, and the chase stage runs it down. The model treated every
  target as a turning vehicle.

Outside the arena (a box hitbox, no terrain short of it), the same rocket hit a steadily
crossing truck with every shot, as the model predicts, which is what points at the first two.
- **The SAM got an explicit `acceleration: 20`.** The HOMING preset's 2.25 u/s² takes almost
  four seconds to get from a half-speed launch to SCORCHING, during which BLAZING aircraft
  outran it.
- **Aircraft-fired weapons moved with their carriers:** the Purifier's and Viper's emissions
  went from 15 to SCORCHING (16.5), and the Interceptor's air-to-air missile to SUPERSONIC, so
  it is faster than every aircraft.

## Where an emission leaves from

**A weapon's emissions leave from its LAUNCH POINTS, the Marker3D children of the Weapon node,
walked as a ring one shot at a time; with none, from the Weapon node itself**
(`Weapon.next_launch_position`). A salvo launcher is a Weapon with one marker per tube: the SAM
site carries three and the MLRS pod twelve, one per round of the clip. Nothing checks that the
count matches the clip; a ring shorter than the clip simply comes round again.

**A turret's weapon is placed in the turret's frame**, so its shots leave the barrel however the
turret has swung: the turret model (`turret_visual_path`) when there is one, otherwise the
carrier turned by `turret_yaw`. The Weapon node cannot live under the turret model, because the
Loadout owns every weapon and a garrison hoists a Loadout whole. So its position is READ in the
turret's frame, while the editor draws it in the carrier's. The accepted cost is that on a
turreted piece the gizmo sits in the wrong place.

Positions are world units. A Weapon's basis often carries a non-uniform scale, which is how
its range shapes are sized, and the launch frames drop that scale so a marker 0.3 to the side
is 0.3 to the side.

Moving a Weapon node changes no gameplay. Range is measured from the attacker's transform, and
only the range shape's radius is read.

**A weapon launching from its carrier's origin warns, once per piece**, because the origin is
inside the model on every piece. The warning fires at the weapon's `_ready` for a
scene-authored weapon only, since one built in code has no authored position.

TODO: the weapon positions given on 2026-09-27 to the pieces that had none are placeholders:
65% of the model's height, 70% of the way to its front face (+Z is forward). They are to be
moved onto real muzzles when models have them.

## Jitter

**A rocket's wobble is real motion.** A phase's `jitter_degrees` and `jitter_frequency_hz` (doc
keys `jitter:` and `jitter_frequency:` in `motion:`) turn the emission's heading a few degrees
either side of where steering and gravity are taking it. The deviation is two sine waves per axis
(sideways and vertical) at unrelated rates (`EmissionJitter`), and it builds over the first
quarter second so a shot leaves the tube cleanly. `PhasedLocomotion` keeps a clean velocity for
steering and gravity to act on and flies that velocity turned by the wobble, so the wobble never
compounds from tick to tick. A homing phase corrects the drift; an unsteered one keeps it and
can miss.

**Why sines.** They are cheap enough to run on every rocket every tick, and a sum of them
integrates to a bounded drift: a mean-zero weave cannot walk a shot arbitrarily far off line, as
a random walk would. The phases are drawn from the seeded gameplay generator (`SU.rng`) at
launch, so a replay flies every rocket identically. The effect is meant to be too small to
decide games: the five rockets carry 3–4°.

A shallow shot aimed at a soldier's feet feels the vertical wobble most, because a small dip
meets the ground early.

REJECTED: the wobble drawn only, displacing the drawn rocket from a true path it still flew
exactly (built and replaced 2026-09-27). It could never cause a miss, and a miss was what was
wanted.

## Visuals

**An emission's visuals are its phases' `visuals:` lists, and it is on screen exactly as long as
it is in the tree.** `EmissionPhase.show_visuals` switches each listed node with its phase:

- **a node holding particle systems** is switched by `emitting` alone and never hidden, so
  what it has already emitted lives out: an exhaust's smoke still hangs where the rocket flew
  while the impact phase plays;
- **anything else** (a mesh, a sprite) is shown and hidden, which is how the in-flight model is
  swapped for the impact's.

**Phases switch visuals by difference** (`PhasedLocomotion._show_visuals_of`, 2026-10-03): a
node the live phase names is never hidden, even when another phase names it too, and one
already showing is not shown again. So several stages of one flight share their mesh and
exhaust, which stay up across the handover rather than vanishing (as the Warlord rocket's did
for its whole first stage, until this) or restarting a delayed start.

So an effect that must be seen after impact is paid for with a longer impact phase and
`payload: once`: the emission stays in the tree showing its explosion, and deals its damage on
the first tick only. A phase's lifespan is therefore a visual length as well as a mechanical
one, and it must cover the longest-lived particle of every effect still on screen.

**A trail starts a moment after its phase does.** A particle system that is an
`EmissionParticles` waits `start_delay_seconds` before emitting (a pausable timer; a phase that
ends first cancels it). The rocket smoke waits 0.12 s and the shell's trace 0.1 s. Started on the
launch frame, a trail's emission volume, which reaches back along the flight line, put smoke
inside the unit that fired and made it appear from nothing. The puffs also fade in over their
first moments rather than appearing at full opacity.

**A phase that does not move stands the emission upright, keeping its heading**
(`PhasedLocomotion._level`). Otherwise an impact phase keeps the facing of the flight that
ended it, which for a falling shell is nearly straight down, and its burst and ground ring would
be drawn on their side.

REJECTED: an effect node that detached itself from the emission and freed itself after its
particles faded. It duplicated the lifetime a phase already has, and put visuals outside the
phase model that governs everything else about an emission.

The effects are cosmetic: they never touch the simulation, and draw at the default render
priority, beneath the fog of war.

**An emission is hidden under an opponent's fog like any piece**
([piece-vocabulary](../authoring/piece-vocabulary.md) §Where today's code disagrees): it becomes
visible as it enters the viewer's sight, and an impact in sight is shown even when the flight
was not. **A beam that spans the fog edge is drawn partially.** The `Tracer` draws one segment
per stretch of the beam in sight (`Tracer.visible_spans`, sampled at half a cell), re-clipped
every frame. The segments are copies of the authored `BeamMesh` parented to the `Tracer`, a
plain `Node`, which breaks visibility inheritance — so hiding the fogged emission does not hide
the part of its beam in sight. The authored `BeamMesh` is only the template and never draws.

### The shared looks

Every visual node keeps the importer's role names — `InFlightMesh`, `InFlightParticles`,
`PostImpactParticles` — since those names are what it writes into each phase's `visuals:`.

- **A lead round is a tracer and nothing else**: a `Tracer`-drawn `BeamMesh` whose mesh is the
  one shared `resources/emissions/lead_tracer_beam.tres`, so every lead round in the game draws
  the same streak and a retune is one edit.
- **A rocket** instances `scenes/effects/emissions/rocket_model.tscn` as its `InFlightMesh`,
  scaled per piece, with `rocket_exhaust.tscn` at its nozzle and `rocket_explosion.tscn`
  (about a unit across) on impact.
- **The Bombard's shell** uses `artillery_shell_model.tscn`, `artillery_trail.tscn` — a glowing
  trace and smoke — and `artillery_explosion.tscn`, whose fireball and ground ring reach three
  units out.

A trail emits along a box one tick of flight long, because an emission moves once per physics
tick: particles emitted at a point would lay a dotted line.

**A rocket's nozzle flame is a mesh, not a particle system** (the `Flame` cone in
`rocket_model.tscn`). As a continuously emitting `local_coords` particle layer it once drew, in
editor-launched runs only, as a large opaque white disc at the nozzle of every rocket at once,
10–40 s into a match. That is what particles with no process shader look like: default 1-unit
quads, uncoloured and unmoving, saturating under additive blending, cut flat where the
camera-facing quad crosses the ground. The trigger was never found. It did not reproduce
offscreen (`--write-movie`, 30 and 120 fps), in real time, in long soaks, or by freeing a
material with the same features, and it went away when the layer became a mesh. If the disc
returns on another effect, the Remote tree finds the layer (toggle nodes under the emission's
`InFlightParticles`/`PostImpactParticles`), and a mesh is the known remedy.

TODO: the artillery burst is sized to `cannon_shell`'s blast by authoring, not derived from its
`HitShape`, so a change to the blast leaves the explosion the old size.

## Checking a change to the model

`tools/emission_trace.tscn` fires every emission scene at a fixed cluster of targets, aimed at a
target and at the ground, and prints the damage each target took on each tick after launch. Its
output is deterministic, so a change to the model is accepted when the trace before and after is
identical — or differs only where the change meant it to.
