---
kind: AbilityDefinition
title: Bombard
flavor:
  description: Drop a shell anywhere on the map your side is spotting.
  verbose: |
    Range is unlimited; what limits it is VISION BY PROXY. The shot may be aimed at any
    point one of your pieces is currently spotting, so the gun is worth nothing on its
    own and everything beside a spotter.
    
    A beacon marks a point once and is spent by the shot that uses it; a Bombard's own
    surroundings and a Reverence's are marked permanently and cost nothing. Spotted
    ground inside a permanent range is preferred, so a free solution never burns a
    beacon a Recruit was walked across the map to place.
ui: {grid: [0, 0], active_grid: [2, 0], factions: [colonial]}
hud_button: true
command: command_bombard
emits: res://scenes/entities/projectiles/cl/cannon_shell.tscn
---

# Bombard

## Not a sanction
Unlocked by nothing: a commander that owns the gun owns the ability. "Sanction" now
means one thing — unlocked with dominion, through the sanction grid — and this is the
worked example of an ability that is not one.

## The HUD button
`hud_button: true`, because the reach is global. The button selects every battery that
can fire and arms `command_bombard`, leaving the player one right-click from the shot;
without it the only way to fire is to find the gun on the map first, which a global-range
weapon should not require.

## Charges
One pool of one charge, five seconds, authored on the gun itself
(`cl_defense_antiStructure`'s `abilities:`) rather than here — the pool belongs to the
piece holding it, so a second battery is a second shot rather than a faster one.

## The shell
`emits:` names the projectile thrown per use. It is a scene path rather than a piece id
because `cannon_shell` has no doc of its own yet.
