# Specifies what things are available to a commander
class_name TechnologySpec

#region Constants
enum UnmetNeed {
	NONE,
	NOT_ENOUGH_ORE,
	NOT_ENOUGH_VIGOR,
	NOT_ENOUGH_DOMINION,
	MISSING_STRUCTURE,
}

static var unmet_need_message_map: Dictionary = {
	UnmetNeed.NONE: "",
	UnmetNeed.NOT_ENOUGH_ORE: "Not enough ore",
	UnmetNeed.NOT_ENOUGH_VIGOR: "Not enough vigor",
	UnmetNeed.NOT_ENOUGH_DOMINION: "Not enough dominion",
	UnmetNeed.MISSING_STRUCTURE: "Required structure missing",
}
#endregion

#region Properties
var ore_cost: int
var dominion_cost: int
## Vigor surplus required to produce this (renamed from population_cost). Gates only
## when > 0 — a 0-cost item is never blocked, even when the commander is strained.
var vigor_cost: int
# Cached prerequisite state, refreshed by Commander.proc_technology against
# required_structures. Resource checks are layered on top in get_unmet_need,
# so this only reflects tech-prereq state.
var unmet_need: UnmetNeed = UnmetNeed.NONE
# Entity.Type values of the structures that must be built (ALL of them) before
# this tech is available. Empty = no structure prerequisite. Declarative data
# (not a callable) so it can be inspected/exported.
var required_structures: Array = []
var creation_time: int
#endregion

#region Lifecycle
func _init(
	a_ore_cost: int,
	a_vigor_cost: int,
	a_dominion_cost: int,
	a_creation_time: int,
	a_required_structures: Array = []
):
	ore_cost = a_ore_cost
	vigor_cost = a_vigor_cost
	dominion_cost = a_dominion_cost
	required_structures = a_required_structures
	creation_time = a_creation_time
	# A structure prerequisite is gated on world state we can't yet inspect (the
	# owning Commander hasn't built structure_type_map). Start pessimistic;
	# proc_technology will refine once a structure event fires.
	if not a_required_structures.is_empty():
		unmet_need = UnmetNeed.MISSING_STRUCTURE
#endregion

#region Public API
func get_unmet_need(a_commander: Commander) -> UnmetNeed:
	if unmet_need != UnmetNeed.NONE:
		return unmet_need
	if a_commander.ore < ore_cost:
		return UnmetNeed.NOT_ENOUGH_ORE
	# Only gate on vigor when this actually costs vigor surplus; a 0-cost item must
	# stay trainable even when the commander is strained (vigor surplus < 0).
	if vigor_cost > 0 and a_commander.vigor < vigor_cost:
		return UnmetNeed.NOT_ENOUGH_VIGOR
	if a_commander.dominion < dominion_cost:
		return UnmetNeed.NOT_ENOUGH_DOMINION
	return UnmetNeed.NONE
#endregion
