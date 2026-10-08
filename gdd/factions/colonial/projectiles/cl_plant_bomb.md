---
kind: Entity
title: cl_plant_bomb
scene: res://scenes/entities/projectiles/cl/cl_plant_bomb.tscn
flavor:
  description: potato
  verbose: potato
damage: 10000
damage_type: EXPLOSIVE
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    lifespan: 0
  - lifespan: 3
    payload: once
---

# Cl Plant Bomb
