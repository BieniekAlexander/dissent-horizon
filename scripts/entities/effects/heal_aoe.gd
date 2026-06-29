class_name HealAOE
extends Area3D

## Continuously heals friendly biological units overlapping this area each physics tick.
## Attach as a child of a structure Entity; commander affiliation is read from the parent
## at _ready() and refreshed each tick from the live parent value.

@export var heal_per_tick: float = 1.0
@export var commander_id: int = -1

var _parent_entity: Entity = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.Mask.MOVEMENT_OBSTRUCTION
	_parent_entity = get_parent() as Entity

func _physics_process(_delta: float) -> void:
	var effective_id: int = _parent_entity.commander_id if _parent_entity != null else commander_id
	for body: Node3D in get_overlapping_bodies():
		if not body.is_in_group("unit"):
			continue
		var entity: Entity = body as Entity
		if entity == null or entity.commander_id != effective_id:
			continue
		if not EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, entity):
			continue
		var defense: Defense = entity.get_node_or_null("Defense") as Defense
		if defense == null:
			continue
		defense.hp = minf(defense.hp + heal_per_tick, defense.hp_max)
		defense.hp_changed.emit(defense.hp, defense.hp_max)
