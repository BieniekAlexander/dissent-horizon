class_name Radiation
extends Projectile

## A radiation projectile with a two-state lifecycle, governed by a small state
## machine on the entity itself:
##
##   FLYING — ballistic arc toward the target (inherited Projectile motion).
##            On landing it transitions to FIELD instead of dying.
##   FIELD  — a stationary radiation field: damages nearby entities every tick
##            for `field_lifespan` frames, then dies.
##
## This replaces the earlier "HitBox nested inside a Projectile" approach: one
## entity owns both phases, so there's no nested Entity fighting the
## auto-initialize/reparent lifecycle.

enum State { FLYING, FIELD }

## How long (physics frames) the radiation field persists once it lands.
@export var field_lifespan: int = 15 * Engine.physics_ticks_per_second
## HP removed from each affected entity per physics tick while in FIELD.
@export var field_damage_per_tick: int = 1

var _state: State = State.FLYING
var _field_timer: int = 0

func _physics_process(_delta: float) -> void:
	match _state:
		State.FLYING:
			if _has_landed():
				_enter_field()
			else:
				_advance()
		State.FIELD:
			_tick_field()

## FLYING → FIELD: settle onto the ground plane and start the field timer.
func _enter_field() -> void:
	_state = State.FIELD
	_field_timer = field_lifespan
	velocity = Vector3.ZERO
	global_position.y = origin.y

func _tick_field() -> void:
	if collider != null:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = collider.shape
		params.transform = collider.global_transform
		params.collision_mask = CollisionLayers.Mask.TARGETABLE
		params.exclude = [self]
		for hit in get_world_3d().direct_space_state.intersect_shape(params, 32):
			var e = Entity.entity_from_collider(hit["collider"])
			if e is Commandable and e.defense != null:
				e.receive_damage(null, field_damage_per_tick)

	_field_timer -= 1
	if _field_timer <= 0:
		_on_death()
