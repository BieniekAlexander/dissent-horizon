# Specifies what things are available to a commander
class_name TechnologySpec

#region Constants
enum UnmetNeed {
	NONE,
	NOT_ENOUGH_ENERGY,
	NOT_ENOUGH_INFRASTRUCTURE,
	NOT_ENOUGH_DOMINION,
	MISSING_STRUCTURE,
}

static var unmet_need_message_map: Dictionary = {
	UnmetNeed.NONE: "",
	UnmetNeed.NOT_ENOUGH_ENERGY: "Not enough energy",
	UnmetNeed.NOT_ENOUGH_INFRASTRUCTURE: "Not enough infrastructure",
	UnmetNeed.NOT_ENOUGH_DOMINION: "Not enough dominion",
	UnmetNeed.MISSING_STRUCTURE: "Required structure missing",
}
#endregion

#region Properties
var energy_cost: int
var dominion_cost: int
## Infrastructure surplus required to produce this. Gates only
## when > 0 — a 0-cost item is never blocked, even when the commander is strained.
var infrastructure_cost: int
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
	a_energy_cost: int,
	a_infrastructure_cost: int,
	a_dominion_cost: int,
	a_creation_time: int,
	a_required_structures: Array = []
):
	energy_cost = a_energy_cost
	infrastructure_cost = a_infrastructure_cost
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
	if a_commander.energy < energy_cost:
		return UnmetNeed.NOT_ENOUGH_ENERGY
	# Only gate on infrastructure when this actually costs infrastructure surplus; a 0-cost item must
	# stay trainable even when the commander is strained (infrastructure surplus < 0).
	if infrastructure_cost > 0 and a_commander.infrastructure < infrastructure_cost:
		return UnmetNeed.NOT_ENOUGH_INFRASTRUCTURE
	if a_commander.dominion < dominion_cost:
		return UnmetNeed.NOT_ENOUGH_DOMINION
	return UnmetNeed.NONE
#endregion
