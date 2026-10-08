---
kind: AbilityDefinition
title: Beacon Drop
flavor:
  description: potato
  verbose: potato
ui: {grid: [1, 1], factions: [colonial]}
hud_button: true
column: 3
levels:
  - title: Beacon
    tier: 1
    cost: 350
    cooldown: 60
    description: Places a firing solution on the ground you can see. Any {{ cl_defense_antiStructure }} can then shell it from anywhere on the map, until a shell spends it.
    verbose: |
      The artillery's reach without the walk. A {{ cl_bioLight_antiLight }} can call a
      solution in for free, but it has to get there, hold still for three seconds and stay
      until the shot is fired; this puts one wherever you can see, immediately.

      It stands until a shell spends it, so it can be placed before the guns are ready.
      It is stealthed, and it does not see: once your eyes leave the spot it marks blind
      ground — still yours to shell, but you will not see what walks onto it. An enemy
      that finds it can repair it away.
---
# Beacon Drop

## Mechanic
Places a `Beacon` on the ground at the target point, owned by the calling commander — the
same entity a `cl_bioLight_antiLight` calls in with its Spot ability, so the Bombards never
need to know which put it there.

- **Ground only.** Aimed over a unit, the drop lands on the ground under the cursor; it never
  rides on the unit, which is Spot's alone.
- **Aimed only where you can see.** The ordinary sanction vision gate.
- **Stands until spent.** No clock. A beacon is **spent by the first bombardment that uses
  it**; ground already inside a permanent beacon range is preferred over a beacon, so a free
  solution never burns one.
- **Blind.** It has no vision of its own, and a Bombard may fire on it whether or not the
  ground around it is still in view.
- **Stealthed**, and an enemy repairer that can see it repairs it away on first touch.
