// Shared terrain shading: what makes elevation READ on both terrain renderers
// (terrain_surface.gdshader for a modelled surface mesh, s1.gdshader for the quad-per-cell mesh).
// The why — which cue answers which question, and what each costs — is the design note:
// gdd/systems/ux/aesthetics/terrain-readability.md. Everything here is placeholder art
// direction (palette, line weights); the CUES are the settled part.
//
// Every input is a derived per-map texture pushed by TerrainShading.push_terrain_uniforms; a
// material that never received them falls back to flat, unlit-by-cue ground, not to an error.

const int MAX_TILE_TYPES = 256;

// Cell-indexed per-cell data. R = tile type index / 255, G = 1 when the cell is too steep to
// traverse. Nearest-filtered: both are per-cell facts and must not blend across boundaries.
uniform sampler2D cell_data : filter_nearest, repeat_disable;
// (min_x, min_z, size_x, size_z) of the cell grid in world XZ — maps world -> cell UV.
uniform vec4 terrain_rect = vec4(0.0, 0.0, 1.0, 1.0);

// Corner heights, linearly filtered and mipmapped: a world-space height lookup, and (at a
// coarse mip) the local mean height that cavity shading compares against.
uniform sampler2D height_texture : filter_linear_mipmap, repeat_disable;
// (min_x, min_z, size_x, size_z) such that uv = (world_xz - xy) / zw hits corner texel centres.
uniform vec4 height_rect = vec4(0.0, 0.0, 1.0, 1.0);
// (lowest, highest) in-play corner height, for the hypsometric tint.
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float has_heights = 0.0;

// Pass-7 ground paint, cell-indexed and linearly filtered so its edges are soft:
// R = meadow / clearing, G = trail, B = scree, A = shore. See MapDecoration.
uniform sampler2D ground_overlay : filter_linear, repeat_disable;
uniform float has_overlay = 0.0;

uniform vec4 tile_colors[MAX_TILE_TYPES];
uniform sampler2DArray tile_textures : source_color, filter_linear, repeat_enable;
uniform int tile_count = 0;
uniform float tile_has_texture[MAX_TILE_TYPES];
// World units per texture tile, so a repeating ground texture is scaled in world space.
uniform float texture_scale = 4.0;

// --- Placeholder palette -------------------------------------------------------------------
uniform vec4 rock_light : source_color = vec4(0.47, 0.44, 0.40, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.27, 0.25, 0.23, 1.0);
uniform vec4 meadow_color : source_color = vec4(0.42, 0.56, 0.24, 1.0);
uniform vec4 trail_color : source_color = vec4(0.52, 0.42, 0.29, 1.0);
uniform vec4 scree_color : source_color = vec4(0.45, 0.42, 0.38, 1.0);
uniform vec4 shore_color : source_color = vec4(0.55, 0.50, 0.37, 1.0);
// The crisp line on the passable side of every passability boundary. Ink, not shading: the
// game's eventual look is illustrative, and this line is what keeps "can a unit go here"
// exact while everything around it is free to be painterly.
uniform vec4 outline_color : source_color = vec4(0.10, 0.09, 0.08, 1.0);
uniform float outline_width = 0.12;   // world units

// --- Elevation cues -----------------------------------------------------------------------
// Contour lines: one every `contour_interval` of height, offset so a level sits BETWEEN the
// generator's terraces rather than on them — each terrace step then carries exactly one line.
uniform float contour_interval = 0.4;
uniform float contour_offset = 0.2;
uniform float contour_strength = 0.35;
uniform float contour_pixels = 1.2;    // line width in screen pixels
// Hypsometric tint: brightness ramp from the lowest to the highest ground.
uniform float hypsometric_low = 0.85;
uniform float hypsometric_high = 1.12;
// Cavity shading: ground below its surroundings darkens, ground above brightens slightly.
uniform float cavity_strength = 0.2;
uniform float cavity_mip = 3.0;
// Slope shading on passable ground: graded ground tends toward rock as it steepens.
uniform float slope_rock_blend = 1.6;
// Two-octave value noise in world space, so no region is one flat colour.
uniform float noise_strength = 0.14;
// Ground grain: a fine stipple (clumps of grass, grit) in albedo AND in the lit normal. Lit
// grain is what makes a slope read on flat-coloured ground: the same bumps catch the sun
// differently once the surface under them tilts.
uniform float grain_cells = 0.22;      // world units per grain clump
uniform float grain_albedo = 0.22;     // albedo contrast of the grain
uniform float grain_bump = 0.55;       // how far the grain tilts the lit normal
// Hachures: strokes running DOWNHILL on sloped walkable ground, the cartographer's cue for
// which way and how steeply the ground falls. They fade in over a GRADIENT (rise per unit run),
// because a terrace grade climbs only about a tenth of a unit per cell.
uniform float hachure_spacing = 0.45;  // world units between strokes
uniform float hachure_strength = 0.7;
uniform float hachure_gradient_min = 0.02;
uniform float hachure_gradient_max = 0.12;
// Terrain specular: 0 is matte. Broad and weak on purpose: a sheen on ground tilted to bounce
// the sun at the camera, broken up by the grain so it reads as grass catching light.
uniform float specular_strength = 0.0;
uniform float specular_roughness = 0.55;
uniform vec4 hachure_color : source_color = vec4(0.11, 0.17, 0.07, 1.0);

float th_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float th_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(th_hash(i), th_hash(i + vec2(1.0, 0.0)), u.x),
		mix(th_hash(i + vec2(0.0, 1.0)), th_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float th_noise2(vec2 p) {
	return 0.65 * th_value_noise(p / 3.0) + 0.35 * th_value_noise(p / 0.9);
}

vec2 th_height_uv(vec2 p) {
	return (p - height_rect.xy) / height_rect.zw;
}

float th_height(vec2 p) {
	return texture(height_texture, th_height_uv(p)).r;
}

// World-space normal from the height field: smooth across cells, which is what lets lighting
// show relief instead of a staircase of flat quads.
vec3 th_normal(vec2 p) {
	float e = 0.5;
	float hx = th_height(p + vec2(e, 0.0)) - th_height(p - vec2(e, 0.0));
	float hz = th_height(p + vec2(0.0, e)) - th_height(p - vec2(0.0, e));
	return normalize(vec3(-hx, 2.0 * e, -hz));
}

// One layer of grain: jittered clumps of random size on a grid rotated off the screen axes,
// so no row or column of the lattice lines up with the camera.
float th_grain_layer(vec2 p, float cells, float angle) {
	vec2 q = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p / cells;
	vec2 cell = floor(q);
	vec2 centre = vec2(th_hash(cell + 7.0), th_hash(cell + 13.0)) * 0.6 + 0.2;
	float radius = mix(0.18, 0.45, th_hash(cell + 29.0));
	float dome = 1.0 - smoothstep(radius * 0.4, radius, length(fract(q) - centre));
	return dome * mix(0.4, 1.0, th_hash(cell));
}

// The grain's height at `p`: two clump layers and a coarse wash, deliberately not smooth.
float th_grain(vec2 p) {
	return 0.55 * th_grain_layer(p, grain_cells, 0.52)
		+ 0.35 * th_grain_layer(p, grain_cells * 0.61, 1.31)
		+ 0.3 * th_value_noise(p / (grain_cells * 4.0));
}

// `n` tilted by the grain's gradient, so the lighting picks the stipple out.
vec3 th_grain_normal(vec2 p, vec3 n, float impassable) {
	float e = grain_cells * 0.18;
	float gx = th_grain(p + vec2(e, 0.0)) - th_grain(p - vec2(e, 0.0));
	float gz = th_grain(p + vec2(0.0, e)) - th_grain(p - vec2(0.0, e));
	float k = grain_bump * (1.0 - 0.6 * impassable);
	return normalize(n + vec3(-gx, 0.0, -gz) * k);
}

// 0..1 hachure stroke at `p` on ground whose (unperturbed) normal is `n`: thin strokes along
// the downhill direction, broken up so they read as drawn rather than ruled.
float th_hachure(vec2 p, vec3 n) {
	float gradient = length(n.xz) / max(n.y, 1e-3);
	float fade = smoothstep(hachure_gradient_min, hachure_gradient_max, gradient);
	if (fade <= 0.0) {
		return 0.0;
	}
	// Stroke direction from a coarser read of the height field, so strokes run straight down
	// the grade instead of swirling with every cell-sized wobble in the fine normal.
	vec2 down = normalize(n.xz);
	if (has_heights > 0.5) {
		vec2 uv = th_height_uv(p);
		vec2 texel = 1.0 / vec2(textureSize(height_texture, 0));
		float hx = textureLod(height_texture, uv + vec2(2.0 * texel.x, 0.0), 1.5).r
			- textureLod(height_texture, uv - vec2(2.0 * texel.x, 0.0), 1.5).r;
		float hz = textureLod(height_texture, uv + vec2(0.0, 2.0 * texel.y), 1.5).r
			- textureLod(height_texture, uv - vec2(0.0, 2.0 * texel.y), 1.5).r;
		if (abs(hx) + abs(hz) > 1e-4) {
			down = -normalize(vec2(hx, hz));
		}
	}
	vec2 across = vec2(-down.y, down.x);
	float u = dot(p, across) / hachure_spacing;
	float v = dot(p, down);
	float lane = floor(u);
	float offset = (th_hash(vec2(lane, 3.0)) - 0.5) * 0.3;
	float stroke = 1.0 - smoothstep(0.1, 0.32, abs(fract(u) - 0.5 - offset));
	float dash = step(0.3, th_value_noise(vec2(lane * 1.7, v / 1.4)));
	return stroke * dash * fade;
}

// SPECULAR and ROUGHNESS for a fragment: matte when specular_strength is 0.
vec2 th_specular(vec2 p, float impassable) {
	if (specular_strength <= 0.0) {
		return vec2(0.0, 1.0);
	}
	float clump = th_grain(p);
	return vec2(specular_strength * mix(0.4, 1.0, clump) * (1.0 - 0.5 * impassable),
		specular_roughness);
}

// 1 on a pixel within `contour_pixels` of a contour level, antialiased; 0 elsewhere.
float th_contour(float h) {
	float w = fwidth(h) * contour_pixels;
	if (w < 1e-5) {
		return 0.0;
	}
	float d = (h - contour_offset) / contour_interval;
	float dist = abs(fract(d + 0.5) - 0.5) * contour_interval;
	return 1.0 - smoothstep(0.0, w, dist);
}

float th_steep_at(vec2 cell_uv) {
	if (cell_uv.x < 0.0 || cell_uv.y < 0.0 || cell_uv.x > 1.0 || cell_uv.y > 1.0) {
		return 0.0;
	}
	return step(0.5, texture(cell_data, cell_uv).g);
}

// Distance-based ink line on a passable cell's sides that face an impassable neighbour.
float th_outline(vec2 p, vec2 uv) {
	vec2 texel = 1.0 / vec2(textureSize(cell_data, 0));
	vec2 f = fract(p - terrain_rect.xy);
	float line = 0.0;
	line = max(line, th_steep_at(uv + vec2(-texel.x, 0.0)) * (1.0 - step(outline_width, f.x)));
	line = max(line, th_steep_at(uv + vec2(texel.x, 0.0)) * (1.0 - step(outline_width, 1.0 - f.x)));
	line = max(line, th_steep_at(uv + vec2(0.0, -texel.y)) * (1.0 - step(outline_width, f.y)));
	line = max(line, th_steep_at(uv + vec2(0.0, texel.y)) * (1.0 - step(outline_width, 1.0 - f.y)));
	return line;
}

vec3 th_base_albedo(int idx, vec2 p) {
	vec3 albedo = tile_colors[idx].rgb;
	if (tile_count > 0 && idx < tile_count && tile_has_texture[idx] > 0.5) {
		albedo = texture(tile_textures, vec3(p / texture_scale, float(idx))).rgb;
	}
	return albedo;
}

// The whole terrain look for one fragment at world position `w`. `idx` and `impassable` are
// the cell's facts from cell_data; `n` is the world normal to shade with.
vec3 th_shade(vec3 w, int idx, float impassable, vec2 uv, vec3 n) {
	vec2 p = w.xz;
	float h = has_heights > 0.5 ? th_height(p) : w.y;
	float noise = th_noise2(p);
	vec3 albedo = th_base_albedo(idx, p);

	if (has_overlay > 0.5) {
		vec4 o = texture(ground_overlay, uv);
		float n2 = th_value_noise(p * 0.7);
		albedo = mix(albedo, meadow_color.rgb, clamp(o.r, 0.0, 1.0) * 0.75);
		albedo = mix(albedo, shore_color.rgb, smoothstep(0.2, 0.7, o.a));
		albedo = mix(albedo, scree_color.rgb, smoothstep(0.25, 0.75, o.b + (n2 - 0.5) * 0.4));
		albedo = mix(albedo, trail_color.rgb, smoothstep(0.35, 0.55, o.g + (n2 - 0.5) * 0.25));
	}

	// Graded (walkable but sloped) ground leans toward rock and carries hachures, so a
	// terrace step reads as one and shows which way it falls.
	float slope = 1.0 - n.y;
	albedo = mix(albedo, scree_color.rgb, clamp(slope * slope_rock_blend, 0.0, 0.35) * (1.0 - impassable));
	albedo = mix(albedo, hachure_color.rgb, th_hachure(p, n) * hachure_strength * (1.0 - impassable));

	// Impassable ground is rock, banded by height so cliff faces show their own relief.
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, noise);
	rock *= 0.88 + 0.12 * step(0.5, fract(h * 1.25));
	albedo = mix(albedo, rock, impassable);

	albedo *= 1.0 + noise_strength * (noise - 0.5);
	albedo *= 1.0 + grain_albedo * (th_grain(p) - 0.55);

	float t = clamp((h - height_range.x) / max(height_range.y - height_range.x, 1e-3), 0.0, 1.0);
	albedo *= mix(hypsometric_low, hypsometric_high, t);

	if (has_heights > 0.5) {
		float around = textureLod(height_texture, th_height_uv(p), cavity_mip).r;
		albedo *= clamp(1.0 - (around - h) * cavity_strength, 0.72, 1.12);
	}

	albedo *= 1.0 - contour_strength * th_contour(h) * (1.0 - impassable);
	albedo = mix(albedo, outline_color.rgb, th_outline(p, uv) * (1.0 - impassable));
	return albedo;
}

// Fog of war, sampled by WORLD position so the shroud conforms to terrain height:
// r = 0 in sight .. 0.5 explored .. 1 unseen.
uniform sampler2D fog_texture : filter_linear, repeat_disable;
uniform vec4 fog_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float fog_enabled = 0.0;

vec3 th_apply_fog(vec3 albedo, vec2 p) {
	if (fog_enabled > 0.5) {
		vec2 fuv = vec2(
			(p.x - fog_rect.x + fog_rect.z) / (2.0 * fog_rect.z),
			(p.y - fog_rect.y + fog_rect.w) / (2.0 * fog_rect.w)
		);
		albedo *= (1.0 - texture(fog_texture, fuv).r);
	}
	return albedo;
}
