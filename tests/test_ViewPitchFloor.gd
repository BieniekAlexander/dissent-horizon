extends GutTest

## The walkable slope limit is derived from the lowest camera pitch the terrain is built for
## (TerrainGrid.MIN_VIEW_PITCH_DEGREES), so a walkable slope is never hidden by facing away.
## That only holds while the camera actually looks down more steeply than that floor.


## The camera's pitch below the horizontal, from where it stands relative to what it looks at.
static func _camera_pitch_degrees() -> float:
	var offset: Vector3 = RTSCamera3D.initial_position()
	return rad_to_deg(atan2(offset.y, Vector2(offset.x, offset.z).length()))


func test_the_camera_looks_down_more_steeply_than_the_floor() -> void:
	assert_gt(_camera_pitch_degrees(), TerrainGrid.MIN_VIEW_PITCH_DEGREES)


func test_the_camera_looks_down_at_all() -> void:
	assert_lt(_camera_pitch_degrees(), 90.0)
