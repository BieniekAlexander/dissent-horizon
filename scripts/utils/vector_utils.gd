class_name VU

## Vector helpers, aliased `VU` for how often they appear. Y is terrain height and XZ is the
## horizontal plane, so converting between a world Vector3 and its ground footprint is the
## single most common operation in this codebase.

## How near straight up or down a pitch counts as gimbal lock, as the engine's get_euler has it.
const _EULER_EPSILON: float = 0.00001


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
	var total_angle: float = DMath.angle_to_3d(current, target)

	if total_angle < 0.001:
		return target.normalized() * current.length()

	var weight: float = minf(max_radians / total_angle, 1.0)
	return slerp_3d(current, target, weight).normalized() * current.length()


## Vector3.slerp, in DMath: turns `from` toward `to` about their common axis by `weight` of the
## angle between them, its length moving linearly between theirs. Parallel or zero vectors
## make it a straight lerp, as the engine's does.
static func slerp_3d(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var from_length_sq: float = from.length_squared()
	var to_length_sq: float = to.length_squared()
	if from_length_sq == 0.0 or to_length_sq == 0.0:
		return from.lerp(to, weight)
	var axis: Vector3 = from.cross(to)
	var axis_length_sq: float = axis.length_squared()
	if axis_length_sq == 0.0:
		return from.lerp(to, weight)
	axis /= sqrt(axis_length_sq)
	var from_length: float = sqrt(from_length_sq)
	var length: float = lerpf(from_length, sqrt(to_length_sq), weight)
	var turn: float = DMath.angle_to_3d(from, to) * weight
	return DMath.rotated_3d(from, axis, turn) * (length / from_length)


## The world yaw of `node`: its piece's `yaw` (Entity.yaw), which is exact where
## `global_rotation.y` is the engine's decomposition of a basis — through the platform's atan2,
## which rounds differently on different platforms. Pieces only ever yaw (pitch and roll live on
## the model), and the nodes between a piece and its weapons do not turn. A node in no piece (a
## test rig) sums its ancestry's own yaws.
static func yaw_of(node: Node3D) -> float:
	var at: Node = node
	while at is Node3D:
		if at is Entity:
			return (at as Entity).yaw
		at = at.get_parent()
	var yaw: float = 0.0
	at = node
	while at is Node3D:
		yaw += (at as Node3D).rotation.y
		at = at.get_parent()
	return yaw


## Basis(Vector3.UP, yaw), built with DMath so it rounds the same everywhere.
static func yaw_basis(yaw: float) -> Basis:
	var c: float = DMath.cos(yaw)
	var s: float = DMath.sin(yaw)
	return Basis(Vector3(c, 0.0, -s), Vector3.UP, Vector3(s, 0.0, c))


## Basis.from_euler(angles) in Godot's default YXZ order — yaw, then pitch, then roll — built with
## DMath, for a node the game turns at run time (see Entity.yaw for why not `rotation`).
static func euler_basis(angles: Vector3) -> Basis:
	var cx: float = DMath.cos(angles.x)
	var sx: float = DMath.sin(angles.x)
	var cz: float = DMath.cos(angles.z)
	var sz: float = DMath.sin(angles.z)
	var pitch := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, cx, sx), Vector3(0.0, -sx, cx))
	var roll := Basis(Vector3(cz, sz, 0.0), Vector3(-sz, cz, 0.0), Vector3(0.0, 0.0, 1.0))
	return yaw_basis(angles.y) * pitch * roll


## Basis.get_euler (YXZ) in DMath: the angles euler_basis would build `basis` from, its scale set
## aside. For reading a node's authored turn once, as its starting state.
static func euler_of(basis: Basis) -> Vector3:
	var b: Basis = basis.orthonormalized()
	var m12: float = b.z.y
	if m12 >= 1.0 - _EULER_EPSILON:
		return Vector3(-PI / 2.0, -DMath.atan2(b.y.x, b.x.x), 0.0)
	if m12 <= -(1.0 - _EULER_EPSILON):
		return Vector3(PI / 2.0, DMath.atan2(b.y.x, b.x.x), 0.0)
	return Vector3(DMath.asin(-m12), DMath.atan2(b.z.x, b.z.z), DMath.atan2(b.x.y, b.y.y))


## `rest` turned to face `yaw`: its own yaw replaced, its pitch, roll and scale kept — what
## setting `rotation.y` on a node does, built with DMath.
static func with_yaw(rest: Basis, yaw: float) -> Basis:
	var angles: Vector3 = euler_of(rest)
	return euler_basis(Vector3(angles.x, yaw, angles.z)) * Basis.from_scale(rest.get_scale())
#endregion
