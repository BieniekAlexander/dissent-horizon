---
kind: unit
id: supply_truck
title: supply_truck
scene: res://scenes/entities/units/cl/supply_truck.tscn
cost: {ore: 600}
build_time: 25
requires: []
hp: 500
armour: MEDIUM
frame: METALLIC
vision: 5
aggro: 2
movement: {mode: GROUNDED_DIRECT, speed: 1.8, turn_rate: 720}
builds: [settlement, power_plant, barracks, internment_camp, sam, cannon]
ui: {label: Supply Truck, grid: [0, 2], factions: [collective]}
---

# Supply Truck

Built at the [[settlement|Colony]].

- armored builder
- repairs
- Collects POWs for dominion
