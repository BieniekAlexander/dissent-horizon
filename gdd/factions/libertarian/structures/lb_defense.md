---
kind: Entity
title: Security Tower
scene: res://scenes/entities/structures/lb/lb_defense.tscn
build:
  cost: {energy: 500}
  time: 20
  requires: [lb_infrastructure]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
  detection: detection_medium
footprint: [3, 3]
garrison:
  capacity: 1
  frames: [MECH]
  armours: [LIGHT]
  movements: [GROUNDED]
  bunker: true
  reach_by_piece: {lb_mechLight_antiLight: ground_range_long}
  pieces: [lb_mechLight_antiLight, lb_mechLight_support]
infrastructure: 50
ui: {grid: [3, 0], factions: [libertarian], context_grid: [2, 0]}
---

# Security Tower

The Warden's static defence: it holds **one drone at a time**, and which drone holds it decides
what the tower does. Its place in the faction's coverage: [[static-defence]] §Libertarians.

- **One drone, one target class.** `capacity: 1`, admitting only the ground drones (Shock Drone,
  Point Defense Drone). A tower's coverage stays narrow; breadth comes from how many towers a
  player builds and which drones fill them, which scouting can read.
- **The drone fires from inside** (`bunker: true`).
- **Per-drone properties** are `reach_by_piece` today — the first of them, and the stub the
  rest will follow: a garrisoned Shock Drone fires at `ground_range_long` instead of its melee
  zap. TODO: what the Point Defense Drone (and later drones) confer is open —
  [deferred](../../../deferred.md) 1.54.
- **Detection is the tower's own** (`detection_medium`), not a drone's, so the Warden's detector
  does not depend on drone tech.
- TODO: no swap time exists — a drone can be ordered out and another in as fast as they walk.

