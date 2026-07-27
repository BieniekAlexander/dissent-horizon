@tool
class_name StartPoint
extends Marker3D

## Where one player slot deploys (Skirmish.START_POINT_GROUP). Draws a coloured column so the
## start reads at a glance while a map is being authored or reviewed; in a running game the
## column is hidden, since the slot's starting units stand on this spot.

#region Constants
## A colour with zero alpha means "none chosen yet": the editor picks one when the marker is
## first seen, and saving the scene keeps it.
const UNCHOSEN := Color(0, 0, 0, 0)
#endregion

#region Properties
@export var color: Color = UNCHOSEN:
	set(v):
		color = v
		_apply_color()
#endregion

@onready var _column: MeshInstance3D = $Column


func _ready() -> void:
	if not Engine.is_editor_hint():
		_column.visible = false
		return
	if color.a == 0.0:
		# Its own generator: an editor-time pick is not a simulation draw, and must not shift
		# the seeded gameplay stream (test_SeededRandomness).
		color = Color.from_hsv(RandomNumberGenerator.new().randf(), 0.8, 0.95)
	_apply_color()


func _apply_color() -> void:
	if _column == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	_column.material_override = material
