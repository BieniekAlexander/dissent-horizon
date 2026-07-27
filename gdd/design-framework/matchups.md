---
title: Matchups — rules, identity departures, absences
type: design-note
---

# Matchups

Faction uniqueness makes some matchups skew. The rules below exist to catch a skew **while it
is still a design choice** rather than after it has shipped. Goal G10 in the
[framework](README.md).

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

From the faction overviews. Blank means not yet designed.

| | Colonial | Anarchist | Libertarian | Technocratic | Marxist | Theocratic |
|---|---|---|---|---|---|---|
| Minion | vulnerable vehicle | combat infantry | slow aircraft | vulnerable infantry | combat vehicle | vulnerable vehicle |
| Dominion | intern captured infantry | Retinue (colocated infantry) | Opticon (sparse placement) | reactors with a byproduct | damage structures | capture Shelters |
| Heal | Servants repair | field hospitals | | technicians repair | **absent** | |
| Mobility | **intentionally lacking** | cheap helicopters | aircraft at low tech | portals | speed modifiers | |
| Disable | Freeze | EMP | rocket defenses | | | |
| Positional | Work Detail | blend into buildings | Relays heal nearby | portals | frenzy | |

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
