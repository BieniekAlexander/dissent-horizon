class_name HeightmapRay
extends RefCounted

## WHETHER A SEGMENT TOUCHES A HEIGHTMAP'S SURFACE, without the physics server — the terrain
## half of Attack's line of fire, read in the decide pass (gdd/systems/commands/
## the-simulation-step.md §The spatial index).
##
## The surface is the one a HeightMapShape3D collides as: corner (i, j) at local
## (i - (w-1)/2, map_data[j*w + i], j - (d-1)/2), each cell split into two triangles along
## `DIAGONAL`. The segment is walked cell by cell in the XZ plane (Amanatides–Woo), a cell is
## skipped when the segment passes wholly above its highest corner, and only a crossing from
## above counts. That matches the physics server for every segment that STARTS above the
## surface — the only kind Attack casts, both ends lifted off the ground — and is pinned by
## tests/test_HeightmapRay.gd; for a segment starting under it the server is not consistent
## (it reports some crossings from below and not others), and this does not follow it there.

## Which way each cell is split, as Godot's HeightMapShape3D splits it: the triangles
## (x, z)-(x+1, z)-(x, z+1) and (x+1, z)-(x+1, z+1)-(x, z+1), sharing the (x+1, z)-(x, z+1)
## edge. Pinned against the physics server by tests/test_HeightmapRay.gd.
const DIAGONAL_FROM_X1_Z0: bool = true


## Whether the segment `a_from` -> `a_to` (world space) touches `a_shape`, standing at
## `a_xform`.
static func hits(
	a_shape: HeightMapShape3D, a_xform: Transform3D, a_from: Vector3, a_to: Vector3
) -> bool:
	var to_local: Transform3D = a_xform.affine_inverse()
	var half_w: float = (a_shape.map_width - 1) * 0.5
	var half_d: float = (a_shape.map_depth - 1) * 0.5
	# Into grid space: x and z count corners from the minimum corner.
	var p: Vector3 = to_local * a_from + Vector3(half_w, 0.0, half_d)
	var q: Vector3 = to_local * a_to + Vector3(half_w, 0.0, half_d)
	var d: Vector3 = q - p
	var cell := Vector2i(floori(p.x), floori(p.z))
	var last := Vector2i(floori(q.x), floori(q.z))
	var step := Vector2i(signi(int(signf(d.x))), signi(int(signf(d.z))))
	var t_max := Vector2(_first_crossing(p.x, d.x), _first_crossing(p.z, d.z))
	var t_delta := Vector2(
		absf(1.0 / d.x) if d.x != 0.0 else INF, absf(1.0 / d.z) if d.z != 0.0 else INF
	)
	var t_enter: float = 0.0
	while true:
		var t_exit: float = minf(minf(t_max.x, t_max.y), 1.0)
		if _cell_hit(a_shape, cell, p, d, t_enter, t_exit):
			return true
		if cell == last or t_exit >= 1.0:
			return false
		t_enter = t_exit
		if t_max.x < t_max.y:
			cell.x += step.x
			t_max.x += t_delta.x
		else:
			cell.y += step.y
			t_max.y += t_delta.y
	return false


## The segment parameter at which it first crosses a whole-number grid line along one axis.
static func _first_crossing(a_start: float, a_delta: float) -> float:
	if a_delta > 0.0:
		return (floorf(a_start) + 1.0 - a_start) / a_delta
	if a_delta < 0.0:
		return (a_start - floorf(a_start)) / -a_delta
	return INF


## Whether the part of the segment between `a_t0` and `a_t1` touches cell `a_cell`'s triangles.
static func _cell_hit(
	a_shape: HeightMapShape3D,
	a_cell: Vector2i,
	a_p: Vector3,
	a_d: Vector3,
	a_t0: float,
	a_t1: float
) -> bool:
	var w: int = a_shape.map_width
	if a_cell.x < 0 or a_cell.y < 0 or a_cell.x >= w - 1 or a_cell.y >= a_shape.map_depth - 1:
		return false
	var data: PackedFloat32Array = a_shape.map_data
	var h00: float = data[a_cell.y * w + a_cell.x]
	var h10: float = data[a_cell.y * w + a_cell.x + 1]
	var h01: float = data[(a_cell.y + 1) * w + a_cell.x]
	var h11: float = data[(a_cell.y + 1) * w + a_cell.x + 1]
	var lowest_ray: float = minf(a_p.y + a_d.y * a_t0, a_p.y + a_d.y * a_t1)
	if lowest_ray > maxf(maxf(h00, h10), maxf(h01, h11)):
		return false
	var c00 := Vector3(a_cell.x, h00, a_cell.y)
	var c10 := Vector3(a_cell.x + 1, h10, a_cell.y)
	var c01 := Vector3(a_cell.x, h01, a_cell.y + 1)
	var c11 := Vector3(a_cell.x + 1, h11, a_cell.y + 1)
	if DIAGONAL_FROM_X1_Z0:
		return (
			_segment_hits_triangle(a_p, a_d, c00, c10, c01)
			or _segment_hits_triangle(a_p, a_d, c10, c11, c01)
		)
	return (
		_segment_hits_triangle(a_p, a_d, c00, c10, c11)
		or _segment_hits_triangle(a_p, a_d, c00, c11, c01)
	)


## Möller–Trumbore for the segment p + t·d, t in [0, 1], crossing a triangle downward.
static func _segment_hits_triangle(
	a_p: Vector3, a_d: Vector3, a_v0: Vector3, a_v1: Vector3, a_v2: Vector3
) -> bool:
	var e1: Vector3 = a_v1 - a_v0
	var e2: Vector3 = a_v2 - a_v0
	# Only a crossing from above counts: the surface's upward face is the one it collides by.
	var normal: Vector3 = e1.cross(e2)
	if normal.y < 0.0:
		normal = -normal
	if a_d.dot(normal) >= 0.0:
		return false
	var h: Vector3 = a_d.cross(e2)
	var det: float = e1.dot(h)
	if absf(det) < 1e-12:
		return false
	var inv: float = 1.0 / det
	var s: Vector3 = a_p - a_v0
	var u: float = inv * s.dot(h)
	if u < 0.0 or u > 1.0:
		return false
	var q: Vector3 = s.cross(e1)
	var v: float = inv * a_d.dot(q)
	if v < 0.0 or u + v > 1.0:
		return false
	var t: float = inv * e2.dot(q)
	return t >= 0.0 and t <= 1.0
