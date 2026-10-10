---
kind: AbilityDefinition
title: Spot
flavor:
  description: Call in a firing solution, leaving a beacon for the artillery to spend.
  verbose: |
    A Recruit walks within range of the chosen point, holds still while it calls the strike
    in, and leaves a [[beacon|Beacon]] standing there. It then STAYS on the beacon until a
    Bombard fires on it — that commitment is what the artillery is paying for. The nearest
    loaded Bombard fires as soon as it can, unless you have switched the Bombard to manual.

    A Sleeper, once Cell Activation is researched, walks to the point itself, plants a beacon
    on the ground over 3 seconds, and moves on. Its beacon stands until a Bombard is ordered onto it.

    A LOCAL ability: it is an order given to the spotter, not something the commander calls in,
    so it has no cell on the ORDNANCE card.
command: command_spot
range: 10
---
# Spot

One order, two ways of carrying it out: a Recruit HOLDS its beacon, a Sleeper
(`plants_beacons: true`) PLANTS one and leaves — see
[bombardment](../../../systems/combat/bombardment.md) §Planting a beacon.

The Colonial half of the bombardment loop — see
[bombardment](../../../systems/combat/bombardment.md).

Folded out of the `Spotter` component, whose PRESENCE was the whole capability.

**The reach is this doc's `range:`**, read through `AbilityCatalog.range_for`, so an upgrade can
raise it: [[advanced_targetting|Advanced Targetting]] takes the Recruit's to
`ground_range_siege`. It was a constant until then, on the grounds that a value that never varied
was not a configuration; the upgrade is what made it vary. The reach sets both how close the
spotter walks before it starts calling the strike in and the leash on a beacon riding a unit.

The channel time stays a [constant](../../../../scripts/interface/commands/spot.gd): nothing
varies it yet.

The charge is spent when the channel starts, and the pool does not recharge while the
order stands: its cooldown runs from the moment the order ends, whether a Bombard fired on
the beacon or the spotter was re-ordered. A spotter therefore cannot bank a charge while
holding a solution, and an order abandoned on the walk there costs nothing.

## One spotter per order

Spot is cast by ONE of the selected recruits, the ability default (see
[control-matrices](../../../systems/ux/ui/control-matrices.md) §Cast arity): the nearest to the
point that is not already spotting — the rule every one-actor command shares, Build included
(control-matrices §Cast arity). Holding `modifier_broaden` sends every selected recruit.

It was `cast_by: ALL` until 2026-10-06, on the grounds that a second solution on the same ground
is worth having. Once a beacon called its own shot (bombardment §Automatic fire), a second
spotter on the same point was a second recruit standing still for one shell, and a squad
marking one target lost all its rifles to do it.
