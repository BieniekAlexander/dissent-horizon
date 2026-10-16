class_name Volatile
extends Node

## The VOLATILE facet: a piece that leaves a blast behind when it is destroyed — a power cell,
## a cryo dewar, an activation cask. The blast is an ordinary emission launched where the host
## stood, unattributed (no bounty, no veterancy), so it hurts whoever stands there, its
## destroyer's side included. The fuse is the EMISSION's first phase, not this node's: a
## motionless phase before the payout, authored per blast, which is what staggers a cascade —
## each blast kills the next cell, whose own fuse delays its blast in turn.
## Rules: gdd/systems/combat/environmental-pieces.md.

## The emission thrown on death. Set by the spec importer from the doc's `volatile:` key.
@export var blast_scene: PackedScene = null

## Set once the blast has been thrown, so no second death path throws it again.
var _has_blasted: bool = false


func _ready() -> void:
	host().entity_occurrence.connect(_on_host_occurrence)


func host() -> Entity:
	return get_parent() as Entity


static func of(a_node: Variant) -> Volatile:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Volatile") as Volatile


## Death fires while the host's map, position and commander are still valid
## (Entity._on_death), which is what lets the blast be placed where the host stood.
func _on_host_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence != Entity.EntityOccurrence.ON_DEATH or _has_blasted:
		return
	_has_blasted = true
	_blast()


func _blast() -> void:
	var piece: Entity = host()
	if blast_scene == null or piece.map == null or piece.commander == null:
		return
	var emission: Entity = blast_scene.instantiate() as Entity
	if emission == null:
		return
	emission.initialize(piece.map, piece.commander)
	emission.global_position = piece.global_position
	Emitter.launch(emission, null, piece.global_position)
