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
