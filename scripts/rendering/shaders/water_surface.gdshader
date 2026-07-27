shader_type spatial;

// Draws a WaterBody's surface plane (see WaterSurfaceMesh).
//
// Two things are mixed, in this order:
//
//   1. DEPTH. Vertex COLOR.r carries a 0..1 shade factor baked per corner, ramping across
//      WaterBasin.WADE_DEPTH — so light blue is water a unit walks through and dark blue is
//      water the navmesh has been cut out of. The gradient between them is cosmetic; the
//      cell classification behind it is binary.
//   2. CHARGE. A lithium pond is not blue. `charge` is how much of its energy budget is
//      left (1 = full, 0 = spent), and it fades the pond from its own `charge_color` back
//      to plain water as extractors drain it. A body with no energy ships charge = 0 and is
//      therefore ordinary water with no special case.
//
// FOG IS PUSHED IN FROM Fog, exactly as it is for the terrain (same uniform names, same
// world-XZ mapping). A surface that does not go through that seam is silently unfogged —
// which is the whole reason Map.fogged_materials() exists rather than Fog naming one node.

render_mode cull_disabled, specular_disabled, depth_draw_never;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.72, 0.85, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.30, 0.60, 1.0);
uniform vec4 charge_color : source_color = vec4(0.87, 0.42, 0.55, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
// How far a full charge pulls the surface toward charge_color. Short of 1 so a charged pond
// still reads as water rather than as paint, and so the depth gradient stays visible in it.
uniform float charge_strength : hint_range(0.0, 1.0) = 0.7;

uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.7;

uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;

varying vec3 v_world;
varying float v_shade;

// Perceived brightness, for scaling the charge tint by depth the same way the blues are.
float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shade = COLOR.r;
}

void fragment() {
	// The charge tints the two DEPTH ENDPOINTS rather than the blended result, so the two
	// signals survive together: hue says "charged", lightness still says "deep". Tinting the
	// result instead washed the depth gradient out almost entirely at full charge.
	//
	// How much darker the deep tint is comes from the two blues themselves rather than from a
	// number of its own, so retuning the water retunes the pond with it.
	float depth_dim = luma(deep_color.rgb) / max(luma(shallow_color.rgb), 0.0001);
	vec3 shallow = mix(shallow_color.rgb, charge_color.rgb, charge * charge_strength);
	vec3 deep = mix(deep_color.rgb, charge_color.rgb * depth_dim, charge * charge_strength);
	vec3 albedo = mix(shallow, deep, v_shade);
	float alpha = mix(shallow_alpha, deep_alpha, v_shade);

	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(v_world.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(v_world.z - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		float shroud = texture(fog_texture, fuv).r;
		albedo *= (1.0 - shroud);
		// Unseen water hides what is under it as completely as the shroud hides the ground.
		alpha = mix(alpha, 1.0, shroud);
	}

	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = 0.1;
	METALLIC = 0.0;
}
