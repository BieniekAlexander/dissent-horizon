---
kind: Entity
title: Battery Rack
scene: res://scenes/entities/structures/nt/nt_batteryRack.tscn
editor_description: Neutral hazard — destroy it and it blows.
commandable: false
flavor:
  description: A rack of storage cells. Its burst reaches further than one cell's.
  verbose: "A rack of superconducting storage cells wired as one: the stored field of a dozen cells. A quench cascades down the rack in an instant and throws a plasma burst a block wide."
defense:
  hp: 80
  armour: MEDIUM
  frame: MECH
senses:
  vision: false
footprint: [1, 1]
volatile: nt_plasma_blast_medium
---

# Battery Rack

A neutral HAZARD: destroyed by any damage, it throws `nt_plasma_blast_medium` where it stood after that
emission's own fuse. Rules and the science behind it:
[environmental-pieces](../../../systems/combat/environmental-pieces.md).
