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
    description: Freezes one of YOUR units for 15 seconds — it can take no action at all, but its armour rises a step while it stands there. A way to save something about to die.
    verbose: |
      Cryogenics cut both ways: a frozen unit is helpless and tougher at the same time.
      Freezing your own unit trades everything it could have done for a step of armour,
      which is how you carry something through a barrage it would not otherwise survive.

      Units already at STRONG armour cannot be frozen — there is no step above it, so
      they would take the immobilisation with none of the protection. Structures cannot
      be frozen either.
  - title: Freeze 2
    tier: 1
    cost: 300
    cooldown: 60
    description: Freezes any unit for 15 seconds — friendly or hostile. It can take no action, and its armour rises a step. Replaces Freeze 1. Strong armour cannot be frozen.
    verbose: |
      The same effect, now aimable at anyone. On an enemy it is a hard removal from the
      fight for 15 seconds; the armour step it also grants them is the cost of using it
      offensively, so it takes a unit out of a fight rather than setting one up to die.
---
# Freeze

## Mechanic
Applies a cryogenic freeze for 15 seconds. While frozen a unit:

- can take **no action at all** — it does not move, shoot, build or respond to orders
- has its **armour class raised one step** (`LIGHT` → `MEDIUM`, `MEDIUM` → `STRONG`)

## Eligibility
- Units at `STRONG` armour **cannot be frozen** — there is no step above it.
- **Structures cannot be frozen** — a building has no actions to stop, so it would be a
  pure armour buff.

An ineligible unit is never targeted: the armed cursor only marks a unit that can actually be
frozen (see `gdd/systems/macroeconomics/sanctions/payloads.md`).

## Progression
Freeze 1 is friendly-only (a defensive save); Freeze 2 widens the target to anyone.

Blizzard is NOT a level of this family: it shares the column but is cast from a different
building (`cl_support3`), and sharing a column is layout rather than a dependency — see
`blizzard.md`. Buying Blizzard therefore does not retire Freeze.
