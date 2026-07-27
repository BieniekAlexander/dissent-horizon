---
kind: AbilityDefinition
title: Work Detail
flavor:
  description: Each sentence served here shaves 8% off the full cooldown of every ability pool on the buildings next door.
  verbose: |
    A POSITIONAL passive, and the only one in the game: it benefits the buildings the
    Compound TOUCHES rather than the Compound itself. Edge contact is what counts — a
    building meeting it corner-to-corner shares no wall and gets nothing.

    The bonus fires per COMPLETION, not per head held. The instant a captive's sentence
    ends, every adjacent friendly building's ability pools each lose 8% of their own full
    cooldown — a fixed chunk of time you can count ("three sentences off the next scan"),
    not a rate that speeds up while the Compound is full. A pool already at full charge
    banks nothing from a completion it did not need.

    Nothing is lent by a Compound that is still going up, by one its commander cannot
    power, or across the front line — only your own buildings are worked.
passive: true
valence: BOON
---
# Work Detail

The Colonials' positional passive: the Compound is not only where captured labour is
banked, it is where that labour is *spent*. Standing a barracks or a tech building against
one is what turns every sentence served into faster abilities next door, which is the whole
reason to think about where a Compound goes.

## Mechanic
No deployment, no aim point, no charge of its own. On a sentence completing —
`Garrison._emit_positional_bonus`, fired once per captive consumed — every adjacent
friendly structure's ability pools each have `SENTENCE_COOLDOWN_BONUS` (8%) of their own
FULL cooldown deducted, via `Abilities.reduce_all_cooldowns`. A percentage of the pool's own
duration, not of whatever time is left on it: a pool close to charging gets the same
absolute deduction as one that just fired, which is what lets a completion finish a
cooldown outright and what makes the deduction countable rather than a taper that never
quite lands.

Superseded the passive per-occupant RECHARGE RATE on 2026-09-17: the two halves of the
building now tell one story, since sentences reward *turning captives over* rather than
*holding* them, and a rate rewarding occupancy pulled the opposite way. See
[colonial-dominion](../../../systems/combat/colonial-dominion.md) §The positional bonus is
an event, not a rate.

"Adjacent" is EDGE contact between grid footprints, resolved through
`SpaceUtils.edge_adjacent_structures`. That definition is expected to change — a radius, a
supply line — which is why it is one call rather than a rule spelled at every reader.

## What switches it off
The same three things that switch off any structure's abilities, asked of the SUPPORTER
— the Compound whose sentence just completed, not the building being helped: it must be
finished, and its commander's infrastructure must cover its upkeep (see
[production and economy](../../../systems/macroeconomics/production-and-economy.md)
§Insufficient infrastructure). Nothing beyond friendliness is asked of the building being
helped, matching the passive rate this replaces.
