---
kind: ShapeLibrary
title: Shape library
# Every named cylinder and sphere that specs point at instead of carrying a radius of
# their own. Entry key = the id a spec names; `kind:` defaults to CylinderShape3D, and a
# cylinder with no `height:` is as tall as every other (SpecSceneSync.SHAPE_HEIGHT).
# Why buckets: gdd/systems/combat/range-buckets.md
shapes:
  # Weapon reach, ground targets
  ground_range_melee:     {radius: 0.5}
  ground_range_short:     {radius: 2.5}
  ground_range_medium:    {radius: 8}
  ground_range_long:      {radius: 12}
  ground_range_artillery: {radius: 20}  # meant to stay inside structure vision
  ground_range_siege:     {radius: 24}  # meant to out-range structure vision
  # Weapon reach, air targets
  air_range_melee: {radius: 0.5}
  air_range_short: {radius: 6}
  air_range_long:  {radius: 12}
  air_range_siege: {radius: 18}
  # Vision
  vision_aerial_medium: {radius: 18}  # flying units
  vision_aerial_large:  {radius: 22}  # hovering units
  vision_ground_small:  {radius: 16}  # infantry
  vision_ground_medium: {radius: 20}  # vehicles, small structures
  vision_ground_large:  {radius: 24}  # structures
  vision_ground_huge:   {radius: 30}  # command centres
  # Stealth detection
  detection_small:  {radius: 8}  # every BIO unit
  detection_medium: {radius: 16}  # low-investment detectors
  detection_large:  {radius: 24}  # high-investment dedicated detectors
  # Area of effect
  aoe_tiny:   {kind: SphereShape3D, radius: 0.25}
  aoe_small:  {kind: SphereShape3D, radius: 1}
  aoe_medium: {kind: SphereShape3D, radius: 2.5}
  aoe_large:  {radius: 5, height: 100}  # reaches aircraft
  aoe_charge: {kind: SphereShape3D, radius: 3}  # a Sapper's planted charge
---
# Shape library

The values above are the only place these radii are written down. Design notes explain
how the buckets relate to each other and link here rather than repeat the numbers:
[combat/range-buckets](../systems/combat/range-buckets.md).
