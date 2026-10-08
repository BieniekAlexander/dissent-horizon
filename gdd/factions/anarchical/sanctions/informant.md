---
kind: AbilityDefinition
title: Informant
flavor:
  description: potato
  verbose: potato
ui: {grid: [1, 0], factions: [anarchists]}
hud_button: true
column: 1
levels:
  - title: Informant 1
    tier: 0
    cost: 125
    cooldown: 30
    description: Grants a clicked {{ an_bioLight_builder }} permanent stealth, letting it move unseen until it attacks.
    verbose: |
      Stealth is permanent once granted — it is a property of the unit from then on, not
      a timed effect. The unit is revealed while it is inside an enemy detector's range,
      and forced fully visible for a few seconds after it attacks or is attacked.
  - title: Informant 2
    tier: 1
    cost: 250
    cooldown: 30
    description: Grants permanent stealth to any clicked friendly biological unit, replacing Informant 1.
    verbose: 'The same grant, now aimable at any of your biological units rather than Irregulars alone.'
  - title: Informant 3
    tier: 3
    cost: 1000
    cooldown: 30
    description: Grants permanent stealth to any clicked friendly unit, replacing Informant 2.
    verbose: 'Any unit you own, machines included.'
---
# Informant

## Mechanic
Attaches a permanent `Stealth` component to the target.

## Progression
Eligibility only — which of your units may receive it widens with the tier:
`an_bioLight_builder` → any friendly BIO unit → any friendly unit.

A unit that is already stealthed is excluded from the candidate search, so the click
falls through to one the sanction can act on.
