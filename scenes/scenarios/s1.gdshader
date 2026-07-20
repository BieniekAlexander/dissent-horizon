shader_type spatial;

// Terrain shader (steps 1-4 of the terrain-visuals plan).
//
// Per-cell tile identity is baked into the mesh's vertex data by HeightmapMeshGenerator:
//   COLOR.rgb = the cell's TileType.map_color (the flat-colour fallback).
//   COLOR.a   = the tile-type index / 255 (selects the Texture2DArray layer below).
//   UV        = per-cell 0..1 (a per-type texture maps once per cell).
//   UV2       = global 0..1 across the map (reserved for whole-map overlays: AO, minimap).
//
// tile_textures packs one layer per TileType (layer index == tile index); tile_has_texture[i]
// is 1.0 for types that supplied a real texture and 0.0 for the rest. A cell shows its texture
// where one exists and its flat map_color otherwise, so partially-textured catalogs Just Work.
// When tile_count == 0 (no catalog, or no type has a texture yet) everything falls back to
// the flat colour — that is the steps 1-3 baseline.

render_mode cull_back, specular_disabled;

const int MAX_TILE_TYPES = 256; // tile index is one byte

uniform sampler2DArray tile_textures : source_color, filter_linear, repeat_disable;
uniform int tile_count = 0;
uniform float tile_has_texture[MAX_TILE_TYPES];

// Fog of war, sampled per fragment by WORLD position so the shroud conforms to terrain height
// instead of floating as a flat plane. Fog.gd (the active commander's fog) drives these:
//   fog_texture : top-down visibility, r = 0 in-sight .. 0.5 explored .. 1 unseen.
//   fog_rect    : (center.x, center.z, half_w, half_d) mapping world XZ -> fog UV in [0,1].
//   fog_enabled : 0 disables (no fog driver / debug view / omniscient) -> terrain full-bright.
uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	// COLOR.a == 1.0 (index 255) is the "void" sentinel for non-passable obstacle cells: keep
	// COLOR.rgb (black) and skip texturing. Real tiles use small indices (a << 1.0).
	if (COLOR.a < 0.999 && tile_count > 0) {
		int idx = clamp(int(COLOR.a * 255.0 + 0.5), 0, tile_count - 1);
		if (tile_has_texture[idx] > 0.5) {
			albedo = texture(tile_textures, vec3(UV, float(idx))).rgb;
		}
	}
	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(v_world.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(v_world.z - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		float shroud = texture(fog_texture, fuv).r;  // 0 clear .. 1 unseen
		albedo *= (1.0 - shroud);                    // dim explored, black-out unseen
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
