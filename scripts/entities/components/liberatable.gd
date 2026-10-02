class_name Liberatable
extends Node

## Liberatable component — declares that its parent entity can be converted by a
## [Liberator] RIGHT NOW, by holding the `CollisionLayers.Mask.LIBERATABLE` bit on the
## entity's TargetBody. Same idiom as [Stealth], which registers its parent on the
## STEALTH layer so DetectionRange queries only ever return entities that opted in.
##
## The bit IS the predicate, not a hint the caller re-checks. `Liberator.tick()` runs
## every physics frame on every warlord, so a hit the query returns and the caller then
## discards is work done for nothing — and, because a shape query is capped at a result
## COUNT, discarded hits crowd out real candidates and conversions silently stop
## happening. Holding the whole condition in the layer is what makes that cap safe.
##
## "Right now" means NEUTRAL (commander 0): a terrestrial an enemy commander has taken
## is not the world's to free. Ownership is the only dynamic half — being a liberatable
## KIND at all is this node's presence, authored on the scene, so nothing here re-tests
## the piece id and a [Liberator] no longer names one.
##
## Conversion itself never has to clear the bit: `Liberator` REPLACES the unit rather
## than re-flagging it, and detaching the original from the tree takes its body out of
## the physics space in the same call.


#region Lifecycle
func _ready() -> void:
	var entity: Entity = get_parent() as Entity
	if entity == null:
		push_error("Liberatable: parent is not an Entity")
		return
	# Resolved by name rather than through Entity's @onready `ownership` — a child's
	# _ready() runs BEFORE its parent's, so that field is still null at this point.
	# (Entity.team_color() resolves Ownership directly for the same class of reason.)
	var own := entity.get_node_or_null("Ownership") as Ownership
	if own != null:
		own.commander_changed.connect(_on_commander_changed)
	# A queue_free()d unit keeps answering physics queries until the tree flush at the
	# end of the frame, so leave the layer the moment it dies rather than making every
	# liberator guard against corpses.
	entity.entity_occurrence.connect(_on_entity_occurrence)
	refresh()


#endregion


#region Public API
## Recompute the LIBERATABLE bit from the parent's current ownership. Driven by
## `commander_changed`; safe to call at any time.
func refresh() -> void:
	_write(_is_currently_liberatable())


#endregion


#region Private helpers
func _is_currently_liberatable() -> bool:
	var own := get_parent().get_node_or_null("Ownership") as Ownership
	return own != null and own.commander_id == 0


## The bit lives on the TargetBody, not the root CharacterBody3D, for two reasons:
## `Entity.refresh_movement_collision()` wipes every root layer bit but STEALTH, and
## `Entity._apply_targetable_layers()` explicitly preserves bits it doesn't own — so
## the TargetBody is the one of the two that will still be carrying this next tick.
## `Entity.entity_from_collider` resolves either back to the entity, so the query side
## is indifferent.
func _write(a_on: bool) -> void:
	var body := get_parent().get_node_or_null("TargetBody") as CollisionObject3D
	if body == null:
		return
	if a_on:
		body.collision_layer |= CollisionLayers.Mask.LIBERATABLE
	else:
		body.collision_layer &= ~CollisionLayers.Mask.LIBERATABLE


func _on_commander_changed(_a_old_commander: Commander, _a_new_commander: Commander) -> void:
	refresh()


func _on_entity_occurrence(a_occurrence: Entity.EntityOccurrence, _a_source: Entity) -> void:
	if a_occurrence == Entity.EntityOccurrence.ON_DEATH:
		_write(false)
#endregion
