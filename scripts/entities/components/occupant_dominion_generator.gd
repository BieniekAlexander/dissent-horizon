class_name OccupantDominionGenerator
extends DominionGenerator

## Generates dominion scaled by how many units the owning entity's Garrison is PAYING for —
## `dominion_per_unit` for each, once per tick cycle (Garrison.paying_count). The Compound uses
## this: it sentences one captive at a time, so the captive serving pays and the ones waiting
## their turn do not.
##
## Counts OCCUPANTS, not occupancy size: a prisoner is worth the same however bulky it
## is, so a large captive filling two of the camp's slots still banks one unit's worth.
##
## Subclasses DominionGenerator and is named "DominionGenerator" in the scene so
## Actor's existing `dominion_generator` hook ticks it with no extra wiring.

#region Properties
## Dominion awarded per paying occupant, per TICK_RATE cycle (every 5 seconds): 5/s, so a
## captive serving the Compound's 30 s sentence is worth 150. Set 2026-10-05 together with
## one-at-a-time sentencing, which puts the Colonial route at about the Technocratic Lab route's
## rate (gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §Colonial decision).
@export var dominion_per_unit: int = 25
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
	var held: int = garrison.paying_count() if garrison != null else 0
	if held > 0:
		parent.commander.add_dominion(dominion_per_unit * held)
		build_up += 1


## Per HEAD, matching what tick() actually pays out.
func payout() -> int:
	return dominion_per_unit * contributor_count()


## The prisoners this camp is paying for — what the Colonial dominion rate is made OF, so the
## economy readout can say "+5/s · 1 captive" rather than just "+5/s". Head count of the
## captives SERVING, matching what tick() actually pays out (a bulky captive is worth one
## prisoner, not two; a captive waiting its turn is worth nothing yet).
func contributor_count() -> int:
	var parent := get_parent() as Entity
	if parent == null:
		return 0
	var garrison: Garrison = parent.get_node_or_null("Garrison") as Garrison
	return garrison.paying_count() if garrison != null else 0
#endregion
