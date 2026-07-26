---
kind: unit
id: chinook
title: chinook
scene: res://scenes/entities/units/an/chinook.tscn
cost: {ore: 350}
build_time: 25
requires: [hangar]
hp: 220
armour: LIGHT
frame: METALLIC
vision: 7
aggro: 4
movement: {mode: HOVERING, speed: 2.4, turn_rate: 720}
ui: {label: Chinook, grid: [3, 0], factions: [anarchists]}
---

# Chinook

Trained at the [[hangar|Hangar]].

- transport chopper
- stealth

Ferries infantry over terrain the ground game can't cross. Garrison capacity and
stealth are hand-wired in the scene (not yet doc-governed).
