---
kind: AbilityDefinition
title: Dignify
ui: {grid: [0, 0], factions: [anarchists]}
hud_button: true
column: 0
levels:
  - title: Dignify
    tier: 0
    cost: 100
    cooldown: 30
    description: Promotes a clicked {{ an_bioLight_builder }} into a {{ an_bioMedium_dominionGen }}, keeping the veterancy it has already earned.
    verbose: |
      A transformation, not a purchase: the Irregular is consumed and the Warlord stands
      in its place at the same spot, carrying its rank across.

      Its STANDING ORDERS come across too, as far as the new piece can carry them. The
      queue is walked and truncated at the first command a Warlord cannot perform — a
      Warlord cannot build, so an Irregular told to raise a redoubt and then hold a hill
      keeps neither order, since the second was given expecting the first to have happened.
---
# Dignify

## Mechanic
Replaces the target `an_bioLight_builder` with an `an_bioMedium_dominionGen` at the same position, for the
same commander, preserving its veterancy level.

## Command queue
The old unit's command chain is carried to the new one, TRUNCATED at the first command
the new piece is incapable of. Capability is a question about components, not about
whether the command could succeed right now.

## Targeting
Friendly `an_bioLight_builder` only.
