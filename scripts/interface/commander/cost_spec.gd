# Specifies what things are available to a commander
class_name TechnologySpec

enum UnmetNeed {
	NONE,
	NOT_ENOUGH_ORE,
	NOT_ENOUGH_POPULATION,
	NOT_ENOUGH_DOMINION,
	MISSING_STRUCTURE,
}

static var unmet_need_message_map: Dictionary = {
	UnmetNeed.NONE: "",
	UnmetNeed.NOT_ENOUGH_ORE: "Not enough ore",
	UnmetNeed.NOT_ENOUGH_POPULATION: "Not enough population",
	UnmetNeed.NOT_ENOUGH_DOMINION: "Not enough dominion",
	UnmetNeed.MISSING_STRUCTURE: "Required structure missing",
}

var ore_cost: int
var dominion_cost: int
var population_cost: int
# Cached result of the last availability_evaluator call (refreshed by
# Commander.proc_technology). Resource checks are layered on top in
# get_unmet_need, so this only reflects tech-prereq state.
var unmet_need: UnmetNeed = UnmetNeed.NONE
var availability_evaluator: Callable
var creation_time: int

static var get_none: Callable = func(_c): return UnmetNeed.NONE

func _init(
	a_ore_cost: int,
	a_population_cost: int,
	a_dominion_cost: int,
	a_availability_evaluator: Callable = get_none,
	a_creation_time: int = 10*Engine.physics_ticks_per_second
):
	ore_cost = a_ore_cost
	population_cost = a_population_cost
	dominion_cost = a_dominion_cost
	availability_evaluator = a_availability_evaluator
	creation_time = a_creation_time
	# A custom evaluator means the tech is gated on world state we can't yet
	# inspect (the owning Commander hasn't built structure_type_map). Start
	# pessimistic; proc_technology will refine once a structure event fires.
	if a_availability_evaluator != get_none:
		unmet_need = UnmetNeed.MISSING_STRUCTURE

func get_unmet_need(a_commander: Commander) -> UnmetNeed:
	if unmet_need != UnmetNeed.NONE:
		return unmet_need
	if a_commander.ore < ore_cost:
		return UnmetNeed.NOT_ENOUGH_ORE
	if a_commander.population < population_cost:
		return UnmetNeed.NOT_ENOUGH_POPULATION
	if a_commander.dominion < dominion_cost:
		return UnmetNeed.NOT_ENOUGH_DOMINION
	return UnmetNeed.NONE
