---
title: Static defence — what each faction's fixed defences cover, and what they must not
type: design-note
---

# Static defence

Resolves [deferred](../deferred.md) 1.22 (static defence calibration). The open questions this
answers were posed in [pacing](pacing.md) §Static defense considerations; the axes it measures
against are [elasticity](elasticity.md)'s. Piece stats live in the spec docs, not here.

## What a static defence is for

A static defence is a short-term, positional investment that trades against mobile forces and
economy. Because it has that trade-off, it may be tuned **strong per cost**, and — because
projectile travel time already limits what it can hit and choke points are wide — its reach may
be on the larger side.

It is **not** a faction's whole defence. Each faction defends with four tools — static, garrison,
deploy, mobile — and the static column exists to cover the target classes the faction would
otherwise struggle with **early**. The cells it leaves empty are empty on purpose and are answered
by mobile units or by later tech.

### The coverage matrix

Audit each faction's defence as target classes × tools:

- **Target classes:** bio-light, bio-heavy, light mech, medium/heavy ground mech, slow air,
  fast air, structures/siege, stealth.
- **Tools:** static, garrison, deploy, mobile.

A faction's static column should read as a deliberate subset, with the holes named.

### Invariants

Agreed 2026-09-28. These are the only cross-faction commitments; everything else (build time,
tech requirement, reach class, footprint, clip windows, counter hardness) is per faction, so a
future faction is not pigeonholed by the current three.

1. **INVARIANT** — no single static covers more than two target classes. Each has a main target
   class and one it hardly touches (counter hardness, [elasticity](elasticity.md) §Scope knobs),
   keeping a Zero Hour-style floor against its non-preferred targets.
2. **INVARIANT** — no faction's static layer covers every target class.
3. **INVARIANT** — static reach stays below the tech-1+ artillery reach classes
   ([shapes](../shapes/shapes.md)), so "long-term investments trump statics" holds everywhere.
4. **INVARIANT** — any warm-up on a static is interruptible, with hold fire as the interrupt
   ([commitment-and-movement](commitment-and-movement.md) §startup rules).
5. **INVARIANT** — statics are MEDIUM armour; STRONG stays reserved for command centres and
   similar ([deferred](../deferred.md) 1.20).
6. **INVARIANT** — each faction has at least one **medium-tier detection source available at low
   tech**, in whatever form. (Not "a detecting static": the Anarchists have no statics.)

Statics are generally low tech, but need not share one tier. Structures in general take long to
build, which is what stops aggressive (forward) placement being abused; stagger lets a small
defending force interrupt construction on top of that.

## Alpha strike

**Decided (Alex, 2026-10-02): statics carry a high alpha strike**, so they are proportionally more
effective early, against small unit counts. Found in play: Watch Towers against Badgers. Cadence
terms (alpha `A`, burst `B`, cycle `T_c`, sustained DPS `D`) are
[weapon-cadence](../systems/combat/weapon-cadence.md)'s.

**TODO — research.** The numbers below are a paper calculation, not self-play. They are a
starting point to check in play.

### Why alpha, and not just DPS

A static is one shooter against a group. The group's damage arrives in **volleys**, one per
attacker reload. Every attacker the static removes before a volley takes that attacker's share
out of every volley that follows. So damage landed **early** is worth more than the same damage
spread across the cycle, and alpha is damage landed early.

That is also why alpha favours **small** groups. Against two attackers, one burst that kills one
of them halves the incoming damage for the rest of the fight. Against eight, the same burst
removes an eighth, and the group's first volleys kill the static before its DPS matters. The
static's edge fades as unit counts grow, which is the shape wanted: statics hold the early game,
and armies and long-term investments (the Bombard, artillery) beat them later.

### The calibration target: break-even group size

For a static and the attacker it has to hold against, the number to set is

```
N*   the smallest group of that attacker that kills the static
```

and the check is the **exchange below N***: the static should kill at least its own price in
attackers before the group breaks off or dies. Set `N*` from the early-game group size of the
threat. First contact is about ten basic units of army in total
([income-and-cost](../systems/macroeconomics/pacing/income-and-cost.md) §The decided targets),
so a specialist squad there is about two to four units.

Three rules of thumb for getting `N*` from alpha:

- **One burst kills one target.** `A ≥` the hit points of the static's main target unit (after
  the damage table), with a little margin. Below that, the first burst kills nothing and the
  group fires its second volley at full strength.
- **The burst lands inside one attacker reload.** `B` well under the attacker's reload (Badger:
  1.5 s), so the kill happens before the next volley rather than across it.
- **Round damage divides the target's hit points evenly.** A round that leaves a target at 5 HP
  wastes nearly a whole round. Today's 15 needs 6 rounds for an 80 HP Irregular (90 damage) and
  7 for a 100 HP Badger.

The other knobs move `N*` too, and differ in what they change:

| Knob | Effect on `N*` | Cost |
|---|---|---|
| **alpha** (clip × round damage, short split) | raises it most against **small** groups | a long reload is a window to bait the clip (the SAM's counterplay, §The SAM against cross-ups); one bait now costs the baiter a unit |
| sustained DPS | raises it at every group size | is also more damage against non-preferred targets (invariant 1) |
| hit points | raises it at every group size; a flat number of attacker volleys | delays rather than wins: does not front-load kills |
| reach over the attacker | free bursts while the group walks in, which is exactly when alpha is worth most | bounded by invariant 3 (below artillery reach) |

### Watch Tower against Badgers

The two have the **same reach** (`ground_range_long`, 12), so neither gets free shots, and the
Badger's rocket (40 EXPLOSIVE) does full damage to the tower's MEDIUM MECH. A tower (400) costs
two Badgers (200 each).

Badger damage to the tower is 40 × 1.0 × 1.0. Tower damage to a Badger (100 HP, LIGHT BIO) is
15 × 1.0 × 1.0. Badgers walk in together (the tower's worst case), all in range at once, with a
0.8 s rocket flight; the tower retargets at once and wastes no rounds.

| Variant | Alpha | DPS | Tower survives up to | Badgers that kill it, and what they lose |
|---|---|---|---|---|
| **today:** 4 × 15, split 0.23 s, reload 1.5 s | 60 in 0.7 s | 27 | 2 Badgers | **4 Badgers (800) kill it for 1 lost (200)**; 3 kill it for 2 |
| same DPS, more alpha: 7 × 15, split 0.1 s, reload 3.25 s | 105 in 0.6 s | 27 | 3 | 4 kill it for 2 lost |
| 4 × 25, split 0.1 s, reload 2.2 s | 100 in 0.3 s | 40 | 3 | 4 kill it but all four die (800 for its 400); 5 kill it for 2 lost |
| **6 × 25, split 0.1 s, reload 3.0 s** | 150 in 0.5 s | 43 | **4** | 5 kill it for 2 lost |
| today's gun, 650 HP | 60 | 27 | 3 | 4 kill it for 1 lost |

**Finding: today a group of four Badgers kills a tower for one Badger, half the tower's price**,
and three trade about evenly (two Badgers, 400, for the 400 tower). With early squads of two to four, the tower loses the matchup it is meant to
win: Badgers are LIGHT BIO, the tower's own target class.

Readings from the table:

- **Rearranging the same DPS into a burst is worth one Badger of `N*`** (2 → 3) at no cost in DPS
  against anything else.
- **Hit points alone** move `N*` as much but do not front-load kills: against four, the 650 HP
  tower still dies having killed one.
- **The 6 × 25 burst** holds four Badgers and kills all four before falling. It is the candidate
  starting point. It also raises DPS by about half against everything else, LEAD's floor included
  (about 17 against light mechs, up from 11): check that against invariant 1.
- **Past `N*` alpha stops mattering.** Five or more Badgers kill most 500 HP variants on their
  third volley (3.8 s): 13 rockets kill the tower, and five Badgers fire 15 in three volleys. That
  is the intended late-game shape.

Not modelled, and worth a self-play check: staggered arrival (which favours the tower), Badgers
breaking off to bait a long reload, focus fire from other units, and the tower's build time.

**Open: reach.** Equal reach is the Badger's main advantage. A tower one or two cells longer than
`ground_range_long` would get a free burst on every approach at SLOW speed (1.65/s), which is the
moment alpha is worth most. There is no shape between `ground_range_long` (12) and
`ground_range_artillery` (20) today, so this would need a new bucket under invariant 3.

**The other anti-mech infantry.** The Anarchist Warlord (250, 160 HP, MEDIUM BIO, the same 40
EXPLOSIVE rocket at the same reach) is a harder case: LEAD does 0.6 to it, so a 6 × 25 burst lands
90 of its 160. The tower is not meant to cover bio-medium cleanly (invariant 1), but the Warlord
is the Anarchists' early anti-air and anti-tower unit at once, so check it in self-play.

## Colonials

Doctrine "strong defences, small deployments". Three statics:

| Piece | Covers | Tier | Detection |
|---|---|---|---|
| [SAM](../factions/colonial/structures/cl_defense_antiAircraft.md) | air | Compound | — |
| [Watch Tower](../factions/colonial/structures/cl_defense_antiLight.md) | bio-light (LEAD) | Compound | `detection_medium` |
| [Bombard](../factions/colonial/structures/cl_defense_antiStructure.md) | structures; units near a spotter, with effort | Operations Center | — (never) |

**Deliberate hole:** medium/heavy ground mech (MLRS, War Wagon, Toxin Tractor, MDC), answered by
the Matilda, the Badger and the Bombard's own effortful unit fire. **Note** the Watch Tower's LEAD
does 1.0 to bio-light but 0.4 to Libertarian light mechs and 0.24 to medium mech — it is in practice
anti-Anarchist-infantry, which is intended: the SAM covers most of the Libertarian threat.

**The Watch Tower can't be a reaction to early pressure.** Its long build time means it has to be
placed ahead of a threat. That is intended: a static is a positional bet.

### The SAM against cross-ups

Fast flyers are meant to be able to cross up a SAM site; well-spread SAMs should make that
impractical. The clip (3 missiles, split, then a reload) is the attacker's window — bait the clip,
cross during the reload — and spreading works because reload windows overlap without the sites
obstructing each other. Keep the 1×1 footprint and moderate reach, which favour spreading over
clustering.

### The Bombard

The Bombard is the one Colonial static that sits higher: it is the faction's long-term answer to
other factions' statics. System rules: [bombardment](../systems/combat/bombardment.md).

- **Reach by spotting.** The Watch Tower carries a `BeaconRange`, so it spots for the Bombard for
  free. Its spotting radius is a knob of its own, kept at or below the tower's vision
  (TODO — calibrate).
- **Usable against units, with effort.** Whether a shot lands depends on the target's speed, the
  shell's flight and the distance. Shots spotted close to the Bombard are reliable; long shots
  are at real risk of missing and very rewarding when they land. A zero floor on long shots is
  an **accepted risk** — the Bombard never has to be used on mobile targets, so the floor that
  matters (against structures) is not zero.
- **The shell follows its spotting source.** A beacon attached to a unit moves with it; the shell
  tracks the beacon in flight; if the beacon is eliminated the shell lands at its last position.
  Area spotting (a `BeaconRange`) places no beacon, so it never homes. As built the shell
  always catches its beacon (the quickest version); how far it may turn is open — TODO.
- **Two ways onto a unit.** A Recruit's Spot ordered onto an enemy tank attaches the beacon to it
  (held on a leash: the tank driving out of the Recruit's spotting range drops it), and a Beacon
  Drop landing on or beside one attaches too.
- **Beacons attach only to grounded MECH units.** Bio units can't carry one — part of why the
  Bombard's unit fire is poor against infantry however strong its damage against bio is.
- **Beacon secrecy.** A beacon is stealthed to opponents (a detector reveals it). A beacon that has
  been fired on is shown as used to its owner's side only; opponents see no change.
- **Recharge.** Untuned; at least 15 s is the working minimum. **Work Detail** shortens it: every
  captive sentence completed at an adjacent Compound removes 8 % of the full cooldown, and each
  battery has its own pool, so N batteries is N shots per cycle — the 1,000 cost is what limits
  batteries, not the cooldown.
- **Coverage.** If the shell is effective against bio, invariant 2 rests on the **targeting
  constraints** (no beacons on bio, unit spread, the single charge, cost), not on the damage
  table. A tuning pass that makes targeting easier is touching coverage.

Any heal strips an enemy beacon off its carrier ([bombardment](../systems/combat/bombardment.md)
§Beacons). Open (see [deferred](../deferred.md)): the shell's damage type, whether a Recruit's
beacon is permanent, and how much of beacon placement the opponent sees.

## Libertarians (the Warden)

- **Deploying vehicles** as pseudo-statics: the Gatling Tank (LEAD, air and ground) and the
  Refraction (lazer) tank, both tier-0 light mechs. Long deploy and unpack times are the
  commitment; their deploy cannot be cancelled ([deploying](../systems/commands/deploying.md)). Rule to keep: **the deployed bonus must not match a
  true static's efficiency per cost**, since the tank keeps the option to move.
- **Security Tower** (`lb_defense`): garrisoned by one drone at a time; the drone fires from
  inside, and the structure's properties depend on which drone holds it. Coverage then grows with
  drone tech — the opposite of the "statics scale poorly" pattern — so the guardrails are:
  - each drone gives the tower exactly one target class, so a tower's coverage stays narrow and
    breadth comes from tower count and drone mix, which scouting can read;
  - swapping drones should be slow, or reactive swapping removes the opponent's counterplay
    (TODO — no swap time exists yet).
  - **Detection is intrinsic** (`detection_medium`) — it doesn't depend on drone tech, so it
    satisfies invariant 6.
  - The first per-drone property is built as a stub: a garrisoned Shock Drone fires at
    `ground_range_long`. Further per-drone properties are open.
- **Likely deliberate hole:** tough bio (the Juggernaut takes 0.25 from LEAD; the lazer tank does
  0.25 to bio) and electric damage, both Anarchist strengths.
- Security Towers also protect the sparse dominion structures, a different job from choke defence.

## Anarchists

No dedicated statics. Their fixed defence is infantry in garrisonable structures (their own or
neutral buildings), which is elastic (units can re-garrison) and exposed to clearing (the Viper
upgrade, the Bombard). The design pressure moves onto infantry cost and investment. Early
anti-air against Libertarian air openers is carried by the Warlord (players build several) and the
tier-1 Juggernaut; the Warlord's rocket is to be tuned against Libertarian flyer speeds.

## The damage attribute table is deprecated

Armour classes and movement physics provide per-class specificity, so the attribute multipliers
(`IS_GROUNDED` / `IS_FLYING` / `HAS_STEALTH`) are deprecated. The game dropped them from the
live damage path already; the balance tooling no longer applies them either.
