---
kind: Entity
title: Fuel Cache
scene: res://scenes/entities/tokens/nt/nt_fuelCache.tscn
editor_description: Neutral pickup — the first ground unit over it collects 2000 energy.
flavor:
  description: A pallet of deuterium cartridges. Walk a unit over it for 2000 energy.
  verbose: A depot's worth of hydride cartridges on one pallet. Inert, like every cartridge, and worth a small structure to whoever gets a unit onto it first.
pickup: {energy: 2000}
---

# Fuel Cache

A neutral PICKUP: a coin, collected by the first ground unit of any commander whose hull
reaches it. Rules: [environmental-pieces](../../../systems/combat/environmental-pieces.md)
§Pickups.
