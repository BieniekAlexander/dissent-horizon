class_name PlantedCharge
extends Node

## Its host is a charge a Sapper has planted: on the ground, where it is a piece of its own
## to be shot at, or riding on a MECH unit or structure. It goes off when its owner orders it
## to (Detonate), when it is destroyed on the ground, or when its carrier dies; it vanishes
## without going off when its planter dies or an opponent repairs it (or its carrier) away.
## The rules and the reasoning: gdd/systems/combat/planted-explosives.md.

## Every live charge, for finding one by its planter.
const GROUP: StringName = &"planted_charge"

## The ability whose charge a planted charge holds (Abilities.hold_recharge) and whose
## emission is the blast.
const PLANT_ABILITY: StringName = &"plant"
const DETONATE_ABILITY: StringName = &"detonate"

## The unit that planted it. Untyped: it may be freed.
var _planter: Variant = null
## The piece it rides on, or null for a charge standing on the ground. Untyped likewise.
var _carrier: Variant = null
## Set once the charge has gone off or been removed, so no second path acts on it.
var _is_resolved: bool = false


func _ready() -> void:
	get_parent().add_to_group(GROUP)
	host().entity_occurrence.connect(_on_host_occurrence)


func host() -> Actor:
	return get_parent() as Actor


static func of(a_node: Variant) -> PlantedCharge:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("PlantedCharge") as PlantedCharge


## The live charge `a_planter` planted, or null.
static func planted_by(a_planter: Node) -> PlantedCharge:
	if a_planter == null or not a_planter.is_inside_tree():
		return null
	for node: Node in a_planter.get_tree().get_nodes_in_group(GROUP):
		var charge: PlantedCharge = PlantedCharge.of(node)
		if charge != null and not charge._is_resolved and is_same(charge._planter, a_planter):
			return charge
	return null


## Whether `a_entity` is a charge riding on something — a charge with no body of its own.
static func is_riding(a_entity: Node) -> bool:
	var charge: PlantedCharge = PlantedCharge.of(a_entity)
	return charge != null and charge._carrier != null


## Whether `a_entity` may carry a charge: a live MECH piece, unit or structure, that does not
## fly. Whose it is does not matter — a charge may be driven into the enemy on a friendly truck.
static func can_carry(a_entity: Variant) -> bool:
	if a_entity == null or not is_instance_valid(a_entity) or not (a_entity is Actor):
		return false
	var piece := a_entity as Actor
	return (
		piece.is_inside_tree()
		and not piece.is_queued_for_deletion()
		and piece.aerial == null
		and PlantedCharge.of(piece) == null
		and piece.defense != null
		and piece.defense.frame_type == Defense.FrameType.MECH
	)


## The charges riding on `a_carrier`.
static func carried_by(a_carrier: Node) -> Array[PlantedCharge]:
	var out: Array[PlantedCharge] = []
	if a_carrier == null or not a_carrier.is_inside_tree():
		return out
	for node: Node in a_carrier.get_tree().get_nodes_in_group(GROUP):
		var charge: PlantedCharge = PlantedCharge.of(node)
		if charge != null and not charge._is_resolved and is_same(charge._carrier, a_carrier):
			out.append(charge)
	return out


## Arm the charge: planted by `a_planter`, riding on `a_carrier` or (null) standing where the
## host is. Holds the planter's Plant charge until this one leaves play.
func arm(a_planter: Actor, a_carrier: Actor) -> void:
	_planter = a_planter
	a_planter.entity_occurrence.connect(_on_planter_occurrence)
	var pool := a_planter.get_node_or_null("Abilities") as Abilities
	if pool != null:
		pool.hold_recharge(PLANT_ABILITY, host())
	if a_carrier != null:
		_carrier = a_carrier
		a_carrier.entity_occurrence.connect(_on_carrier_occurrence)
		host().global_position = a_carrier.global_position
		host()._apply_targetable_layers()


func planter() -> Actor:
	return _planter as Actor if is_instance_valid(_planter) else null


func carrier() -> Actor:
	return _carrier as Actor if is_instance_valid(_carrier) else null


func is_resolved() -> bool:
	return _is_resolved


## Ride along with the carrier. One off the tree (garrisoned) carries it nowhere: the charge
## waits where it last was. A planter freed without a death of its own (killed inside a
## transport) takes its charge with it, as a death does.
func _physics_process(_a_delta: float) -> void:
	if not _is_resolved and _planter != null and not is_instance_valid(_planter):
		remove()
		return
	var carrier: Actor = carrier()
	if carrier != null and carrier.is_inside_tree():
		host().global_position = carrier.global_position


## Go off where the charge is: at its carrier, or on the ground under it.
func detonate() -> void:
	if _is_resolved:
		return
	_blast()
	_is_resolved = true
	host().die()


## Take the charge out of play without it going off — an opponent's repair, or its planter's
## death.
func remove() -> void:
	if _is_resolved:
		return
	_is_resolved = true
	host().die()


func _blast() -> void:
	var scene: PackedScene = AbilityCatalog.emission_of(DETONATE_ABILITY)
	var map: Map = host().map
	if scene == null or map == null or host().commander == null:
		return
	var emission: Entity = scene.instantiate() as Entity
	emission.initialize(map, host().commander)
	emission.global_position = host().global_position
	var carrier: Actor = carrier()
	var target: Variant = (
		carrier if carrier != null and carrier.is_inside_tree() else host().global_position
	)
	Emitter.launch(emission, planter() if planter() != null else host(), target)


## Destroyed where it stood: it goes off. Only a charge on the ground has a body to destroy.
func _on_host_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence != Entity.EntityOccurrence.ON_DEATH or _is_resolved:
		return
	_is_resolved = true
	_blast()


func _on_planter_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence == Entity.EntityOccurrence.ON_DEATH:
		remove()


## A carrier that dies sets its charge off where it fell — at the spot, since the carrier
## itself is on its way out.
func _on_carrier_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence == Entity.EntityOccurrence.ON_DEATH:
		host().global_position = (_carrier as Node3D).global_position
		_carrier = null
		detonate()
