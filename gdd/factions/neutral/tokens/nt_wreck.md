---
kind: Entity
title: Wreck
scene: res://scenes/entities/tokens/nt/nt_wreck.tscn
editor_description: Neutral token — left where a grounded vehicle was destroyed; scavenged by Anarchist infantry.
flavor:
  description: What is left of a vehicle. Anarchist infantry can strip it for parts.
  verbose: A burnt-out hull, still worth something to anyone with a wrench and no scruples. It does not stay long before the fires and the recovery crews finish it off.
wreck: {lifespan: 30}
---

# Wreck

The token a destroyed GROUNDED VEHICLE leaves where it fell: neutral, uncommandable and
undamageable, standing for `wreck.lifespan` seconds. Armed Anarchist infantry scavenge it to
switch to their scavenged weapons, consuming it. Rules:
[scavenging](../../../systems/combat/scavenging.md).
