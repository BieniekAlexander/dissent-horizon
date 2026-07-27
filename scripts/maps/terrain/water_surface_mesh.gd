@tool
class_name WaterSurfaceMesh
extends RefCounted

## Builds the flat plane a WaterBasin is drawn as: one quad per covered cell, all at the
## body's water level, in the heightmap's local frame (the same frame HeightmapMeshGenerator
## builds in, so the two line up without a transform of their own).
##
## The only thing baked into the geometry is HOW DEEP THE WATER IS at each corner, as a
## 0..1 shade factor in vertex COLOR.r. Everything else the surface shows — the two blues,
## the lithium tint, how much charge is left — is a shader uniform, because those change
## while the mesh does not: a pond drains during a match and must fade from its tint to
## plain blue without regenerating a single vertex.

#region Constants
## Depth at which the shade factor starts and finishes ramping, as multiples of WADE_DEPTH.
## Centred on the wading threshold so the colour change lands where the navmesh boundary
## actually is, and spread over a band so the boundary reads as a shoreline rather than as
## a painted-on line. The classification itself is binary — this is only the picture of it.
const _SHADE_RAMP_START: float = 0.5
const _SHADE_RAMP_END: float = 1.5

## How far above the GROUND a water vertex is pushed when the water level alone would leave it
## at or under the terrain.
##
## The water surface is a passability READOUT — light blue is ground a unit walks through, dark
## blue is ground it cannot — so it has to be legible even where the water is thinner than the
## terrain's own relief. Left at the plain level, a pond 0.07 deep on ground that steps 0.15 is
## geometrically inside the steps around it and draws ZERO pixels from the game's camera angle,
## measured. A physical water plane would do exactly that; a readout must not.
##
## Small enough to be invisible as a height (it is centimetres), large enough to clear the
## z-fighting band and the mismatch between the water quad's triangulation and the authored
## terrain mesh's.
const GROUND_CLEARANCE: float = 0.06
#endregion

#region Public API
## The water plane for `a_basin` over `a_terrain`, or null when the basin covers nothing.
##
## Corner depths are read from the heightmap CORNER heights rather than from the per-cell
## means the basin classifies with: adjacent quads share a corner, and a shared corner has
## to produce one shade from both sides or the gradient creases along every cell boundary.
static func build(a_basin: WaterBasin, a_terrain: TerrainData) -> ArrayMesh:
	var cells: Array[Vector2i] = a_basin.covered_cells()
	if cells.is_empty() or a_terrain == null:
		return null

	var half_width: float = (a_terrain.map_width() - 1) * 0.5
	var half_depth: float = (a_terrain.map_depth() - 1) * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for cell: Vector2i in cells:
		var base: int = verts.size()
		# The quad is lifted as a WHOLE, above the highest corner of its own cell.
		#
		# Clamping each vertex on its own was not enough: it lifted the shoreline ring clear but
		# left the interior at the plain level, where the rim around it still hid it — the pond
		# drew as a dashed outline with nothing inside. A quad has to clear the cell it covers,
		# not just the corner it touches, or part of it stays inside the ground.
		var highest: float = -INF
		for corner: Vector2i in [
			cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)
		]:
			highest = maxf(highest, a_terrain.corner_height(corner))
		var quad_y: float = maxf(a_basin.level, highest + GROUND_CLEARANCE)
		# Wound the same way HeightmapMeshGenerator winds its cells, so the surface faces up.
		for corner: Vector2i in [
			cell, cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1)
		]:
			# Flat at the water level over open water; riding just above the ground wherever the
			# level alone would bury it. SHADE IS UNAFFECTED — it is computed from the true
			# depth, so the colour still reports real passability while the geometry stays
			# visible. `level` remains the only number gameplay reads.
			var ground: float = a_terrain.corner_height(corner)
			verts.append(Vector3(corner.x - half_width, quad_y, corner.y - half_depth))
			normals.append(Vector3.UP)
			uvs.append(Vector2(corner.x - cell.x, corner.y - cell.y))
			var shade: float = shade_factor(a_basin.level - ground)
			colors.append(Color(shade, 0.0, 0.0, 1.0))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 0 where the water is shallow enough to wade, 1 where it is well past wading depth, and a
## smooth ramp across the threshold. Exposed so a test can pin the ramp against WADE_DEPTH
## rather than against the two literals.
static func shade_factor(a_depth: float) -> float:
	return smoothstep(
		WaterBasin.WADE_DEPTH * _SHADE_RAMP_START,
		WaterBasin.WADE_DEPTH * _SHADE_RAMP_END,
		a_depth
	)
#endregion
