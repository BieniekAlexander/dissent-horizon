---
title: Mechanics design — the knob matrix for how rich a mechanic is
type: design-note
---

# Mechanics design

**Five axes describe a mechanic that changes a piece's state, and where it sits on each says how
much play it can carry.** *Effect* is what it does; *Duration*, *Source*, *Valence* and *Breadth*
are how it is delivered. A mechanic that is interactive, situationally good or bad, and broad
across the roster is a rich toy with room for expression and creative misuse; one that is
self-contained, fixed in valence and narrow is a simple, readable anchor. Both have a place —
this note is for seeing which one a design is, and which knob would move it.

It sits beside two other ways of measuring an option: [elasticity](elasticity.md) asks how much
an option pays back extra execution, and [decisions](decisions.md) asks what decision it creates
(commitment, information, payoff, scarcity). This one asks what the effect itself is shaped
like. Breadth is the axis that meets the [README](README.md) §Tiers rule — complexity follows
prevalence.

Brainstormed 2026-10-16.

## The knob matrix

Each table lists the knobs, their settings, and where today's mechanics sit.

### Effect

| Knob | Settings | Where it sits now |
|---|---|---|
| Category | damage, disable, protection, mobility, information, augmentation, ownership | Bombard: damage. Freeze: disable plus protection. EMP: disable |
| Magnitude | a nudge, a swing, decisive | Bombard is meant to decide games late (G3); an EMP stun is short |
| Granularity | the whole unit, or one subsystem (weapon only, movement only) | Freeze and EMP both shut down everything |
| Delivery shape | burst, sustained, delayed | Bombard shell: burst. Frost fields: sustained. Blizzard: delayed |
| Compound effects | one effect, or several bundled | Freeze bundles a stun with a 150 hp ice shield |

### Duration

| Knob | Settings | Where it sits now |
|---|---|---|
| Length | instant, seconds, until an event, until death, the rest of the match | Freeze: 10 s. Frost field: 5 s (Avalanche). Promotion: permanent |
| End condition | timer, damage threshold, leaving an area, the host acting, the source dying or leaving | Breaking the ice ends a Freeze; a beacon is used on firing and consumed at impact |
| Build-up | immediate, or exposure that accumulates (and drains outside) | Frost field: 2 s of exposure, draining at the rate it built |
| Reapplication | refresh, extend, stack, keep the larger | EMP refreshes rather than extends; shields keep the larger hit points and time |
| Reversal cost | free, timed, cancellable or not, irreversible | Deploy: 3 s to set up, 1 s to pack, not cancellable |
| Source cooldown | per use, charges, rearm trip | Condor: one bomb, then home to rearm (8 s). Avalanche: 15 s reload |

### Source

| Knob | Settings | Where it sits now |
|---|---|---|
| Who applies it | self, ally unit or structure, sanction, enemy, the field | Deploy: self. Spot: ally. Freeze: either side |
| Parties needed | one, two, a chain | Spotter → beacon → Bombard |
| Delivery | touch, projectile, aura, field, attach / garrison | Freeze: ordnance, Avalanche shell, Blizzard field |
| What the applier commits | nothing, a channel, standing still, itself | Spot is a channel; the Hijacker is expended |
| Telegraph | silent, visible to its own side, visible to all, announced ahead | Blizzard gathers for 10 s; beacons are subject to stealth for opponents |
| Removability | none, focus fire, healing, cleansing, killing the source | Focus fire breaks the ice; heals removing an enemy beacon has been considered |

### Valence

| Knob | Settings | Where it sits now |
|---|---|---|
| Target filter | enemies, allies, anyone | Freeze ordnance: anyone. Shock Trooper EMP: enemies |
| Effect on the host | buff, debuff, trade-off | Freeze is a trade-off: no action, but a shield |
| Area friendly fire | none, or everyone | Frost fields and Global EMP hit both sides |
| Who triggers the payoff | applier, host, opponent | Detonate: the applier |
| Enemy exploitation | can the opponent use or deny it? | barely used yet — the open dial |
| Conditional payoff | a bonus against an affected target, or none | Extra damage vs EMP'd targets is REJECTED (README §Settled); Freeze pays off by holding targets still for Siege and Bombards |

### Breadth

| Knob | Settings | Where it sits now |
|---|---|---|
| Frame filter | BIO, MECH, both | EMP: MECH only. Bio Stun: BIO only |
| Armour filter | excludes some classes, or none | Freeze skips STRONG |
| Layer filter | ground, air, structures | Beacons: grounded MECH only. Frost fields spare structures |
| Targets per use | one, an area, the whole map | Shock Trooper: one. Condor: an area. Global EMP: every unit |
| Producers across the roster | how many pieces apply it | Spotting: Recruit, Sleeper, Reverence, Beacon Drop |
| Payoffs across the roster | how many pieces cash it in | Spotting: the Bombard alone. Freeze: Siege damage, Bombard targets, self-protection |
| Cross-faction contact | does it touch other factions' systems? | TODO: e.g. a Freeze interrupting a Libertarian deploy |

---

## Worked examples

Four mechanics profiled on the five axes.

| Axis | Bombard spotting | Freeze | EMP | Drone attachment |
|---|---|---|---|---|
| Effect | high burst damage | disable plus protection | disable | augments the abilities available to the host |
| Duration | until fired; permanent near a Reverence | 10 s, or until the ice breaks | short; refreshes | TODO |
| Source | a chain of allies | self or enemy; three applicators | enemy; three applicators (Shock Trooper, Condor, Global EMP) | TODO |
| Valence | fixed | trade-off, with friendly fire | fixed (Global EMP hits both sides) | TODO |
| Breadth | 4 producers, 1 payoff | wide, minus STRONG | MECH only | TODO |

---

## Observations

- **There are two routes to two-sided valence.** Hit everyone (Global EMP, frost fields), or make
  the effect itself a trade-off (Freeze). The second is the richer one, and it is open for drone
  attachment: a host could gain from its drone while giving something up.
- **Breadth pulls against the frame-based counter system.** Frame filters are what make EMP
  MECH-only, and they cap breadth on the receiving side. So a broad mechanic gets its breadth
  from producers and payoffs, not from receivers.
- **Breadth buys complexity.** Complexity is proportional to prevalence
  ([README](README.md) §Tiers): a mechanic broad enough to define a faction is met often enough
  to afford more rules, and a narrow one should stay simple.
- **EMP and drone attachment sit at opposite ends of the capability axis** — one removes what a
  unit can do, the other adds to it — which makes Anarchical against Libertarian a natural place
  for cross-faction contact: an EMP shutting off an augmentation, or knocking a drone loose.
  TODO: not decided.
- **Subsystem-granular disables could deepen EMP without overlapping Freeze.** Freeze already
  shuts down everything; a weapon-only or movement-only EMP would be a different tool.
  TODO: not decided.
