class_name MeshPrimitives
extends RefCounted

## Low-poly convex solids as flat triangle lists — three vertices per triangle, no index
## buffer — for the generated structure models (generate_structure_models.gd).
##
## Every solid is convex, so winding is decided by geometry rather than by care: each face is
## turned away from the solid's centre, CLOCKWISE seen from outside, which is Godot's front
## face. A model is a concatenation of solids; nothing here welds or shares vertices, so
## every face shades flat, which is the look these placeholders want.

#region Public API


## An axis-aligned box between two opposite corners.
static func box(from: Vector3, to: Vector3) -> PackedVector3Array:
	return prism(_rectangle(Vector2(from.x, from.z), Vector2(to.x, to.z)), from.y, to.y)


## A convex XZ outline extruded straight up from `bottom` to `top`.
static func prism(outline: PackedVector2Array, bottom: float, top: float) -> PackedVector3Array:
	var corners: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in outline:
		corners.append(Vector3(point.x, bottom, point.y))
	for point: Vector2 in outline:
		corners.append(Vector3(point.x, top, point.y))
	return _solid(corners, _extrusion_faces(outline.size()))


## A regular `sides`-gon tapering from `bottom_radius` to `top_radius`. A top radius of zero
## makes a cone or pyramid; `phase_degrees` turns the outline, so a square can sit flat to
## the axes (45) rather than on its corners (0).
static func frustum(
	centre: Vector2,
	bottom_radius: float,
	top_radius: float,
	bottom: float,
	top: float,
	sides: int,
	phase_degrees: float = 0.0
) -> PackedVector3Array:
	var lower: PackedVector2Array = regular_polygon(centre, bottom_radius, sides, phase_degrees)
	if top_radius <= 0.0:
		var corners: PackedVector3Array = PackedVector3Array(
			Array(lower).map(func(p: Vector2) -> Vector3: return Vector3(p.x, bottom, p.y))
		)
		corners.append(Vector3(centre.x, top, centre.y))
		var faces: Array[PackedInt32Array] = [_reversed_range(sides)]
		for i: int in range(sides):
			faces.append(PackedInt32Array([i, (i + 1) % sides, sides]))
		return _solid(corners, faces)
	var upper: PackedVector2Array = regular_polygon(centre, top_radius, sides, phase_degrees)
	var all_corners: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in lower:
		all_corners.append(Vector3(point.x, bottom, point.y))
	for point: Vector2 in upper:
		all_corners.append(Vector3(point.x, top, point.y))
	return _solid(all_corners, _extrusion_faces(sides))


static func cylinder(
	centre: Vector2, radius: float, bottom: float, top: float, sides: int
) -> PackedVector3Array:
	return frustum(centre, radius, radius, bottom, top, sides)


## A square pyramid sitting flat to the axes, `half_width` from its centre to each side.
static func pyramid(
	centre: Vector2, half_width: float, bottom: float, top: float
) -> PackedVector3Array:
	return frustum(centre, half_width * sqrt(2.0), 0.0, bottom, top, 4, 45.0)


## A hemisphere of stacked frustums, `rings` bands from the equator to the pole.
static func dome(centre: Vector3, radius: float, rings: int, sides: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for ring: int in range(rings):
		var lower_angle: float = PI * 0.5 * ring / rings
		var upper_angle: float = PI * 0.5 * (ring + 1) / rings
		out.append_array(
			frustum(
				Vector2(centre.x, centre.z),
				radius * cos(lower_angle),
				radius * cos(upper_angle),
				centre.y + radius * sin(lower_angle),
				centre.y + radius * sin(upper_angle),
				sides
			)
		)
	return out


## A hipped roof over the rectangle `from`–`to` (corners at the eaves height `from.y`): a
## ridge at `ridge_height`, running along the rectangle's longer side and stopping
## `hip_inset` short of each end, so every face slopes — no gable wall stands at full height
## at the building's edge.
static func hip_roof(
	from: Vector3, to: Vector3, ridge_height: float, hip_inset: float
) -> PackedVector3Array:
	var eaves: PackedVector3Array = PackedVector3Array(
		[
			Vector3(from.x, from.y, from.z),
			Vector3(to.x, from.y, from.z),
			Vector3(to.x, from.y, to.z),
			Vector3(from.x, from.y, to.z),
		]
	)
	var middle: Vector2 = Vector2((from.x + to.x) * 0.5, (from.z + to.z) * 0.5)
	var ridge_along_x: bool = absf(to.x - from.x) >= absf(to.z - from.z)
	var ridge: PackedVector3Array = (
		PackedVector3Array(
			[
				Vector3(minf(from.x, to.x) + hip_inset, ridge_height, middle.y),
				Vector3(maxf(from.x, to.x) - hip_inset, ridge_height, middle.y),
			]
		)
		if ridge_along_x
		else PackedVector3Array(
			[
				Vector3(middle.x, ridge_height, minf(from.z, to.z) + hip_inset),
				Vector3(middle.x, ridge_height, maxf(from.z, to.z) - hip_inset),
			]
		)
	)
	var corners: PackedVector3Array = eaves + ridge
	# Each eave edge rises to the ridge end nearer it; a long side's face is a trapezium, an
	# end's a triangle. Which ridge end is nearer each corner is decided by distance, so the
	# faces come out right whichever axis the ridge runs along.
	var near_ridge: Callable = func(corner: int) -> int:
		var to_first: float = corners[corner].distance_squared_to(corners[4])
		var to_second: float = corners[corner].distance_squared_to(corners[5])
		return 4 if to_first <= to_second else 5
	var faces: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 2, 3])]
	for edge: int in range(4):
		var a: int = edge
		var b: int = (edge + 1) % 4
		var ridge_a: int = near_ridge.call(a)
		var ridge_b: int = near_ridge.call(b)
		faces.append(
			(
				PackedInt32Array([a, b, ridge_b])
				if ridge_a == ridge_b
				else PackedInt32Array([a, b, ridge_b, ridge_a])
			)
		)
	return _solid(corners, faces)


## A square-section bar of `width` from `start` to `end` — legs, barrels, girders, masts.
static func beam(start: Vector3, end: Vector3, width: float) -> PackedVector3Array:
	var axis: Vector3 = (end - start).normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var side: Vector3 = axis.cross(reference).normalized() * width * 0.5
	var other: Vector3 = axis.cross(side).normalized() * width * 0.5
	var ring: Array[Vector3] = [side + other, side - other, -side - other, -side + other]
	var corners: PackedVector3Array = PackedVector3Array()
	for offset: Vector3 in ring:
		corners.append(start + offset)
	for offset: Vector3 in ring:
		corners.append(end + offset)
	return _solid(corners, _extrusion_faces(ring.size()))


## `sides` points evenly round a circle in the XZ plane.
static func regular_polygon(
	centre: Vector2, radius: float, sides: int, phase_degrees: float = 0.0
) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(sides):
		var angle: float = TAU * i / sides + deg_to_rad(phase_degrees)
		out.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return out


## Every vertex of `triangles` moved by `xform` — how a solid is tilted or turned.
static func transformed(triangles: PackedVector3Array, xform: Transform3D) -> PackedVector3Array:
	return PackedVector3Array(Array(triangles).map(func(v: Vector3) -> Vector3: return xform * v))


#endregion

#region Private helpers


static func _rectangle(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]
	)


## The faces of an outline of `n` corners joined to a copy of itself: corners 0..n-1 are one
## cap and n..2n-1 the other, in the same order.
static func _extrusion_faces(n: int) -> Array[PackedInt32Array]:
	var faces: Array[PackedInt32Array] = [_reversed_range(n), PackedInt32Array(range(n, 2 * n))]
	for i: int in range(n):
		var j: int = (i + 1) % n
		faces.append(PackedInt32Array([i, j, j + n, i + n]))
	return faces


static func _reversed_range(n: int) -> PackedInt32Array:
	return PackedInt32Array(range(n - 1, -1, -1))


## Triangulates each (convex, planar) face as a fan and winds every triangle clockwise seen
## from outside the solid — the solid being convex, "outside" is away from its centre.
static func _solid(
	corners: PackedVector3Array, faces: Array[PackedInt32Array]
) -> PackedVector3Array:
	var centre: Vector3 = (
		Array(corners).reduce(
			func(sum: Vector3, v: Vector3) -> Vector3: return sum + v, Vector3.ZERO
		)
		/ corners.size()
	)
	var out: PackedVector3Array = PackedVector3Array()
	for face: PackedInt32Array in faces:
		var outward: Vector3 = _face_centre(corners, face) - centre
		for k: int in range(1, face.size() - 1):
			var a: Vector3 = corners[face[0]]
			var b: Vector3 = corners[face[k]]
			var c: Vector3 = corners[face[k + 1]]
			# cross(b - a, c - a) points out of a counter-clockwise triangle, so clockwise
			# from outside is the order whose cross product points INWARD.
			out.append_array(
				PackedVector3Array(
					[a, c, b] if (b - a).cross(c - a).dot(outward) > 0.0 else [a, b, c]
				)
			)
	return out


static func _face_centre(corners: PackedVector3Array, face: PackedInt32Array) -> Vector3:
	return (
		Array(face).reduce(
			func(sum: Vector3, i: int) -> Vector3: return sum + corners[i], Vector3.ZERO
		)
		/ face.size()
	)

#endregion
