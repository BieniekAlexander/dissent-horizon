---
title: Macroeconomic pacing
type: system-index
---

# Macroeconomic pacing

**TODO — research. Only items marked Decided are settled.** How the economy should shape a match over time:
what a tech tier buys, what an investment costs and how to calibrate it, what dominion is
worth, and what each structure contributes. Every recommendation is a proposal until it is
answered, and every number named here is a starting guess.

The goals it answers to are the [design framework](../../../design-framework/README.md)'s,
especially G3 (a volatility curve: low early, high late), G6 (multi-purpose pieces), G13 (no
pareto-optimal line) and G17 (economic leads are buffered). The pacing questions it takes up
are posed in [design-framework/pacing](../../../design-framework/pacing.md), and the equations
it borrows are in [design-framework/timings](../../../design-framework/timings.md).

| Note | Covers |
|---|---|
| [tech-investment](tech-investment.md) | what a higher tier should buy (volatility, not just efficiency), how a tech investment is priced, and how to calibrate it between "nobody techs" and "everybody techs" |
| [tree-shape](tree-shape.md) | linear versus dense tech trees: diameter, breadth, and what a many-path tree costs |
| [income-and-cost](income-and-cost.md) | what a minute of income buys: one unit versus an army, replacement time, permanent versus temporary income, and an order to calibrate them in |
| [resource-allotment](resource-allotment.md) | how much energy a map should give each player, compared with Zero Hour and StarCraft II army and base costs |
| [structure-costs](structure-costs.md) | pricing buildings by role, from a half-of-Zero-Hour anchor; proposed Colonial and Anarchical prices |
| [building-roles](building-roles.md) | marginal value of each copy of a structure, by what the structure confers; multi-purpose buildings |
| [dominion-and-ordnance](dominion-and-ordnance.md) | dominion as a super meter, the sanction-as-permission / structure-as-charges split, shared pools, and the command centre |
| [sanction-calibration](sanction-calibration.md) | first-pass numbers for the sanction grid: a four-tier layout, a price ladder, dominion ≈ energy via the Technocratic extractor, and per-family changes (Scan, Ambush, Drop) |

Upgrades, which several of these notes discuss, are built: [upgrades](../upgrades.md).

## The pitfalls, in one place

Each note carries its own list. These are the ones that cut across them, i.e. the risks to
the design as a whole. A "Decided" item records the answer given (Alex, 2026-09-30) and the
risk that remains.

1. **A flat tree shortens the build list, not the clock.** Fewer prerequisite structures
   speed the game up only if the price along a path stays the same. If the top tier gets
   cheaper, volatile tools arrive earlier, and that works against G3.
   → [tree-shape](tree-shape.md) §Pitfalls
2. **Tech is free while income outruns production.** When income exceeds what the producers
   can spend, the surplus has no other use, so no tech price is felt at all. Calibrating tech
   is pointless until the income-to-throughput ratio is settled (deferred 1.23).
   → [tech-investment](tech-investment.md) §The hidden discount, and
   [income-and-cost](income-and-cost.md) for the whole gather-rate revisit
3. **A good secondary role turns into the spam building.** If a structure's weapon or charge
   is better per cost than the dedicated piece, copies of it become the default purchase.
   → [building-roles](building-roles.md) §The rider rule
4. **A finished grid would silence dominion.** Decided: tier prices escalate so no match
   can buy the whole grid. The risk left is long, turtled matches that could, so the margin
   between grid price and a long match's dominion is a calibration check.
   → [dominion-and-ordnance](dominion-and-ordnance.md) §The grid is never finished; superseded 2026-10-02 by
   [sanction-calibration](sanction-calibration.md) §Finishing the grid (the grid may be finished
   in a very long match; a second T4 should be out of reach in any other)
5. **The opening owes a tell; later play does not.** Decided: macro timing must keep a threat
   off the doorstep until the defender has had the chance to see the attacker's base. After
   that, scouting is the player's job. The risk left is hard counters that turn one missed
   scout into a lost match. → [tech-investment](tech-investment.md) §Tells
6. **A cheap snipe is a tuning bug.** Decided: losing a gate blocks new purchases, and fielded
   pieces stay. Structure durability is what keeps a snipe out of the early game, so any
   early unit that kills a gate cost-effectively gets retuned. → [tree-shape](tree-shape.md)
   §Pitfalls
7. **Footprint is a price.** A larger building exposes more surface and fills the defended
   ground sooner. It is a useful knob, but its value depends on map generation's buildable
   area. → [building-roles](building-roles.md) §Size is a price
