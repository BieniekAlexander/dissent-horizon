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
    visuals: [InFlightSprite]    # optional; first phase in-flight set, later post-impact
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
