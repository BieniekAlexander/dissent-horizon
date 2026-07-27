---
kind: AbilityDefinition
title: Radiate
flavor:
  description: Lay down a radiation field on a point within range.
  verbose: |
    A LOCAL ability, not an ordnance: the unit carrying it walks into range and puts the field
    down itself, so there is no commander-level button and no cell on the ORDNANCE card.

    Charges are the unit's own pool — three of them, one back every three seconds — so a
    carrier can lay a short burst and then has to wait.
command: command_launch
range: 5
emits: res://scenes/entities/projectiles/radiation.tscn
---
# Radiate

Folded out of the hard-coded `Ability.Type` enum, which was a second, parallel ability system
holding exactly this one member. Nothing about the mechanic changed in the move: the pool is
authored to the charge count and reload period `ToolSpec` defaulted to.

`range:` is 5 world units — the value every ability shared back when `Ability` carried one
hardcoded `RANGE` for all of them. It is authored here now because reach is a property of
the ability rather than of the command class, which is what let the [[bombard]] stop being
a second copy of that class.

Carried by the [[tc_bioLight_antiMech]], the [[an_aircraftLight_antiMech]] and the
[[cl_bioLight_antiLight]].
