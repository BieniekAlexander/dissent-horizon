---
kind: Entity
title: Planted Charge
scene: res://scenes/entities/units/an/an_plantedCharge.tscn
flavor:
  description: A Sapper's charge, waiting to be set off
  verbose: Goes off when its Sapper says so, when it is destroyed, or when what it rides on is. Removed without going off if its Sapper dies, or if an enemy repairs it away.
defense:
  hp: 50
  armour: LIGHT
  frame: MECH
senses:
  vision: false
abilities:
  - max_charges: 1
    cooldown: 1
    grants:
      - detonate
stealth: true
---
# Planted Charge

Placed only by [[plant]]; never built or trained. Its behaviour is the scene-authored
`PlantedCharge` component — one piece has it, so it is not a doc key. See
[planted-explosives](../../../systems/combat/planted-explosives.md).
