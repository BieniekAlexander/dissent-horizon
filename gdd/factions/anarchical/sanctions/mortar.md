---
kind: AbilityDefinition
title: Mortar Strike
ui: {grid: [1, 1], factions: [anarchists]}
hud_button: true
column: 3
levels:
  - title: Mortar 1
    tier: 1
    cost: 500
    cooldown: 60
    description: 'Four shells lob in from off the map onto the target point.'
    verbose: |
      Called in rather than fired: the shells come over the map edge nearest the
      Distress Signal that called them, so where you build the caster decides which
      side the barrage arrives from.
      The muzzles are scattered; the aim is not. Every shell converges on the point
      you clicked.
  - title: Mortar 2
    tier: 2
    cost: 500
    cooldown: 60
    description: 'Eight shells lob in from off the map onto the target point, replacing Mortar 1.'
    verbose: |
      Twice the barrage, same arrival and same aim point. Replaces Mortar 1 outright —
      a column is one sanction you improve, not a growing collection.
  - title: Mortar 3
    tier: 3
    cost: 500
    cooldown: 60
    description: 'Sixteen shells lob in from off the map onto the target point, replacing Mortar 2.'
    verbose: |
      The heaviest barrage the Anarchists can call down, and the reason to take the
      Mortar column to its end.
---
# Mortar Strike

## Mechanic
An **off-map ability**: the shells are not fired by the caster. They enter from beyond the
play-area perimeter nearest the caster and fly a normal ballistic arc onto the target
point. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md)
for how that origin is derived and why it keys off the caster rather than the target.

Each shell's launch point is scattered around that single origin, so a heavy barrage
arrives as sixteen separate arcs rather than one thick line. The AIM is not scattered:
every shell is launched at the same point, and the barrage converges.

The shell is the Colonial Bombard's (`cannon_shell`) — a stand-in until the Anarchists
have one of their own.

## Progression
4 → 8 → 16 shells. The tiers differ by `shell_count` on the event scene and by nothing
else; all three are one `EventMortarBarrage`.
