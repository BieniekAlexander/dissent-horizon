---
title: Structure costs — pricing buildings by role
type: system-note
---

# Structure costs

**Applied (Alex, 2026-10-01)**, as a starting point for playtesting. Part of [pacing](README.md). The question (Alex,
2026-10-01): Colonial structures cost Zero Hour prices while units cost about half of Zero
Hour's, so a base takes twice the share of a player's energy it does there
([resource-allotment](resource-allotment.md)). Revisit the prices, with half of Zero Hour as a
starting point rather than a rule.

## How to price a structure

Half of Zero Hour is the anchor. Each structure then moves by its role, using the marginal-value
classes in [building-roles](building-roles.md):

- **A producer is worth two or three of what it makes** (the observation in
  [design-framework/pacing](../../../design-framework/pacing.md)). A Barracks making 100–300
  units prices at 300–600; a War Factory making 500–750 tanks at 1000–1500. An airfield is
  capacity-limited, so it sits under its aircraft.
- **A tech gate is priced by the window it should open**, not by what it unlocks
  ([tech-investment](tech-investment.md) §Calibration band): tier one about two mid-game units,
  tier two about two late ones.
- **An ordnance caster's return per energy must not beat army**
  ([dominion-and-ordnance](dominion-and-ordnance.md)): price it against its charges.
- **Static defences** follow [static-defence](../../../design-framework/static-defence.md); today's
  are already below half of Zero Hour's and stay.
- **Overhead target: about 15–20% of what a player spends in a long match**, roughly Zero Hour's
  share. On the ~46k–50k of [resource-allotment](resource-allotment.md), that is 7k–10k for one
  full tech line with its support structures.

## Colonial

| Structure | Role | Now | Zero Hour analogue (½) | Proposal | Why |
|---|---|---|---|---|---|
| Compound (`cl_infrastructure`) | infrastructure, dominion, gate to Barracks | 1000 | Power Plant 800 (400) | **600** | mandatory and first; a high price only delays every opening equally |
| Barracks | producer (100–300 units) | 500 | 500 (250) | **300** | three baseline units |
| Air Field | producer, capacity-limited | 1000 | 1000 (500) | **700** | under the aircraft it docks |
| War Factory | producer (500–750 units) | 2000 | 2000 (1000) | **1200** | two tanks; also fixes its build-time outlier ([timings](../../../design-framework/timings.md) §Build-time outliers) |
| Operations Center (`cl_tech1`) | tier-one gate, research | 1200 | Strategy Center 2500 (1250) | **800** | about two mid-game units; it now researches too ([upgrades](../upgrades.md)) |
| Academy (`cl_tech2`) | tier-two gate, Gunship ordnance | 2000 | — | **1200** | about one late unit plus its ordnance |
| Annex (`cl_support1`) | minor support | 1000 | — | **500** | |
| Supply Beacon (`cl_support2`) | Drop ordnance caster | 1200 | — | **800** | one 60 s charge |
| Storm Cell (`cl_support3`) | Blizzard, superweapon-like, 240 s | 2500 | Particle Cannon 5000 (2500) | **2000** | still the dearest building; the charge is the cost |
| Citadel (`cl_commandCenter`) | command centre | 2000 | 2000 (1000) | **1500** | decided: another one must be a poor buy against army |
| Watch Tower, Sam | statics | 400 | 800–1000 (400–500) | 400 | already at half |
| Bombard | static artillery | 1000 | — | 1000 | |

**Overhead:** the production and tech line falls from 7700 to 4800, and with the three support
structures from 12400 to 8100: about 17% of a 46k match.

## Anarchical

The same roles give: Safehouse (`an_infrastructure`) 800 → 500 (it takes its price from the
neutral buildings it converts, so that family was scaled by the same factor: large 1200 → 750,
long and square 800 → 500, shack 500 → 300), Redoubt (`an_barracks`) 1000 →
400, Chop Shop (`an_warFactory`) 2000 → 1200, Hangar (`an_airField`) 800 → 700, Stockpile
(`an_tech1`) 1200 → 800, Clandestine Lab (`an_tech2`) 2000 → 1200, supports 1000 / 2000 / 3000
→ 600 / 1200 / 2000, command centre 1500 unchanged.

The Libertarian prices are placeholders (300–500 across the board) and are left until that
roster is designed.

## Pitfalls

- **Build times stay put, so build rate moves.** A War Factory at 1200 in 15 s is still the
  fastest build per energy. Revisit times with prices, against the 60 s first-contact target.
- **Cheaper gates move tech earlier.** Lower tech prices shorten the window
  ([tech-investment](tech-investment.md)). The cut is meant to match the overhead to the economy,
  not to speed tech up, so watch tier timings in self-play.
- **The generator prices nothing here, but map space does.** Cheaper structures mean more of them,
  which leans on buildable area ([building-roles](building-roles.md) §Size is a price).
