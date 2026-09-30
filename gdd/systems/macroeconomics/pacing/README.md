---
title: Macroeconomic pacing
type: system-index
---

# Macroeconomic pacing

**TODO — research, nothing here is decided.** How the economy should shape a match over time:
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
| [building-roles](building-roles.md) | marginal value of each copy of a structure, by what the structure confers; multi-purpose buildings |
| [dominion-and-ordnance](dominion-and-ordnance.md) | dominion as a super meter, the sanction-as-permission / structure-as-charges split, shared pools, and the command centre |

## The pitfalls, in one place

Each note carries its own list. These are the ones that cut across them, i.e. the risks to
the design as a whole:

1. **A flat tree shortens the build list, not the clock.** Fewer prerequisite structures
   speed the game up only if the price along a path stays the same. If the top tier gets
   cheaper, volatile tools arrive earlier, and that works against G3.
   → [tree-shape](tree-shape.md) §Pitfalls
2. **Tech is free while income outruns production.** When income exceeds what the producers
   can spend, the surplus has no other use, so no tech price is felt at all. Calibrating tech
   is pointless until the income-to-throughput ratio is settled (deferred 1.23).
   → [tech-investment](tech-investment.md) §The hidden discount
3. **A good secondary role turns into the spam building.** If a structure's weapon or charge
   is better per cost than the dedicated piece, copies of it become the default purchase.
   → [building-roles](building-roles.md) §The rider rule
4. **A finite sanction grid is a meter with a cap.** Once a player owns the whole grid, more
   dominion is worth nothing, so contesting it stops mattering late in the match, which is
   exactly when it is meant to matter most. → [dominion-and-ordnance](dominion-and-ordnance.md)
   §Dominion after the grid
5. **Every volatile tool needs a tell.** Faster units, more tech paths and bigger area effects
   all shrink the defender's window to scout and answer (M2).
   → [tech-investment](tech-investment.md) §What a tier buys
6. **Losing a gate loses its whole branch.** Prerequisites are checked live
   (`Commander.has_built_structure`). A dense tree with many gate structures makes a snipe
   more decisive, and G17 wants that bounded. → [tree-shape](tree-shape.md) §Pitfalls
