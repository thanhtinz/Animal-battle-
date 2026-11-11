shader_type canvas_item;
// Flag/banner wave for building art (13o animation pass): the flags
// on the Town Center / Castle / Barracks art are baked into a single
// static texture, so the wave is faked in the vertex stage — the
// TOP band of the texture (where every flag + pole sits) ripples
// with a travelling sine while the weight fades to zero at `band`,
// leaving walls and roofs planted. Amplitude is in texture pixels;
// the sprite's own scale carries it to world size. Presentation
// only: TIME-driven, identical cost per building, no sim contact.
uniform float wave_amp : hint_range(0.0, 10.0) = 4.2;
uniform float wave_speed : hint_range(0.5, 12.0) = 5.2;
uniform float band : hint_range(0.05, 0.6) = 0.30;
uniform float phase = 0.0;

void vertex() {
	float w = smoothstep(band, 0.0, UV.y);
	float travel = TIME * wave_speed + phase - UV.y * 16.0 + UV.x * 2.5;
	VERTEX.x += sin(travel) * wave_amp * w;
	VERTEX.y += cos(travel * 0.83) * wave_amp * 0.32 * w;
}
