---
title: Dominion and ordnance — calibrating the super meter
type: system-note
---

# Dominion and ordnance

**TODO — research. Only items marked Decided are settled.** Part of [pacing](README.md). The grid's rules are
[sanction-grid](../sanctions/sanction-grid.md). This note is about what dominion should be
*worth*.

## The inputs are all placeholders

As of 2026-09-30, none of the three numbers the calibration rests on is set:

- **Sanction prices are test values.** Most cells are 500, one is 250, and two Anarchical
  cells (Informant, Dignify) are 100. None of these is a design.
- **Dominion generation rates are uncalibrated across factions.** Each faction collects
  differently (occupants, damage dealt, sparse structures), so the rates do not compare
  directly.
- **Starting dominion** is planned to be below the cheapest unlock. Its only job is to make
  the first unlock slightly cheaper.

What is decided is the *shape* of the prices (Alex, 2026-09-30): **higher tiers cost more, and
the whole grid is more than one match can pay for.** The meter has a cap, and the cap is
never reached. See §The grid is never finished.

## The fighting-game model

Dominion is a **super meter** (G6, the burst-meter shape). In fighting games, meter:

- is **gained by both players from ordinary play**, with deliberate actions gaining a bit more
  (Third Strike's whiffs, Guilty Gear's forward movement). Here, collection is meant to be
  cheap in energy and decided mostly by whether the opponent disrupts it
  ([pacing](../../../design-framework/pacing.md) G1);
- is **spent across a ladder**: small, frequent spends (EX moves) and rare, decisive ones
  (supers). Here the ladder is the grid's tiers;
- has a **cap**, which forces spending and prevents a hoard;
- often has a **comeback term**, meter gained by taking damage (SF4's Ultra, SFV's V-gauge).

What this model says about "consequential but not decisive": **meter decides fights, not
matches.** A super wins the exchange it is spent in. The round is still won by the play that
earned the meter and set up the super.

## Permission and charges are split

**Most of the proposed design is already built.** A sanction is the PERMISSION to use an
ability; a structure's `abilities:` pool supplies the CHARGES
([command-card-and-hotkeys](../../ux/ui/command-card-and-hotkeys.md) §The sanction is the
permission). Consequences:

- **Each copy of a caster is an independent charge source.** N casters give N charges per
  cooldown.
- **A pool can grant several abilities from one charge**: the shared cooldown. The Citadel's
  single charge grants Scan, Freeze, Beacon and Promotion.
- **A caster can start empty** (`initial_charges: 0`, e.g. the Storm Cell). This stops a player
  from building a fresh caster just to fire it at once.
- **Casters sit on the energy tech tree**, e.g. the Storm Cell behind tech 2.

The last point is what keeps dominion from deciding matches on its own. **The volatile
ordnance needs both gates**: dominion for permission, and energy tech for a caster. A player
rich in dominion but behind on energy cannot fire the top tier, and a player whose caster dies
loses the uses without losing the permission. This is Zero Hour's superweapon shape (the
building is the target), with the general's promotion as the unlock.

## Calibration

### Time to tier

The breadth toll (two cells in a tier open the next) means reaching tier `k` takes about two
cells in each tier above it. With `p_j` the price of a tier-`j` cell, rising with `j`:

```
t_tier(k) ≈ ( 2·Σ_{j<k} p_j  −  D₀ ) / r_D
```

where `D₀` is the starting dominion and `r_D` the faction's steady dominion rate. Escalating
`p_j` makes depth cost more than linear, and that growth is the knob that sets *when* the
game-swinging tier arrives. **Calibrate `r_D` across factions by `t_tier`, not by raw rate.** Each faction
should reach each tier at a comparable time when uncontested, and be pushed later by the same
proportion when harassed. A faction whose rate is bursty (paid for damage dealt) has no
steady `r_D`; use its expected rate in a typical engagement pattern and check it in
self-play.

### Starting dominion

`D₀ < p_min` does what the plan says: it shortens the wait for the first unlock by `D₀ / r_D`.
Two things to watch:

- **A flat `D₀` is a bigger head start for a slower faction.** Set it per faction as *seconds
  of that faction's rate*, or as a fraction of its cheapest tier-0 cell, if the goal is an
  equal head start.
- **It biases the opening toward the cheapest cell.** A 100-dominion cell next to a start just
  below it is a free opening pick. That is fine if intended, but then it is a cell the designer
  chose for everyone.

### What a charge should be worth

State the target as the fraction of an engagement a charge can swing, rising with tier:

| Tier | Target swing (TODO, a guess) | Framing |
|---|---|---|
| 0 | a few units' worth: wins a skirmish, never an army fight | EX move |
| middle | tips a fair army fight | combo extender |
| top | wipes an army or kills a structure, **only if landed** | super: a tell, a delay, a counter |

Then bound the aggregate: **the ordnance value a player can deploy per minute should stay a
modest fraction of their energy income per minute.** A starting band would be well under a
tenth at tier 0 and a few tenths at the top (TODO: a guess to test, not a decision). The
aggregate multiplies charge value by caster count, which is why caster price is part of
dominion's calibration.

### Contesting collection

Disrupting the opponent's collection should cost roughly what it denies them. If denying is
much cheaper, dominion becomes a harassment tax. If it is much dearer, nobody bothers and
dominion becomes free income. Each faction's collection method is where this is set
([colonial-dominion](../../combat/colonial-dominion.md) for the Colonials).

## The grid is never finished

**Decided (Alex, 2026-09-30): a cap is fine, and prices put it out of reach.** Escalating tier
prices make the whole grid cost more than any one match yields, so a finite grid never runs
dry of things to buy. Two consequences follow:

- **The choice of cells is the dominion decision.** A player buys a *subset*, and which subset
  is their dominion strategy: wide and shallow, or deep in one family.
- **Match length is part of the calibration.** "Infeasible" is relative to how much dominion a
  long match yields: `Σ p (whole grid) > r_D · T_long`, with margin, for the strongest
  dominion player. If matches run long (turtling), the grid can be finished and the cap
  starts to matter. So check the margin in self-play, not only on paper.

A per-use dominion cost at the top tier, the fighting-game "spend per super", stays open as a
lever if dominion ever goes quiet late.

## Gating: a tier toll, or a dependency graph

**Today: the tier toll.** Any two cells in a tier open the next ([sanction-grid](../sanctions/sanction-grid.md)).
It is chosen for flexibility: any combination of shallow cells buys depth, so players reach
the strong tier by the route that suits their match.

**The alternative, still worth considering: explicit dependency edges between cells** ("Blizzard
needs Freeze 2 *and* Scan 2"). The grid already has edges *within* a family (`parent`); this
would add them *across* families.

| | Tier toll | Dependency graph |
|---|---|---|
| player routes to depth | many, any two per tier | few, the authored ones |
| designer control over combos | low: any cell may pair with any | high: a strong cell can require a specific set-up |
| failure mode | a cheap pair of cells is the universal toll payment, and the others go unbought | the graph dictates the build, becoming a linear tree in disguise (see [tree-shape](tree-shape.md)) |
| legibility | one rule | an edge list to learn per faction |

A hybrid is possible: the tier toll for access, plus a single dependency edge on the one or
two cells that need a specific set-up to be fair.

**The toll's own pitfall** is the first row. If one pair of shallow cells is clearly the
cheapest way through, every player pays the toll the same way. With escalating prices, keep
the cells *within* a tier close in price, so the pair is chosen for its use, not its cost.

## Shared pools change what a second sanction is worth

In a shared pool, buying a second sanction adds an **option**, not a **use**: the charge rate
is unchanged. Its value is the gain from having a better answer available, which is smaller
than the first sanction's value. Price the later cells of one pool accordingly, or give them a
role the first cannot fill, so they are not bought only to complete the set.

**A strictly dominated ability in a pool is dead.** It never gets the charge. Each ability in a
pool should win in some state (the target, the timing, the matchup), which is the pool's whole
point (G6).

## The command centre

The brief's design: command centres are the player's "hitpoints" (if the win condition in
[proposals](../../../design-framework/proposals.md) is adopted), train builders and dominion
units, and cast the lowest-tier ordnance from a shared pool. The first one is free, and extra
copies have low marginal value.

**Why low marginal value is the right target:**

- **Insurance is priced by the threat.** An extra centre is worth little early and more once
  the opponent has finishing tools. So the purchase arises naturally late, *as a response to a
  scouted tell*, which is G3's curve produced by the players themselves.
- **Worker production has little value** because the economy is not saturation-driven (G1).
- **Extra tier-0 charges** are real but capped by the shared pool: one charge per cooldown per
  centre.

**Pitfalls:**

1. **Turtling by centre count.** If centres are cheap relative to the finishing tools, stacking
   them makes a match unfinishable, against G8. Options (TODO): an escalating price per centre
   owned, or finishing tools (the STRONG revisit, deferred 1.20) scaled so N centres cost N
   times the effort but no more.
2. **The ordnance battery.** If tier-0 ordnance is strong, extra centres become a durable
   (STRONG) caster farm. The rider rule ([building-roles](building-roles.md)) applies:
   another centre must be a worse ordnance buy than any dedicated caster.
3. **The hidden last centre.** A centre tucked into a far corner drags out a lost match, the
   classic hidden-building endgame. StarCraft's answer is to reveal a player who has lost every
   town hall. The equivalent here would be revealing the last centre, or every centre once the
   player is down to one. TODO if the win condition is adopted.
4. **Forward centres.** If centres can be built anywhere, a forward centre is a forward
   builder factory and caster. Check it against the forward-production concerns in
   [pacing](../../../design-framework/pacing.md) (Zero Hour chinook builders, GLA tunnels).
