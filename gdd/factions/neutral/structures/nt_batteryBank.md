---
kind: Entity
title: Battery Bank
scene: res://scenes/entities/structures/nt/nt_batteryBank.tscn
editor_description: Neutral hazard — destroy it and it blows.
commandable: false
flavor:
  description: A settlement's battery bank — heavily shielded, and the biggest burst on the map.
  verbose: A settlement's whole stored charge in one shielded bank of racks. Its shielding takes a great deal of punishment, and when it finally quenches the plasma column reaches anything flying over it.
defense:
  hp: 250
  armour: STRONG
  frame: MECH
senses:
  vision: false
footprint: [2, 2]
volatile: nt_plasma_blast_large
---

# Battery Bank

A neutral HAZARD: destroyed by any damage, it throws `nt_plasma_blast_large` where it stood after that
emission's own fuse. Rules and the science behind it:
[environmental-pieces](../../../systems/combat/environmental-pieces.md).
