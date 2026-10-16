---
kind: Entity
title: Cryo Dewar
scene: res://scenes/entities/tokens/nt/nt_cryoDewar.tscn
editor_description: Neutral hazard — destroy it and it blows.
commandable: false
flavor:
  description: A cryogen coolant dewar. Rupture it and the cold cloud freezes whatever stands in it.
  verbose: Liquid coolant for a storage cell's superconducting coils — the same cryogenics the Colonials build weapons from. A breach flashes it to gas: a pressure burst, then a dense cold cloud that hugs the ground and freezes the units in it. Structures shrug it off.
defense:
  hp: 150
  armour: LIGHT
  frame: MECH
senses:
  vision: false
volatile: nt_cryo_burst
---

# Cryo Dewar

A neutral HAZARD: destroyed by any damage, it throws `nt_cryo_burst` where it stood after that
emission's own fuse. Rules and the science behind it:
[environmental-pieces](../../../systems/combat/environmental-pieces.md).
