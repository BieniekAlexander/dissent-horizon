---
title: Tree shape — linear versus dense tech trees
type: system-note
---

# Tree shape

**TODO — research. Only items marked Decided are settled.** Part of [pacing](README.md).

## Vocabulary

- **Diameter:** the longest prerequisite chain to any top-tier unlock, counted in structures.
  It governs how many things must be built, not how long they take.
- **Breadth:** the number of parallel paths that reach the top tier independently.
- **Path price:** the energy and build time along one path to its top. Price, not diameter,
  is what sets *when* the volatile tools arrive.

A **linear** tree has breadth ≈ 1: one line of purchases leads to the strongest tools, with
side branches. A **dense** tree, as proposed, has a low diameter and a high breadth: several
deep paths, each reachable in a few structures.

## Where the game is today

The snapshot (2026-09-30) comes from the `requires:` chains in the spec docs, which the
importer writes to `resources/generated/technology.json`.

- Each built faction (Colonial, Anarchical, Libertarian) has a diameter of about four:
  infrastructure → barracks → {factories, tech 1} → tech 2.
- **Each has exactly two tech structures, and tech 2 hangs off ONE producer's branch.** For
  Colonial and Libertarian that is the war factory; for Anarchical, the air field. So the top
  tier is reached through a single path per faction. By this definition the trees are already
  low-diameter, but they are still linear in breadth.
- The support structures (the ordnance casters) hang off different branches, which makes
  them the nearest thing to parallel paths today.

## Precedents

| Game | Shape | What it teaches |
|---|---|---|
| **StarCraft II, Protoss** | Gateway → Cybernetics Core → {Robotics Facility, Stargate, Twilight Council} → one tech building each | Low diameter, breadth three. Openings are named after the path taken. Scouting which path is the central early read. |
| **Supreme Commander** | each factory type (land, air, naval) upgrades T1 → T2 → T3 on its own | High breadth, each path deep. Switching paths late is expensive. "Tier rushing" one path is a known strategy. |
| **Warcraft III** | the town hall's tier gates everything; each building then offers its own content | Diameter set by a single spine. Breadth lives in *which* buildings you add at each tier. |
| **C&C Generals / Zero Hour** | mostly linear buildings; the general's promotions branch the ability tree | Structure breadth is low. The choice lives in a side tree bought with a second resource. This game's sanction grid already plays that part. |

## What density buys

The case made in the brief, restated against the goals:

- **Variety across matches** (G13). Different players take different paths, so no single line
  is "the" build.
- **Fewer builds to reach the top** (G1). The same number of options sits in a shallower
  tree.
- **More targets** (G4, G14). With several tech and key structures, an attacker chooses which
  part of the opponent's tech and production to take away. With one or two, the choice is
  made for them.
- **Base-planning decisions.** How many structures fit, when to expand the base, and which
  structures to put at the front or the back. The same goes for the units and static
  defences that cover them.
- **Cross-path synergies.** Strong combinations drawn from divergent paths, priced by the
  investment it takes to reach both.

## Pitfalls

1. **A flat tree shortens the build list, not the clock.** With breadth `b`, the cheapest top
   tier is the cheapest path's price, and that is usually below a linear tree's single price.
   Unless each path is priced as its own full-price climb, the top tier and its volatility
   arrive earlier, which works against G3.
   Rule of thumb: **the cheapest path to the top should cost about what the single path of a
   linear tree would.** Breadth adds choice, not speed.
2. **A dominant path collapses the tree.** If one path wins, the dense tree becomes a linear
   one with dead branches, which is worse than an honest linear tree because the dead branches
   still cost learning. Measure the win rate per path in self-play. Every path needs its own
   reason to exist, preferably tied to the matchup (G10) rather than to raw strength.
3. **More paths means more to scout, and that is fair.** Past the opening, finding the path is
   the player's job, and a well-hidden tech structure is information the opponent is entitled
   to withhold ([tech-investment](tech-investment.md) §Tells, decided 2026-09-30). The risk
   left is the COUNTER structure: if each path's answer is a narrow hard counter, one missed
   scout loses the match, and play becomes guessing rather than scouting. Keep answers soft
   and generic (anti-air before any air path), so a missed scout costs efficiency, not the
   game.
4. **Losing a gate blocks its branch.** Decided (Alex, 2026-09-30): pieces already fielded
   stay, and only new purchases are blocked until the gate is rebuilt. Prerequisites are live
   (`Commander.has_built_structure`). Two things keep the swing acceptable:
   - **insurance copies** ([building-roles](building-roles.md)) are the defender's answer;
   - **durability sets when a snipe becomes possible.** Structures are tough, so by the time a
     player fields enough to kill a gate, the match is late enough for that volatility (G3).
   The calibration check follows from that: **a snipe must cost a mid-game army.** If an
   early unit kills a gate cost-effectively, that unit or the gate's armour is what gets
   retuned ([timings](../../../design-framework/timings.md) §Structure armour has the
   time-to-kill table).
5. **Balance cost grows with pairs of paths.** `b` paths per faction across `f` factions means
   interactions scale with `(b·f)²`. Cross-path synergies are the hardest to see. Keep them few
   and deliberate, each written down where it is intended.
6. **The complexity budget applies.** A path is faction-unique content, and the framework's
   [Tiers](../../../design-framework/README.md) rule spends complexity sparingly there. Many
   paths with many unique rules each is too much to learn.
7. **Space is a map-generation input.** Footprint is itself a price
   ([building-roles](building-roles.md) §Size is a price). More structures need more
   buildable area, which is set by map generation's quotas
   ([map-generation](../../terrain-and-navigation/map-generation.md)). A dense tree also
   spreads a base, so a raid always finds something unguarded. That favours raiders, and
   static defence has to be priced with it in mind
   ([static-defence](../../../design-framework/static-defence.md)).
8. **The CPU commander must choose paths.** A linear tree needs only a build order. A dense one
   needs a path choice and a reason to switch ([ai](../../ai/)). Cheap if planned for, costly
   if retrofitted.
9. **A synergy that is required is not a choice.** If the late game is only viable with the
   cross-path synergy, every player buys both paths and the tree is linear again, just wider
   and dearer.
