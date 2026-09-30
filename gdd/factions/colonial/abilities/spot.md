---
kind: AbilityDefinition
title: Spot
flavor:
  description: Call in a firing solution, leaving a beacon for the artillery to spend.
  verbose: |
    The unit walks within range of the chosen point, holds still while it calls the strike in,
    and leaves a [[beacon|Beacon]] standing there. It then STAYS on the beacon until a Bombard
    spends it — that commitment is what the artillery is paying for.

    A LOCAL ability: it is an order given to the spotter, not something the commander calls in,
    so it has no cell on the ORDNANCE card.
command: command_spot
range: 10
cast_by: ALL
---
# Spot

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

The pool is one charge on a one-tick cooldown — that is "no cooldown", spelled in the one
vocabulary every ability uses, rather than a second concept meaning the same thing.

## `cast_by: ALL`, alone in the roster

Every other ability is cast by ONE of the selected casters (see
[control-matrices](../../../systems/ux/ui/control-matrices.md) §Cast arity) — the default,
because the whole selection firing at one point spends every charge on it.

Spotting is the exception that default was written against. A second solution on the same
ground is worth having rather than wasted: the beacon is what a battery spends, and a spotter
committed to one is out of the fight until it is spent, so ordering a squad to mark a target
and having one of them do it leaves the rest idle for no reason. Holding `modifier_narrow`
still sends exactly one.
