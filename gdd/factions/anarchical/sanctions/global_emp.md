---
kind: AbilityDefinition
title: Global EMP
ui: {grid: [1, 2], factions: [anarchists]}
hud_button: true
column: 2
levels:
  - title: Global EMP
    tier: 3
    cost: 1500
    cooldown: 60
    description: Stuns every machine on the map for five seconds — yours included. Your infantry does not care, which is the point.
    verbose: |
      Fires the moment you press it: there is nowhere to point a map-wide effect, so it
      is never armed and never waits on a click.

      It catches YOUR machines too. That asymmetry is the mechanic rather than an
      oversight — an EMP only takes hold on a mechanical frame, and the Anarchists field
      infantry, so they pay almost nothing to fire it while a vehicle-heavy opponent
      stops dead. Sparing your own vehicles would erase the only real cost of fielding
      them as this faction.
    needs_vision: false
    needs_target: false
---
# Global EMP

## Mechanic
Applies a MECH-only stun to **every unit on the map**, both sides included, for a fixed
duration. Biological units are unaffected. Structures are not caught — widening it to
buildings would silence turrets and production at once.

## Targeting
None. `needs_target: false` — pressing the button IS the deployment, and the fog gate
does not apply because there is no point to check.
