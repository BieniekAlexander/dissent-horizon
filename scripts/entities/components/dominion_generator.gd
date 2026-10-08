class_name DominionGenerator
extends Node

## Generates dominion for the owning commander at a fixed tick rate. Attach as
## a child of a Actor that should contribute dominion over time.

#region Properties
@export var dominion_rate: int = 10
static var TICK_RATE := 5 * TimeUtils.ticks_per_second()
## Physics ticks since the last payout. PUBLIC because a caller may wind the cycle
## forward — which is how a test reaches a payout without running TICK_RATE frames.
var ticks_elapsed: int = 0
var build_up: int = 0
var build_up_max: int = 10
#endregion


#region Public API
func tick() -> void:
	ticks_elapsed += 1
	if ticks_elapsed == TICK_RATE:
		var commandable := get_parent() as Actor
		commandable.commander.add_dominion(dominion_rate)
		ticks_elapsed = 0
		build_up += 1


## How many things are feeding this generator right now, or NO_ATTRIBUTION when the
## question doesn't apply. The economy readout shows it beside the dominion rate, because
## a rate that explains itself ("+3/s · 6 captives") is worth far more than a bare one.
##
## The variation here is per-FACTION, and it lives on the generator subclass rather than on
## Faction because that is where the mechanic already differs: the Colonial camp counts
## prisoners (see OccupantDominionGenerator), an Anarchical warlord would count the units
## inside its dominion range. The base generator awards a FLAT rate with nothing feeding
## it, so it has no contributors to name and returns NO_ATTRIBUTION.
##
## A faction whose dominion is event-driven rather than per-tick — damage dealt to
## structures, say — owns no DominionGenerator at all, so it reports no rate and no count
## and needs no special case here. See Commander.dominion_source_count.
const NO_ATTRIBUTION: int = -1


func contributor_count() -> int:
	return NO_ATTRIBUTION


## What this generator would pay THIS CYCLE — the figure its info card carries.
##
## Asked rather than derived by the HUD, because the answer differs by subclass in the same
## way `tick` does: a flat generator pays its rate, and a per-occupant one pays per head. One
## method, so the card and the payout cannot disagree about the number.
func payout() -> int:
	return dominion_rate
#endregion
