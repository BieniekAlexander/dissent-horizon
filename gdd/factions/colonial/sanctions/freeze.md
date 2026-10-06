---
kind: AbilityDefinition
title: Freeze
ui: {grid: [3, 0], factions: [colonial]}
hud_button: true
column: 2
levels:
  - title: Freeze 1
    tier: 0
    cost: 125
    cooldown: 60
    description: Freezes one of YOUR pieces for 10 seconds — it can take no action at all, but 150 points of STRONG ice take damage before it does. A way to save something about to die.
    verbose: |
      Cryogenics cut both ways: a frozen piece is helpless and shielded at the same time.
      Freezing your own unit or building trades everything it could have done for a coat
      of ice, which is how you carry something through a barrage it would not otherwise
      survive. Break the ice and the freeze ends.

      Pieces with STRONG armour cannot be frozen.
  - title: Freeze 2
    tier: 1
    cost: 300
    cooldown: 60
    description: Freezes any piece for 10 seconds — friendly or hostile. It can take no action, and 150 points of STRONG ice take damage first. Replaces Freeze 1. Strong armour cannot be frozen.
    verbose: |
      The same effect, now aimable at anyone. On an enemy it is a hard removal from the
      fight for 10 seconds; the ice it also grants them is the cost of using it offensively,
      so it takes a piece out of a fight rather than setting one up to die.
---
# Freeze

## Mechanic
Applies the cryogenic freeze to the clicked unit or structure, immediately. The freeze, who
can take it, and its ice are [shields](../../../systems/combat/shields.md) §Freeze.

An ineligible piece is never targeted: the armed cursor only marks one that can actually be
frozen (see `gdd/systems/macroeconomics/sanctions/payloads.md`).

## Progression
Freeze 1 is friendly-only (a defensive save); Freeze 2 widens the target to anyone.

Blizzard is NOT a level of this family: it shares the column but is cast from a different
building (`cl_support3`), and sharing a column is layout rather than a dependency — see
`blizzard.md`. Buying Blizzard therefore does not retire Freeze.
