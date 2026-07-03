# Bugs
# Mechanics
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