class_name VU

## Vector helpers, aliased `VU` for how often they appear. Y is terrain height and XZ is the
## horizontal plane, so converting between a world Vector3 and its ground footprint is the
## single most common operation in this codebase.


#region Public API
static func in_xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func on_xz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


static func from_xz(v: Vector2) -> Vector3:
	return Vector3(v.x, 0, v.y)


static func l1_norm(v: Vector2) -> float:
	return abs(v.x) + abs(v.y)


static func range(v: Vector2) -> int:
	assert(
		v.x <= v.y,
		"first component was larger than second component, so range undefined for vector %s" % v
	)
	return v.y - v.x


static func get_rotated_vector_3d(current: Vector3, target: Vector3, max_radians: float) -> Vector3:
	var total_angle = current.angle_to(target)

	if total_angle < 0.001:
		return target.normalized() * current.length()

	var weight = min(max_radians / total_angle, 1.0)
	return current.slerp(target, weight).normalized() * current.length()
#endregion
