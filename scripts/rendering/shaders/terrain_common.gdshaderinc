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
uniform float contour_interval = 0.8;
uniform float contour_offset = 0.4;
uniform float contour_strength = 0.2;
uniform float contour_pixels = 1.2;    // line width in screen pixels
// Relief exaggeration: the LIT normal's tilt is multiplied by this on walkable ground, the way
// RTS terrain overstates its hillshade. A terrace grade tilts the ground only a few degrees,
// which a 50-degree sun barely separates from flat; overstated, the sunward side of every grade
// lifts and the far side falls into shade. Smooth by construction, so it cannot alias.
uniform float relief_exaggeration = 4.0;
// Hypsometric tint: brightness ramp from the lowest to the highest ground.
uniform float hypsometric_low = 0.85;
uniform float hypsometric_high = 1.12;
// Cavity shading: ground below its surroundings darkens, ground above brightens slightly.
uniform float cavity_strength = 0.175;
uniform float cavity_mip = 3.0;
// Banks: graded walkable ground is darkened in VALUE only, keeping the hue of the ground around
// it, as RTS ramps are (a ramp is the same floor, lit differently, never a different material).
// Faded in over a GRADIENT (rise per unit run) read from the smoothed height field, with a
// noisy edge so a bank is a painted patch rather than a ruled band. Which side is light and
// which dark is the relief lighting's job, not this one's.
uniform float bank_gradient_min = 0.06;
uniform float bank_gradient_max = 0.26;
uniform float bank_darkening = 0.12;
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
// because a terrace grade climbs only a fraction of a unit per cell.
uniform float hachure_spacing = 0.45;  // world units between stroke centres
uniform float hachure_length = 0.32;   // half a stroke's length, world units
uniform float hachure_width = 0.05;    // a stroke's half-width at its uphill end
uniform float hachure_strength = 0.0;  // off: see terrain-readability.md
uniform float hachure_gradient_min = 0.04;
uniform float hachure_gradient_max = 0.24;
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

// Cubic B-spline weights for a texel fraction `f`.
vec4 th_bspline_weights(float f) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - f;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

// The height field B-spline filtered (four bilinear taps): continuous in slope, where the
// bilinear field kinks at every cell edge. Anything drawn from the height's DERIVATIVES (lit
// normals, contours, banks) uses this one — off the bilinear field those lines zigzag cell by
// cell. It smooths the terrace steps slightly, which no gameplay fact depends on.
float th_height_smooth(vec2 p) {
	vec2 size = vec2(textureSize(height_texture, 0));
	vec2 tc = th_height_uv(p) * size - 0.5;
	vec2 f = fract(tc);
	tc -= f;
	vec4 xw = th_bspline_weights(f.x);
	vec4 yw = th_bspline_weights(f.y);
	vec4 c = tc.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xw.xz + xw.yw, yw.xz + yw.yw);
	vec4 o = (c + vec4(xw.yw, yw.yw) / s) / size.xxyy;
	float t0 = textureLod(height_texture, o.xz, 0.0).r;
	float t1 = textureLod(height_texture, o.yz, 0.0).r;
	float t2 = textureLod(height_texture, o.xw, 0.0).r;
	float t3 = textureLod(height_texture, o.yw, 0.0).r;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(t3, t2, sx), mix(t1, t0, sx), sy);
}

// The smoothed height field's gradient (rise per unit run) at `p`.
vec2 th_gradient(vec2 p) {
	float e = 0.35;
	float hx = th_height_smooth(p + vec2(e, 0.0)) - th_height_smooth(p - vec2(e, 0.0));
	float hz = th_height_smooth(p + vec2(0.0, e)) - th_height_smooth(p - vec2(0.0, e));
	return vec2(hx, hz) / (2.0 * e);
}

// World-space normal from the height field: smooth across cells, which is what lets lighting
// show relief instead of a staircase of flat quads.
vec3 th_normal(vec2 p) {
	vec2 g = th_gradient(p);
	return normalize(vec3(-g.x, 1.0, -g.y));
}

// `n` with its tilt overstated by relief_exaggeration on walkable ground. Cliffs keep their
// true normal: they are already steep, and their rock banding does their relief.
vec3 th_relief_normal(vec3 n, float impassable) {
	float k = mix(relief_exaggeration, 1.0, impassable);
	return normalize(vec3(n.x * k, n.y, n.z * k));
}

// World units one screen pixel covers at `p`. Fragment stage only (fwidth).
float th_pixel(vec2 p) {
	vec2 w = fwidth(p);
	return max(max(w.x, w.y), 1e-5);
}

// One layer of grain: jittered clumps of random size on a grid rotated off the screen axes,
// so no row or column of the lattice lines up with the camera.
float th_grain_layer(vec2 p, float cells, float angle, float px) {
	vec2 q = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p / cells;
	vec2 cell = floor(q);
	vec2 centre = vec2(th_hash(cell + 7.0), th_hash(cell + 13.0)) * 0.6 + 0.2;
	float radius = mix(0.18, 0.45, th_hash(cell + 29.0));
	float aa = px / cells;
	float dome = 1.0 - smoothstep(radius * 0.4 - aa, radius + aa, length(fract(q) - centre));
	return dome * mix(0.4, 1.0, th_hash(cell));
}

// The clump layers' mean (0.55 + 0.35 times one layer's 0.114, measured), which they fade to.
const float TH_GRAIN_CLUMP_MEAN = 0.103;

// How much of the grain's clumps survive at pixel footprint `px`: all of them while a clump
// spans several pixels, none once it shrinks toward one. Sub-pixel clumps only alias (crawl
// and sparkle as the camera moves), so zoomed out they fade to their mean.
float th_grain_detail(float px) {
	return smoothstep(2.0, 5.0, grain_cells / px);
}

// The grain's height at `p`: two clump layers and a coarse wash, deliberately not smooth.
// `px` is th_pixel at the fragment.
float th_grain(vec2 p, float px) {
	float clumps = 0.55 * th_grain_layer(p, grain_cells, 0.52, px)
		+ 0.35 * th_grain_layer(p, grain_cells * 0.61, 1.31, px);
	clumps = mix(TH_GRAIN_CLUMP_MEAN, clumps, th_grain_detail(px));
	return clumps + 0.3 * th_value_noise(p / (grain_cells * 4.0));
}

// `n` tilted by the grain's gradient, so the lighting picks the stipple out.
vec3 th_grain_normal(vec2 p, vec3 n, float impassable) {
	float px = th_pixel(p);
	// Differencing no finer than a pixel: finer steps resolve edges the pixel can't show.
	float e = max(grain_cells * 0.18, px);
	float gx = th_grain(p + vec2(e, 0.0), px) - th_grain(p - vec2(e, 0.0), px);
	float gz = th_grain(p + vec2(0.0, e), px) - th_grain(p - vec2(0.0, e), px);
	float k = grain_bump * (1.0 - 0.6 * impassable) * (grain_cells * 0.18 / e);
	return normalize(n + vec3(-gx, 0.0, -gz) * k);
}

// The height field's gradient (rise per unit run) at `p`, read from a coarse mip so a stroke's
// direction follows the grade, not every cell-sized wobble in it.
vec2 th_coarse_gradient(vec2 p) {
	float e = 1.0;
	vec2 ex = vec2(e, 0.0) / height_rect.zw;
	vec2 ez = vec2(0.0, e) / height_rect.zw;
	vec2 uv = th_height_uv(p);
	float hx = textureLod(height_texture, uv + ex, 1.5).r - textureLod(height_texture, uv - ex, 1.5).r;
	float hz = textureLod(height_texture, uv + ez, 1.5).r - textureLod(height_texture, uv - ez, 1.5).r;
	return vec2(hx, hz) / (2.0 * e);
}

// 0..1 hachure ink at `p`: short strokes stamped on a jittered grid, each pointing straight
// downhill at its own centre. Stamped rather than drawn as stripes: a stripe pattern's phase
// is a function of position, and wherever the downhill direction turns, the stripes compress
// into bands and moire. A stamp's direction is one number, so turning ground only rotates it.
float th_hachure(vec2 p) {
	if (has_heights < 0.5 || hachure_strength <= 0.0) {
		return 0.0;
	}
	float px = th_pixel(p);
	// Zoomed out until strokes are a few pixels apart, they read as hatching noise: fade them.
	float detail = smoothstep(3.0, 6.0, hachure_spacing / px);
	if (detail <= 0.0) {
		return 0.0;
	}
	vec2 base = floor(p / hachure_spacing);
	float ink = 0.0;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 cell = base + vec2(float(dx), float(dz));
			vec2 jitter = vec2(th_hash(cell + 7.0), th_hash(cell + 13.0));
			vec2 centre = (cell + 0.2 + 0.6 * jitter) * hachure_spacing;
			// Whether to ink is the ground's OWN steepness at the stamp; which way to point is the
			// coarse grade around it. Fading by the coarse grade too bleeds strokes onto the flat
			// ground beside every slope.
			vec3 local = th_normal(centre);
			float steepness = length(local.xz) / max(local.y, 1e-3);
			float fade = smoothstep(hachure_gradient_min, hachure_gradient_max, steepness);
			vec2 gradient = th_coarse_gradient(centre);
			if (fade <= 0.0 || dot(gradient, gradient) < 1e-8) {
				continue;
			}
			vec2 down = -normalize(gradient);
			vec2 d = p - centre;
			float along = dot(d, down);
			float across = dot(d, vec2(-down.y, down.x));
			float half_length = hachure_length * mix(0.7, 1.0, th_hash(cell + 29.0));
			// A wedge: full width uphill, tapering to a point at the downhill end.
			float t = clamp(along / half_length * 0.5 + 0.5, 0.0, 1.0);
			float width = hachure_width * mix(1.0, 0.25, t);
			// Antialiased: the edge ramps over a pixel, and a stroke thinner than a pixel is
			// drawn a pixel wide but fainter (its coverage), rather than breaking into dashes.
			float drawn = max(width, 0.5 * px);
			float body = (1.0 - smoothstep(drawn - 0.5 * px, drawn + 0.5 * px, abs(across)))
				* (width / drawn);
			float ends = 1.0 - smoothstep(half_length - max(0.15 * half_length, px), half_length,
				abs(along));
			ink = max(ink, body * ends * fade);
		}
	}
	return ink * detail;
}


// SPECULAR and ROUGHNESS for a fragment: matte when specular_strength is 0.
vec2 th_specular(vec2 p, float impassable) {
	if (specular_strength <= 0.0) {
		return vec2(0.0, 1.0);
	}
	float clump = th_grain(p, th_pixel(p));
	return vec2(specular_strength * mix(0.4, 1.0, clump) * (1.0 - 0.5 * impassable),
		specular_roughness);
}

// 1 on a pixel within `contour_pixels` of a contour level, antialiased; 0 elsewhere. `h` must
// be the SMOOTHED height, or the line kinks at every cell edge. The edge ramps over one pixel
// measured in screen space; where levels crowd closer than a few pixels (steep ground, far
// zoom) they would only moire, so they fade out.
float th_contour(float h) {
	float per_pixel = fwidth(h);
	if (per_pixel < 1e-6) {
		return 0.0;
	}
	float d = (h - contour_offset) / contour_interval;
	float dist_pixels = abs(fract(d + 0.5) - 0.5) * contour_interval / per_pixel;
	float half_width = 0.5 * contour_pixels;
	float line = 1.0 - smoothstep(half_width - 0.5, half_width + 0.5, dist_pixels);
	return line * min(1.0, half_width + 0.5) * smoothstep(3.0, 6.0, contour_interval / per_pixel);
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
	// The line's inner edge ramps over a pixel instead of stepping, so it doesn't stair-step.
	float aa = 0.5 * th_pixel(p);
	vec2 near = 1.0 - smoothstep(vec2(outline_width - aa), vec2(outline_width + aa), f);
	vec2 far = 1.0 - smoothstep(vec2(outline_width - aa), vec2(outline_width + aa), 1.0 - f);
	float line = 0.0;
	line = max(line, th_steep_at(uv + vec2(-texel.x, 0.0)) * near.x);
	line = max(line, th_steep_at(uv + vec2(texel.x, 0.0)) * far.x);
	line = max(line, th_steep_at(uv + vec2(0.0, -texel.y)) * near.y);
	line = max(line, th_steep_at(uv + vec2(0.0, texel.y)) * far.y);
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

	// Graded (walkable but sloped) ground is a shade darker, so a terrace step reads at a glance.
	float h_smooth = has_heights > 0.5 ? th_height_smooth(p) : h;
	float steepness = has_heights > 0.5 ? length(th_gradient(p)) : length(n.xz) / max(n.y, 1e-3);
	float bank = smoothstep(bank_gradient_min, bank_gradient_max,
		steepness + (th_value_noise(p * 0.8) - 0.5) * 0.08);
	albedo *= 1.0 - bank * bank_darkening * (1.0 - impassable);
	albedo = mix(albedo, hachure_color.rgb, th_hachure(p) * hachure_strength * (1.0 - impassable));

	// Impassable ground is rock, banded by height so cliff faces show their own relief.
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, noise);
	// Bands antialiased: a triangle wave's distance from the band edge, ramped over a pixel.
	float band_x = h * 0.625;
	float band_aa = max(fwidth(band_x), 1e-4);
	float band = 1.0 - smoothstep(0.25 - band_aa, 0.25 + band_aa, abs(fract(band_x - 0.25) - 0.5));
	rock *= 0.88 + 0.12 * band;
	albedo = mix(albedo, rock, impassable);

	albedo *= 1.0 + noise_strength * (noise - 0.5);
	albedo *= 1.0 + grain_albedo * (th_grain(p, th_pixel(p)) - 0.55);

	float t = clamp((h - height_range.x) / max(height_range.y - height_range.x, 1e-3), 0.0, 1.0);
	albedo *= mix(hypsometric_low, hypsometric_high, t);

	if (has_heights > 0.5) {
		float around = textureLod(height_texture, th_height_uv(p), cavity_mip).r;
		albedo *= clamp(1.0 - (around - h) * cavity_strength, 0.72, 1.12);
	}

	albedo *= 1.0 - contour_strength * th_contour(h_smooth) * (1.0 - impassable);
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
