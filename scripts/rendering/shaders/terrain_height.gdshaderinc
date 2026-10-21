// The terrain's height field as shaders read it: the corner heights TerrainShading pushes
// (push_terrain_uniforms), and the smoothed field and gradient drawn from them. Shared by the
// terrain shading (terrain_common.gdshaderinc) and the water surface, which ends where this
// same field rises through its level, so a shoreline sits on the ground the player sees.

// Corner heights, linearly filtered and mipmapped: a world-space height lookup, and (at a
// coarse mip) the local mean height that cavity shading compares against.
uniform sampler2D height_texture : filter_linear_mipmap, repeat_disable;
// (min_x, min_z, size_x, size_z) such that uv = (world_xz - xy) / zw hits corner texel centres.
uniform vec4 height_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float has_heights = 0.0;

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
