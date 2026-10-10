---
kind: AbilityDefinition
title: Gunship
flavor:
  description: potato
  verbose: potato
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
  - title: Gunship 2
    tier: 3
    cost: 1000
    cooldown: 60
    description: Calls a {{ cl_aircraftMedium_gunship2 }} to hold station over the target point for 20 seconds, firing on anything it finds. Replaces Gunship.
    verbose: |
      The same sortie with a different gun. Everything else about it — the run in, the 20
      seconds on station, the Attack orders, the run home — is level 1's.
---
# Gunship

Sits in the Scan column WITHOUT continuing it: it is a separate sanction doc that happens
to share the column, which is layout rather than a dependency. That is why it has no
parent and does not supersede Scan 3.

## Progression
Gunship 2 replaces Gunship: the same sortie (`EventGunship`, 20 s on station) flying
[[cl_aircraftMedium_gunship2]], whose only difference is its weapon — a placeholder copy of the
Constable's. Each level is its own event scene, because the flown piece is the event's
`gunship_scene` (`sanction_gunship.tscn`, `sanction_gunship_2.tscn`).

TODO: Gunship 2's tier (T4, `tier: 3`, the next row down) and price (1000, the bottom of the T4
band) were chosen by Claude 2026-10-10, not by Alex; the request named only the weapon.

## Mechanic
An **off-map ability**: a [[cl_aircraftMedium_gunship]] flies a sortie over the target point —
in from beyond the perimeter nearest the caster with its weapon disabled, on station for 20
seconds with its weapon live, then back out past its entry point, where it despawns. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md) §Gunship.

On station it acquires targets on its own and takes the player's Attack orders, but never a
move: the station is what was paid for.
