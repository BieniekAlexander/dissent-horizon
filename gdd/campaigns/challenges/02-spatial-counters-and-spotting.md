# Challenge 2 — Spatial counters and spotting

Status: draft. Drills the counters that come from movement and range rather than the damage table: making a shot miss, and firing artillery beyond your own vision.

## Skill

- **Spatial counters.** A shot can miss because of how the target moves. The modes:
  - **Outpace:** run faster than the projectile can close.
  - **Outturn:** get inside its turning circle up close.
  - **Outguess:** juke a leading shot.
  - **Outlast:** stay ahead until its lifespan or lock runs out.

  Related lessons: turreted weapons aim independently of movement, and non-turreted ones make the whole unit turn first. Rules: [projectile-evasion](../../systems/combat/projectile-evasion.md), [turrets](../../systems/combat/turrets.md), [weapon-cadence](../../systems/combat/weapon-cadence.md).
- **Spotting.** Artillery can out-range its own vision, so it needs another unit to see the target. Rules: [range-buckets](../../systems/combat/range-buckets.md). The Colonial version is [bombardment](../../systems/combat/bombardment.md) with beacons.

## Prerequisites

Prologue mission 1 (counters by damage type). This challenge shows the second way a fight is decided.

## Drills

- **Outpacing:** a [Raven](../../factions/anarchical/units/an_aircraftLight_transport.md) flies past steering rockets. Fleeing a rocket it can outrun makes the rocket miss, and crossing in front of it gets the Raven hit. The arena results in [projectile-evasion](../../systems/combat/projectile-evasion.md) §Outpace are this drill's basis.
- **Outturning:** a ground unit can't outrun a [Badger](../../factions/colonial/units/cl_bioLight_antiMech.md)'s rocket, but crossing it at close range, inside its turning circle, makes it overshoot. Score on hit rate, not kills.
- **Turrets:** a [Matilda](../../factions/colonial/units/cl_mechMedium_antiMech.md), which has a turret, keeps firing while it repositions. A non-turreted unit has to stop and turn. Exploit the difference by flanking the unit that has to face its target.
- **Spotting:**
  - An [MLRS](../../factions/anarchical/units/an_mechMedium_artillery.md) can reach a target it can't see.
  - Send infantry forward to spot, then fire. Keep the spotter alive and unseen.
- **Being spotted:**
  - A Colonial [Bombard](../../factions/colonial/structures/cl_defense_antiStructure.md) fires on the player's vehicles only while a beacon is on one or a spotter has vision.
  - Find and kill the spotter, or move the beaconed vehicle out of the shell's path.
- **Combined test:** cross a defended zone with a mixed force, using evasion for the vehicles and spotting for the MLRS to clear the way.

## Pass and score

- **Pass:** reach the far side of the combined test with the MLRS alive.
- **Score:** hit rate against the player's units (lower is better), and units lost.

## Pieces

- Anarchist: the MLRS, infantry spotters, a fast vehicle (e.g. a [Collective](../../factions/anarchical/units/an_mechLight_transport.md))
- Colonial: Badgers, Matildas, a Bombard with its beacon sources

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- Several evasion rules are still TODO in [projectile-evasion](../../systems/combat/projectile-evasion.md), notably whether outguessing exists at mid range. Should this challenge wait for those, or drill only the modes already shown in the arena (outpace, outturn)?
- Does the challenge visualise projectile paths or the turning circle, to make the lesson legible?
- Outpacing needs an emitter that the Raven can outrun. Which Colonial anti-air weapon fits, or is a scripted emitter acceptable in a challenge?
