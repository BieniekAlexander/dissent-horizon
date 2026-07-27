---
kind: AbilityDefinition
title: Detonate
flavor:
  description: Set off a planted charge.
  verbose: |
    Given to the charge itself, or to the Sapper that planted it, from anywhere on the map and
    whether or not the charge can be seen.
command: command_detonate
cast_by: ALL
emits: res://scenes/entities/projectiles/an/an_plant_bomb.tscn
---
# Detonate

`emits:` is the blast: the charge throws it at whatever it rides on, or at the ground under it.
`cast_by: ALL` because every selected charge, and every selected Sapper's charge, is its own —
setting off one of them when the player selected five would be a surprise.

The charge's pool is one charge on a one-second cooldown, as Spot's is: a charge goes off once and is gone, so the cooldown never runs.
