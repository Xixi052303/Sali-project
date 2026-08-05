shader_type spatial;

render_mode blend_add, cull_back, depth_draw_always;

uniform vec4 emission_color : source_color = vec4(0.31, 0.8, 1.0, 0.86);
uniform float emission_amount : hint_range(0.0, 16.0) = 5.0;
uniform float rim_sharpness : hint_range(0.0, 16.0) = 3.0;


void fragment() {
	EMISSION = emission_color.rgb * emission_amount;
	float rim_factor = pow(
		clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0),
		rim_sharpness
	);
	ALPHA = rim_factor * emission_color.a;
}
