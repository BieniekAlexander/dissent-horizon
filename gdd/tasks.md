# Bugs
- when units are issued a command against a structure (e.g. garrison, interact, etc.), it appears that the units generally try to navigate to the position on the navmesh "above" the structure. They should be navigating to the point on the navmesh near the structure that is closest to them
- if my cursor is trying to evaluate something related to position, and my cursor is off of the navmesh, the game crashes because of an out-of-bounds error. Rather than throwing a bounds error, just return some sentinel value or NULL, and provide some "invalid command" state
```
  E 0:01:27:908   Map.grid_to_world: Out of bounds get index '904' (on base: 'PackedFloat32Array')
  <GDScript Source>map.gd:65 @ Map.grid_to_world()
  <Stack Trace> map.gd:65 @ grid_to_world()
                rts_controller.gd:633 @ _update_build_preview()
                rts_controller.gd:144 @ _process()

```
- Some of my units are collecting an attack command, even when it already has an active Move `Command`. Aggro should be evaluated during an AttackMove command, but not a  `Command`. Retargeting during a plain move `Command` might happen for a CPU Bot that is changing the decisions of the units, but there should be no command override logic for commands in-and-of-themselves unless specifically implemented in an `get_updated_state` override
	- Maybe for semantic clarity, rename Command to MoveCommand
- Upon Skirmish startup, it appears that structures and units are being spawned at the same position, and units are being spawned inside structures. To address this, spawn all structures first, and then add units in afterwards, only positioning units on the remaining available navmesh space. There should already be utility functions implemented elsewhere that support the spawning of units onto the navmesh.
# Mechanics
## Rally Points
- I recall that structures which produce units have a feature that, if they receive a Move `Command`, the command is interpreted as an assignment of a rallypoint for the units trained. Structures with the `garrison` component should have the same sort of logic, where a move command issued to it should direct units to go in that direction if they're given the `Evacuate` command. I think, in summary, here's what the implementation should look like:
	- Consider that commandables might have features which produce units from it - wrap this detail in a check, `can_rally`, which will be true in the cases that:
		- The unit has a garrison, which is to say that units can occupy it
		- The unit might be able to produce other units
		- The commandable might produce commandables in response to events, such as its own death
	- In these cases, there should be some sort of logic that gives the produced or released units a destination to move towards:
		- produce units and give them a rally point
		- If a unit dies and produces units, they can inherit the movement command of its source unit
	- In the event that the source unit can move, the produced units can just inherit move commands. However, in the case that the unit cannot move (i.e. it's a structure), it should hold onto a `rally_point`, which is used to give released units an initial movement destination
# Ordnances
I'll define some ordnances that I want to be implemented - just set them to cost 100 dominion, 30 second cooldown, and without any ordnance dependencies. I'll modify those details myself.
## Anarchical
- Dignify - select a target irregular to be turned into a Warlord
	- the promoted unit should maintain its veterancy
- Informant - give an irregular stealth
## Colonial
- Promote - give one veterancy level to a unit
- Radar Scan - unlocks an ability that allows you to temporarily reveal a portion of the map
	- implementation-wise, execute an event that spawns an invisible Entity at a specified location, assigned to the commander, with a lifespan of some 15 seconds. For ease of implementation, it might be easiest if it's programmed using a projectile with zero speed, though I don't recall if such entities will properly have their line of sight handled
# Interface
Updates need to be made to make the game controls and visuals always be subject to the fog of war:
- Visuals
	- Currently, units are only visible when they are not in vision range of one of the commander's units, which is correct
	- There should be slightly different logic governing the visibility of structures. Given that structures are basically locked to the terrain grid, it would make sense for the structure to be visible while still under a previously explored portion of the fog of war. However, the true state of the structure might change while under the fog of war (the structure might be destroyed, somehow moved, etc.). So, the implementation should be as follows:
		- Each commander should have some sort of construct which stores the locations of units that were already seen. A blackboard was previously implemented for Bot behavior, and it would make sense to reuse this blackboard for this task. Some aspects of the blackboard implementation will still be specific to the Bot decision-making, but some aspects will be general to commanders (i.e. including the ones controlled by players, without any sort of AI logic being used), so move the BotBlackboard class to instead be a CommanderBlackboard, which is governed by the Commander.
		- The blackboard detects the presence of structures. For each previously seen structure, the blackboard will need to create a visual clone of the structure. (I'll refer to this as a visual clone for now, but if a better name for this concept exists, opt for that - this pattern is surely a well-defined pattern for RTS games):
			- The visual clone should be mapped to its counterpart in some way, so that the visualization of the clone can be reconciled with its real counterpart
			- The visual clone need only copy the sprite of its counterpart. If the actual structure has already been seen by the player, then the clone should be visible if and only if the actual structure is not currently visible to the player
			- If the counterpart structure ever changes position or gets destroyed, then the clone should stay active as a visualization until the player regains visibility of the structure location. When running this check to reconcile the clone with the real structure, the cases are:
				- If the structure was not destroyed, then the clone stays defined, for visualization purposes
				- If the structure was destroyed or moved, then the clone is now not representative of what the commander is aware of, so it can be deleted
				- Note: It's possible that a real structure might have multiple clones - consider the case where:
					- a commander sees a structure
					- the structure moves to another location
					- the commander sees the same structure, but it's now in a different location
					- Given that the commander may not know that the second structure happens to be the same structure as the first structure (they would not know that the structure had moved and it is, in fact, the same one) the blackboard should have two visual clones representing the same structure
					- As such, the visual clone effectively represents a given structure at a given terrain_grid coordinate, and so multiple visual clones could refer to the same structure, albeit at different coordinates
- Controls
	- When processing the target handling of the RTS Controller, the assignment of an entity as the target of the action should be gated by whether the commander can actually see the target. For example, if I have units selected, and my mouse is hovering over an enemy unit, the current implementation works as follows:
		- My mouse detects that it's hovering over enemy units, and so the target of the next command is set to the enemy unit
		- Given that I've selected units and my command target is an enemy unit, the command to be registered will be an attack command (in the default controller context)
	- However, I need the controller to only "detect" the enemy unit if the unit is actually in vision range:
		- If the unit is in vision range, the command should be interpreted as explained above
		- If the unit is not in vision range, the mouse should not detect the unit under the cursor, so the target of the command will then just be a position on the terrain grid, and the selected command will be a move `Command`
		- Note: even with the previously described "visual clone" of a structure, the visual clone will not actually have the `SELECTION` collision shape, and so even if the user sees that their mouse is hovering over what appears to be a structure, there's no guarantee that the displayed sprite is representing a structure at that position. The visual clone will be present if and only if the fog of war is active at that location, which means that the counterpart structure will not be visible, and so as described here, the mouse should not detect the structure under the cursor because the actual structure is not visible
	- When selecting multiple units at once with the "box select" (involving dragging a box around a group of units) - if any non-structure commandables are selected, then structure commandables should be skipped from the selection