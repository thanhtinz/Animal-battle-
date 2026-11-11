shader_type canvas_item;
// Rounds the corners of a textured rect (13p: the painted scene
// inside the matchmaking frame). rect_size is the control size
// in pixels, corner_radius in pixels; fragments outside the
// rounded rect fade out over ~2px.
uniform vec2 rect_size = vec2(860.0, 410.0);
uniform float corner_radius = 30.0;

void fragment() {
	vec2 px = UV * rect_size;
	vec2 half_s = rect_size * 0.5;
	vec2 q = abs(px - half_s) - (half_s - vec2(corner_radius));
	float d = length(max(q, vec2(0.0))) - corner_radius;
	vec4 c = texture(TEXTURE, UV);
	c.a *= 1.0 - smoothstep(-1.0, 1.0, d);
	COLOR = c;
}
