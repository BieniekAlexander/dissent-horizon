extends GutTest

## Commander.projected_dominion_rate() — the steady-state dominion/s a commander's TASKED
## trucks would sustain, given where they are working right now. Read by DominionBar's
## forward-looking projection region in place of the instantaneous
## dominion_collection_rate(), because a sentence-based Compound's occupancy DECAYS as
## terms complete rather than only ever rising — see gdd/systems/ux/ui/economy-bars.md
## §Rate projection and gdd/systems/combat/colonial-dominion.md §A captive serves a
## sentence.
##
## Built from real scenes, like test_WorkDetail.gd and test_TaskShelter.gd: a bare
## off-tree Actor never gets a real CommandReceiver.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ProjectedDominionRate.gd
## -gexit

const TRUCK: Dictionary = {
	"speed": 2.0,
	"garrison": {"capacity": 3, "bunker": false},
	"interactions": [Interaction.Type.DEPOSIT]
}
const SHELTER: Dictionary = {"structure": true, "shelter": true}
const COMPOUND: Dictionary = {
	"structure": true,
	"occupant_dominion": true,
	"garrison": {"capacity": 6, "sentence_length": 30.0, "frames": 0, "armours": 0, "movements": 0}
}

var _world: Node3D
var _commander: Commander


func before_each() -> void:
	_world = Node3D.new()
	_commander = Commander.new()
	_commander.id = 1
	_world.add_child(_commander)
	add_child_autofree(_world)
	_commander.set_physics_process(false)


func _shelter(a_spawn_interval: float, a_position: Vector3 = Vector3.ZERO) -> Entity:
	var shelter: Entity = FakePieces.make(SHELTER)
	_world.add_child(shelter)
	shelter.set_physics_process(false)
	shelter.top_level = true
	shelter.global_position = a_position
	(shelter.get_node("Shelter") as Shelter).spawn_interval = a_spawn_interval
	return shelter


func _compound(a_position: Vector3 = Vector3.ZERO) -> Actor:
	var compound: Actor = FakePieces.make(COMPOUND)
	_world.add_child(compound)
	compound.set_physics_process(false)
	compound.top_level = true
	compound.commander = _commander
	compound.global_position = a_position
	return compound


## A truck tasked on `a_shelter`, at `a_position`.
func _tasked_truck(a_shelter: Entity, a_position: Vector3 = Vector3.ZERO) -> Actor:
	var truck: Actor = FakePieces.make(TRUCK)
	_world.add_child(truck)
	truck.set_physics_process(false)
	truck.top_level = true
	truck.commander = _commander
	truck.global_position = a_position
	truck.command_receiver.update_commands(TaskShelter.new(CommandMessage.new(null, a_shelter)))
	return truck


func test_no_tasked_trucks_projects_nothing() -> void:
	_shelter(10.0)
	_compound()
	assert_almost_eq(_commander.projected_dominion_rate(), 0.0, 0.001)


func test_a_tasked_truck_with_no_compound_projects_nothing() -> void:
	var shelter := _shelter(10.0)
	_tasked_truck(shelter)
	assert_almost_eq(
		_commander.projected_dominion_rate(),
		0.0,
		0.001,
		"nowhere for the haul to go — no ceiling for it to sustain"
	)


func test_a_shelter_with_no_regeneration_rate_projects_nothing() -> void:
	var shelter := _shelter(0.0)
	_compound()
	_tasked_truck(shelter)
	assert_almost_eq(_commander.projected_dominion_rate(), 0.0, 0.001)


## Shelter and Compound at the SAME position: round-trip time is zero, so transport bounds
## nothing and the Shelter's own regeneration is the only limit — the degenerate case that
## also proves the formula does not divide by zero.
func test_adjacent_compound_is_bounded_only_by_shelter_regeneration() -> void:
	var shelter := _shelter(10.0)  # lambda = 0.1 captives/s
	var compound := _compound()
	compound.garrison.sentence_length = 5.0
	compound.garrison.capacity = 100  # not the binding constraint here
	var generator := compound.get_node("DominionGenerator") as OccupantDominionGenerator
	generator.dominion_per_unit = 5
	_tasked_truck(shelter, compound.global_position)
	# arrival_rate = min(0.1, INF) = 0.1; serving = min(0.1 * 5, 1) = 0.5; rate = 5 * 0.5 = 2.5
	assert_almost_eq(_commander.projected_dominion_rate(), 2.5, 0.001)


func test_the_transport_term_binds_at_a_real_distance() -> void:
	var shelter := _shelter(1.0, Vector3.ZERO)  # lambda = 1.0/s, effectively unbounded here
	var compound := _compound(Vector3(35.0, 0, 0))
	compound.garrison.sentence_length = 10.0
	compound.garrison.capacity = 1000
	var generator := compound.get_node("DominionGenerator") as OccupantDominionGenerator
	generator.dominion_per_unit = 1
	var truck := _tasked_truck(shelter)
	var round_trip: float = 2.0 * 35.0 / truck.movement.speed
	# arrival_rate = min(1.0, 1/round_trip) = 1/round_trip, since one lone truck's round trip
	# is far slower than the Shelter's 1/s regeneration.
	var expected: float = minf(1.0, 1.0 / round_trip) * 10.0
	assert_almost_eq(_commander.projected_dominion_rate(), expected, 0.01)


func test_more_tasked_trucks_raise_the_transport_bound() -> void:
	var shelter := _shelter(1.0, Vector3.ZERO)
	var compound := _compound(Vector3(35.0, 0, 0))
	compound.garrison.sentence_length = 10.0
	compound.garrison.capacity = 1000
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 1
	_tasked_truck(shelter)
	var one_truck_rate: float = _commander.projected_dominion_rate()
	_tasked_truck(shelter)
	var two_truck_rate: float = _commander.projected_dominion_rate()
	assert_almost_eq(
		two_truck_rate,
		2.0 * one_truck_rate,
		0.01,
		"double the trucks working the same route doubles the throughput bound"
	)


func test_capped_at_one_captive_serving() -> void:
	var shelter := _shelter(1.0)  # effectively unbounded regeneration for this test
	var compound := _compound()
	compound.garrison.sentence_length = 1000.0  # a long term, so occupancy would otherwise soar
	compound.garrison.capacity = 3
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 7
	_tasked_truck(shelter, compound.global_position)
	assert_almost_eq(
		_commander.projected_dominion_rate(),
		7.0 * Garrison.SENTENCES_AT_ONCE,
		0.001,
		"the ceiling is the captives a Compound sentences at once, not the places it holds"
	)


func test_two_shelters_contribute_independently() -> void:
	var near_shelter := _shelter(10.0, Vector3.ZERO)
	var far_shelter := _shelter(10.0, Vector3(1000, 0, 0))
	var compound := _compound()
	compound.garrison.sentence_length = 5.0
	compound.garrison.capacity = 1000
	(compound.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 1
	_tasked_truck(near_shelter, compound.global_position)
	var one_shelter_rate: float = _commander.projected_dominion_rate()
	# The far Shelter's own truck is placed right at ITS Shelter, at the same distance to the
	# one Compound the far Shelter has to route through as well — so it contributes the SAME
	# amount independently, and the total should be exactly double.
	var far_compound := _compound(far_shelter.global_position)
	far_compound.garrison.sentence_length = 5.0
	far_compound.garrison.capacity = 1000
	(far_compound.get_node("DominionGenerator") as OccupantDominionGenerator).dominion_per_unit = 1
	_tasked_truck(far_shelter, far_shelter.global_position)
	assert_almost_eq(_commander.projected_dominion_rate(), 2.0 * one_shelter_rate, 0.01)
