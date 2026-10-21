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
//      left (1 = full, 0 = spent), and it fades the pond from `charge_color` (its Biome's
//      pond_hue) back
//      to plain water as extractors drain it. A body with no energy ships charge = 0 and is
//      therefore ordinary water with no special case.
//   3. SHORE. The water ends where the terrain rises through its level, not at a cell edge:
//      depth is `water_level` minus the terrain's SMOOTHED height field (the one the terrain
//      shades from, terrain_height.gdshaderinc), and dividing it by the field's slope gives the
//      distance from that contour. The raw corner heights step at every cell edge, so their own
//      contour zigzags; UV2.x carries them only as the fallback when no height field was pushed. Plain
//      water thins out toward it into a darker wet margin on the ground beyond. A lithium pond
//      that holds energy (`cultivated`, WaterBody.is_cultivated) instead grows a pale
//      evaporite crust, thickest at the contour: still and matte, so a red or orange pond reads
//      as brine rather than as a hazard (gdd/setting/natural-environment.md §Lithium ponds are
//      cultivated). Neither climbs a bank: both stop where the ground rises far above the level.
//
// FOG IS PUSHED IN FROM Fog, exactly as it is for the terrain (same uniform names, same
// world-XZ mapping). A surface that does not go through that seam is silently unfogged —
// which is the whole reason Map.fogged_materials() exists rather than Fog naming one node.

render_mode cull_disabled, specular_disabled, depth_draw_never;

#include "res://scripts/rendering/shaders/terrain_height.gdshaderinc"

// The body's water level, in world units: WaterBody pushes it, with the height field.
uniform float water_level = 0.0;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.72, 0.85, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.30, 0.60, 1.0);
uniform vec4 charge_color : source_color = vec4(0.87, 0.42, 0.55, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
// How far a full charge pulls the surface toward charge_color. Short of 1 so a charged pond
// still reads as water rather than as paint, and so the depth gradient stays visible in it.
uniform float charge_strength : hint_range(0.0, 1.0) = 0.7;

uniform float cultivated : hint_range(0.0, 1.0) = 0.0;
uniform vec4 crust_color : source_color = vec4(0.88, 0.86, 0.82, 1.0);
// Distances from the contour, in cells (world units): how far a pond's crust reaches into the
// water and out over the ground, how far plain water thins out before the contour, and how far
// its wet margin reaches beyond it.
uniform float crust_reach_in = 0.4;
uniform float crust_reach_out = 0.5;
uniform float soft_edge_in = 0.4;
uniform float wet_reach_out = 0.45;
// World units per feature of the noise that breaks the shore's edge up. A world unit is a cell.
uniform float crust_noise_size = 0.7;
// The crust's opacity at its thickest; below 1 so the ground still shows through it.
uniform float crust_opacity = 0.9;
// How dark the wet margin is at the contour.
uniform float wet_darkening = 0.3;
// How far the ground may rise above the level, in world units, before the shore stops drawing:
// past this it is a bank or a cliff wall.
uniform float bank_rise = 0.5;
// The gentlest slope the contour distance is measured against (depth per world unit), so
// near-flat ground does not stretch the shore out across the map.
uniform float min_slope = 0.05;

uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.7;

uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;

varying vec3 v_world;
varying float v_shade;
varying float v_depth;

// Perceived brightness, for scaling the charge tint by depth the same way the blues are.
float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, 0..1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shade = COLOR.r;
	v_depth = UV2.x;
}

void fragment() {
	float n = value_noise(v_world.xz / crust_noise_size);
	float n_fine = value_noise(v_world.xz / (crust_noise_size * 0.35) + 17.0);
	float mottle = mix(0.45, 1.0, n_fine);

	// Signed distance from the contour, in world units: positive in the water.
	float pixel = max(length(fwidth(v_world.xz)), 1e-4);
	float depth = v_depth;
	float slope = fwidth(v_depth) / pixel;
	if (has_heights > 0.5) {
		depth = water_level - th_height_smooth(v_world.xz);
		slope = length(th_gradient(v_world.xz));
	}
	float from_shore = depth / max(slope, min_slope);
	float in_water = smoothstep(-pixel, pixel, from_shore);

	// The water. The charge tints the two DEPTH ENDPOINTS rather than the blended result, so the
	// two signals survive together: hue says "charged", lightness still says "deep". Tinting the
	// result instead washed the depth gradient out almost entirely at full charge.
	//
	// How much darker the deep tint is comes from the two blues themselves rather than from a
	// number of its own, so retuning the water retunes the pond with it.
	float depth_dim = luma(deep_color.rgb) / max(luma(shallow_color.rgb), 0.0001);
	vec3 shallow = mix(shallow_color.rgb, charge_color.rgb, charge * charge_strength);
	vec3 deep = mix(deep_color.rgb, charge_color.rgb * depth_dim, charge * charge_strength);
	vec3 water = mix(shallow, deep, v_shade);
	float water_alpha = mix(shallow_alpha, deep_alpha, v_shade);

	// The shore, on the ground beyond the contour.
	float beyond = -from_shore;
	float on_shore = 1.0 - smoothstep(bank_rise * 0.5, bank_rise, -depth);
	vec3 shore;
	float shore_alpha;
	if (cultivated > 0.5) {
		float crust_in = 1.0 - smoothstep(0.0, crust_reach_in, from_shore + (n - 0.5) * 0.25);
		crust_in *= mottle * crust_opacity;
		water = mix(water, crust_color.rgb, crust_in);
		water_alpha = mix(water_alpha, 1.0, crust_in);
		float crust_out = 1.0 - smoothstep(0.0, crust_reach_out, beyond + (n - 0.5) * 0.3);
		shore = crust_color.rgb;
		shore_alpha = crust_out * mottle * crust_opacity * on_shore;
	} else {
		water_alpha *= smoothstep(0.0, soft_edge_in, from_shore + (n - 0.5) * 0.15);
		float wet = 1.0 - smoothstep(0.0, wet_reach_out, beyond + (n - 0.5) * 0.2);
		shore = vec3(0.0);
		shore_alpha = wet * wet_darkening * on_shore;
	}

	vec3 albedo = mix(shore, water, in_water);
	float alpha = mix(shore_alpha, water_alpha, in_water);
	if (alpha < 0.004) {
		discard;
	}

	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(v_world.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(v_world.z - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		float shroud = texture(fog_texture, fuv).r;
		albedo *= (1.0 - shroud);
		// Unseen water hides what is under it as completely as the shroud hides the ground.
		alpha = mix(alpha, 1.0, shroud * in_water);
	}

	ALBEDO = albedo;
	ALPHA = alpha;
	ROUGHNESS = 0.1;
	METALLIC = 0.0;
}
