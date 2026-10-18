# Prologue Campaign Design

The prologue is five missions that teach generic RTS skills first (missions 1–3) and dissent-horizon's own systems after (missions 4–5); mechanics set the order, and each mission gets a story reason for its situation.

## How these docs map to the repo

Each tab here becomes one markdown file under a proposed `gdd/scenarios/` directory, with one subdirectory per campaign:

```
gdd/scenarios/
  prologue/
    README.md                       ← this tab
    mission-01-unit-control.md
    mission-02-army-and-counters.md
    mission-03-base-and-economy.md
    mission-04-dominion-and-shelters.md
    mission-05-capstone.md
```

- A mission doc describes design intent: what it teaches, why the story puts the player there, and the beats.
- Each mission doc links to its scenario file, which holds the real placements, triggers and values. Numbers in a mission doc are illustration only, so they don't go stale when the scenario is retuned.
- Every mission doc uses the same template: Status, Teaches, Player fantasy, Narrative justification, Setup, Objectives, Teaching beats, Constraints, Scenario file, Open questions.

## Mechanic sequence

Each mission's problem is one its new mechanic solves; earlier mechanics come back as reinforcement.

| # | Mission | Teaches | Reinforces | Story hook (draft) |
| --- | --- | --- | --- | --- |
| 1 | Unit control | Select, move, attack, attack-move, vision and fog | — | A small detachment is cut off and has to reach friendly lines |
| 2 | Army and counters | Control groups, selection keys, Frame × Armour counters, crushing, garrisons | Unit control | The survivors link up with a mixed force and must break an enemy screen |
| 3 | Base and economy | Command centre drop, extractor drops, extraction sites, training, the production queue | Counters | Command authorises a forward base, but where to drop it is the player's call |
| 4 | Dominion and shelters | Dominion, shelters, the first sanction | Economy, army control | Holding ground isn't enough; the faction has to establish its claim over the people here |
| 5 | Capstone | Faction signature mechanic, combining everything | All | The enemy commits; the player has to win the region outright |

## Narrative arc

The player's toolkit grows with the faction's situation: a stranded squad, then a field army, then a base, then a claim on the region, then a decisive battle.

- **Missions 1–2 (survival):** the faction is on the back foot, so small forces and no base feel earned, not arbitrary.
- **Mission 3 (foothold):** the turn from surviving to building; the command centre drop is the story's first moment of initiative.
- **Missions 4–5 (claim):** the faction starts pursuing its ideology's version of dominion, which is where the game's critique of each faction can start to show.

The arc should end on a hook into the main campaigns, not a full resolution.

## Open questions

- [ ] Which faction does the player control in the prologue? One faction throughout, or a short look at several?
- [ ] Who is the enemy faction, and does it stay the same across all five missions?
- [ ] Where do scenario files live in the repo, so each mission doc can link to its file?
- [ ] Is HEGEMONY the win condition anywhere in the prologue, or are all five scripted objectives?
- [ ] Should sanctions (mission 4) and the signature mechanic (mission 5) swap, depending on the faction?
