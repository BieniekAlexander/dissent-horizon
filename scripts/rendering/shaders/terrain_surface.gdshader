shader_type spatial;

// Draws the AUTHORED SURFACE MESH (Map.terrain_source_mesh) as the terrain.
//
// The older terrain shader (scenes/scenarios/s1.gdshader) reads tile identity from vertex
// COLOR, which HeightmapMeshGenerator bakes in per cell. A source mesh has no such data — its
// vertices belong to the modelled surface, not to the grid — so identity is looked up PER
// FRAGMENT by world XZ instead, out of a cell-indexed texture. That is the whole difference,
// and it is what lets the drawn geometry be smooth while the gameplay grid stays cell-sized.
//
// Two things are deliberately NOT taken from the cell grid, because sampling them per cell is
// exactly what makes a smooth surface look jagged again:
//
//   * THE PLAY BOUNDARY is tested analytically against the play rectangle (a 45-degree
//     rotated rectangle in world XZ), so the edge of the world is a clean straight line
//     rather than a staircase at cell resolution.
//   * IMPASSABILITY is BINARY and comes from the cell_data steep flag, which is literally the
//     test the navmesh runs (corner spread vs TerrainGrid.MAX_SLOPE_DIFF). An impassable cell
//     is rock, and an ink line on the passable side marks the boundary exactly. Everything
//     else — slope, height, cavity — is free to be soft; the yes/no fact never is. An earlier
//     version inferred steepness from the interpolated surface normal — smooth, but both
//     soft-edged and subtly offset, since vertex normals are a central difference spanning
//     neighbouring cells.
//
// The shading itself is shared with s1.gdshader: terrain_common.gdshaderinc.

render_mode cull_disabled, specular_disabled;

#include "res://scripts/rendering/shaders/terrain_common.gdshaderinc"

// The play rectangle, in its own frame: centre, two perpendicular unit axes, half-extents.
// Fragments outside it are discarded, so the playable area reads against the background the
// same way omitted cells do on a generated mesh.
uniform vec2 play_center = vec2(0.0);
uniform vec2 play_axis_a = vec2(1.0, 0.0);
uniform vec2 play_axis_b = vec2(0.0, 1.0);
uniform vec2 play_half = vec2(1e9);
uniform float play_bounds_enabled = 1.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (play_bounds_enabled > 0.5) {
		vec2 d = v_world.xz - play_center;
		if (abs(dot(d, play_axis_a)) > play_half.x || abs(dot(d, play_axis_b)) > play_half.y) {
			discard;
		}
	}

	vec2 uv = (v_world.xz - terrain_rect.xy) / terrain_rect.zw;
	int idx = 0;
	float impassable = 0.0;
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec2 cell = texture(cell_data, uv).rg;
		idx = clamp(int(cell.r * 255.0 + 0.5), 0, MAX_TILE_TYPES - 1);
		impassable = step(0.5, cell.g);
	}

	// The surface mesh carries its own authored normals; the height field's are only a
	// fallback for a material that has heights but no usable mesh normal.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = th_apply_fog(th_shade(v_world, idx, impassable, uv, n), v_world.xz);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
