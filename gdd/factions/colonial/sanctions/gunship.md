---
kind: AbilityDefinition
title: Gunship
ui: {grid: [0, 2], factions: [colonial]}
hud_button: true
column: 1
levels:
  - title: Gunship
    tier: 2
    cost: 750
    cooldown: 60
    description: Calls a {{ cl_aircraftMedium_gunship }} to hold station over the target point for 20 seconds, firing on anything it finds.
    verbose: |
      The gunship flies in from your side of the board with its guns cold, circles the point
      you clicked, and opens fire on whatever comes into reach. While it is on station you may
      order it to attack a target, but not to go anywhere else. When its time is up it flies
      home the way it came.

      It is a real aircraft on the anti-air layer the whole time: shoot it down and the strike
      is over.
---
# Gunship

Sits in the Scan column WITHOUT continuing it: it is a separate sanction doc that happens
to share the column, which is layout rather than a dependency. That is why it has no
parent and does not supersede Scan 3.

## Mechanic
An **off-map ability**: a [[cl_aircraftMedium_gunship]] flies a sortie over the target point —
in from beyond the perimeter nearest the caster with its weapon disabled, on station for 20
seconds with its weapon live, then back out past its entry point, where it despawns. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md) §Gunship.

On station it acquires targets on its own and takes the player's Attack orders, but never a
move: the station is what was paid for.
