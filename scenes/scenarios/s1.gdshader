shader_type spatial;

// Number of grid cells per axis — should match (map_width - 1) and (map_depth - 1).
uniform int grid_width = 29;
uniform int grid_depth = 29;

uniform vec4 color_a : source_color = vec4(0.22, 0.40, 0.22, 1.0);
uniform vec4 color_b : source_color = vec4(0.16, 0.30, 0.16, 1.0);

void fragment() {
	vec2 cell = floor(UV * vec2(float(grid_width), float(grid_depth)));
	cell = clamp(cell, vec2(0.0), vec2(float(grid_width) - 1.0, float(grid_depth) - 1.0));
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(color_a.rgb, color_b.rgb, checker);
}
