---
kind: Entity
title: Compound
scene: res://scenes/entities/structures/cl/cl_infrastructure.tscn
flavor:
  description: Holds prisoners; supplies infrastructure and dominion
  verbose: Supplies infrastructure, and banks dominion for every prisoner serving its sentence in it
build:
  cost:
    energy: 600
  time: 20
defense:
  hp: 750
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
garrison:
  capacity: 3
  closed: true
  bunker: false
  sentence_length: 60
abilities:
  - max_charges: 1
    cooldown: 1
    grants:
      - work_detail
infrastructure: 100
ui:
  grid:
    - 2
    - 0
  factions:
    - colonial
---

# Compound

The Colonials' infrastructure structure and their dominion structure are the same building. It
holds up to 6 occupants, and each one generates dominion every cycle.

It is stocked by [[cl_mechLight_dominionGen|Stock Trucks]] delivering what they captured, and
**a deposited captive is held as ITSELF for `sentence_length` (60s, a placeholder) before
being CONSUMED** — a prisoner is not put to work, it is spent. Naming a positive
`sentence_length` is also what marks this building as a deposit target at all
(`Garrison.can_intern`).

**The garrison is CLOSED**: nothing may be ordered into it — deposit is the only way in — and
it names no `pieces:` allowlist, since a captive is never converted into a Servant that could
walk back out.

**Servants arrive by deposit too**, riding a [[cl_mechLight_dominionGen|Stock Truck]], and serve
a sentence like a prisoner: they pay dominion each cycle and are consumed at the end of it.
Unlike a prisoner, a Servant can be let out before then — Evacuate, or its card in the info
panel, returns it to the game — while the captives beside it stay. A Servant is a very
cost-inefficient source of dominion (500 energy a head), which is the point: an option, not a
route. On a sentence completing, the Compound reduces the cooldown of every ability
pool on every edge-adjacent friendly structure by a percentage of its full duration ([[work_detail|Work
Detail]]). Destroy it and its occupants go free, to the commander they were taken from —
rescuing them, not merely denying the income.

See [colonial-dominion](../../systems/combat/colonial-dominion.md) for the mechanics and
[unit-tasking](../../systems/commands/unit-tasking.md) for how a Stock Truck is kept fed.

# Notes
- **Reworked 2026-09-17**: conversion-on-deposit retired in favour of a SENTENCE — a captive
  is held as itself and consumed at the end of its term, and the passive Work Detail rate is
  now a per-completion cooldown-reduction event. The Servants-only allowlist (`garrison.pieces`)
  is gone with it: the garrison is CLOSED again, as it was before the 2026-08-26 rework, but for
  a different reason — a prisoner it holds is never a Servant to walk back out.
- **Reworked 2026-08-26**: was a closed hold banking anonymous prisoners; became a
  Servants-only garrison that converted what was deposited into it. The `is_closed()` test
  that marked it as a prison was replaced by `interns:` — see the
  garrison-and-transport design note
- **Merged 2026-08-15**, from `cl_infrastructure` (Power Plant, infrastructure 100, 2×2) and
  `cl_dominion` (Internment Camp, the closed garrison + `OccupantDominionGenerator`). This
  doc is the camp's, re-keyed onto the Power Plant's id and carrying its `infrastructure:
  100`; the Power Plant doc and both `power_plant.tscn` / `cl_infrastructure.tscn` are gone
- Takes the **infrastructure** grid cell (1, 0) rather than the dominion cell (2, 0). Structure
  buttons are laid out by ROLE so a cell means the same thing in every faction, and this
  piece is `cl_infrastructure`; (2, 0) is simply empty for the Colonials. See CLAUDE.md
  §Structure buttons are laid out by ROLE
- Its `requires: [cl_infrastructure]` was dropped as self-referential. Everything that gated
  on either half now gates on this one building: `cl_barracks` and `cl_defense_antiAircraft`
  already named it, and `cl_defense_antiStructure` was moved off `cl_dominion`
- Consequence of the merge worth knowing: the Compounds standing in s1/s2/s3 are no longer
  an id the tech tree doesn't know — they are `cl_infrastructure`, so each one PROVIDES 100
  infrastructure to whoever owns it. That is the merge working as specified, not a scenario
  edit
