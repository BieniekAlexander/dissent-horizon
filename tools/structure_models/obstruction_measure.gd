class_name ObstructionMeasure
extends RefCounted

## How much of an infantry figure standing BEHIND a structure the structure's model hides from
## the game camera. The structure models' budget is that no more than half of the figure is
## ever hidden (gdd/systems/ux/aesthetics/README.md §Models); generate_structure_models.gd
## measures every model against it before writing any.
##
## The figure is the infantry HURTBOX — an upright cylinder standing on the ground — and
## "how much" is the share of its on-screen silhouette whose line of sight to the camera
## passes through the model. The camera is orthographic, so a line of sight is the view
## direction itself and distance never matters, only the angle. The player can turn the camera,
## so every yaw is tried; the elevation is fixed.
##
## Pure: triangles in, a number out. Ground is flat at y = 0, and the model is in the piece's
## own space — origin at the footprint's centre, which is where Map.add_structure puts it.

#region Constants
## Spacing of the figure positions tried round the footprint, in world units. A quarter of a
## cell is finer than the smallest feature a placeholder model has that could hide a figure.
const POSITION_STEP: float = 0.25

## How finely the figure's silhouette is sampled: columns across it, rows up it. A share is
## then measured in steps of 1 / (columns × rows) of the silhouette.
const SILHOUETTE_COLUMNS: int = 6
const SILHOUETTE_ROWS: int = 12

## Side of the screen-space buckets the projected triangles are filed in, so a figure tests
## only the triangles near it. About a figure's width: smaller buckets cost more lookups per
## figure than they save in triangle tests.
const BUCKET_SIZE: float = 0.4
#endregion

#region Public API


## The worst share of the figure the model hides, over every yaw in `yaw_count` even steps
## and every figure position on the model's far side. Returns
## `{fraction, yaw_degrees, position}`; a fraction of 0 means nothing was ever hidden.
##
## `footprint` is the size of the footprint in world units (X, Z). A figure may stand
## anywhere its whole base is clear of the footprint.
static func worst_case(
	triangles: PackedVector3Array,
	footprint: Vector2,
	figure_radius: float,
	figure_height: float,
	elevation_radians: float,
	yaw_count: int
) -> Dictionary:
	var worst: Dictionary = {"fraction": 0.0, "yaw_degrees": 0.0, "position": Vector2.ZERO}
	var model_top: float = Array(triangles).reduce(
		func(top: float, v: Vector3) -> float: return maxf(top, v.y), 0.0
	)
	# Nothing further out than the model's height seen along the view can be behind it.
	var reach: float = figure_radius + model_top / tan(elevation_radians) + POSITION_STEP
	for step: int in range(yaw_count):
		var yaw: float = TAU * step / yaw_count
		var view: Basis = view_basis(yaw, elevation_radians)
		var projection: Dictionary = project(triangles, view)
		for position: Vector2 in _far_side_positions(footprint, figure_radius, reach, view):
			var fraction: float = hidden_fraction(
				projection, view, position, figure_radius, figure_height
			)
			if fraction > worst["fraction"]:
				worst = {"fraction": fraction, "yaw_degrees": rad_to_deg(yaw), "position": position}
	return worst


## The camera's axes at a yaw and elevation, matching RTSCamera3D.initial_position: x is
## screen right, y screen up, z the view direction (INTO the scene, so larger z is further
## from the camera).
static func view_basis(yaw_radians: float, elevation_radians: float) -> Basis:
	var toward_camera: Vector3 = Vector3(
		cos(elevation_radians) * sin(yaw_radians),
		sin(elevation_radians),
		cos(elevation_radians) * cos(yaw_radians)
	)
	var forward: Vector3 = -toward_camera
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	return Basis(right, right.cross(forward), forward)


## The model as seen from `view`: each triangle's screen corners and their depths, filed in
## screen-space buckets. What hidden_fraction measures against; one per view.
static func project(triangles: PackedVector3Array, view: Basis) -> Dictionary:
	var corners: PackedVector2Array = PackedVector2Array()
	var depths: PackedFloat32Array = PackedFloat32Array()
	var buckets: Dictionary = {}
	for i: int in range(triangles.size()):
		var v: Vector3 = triangles[i]
		corners.append(Vector2(v.dot(view.x), v.dot(view.y)))
		depths.append(v.dot(view.z))
	for triangle: int in range(triangles.size() / 3):
		var a: Vector2 = corners[triangle * 3]
		var bounds: Rect2 = Rect2(a, Vector2.ZERO).expand(corners[triangle * 3 + 1]).expand(
			corners[triangle * 3 + 2]
		)
		# A plain Array, not a PackedInt32Array: a packed array read out of a Dictionary is a
		# copy, and appending to it would leave the bucket empty.
		for bucket: Vector2i in _buckets_over(bounds):
			if not buckets.has(bucket):
				buckets[bucket] = []
			(buckets[bucket] as Array).append(triangle)
	return {"corners": corners, "depths": depths, "buckets": buckets}


## The share of a figure at `position` that the model, as `project` saw it from `view`, hides.
static func hidden_fraction(
	projection: Dictionary, view: Basis, position: Vector2, radius: float, height: float
) -> float:
	var base: Vector3 = Vector3(position.x, 0.0, position.y)
	var across: float = base.dot(view.x)
	var up: float = base.dot(view.y)
	# The silhouette spans the radius either side, and from the near bottom rim to the far
	# top rim: the rims add radius × the view's horizontal reach into screen-up.
	var rim: float = radius * Vector2(view.y.x, view.y.z).length()
	var low: float = up - rim
	var high: float = up + height * view.y.y + rim
	var bounds: Rect2 = Rect2(across - radius, low, radius * 2.0, high - low)
	var buckets: Dictionary = projection["buckets"]
	var near: Dictionary = {}
	for bucket: Vector2i in _buckets_over(bounds):
		for triangle: int in buckets.get(bucket, []):
			near[triangle] = true
	if near.is_empty():
		return 0.0
	var candidates: PackedInt32Array = PackedInt32Array(near.keys())
	var corners: PackedVector2Array = projection["corners"]
	var depths: PackedFloat32Array = projection["depths"]
	var seen: int = 0
	var hidden: int = 0
	for column: int in range(SILHOUETTE_COLUMNS):
		for row: int in range(SILHOUETTE_ROWS):
			var screen: Vector2 = (
				bounds.position
				+ (
					bounds.size
					* Vector2((column + 0.5) / SILHOUETTE_COLUMNS, (row + 0.5) / SILHOUETTE_ROWS)
				)
			)
			var depth: float = _cylinder_depth(screen, view, base, radius, height)
			if is_inf(depth):
				continue
			seen += 1
			for triangle: int in candidates:
				if _covers(corners, depths, triangle, screen, depth):
					hidden += 1
					break
	return float(hidden) / seen if seen > 0 else 0.0


#endregion

#region Private helpers


## The buckets a screen rectangle overlaps.
static func _buckets_over(bounds: Rect2) -> Array[Vector2i]:
	var first: Vector2i = Vector2i((bounds.position / BUCKET_SIZE).floor())
	var last: Vector2i = Vector2i((bounds.end / BUCKET_SIZE).floor())
	var out: Array[Vector2i] = []
	for x: int in range(first.x, last.x + 1):
		for y: int in range(first.y, last.y + 1):
			out.append(Vector2i(x, y))
	return out


## Figure positions on the far side of the footprint from the camera, whose whole base is
## clear of it, out to `reach` from its edge.
static func _far_side_positions(
	footprint: Vector2, radius: float, reach: float, view: Basis
) -> Array[Vector2]:
	var half: Vector2 = footprint * 0.5
	var away: Vector2 = Vector2(view.z.x, view.z.z)
	var steps: Vector2i = Vector2i(((half + Vector2(reach, reach)) / POSITION_STEP).ceil())
	var out: Array[Vector2] = []
	for i: int in range(-steps.x, steps.x + 1):
		for j: int in range(-steps.y, steps.y + 1):
			var p: Vector2 = Vector2(i, j) * POSITION_STEP
			var outside: Vector2 = (p.abs() - half).max(Vector2.ZERO)
			var clearance: float = outside.length()
			if clearance >= radius and clearance <= reach and p.dot(away) > 0.0:
				out.append(p)
	return out


## The depth at which the line of sight through screen point `screen` first meets the figure,
## or INF if it misses. The figure is a vertical cylinder on `base`; looking down, a line of
## sight enters it through the top cap or the side, never the bottom.
static func _cylinder_depth(
	screen: Vector2, view: Basis, base: Vector3, radius: float, height: float
) -> float:
	var origin: Vector3 = view.x * screen.x + view.y * screen.y - base
	var direction: Vector3 = view.z
	var best: float = INF
	# Side: |origin.xz + t·direction.xz| = radius, the nearer root.
	var a: float = direction.x * direction.x + direction.z * direction.z
	var b: float = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c: float = origin.x * origin.x + origin.z * origin.z - radius * radius
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant >= 0.0:
		var t: float = (-b - sqrt(discriminant)) / (2.0 * a)
		var y: float = origin.y + t * direction.y
		if y >= 0.0 and y <= height:
			best = t
	# Top cap.
	var t_top: float = (height - origin.y) / direction.y
	var on_top: Vector3 = origin + direction * t_top
	if Vector2(on_top.x, on_top.z).length_squared() <= radius * radius:
		best = minf(best, t_top)
	# `origin` lies on the screen plane through the world origin, so t is already a depth on
	# the same scale as the projected triangles'.
	return best


## Whether projected triangle `triangle` covers `screen` nearer the camera than `depth`.
static func _covers(
	corners: PackedVector2Array,
	depths: PackedFloat32Array,
	triangle: int,
	screen: Vector2,
	depth: float
) -> bool:
	var i: int = triangle * 3
	var weights: Vector3 = _barycentric(screen, corners[i], corners[i + 1], corners[i + 2])
	if weights.x < 0.0 or weights.y < 0.0 or weights.z < 0.0:
		return false
	return weights.x * depths[i] + weights.y * depths[i + 1] + weights.z * depths[i + 2] < depth


## Barycentric weights of `p` in triangle a-b-c; a degenerate (edge-on) triangle covers
## nothing.
static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var area: float = (b - a).cross(c - a)
	if is_zero_approx(area):
		return -Vector3.ONE
	var wb: float = (p - a).cross(c - a) / area
	var wc: float = (b - a).cross(p - a) / area
	return Vector3(1.0 - wb - wc, wb, wc)

#endregion
