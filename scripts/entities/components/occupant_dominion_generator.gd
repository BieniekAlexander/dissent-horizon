class_name OccupantDominionGenerator
extends DominionGenerator

## Generates dominion scaled by how many units the owning entity is holding in its
## Garrison — `dominion_per_unit` for each occupant, once per tick cycle. The
## Compound uses this: each imprisoned unit contributes dominion every cycle.
##
## Counts OCCUPANTS, not occupancy size: a prisoner is worth the same however bulky it
## is, so a large captive filling two of the camp's slots still banks one unit's worth.
##
## Subclasses DominionGenerator and is named "DominionGenerator" in the scene so
## Commandable's existing `dominion_generator` hook ticks it with no extra wiring.

#region Properties
## Dominion awarded per held unit, per TICK_RATE cycle (every 5 seconds).
@export var dominion_per_unit: int = 5
#endregion

#region Public API
## Overrides DominionGenerator.tick: award per-prisoner dominion each cycle instead
## of a flat rate. No-op cycles when the garrison is empty.
func tick() -> void:
	ticks_elapsed += 1
	if ticks_elapsed < TICK_RATE:
		return
	ticks_elapsed = 0
	var parent := get_parent() as Entity
	if parent == null or parent.commander == null:
		return
	var garrison: Garrison = parent.get_node_or_null("Garrison") as Garrison
	var held: int = garrison.garrisoned_count() if garrison != null else 0
	if held > 0:
		parent.commander.add_dominion(dominion_per_unit * held)
		build_up += 1

## Per HEAD, matching what tick() actually pays out.
func payout() -> int:
	return dominion_per_unit * contributor_count()


## The prisoners this camp is holding — what the Colonial dominion rate is made OF, so the
## economy readout can say "+3/s · 6 captives" rather than just "+3/s". Head count, matching
## what tick() actually pays out (a bulky captive is worth one prisoner, not two).
func contributor_count() -> int:
	var parent := get_parent() as Entity
	if parent == null:
		return 0
	var garrison: Garrison = parent.get_node_or_null("Garrison") as Garrison
	return garrison.garrisoned_count() if garrison != null else 0
#endregion
