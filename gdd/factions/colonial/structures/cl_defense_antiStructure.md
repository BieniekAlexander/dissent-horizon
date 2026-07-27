---
kind: Entity
title: Bombard
scene: res://scenes/entities/structures/cl/cl_defense_antiStructure.tscn
build:
  cost:
    energy: 1000
  time: 30
  requires:
    - cl_tech1
defense:
  hp: 750
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
abilities:
  - cooldown: 5
    grants:
      - bombard
beacon: 20
infrastructure: -75
ui:
  grid:
    - 4
    - 0
  factions:
    - colonial
---

# Bombard

The foundation of the Colonial **bombardment system**: a siege gun whose range is not
distance but VISION BY PROXY.

## No weapon, no aggro
The Bombard has **no `weapons:` block and `aggro: 0`**. It never picks its own targets and
never fires on its own — every shot is a deliberate `command_bombard` order at a point the
player chose. A `Weapon` would have brought an AttackRange, an aggro pickup and automatic
firing with it, and all three are wrong for this piece, which is why the capability is an
ABILITY (see `bombard`) rather than a weapon.
## Reach
**Global.** It can drop a shell anywhere on the map, provided its side is SPOTTING the
spot — which happens two ways (see `BombardTargeting`):

- a **beacon**, placed by a `cl_bioLight_antiLight` using its Spot ability or by the
  Beacon Drop sanction. Spent by the shot that uses it.
- a **beacon range**, the persistent bubble carried here (radius 20) and by
  `cl_aircraftStrong_support` (radius 5). Never spent.

Ground inside a permanent range is preferred over a beacon, so a free solution never
burns one the player walked a Recruit across the map to place.

## Notes
- The shell it throws is `cannon_shell`, which keeps a name the gun itself no longer carries.
- The 5-second reload is the old weapon's, now a charge pool on the gun: one charge, five
  seconds to regain it. It is authored here rather than on the ability because the pool
  belongs to the piece holding it.
