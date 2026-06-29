class_name InventoryDominionGenerator
extends DominionGenerator

## Generates dominion scaled by how many units the owning entity is holding in its
## Inventory — `dominion_per_unit` for each held unit, once per tick cycle. The
## internment camp uses this: each imprisoned unit contributes dominion every cycle.
##
## Subclasses DominionGenerator and is named "DominionGenerator" in the scene so
## Commandable's existing `dominion_generator` hook ticks it with no extra wiring.

#region Properties
## Dominion awarded per held unit, per TICK_RATE cycle (every 5 seconds).
@export var dominion_per_unit: int = 5
#endregion

#region Public API
## Overrides DominionGenerator.tick: award per-prisoner dominion each cycle instead
## of a flat rate. No-op cycles when the inventory is empty.
func tick() -> void:
	frame += 1
	if frame < TICK_RATE:
		return
	frame = 0
	var parent := get_parent() as Entity
	if parent == null or parent.commander == null:
		return
	var inventory: Inventory = parent.ability_inventory
	var held: int = inventory.item_count() if inventory != null else 0
	if held > 0:
		parent.commander.add_dominion(dominion_per_unit * held)
		build_up += 1
#endregion
