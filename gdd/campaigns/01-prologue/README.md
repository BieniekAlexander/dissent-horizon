# Prologue Campaign Design

Status: draft. The prologue is three missions played as the **Anarchists** against the **Colonials**. Mission 1 teaches the mechanics every RTS player meets, mission 2 the mechanics specific to dissent-horizon, and mission 3 running an economy. Mechanics set the order, and each mission gets a story reason for its situation.

The prologue is kept small on purpose so new players aren't overwhelmed. Skills a player can pick up later — the control idioms, spatial counters and spotting, and requisition — live in the [challenge series](../challenges/README.md) instead.

## How these docs map to the repo

- A mission doc describes design intent: what it teaches, why the story puts the player there, and the beats.
- Each mission doc links to its scenario file under `scenes/scenarios/`, which holds the real placements, triggers and values. Numbers in a mission doc are illustration only, so they don't go stale when the scenario is retuned. Piece names link to their spec docs for the same reason.
- Every mission doc uses the same template: Status, Teaches, Reinforces, Player fantasy, Narrative justification, Setup, Objectives, Teaching beats, Constraints, Scenario file, Open questions.

| # | Doc | Teaches | Story hook (draft) |
| --- | --- | --- | --- |
| 1 | [Pervasive mechanics](01-pervasive-mechanics.md) | Unit control, garrisoning, the counter system, defection | In the middle of a Colonial siege on allied Anarchists, a small force fights through the battle, picks up survivors and strikes the besiegers' base |
| 2 | [Game-specific mechanics](02-game-specific-mechanics.md) | Unit abilities (via the Sapper), crushing, stealth, dominion generation, ordnances, garrison clearing | A defunct base with Distress Signals holds out while it banks dominion for Informant and Mortar Strike |
| 3 | [Macroeconomics](03-macroeconomics.md) | Structure and unit production, resource collection, the tech tree, transports | Destroy the Colonial base; each part of it calls for a different tool |

## Narrative arc

The player's toolkit grows with the Anarchists' situation: a squad caught in someone else's battle, then a cell holding a ruined base, then a war band able to build and take the fight to the Colonials.

- **Mission 1 (in medias res):** no base and no economy, because the player arrives mid-battle with whatever survived.
- **Mission 2 (holding out):** the base is defunct, so there's no production. The Anarchists' leverage is dominion — their Warlords' following — not industry.
- **Mission 3 (taking initiative):** the first full base, used for a direct assault.

The arc should end on a hook into the main campaigns, not a full resolution.

## Deliberately left out

Kept out of the prologue to avoid overloading it. Each is either a challenge or main-campaign material.

| Mechanic | Where it goes |
| --- | --- |
| Modifier controls (Alt narrow, Ctrl broaden, Shift append), the F1–F3 selector matrix, control groups | [Challenge: controls](../challenges/01-controls.md) |
| Spatial counters (outpacing projectiles, kiting, turrets), spotting. Spotting-dependent pieces, like the MLRS, are kept out of the prologue | [Challenge: spatial counters and spotting](../challenges/02-spatial-counters-and-spotting.md) |
| Requisition | [Challenge: requisition](../challenges/03-requisition.md) |
| Command centre drop and the free extractor drops | Main campaign or skirmish onboarding; the prologue starts players with a base (see mission 3's open questions) |
| Anarchist signature mechanics (disable/EMP, scavenging), the Hijacker, Dignify, Ambush, Scavenge | Main campaign |
| Shelters, static defence design, upgrades, aerial rearm, alliances, superweapons | Main campaign |

## Open questions

- [ ] Do survivors and veterancy carry over between missions? It ties the missions together, but it snowballs difficulty.
- [ ] Is the challenge series unlocked after a particular prologue mission, or available from the start?
- [ ] Is HEGEMONY the win condition in mission 3, or is it a scripted objective?
- [ ] Some game-wide behaviours will happen before the mission that teaches them. Vehicles crush infantry in mission 1, and destroyed grounded vehicles leave wrecks that Anarchist infantry can scavenge. Suppress these in early missions, or let them happen and only explain them later?
