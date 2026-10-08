---
title: Commitment expressed through movement
type: design-note
---

# Commitment expressed through movement

**Status: partly decided.** The movement classes, the turret split, hold fire and the rules
for startup are decided (§Movement classes, §Action timing), and health-linked speed is wanted,
from half health. The other disengagement levers and every duration are still open; they are
recorded so the revisit starts from the relationships rather than from a blank page.

**There is no withdraw order.** Leaving a fight should be priced rather than commanded: a
continuous decision a player makes by watching the field, not a button that declares an
intention. This note is how that price is built out of movement properties, and what each
property buys.

The decision being shaped is the one in [decisions](decisions.md) §Commitment — cutting losses —
and the lever it uses is `Loss`, not `p_punished`.

---

## Movement classes

The physics has three modes — `GROUNDED`, `HOVERING`, `FLYING` — and they do not exhaust how
units move. For tractability, movement is thought of in **classes: named bundles of the existing
`Movement` fields** (turn rate, the turn-speed ratio, the reverse ratio, acceleration). A class is
prose, for designers; nothing in the code or the spec schema names one. Speed varies within a
class, relative to units of similar properties ([unit-descriptors](unit-descriptors.md)).

| Class | Mode | Turning | Default values, where the roster already has them |
|---|---|---|---|
| **Foot** — infantry, small drones | grounded | very fast; pivots in place | speed 1.1–1.5, turn 1080°/s, turn-speed ratio 0 (Colonial infantry) |
| **Light vehicle** | grounded | fast; arcs at speed | speed 2.5–2.75, turn 540–720°/s, turn-speed ratio 1, acceleration 1.5–2 (Colonial buggies) |
| **Heavy vehicle** | grounded | slow; three-point turns | — |
| **Slow hover** | hovering | the reverse ratio decides how it kites | speed 1–3, turn 180–360°/s (Colonial hover) |
| **Fast hover** | hovering | the reverse ratio decides how it kites | — |
| **Slow flyer** | flying | banked turns; a wide circle it cannot stop out of | — |
| **Fast flyer** | flying | banked turns; wider still at speed | — |

Speeds are world units per second. The defaults are a starting point to supply on request, not a
standard to hold a piece to.

The speed classes, one ladder shared by units and projectiles, and their values are in
[movement/speed_classes.md](../movement/speed_classes.md); the movement classes built on them
are in [movement/movement.md](../movement/movement.md).

### What each class means in a fight

The same fields that make up a class set its combat character: how well it avoids fire
(§Evasion), how cheaply it leaves a fight it is losing (the tax `f`, §The disengagement tax), and
what it can out-run or be run down by. These are the INTENT for each class. A piece departs from
them deliberately, with its speed within the class or with a turret, not by accident.

| Class | Evasiveness | Commitment once engaged | In a fight |
|---|---|---|---|
| **Foot** | Low. Too slow to cross a projectile's path, so it dodges nothing aimed at it; spreading out against area damage is its only defence. | Cheap to STOP (no turn term), costly to LEAVE: slower than almost every pursuer, so against vehicles and aircraft it sits past the `Δv ≤ 0` cliff and cannot leave at all. | Holds ground; takes and garrisons structures. Kites only slower foot. Out-running it is anyone's answer to it, so its counter is a faster unit. |
| **Light vehicle** | High. Keeps its speed through turns, so it crosses lines of fire and slips unled projectiles. | Low: the skirmisher band. Short `T_out`, positive `Δv` against most things. | Hit-and-run, and runs foot down. Its banding answer is hitscan, area damage, or something faster. |
| **Heavy vehicle** | Low. Slow and wide, so crossing a line of fire is not on offer; it absorbs fire instead of avoiding it. | High: three-point turns make `θ/ω` the biggest term in `T_out`, so a heavy vehicle that has turned to fight has half-committed already. | The line. Chases poorly and cannot kite unless turreted (see **Turreted** below). |
| **Slow hover** | Low. Moves slowly in any direction but crosses fire no faster than a heavy vehicle. | Medium. It turns in place and backs off at its reverse ratio, so `T_out` is short, but its low `Δv` means it rarely breaks contact. | A stable platform: it can stop and hold a point, which a flyer cannot, so it suits sustained fire, spotting and support. Anti-air and fast flyers catch it. |
| **Fast hover** | High, while it is moving. It does not bank, so unlike a flyer it can reverse or change direction outright. | Low. With a high reverse ratio it kites while backing off, and fire and flight need not pull against each other. | Harassment and chasing. It can also stop on a spot, so it trades evasion for a stable aim whenever it chooses to. |
| **Slow flyer** | Low. Cannot stop and cannot turn tightly, so it cannot dodge rockets (§Evasion: slow flyers are meant to be hit). | High inside anti-air coverage: leaving means flying a wide arc through it. | Committed runs: bombing, dropping, loitering where anti-air is thin. It never holds a point exactly; it circles it. |
| **Fast flyer** | High. It crosses a rocket's path fast enough to escape homing fire (`v_perp > ω_m · r_hit`), so it can bait a SAM's salvo. | Low in the fight itself, but it overshoots on a wide circle and must re-attack in passes, and a charged loadout, where it has one, sends it home between sorties. | Strikes and leaves; intercepts. It cannot loiter over a target; its answer is hitscan anti-air or a rocket above its band. |

**Turreted is a separate property**, not a class: whether a unit aims independently of the way
it faces. It removes the turn term from kiting (see [elasticity](elasticity.md) §Kiting) and is
the one change that lets a heavy vehicle kite. Built as a weapon property — see
[combat/turrets](../systems/combat/turrets.md).

PLANNED — **a unit holds its attack target and its movement target separately.** An attack order
registers a target that stays through later movement orders, so a unit can be told to attack and
then to retreat and keeps shooting as it goes. The target is dropped when it leaves range, or by
hold fire (§Action timing). A turret is what makes use of it; a unit that must face its target
still has to choose. Deferred until turrets are built.

---

## Travel time and scouting

**A unit that can threaten a base should not reach it before the defender can prepare.** Two
consequences:

- **Foot units are slow enough that they cannot cross the map fast enough to be a threat on
  their own.** A player who wants them there quickly invests in a transport.
- **The transport route is timed the same way**: raising the infrastructure, training the
  transport and sending it must together take longer than the defender needs to answer.

**Scouting is the exception, and it is paid for with threat.** A scout reaches the enemy base
quickly, so it has little or no ability to threaten it — the Age of Empires and SC2 pattern. The
factions answer it differently:

- **Libertarian** builders fly and have no attack: natural scouts.
- **Anarchical** has no good scout. Its many slow starting builders scout *wide* rather than
  *far*, which suits a faction meant to spread its presence and be hard to pin down.
- **Colonial**'s dominion generator crushes infantry while it scouts — threatening, not
  game-ending. Factions with infantry builders get very early answers to it (Anarchical
  infrastructure garrisons infantry).

TODO: calibrate the crossing times — foot, transport route and scout — against the defender's
response time. Tied to the reinforcement-distance item in the [framework](README.md).

---

## Evasion

**It is good when a unit can be micromanaged to survive fire**, and bad when it can do so
forever. Fast flyers are meant to evade rockets and slow flyers are not; the same expressiveness
is wanted for ground vehicles.

For a homing rocket turning at `ω_m` with hit radius `r_hit`, a target crossing it at
perpendicular speed `v_perp` escapes roughly when

```
v_perp > ω_m · r_hit
```

Flying straight at the shooter makes `v_perp` zero and is hit; crossing its line of fire dodges.
The approximation assumes pure pursuit. **Rockets may lead their targets** if that keeps the
problem from being over-constrained — a leading rocket punishes a steady crossing and rewards
changing direction, which moves the band rather than removing it.

The interaction this is for: **a player baits a SAM's salvo with one aircraft, and the rest fly
past while it reloads** — which works when the reload is longer than a fast flyer takes to cross
the SAM's coverage (about `2 · R_sam / v_fast`). With several SAMs, the defender answers by
spreading targets to avoid overkill.

**The banding rule: every evasive unit has an answer it cannot evade.** A unit that can stay out
of its opponents' range forever, or dodge every projectile aimed at it, has no counterplay. So in
each matchup it meets something faster than it can out-kite (`v_kite < v_c`, [elasticity](elasticity.md)
§Kiting), or a weapon it cannot dodge — hitscan, area damage, or a rocket above its band. This is
M1 ([matchups](matchups.md)) applied to evasion.

TODO: the dodge bands — which rockets each flyer class evades — and whether rockets lead. To be
measured in the simulation harness (`sims/`, [simulation-tests](../systems/scenario-scripting/simulation-tests.md)).

---

## The disengagement tax

| Symbol | Meaning |
|---|---|
| `v`, `a` | speed and acceleration |
| `ω` | turn rate |
| `θ` | the turn needed to leave — 180° for a unit facing what it is leaving |
| `t_h` | holster: time between "stop fighting" and "move at all" |
| `δ`, `t_δ` | post-attack speed penalty, and how long after the last shot it lasts |
| `Δv` | own speed minus the pursuer's |
| `r` | the pursuer's reach, plus whatever margin counts as safe |
| `σ` | suppression: the fraction of speed incoming fire takes away |

```
time to get moving     T_out = t_h + θ/ω + v/a
time to break contact  T_gap = r / (Δv · (1 − σ))          Δv ≤ 0  ⇒  unbounded
exposure               T_exp = T_out + T_gap + δ · min(t_δ, T_gap)
the tax                f     = DPS_in · T_exp / HP
```

**`f` is the number to design against**: the fraction of a unit's health it pays to leave a fight
it is losing. Suggested bands, to be checked in simulation rather than by eye — a skirmisher
around 0.05, a line unit 0.15–0.25, a siege or deployed piece 0.5 and up, where leaving is not
really on offer and the commitment *is* the unit.

**The cliff is `Δv ≤ 0`.** A unit slower than what is chasing it cannot buy its way out at any
price; `f` stops being a tax and becomes the whole unit. Which side of that line each piece sits
on is a bigger design statement than any of the smooth levers below, and it is worth deciding
deliberately per matchup rather than falling out of speed numbers chosen one piece at a time.

---

## The levers

**Turn rate `ω`** — costs `θ/ω`, so the authored range in the game today (roughly 120 to 1080
degrees per second) already spans over a second of exposure. It is the cheapest and most legible
lever, and the only one that is *directional*: a nimble unit can leave from anywhere, while a
slow-turning one has to decide which way it will leave **before** it commits, which is a read
made in advance.

**Holster `t_h`** — a flat toll on disengaging, paid whether or not the unit just fired. It reads
as packing up, so it belongs on pieces whose weapon is a setup rather than a rifle, and it pairs
naturally with a deployed stance.

**Post-attack penalty `δ` over `t_δ`** — the unit may move after firing, but at `v·(1 − δ)` until
`t_δ` has passed. This taxes *fighting and then leaving*, which is different from taxing leaving,
and it is the lever that prices kiting:

```
effective travel speed while fighting   v_eff = v · (1 − δ · min(1, t_δ / T_c))
```

for a weapon cycling every `T_c`. So `δ` and `t_δ` together answer "can this unit fight while
repositioning", on a dial rather than as a yes or no. **Fire/move exclusivity is this lever at
`δ = 1`**: the unit stops to shoot, and its advance rate is `v · (1 − t_f/T_c)`.

**Suppression `σ`** — incoming fire takes speed away. Because it divides into `T_gap`, the tax
grows as `1/(1 − σ)`: mild at 0.2, brutal past 0.6. What makes it interesting is *who* controls
it — suppression is commitment **imposed by the attacker** rather than chosen by the defender,
which is the only lever here that the opponent operates. What makes it dangerous is that it
compounds with focus fire, and it lands hardest on the player already losing the engagement. Keep
it modest, cap it, and consider making it a property of the damage type rather than of damage.

**Health-linked speed** — wanted, and it begins at half health: a unit above 50% moves at full
speed, and below it

```
v(hp) = v_min + (v_max − v_min) · (2 · hp / hp_max)^α
```

`α < 1` brings the penalty on early and levels off; `α > 1` keeps a unit fast until it nearly
dies, then drops it. Both `Δv` and `T_gap` worsen as health falls, so **the tax rises exactly when
the unit can least afford it** — positive feedback inside a fight, which raises punish magnitude
everywhere rather than only late (G3 wants that curve, so watch it).

`v_min` matters more than `α`: a floor at or above the common pursuit speed keeps "damaged" from
quietly meaning "dead". Set right, this is the lever that best answers the withdraw question,
because it turns *when do I pull back* into a continuously priced decision read off a health bar —
pull out early and cheaply, or stay and pay more to leave later. No command, no new UI.

TODO: whether it applies to every frame or only to MECH — an engine losing power reads; a
wounded soldier slowing down is a different, heavier claim.

**Acceleration `a`** — usually a small term, and mostly an aircraft lever. The fields already
exist.

---

## Action timing

**Incremental mechanics are preferred over all-or-nothing ones**, because each increment is
another point where execution matters. Examples: captives unloaded one at a time, a slowdown that
begins past half health, a clip emptied over time rather than in one volley, units trained in
pairs so each is weaker but the pair can be in two places (the Zero Hour Red Guard).

The fighting-game vocabulary, mapped:

- **Startup** — the time before an action has any effect: turning to face the target, and an
  attack startup where a weapon has one — a target held for a set time before the first shot
  ([weapon-cadence](../systems/combat/weapon-cadence.md) §Attack startup). It is the telegraph.
- **Active** — instant for a projectile. Something that emits persistently — a lazer — has a
  real active window.
- **Recovery** — the time after acting during which the actor is committed and open to a follow-up:
  the holster and the post-attack penalty above.

**The rules for startup:**

- The target must be in range when startup begins. Once it has begun, the emission completes
  even if the target leaves range — the actor stops when its salvo is out, or when it is
  interrupted. TODO: the built attack startup does NOT follow this — a lost hold resets it; see
  [weapon-cadence](../systems/combat/weapon-cadence.md) §Attack startup for the alternatives.
- **Some startups are interruptible and some are not.** Static defence, where it has a startup,
  should be interruptible: it gives the defender elasticity. Hold fire is the interrupt.
- **Deploying is conceptually a startup.** Whether a deploy may be called off is per unit
  (`deploys.cancellable`); the Libertarian tanks' may not — a deploy is finished and then
  undeployed ([deploying](../systems/commands/deploying.md)).

TODO: whether an action is interruptible could be a flag on some shared description of how an
action is fulfilled; no such description exists yet.

**Hold fire** is a flag rather than an order (`Actor.is_holding_fire`), toggled from the
command card: it leaves the queue alone, and an Attack, Attack-move, Force Fire or Defend lifts
it. Stealth units are its main customer — a
piece holds fire the moment it gains stealth. Once startups exist it is also their interrupt.

A hold fire issued with the additive modifier is queued, and takes effect when the queue
reaches it (`SetHoldFire`, setting what the toggle meant when it was pressed).

### Commitment, per action

| Action | Today | Direction |
|---|---|---|
| Build | timed; the builder may leave and return | build times are a commitment and are tuned as one |
| Deploy / undeploy | timed (3 s / 1 s on the Libertarian tanks); immobile and unable to fire throughout | cancellable per unit ([deploying](../systems/commands/deploying.md)) |
| Stock-truck unload | every captive at once | PLANNED — one captive at a time, which also sets the dominion rate ([proposals](proposals.md) §The model) |
| Attack while moving | stop to fire, except aircraft that cannot hold still, and a turret, which keeps shooting its attack target through a move ([turrets](../systems/combat/turrets.md) §Attacking while moving) | turreted is a property (§Movement classes). TODO: per-unit `δ` above, where δ = 1 is stop-to-fire |
| Startup | turning to face; an attack startup on the MLRS, kept through its reload | only where it earns its place — the rules above, and the cases in [weapon-cadence](../systems/combat/weapon-cadence.md) §Where a startup earns its place |
| Repair | a repairer works whenever it is in reach, so it can follow a moving patient; stagger blocks it | TODO: whether either party may move. An interesting knob; the long-term shape is undecided |

---

## Stagger as a damage-type property

The related idea — stagger applying only to certain interactions — is best expressed as **one
more column in the damage table**: each damage type carries a stagger (or suppression)
coefficient, next to its armour and frame multipliers.

- It gives types a **second identity axis**. Lead is anti-light by its multipliers; a stagger
  coefficient would make it anti-*action* as well, which is what a machine gun is for.
- **Healing denial becomes selective.** Stagger blocks healing, so which damage types can shut
  down repair turns into a real matchup question — and one that needs checking against M1, since
  a faction with no staggering damage has no way to stop an opponent mending under fire.
- **The cost is complexity budget.** Stagger is currently generic, which is what pays for its
  several rules. Putting it in the damage table is the cheapest way to keep it legible while
  making it selective: the table is already the thing players learn, and one vocabulary across a
  schema beats a bespoke rule per weapon.

---

## What this would add, minimally

Three authored numbers and one column, all on things that already exist:

- per unit: `δ` and `t_δ`; `t_h` where the weapon is a setup
- per unit: `v_min` for health-linked speed, with `α` shared globally
- per damage type: the stagger/suppression coefficient

Together they produce withdrawal as a decision without a withdrawal command. Note what stays
untouched: **stagger never blocks movement**, which is deliberate and consistent with all of the
above — leaving is priced, never forbidden.

TODO: choose target bands for `f` by role, then measure them in the simulation harness rather
than by eye.
