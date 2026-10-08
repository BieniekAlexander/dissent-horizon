---
kind: Entity
title: an_plant_bomb
scene: res://scenes/entities/projectiles/an/an_plant_bomb.tscn
flavor:
  description: potato
  verbose: potato
damage: 10000
damage_type: EXPLOSIVE
blast: aoe_charge
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    lifespan: 0
  - lifespan: 1
    payload: 0
---

# An Plant Bomb
