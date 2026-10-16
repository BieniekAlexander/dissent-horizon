---
kind: Entity
title: Fuel Cartridge
scene: res://scenes/entities/tokens/nt/nt_fuelCartridge.tscn
editor_description: Neutral pickup — the first ground unit over it collects 500 energy.
flavor:
  description: A deuterium cartridge. Walk a unit over it for 500 energy.
  verbose: Fusion fuel bound into a metal hydride bed — the form it is stored in precisely so it cannot explode. Shoot it and it leaks; drive over it and it is yours.
pickup: {energy: 500}
---

# Fuel Cartridge

A neutral PICKUP: a coin, collected by the first ground unit of any commander whose hull
reaches it. Rules: [environmental-pieces](../../../systems/combat/environmental-pieces.md)
§Pickups.
