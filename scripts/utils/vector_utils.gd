class_name VU

#region Public API
static func inXZ(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func onXZ(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

static func fromXZ(v: Vector2) -> Vector3:
	return Vector3(v.x, 0, v.y)

static func l1Norm(v: Vector2) -> float:
	return abs(v.x) + abs(v.y)

static func range(v: Vector2) -> int:
	assert(v.x<=v.y, "first component was larger than second component, so range undefined for vector %s" % v)
	return (v.y-v.x)
#endregion
