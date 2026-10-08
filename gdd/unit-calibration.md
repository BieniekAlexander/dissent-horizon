# Unit calibration

How the physics-facing numbers on a piece are chosen, and why.

This note covers the values the simulation actually reads — ranges, speeds, turn
rates, acceleration, projectile velocity. It does **not** cover cost, HP, damage or
the rock-paper-scissors table; those are balance and live in `tools/balance`.

Two kinds of statement live here, and they are kept apart deliberately:

- **Rules** are enforced by the spec importer (`tools/spec_import/spec_rules.gd`).
  Breaking one either fails the import or has to be declared in the doc's
  `exceptions:` block. They are listed in [Enforced rules](#enforced-rules) with
  only a pointer to their reasoning, which lives beside the code.
- **Heuristics** are how a piece is usually built. Nothing checks them, because
  most of the interesting design in an RTS is a deliberate departure from one.
  They exist so that a departure is a *decision* rather than an oversight.

---

## The units

| Quantity | Unit | Note |
|---|---|---|
| distance, radius, reach | world units | 1 world unit = 1 terrain cell (`Map.CELL_SIZE`) |
| `movement.speed` | world-units / second | |
| `movement.turn_rate` | degrees / second | `INF` (the default) = snaps instantly |
| `max_acceleration` / `max_deceleration` | world-units / second² | decel is a **signed floor**, so negative |
| `projectile.speed` | world-units / **second** | the component stores per-tick; the importer divides by 30 |
| every time (`build_time`, `split_time`, `reload_time`, cooldowns) | seconds | the importer converts to ticks |

The simulation runs at **30 ticks/second**.

> **The one trap.** `Projectile.speed` on the component is per *tick*. Only the doc
> key is per second. Read a `.tscn` and multiply by 30 before comparing it to
> anything.

Some reference magnitudes, so a new number can be placed against something:

| | |
|---|---|
| infantry speed | 1.5 |
| ground vehicle speed | 4.0 |
| fixed-wing cruise | 6.0 |
| aerial cruise altitude (`Aerial.AERIAL_HEIGHT`) | 6.0 |
| weapon reach | a named bucket, not a number — see [combat/range-buckets](systems/combat/range-buckets.md) |
| vision | a named bucket — see [combat/range-buckets](systems/combat/range-buckets.md) |

---

## The three radii

Every armed piece carries three concentric numbers, and they answer three different
questions. Getting them confused is the single most common calibration mistake in
this project — 13 units shipped with `aggro: 2` against reaches of up to 7.5, which
meant they declined shots they could already take and stood still until the enemy
walked into arm's length.

| Radius | The question | Read by |
|---|---|---|
| `vision` | what does my side SEE from here? | fog of war; also the retaliation radius (`Actor._get_vision_range_attack`) |
| `aggro` | what will I START a fight over, unprompted? — derived, never authored | the idle pickup (`Actor.get_aggro_near_position`) |
| weapon `reach` | what can I actually shoot? | `SU.is_in_attack_range` |

### `aggro` is not a knob any more

It is derived from reach, per target layer: one unit past it, clamped to 5–10, and held
to reach on a piece that cannot move. Rule and history:
[combat/range-buckets](systems/combat/range-buckets.md) §Aggro is derived from reach.

### Heuristic: `vision` covers `reach`, and the exceptions are the artillery

A piece that cannot see what it shoots depends on somebody else's eyes. That is a
real and valuable design — it is *why* spotters are worth fielding, and it gives an
opponent a second way to answer a battery — but it should be a short, named list
rather than something that happens by accident. Enforced as a norm with declared
exceptions. Which pieces are on the list is whatever declares `reach_within_vision` in
its `exceptions:` block; the importer prints them on every run, so no copy is kept here.

Aggro is fog-filtered — a candidate must be visible to the asking commander
([target-acquisition](systems/combat/target-acquisition.md)) — so a piece whose reach
passes its vision fires past it only on what the rest of its side can see. That is the
mechanic that makes spotting worth something.

---

## Movement

### Heuristic: fast units turn slowly

Speed and turn rate trade against each other, because what they jointly determine is
the **turning circle**: `radius = speed / turn_rate` (in radians). A unit that is
both fast and nimble has no downside to being ordered anywhere; a fast unit with a
wide circle has to be *aimed*, which is the intentionality that makes moving an army
a skill rather than a click.

Current circles, for calibration:

| Piece | speed | turn°/s | circle |
|---|---|---|---|
| infantry | 1.5 | 1080 | 0.08 |
| ground vehicle | 4.0 | 150 | 1.53 |
| Drake (fixed wing) | 6.0 | 90 | 3.82 |
| kamikaze (fixed wing) | 4.0 | 120 | 1.91 (0.48 diving) |

**The circle is only real when the unit cannot stop to turn.** A GROUNDED unit with
`min_turn_speed_ratio: 0` pivots in place, so its circle is zero however slow its
turn rate — the turn rate then buys a *delay* before setting off, not an arc. A
FLYING unit never stops, so its circle is always real, which is why it is the one
mode with an enforced rule about it.

### Heuristic: infantry pivots, vehicles arc

`min_turn_speed_ratio` is the fraction of speed a GROUNDED unit keeps while turning:

| Value | Behaviour | Fits |
|---|---|---|
| 0.0 | pivot in place, then set off straight | infantry (enforced for BIO) |
| 0.3–0.5 | keeps rolling, reverses to swing around — three-point turns | most vehicles |
| 1.0 | full-speed arcs, never slows to turn | fast light vehicles, hovercraft |

Only three scenes set it at all today, so nearly every Colonial vehicle currently
pivots like a soldier. That is the biggest single gap between how the game reads and
how it is authored.

### Heuristic: brakes beat engines, except in the air

Real ground vehicles stop about three times harder than they accelerate. That
asymmetry is most of what makes a vehicle feel heavy: it commits to getting moving
and can still bail out. `matilda` (accel 1.5, decel −3.0) is the only piece in the
game authored this way; every other pair is symmetrical, which reads as inertia-less.

A fixed wing is the honest counterexample and the reason the rule is GROUNDED-only:
thrust accelerates an aeroplane and almost nothing sheds that speed again. The
kamikaze is 5.0 / −2.0, correctly.

### Heuristic: long reach costs speed — but fragility can buy it back

The default pairing is that a piece which out-ranges the enemy should not also
out-run them, or there is no way to close with it. The MLRS follows this loosely
(siege reach at vehicle speed).

The counterexample worth keeping in mind is C&C Generals' Rocket Buggy: very long
reach *and* very fast, paid for with almost no health. The axis being traded is
"can you be caught", and fragility answers it as well as slowness does — a fast
glass cannon dies to whatever does catch it. So the rule is not "long reach ⇒ slow",
it is **"long reach ⇒ at least one way to be punished for being caught"**.

---

## Weapons and projectiles

### Heuristic: a clip is a rhythm, not a number

`reload_time` is the time to restore a FULL clip and `split_time` is the gap between
shots, so a clip of *N* empties in `N × split_time`. The clip only exists if that is
comfortably shorter than the reload — the MLRS fires twelve rockets over 1.2s and
then stands reloading for 10s, and that salvo-then-vulnerable rhythm *is* the unit.
A clip that refills as fast as it empties is decoration. Enforced.

**A CHARGED weapon reads differently.** It never reloads in the field, so its
`reload_time` is time parked on an airfield pad, and the rhythm is the sortie rather
than the salvo. The clip rule does not apply.

### Heuristic: a projectile must outrun what it is shot at

Flight time is `reach / speed`, and the target moves during it. Against a target
crossing at right angles, the miss distance is roughly `target_speed × flight_time`
— there is no lead prediction, so a non-HOMING projectile aimed where the target
*was* simply arrives late.

Worked example, the MLRS (radii of the time of writing; current ones in
[shapes.md](shapes/shapes.md)): reach 12, projectile 9 u/s → 1.33 s of flight. A ground
vehicle at 4 u/s travels 5.3 units in that time, against a 1.5-unit blast. It should
essentially never hit a moving vehicle at maximum range, and should reliably hit
infantry at 1.5 u/s (2.0 units of travel — still outside the blast, but close).

**This is deliberately not an enforced rule.** The threshold at which "usually
misses" becomes "is useless" is a balance question, and the honest way to settle it
is measurement rather than an invented constant — see [Open questions](#open-questions).
Three levers exist when a projectile misses too much: raise its speed, widen its
`blast:`, or make it `HOMING`.

### Heuristic: reach is measured on XZ, so altitude never denies a shot

Every `AttackRange` is a cylinder 100 units tall (`SpecSceneSync.SHAPE_HEIGHT`), so
a height difference between attacker and target never decides an overlap. Two
consequences worth holding on to:

- Air reach and ground reach are the same kind of number. A weapon with air reach 8
  hits an aircraft 8 units away horizontally, whatever altitude it is at.
- A melee weapon that `hits: [air]` therefore *does* connect with something cruising
  six units overhead. It reads as an infantryman stabbing at the sky, which is why
  that combination is enforced against for ground units.

The one place vertical separation is measured is the dive gate — a ramming airframe
must actually descend to within its reach before it may strike.

---

## Enforced rules

The full list, with severity, lives in `tools/spec_import/README.md`. The reasoning
for each is in the doc comment on its `_check_*` function in
`tools/spec_import/spec_rules.gd`, and the counterexamples that shaped them are in
`tools/spec_import/spec_rules.gd`, checked by running the importer.

Two things about the mechanism are worth knowing from the design side:

- **Declaring an exception is free but not silent.** Any NORMATIVE rule can be
  waived in the doc's `exceptions:` block with a sentence saying why, and every
  waiver is printed in the import summary. The list is meant to stay short enough
  to read in one go.
- **A stale waiver is an error.** If you fix the numbers and leave the declaration,
  the import fails. Otherwise the block becomes a list of things that used to be
  true, which still reads as deliberate.

---

## Open questions

Things this note deliberately does not settle. Each is a `TODO` — a decision waiting on an
answer, logged in [tasks](tasks.md).

**TODO — how much lead error is too much?** The projectile heuristic above gives the
arithmetic but no threshold. What is wanted is a simulation that sweeps a
projectile against a crossing target over a range of relative velocities and reports
hit rate, so "the MLRS should generally hit infantry and generally miss vehicles"
becomes a measured claim rather than an intention. The simulation-test framework that can run
that sweep is built — see [simulation-tests](systems/scenario-scripting/simulation-tests.md).

**`aggro` is fog-filtered** — answered yes, and already built: an aggro candidate must be
visible to the asking commander ([target-acquisition](systems/combat/target-acquisition.md)).
The same answer extends the rule to build placement — see
[construction](systems/commands/construction.md) §Placement is judged against what the
commander knows. Shared vision waits on alliances, PLANNED in target-acquisition §Alliances.

**TODO — which of the two speed/turn-rate families should vehicles use?** The Anarchical
vehicles are 4.0 / 150 and every Colonial one is 1.5 / 1080 — the second is
infantry handling on a tank chassis. They should probably converge, but which way is
a faction-identity question rather than a calibration one.

**TODO — nothing here is tuned per faction yet.** Every heuristic above is stated for the
game as a whole. Faction identity ought to show up as a systematic departure from
several of them at once ("the Colonials are slow and out-range you"; "the Anarchists
are fast and fragile"), and that is a layer this note does not have.
