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
