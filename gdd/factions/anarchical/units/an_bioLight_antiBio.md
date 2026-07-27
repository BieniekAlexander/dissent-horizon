---
kind: Entity
title: Sharpshooter
scene: res://scenes/entities/units/an/an_bioLight_antiBio.tscn
build:
  cost: {energy: 750}
  time: 30
  requires: [an_tech1]
defense:
  hp: 90
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
ui: {grid: [2, 1], factions: [anarchists]}
---
TODO Give this unit a Deploy command. The generic Deploy/Undeploy command is built ([deploying](../../../systems/commands/deploying.md)); what is left for this unit is its `deploys:` key and the weapon rule below, which is not built (and 15 is no reach bucket). "Deploy" can be a generic command type, as it will be applicable for multiple units, but the effects of the "Deploy" command will need to differ the different applicable units. Note that the "deploy" behavior should take some pre-established duration of time, during which it must be stationary (for this unit, set it to 3 seconds). When units are deployed, they should also be able to un-deploy, and maybe the duration can differ (for this, set it to 1 second). This will be like a command like "evacuate" which is not applicable to all units, but is applicable to many different units across factions.
There will need to be a slight complexity here, given that "deploy" and "undeploy" are sort of separate behaviors. For example, if two units are selected, and one is "deployed" an the other is "undeployed", and I use the "deploy" command, what happens? In general, it should be as follows - the UI and the default behavior of the command depend on the selection:
	- If any units are undeployed, the command should behave as a "deploy" for the undeployed units (and a no-op for the remaining units)
	- If all units are deployed, the command should behave as an undeploy for all units
Assuming it's not taken, please put this Deploy/Undeploy button in the command grid position for Z.
The behavior for the Sharpshooter will be as follows:
- immobile while deployed
- Has a weapon (15 range, 3 second split time, 100 damage, LEAD), but the weapon is only usable while in a deployed state

