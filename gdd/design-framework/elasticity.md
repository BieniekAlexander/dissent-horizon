---
title: Execution elasticity — what it is, and what tunes it
type: design-note
---
# Execution elasticity

**An option is execution-elastic when its effectiveness rises with marginal execution effort.**
Not pass/fail: a player squeezes out more damage, uptime, safety or utility by performing the
same action better. E. Honda's Hundred Hand Slap is the canonical example; a resource truck that
collects at a fixed rate is the opposite.

Why this game wants it: it is the surface on which **a player who is behind on resources can
still win**, and it is what makes G9 measurable rather than a slogan.

---

## Mechanical options

What elasticity is measured against is a **mechanical option**: *mechanical* because it asks for
more input from the player, *option* because options are generally mutually exclusive. The
exclusivity is what makes an option cost attention — the player is choosing, not stacking:

- A unit that cannot move and attack at once trades movement against damage. A unit that can
  fire on the move softens the choice without removing it: auto-targeting still stops it once a
  target is in reach, and a manual order is what keeps it moving.
- A unit attacks one target at a time.
- Positioning decides what a unit can do at all: an option has an effective range (shooting
  versus crushing), speed is how quickly a unit can change which options it has, and a concave
  keeps friendly units from blocking each other out of range.

### Generic options

**Generic** options apply across much of a roster, to a degree set by each unit's properties —
you cannot kite with an actor that cannot move. Because every unit meets them, a unit's generic
properties (speed, turn rate, range, reload, durability) are tuned with them in mind; the
descriptors those properties cluster into are in [unit-descriptors](unit-descriptors.md).

| Against your own units | Against the opponent |
|---|---|
| avoiding overkill | focus-firing key targets |
| kiting | splitting to avoid area attacks |
| splitting a payload across targets | staggering units to block their healing and building |
| preserving units (and their veterancy) | |

### Specific options

Some options belong to one unit, one faction, or a few pieces across factions. Faction mechanics
are out of scope here, but much elasticity is situational on which units meet, and some of those
meetings are faction-specific.

### Options that need two units

- **Garrisoning** preserves a unit — it may fire from inside a bunker — at the cost of mobility.
  How the door's timing should work is open: see
  [garrison-and-transport](../systems/combat/garrison-and-transport.md) §Entry and exit take no
  time.
- **Transport** repositions a less mobile unit, at the cost of its output while carried and of
  one sniped transport killing every passenger.
- **Dependence**: one unit completes another's option — a spotter for artillery, a sapper
  planting on a friendly vehicle.

---

## The shape of an elastic option

For one unit, with `a` the execution effort spent on it per unit time:

```
E(a) = E₀ + ΔE · g(a / a*)          g concave, g(0) = 0, g(∞) = 1
```

| Term | Name      | What it says                                                          |
| ---- | --------- | --------------------------------------------------------------------- |
| `E₀` | **floor** | what the unit does with no attention at all                           |
| `ΔE` | **band**  | how much skill can add — the ceiling minus the floor                  |
| `a*` | **price** | the attention that saturates it; the window's width is what sets this |
| `g`  | **curve** | concave, or the returns do not diminish                               |

And at the army level, where it actually gets decided:

```
army gain ≈ ΔE · min(c, N) · g( A / (min(c, N) · a*) )
```

with `N` units, `c` the **concurrency** — how many instances can be serviced at once — and `A`
the player's whole attention budget.

**Two distinct ways elasticity goes wrong, and they need different fixes:**

- **`ΔE` large against a near-zero `E₀`.** The option is really pass/fail wearing elasticity's
  clothes: the SC2 disruptor, where a misplaced shot is worth nothing and a placed one decides
  the fight. Fix the FLOOR, not the ceiling.
- **`c` unbounded.** Each unit is independently elastic in several dimensions, so gains multiply
  with army size — the Zero Hour technical, elastic at combat, salvage, transport, scouting and
  running units over, all at once and all the time. Fix the CAP.

---

## Measuring an option

The formula holds the opponent fixed. An option is measured on five axes, and the fourth of them
is the opponent's:

| Axis            | Question                                                                                                | In the formula                                |
| --------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **Investment**  | What are the prerequisites — upgrades, technology — to realising the gain?                              | tech depth; see §The budget over a match      |
| **Specificity** | How pervasively can it be used?                                                                         | the scope knobs                               |
| **Tradeoffs**   | What does performing it open the player up to? What does bad execution cost, against not trying at all? | the floor, and the costs of use               |
| **Setup**       | How much must the situation be set up, and how far can the opponent get ahead of it?                    | none — the opponent's side                    |
| **Scalability** | How much does each further unit of input add, and across how many units at once?                        | the curve `g`, the price `a*` and the cap `c` |

The band `ΔE` and the floor `E₀` stay named on their own: the axes say how an option pays, and
these two say how much, and from where.

**Setup is where counterplay lives.** Every interaction presumes proximity, so lower speed and
shorter reach already mean slower setup and more time to answer. Three reference points:

- **SC2 blink**: almost no counterplay — there is nothing to react to.
- **Zero Hour aurora bombers**: good counterplay. The target can pre-split against the strike,
  but pre-splitting has its own costs and the window to split is tight.
- **Zero Hour bomb trucks**: counterplay so easy the option is nearly worthless — a disguised
  truck is spotted and killed, and an intercepted truck's reward is zero. A high-risk option
  with a near-zero floor, which is the first failure above.

**Tradeoffs, in two cases.** Deploying is a short positional commitment against an output reward.
SC2 siege tanks are overtuned on this axis: deploying is quick, the tank is effective against a
great deal, and it is easy to defend. A unit that fires on the move pays no tradeoff at all.

**Scalability, at its extremes.** Infinite kiting is the perfectly elastic action: a unit faster
than its target and outranging it can kite it forever (§Kiting). The Zero Hour air payload is the
counter-example: the units are expensive enough that a player has few, and their tight windows
force staggered commands, so attention cost rises faster than linearly.

---

## The knobs

Sorted by which term they move.

### Band knobs — how much is on the table

| Knob | What it does |
| --- | --- |
| **Movement speed, turn rate, acceleration** | Position is continuous, so the rate at which a unit can change position sets how much of the positional value gradient a player can capture: `ΔE_position ≈ speed × ∇V × time`. This is why fast units are elastic by default, and why fast *and* flexible compounds into a technical. |
| **The value gradient `∇V` itself** | Range bands, area radius against unit spacing, damage falloff, armour and frame multipliers. **A flat value surface is inelastic at any speed** — no amount of execution improves a position that is worth the same everywhere. Most of the band comes from here, not from the unit. |
| **Same-team obstruction** | Units block each other from reach, so spacing and concave are worth output. A unit firing from where it stands yields to no friendly unit, so freeing room for the ones behind it is the player's job — see [navigation-and-pathing](../systems/terrain-and-navigation/navigation-and-pathing.md) §Avoidance priority. Short reach narrows the arc a unit can engage from, so obstruction is far more elastic for melee and short-range units. |
| **Persistence of gains** | See §Veterancy: it converts one-off execution into a lasting stat, so every earlier success is multiplied by everything that follows. |
| **Payload size per decision** | How much rides on the one moment — a full clip versus a single shot, a whole attack run versus a strafe. |

### Price knobs — how hard it is to get

| Knob | What it does |
| --- | --- |
| **Window width** | The timing or position tolerance. Narrow windows raise `a*` steeply, and they cut concurrency too, because two narrow windows cannot be served at once. |
| **Animation cancelling** | A recovery the player may cut short by issuing the next order — the SC2 roach stands still to fire, and a move order ends the backswing. The skipped recovery is the band; catching the moment is the price. |
| **Information legibility** | What the game shows moves `a*` without touching a combat number. **But not every elastic dynamic needs to be shown**: players pick many of them up intuitively, or learn them from resources outside the game, and that discovery is part of the skill surface. Reserve in-game visualisation for things a player must know to play at all. |
| **Selection and control friction** | Control groups, per-unit versus group orders, whether an ability distributes itself across a selection. This is the attention price, directly, and it is the right knob when an option is "elastic in principle, but only above 250 actions a minute". |
| **Assists and automation** | Anything the game does for the player *lowers* `ΔE` on purpose: auto-retargeting, attack-move behaviour, rally points, formation movement, the production queue, unit tasking. This is a dial, not a courtesy — see §Where the budget is spent. |

### Cap knobs — how far it scales

| Knob | What it does |
| --- | --- |
| **Window simultaneity** | **The strongest cap, and the least obvious.** If N units' decision windows coincide, `c` collapses toward 1 however large the army: the player can only be in one place in that second. The Zero Hour raptor is elastic per unit and barely more elastic per squadron, because the payload system forces every raptor's window into the same overlapping moment. Take the recharge cycle away and the same skill staggers the windows and multiplies across the battle. |
| **Duty cycle: split, reload, clips, rearm trips** | Sets how many decision points a unit offers per minute. Long recharge means few, large decisions — and it is what forces simultaneity above, so these two knobs are one mechanism seen twice. A projectile split is usually too brief to reposition in; a reload usually is not (the Zero Hour rocket buggy), and the reposition is where the band is — see §Kiting. |
| **Concave payoff by construction** | Overkill avoidance can only ever recover the damage that would have been wasted, so its returns diminish on their own. Prefer this to an imposed cap, which reads as arbitrary. |

### Costs of use

An option's use can be priced in several currencies, and a rate limit is only one of them:

| Cost | Example |
| --- | --- |
| **Time** | SC2 blink's cooldown |
| **Health or resources** | SC2 stim: damage and speed now, health later |
| **Capability forfeited while active** | SC2 roach burrow: stealth and regeneration, but slow or immobile, and no attacks |
| **Commitment and exposure** | a deploy or pack-up time — see [commitment-and-movement](commitment-and-movement.md) |

**A rate limit is for an option that would be degenerate unlimited** — blink is instant
movement, so without a cooldown a stalker's speed would be unbounded. The other costs shape the
tradeoff instead, and a cost like stim's makes a mistimed use worse than none, which gives the
option a negative floor on purpose.

### Scope knobs — when and where it applies

| Knob | What it does |
| --- | --- |
| **Counter hardness** | A hard counter bounds the *situations* an elastic tool is relevant in: the Zero Hour missile defender's laser targeting is available very early and is fine, because the unit does nothing to infantry. Soft counters (SC2) make every elastic tool relevant everywhere, which multiplies elasticity and makes it much harder for the opponent to contest. **Counter hardness is an elasticity knob, not only a balance one.** |
| **Tech depth of the unlock** | Where the elastic surface arrives. Early options: small band, wide windows, high floor. Widen through upgrades — the blink pattern is *ship the band small, sell the widening*. |
| **Frame, layer and target restrictions** | The same scoping in miniature: an elastic tool that only works on MECH targets is elastic in fewer matchups. |

---

## Kiting

Units attack only while stationary today; some future units will fire on the move. Take a kiter
retreating from a chaser, with the symbols of
[commitment-and-movement](commitment-and-movement.md):

| Symbol | Meaning |
|---|---|
| `T_c` | the kiter's weapon cycle — split and reload together |
| `t_f` | time stationary to fire, including any recovery not cancelled |
| `θ/ω` | time to turn, at turn rate `ω` — paid twice per cycle when retreating, to face and to leave |
| `v_k`, `v_c` | kiter and chaser speed |
| `R_k − R_c` | the kiter's range advantage |

The kiter's average retreat speed over one cycle is

```
v_kite = v_k · (1 − (t_f + 2θ/ω) / T_c)
```

reduced further by any post-attack penalty `δ`. For a burst weapon, `t_f` is the burst and
`T_c` the burst plus the reload — the terms worked out in
[weapon-cadence](../systems/combat/weapon-cadence.md) §When kiting pays. **Kiting is free forever
iff `v_kite ≥ v_c`.**
Otherwise the range advantage is a buffer that lasts about `(R_k − R_c) / ((v_c − v_kite) · T_c)`
cycles.

What each property does to it:

- **Turn rate** does not touch kiting while advancing, and punishes it while retreating. A turret
  decouples aim from heading and removes the term entirely.
- **Acceleration** is a small addition to the stop time.
- **Animation cancelling** makes part of `t_f` optional, for a player who catches it.
- **Reload time works both ways.** A longer `T_c` lowers the floor — more of each cycle is spent
  idle — and lowers the speed a unit needs to kite forever, so it widens the band too.
- **A speed penalty while targeting or reloading** scales `v_k` only in the retreat phase, which
  makes it the most direct lever on whether kiting is free. Standing still to reload is its
  extreme: a real trade between repositioning and the duty cycle.
- **Facing-dependent armour** (Kane's Wrath) has no tradeoff while reverse movement is free,
  because reversing removes the turn term. It would need reverse speed below forward speed.

**Infinite kiting is acceptable late and not early.** A late-game match rarely has one front, so
a player who spends attention kiting has spent it somewhere they could not afford to. The
condition gives the gate a checkable form: no early pairing should satisfy `v_kite ≥ v_c`.

TODO: auto-targeting ranks by target priority and then distance across the whole aggro range,
not by what is already in reach — see navigation-and-pathing §Avoidance priority. Whether an
in-reach target should win is undecided.

---

## Veterancy

Veterancy is built: four levels, experience from damage dealt, kills and completed builds,
paying **+10% damage per level to +30%** at heroic. It is a **persistence** knob, and it works on
both sides:

- **It rewards preserving units** rather than replacing them, so every earlier execution success
  compounds. Production is streamlined enough that the choice between preserving a unit and
  replacing it is not a pressing attention cost, but it is one to keep watching.
- **It gives the opponent a second elastic surface**: a visible rank is something worth sniping,
  and the larger the rank's payoff, the larger that incentive.

**Large jumps in power are wanted**, as long as the experience to reach them is priced to match.
C&C veterans grow in damage *and* durability and become very hard to answer cost-effectively; a
tank that heals itself and is five times as durable can still be fair if it had to destroy twenty
tanks to get there. So the tuning measure is **the power a rank confers against the kills it
takes to reach it**. Two things shape it:

- **Durability compounds.** A tougher unit survives to earn the next level, so a rank that grows
  durability needs a steeper experience curve than one that grows damage.
- **Stagger limits self-healing.** A hit blocks healing, so a veteran that heals itself is still
  answerable by sustained chip damage.

TODO: calibrate per unit — what each rank grants (durability, abilities) and the experience
thresholds to reach it. Deferred; the thresholds are one table today (`Veterancy`).

---

## Where diminishing returns must come from

In order of preference:

1. **Concurrency** — attention is spent per unit, and coinciding windows cap the total.
2. **Concave payoff by construction** — the gain is bounded by the waste it recovers.
3. **Costs of use** — cooldowns, charges, and the other currencies above.

Avoid an imposed ceiling ("the bonus caps at 5"), which players read as arbitrary and which
teaches nothing about why.

---

## Where elasticity is allowed to live

**Elasticity belongs where the game touches the opponent** (G11). Execution that pays off
against neutral features, or against the player's own economy, spends a player's attention on
something the opponent cannot contest. Warcraft III is the example: micro-intensive tricks that
gather faster, and creeping against neutral camps — much of the challenge never comes from the
opponent, and because the payoff is economic it decides whether a player can field an army at
all.

Two consequences, cutting in opposite directions:

- **A band on an opponent-facing action is the good kind**, even a large one: the opponent can
  answer it, and the answer is the game.
- **A band on a private routine is a tax**, not a skill surface. It rewards practice rather than
  reading an opponent, and it punishes the player with less time to drill rather than the one who
  played worse.

---

## The budget over a match

Total reachable band at tech depth `d` should follow the volatility curve (G3): **low early.**
This is the micro subgoal in [pacing](pacing.md) — elasticity starts low and is unlocked by depth
— and the volatility curve and the elasticity curve are the same curve seen twice. If early
options are highly elastic, a mechanically stronger player wins the mechanics competition before
the match becomes a game, and an opponent with different strengths never gets to play.

- **Early: small band, wide windows, high floor.** An early elastic option should be worth
  having un-micro'd.
- **Elasticity arrives through unlocks** — research, tech depth, an upgrade.
- **Every faction gets several high-band options at depth**, or its late game has no skill
  surface.
- Scope is a legitimate substitute for depth: an early elastic tool is acceptable when it is
  narrow enough (hard-countered, frame-restricted) that the opponent can sidestep it.

This is checkable with the role tags in [auditing](auditing.md): tag the elastic pieces, derive
depth from the tech tree, and the rules become "no high-band option below depth X" and "at least
N per faction by depth Y".

---

## Where the budget is spent here

**The economy has a low floor and low overhead, and its ceiling is set by the opponent** (G1).
Primary resource collection asks for little input, offers coarse decisions, and supports
pre-commanding: one collector type, a production queue that charges on submit, unit tasking that
turns a hauling loop into one order. A player sets up investments in a few quick orders and
front-loads them into combat downtime, freeing attention for combat. The economy is not trivial —
its decisions still adapt to the opponent — but outcomes are meant to be decided mostly by what
is done in combat. Keep new macro conveniences in that column.

**The secondary resource is the exception, deliberately.** It is far more contestable, so it asks
for more input; its rewards aggregate slowly and compound from primary investment, so players
fight over it across the whole match, and a game-swinging payoff needs a large investment.

**Selling is `REJECTED` partly on these grounds** — beyond complicating the economy, it is a
large elastic band on a private routine (G11), and it lets a player walk back investments
cheaply, which weakens every commitment the rest of the design prices.

**Elastic surfaces the game already has:** spotting and bombard placement, the aircraft rearm
cycle (the duty-cycle and simultaneity limiter, already built), lazer warm-up, point-defence
coverage, freeze timing, the Sapper's plant and fuse, capture by crush, and garrisoning for
preservation.

**Overkill avoidance is already an elastic surface, and needs nothing added.** Projectiles
travel, so damage is committed at launch and resolved later, and auto-targeting picks the nearest
of the most important targets with no notion of damage already on its way — so a group engaging
a group wastes the shots that land after their target dies. Splitting and redirecting fire
recovers that waste. It is left **implicit** on purpose: no readout, no overkill-aware
auto-targeting. Players find it by intuition or learn it outside the game, its payoff is concave
by construction (it can only recover waste that exists), and it concentrates in slow,
high-damage shots that sit later in the tech trees.
