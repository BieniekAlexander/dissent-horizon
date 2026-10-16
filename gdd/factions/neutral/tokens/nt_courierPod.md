---
kind: Entity
title: Courier Pod
scene: res://scenes/entities/tokens/nt/nt_courierPod.tscn
editor_description: Neutral pickup — a charge of an ordnance (a Mortar Strike by default; authored per instance).
flavor:
  description: A downed courier capsule with its dispatch intact. Recover it and command sends support.
  verbose: A drop capsule that came down wrong, its sealed dispatch still inside. Recovering it earns the favour of whoever sent it — a charge of an ordnance, authored on the map where the pod lies, ready to use once.
pickup: {ability: mortar, charges: 1}
---

# Courier Pod

A neutral PICKUP granting ORDNANCE charges into the collector's depot. `mortar` (a Mortar Strike) is the
authored default; a mission overrides `Pickup.ability` on the placed instance, so what a pod
grants is a map decision and never the piece's. Rules:
[environmental-pieces](../../../systems/combat/environmental-pieces.md) §Pickups.
