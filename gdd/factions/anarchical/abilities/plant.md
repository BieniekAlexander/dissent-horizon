---
kind: AbilityDefinition
title: Plant
flavor:
  description: Rig a charge on a point, a vehicle or a building.
  verbose: |
    The Sapper walks to the chosen point or piece and works on it — longer on a sturdier
    target — then leaves a charge there. On a vehicle or building (anyone's, as long as it is a
    machine) the charge rides with it; anywhere else it stands on the ground.

    One charge, and it does not come back while the one it planted is still in play.
command: command_plant
---
# Plant

The Sapper's ability — [planted-explosives](../../../systems/combat/planted-explosives.md). The
pool (one charge, 30 s) is authored on the Sapper; that it does not recharge while the planted
charge lives is the charge's doing (`Abilities.hold_recharge`), not a pool setting.
