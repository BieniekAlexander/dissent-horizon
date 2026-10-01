shader_type spatial;

// Cosmetic props (DoodadLibrary meshes, drawn by MapDecorator's MultiMeshes): vertex colour,
// which the engine has already multiplied by the MultiMesh's per-instance tint, a slight sway for foliage, and the same fog of war as the terrain
// — a prop drawn over the shroud would give away the ground beneath it.

render_mode specular_disabled;

// Fog of war: same contract as terrain_common.gdshaderinc (r = 0 in sight .. 1 unseen).
uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;
// How far the top of a 1-unit-tall prop leans in the wind; 0 for rigid kinds (stone).
uniform float sway_amount = 0.0;

varying vec3 v_world;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = TIME * 1.3 + origin.x * 0.37 + origin.z * 0.23;
	VERTEX.x += sin(phase) * sway_amount * VERTEX.y * VERTEX.y;
	VERTEX.z += cos(phase * 0.8) * sway_amount * 0.5 * VERTEX.y * VERTEX.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(v_world.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(v_world.z - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		albedo *= (1.0 - texture(fog_texture, fuv).r);
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
}
