---
title: Zero Hour speed reference
# NOT A SPEC: no `kind:`, so the importer skips this doc. Reference data only — C&C Generals:
# Zero Hour movement and projectile speeds, mapped onto this game's scale. Nothing reads it.
---
# Zero Hour speed reference

Reference for revisiting [speed_classes](speed_classes.md). Zero Hour tunes each unit
individually; this game buckets speeds into classes. The catalog below is the raw material for
deciding where the bucket boundaries should go. Collected 2026-10-03.

## Units and the mapping

- **Zero Hour units:** a Locomotor's `Speed` is world distance per second. One heightmap cell is
  10 world units (`MAP_XY_FACTOR`), so Speed 20 is 2 cells/s. `SpeedDamaged` applies once a
  unit is REALLYDAMAGED, which is below 35% HP.
- **The anchor is infantry.** Zero Hour basic infantry (Ranger, Rebel, RPG trooper, Tank
  Hunter) move at 20, and this game's infantry tier is `SLOW` = 1.65 u/s. So
  **k = 1.65 / 20 = 0.0825**: multiply a Zero Hour speed by k to get u/s here.
- Our infantry is 1.65 cells/s against Zero Hour's 2. So under this mapping our cells are
  slightly larger relative to our unit speeds. Mapping by cells instead would be k = 0.1.
- In the tables, "→ u/s" is `Speed × k`, and "nearest class" is the closest current rung on the
  ladder.

## Infantry

| Zero Hour unit | Speed / damaged | → u/s | nearest class |
|---|---|---|---|
| Angry mob | 18 | 1.49 | SLUGGISH |
| Ranger, Missile Defender, Rebel (all variants), RPG trooper, Tank Hunter, Hacker | 20 / 10 | 1.65 | SLOW (anchor) |
| Red Guard, Mini-Gunner, Terrorist, Worker | 25 / 15 | 2.06 | STEADY |
| Black Lotus, Jarmen Kell, Burton, Pathfinder, Hijacker, Saboteur, Pilot | 30 / 20 | 2.48 | STEADY |

Zero Hour infantry span 18–30, so the fastest infantry run 1.5× the basic soldier. The fast
ones are specialists and heroes.

## Ground vehicles

| Zero Hour unit | Speed / damaged | → u/s | nearest class |
|---|---|---|---|
| Overlord | 20 / 20 | 1.65 | SLOW |
| SCUD launcher, Nuke cannon | 20 / 15–18 | 1.65 | SLOW |
| Battlemaster | 25 / 25 | 2.06 | STEADY |
| Emperor Overlord | 25 | 2.06 | STEADY |
| Crusader, Paladin, Microwave tank, Tomahawk, Avenger, Dragon tank, Toxin tractor, Dozers | 30 / 20–25 | 2.48 | STEADY |
| Overlord + Nuclear Tanks, Inferno cannon (ZH 1.03) | 30 | 2.48 | STEADY |
| Scorpion, Marauder, Quad cannon, Gattling tank, Troop crawler, ECM tank, Listening outpost, Radar van, China supply truck | 40 / 25–40 | 3.30 | BRISK |
| Battlemaster (Nuke General) | 45 | 3.71 | QUICK |
| Bomb truck | 50 | 4.13 | QUICK |
| Humvee, Ambulance | 60 / 30 | 4.95 | FAST |
| Battle bus | 70 / 50 | 5.78 | FAST |
| Technical, Rocket buggy | 90 / 80 | 7.43 | RAPID |
| Combat cycle (INI) | 120 / 90 | 9.90 | (gap: RAPID–BLAZING) |

## Aircraft

| Zero Hour unit | Speed / damaged | → u/s | nearest class |
|---|---|---|---|
| Helix | 75 / 60 | 6.19 | FAST |
| Comanche, A-10 | 120 / 120 | 9.90 | (gap: RAPID–BLAZING) |
| B-52 | 125 / 75 | 10.3 | (gap) |
| Chinook, Combat Chinook | 150 / 60 | 12.4 | BLAZING |
| MiG | 160 / 160 | 13.2 | BLAZING |
| Raptor, King Raptor, Stealth fighter | 175 / 120 | 14.4 | BLAZING |
| Aurora (cruise / supersonic) | 180 / 480 | 14.9 / 39.6 | BLAZING / beyond SUPERSONIC |

## Drones

| Zero Hour unit | Speed / damaged | → u/s |
|---|---|---|
| Battle drone | 40 / 20 | 3.30 |
| Scout drone, Hellfire drone | 60 / 30 | 4.95 |

## Projectiles

Unguided shells fly at their weapon's `WeaponSpeed`. A homing missile flies at its missile
Locomotor's `Speed`, and its `WeaponSpeed` is ignored. A `WeaponSpeed` of 999999 is instant.

| Zero Hour projectile | Speed | → u/s | nearest class |
|---|---|---|---|
| Artillery platform shell | 150 | 12.4 | BLAZING |
| Scorpion missile (homing, turn 540°/s) | 150 | 12.4 | BLAZING |
| Tomahawk cruise missile, SCUD | 200 | 16.5 | BLAZING / HYPER |
| Inferno cannon shell | 250 | 20.6 | HYPER |
| Nuke cannon shell | 200 | 16.5 | BLAZING / HYPER |
| Infantry/buggy/Comanche AT rocket (homing: min 120, accel 675, turn 100–180°/s) | 225 | 18.6 | HYPER |
| Raptor/Aurora jet missile (homing, turn 200°/s) | 300 | 24.8 | SUPERSONIC |
| Paladin, Overlord, Marauder (base) tank shell | 300 | 24.8 | SUPERSONIC |
| Crusader, Battlemaster, Scorpion tank shell | 400 | 33.0 | above SUPERSONIC |
| Patriot, Stinger AA missile (homing, turn 300–625°/s) | 400 | 33.0 | above SUPERSONIC |
| Crusader/Humvee machine gun | 600 | 49.5 | above SUPERSONIC |
| Rifles, Gattling, Quad cannon, Comanche cannon | instant | — | hitscan |

## What the comparison shows

1. **Zero Hour's ground ladder is compressed and overlapping.** Main battle tanks (20–40) move
   at infantry speed (20–30). The Overlord is exactly as fast as a Ranger, and the Crusader
   matches a Black Lotus. Our ladder puts every vehicle above every infantry tier. Zero Hour
   gets its speed separation from LIGHT vehicles (60–90, which is 3–4.5× infantry), not from
   tanks.
2. **Zero Hour's aircraft are much faster relative to the ground.** Helicopters (other than the
   Helix) and jets sit at 120–180, which is 6–9× infantry. Our FAST, where most aircraft sit, is
   only 3.2× infantry. Only BLAZING (9×) reaches the Zero Hour jet band.
3. **There is a hole between RAPID (7.2) and BLAZING (15).** In Zero Hour that band, 90–180,
   holds the fastest ground vehicles and nearly every aircraft. Our ladder has no rung for it.
4. **Projectiles are where the gap is biggest.** Zero Hour rockets fly at 225 (18.6 u/s here)
   and shells and AA missiles at 300–400 (25–33 u/s). Both are 11–20× infantry speed, and
   1.3–2× a jet. Our standard projectile tier, RAPID, maps back to Zero Hour 87, which is
   *Technical* speed: a dune buggy, well below every Zero Hour aircraft except the Helix. That fits the reported problem:
   - `an_bioMedium_dominionGen` fires a HOMING rocket at RAPID. In Zero Hour terms that is
     about 87; the equivalent infantry rocket flies at 225.
   - `cl_bioLight_antiMech` boosts to BLAZING (about 182 in Zero Hour terms, close to an AT
     rocket) but then coasts at RAPID (about 87).
   - Zero Hour's homing missiles also never drop below `MinSpeed` 120 (9.9 u/s), whereas
     `cl_bioLight_antiMech` has `min_speed: 2`.
5. **The one Zero Hour missile that is outrun on purpose is the Scorpion's** (150 against a
   175 Raptor), and it makes up for that with a 540°/s turn rate. Everything else is built to
   catch what it shoots at. The Patriot locomotor is commented `(silly if not faster than
   planes)`.

## Caveats

- Infantry speeds come from cnc.fandom.com infoboxes, read through search-result summaries.
  The fandom pages could not be fetched directly from the session that collected this.
- Locomotor and weapon values are quoted from the retail Zero Hour INI files.
- Where the two disagree, the INI wins:
  - Combat cycle: wiki 70, INI `CombatBikeGroundLocomotor` 120/90.
  - Gattling, Overlord, MiG and Comanche: the INI keeps the full speed when damaged.
- Still unconfirmed: the Laser tank, the Sentry drone, the Aurora Alpha's undamaged values, and
  the Battlemaster's Nuclear Tanks figure (the wiki gives 35/32, but the upgrade's +50% would
  make it 37.5).

## Sources

- Retail Zero Hour INI (mirror):
  [Locomotor.ini](https://github.com/FreemanZY/Command_And_Conquer_INI/blob/master/Command%20&%20Conquer(tm)%20Generals%20Zero%20Hour/Data/INI/Locomotor.ini),
  `Weapon.ini` and `GameData.ini` in the same directory
- EA source release:
  [CnC_Generals_Zero_Hour](https://github.com/electronicarts/CnC_Generals_Zero_Hour) —
  `Locomotor.cpp`, `INI.cpp`, `GameCommon.h` (30 logic frames/s), `MapObject.h` (`MAP_XY_FACTOR`)
- cnc.fandom.com unit pages, e.g. [Crusader tank](https://cnc.fandom.com/wiki/Crusader_tank),
  [Ranger](https://cnc.fandom.com/wiki/Ranger_(Generals)),
  [Red Guard](https://cnc.fandom.com/wiki/Red_Guard_(Generals_1)),
  [Rebel](https://cnc.fandom.com/wiki/Rebel_(Generals_1)),
  [Humvee](https://cnc.fandom.com/wiki/Humvee_(Generals)),
  [Raptor](https://cnc.fandom.com/wiki/Raptor_(Generals)),
  [Nuclear tanks](https://cnc.fandom.com/wiki/Nuclear_tanks),
  [Zero Hour patch 1.03](https://cnc.fandom.com/wiki/Zero_Hour_patch_1.03)
