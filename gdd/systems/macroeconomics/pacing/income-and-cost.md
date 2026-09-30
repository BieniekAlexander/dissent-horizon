---
title: Income and cost — what a minute of income buys
type: system-note
---

# Income and cost

**TODO — research. Only items marked Decided are settled.** Part of [pacing](README.md).
Gather rates, both permanent and temporary, are to be revisited as a whole and against each
other (Alex, 2026-09-30). This note is the frame for that revisit. The greed and payback
equations it leans on are [timings](../../../design-framework/timings.md) §The equations, and
today's numbers are that note's dated snapshot.

## The question

*If I gather `X` per minute, what does it mean whether that buys a single unit or an entire
army?* Everything below follows from one ratio:

```
s_u = c / I          seconds of income one unit costs
```

with `c` a unit's price and `I` the income per second. Its inverse, units per income-minute, is
the same fact.

| | Income buys **about one unit a minute** (`s_u` ≈ 30–60 s) | Income buys **an army a minute** (`s_u` ≈ a few seconds) |
|---|---|---|
| **A loss** | stings: a unit is a real fraction of a minute's work | is refilled before the next fight |
| **Army size** | small, so each unit's handling matters (G9, G11) | large; mass effects dominate, and G7 has to fight them |
| **A won fight** | propagates (G14), but can decide the match early (against G17) | barely propagates: both sides re-buy, and the fight changed nothing |
| **What binds** | income: every purchase is a choice | production throughput: income stops being the constraint (see `ρ` below) |
| **Pace** | slow build-up, few decisive fights | constant fighting, few consequences |

Neither end is the target. The framework wants micro to matter (a small army) and fights to
count without deciding the match early (a moderate replacement time), which puts the target in
the middle, and pins it down through the derived quantities below.

## The derived quantities

| Symbol | Formula | What it governs | Today (snapshot) |
|---|---|---|---|
| `s_u` | `c / I` | how precious one unit is | two extractors (`I` = 40/s): Recruit 3 s, Matilda ~19 s |
| `T_rep` | `A / I` | how long a lost army takes to replace, i.e. what a won fight is worth in time | a 3000 army: 75 s on two extractors, 30 s on five |
| `ρ` | `I / S` | whether income or producers bind; above 1, the surplus is free to spend (see [tech-investment](tech-investment.md) §The hidden discount) | well above 1 on five extractors |
| `N` | `A / c̄` | army size in units at contact: the micro load, and what G7 leans against | tens of infantry, within a few minutes |
| `t*` | `t_b + c_x / r` | how long an extractor takes to pay back, i.e. whether greed has a window (timings eq. 4) | 20 s build + 25 s = 45 s |

**The reading today:** units are cheap relative to income, armies are replaced in well under
two minutes, and an extractor pays back before any army can reach it. So losses matter little,
and greed is nearly free. That is the finding behind deferred 1.23's proposed cut to gather
rates.

## Permanent and temporary income

Two kinds of source, with different jobs:

- **Permanent: an extraction site** (inexhaustible). Its value is `r × time held`, so it
  **compounds**: a lead in sites becomes a larger lead in energy every minute. It rewards holding
  ground, which is the turtling [pacing](../../../design-framework/pacing.md) is wary of.
- **Temporary: a lithium pond** (a finite charge `Q`). Its value is `Q` however it is worked. The
  rate only sets how long it must be held (`Q / r`). It **does not compound**: it is a prize,
  won once, whose value does not depend on how long the match runs. That is G2's "neutral
  things are prizes" exactly.

**Suggested division of labour:** permanent income carries the **baseline**, the floor that keeps
a player who is behind in the game (G17). Temporary income carries the **swing**: the prizes
the mid-game fights are over (G3, G4, G14).

**The exchange rate between them already exists.** Map generation prices a site as
`site_energy_per_second × value_horizon_seconds` (timings §Map levers), so `value_horizon` is
how many seconds of a permanent site one unit of temporary charge is worth. Calibrate `Q` in
**armies**: a pond worth about one mid-game army makes contesting it worth about one fight.

## A calibration order

Each step fixes one knob from a target, so the numbers follow rather than being typed in. The
targets are guesses to be tested in play, not decisions.

1. **Army scale.** Pick `N` at first contact and at mid-game. Micro (G9, G11) wants it small:
   the order of ten basic units at first contact, not thirty. That sets unit prices relative to
   the bank.
2. **Replacement time.** Pick `T_rep` for a mid-game army, e.g. 60–120 s: a won fight is worth a
   minute or two of tempo, never the match (G3, G17). That fixes `I` from `A`.
3. **Throughput.** Set producer spend `S` so that `ρ ≈ 1` at the intended producer count. With
   `ρ ≈ 1`, the choice between another producer, tech and army is real.
4. **Extractor payback.** Set `c_x` so that `t*` outlasts first contact (timings eq. 4). Greed
   then has a window.
5. **Temporary charges.** Set `Q` to about one mid-game army.
6. **Tech,** last, against the surplus these leave ([tech-investment](tech-investment.md)).

Map distance feeds steps 2 and 4 through contact time, so the calibration is per median map
and random maps are allowed to skew it (G13).

## Pitfalls

- **Tuning costs without income.** A price means nothing except as seconds of income. Retune
  `c` and `I` together, and read every price change through `s_u`.
- **Compounding permanent income.** If sites are the main income, a territorial lead snowballs.
  The permanent share should be the floor, not the engine.
- **Large armies are an engine cost too.** A cheap-unit economy fields many units, which costs
  pathing, avoidance and fog updates, not only design clarity.
