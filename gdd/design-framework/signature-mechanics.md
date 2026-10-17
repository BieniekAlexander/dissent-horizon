---
title: Signature mechanics — the systems that define a faction, and the knobs that shape them
type: design-note
---

# Signature mechanics

**A signature mechanic is a faction-defining SYSTEM, not a one-off tool with a theme on it.**
Each faction should have two (revised 2026-10-17 from three). The fighting-game analogue is Street Fighter 6's Manon:
on the surface her medals only make command grabs hit harder, but they change what the opponent
fears. Once her throws are scary, the opponent stops just blocking, which opens up her strikes.

Brainstormed 2026-10-16. Where a signature sits in the tier model is in
[README](README.md) §Tiers; its rules live in its own system note.

## What qualifies

**Mechanical systems are kept separate from thematic flavour.** A piece can carry a strong theme
and still be mechanically flat: the Anarchist [[scavenge|Scavenge]] sanction reads as scavenging
from the enemy, but all it does is pay out for kills. That is a fine sanction, not a signature.

A signature mechanic passes both tests:

1. **Several ways in, several payoffs.** Many producers feed it, and it pays off in more than one
   way. Bombard spotting has four producers feeding one threat. Freeze has three applicators and
   pays off both as a disable and as protection. A mechanic with one source and one result is a
   tool, however good a tool.
2. **It changes how the opponent plays even when it is not being used.** Anything standing still
   near a Colonial spotter is a liability, whether or not a gun is charged.

## A faction's set, against the other factions' sets

**A faction's signatures are designed as a SET, and the sets are designed against each other.**
Decided 2026-10-16.

- **They interact.** Each faction's signatures should touch other factions' signatures to some
  degree, rather than running in parallel. A signature that never meets an opposing system
  passes test 2 only against generic play.
- **More importantly, the advantages a set confers are broadly comparable across factions.**
  The mechanics differ; the opportunities they open should not. Colonial's set gives:

  | Role | Colonial signature |
  |---|---|
  | Damage output and global spatial presence | Bombard spotting |
  | Disable plus protection | Freeze |

  Every other faction's set should offer comparable opportunities — a way to greatly increase
  damage output, for instance — expressed through its own mechanics. This is
  parity of opportunity, not mirroring: [matchups](matchups.md) still governs where a faction
  deliberately lacks something.

## Current allocation

| Faction | Signature mechanics | Open slots |
|---|---|---|
| Colonial | Bombard spotting ([bombardment](../systems/combat/bombardment.md)); Freeze ([shields](../systems/combat/shields.md) §Freeze) | none |
| Anarchical | Disable (EMP) | none — considered complete (2026-10-16): the faction's many nuanced details carry it |
| Libertarian | Drone attachment | 1 — TODO |

**Roles still to cover.** Against Colonial's set, Libertarian has augmentation (drone
attachment). TODO: its second slot is open; parity suggests a damage-output role.

**Hijacking is meant to interact with the Anarchist disable**, but it is not a signature in its
own right.

### Ruled out as signatures

| Mechanic | Why not |
|---|---|
| Crushing | game-wide: every vehicle crushes, so it is a generic mechanic, not a faction's |
| Veterancy / Promotion | the Colonial ordnance is thematic, but not interactive enough to carry a system |
| Planted explosives | a one-off tool on one unit |
| Hijacking | one instance of stealing units from an opponent; not thorough enough alone |
| Deployment | Libertarian-only today, but not meant to stay exclusive |
| Projectile interception | other factions may get their own versions of it |
| Supply lines / Work Detail | REJECTED (2026-10-17): overlaps dominion collection too much and adds too much macroeconomic elasticity — see [README](README.md) §Settled |

---

## The knob matrix

**Five axes describe a state mechanic.** *Effect* is what it does; the other four are how it is
delivered. Each table lists the knobs, their settings, and where today's mechanics sit.

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

## Profiles

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
  MECH-only, and they cap breadth on the receiving side. So a signature gets its breadth from
  producers and payoffs, not from receivers.
- **A signature pushes toward the generic tier's complexity budget.** Complexity is proportional
  to prevalence (README §Tiers); a mechanic broad enough to define a faction is met often enough
  to afford more rules.
- **EMP and drone attachment sit at opposite ends of the capability axis** — one removes what a
  unit can do, the other adds to it — which makes Anarchical against Libertarian a natural place
  for cross-faction contact: an EMP shutting off an augmentation, or knocking a drone loose.
  TODO: not decided.
- **Subsystem-granular disables could deepen EMP without overlapping Freeze.** Freeze already
  shuts down everything; a weapon-only or movement-only EMP would be a different tool.
  TODO: not decided.
