---
kind: Entity
title: Activation Cask
scene: res://scenes/entities/tokens/nt/nt_activationCask.tscn
editor_description: Neutral hazard — destroy it and it blows.
commandable: false
flavor:
  description: A shielded cask of spent reactor internals. Breach it and the ground stays hot for a long while.
  verbose: A reactor's neutrons activate its own first wall; the spent internals go into shielded casks to decay. Break one open and the scattered debris irradiates everything near it, organic or mechanical, long after the breach.
defense:
  hp: 300
  armour: STRONG
  frame: MECH
senses:
  vision: false
volatile: nt_radiation_field
---

# Activation Cask

A neutral HAZARD: destroyed by any damage, it throws `nt_radiation_field` where it stood after that
emission's own fuse. Rules and the science behind it:
[environmental-pieces](../../../systems/combat/environmental-pieces.md).
