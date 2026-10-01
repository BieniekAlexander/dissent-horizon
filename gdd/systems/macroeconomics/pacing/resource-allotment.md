---
title: Resource allotment — how much energy a player should have, by comparison
type: system-note
---

# Resource allotment

**TODO — research. Only items marked Decided are settled.** Part of [pacing](README.md). The
question (Alex, 2026-10-01): **12000 energy per alliance looks low.** How much should a map
hold, judged against what armies and bases cost here and in two reference games?

The reference figures are from memory of the shipped games, not measured. They are close enough
to compare orders of magnitude, which is all this note uses them for.

## The unit scale this game expects

Alex's expected costs (2026-10-01):

| Tier | Cost | Examples |
|---|---|---|
| baseline | 100 | light BIO, ballistic: weak to most other units |
| other cheap units | 200–300 | |
| mid-game mainstays | 500–750 | tanks, aircraft |
| late game | 1000–1200 | |

**Structures** follow the Colonial roster (snapshot): Compound 1000, Barracks 500, Air Field
1000, Operations Center 1200, War Factory 2000, Academy 2000, support structures 1000–2500,
command centre 2000, extractor 500. One of each production and tech structure is about 7700;
with the three support structures, about 12400.

## Zero Hour

- **Units** cost about 1.5–2× what this game expects (Alex's estimate). Ranger 225, Red Guard
  pair 300, Rebel 150; Crusader 900, Battlemaster 800, Scorpion 600; Overlord 2000, Raptor
  1400, Comanche 1500, Aurora 2500.
- **Structures:** Barracks 500, War Factory 2000, Air Field 1000, Strategy Center 2500,
  Command Center 2000.
- **The map:** about $60k–75k of finite supplies per player, plus infinite oil derricks, plus
  late-tree infinite income (supply drop zones, Black Market, Hackers).

Converted at ÷1.75: **about 34k–43k of finite energy per player**, before the infinite sources.

**The structures do not scale like the units.** Colonial structures cost about what Zero Hour's
do (a 2000 War Factory in both), while its units cost about half. Relative to the army, base
overhead here is roughly twice Zero Hour's. Either that is intended, and the map must fund it,
or structures are due the same discount.

## StarCraft II

Two resources: minerals and vespene gas. Summed below, which undervalues gas (it is scarcer and
gates tech), so treat these as lower bounds.

- **Units:** Marine 50, Zergling pair 50, Zealot 100, Marauder 125, Stalker 175, Siege Tank 275,
  Mutalisk 200, Colossus 500, Thor 500, Carrier 600, Battlecruiser 700.
- **Structures:** Barracks 150, Factory 250, Starport 250, Command Center 400; tech
  attachments and upgrade buildings 75–400.
- **The map:** a base holds 10800 minerals (four patches of 1800, four of 900) and two geysers of
  2250, so **about 15300 per base**. A 1v1 map has 14–16 bases, about 7–8 per player, so **over
  100k per player** in reach. A typical game mines three or four bases, **about 50k–60k per
  player**.

**Converted at ×2** (a Marine at 50 matches the 100 baseline): Siege Tank 550 and Stalker 350 sit
in the mid band, and Thor 1000 and Battlecruiser 1400 at the late end. The conversion fits Alex's
scale well. Structures convert to 300–800, cheaper relative to units than here, which makes the
same point as Zero Hour.

## Army value at three milestones

In this game's energy, using each reference's own conversion:

| Milestone | Zero Hour (÷1.75) | StarCraft II (×2) | Expected here |
|---|---|---|---|
| first contact | 600–1100 ($1000–2000: a few infantry or a light vehicle) | 1000–2000 (500–1000 resources) | **1000–2000**: six to ten cheap units at 100–300 |
| medium army | 4500–7000 ($8k–12k) | 6000–10000 (3k–5k resources) | **5000–7000**: about a dozen units, mid-game mainstays among them |
| late army | 11k–17k ($20k–30k) | 16k–24k (a maxed army, workers excluded) | **12k–18k**: 15–20 units including late ones |

**The note's earlier medium army (2000–3000, [income-and-cost](income-and-cost.md)) is too small
by about half.** It assumed armies of baseline units, and they are not what a medium army is
made of.

## What a player spends in a match

A long game, about 20–25 minutes, for one player:

| | Energy |
|---|---|
| structures: one tech line, the support structures, a second producer | ~15k |
| extractors (five) | ~2.5k |
| armies lost in three medium-army trades | ~18k |
| the late army standing at the end | ~15k |
| **total** | **~50k** |

**That converges with both references:** Zero Hour converted gives about 34k–43k finite per player
plus infinite income, and StarCraft II converted gives a typical game of 100k–120k (high, because
its economy has worker saturation and supply as additional spend), with the lower 50k–60k
unconverted. **A target of about 50k per player over a long game, most of it from finite
deposits,** sits between them.

## Today against that

**Today's map holds 12000 per alliance, 7200 of it in ponds.** In a 1v1 that is 7200 of finite
energy per player, **about a fifth of the target**. The sites' income is infinite: at 6/s a
site yields 7200 over 20 minutes, so a player holding two home sites and a share of the others
reaches perhaps 25k, about half the target, with ponds the smaller part.

**Income rate.** Spending 50k in 20 minutes averages about 42/s. Today two home sites give 12/s
and each worked pond 24/s, so it takes about one pond worked the whole game, or two in the middle
of it. That is the decided shape (ponds necessary), at about the right rate. The total in the
ponds is what is short.

## Per player, not per alliance

**Recommended, as Alex suggested.** Alliances exist so teammates can start together. The budget
should be **per player**, `energy_value_per_player × start_count`, while placement keeps
balancing access per alliance (an alliance's share is then its members' sum). In 1v1 nothing
changes. In a 2v2, a per-alliance budget gives each player half of a 1v1 player's energy, which
is the current fault.

## A proposal

**TODO, not applied.** Numbers are starting points for playtesting:

| Knob | Proposal | Today |
|---|---|---|
| budget unit | per player | per alliance |
| finite (pond) energy per player | ~35k | 7200 |
| site share per player | about the same number of sites as now (~2.7) | ~2.7 |
| medium army (the pond yardstick) | 5000–7000 | 2000–3000 |
| pond charge | ~2000–8000 (effective 1500–7500 after the extractor), averaging ~5000 | 1500–3900 |
| ponds per player | ~6–8 | ~2–4 |

Two consequences need a decision with it:

1. **A larger pond drains slowly.** At 24/s, a 5000 pond takes about 3.5 minutes with its one
   extractor. If ponds are meant to be fast prizes, the pond rate rises (6–8× the site rate,
   36–48/s, about 2 minutes). If they are meant to be held, the rate stays and holding is the
   contest.
2. **Six to eight ponds per player is a lot of water** for map generation to place, at about 30–60
   cells each. The alternative is fewer, richer ponds, which pushes the size or richness bounds up
   rather than the count.

And one question it raises: **is the structure overhead intended?** Colonial structures cost
Zero Hour prices while units cost half of Zero Hour's, so a base takes about twice the share of a
player's energy that it does there. If that is intended, it is part of why the map needs ~50k
per player. If not, cheaper structures lower the target instead.
