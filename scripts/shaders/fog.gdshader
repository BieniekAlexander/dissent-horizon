shader_type spatial;
render_mode unshaded, depth_draw_never, blend_mix;

uniform sampler2D fog_texture;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = texture(fog_texture, UV).r;
}
