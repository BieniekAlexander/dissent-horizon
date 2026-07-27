class_name Lifespan
extends Node

## The EXPIRING facet (gdd/systems/authoring/piece-vocabulary.md §Facets): removes its host
## piece a fixed time after it enters play.
##
## A piece that never expires has NO Lifespan, rather than one holding a "forever" sentinel —
## presence is the capability, as under composition generally. The negative-means-permanent
## convention survives only at the AUTHORING boundary (`attach`), where an event's exported
## duration needs some way to say "stands until spent".
##
## Expiring is `Entity.expire()` — leaving play without dying: no death reaction, bounty or
## sound. A component that must hear its host go (a Beacon's) listens for the free.

#region Properties
## How long the host stands, in seconds. Authored in seconds; ticks are derived once, at the
## boundary, through TimeUtils (~/.claude/CLAUDE.md §2.2).
@export var lifespan_seconds: float = 0.0

## Physics ticks the host has stood so far. Per-frame node state, the framework's shape.
var _ticks_alive: int = 0
#endregion

#region Public API
## Give `a_entity` a Lifespan of `a_seconds`, or nothing when `a_seconds` is negative (the
## piece is permanent). Call before the entity enters the tree, as the spawning events do;
## the component then starts counting on the host's first physics tick.
static func attach(a_entity: Entity, a_seconds: float) -> Lifespan:
	if a_seconds < 0.0:
		return null
	var lifespan := Lifespan.new()
	lifespan.name = "Lifespan"
	lifespan.lifespan_seconds = a_seconds
	a_entity.add_child(lifespan)
	return lifespan


## Whether the host has stood its full time.
func is_expired() -> bool:
	return _ticks_alive >= TimeUtils.ticks_from_seconds(lifespan_seconds)
#endregion

#region Lifecycle
func _physics_process(_a_delta: float) -> void:
	_ticks_alive += 1
	if is_expired():
		set_physics_process(false)
		(get_parent() as Entity).expire()
#endregion
