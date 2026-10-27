extends GutTest

## A VISION FOOTPRINT DOES NOT DEPEND ON WHICH WAY ITS PIECE FACES. The raster sizes a source's
## footprint from its shape's GLOBAL basis, which carries the piece's yaw, and a rotated unit
## column is 1 only to within a float ulp. Truncating radius x scale flipped a 16-unit sight
## between 15 and 16 px as a unit walked, so the fog's edge pulsed (FogRaster.footprint_for,
## found 2026-10-18).

const RADIUS: float = 16.0


func _fog() -> Fog:
	var fog := Fog.new()
	fog.watching_commander_id = 1
	add_child_autofree(fog)
	fog.set_physics_process(false)
	fog._configure(64, 64, Vector2.ZERO, 32.0, 32.0)
	return fog


func _shape_at_yaw(a_yaw: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	shape.shape = cylinder
	add_child_autofree(shape)
	shape.global_transform = Transform3D(VU.with_yaw(Basis(), a_yaw), Vector3.ZERO)
	return shape


func test_the_footprint_is_the_same_at_every_heading() -> void:
	var raster: FogRaster = _fog()._raster
	var upright: int = raster.vision_offsets(_shape_at_yaw(0.0)).size()
	assert_gt(upright, 0, "a 16-unit sight covers something")
	var differing: Array = []
	for step: int in 360:
		var yaw: float = deg_to_rad(float(step))
		var size: int = raster.vision_offsets(_shape_at_yaw(yaw)).size()
		if size != upright:
			differing.append([step, size])
	assert_eq(differing, [], "every heading stamps the upright footprint (degree, size)")


# --- A box ----------------------------------------------------------------------


func _box_at_yaw(a_size: Vector2, a_yaw: float) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(a_size.x, 4.0, a_size.y)
	shape.shape = box
	add_child_autofree(shape)
	shape.global_transform = Transform3D(VU.with_yaw(Basis(), a_yaw), Vector3.ZERO)
	return shape


func test_a_box_at_a_right_angle_keeps_its_grid_aligned_footprint() -> void:
	var raster: FogRaster = _fog()._raster
	var upright: Array = raster.vision_offsets(_box_at_yaw(Vector2(20.0, 6.0), 0.0))
	var quarter: Array = raster.vision_offsets(_box_at_yaw(Vector2(20.0, 6.0), PI / 2.0))
	assert_eq(quarter, upright, "as every footprint was before turned ones")


func test_a_turned_box_opens_turned() -> void:
	var raster: FogRaster = _fog()._raster
	var yaw: float = 0.5
	var half := Vector2(20.0, 4.0)
	var offsets: Array = raster.vision_offsets(_box_at_yaw(half * 2.0, yaw))
	var turned := HighlightShape.rect(Vector2.ZERO, half, yaw)
	var area: float = half.x * half.y * 4.0
	assert_almost_eq(float(offsets.size()), area, area * 0.1, "about the box's own area")
	var far: Vector2 = turned.local_to_world_xz(Vector2(half.x - 1.0, 0.0))
	assert_true(offsets.has(Vector2i(roundi(far.x), roundi(far.y))), "reaches along its length")
	assert_false(offsets.has(Vector2i(roundi(half.x - 1.0), 0)), "not along the world axis")
