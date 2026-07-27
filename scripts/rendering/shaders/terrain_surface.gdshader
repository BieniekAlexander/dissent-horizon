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
//   * CLIFF SHADING is BINARY and comes from the cell_data steep flag, which is literally the
//     test the navmesh runs (corner spread vs TerrainGrid.MAX_SLOPE_DIFF). Green means a unit
//     can walk here; black means it cannot. There is deliberately no gradient: impassability is
//     a yes/no fact about a cell, and a soft ramp between the two states misreports where the
//     boundary actually is. An earlier version inferred steepness from the interpolated surface
//     normal — smooth, but both soft-edged and subtly offset, since vertex normals are a
//     central difference spanning neighbouring cells.

render_mode cull_disabled, specular_disabled;

const int MAX_TILE_TYPES = 256;

// Cell-indexed per-cell data. R = tile type index / 255, G = 1 when the cell is too steep to
// traverse. Nearest-filtered: both are per-cell facts and must not blend across boundaries.
uniform sampler2D cell_data : filter_nearest, repeat_disable;
// (min_x, min_z, size_x, size_z) of the cell grid in world XZ — maps world -> cell_data UV.
uniform vec4 terrain_rect = vec4(0.0, 0.0, 1.0, 1.0);

// Flat colour per tile type, indexed by the tile index in cell_data.
uniform vec4 tile_colors[MAX_TILE_TYPES];
uniform sampler2DArray tile_textures : source_color, filter_linear, repeat_enable;
uniform int tile_count = 0;
uniform float tile_has_texture[MAX_TILE_TYPES];
// World units per texture tile, so a repeating ground texture is scaled in WORLD space
// rather than per cell (a source mesh has no per-cell UVs to key off).
uniform float texture_scale = 4.0;

// The play rectangle, in its own frame: centre, two perpendicular unit axes, half-extents.
// Fragments outside it are discarded, so the playable area reads against the background the
// same way omitted cells do on a generated mesh.
uniform vec2 play_center = vec2(0.0);
uniform vec2 play_axis_a = vec2(1.0, 0.0);
uniform vec2 play_axis_b = vec2(0.0, 1.0);
uniform vec2 play_half = vec2(1e9);
uniform float play_bounds_enabled = 1.0;

// Colour for ground a unit cannot traverse.
uniform vec4 cliff_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);

// Fog of war, sampled by WORLD position so the shroud conforms to terrain height. Same
// contract as s1.gdshader: r = 0 in sight .. 0.5 explored .. 1 unseen.
uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;

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

	vec3 albedo = tile_colors[idx].rgb;
	if (tile_count > 0 && idx < tile_count && tile_has_texture[idx] > 0.5) {
		albedo = texture(tile_textures, vec3(v_world.xz / texture_scale, float(idx))).rgb;
	}

	// Untraversable ground reads as rock — a hard switch, not a blend.
	albedo = mix(albedo, cliff_color.rgb, impassable);

	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(v_world.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(v_world.z - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		albedo *= (1.0 - texture(fog_texture, fuv).r);
	}

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
