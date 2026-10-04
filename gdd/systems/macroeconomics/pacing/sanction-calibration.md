---
title: Sanction calibration — prices, tiers and dominion rates
type: system-note
---

# Sanction calibration

**TODO — research. Only items marked Decided are settled.** Part of [pacing](README.md). This
note turns [dominion-and-ordnance](dominion-and-ordnance.md)'s model into a first pass of
numbers and a four-tier grid. The grid's rules are [sanction-grid](../sanctions/sanction-grid.md).
Every number here is a **starting point for playtesting**, not a tuned value.

Tiers are named **T1–T4** here, counted from 1. The code counts from 0 (`SanctionUnlock.tier`),
so T1 here is `tier: 0` in a sanction doc.

## The economic framing

A sanction is a **permission**. The structure that casts it is **capital**. Its return is a fixed
number of charges per cooldown, for the rest of the match. Some useful terms:

- **Complements.** A sanction is worth nothing without a caster, and a sanction-gated caster is
  worth nothing without its sanction. Price the two as a pair. **Not every ability is a
  complement:** some structures grant abilities with no sanction at all (the Bombard's battery).
  For those, the structure's price carries the whole cost.
- **No usage price.** **Decided (Alex, 2026-10-02): there is no plan for a per-use cost.** The
  whole cost is the dominion unlock, the caster's energy and the recharge time. Cooldown is the
  only rate limit, so **caster count multiplies output**. That makes the caster's price the main
  control on how often an ability can be used.
- **Return on capital, and payback.** A caster yields `value per charge / cooldown` per second.
  Divide by its energy price for a return comparable with an extractor's (5/s for 500 energy:
  1% of its price per second, a 100 s payback).
- **Increasing returns.** One unlock pays across every caster, so a sanction is worth more to the
  player who will build more casters. Informant on the Stronghold is the clean case.
- **Horizon.** An unlock pays back over the rest of the match. A cell bought at minute 12 has a
  few minutes to earn its price, which is the economic argument for T4 being decisive per charge
  rather than efficient.
- **Real option.** The unlock buys the right, not the obligation, to invest in casters. That is
  why it can be worth buying before the player knows how many casters they will want.
- **Marginal rate of transformation.** The rate at which one input (an extraction site) can be
  turned into either of two outputs (energy or dominion). It is the exchange rate between the two
  resources (§Fungibility).

## Fungibility: one dominion ≈ one energy

**Decided (Alex, 2026-10-02): dominion and energy magnitudes should be fungible.** The anchor is
the Technocratic dominion route: a Technocrat builds either an **energy extractor** or a
**dominion extractor** on a site. With a site paying `r_s` = 5 energy/s and a dominion extractor
paying `r_d`, one dominion is worth

```
e = r_s / r_d    energy
```

**Proposed: `r_d` = 5/s, so `e` = 1.** A 500-dominion sanction is then a 500-energy decision.

`e` = 1 is safe because of the complements rule. A Technocrat who turns every site to dominion
cannot afford the casters, so all that dominion buys permissions nobody can use.

### Every faction's rate, in site-equivalents

Calibrate each faction's dominion rate as a fraction of one site's `r_s`, not as a raw number.
**Decided: the exact rates are revisited as part of this work.** Today's, read that way:

| Faction | Today | At `e` = 1 | Reading |
|---|---|---|---|
| Colonial | 1/s per captive (`dominion_per_unit` 5 per 5 s), Compound capacity 3, 60 s sentence | a Shelter worked to steady state (if one captive arrives per 10 s: × 60 s ≈ 6 captives, across two Compounds) ≈ 6/s ≈ **1.2 sites** | plausible |
| Anarchical | 1/s per BIO follower near a Warlord | 8 followers ≈ 8/s ≈ **1.6 sites** | **likely too generous**: the followers are also an army, so the investment is dual-use, unlike a Technocrat's extractor |
| Libertarian | 0.0032/s per claimed tile | depends on coverage | to be measured in self-play |
| Technocratic | proposed 5/s per dominion extractor | **1 site each**, by definition | the anchor |
| Colonial Servants | 500 energy buys one 60 s sentence ≈ 60 dominion | ≈ 8 energy per dominion | intended to be inefficient; this puts a number on how much |

Open: whether a dominion extractor may sit on a pond, and whether choosing energy or dominion is
permanent for that extractor (Alex: TBD). A free toggle would let a Technocrat always hold the
ideal mix, which is an advantage no other faction gets.

## Tiers

**Decided (Alex, 2026-10-02): four tiers, down from five.** Higher tiers bring more volatility and
need more investment.

**The placement rule** (Decided): **offensive strength arrives later than defensive, utility and
informational strength.** Roles are not more specific than that. Strength of any kind still
climbs with tier: an ability that revealed the whole map would be very strong, so it belongs in
T3 or T4 even though it is informational.

Rough guidance for where a cell lands:

| Tier | Typical content |
|---|---|
| T1 | early and minor: defensive, informational, economic. Little room for offensive use (Informant 1 stealths one Irregular, a weak unit) |
| T2 | mild offence; defence and information can be strong |
| T3 | strong offence: big swings in a match |
| T4 | close to game-ending: several buildings destroyed, a small army made invincible, an army taken out of a fight |

### Price ladder

**Decided (Alex, 2026-10-04): the ladder is HALVED from the 2026-10-02 one, T1 excepted.** A
playtest as Colonial against a passive bot, all resources into dominion and 3–4 Shelters worked,
reached T4 money at about 10 minutes. Uncontested, Alex wants that by 5–6 minutes, so that the
~10-minute power peak is what a CONTESTED match reaches. The rates were left alone and the prices
halved, which keeps dominion and energy fungible at the rate the cells were priced against
(§Fungibility). T1 is held at 125–150 rather than halved, so starting dominion (100) still buys
nothing outright. Cells in one tier need not cost the same, and a cell may cost more than one in the next
tier as an exception. Keep cells *within* a tier reasonably close, so the cheapest pair does not
become every player's way of paying the tier toll
([dominion-and-ordnance](dominion-and-ordnance.md) §Gating).

| Tier | Price band (dominion) |
|---|---|
| T1 | 125–150 |
| T2 | 200–350 |
| T3 | 450–750 |
| T4 | 1000–1500 |
| **starting dominion** | **about 100, the same for every player** — below the cheapest cell (Decided) |

A flat starting amount is a fair head start once each faction's rate is calibrated so its first
purchase lands at the same time (§Time to tier). This supersedes
[dominion-and-ordnance](dominion-and-ordnance.md) §Starting dominion's suggestion to set it per
faction.

### Time to tier

Assume the dominion rate climbs as the player invests in it. A target rate ramp, in site-equivalents.
**It is an UNCONTESTED ceiling.** Dominion gathering is designed to be vulnerable to interference
(Alex, 2026-10-02), so in a real match every arrival time below slips by however much the opponent
disrupts collection:

| Match time | Rate | Site-equivalents | Cumulative dominion |
|---|---|---|---|
| 0–3 min | 3/s | 0.6 | ~540 at 3 min |
| 3–7 min | 6/s | 1.2 | ~2000 at 7 min |
| 7–12 min | 10/s | 2 | ~5000 at 12 min |
| 12 min on | 12/s | 2.4 | ~7100 at 15 min, ~10700 at 20, ~14300 at 25 |

Against the lower end of the ladder (T1 200, T2 500, T3 1000, T4 2500), with only the toll bought:

| Milestone | Dominion needed | Arrives at about |
|---|---|---|
| first T1 cell | 100 after the start | under a minute |
| T2 open (two T1) | 400 | 1.5–2 min |
| T3 open (+ two T2) | 1400 | 5 min |
| T4 open (+ two T3) | 3400 | 9 min |
| first T4 cell | 5900 | 13 min |

With matches targeted at 10–15 minutes, the first T4 cell is a late-game closer, as intended.
Every extra cell bought off the toll path pushes these later, which is the depth-versus-breadth
trade the grid exists for.

**Late dominion is a large share of income.** 12/s at `e` = 1 is 2.4 sites, a quarter to a half of
a mid-game energy income of 25–50/s ([resource-allotment](resource-allotment.md)). That is the
super-meter role working as designed, but it is also the first knob to turn if dominion
dominates.

## Finishing the grid, and the second T4

**Decided (Alex, 2026-10-02):** the whole grid **may** be bought if a match runs long enough. More
than one T4 cell should be **prohibitively expensive in any match that is not very drawn out**.
The volatility of the abilities should usually end a match before then. Collecting that much
dominion will mostly happen in casual, lower-skill play and in relaxed matches against easy bots.
This supersedes [dominion-and-ordnance](dominion-and-ordnance.md) §The grid is never finished.

**Decided (Alex, 2026-10-02): about three minutes between the first and second T4 is fine.** Late
in a match dominion arrives at about 12/s, so a second 2500 cell is about 3.5 minutes behind the
first (about 16.5 min above) when collection goes uncontested. Because collection is meant to be
interfered with, the real gap is longer, and a player who wins the second T4 has usually won the
fight over their dominion too. **So price alone is the starting point, with no new mechanic.**

The levers, should self-play show second T4s arriving too often:

1. **The caster gate, which already exists.** Each T4 cell is cast from its own expensive,
   slow-charging building: the Storm Cell (2000 energy, 240 s cooldown) for Blizzard and the EMP
   Device (2000, 300 s) for Global EMP. A second T4 is a second energy commitment of that size,
   so the complements rule already makes it expensive. Check that this binds before adding
   anything.
2. **Price T4 at the top of its band** (3000). It costs the first T4 about a minute.
3. **An escalating T4 price**: each T4 owned multiplies the next one's price (×2 puts the second
   at about 20 minutes on the ramp above). Not wanted for now; it would need code.

Whole-grid prices on the proposed grids below, at the band midpoints (T1 225, T2 550, T3 1200,
T4 2500), with no escalation:

| Faction | T1 | T2 | T3 | T4 | Total | Reached at about |
|---|---|---|---|---|---|---|
| Colonial | 3 cells | 4 | 3 | 3 | ≈ 14 000 | 24 min |
| Anarchical | 3 | 4 | 3 | 3 | ≈ 14 000 | 24 min |

So the whole grid is reachable only in drawn-out matches, as intended.

TODO: §Time to tier and §Finishing the grid below still work the 2026-10-02 ladder. At half the
prices on the same ramp, T4 opens at about 6.5 minutes and the first T4 cell lands at about 8.5 —
redo them once a measured rate ramp replaces the assumed one.

## Proposed grids

Each tier T1–T3 needs at least two cells, or the tier below it can never open.

### Colonial

| Tier | Cells |
|---|---|
| T1 | Promotion, Scan 1, Freeze 1 |
| T2 | Drop 1, Scan 2, Freeze 2, Beacon |
| T3 | Drop 2, Gunship |
| T4 | Drop 3, Blizzard |

- **Drop stays at three levels** (Decided, for now), placed T2–T4 because even Drop 1 can open a
  second front. Drop 1 at T1, framed as reinforcing a defence, is the alternative.
- **Beacon** is one level at T2 (decided 2026-10-04, moved down from T3 the same day): a
  ground-only, permanent, blind solution, priced at the top of T2.
  REJECTED: the three-level version (a 15 s clock, then sight, then no clock) — collapsed into the
  one level at Alex's direction.
- **Freeze 2** at T2: freezing one enemy is control, and it raises the target's armour, so it is
  mild offence at most.

### Anarchical

| Tier | Cells |
|---|---|
| T1 | Dignify, Informant 1, Scavenge 1 |
| T2 | Ambush 1, Informant 2, Scavenge 2, Mortar 1 |
| T3 | Ambush 2, Scavenge 3, Mortar 2 |
| T4 | Informant 3, Mortar 3, Global EMP |

- **Informant 3** (stealth for any friendly unit) moves to T4 (Alex, 2026-10-02).
- **Mortar 3** (16 shells) at T4 is close to "destroying several buildings".
- **Overcharge leaves the Anarchists** (Alex, 2026-10-02): it needs a stunned target, and their
  only stun is Global EMP, a tier below Overcharge's current place. It will likely move to the
  Libertarians. **Rule:** Overcharge belongs to a faction with a usable EMP at a lower tech
  level.

## Changes to specific families

### Scan: two levels, permanent, larger

**Decided (Alex, 2026-10-02):** Scan drops from three levels to two. The observer **no longer
expires**, and **level 2 adds detection**. **The radius grows**: at 10 it is smaller than an
infantry unit's sight (`vision_ground_small`, 16), so it feels useless.

| Level | Tier | Observer | Reveal | Detection |
|---|---|---|---|---|
| Scan 1 | T1 | permanent, **visible** | larger radius | none |
| Scan 2 | T2 | permanent, possibly **stealthed** | same | yes |

- **Decided (Alex, 2026-10-02): the reveal grows to `vision_ground_large` (24) for now**, up from
  10 — the structure vision shape in [shapes](../../../shapes/shapes.md). For Scan 2's detection, `detection_medium` (16) keeps it below
  dedicated detectors, and `detection_large` (24) makes it one.
- **Counterplay is the observer itself.** It is a Recon Drone, visible and shootable by
  anti-air, so a permanent reveal costs the opponent an anti-air response rather than nothing.
- **If Scan 2's observer is stealthed,** the counter becomes detection, and a detector observer
  that is itself stealthed is the strongest information tool in the Colonial grid. Check it
  against the placement rule: it may want T3.
- **Watch accumulation.** On a 60 s Citadel cooldown, unanswered observers pile up over a match.
  A cap on live observers per commander is the fallback if anti-air is not enough.

### Ambush: two levels

**Decided (Alex, 2026-10-02):** Ambush drops to two levels, roughly **3** and **8** Irregulars.

### Drop: an expensive caster

**Finding:** Drop returns energy-equivalent units faster than an extractor returns energy. On the
Supply Beacon (800 energy, 60 s cooldown):

| Level | Best shipment | Value per charge | Per second | Return on caster price |
|---|---|---|---|---|
| Drop 1 | 3 Recruits | 300 | 5 | 0.6%/s |
| Drop 2 | 5 Recruits | 500 | 8.3 | 1.0%/s |
| Drop 3 | 2 Sloops | 1000 | 16.7 | 2.1%/s |
| *extractor on a site* | — | — | 5 | 1.0%/s |

**Decided (Alex, 2026-10-02): make the Supply Beacon a very expensive investment**, after Zero
Hour's Supply Drop Zone, **priced about 2000–2500 energy.** The rule behind it: a caster that
delivers units should pay back no faster than an extractor at its *top* level. Drop 3 at 16.7/s
then needs a Supply Beacon of at least about 1700 energy. At 2000–2500, Drop 1 is a slow
investment (a 400–500 s payback) that only the deeper levels justify.

Ambush, for comparison, is safe today: the Hideout (600 energy, 180 s) yields 1.7/s at 3
Irregulars and 4.4/s at 8.

### Command centres: three minor abilities each

**Decided (Alex, 2026-10-02):** each faction's command centre should carry **three minor
abilities** in its shared pool, for player expression. An ability too strong for that is moved
to a different building. Stealth on one unit (Informant 1) counts as minor. Command-centre prices
are set with this in mind, so a second centre's extra charges stay worth less than the same
energy in army ([dominion-and-ordnance](dominion-and-ordnance.md) §The command centre).

## Implementation (applied 2026-10-02, repriced 2026-10-04)

Done, as starting points for playtesting:

- `SanctionGrid.NUM_TIERS` 5 → 4; every sanction doc re-tiered per §Proposed grids.
- Every cell priced from the ladder (halved 2026-10-04; T1 held at 125–150):

  | Tier | Colonial | Anarchical |
  |---|---|---|
  | T1 | Promotion 125, Scan 1 150, Freeze 1 125 | Dignify 125, Informant 1 125, Scavenge 1 150 |
  | T2 | Drop 1 250, Scan 2 225, Freeze 2 300, Beacon 350 | Ambush 1 225, Informant 2 250, Scavenge 2 300, Mortar 1 275 |
  | T3 | Drop 2 600, Gunship 750 | Ambush 2 550, Scavenge 3 600, Mortar 2 600 |
  | T4 | Drop 3 1000, Blizzard 1500 | Informant 3 1000, Mortar 3 1250, Global EMP 1500 |

  Overcharge, parked off every grid, was halved with them (250).

- `PlayerSlot.starting_dominion` default 300 → 100. Scenarios that set their own value (the
  tutorial, `blue_hole`, test scenes) were left as content.
- Scan: two levels, a permanent observer, reveal 24; level 2 detects at 16 (`detection_medium`,
  provisional — the open question below).
- Ambush: two levels, 3 and 8.
- Supply Beacon (`cl_support2`) 800 → 2000.
- Overcharge parked: off the Anarchist grid **and out of the Clandestine Lab's ability pool**,
  since an ability no grid offers is free, so leaving it on the Lab would have granted it with no
  dominion cost. The doc stays, unlisted, until it moves to a faction with a low-tier EMP.
- [sanction-grid](../sanctions/sanction-grid.md)'s worked examples and cell counts.

Not done:

- Dominion rates per §Fungibility, and the Technocratic dominion extractor (the rates are to be
  revisited; nothing numeric was decided).

## Open questions

- Technocratic dominion extractors: allowed on ponds? Is the energy/dominion choice permanent?
- Drop's tier placement: T2–T4, or T1–T3?
- Scan 2: stealthed observer or not, and which detection radius?
