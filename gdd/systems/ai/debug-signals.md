---
title: The bot's signals, and drawing them
type: system-note
---

# The bot's signals, and drawing them

Everything a bot holds or derives that could be drawn for the person watching it, grouped
into the CATEGORIES the debug overlay shows one at a time. The overlay draws for the bot being
viewed (the spectator HUD's POV toggle) while the debug view is up, and the spectator HUD's
**Bot overlay** picker chooses the category. A category is world marks plus a text readout in
the top-right corner. See [debug-mode](../ux/ui/debug-mode.md) §The debug view.

Each signal carries its level in the [world model](world-model.md) (L0 sightings, L1 tracks,
L2 situation, L3 assessment, L4 attention), and one of three costs:

- **stored**: the bot keeps it; drawing it is free.
- **cheap**: derived on demand, but cheap enough to derive every frame or every readout.
- **heavy**: too expensive to derive for a picture today. It waits for the bot to store it
  (the world model's lattice, or a cache written by the think that computes it).

A signal the bot computes and then discards (a candidate's score, the runner-up choice) is
marked **discarded**. Drawing it needs the deciding manager to keep its last answer.

**A drawn signal is the bot's BELIEF, never the truth.** That is what makes the overlay useful:
it shows why the bot did what it did, including when it was wrong.

## Built

### Scouting

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Sight age per scout-grid point | L2 | stored | a marker per point, green → red over the expiry; grey if never seen |
| Scouts out, their waypoint, their stall clock | L4 | stored | a ring per scout, cyan → orange toward the stall limit, white while waiting; a line to its waypoint |
| Ever-seen and stale fractions | L2 | cheap | readout |
| Scouts out against the allowance, and how many are waiting | L4 | stored | readout |
| What the first scout is worth (information price × stale fraction) | L4 | cheap | readout |

### Enemy picture

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Believed pieces at their last-known position, and how long since seen | L1 | stored | a filled square per unit, an outline per structure; a remembered unit fades over the belief's expiry |
| In view now, against remembered | L0 | stored | red in view, orange remembered |
| Whether a believed piece can shoot | L1 | cheap | a stick |
| Believed counts, and how many are in view | L1 | stored | readout |
| Believed enemy army value against own | L3 | cheap | readout |
| Counter-demand per believed enemy type | L3 | cheap | readout, ranked, refreshed four times a second |

Remembered structure meshes are already drawn by the game itself (the blackboard's snapshots).

### Base defence

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Base threats: enemy → the structure it threatens → its value (cost × matchup) | L2 | cheap | a red line from enemy to structure and a ring on the enemy, brighter the more it is worth; readout count and total |
| The base centroid and the believed threat direction | L2 | cheap | a white outline, and a yellow line along the direction |
| Safety, and its three terms (under attack, outgunned, bleeding) | L3 | cheap | readout |
| The income target, and what safety bends it to | L3 | cheap | readout |
| Static-defence demand per region (value, own, enemy, demand) | L3 | cheap | a ring per contested region, blue → magenta as its demand nears the cheapest turret's price, and a stick that high; readout, ranked |

### Army

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Posture and objective, and the structure behind it | L3 | stored | a ring and stick in the posture's colour (red attack, blue defend, green mass); an outline on the structure |
| Squads (main, reserve, guard): members and the point each policy holds | L3 | stored | a ring per member in the squad's colour, a filled square at the centroid, a line to the policy's point |
| Rally point; abandoned objectives until they expire | L3 | stored | a yellow stick; a grey X |
| Each unit's current target | L3 | stored | a line from unit to target |
| Wave state: launch value, value now, the spent and retreat lines, regroup timer, time on objective | L3 | stored | readout |
| Attack ratio against the required ratio as stalemate lowers it; the smoothed enemy estimate | L3 | stored | readout |
| Momentum: slope, loss rate, losing or not | L3 | stored | readout |

### Economy

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Written-off build spots | L2 | stored | a grey X |
| Contested build spots and their cooldown | L2 | stored | an orange ring, fading as the cooldown runs out |
| Spots an in-flight construction job is aimed at | L2 | cheap | a cyan outline and stick |
| Savings: every proposal, the goal, whether the claim is held | L3 | stored | readout |
| Game phase; dominion demand | L3 | cheap | readout |
| Composition value per unit the bot could train now | L3 | cheap | readout, best first |
| The latest scored decisions (train, production, tech, defence, research): the winner and its runner-up | L3 | stored | readout, latest first; kept by the usage log's short ring of recent choices |

### Unit control

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| Which manager owns each unit, and at what priority | L4 | stored | a ring per unit in its owner's colour, one ring per priority step; a faint grey ring when unclaimed; readout counts |
| Each unit's active command | — | — | already drawn by the debug view's unit labels |

### Bot internals

Text only; none of it has a place on the map.

| Signal | Level | Cost | Shown as |
|---|---|---|---|
| The personality drawn for this match | — | stored | readout: each searched field that the draw moved, tier → drawn |
| Per-job compute: work units and microseconds of the last run, ticks until due | — | stored | readout |
| The usage log's orders, issued against refused, per kind | — | stored | readout |

## Not built

TODO: catalogued and not drawn, each for the reason given.

- **Scouting:** where a REVEAL would land (cheap, one pass over the grid), and the errand search
  in progress (stored only while a dispatch is part-way through).
- **Enemy picture:** enemy forces as groups (centroid, strength, value, heading) is **heavy**
  (grouping is quadratic over live units, and reads live units rather than beliefs); it waits for
  the world model's groups. Per-commander knowledge (inferred tech) is not built.
- **Army:** candidate target scores are **discarded** by BotTargeting; drawing them needs it to
  keep its last scores.
- **Economy:** the build-spot ranking, command-centre spot search and dominion site survey are
  stored only while a search is part-way through. Which rung of the build ladder fired is not
  recorded; the recent decisions show what each scored choice picked, not why the ladder reached it.
- **Unit control:** scored errands (liberate, capture, deposit, garrison) are **discarded**; the
  kamikaze target and sanction aim point are **heavy** (each scores over groups).
- **Bot internals:** the usage log's per-piece choice counts and cast positions are not shown
  (the self-play report reads them from the log file).

The world model's L2 channels (influence, threat by damage type, tension, vulnerability,
value, approach, combat) are not built. Once they are, each is a heat map on the scout grid's
lattice, and the scout grid's marker is the template for drawing one.
