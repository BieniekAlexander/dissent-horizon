---
kind: StatusEffect
title: burning
scene: res://scenes/entities/status_effects/burning.tscn
---

# Burning

A structure on fire: a damage-over-time on FIXTURES only (`host_filter`), lit by a plasma
blast and put out by a repair (`ends_on_heal`). Rules:
[environmental-pieces](../../../systems/combat/environmental-pieces.md) §Hazards. Registration
only — the tuning lives in the scene.
