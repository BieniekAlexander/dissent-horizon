class_name LazerVisualization
extends MeshInstance3D

## Beam visualization for a LazerWeapon. Attach as a child of the Weapon node.
## Activated by show_beam(); hides itself after the beam duration elapses.

#region Constants
const BEAM_TICKS: int = 5
#endregion

#region Properties
var _owner_entity: Commandable
var _target_pos: Vector3
var _ticks_left: int = 0
#endregion

#region Lifecycle
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	visible = false

func _physics_process(_delta: float) -> void:
	_ticks_left -= 1
	if _ticks_left <= 0:
		visible = false
		set_process(false)
		set_physics_process(false)

func _process(_delta: float) -> void:
	if not visible:
		return
	var diff := _target_pos - _owner_entity.global_position
	global_position = _owner_entity.global_position + 0.5 * diff + Vector3.UP * 0.5
	rotation = Vector3(-VU.inXZ(diff).angle(), 0, deg_to_rad(90))
	scale.y = diff.length() / 2.0
#endregion

#region Public API
func show_beam(owner: Commandable, target: Entity) -> void:
	_owner_entity = owner
	_target_pos = target.global_position
	_ticks_left = BEAM_TICKS
	visible = true
	set_process(true)
	set_physics_process(true)
#endregion
