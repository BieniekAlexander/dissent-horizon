---
title: Matchups — rules, identity departures, absences
type: design-note
---

# Matchups

Faction uniqueness makes some matchups skew. The rules below exist to catch a skew **while it
is still a design choice** rather than after it has shipped. Goal G10 in the
[framework](design-framework/README.md).

## Rules

**M1 — Answerability.** For every threat faction B can field, faction A has an answer, and
that answer is reachable in A's tech tree. The reverse holds too.

**M2 — Scoutable lead time.** If B can produce a threat, A had a reasonable chance to scout it
and prepare in time. Put another way: the time between B's tell becoming visible (a
prerequisite structure, a production building) and the threat arriving must cover the time A
needs to reach its answer.

**M3 — No dead pieces.** It should be rare for a unit to be completely useless against another
faction. A unit whose damage finds few targets there (a Toxic weapon against the Libertarians)
carries some other utility that keeps it situationally useful.

**M4 — Identity departures are declared.** A faction's uniqueness is a systematic departure
from the game-wide norms, and it is written down with what compensates for it. An undeclared
departure is how a skew goes unnoticed. This is the concrete form of `unit-calibration.md`'s
open question on what faction identity does to the calibration norms.

## Identity departures

| Faction | Departure | Compensated by | State |
|---|---|---|---|
| Colonial | units generally struggle to traverse the map quickly | strength in map encroachment | declared |
| Anarchist | not a wide array of durable MECH units — glass cannon | | declared; TODO: name the compensation |
| Libertarian | no BIO units | | TODO: name the compensation |
| Marxist | no heal; glass cannon | tempo, frenzy | from the faction overview; TODO: two glass-cannon factions need to differ in how |

## Faction slots

**A slot is a mechanic every faction has its own version of** — the Slot tier of the
[README](design-framework/README.md) §Tiers. This table is the canonical list; each faction doc says what its
version is under `slots:` in its front matter, keyed by the ids below. A value of `TODO` means
not yet designed, and `ABSENT — …` a deliberate hole (with its matchup consequences, M1–M4).

| Id | Slot | What the faction's version answers |
|---|---|---|
| `dominion_generation` | Dominion generation | how it earns dominion |
| `secondary_economy` | Secondary economy | how it earns energy beyond extraction |
| `disable` | Disable | how it shuts enemy pieces down |
| `mobility` | Mobility | how it moves fast or crosses terrain |
| `garrison_clearing` | Garrison clearing | how it flushes an enemy out of a building |
| `stealth` | Stealth | how its pieces go unseen |
| `stealing` | Stealing | how it takes enemy units, structures, resources or production (coverage parity matters: a BIO-only steal cannot touch the all-MECH Warden) |
| `power_scaling` | Power scaling | how its power grows over a match through play (Zero Hour: GLA scrap, China horde, USA pilots) |
| `scouting` | Scouting | how it finds things out — vision and detection; at least one medium detection source at low tech ([static-defence](static-defence.md) invariant 6) |
| `constitution` | Constitution | how it keeps its pieces alive — healing, repair, regeneration, shields |
| `infrastructure` | Infrastructure | how it provides infrastructure |

Revised 2026-10-17. Minion, positional and static defence are no longer slots; heal became
`constitution`, detection became `scouting`, and unit bonus became `power_scaling`.

The per-faction view, drawn in Obsidian from the faction docs' `slots:`:

```dataviewjs
const ids = ["dominion_generation", "secondary_economy", "disable", "mobility", "garrison_clearing",
	"stealth", "stealing", "power_scaling", "scouting", "constitution", "infrastructure"];
const factions = ["colonial", "anarchical", "libertarian", "technocratic", "marxist", "theocratic"]
	.map((f) => dv.page(`factions/${f}/${f}`)).filter((p) => p);
dv.table(["", ...factions.map((p) => p.file.name)],
	ids.map((id) => [id, ...factions.map((p) => (p.slots ?? {})[id] ?? "")]));
```

## Known skews

| Matchup | Skew | Rule | State |
|---|---|---|---|
| any vs Libertarian | no BIO: anti-BIO damage types (Toxic, Sonic, Lead, Incendiary) find few targets; bio stun has none | M3 | TODO: give the affected pieces a secondary utility |
| Anarchist vs Libertarian | the mech-only EMP reaches the whole army; every unit is a Hijacker target | M1 (reverse) | TODO: check the Libertarian answer to Condors and Hijackers |
| Colonial vs Libertarian | the Stock Truck captures light BIO only, so Colonial dominion there is Shelters only | M4 | TODO: accept or compensate |
| command-center win condition | command-center HP is a placeholder for three factions (a small fraction of the other two) | M1 | only matters if the proposal is adopted |

## Catching skews ahead of time

TODO (proposal, not built): generate a **threat/answer matrix** per ordered faction pair from the
spec docs, which already carry everything it needs — frame, armour, movement layer, damage
type and what it hits, and the `requires` chain that sets tech depth. For each of B's units it
lists A's units that damage it well *and* can reach its layer, with each side's tech depth.
It flags a threat with no answer at or below its depth (M1/M2) and an A unit with nothing
worth hitting in B (M3). The damage tables are already plain TSV for exactly this kind of
tooling. Behaviour-level checks, such as whether an answer actually holds, belong to the
simulation tests rather than to the matrix.
