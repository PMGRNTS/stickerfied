// Recolors a dress-up layer to a chosen hue.
// Colorful parts take on the new hue; black, white and gray parts
// (outlines, eye whites, shading) keep their original look.
shader_type canvas_item;

uniform bool enabled = false;
uniform float target_hue : hint_range(0.0, 1.0) = 0.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 color = COLOR;
	if (enabled) {
		vec3 hsv = rgb_to_hsv(color.rgb);
		hsv.x = target_hue;
		color.rgb = hsv_to_rgb(hsv);
	}
	COLOR = color;
}
