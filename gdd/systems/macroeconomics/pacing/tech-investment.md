---
title: Tech investment — what a tier buys and what it should cost
type: system-note
---

# Tech investment

**TODO — research, nothing decided.** Part of [pacing](README.md). Symbols follow
[timings](../../../design-framework/timings.md) §Symbols.

## What a tier buys: variance, not just mean

**A higher tier should raise the VARIANCE of an exchange more than its MEAN.** There are two
ways to make a later unit "better":

- **Efficiency.** More value per energy in a straight fight. The player who reaches it first
  wins every even trade after that, which is a snowball. This works against G17.
- **Volatility.** A wider spread of outcomes, depending on execution, position and the
  opponent's state. A storm that erases a clumped army and does nothing to a spread one. A
  fast raider that ends a match if the defence is thin and dies if it is not. This is G3's
  curve, and because the underdog can also land the big swing, it doubles as a comeback route.

So a late piece can be *close to* cost-efficient on average, as long as its upside is large
and conditional. That is the [elasticity](../../../design-framework/elasticity.md) model
applied per tier: the band (floor to cap) should widen as the tier rises.

The axes along which a tier can add volatility, each with the check it needs:

| Axis | Examples | The check |
|---|---|---|
| **Burst and area** | AoE ordnance, splash, chained disables | colocation must be avoidable, and the payoff conditional on the target's state (*counter hit*) |
| **Reach** | range, and above all map mobility: fast movers, air, transports, drops | equation 2 (scout and answer) must still hold at the new crossing time `τ` |
| **Structure damage** | new damage types against STRONG/MEDIUM | the finish stays late: early units stay inert against infrastructure ([pacing](../../../design-framework/pacing.md)) |
| **Information** | stealth, detection, scans | every hidden threat has a scoutable answer (G10, M1) |
| **Control** | freezes, stuns, suppression | combo scaling: tier governs duration and area, and chains diminish |

**Volatility has to be two-sided.** Late defensive tools (an ordnance that wipes a committed
attacker, a static that deletes a drop) must be as swingy as the offensive ones. Otherwise
the late game is volatile only for whoever attacks first, and that turns it into a race.

**Stacked volatility is a coin flip.** An AoE payload delivered by a fast unit under stealth
leaves the defender no decision to make, only a dice roll. The goal is a volatile
*consequence* of a readable decision. Each tier should add volatility along one or two axes
per piece, not along all of them.

## How a tech investment is priced

A tech investment costs more than its sticker price. It has three prices:

1. **The sticker.** The chain's energy `C_k`: the target structure plus every prerequisite
   not already owned.
2. **The window.** For the chain's build time `T_k`, and until the unlock is fielded, that
   energy is not army. The deficit at contact is `ΔA ≈ C_k`, but **only when income is the
   binding constraint** (see below). This is timings equation 4 ("what greed costs at the
   moment of contact") with the tech chain as the greed.
3. **The exposure.** A tech structure is a target whose loss removes its whole branch.
   Prerequisites are live: `Commander.has_built_structure`. Its HP and position are a price
   paid again every time the opponent can reach it. Duplicating it as insurance is a real
   option; see [building-roles](building-roles.md).

There is no selling ([pacing](../../../design-framework/pacing.md)), so none of the three can
be walked back. Committing is more final than in a game with refunds, so the sticker price
can sit lower than such a game would need for the same deterrence.

### The hidden discount

**Tech is free whenever income exceeds production throughput.** Let `ρ = I / S` be income over
what the producers can spend. When `ρ > 1`, the surplus `I − S` has nowhere to go except tech,
static defence or more producers, so tech displaces no army and the window (price 2) is zero.
[timings](../../../design-framework/timings.md) §Income finds `ρ` well above 1 today on five
extractors. **So no tech price can be calibrated until `ρ` is.** Deferred 1.23's proposed
cut to gather rates comes first, and the tech numbers after it.

## Calibration band

Both failure modes are named in the brief:

- **Too expensive:** a pure low-tier army punishes the tech player at completion AND keeps
  the lead afterwards. Nobody takes the risk, and every match plays out at tier 1.
- **Too cheap:** the tech player's army at contact is nearly the same size. The window has no
  teeth and everybody techs on a fixed timer.

**The window should cost about one attack's worth of risk.** An opponent who scouts the
investment and commits should be able to punish it, and one who does not should get
out-scaled. The defender's home advantage `δ` (timings equation 3) gives the lower bound:

```
δ · A_contact  <  ΔA  <  A_decisive
```

- Below `δ·A_contact`, statics and position absorb the deficit and teching is safe (too cheap).
- `A_decisive` is the deficit at which a punished window ends the match. Per G3, early fights
  "confer advantage but rarely decide", so the deficit must stay below that. Holding here
  means the punish costs the tech player units and tempo, not the game.

Both bounds depend on the map. `τ` grows with the start distance `D`, and random maps vary
`D`. That variation is wanted (G13): calibrate at the median `D`, and let short maps favour
the punisher and long maps favour the teching player.

**The payoff shrinks as the match goes on.** A tech's value is its advantage multiplied by the
match time left to use it, so a late tech pays back less. That creates a natural "tech now or
not at all" pressure without any extra rule. The flip side is that the curve depends on
typical match length, so match length is also a calibration target.

### How to measure it

Equations give first numbers. The verdict comes from play, not from a GUT test (CLAUDE.md
§A simulation test is not a unit test):

- **Bot self-play** (`tools/selfplay/`) and **simulation scenarios** (`tools/simulation/`).
  Record when each tier is reached, the win rate by tech timing, and the share of long matches
  that reach each tier.
- **The target:** most long matches reach the top tier, but no single tier timing dominates
  the win rate. A tier that is never reached is priced too high. A tier timing that wins
  outright is priced too low, or is a solved line (G13).

## Pitfalls

- Calibrating tech before fixing `ρ` (see §The hidden discount).
- A top tier that is efficient rather than volatile, which is a snowball.
- Mobility bought at a tier that equation 2 was never re-run against.
- One-sided volatility: offensive swing with no defensive swing to match.
- Calibrating against one map distance only.
