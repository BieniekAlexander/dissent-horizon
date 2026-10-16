---
kind: Entity
title: Power Cell
scene: res://scenes/entities/tokens/nt/nt_powerCell.tscn
editor_description: Neutral hazard — destroy it and it blows.
commandable: false
flavor:
  description: A portable superconducting storage cell. Shoot it and it quenches into a plasma burst.
  verbose: "A man-portable storage cell: a superconducting coil holding a charge, swapped out when spent. Breach it and the coil quenches — the stored field dumps as an arc that boils the cell's contents into a small plasma burst. The next cell along goes with it."
defense:
  hp: 50
  armour: LIGHT
  frame: MECH
senses:
  vision: false
volatile: nt_plasma_blast_small
---

# Power Cell

A neutral HAZARD: destroyed by any damage, it throws `nt_plasma_blast_small` where it stood after that
emission's own fuse. Rules and the science behind it:
[environmental-pieces](../../../systems/combat/environmental-pieces.md).
