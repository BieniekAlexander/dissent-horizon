shader_type spatial;

// Terrain shader for the quad-per-cell mesh HeightmapMeshGenerator builds from the heightfield.
//
// Cell identity (tile type, the steep flag) is looked up per fragment from cell_data by world
// XZ, exactly as terrain_surface.gdshader does, and all shading is shared with it through
// terrain_common.gdshaderinc. The mesh's own vertex COLOR (flat map colour, type index in
// alpha) is only the fallback for a material that was never handed cell_data.
//
// The normal is taken from the height FIELD, not the mesh: the mesh is one flat quad per cell,
// and lighting its facets renders a smooth grade as a staircase. Cliffs stay sharp anyway,
// because they are coloured by the per-cell steep flag rather than by the normal.

render_mode cull_back, specular_disabled;

#include "res://scripts/rendering/shaders/terrain_common.gdshaderinc"

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (v_world.xz - terrain_rect.xy) / terrain_rect.zw;
	int idx = clamp(int(COLOR.a * 255.0 + 0.5), 0, MAX_TILE_TYPES - 1);
	float impassable = COLOR.a > 0.999 ? 1.0 : 0.0;
	if (has_heights > 0.5) {
		vec2 cell = texture(cell_data, uv).rg;
		idx = clamp(int(cell.r * 255.0 + 0.5), 0, MAX_TILE_TYPES - 1);
		impassable = step(0.5, cell.g);
	}

	vec3 n = has_heights > 0.5 ? th_normal(v_world.xz)
		: normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	NORMAL = normalize((VIEW_MATRIX * vec4(th_grain_normal(v_world.xz, n, impassable), 0.0)).xyz);
	ALBEDO = th_apply_fog(th_shade(v_world, idx, impassable, uv, n), v_world.xz);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
