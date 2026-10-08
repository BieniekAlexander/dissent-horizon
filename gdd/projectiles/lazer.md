---
kind: Entity
title: lazer
scene: res://scenes/entities/projectiles/lazer.tscn
flavor:
  description: potato
  verbose: potato
damage: 20
damage_type: LEAD
status_effects: [lazer_burn]
hitscan: true
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    lifespan: 0.2
  - lifespan: 0
    payload: once
---

# Lazer
