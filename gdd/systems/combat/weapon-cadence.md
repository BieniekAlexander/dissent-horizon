---
title: Weapon cadence — bursts, reloads, startup and the states between them
type: system-note
---

# Weapon cadence

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.*

How a weapon's shots are spaced in time, and what the carrier is committed to while they are.
The goals these serve are in the design framework: kiting and the elasticity knobs in
[elasticity](../../design-framework/elasticity.md) §Kiting, and commitment in [commitment-and-movement](../../design-framework/commitment-and-movement.md) §Action timing. This note specialises that algebra to the weapon's own numbers, and owns the rules for the parts that are built.

---

## The cycle

A weapon is authored with four timings, all in seconds on the doc:

| Symbol | Doc key | Meaning |
|---|---|---|
| `n` | `clip_size` | rounds per clip — a burst, when `n > 1` |
| `s` | `split_time` | seconds between rounds within a clip (the **split**) |
| `r` | `reload_time` | seconds to restore a FULL clip, counted from the last round fired |
| `t_s` | `startup_time` | seconds a target must be held before the first round (§Attack startup) |

So one full cycle against a held target is

```
burst duration   B   = (n − 1) · s
cycle            T_c = B + r
damage per cycle     = n · d            (d per round, before the damage table)
sustained DPS    D   = n · d / T_c
alpha            A   = n · d            the clip, landed in B
```

**Alpha** is the damage a weapon lands in one burst — the whole clip, delivered over `B` rather
than spread over `T_c`. It is what a target takes before it can react, so it is the number that
matters against a target caught unaware and the one a telegraph or a startup exists to give
counterplay against. Two weapons of equal DPS can differ widely in alpha.

`r` restarts on every round, so a clip that stops part-way refills whole `r` after its last
round: a weapon that fires 3 of 12 and breaks off is back to 12 in `r`. That rewards breaking off
early, and is itself a knob — see §Reload variants.

A single-shot weapon (`n = 1`) has `B = 0` and `T_c = r`; the split and the reload are one
number for it.

---

## When kiting pays

Kiting (elasticity §Kiting) is retreating between shots and stopping to fire. With bursts, the
stationary time per cycle is the burst, and the free time is what the reload leaves after turning
away, turning back and re-acquiring. A startup is held whether or not the weapon is loaded, so a
startup repaid after turning back comes out of the reload, not on top of it:

```
stationary per cycle     t_f = B
free window              W   = r − 2θ/ω − v/a − t_s'   θ/ω a half-turn, v/a getting to speed,
                                                       t_s' the startup repaid this cycle
kiting pays at all  iff  W > 0,     i.e.   r > 2θ/ω + v/a + t_s'
ground gained per cycle  ≈ v_k · W − v_c · T_c         against a chaser at v_c
```

and `v_kite = v_k · W / T_c` is elasticity's retreat speed with these terms filled in. **Kiting is
free forever iff `v_kite ≥ v_c`**; otherwise the range advantage `R_k − R_c` lasts about
`(R_k − R_c) / ((v_c − v_kite) · T_c)` cycles.

Three consequences that are specific to weapons:

- **The reload, not the split, is the window.** A split is rarely long enough to turn in; a
  reload usually is. So `r` against `2θ/ω` is the first number to read on any piece.
- **A startup that does not survive turning away is repaid every cycle** (`t_s' = t_s`). That is
  the built rule (§Attack startup): a unit that turns its back on its target loses the lock. So
  a startup is a direct tax on kiting for a body-aimed weapon, and none at all for a turret,
  which keeps aiming while the body leaves.
- **Turning is paid twice per cycle while retreating and never while advancing.** Kiting forward
  (chasing) pays only `t_f`.

### Clip size against travel

At a fixed DPS budget `D`, a bigger clip means a longer reload: `T_c = n · d / D`. The free
window then grows with the clip:

```
W(n)       = n · (d/D − s) + s − t_s' − 2θ/ω − v/a
W(n) / T_c → 1 − s · D / d          as n grows
```

- **Bigger clips amortise the fixed costs** — the turns and the startup are paid once per
  cycle, whatever the clip — so at equal DPS a bigger clip kites better, and a clip of one kites
  worst.
- **Bigger clips commit more per decision.** `n · d` lands in one burst, so the alpha `A` against a
  target that has not reacted is higher, and a clip started on the wrong target is a larger
  mistake (elasticity's "payload size per decision"). Overkill grows with the clip too, but
  not simply — see §Overkill within a clip.
- **Longer splits lengthen the stationary time** without changing DPS, and take free window
  away one-for-one: `s` is how long the burst holds the carrier still.

### Overkill within a clip

**A clip is not spent on one target.** When the target dies part-way through a clip, the actor
picks another for the rounds that remain. So what a clip wastes is not everything past the
killing round, only the rounds **already in flight** when that round lands — launched after it,
but too early to know the target was dead:

```
rounds to kill           k   = ⌈HP / d⌉
travel time              t_t = distance / projectile speed
rounds wasted per kill   ≈ min(n − k, ⌊t_t / s⌋)        plus the killing round's excess
```

- **Travel time is what makes a clip overkill.** A hitscan-fast or point-blank shot
  (`t_t < s`) wastes almost nothing: each round is known to have killed before the next leaves.
  A slow projectile fired from far away wastes up to `t_t / s` rounds on every kill.
- **It only applies when a clip can kill**, i.e. `k < n`. Against a target that takes several
  clips, one shooter wastes nothing and overkill is a group effect — several shooters' rounds
  in flight at once.
- **So distance is part of it**, and closing the range is a way to waste less — a positional
  choice with a damage payoff, on top of the range band's own.
- **Short splits waste more**, since more rounds leave during one flight. A salvo weapon is the
  worst case: short `s`, slow rockets, long reach.
- **Small targets waste more** than large ones, since `k` is small and the kill comes early in
  the clip, with most of it still to fire.

**Avoiding this waste is a mechanical elasticity opportunity**, the same one the aircraft
payload offers when a whole attack run is spent on one target: the player splits fire, or
gives a salvo a target it will not kill before the salvo is out, and recovers damage that
auto-targeting throws away. It is the within-clip case of the overkill surface
[elasticity](../../design-framework/elasticity.md) §Where the budget is spent here already
names, and it inherits that section's properties: concave by construction, since it only
recovers waste that exists, and left implicit, with no readout and no overkill-aware
auto-targeting. Its band is widest on exactly the later, long-window weapons the next section
places late, which is where elasticity is wanted.

---

## Elasticity by game stage

The duty cycle is elasticity's strongest **cap** knob, because the free window `W` is also the
time the player has to give the order that uses it:

```
concurrency   c ≈ W / a_order          a_order: the attention one repositioning order takes
```

A window shorter than an order is serviceable for one unit at a time; a long one can be staggered
across many. So the same act — move between volleys — scales very differently:

| Cadence                                   | `W`             | `c`  | Where it belongs                                                                                                                                              |
| ----------------------------------------- | --------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| short burst, short reload (a rifle burst) | under a second  | ~1   | **early**: rewards one squad handled well, and does not multiply with army size, so the early skill surface stays small (elasticity §The budget over a match) |
| long split, long reload (a rocket salvo)  | several seconds | many | **later**: each unit's window can be staggered, so the skill multiplies with the army — the scalable elasticity a late game should carry                      |

The early row also satisfies the early gate: `W / T_c` stays well under one, so no early unit
kites a similar unit for free.

The Irregular and the Recruit carry the short rifle burst (§Framing: LEAD weapons), and are its
reference. TODO: whether the rest of the infantry follows. Giving all infantry multi-round
bursts is the leaning, not a decision. What it costs: every infantry doc gains `clip_size > 1`
and a reload, which raises alpha against light targets and makes infantry fights more
front-loaded. Short `s` and `r` keep the early window narrow (the table's first row); longer
ones would hand early infantry a kite. A sweep in `sims/` over `n` and `r` against the foot turn
rate is the way to check the numbers.

TODO: which later units are designed around a long window — the rocket-buggy shape — and which around position over DPS (a unit whose reload is spent moving is worth little stood still). Not decided per piece.

---

## Framing: LEAD weapons

Three pieces anchor LEAD: the Irregular and the Recruit as the short-burst rifle, and the Sloop
(`cl_mechMedium_antiLight`) as a lower-middle-tier autocannon. All three fire SUPERSONIC
(28 u/s) hitscan rounds, and a round whose target died in flight lands on nobody.

**Every piece kept its sustained DPS.** Splits are whole ticks at 30 Hz (0.1333s is 4), so
the reloads are chosen to make each cycle come out exact. What changes is how it is delivered, and the measure of
that is the **alpha-to-DPS ratio** `A / D`, in seconds — how many seconds of sustained fire one
burst delivers at once. Since `D = A / T_c`, it is simply the cycle length: `A / D = T_c`.

**Assumed:** one repositioning order costs `a_order ≈ 0.5 s` of attention, so `c ≈ 2 · W`.
"Few" is read as `c` of about 3–5.

| | Irregular | Recruit | Sloop |
|---|---|---|---|
| `d` | 5 | 7.5 | 22.5 |
| `n` | 3 | 3 | 10 |
| `s` | 0.1 | 0.1333 | 0.1333 |
| `r` | 0.8 | 1.2333 | 1.8 |
| `B` | 0.2 | 0.2667 | 1.2 |
| `D` | 15 | 15 | 75 |
| `A` | 15 | 22.5 | 225 |
| `A / D = T_c` | 1.0 | 1.5 | 3.0 |
| `W` | 0.47 | 0.9 | ≈ 1.8 |
| `c` | ~1 | ~2 | ~3–4 |

Before this, each fired one round per split: the Irregular 5 every 0.33s, the Recruit 7.5 every
0.5s, the Sloop 10 every 0.1333s — the same DPS with no burst at all.

### The rifles

- **The window is under a second.** Foot turns at 1080°/s, so `2θ/ω = 0.33 s`, and `W` is 0.47 s
  for the Irregular and 0.9 s for the Recruit — serviceable for one squad, not an army.
- **Kiting buys time and is never free.** `v_kite = v · W / T_c` is 0.78 and 0.99 u/s against a
  SLOW (1.65) chaser, and equal reach gives no buffer, so the early gate (no early pairing kites
  for free) holds.
- **One rifle's clip never overkills a rifleman.** `k` is 16 (Irregular vs Irregular) or more,
  well above `n = 3`. Rifle overkill is the group effect.

### The Sloop

- **Alpha-to-DPS of 3 s**, twice the Recruit's and three times the Irregular's, at today's 75
  DPS. The burst is heavier per round (22.5, from 10) and the gap between bursts longer.
- **Longer burst**: 1.2 s, against 0.2–0.27 s for the rifles.
- **Concurrency "few"**: its reload is its decision window. It is body-aimed at 150°/s
  (`2θ/ω = 2.4 s`) and reaches speed in 2 s, so it does not kite in the turn-away sense at all;
  its 1.8 s window is spent choosing the next burst's target and position, not retreating.
- **Distance changes its overkill, and SUPERSONIC supports it.** Travel is 0.11 s at 3 u and
  0.43 s at its full 12 u ground reach. With `s = 0.1333` a round launched at ≤3.7 u lands before
  the next leaves, so a close kill wastes nothing, and a kill at 12 u wastes 3 rounds. It bites:
  4 rounds kill an Irregular (`k = 4 < n = 10`), so a clip kills 2.5 Irregulars up close and
  1.75 at full reach; against Recruits (`k = 6`) it is 1.7 and 1.2. Any `s` between 0.11 and
  0.43 keeps the close/far split; a longer `s` widens the close band but stretches the burst.
- **Mid-clip retargeting costs it a turn.** A body-aimed vehicle must face its next target
  before firing on, so the rest of a clip is delayed by up to `θ/ω` — a second cost of a kill
  landing early in the clip, on top of the waste.

**The dial is `T_c`.** At a fixed 75 DPS, a longer cycle raises both the alpha-to-DPS ratio and
the window, and a shorter one lowers both. The split between the burst and the reload then
decides whether the extra time goes to a longer burst or a longer window:

| `T_c` | `A` | burst | `W` | `c` |
|---|---|---|---|---|
| 2.5 | 187.5 | 10 × 18.75, `B` 1.2 | 1.3 | ~2–3 |
| 3.0 | 225 | 10 × 22.5, `B` 1.2 | 1.8 | ~3–4 (built) |
| 4.0 | 300 | 10 × 30, `B` 1.2 | 2.8 | ~5 |

## Attack startup

**A weapon with a startup fires only once it has HELD its target for `startup_time`.** Held
means in reach and aimed at — the same conditions a shot needs, except being loaded. The lock is
kept through a reload, so a weapon that held its target through one salvo fires the next without
waiting again. It is lost by:

- a different target — returning to the first is a new startup;
- one tick not held — out of reach, or turned away;
- the target leaving play.

Ground fire at a point locks on the point. Bunker fire from a garrison does not pay a startup.

A startup is a weapon property, `startup_time:` on the weapon's doc entry. Only the MLRS has one.

TODO: the lock is invisible — nothing shows a startup in progress. Whether it wants a readout
(an aim line, a filling ring) is open; elasticity says not every dynamic needs showing.

TODO: this rule departs from
[commitment-and-movement](../../design-framework/commitment-and-movement.md) §Action timing, which
says a startup, once begun, completes even if the target leaves range. Here a lost hold resets it
and nothing fires. The alternatives:

1. **Held lock**, as built. The startup is the price of aiming, repaid on any break; kiting and
   target-switching both pay it.
2. **Committed startup.** Once begun it runs out and the burst fires at the target wherever it is,
   even out of reach; the unit cannot move meanwhile. That is a harder commitment and a telegraph
   the target can dodge by leaving.
3. **Held lock with grace.** As built, but a break shorter than a tolerance (say a quarter of the
   startup) keeps the count. Fewer resets from pathing jitter; less punishment for turning away
   briefly.

### Where a startup earns its place

Generic cases, none tied to a roster piece:

| Case | What the startup buys | Stage |
|---|---|---|
| **Telegraph before a large payload** | the target can react — spread, retreat, break line of sight — so a high-alpha shot has counterplay on the Setup axis | mid–late, as payloads grow |
| **Anti-switching** | retargeting costs time, so focus-fire and overkill-avoidance become commitments rather than free corrections | mid–late |
| **Anti-shoot-and-scoot** | a startup repaid after moving makes a fast unit choose between moving and firing | any stage where the unit is fast |
| **Static defence warm-up** (interruptible) | the attacker gets the first shot, and the defender's hold fire is the interrupt — elasticity for the defender | early; cheap to read |
| **Ramp** — damage or rate rising while the hold is kept (spin-up, beam focus) | an incremental version of the above: a broken hold loses part, not all | mid–late |
| **Charge and release** — release early for less | the player chooses the payload; elastic by construction | late |
| **Lock-breaking counterplay** — smoke, stealth, jamming break the hold | a tech-gated answer to high-alpha locked weapons | late |

Early startups should be short, on static pieces, and interruptible; long or uninterruptible ones
belong where the payload they gate is large enough to be worth a telegraph.

---

## Vulnerable states

A weapon's cycle can impose a state on its carrier. None of these are built; they are framed so a
piece can be designed against them. Each is a form of elasticity's post-attack penalty `δ`, or of
a stronger commitment.

| State                                             | Effect on the kiting terms                                                                                   | Notes                                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| **Reload only while stationary**                  | the reload is spent standing, so `W` buys no ground: every moment moved is a moment of DPS lost, one-for-one | stops shoot-and-scoot outright. A deployed-artillery feel without a deploy |
| **Slowed while the clip is not full**             | `v_k → v_k · (1 − δ)` for the whole of `r`; elasticity's `δ` with `t_δ = r`                                  | graded rather than binary, so it prices kiting instead of forbidding it    |
| **Slowed after firing**                           | `δ` for a fixed `t_δ` after each round                                                                       | taxes fighting-then-leaving; the existing lever                            |
| **Turret locked during the burst**                | the burst cannot follow a crossing target                                                                    | a turret's aim advantage paid back during `B`                              |
| **Armour or damage taken raised while reloading** | raises the tax `f` inside the window rather than slowing the unit                                            | a punish window the opponent can see and time                              |
| **Revealed after firing**                         | a stealthed or fogged unit is visible for a while after a shot                                               | ties fire to exposure; stealth pieces already hold fire                    |
| **No embark while reloading**                     | cannot escape into a garrison mid-cycle                                                                      | narrow; for transport-heavy factions                                       |

### Reload variants

| Variant                                     | What changes                                                                                                                                                        |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Whole clip, from the last round** (built) | breaking off early costs nothing; the clip is always refilled whole                                                                                                 |
| **Per round**                               | rounds return one at a time over `r`; a part-fired clip refills proportionally, so a short burst is cheaper. The incremental option commitment-and-movement prefers |
| **Manual reload**                           | the player chooses when the reload starts: an elastic decision, and a new command                                                                                   |
| **Reload interrupted by moving**            | the reload restarts if the unit moves; harsher than reload-while-stationary                                                                                         |

TODO: which vulnerable states, and which reload variant, any piece should carry. Undecided — the
table is the menu, not a plan.

---

## The MLRS

The worked example. A twelve-rocket salvo, 0.1s apart, then a 10s reload; one second of startup.
Its doc: [an_mechMedium_artillery](../../factions/anarchical/units/an_mechMedium_artillery.md).

- `B = 1.1 s`, `T_c = 11.1 s`, `W ≈ 10 s` less its turns: a long window, the late-game row above.
  It is not a kiter — its reach is its defence — but its window is long enough to relocate
  between salvos, and the lock means a relocation that turns away from the target costs the
  startup again.
- **It hits aircraft**, at its ground reach. A lobbed rocket is aimed where the target was when it
  fired, so it lands on a hovering or slow aircraft and rarely on a fast one.
- **Its rocket is lofted**, launched at 45° under a steeper gravity than the roster's shells so
  that the full-reach flight stays about as long as the old flat arc. The flight is baked into the
  rocket's scene, which only the MLRS fires; a rocket shared with another piece would have to be
  copied before its flight changed.

TODO: whether anti-air fire should use a different flight. A lob at an aircraft is an
unpredictable weapon against anything that moves — which may be the wanted identity (it deters
hovering), or may want a flatter, faster flight when the target is airborne. The second means a
weapon choosing its emission by the target's layer, which no weapon does today.
