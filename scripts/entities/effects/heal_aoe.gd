class_name HealAOE
extends Area3D

## Continuously heals friendly biological units overlapping this area each physics tick —
## its owner's and its allies' (gdd/systems/combat/target-acquisition.md §Alliances): the BIO
## counterpart of Repair, which allies share too. Attach as a child of a structure Entity;
## commander affiliation is read from the parent at _ready() and refreshed each tick from the
## live parent value.

@export var heal_per_tick: float = 1.0
@export var commander_id: int = -1

var _parent_entity: Entity = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
	_parent_entity = get_parent() as Entity


func _physics_process(_a_delta: float) -> void:
	for body: Node3D in get_overlapping_bodies():
		var entity: Entity = body as Entity
		if not heals(entity):
			continue
		(entity.get_node("Defense") as Defense).restore(heal_per_tick)


## Whether this aura mends `a_entity`: a biological unit with a Defense, on the parent's side —
## its own or an ally's. With no parent, `commander_id` alone decides.
func heals(a_entity: Entity) -> bool:
	if a_entity == null or not a_entity.is_in_group("unit"):
		return false
	var friendly: bool = (
		_parent_entity.is_friendly_to(a_entity)
		if _parent_entity != null
		else a_entity.commander_id == commander_id
	)
	if not friendly:
		return false
	if not EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, a_entity):
		return false
	return a_entity.get_node_or_null("Defense") is Defense
