---
kind: Entity
title: Sky Port
scene: res://scenes/entities/structures/cl/cl_airField.tscn
build:
  cost: {energy: 1000}
  time: 25
  requires: [cl_barracks]
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [6, 4]
trains: [cl_aircraftLight_antiLight, cl_aircraftMedium_antiMech, cl_aircraftMedium_transport, cl_aircraftStrong_support]
infrastructure: -75
ui: {grid: [2, 1], factions: [colonial], context_grid: [3, 0]}
---
## Visuals
- flat tarmac apron, one runway down the long axis with two parking pads either side of
  it, a control tower at one corner and a low fuel bunker at the other. The mesh occupies
  the whole 6x4 footprint and nothing overhangs it — see `sky_port()` in
  `assets/meshes/generate_colonial_meshes.py`.
# Notes
- The `Pad` markers on the scene sit on the four apron squares the mesh draws, and the
  `Runway` marker is the touchdown/departure point at the +X end. Docking aircraft land on
  the runway and taxi to a pad, so those markers and the art have to agree.

