class_name Pickup
extends Node

## The COLLECTIBLE facet: a token the first ground unit to walk over it collects for its
## commander — energy, or charges of an ordnance into the commander's depot — after which the
## token leaves play. A coin: no order, no interaction, any commander's unit, once.
## Rules: gdd/systems/combat/environmental-pieces.md §Pickups.
##
## Aircraft collect nothing; a cruising aircraft is not standing on the ground the token lies
## on. Neutral units (commander 0, the world's) collect nothing either: the world has no purse.

## Fired as the token is collected, before it leaves play.
signal collected(by: Actor)

## Energy handed to the collector's commander. 0 for a token that grants an ordnance instead.
@export var energy: int = 0
## The ordnance whose charges the collector's commander is handed, or empty for an energy token.
@export var ability: StringName = &""
## How many charges of `ability` one token holds.
@export var charges: int = 1
## How close a unit's hull must come to the token's centre to collect it, in world units.
@export var radius: float = 0.5

## Set once collected, so the token cannot be collected twice while it waits to be freed.
var _is_collected: bool = false

## A flat cylinder stands for the token's reach: how far out a hull must come, with a height
## that keeps a cruising aircraft's hurtbox clear of it.
const REACH_HEIGHT: float = 1.0


func host() -> Entity:
	return get_parent() as Entity


static func of(a_node: Variant) -> Pickup:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Pickup") as Pickup


## Whether `a_entity` may collect a token: a ground unit of a commander with a purse.
static func can_collect(a_entity: Entity) -> bool:
	return (
		a_entity is Actor
		and a_entity.is_inside_tree()
		and a_entity.is_in_group(&"unit")
		and a_entity.commander_id > 0
		and a_entity.commander != null
		and not a_entity.is_air_target()
	)


func sleep_ticks() -> int:
	return 0


func simulation_step(_a_delta: float) -> void:
	if _is_collected:
		return
	var collector: Actor = _first_collector()
	if collector != null:
		collect_by(collector)


## Hand the token's contents to `a_collector`'s commander and take the token out of play.
func collect_by(a_collector: Actor) -> void:
	if _is_collected:
		return
	_is_collected = true
	var commander: Commander = a_collector.commander
	if energy > 0:
		commander.add_energy(energy)
	if ability != &"" and charges > 0:
		commander.ordnance_depot.grant(ability, charges)
	collected.emit(a_collector)
	host().expire()


## The first unit, in serial order, whose hull reaches the token — or null.
func _first_collector() -> Actor:
	var piece: Entity = host()
	if not piece.is_inside_tree():
		return null
	var reach := CylinderShape3D.new()
	reach.radius = radius
	reach.height = REACH_HEIGHT
	var origin: Vector3 = piece.global_position
	var near: Array[Entity] = SU.entities_within(
		piece.get_world_3d(),
		Hull.point(VU.in_xz(origin)),
		reach,
		origin,
		CollisionLayers.Mask.TARGETABLE_GROUND,
		[piece]
	)
	for candidate: Entity in near:
		if can_collect(candidate):
			return candidate as Actor
	return null
