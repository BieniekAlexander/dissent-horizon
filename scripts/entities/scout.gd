class_name Scout extends Entity

## An invisible, commander-owned recon entity spawned by the Radar Scan ordnance. It
## contributes vision — its VisionRange shape clears fog for its owner exactly like a
## unit's does — for `lifespan_frames` physics ticks, then removes itself.
##
## Being in the "commandable" group with a VisionRange shape and an Ownership
## component is what makes fog.gd count it as a vision source (fog iterates that group
## as Entity, reading commander_id + vision_range_shape). It has no Sprite, Defense,
## Selectable or TargetBody, so it is invisible, unattackable and unselectable; the
## minimap skips it (it draws only Commandables). It never registers in the terrain
## grid, so it obstructs nothing.

## Physics frames the scout persists before freeing itself. 450 ≈ 15 s at the game's
## 30 ticks/second.
@export var lifespan_frames: int = 450

var _frames_alive: int = 0

func _physics_process(_delta: float) -> void:
	_frames_alive += 1
	if _frames_alive >= lifespan_frames:
		queue_free()
