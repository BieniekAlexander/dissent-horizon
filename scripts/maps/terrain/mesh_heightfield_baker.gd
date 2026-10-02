@tool
class_name MeshHeightfieldBaker
extends RefCounted

## Derives a TerrainData heightfield from an arbitrary triangle Mesh — the "author the
## surface in a modelling tool, play on a heightfield" path.
##
## This is a ONE-WAY IMPORT, the same shape as tools/spec_import: the mesh is an authoring
## input, the baked `heights` / `tile_types` layers are the artifact, and everything
## downstream (TerrainGrid, NavManager, HeightmapMeshGenerator, Map's coordinate helpers,
## fog, the minimap) reads those layers exactly as it does for brush-painted terrain. No
## runtime code learns that a mesh was involved.
##
## WHY a heightfield at all, when the mesh is right there: the game constrains the world to a
## single playable surface with structures on a grid, so the surface must stay a height
## FUNCTION over XZ — one Y per (x, z). An arbitrary mesh's only representational advantage
## is exactly what that forbids (overhangs, caves, stacked floors). Measured, a mesh queried
## by raycast costs ~3.2x a bilinear heightfield read per height query, and terrain_height_at
## runs thousands of times per physics tick. So the mesh buys no representational power and
## costs the hottest arithmetic path in the game; baking keeps the sculpted surface and the
## O(1) query both.
##
## NO PHYSICS. Sampling is a pure triangle rasterization rather than a downward raycast, so
## the bake runs identically in the editor, in a headless tool script and in a GUT test, with
## no World3D, no collider and no frame to wait for. It is also deterministic, which a
## physics query is not obliged to be.

#region Constants
## Triangles whose XZ-projected area is below this contribute no height and are skipped.
##
## This is what makes a VERTICAL WALL work rather than break: a cylinder's side wall projects
## to a zero-area sliver in XZ, so it can never be the surface at any (x, z) — the cap above
## it or the ground beside it is. Skipping them is therefore correct, not a tolerance hack,
## and it is why a plateau can be modelled with genuinely vertical sides and still bake into
## a clean one-cell cliff.
const MIN_TRIANGLE_XZ_AREA: float = 1e-9

## Barycentric slack when testing whether a corner lies in a triangle, in barycentric units.
## Corners sitting exactly on a shared edge must land on SOMETHING; without slack, floating
## point drops a scattering of them and the bake pits the surface with holes.
const BARYCENTRIC_EPSILON: float = 1e-6
#endregion


## What a bake produced. `heights` is always full-size and safe to assign straight to
## TerrainData.heights; `hit` records which corners the mesh actually covered, which is the
## interesting part for a surface that does not fill its grid (an island, a disc).
class Result:
	extends RefCounted
	## Per-corner heights, size dims.x * dims.y, index z*W + x — TerrainData.heights' layout.
	var heights: PackedFloat32Array = PackedFloat32Array()
	## Per-corner coverage, same indexing. 1 = a triangle was found over/under this corner.
	var hit: PackedByteArray = PackedByteArray()
	## Triangles considered, and those skipped as vertical/degenerate in XZ.
	var triangle_count: int = 0
	var skipped_triangles: int = 0

	func corner_count() -> int:
		return hit.size()

	func hit_count() -> int:
		var n: int = 0
		for b: int in hit:
			n += b
		return n

	## True when the mesh covered every corner of the grid — i.e. the surface is a full
	## rectangle and no cell needs to be voided.
	func is_fully_covered() -> bool:
		return hit_count() == hit.size()


## Bake `mesh` into a corner heightfield for a `dims` corner grid.
##
## Coordinates: the grid is centred on the origin exactly as HeightMapShape3D centres its
## own (corner (0,0) at local (-(W-1)/2, y, -(D-1)/2)), one unit per cell, so the mesh must
## be supplied in that same local frame. `mesh_to_local` is applied to every vertex first,
## which is where a mesh authored at a different scale or offset gets fitted.
##
## Corners the mesh does not cover keep `hit == 0`; their heights are filled from the
## nearest covered corner (see _fill_uncovered) so the derived collider extends flat outward
## instead of dropping to a spurious cliff at the surface's edge.
static func bake(mesh: Mesh, dims: Vector2i, mesh_to_local: Transform3D = Transform3D()) -> Result:
	var result := Result.new()
	var w: int = dims.x
	var d: int = dims.y
	result.heights.resize(w * d)
	result.hit.resize(w * d)
	if mesh == null or w < 2 or d < 2:
		return result

	var half_w: float = (w - 1) * 0.5
	var half_d: float = (d - 1) * 0.5

	for surface: int in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		# ARRAY_INDEX is null (not an empty array) on an unindexed surface, so it cannot be
		# assigned to a typed PackedInt32Array without this check.
		var raw_index: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if raw_index != null:
			idx = raw_index
		var indexed: bool = not idx.is_empty()
		var count: int = idx.size() if indexed else verts.size()
		var i: int = 0
		while i + 2 < count:
			var a: Vector3 = mesh_to_local * verts[idx[i] if indexed else i]
			var b: Vector3 = mesh_to_local * verts[idx[i + 1] if indexed else i + 1]
			var c: Vector3 = mesh_to_local * verts[idx[i + 2] if indexed else i + 2]
			result.triangle_count += 1
			if not _rasterize(a, b, c, result, w, d, half_w, half_d):
				result.skipped_triangles += 1
			i += 3

	_fill_uncovered(result, w, d)
	return result


## Stamp one triangle onto every grid corner its XZ projection covers, keeping the HIGHEST
## surface found at each corner.
##
## Scatter (walk the triangle's corner-space bounding box) rather than gather (search
## triangles per corner) so the bake needs no spatial index at all: total work is proportional
## to the area the mesh covers, and a finely tessellated mesh has small triangles that each
## touch few corners.
##
## "Highest wins" is the rule that collapses a solid to a surface. A modelled plateau is a
## closed body with a floor under its cap, and the playable surface is the top of it — so a
## mesh may be a watertight solid rather than a carefully-authored open sheet.
##
## Returns false when the triangle was skipped as vertical/degenerate in XZ.
static func _rasterize(
	a: Vector3, b: Vector3, c: Vector3, result: Result, w: int, d: int, half_w: float, half_d: float
) -> bool:
	# Corner-index space: corner (cx, cz) sits at local (cx - half_w, y, cz - half_d), so
	# shifting by the half-extents puts the triangle in the same space as the loop counters.
	var ax: float = a.x + half_w
	var az: float = a.z + half_d
	var bx: float = b.x + half_w
	var bz: float = b.z + half_d
	var cx: float = c.x + half_w
	var cz: float = c.z + half_d

	# Twice the signed XZ area. Zero means the triangle is edge-on from above — a vertical
	# wall — and it is not the surface anywhere.
	var area2: float = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
	if absf(area2) < MIN_TRIANGLE_XZ_AREA:
		return false
	var inv_area2: float = 1.0 / area2

	var min_x: int = maxi(0, ceili(minf(ax, minf(bx, cx)) - 1.0))
	var max_x: int = mini(w - 1, floori(maxf(ax, maxf(bx, cx)) + 1.0))
	var min_z: int = maxi(0, ceili(minf(az, minf(bz, cz)) - 1.0))
	var max_z: int = mini(d - 1, floori(maxf(az, maxf(bz, cz)) + 1.0))

	for gz: int in range(min_z, max_z + 1):
		var pz: float = float(gz)
		for gx: int in range(min_x, max_x + 1):
			var px: float = float(gx)
			# Barycentric weights of (px, pz) against the XZ projection.
			var wa: float = ((bx - px) * (cz - pz) - (cx - px) * (bz - pz)) * inv_area2
			var wb: float = ((cx - px) * (az - pz) - (ax - px) * (cz - pz)) * inv_area2
			var wc: float = 1.0 - wa - wb
			if wa < -BARYCENTRIC_EPSILON or wb < -BARYCENTRIC_EPSILON or wc < -BARYCENTRIC_EPSILON:
				continue
			var y: float = wa * a.y + wb * b.y + wc * c.y
			var at: int = gz * w + gx
			if result.hit[at] == 0 or y > result.heights[at]:
				result.heights[at] = y
				result.hit[at] = 1
	return true


## Give every uncovered corner the height of the nearest covered one, by multi-source BFS
## over the 4-neighbourhood from the covered set.
##
## The cells around an uncovered corner are voided by the caller, so this never changes what
## is playable — it decides what the DERIVED artifacts do off the surface's edge. Leaving the
## gaps at 0.0 puts a full-height cliff along the rim of any raised island in the picking
## collider and in the generated mesh's normals; extending the edge flat outward is quiet.
##
## A grid with no coverage at all is left flat at 0.0.
static func _fill_uncovered(result: Result, w: int, d: int) -> void:
	var queue: PackedInt32Array = PackedInt32Array()
	var filled: PackedByteArray = result.hit.duplicate()
	for i: int in filled.size():
		if filled[i] == 1:
			queue.append(i)
	if queue.is_empty() or queue.size() == filled.size():
		return
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		var x: int = at % w
		var z: int = at / w
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + step.x
			var nz: int = z + step.y
			if nx < 0 or nx >= w or nz < 0 or nz >= d:
				continue
			var n: int = nz * w + nx
			if filled[n] == 1:
				continue
			filled[n] = 1
			result.heights[n] = result.heights[at]
			queue.append(n)
