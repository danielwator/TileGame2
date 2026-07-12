// ============================================================
//  AEONS — atmosphere rim glow
//  Rendered on an enclosing sphere with front-face culling, so
//  only the far shell is drawn; additive fresnel makes a soft
//  blue halo hugging the planet's silhouette.
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;

uniform vec3 atmo_color: source_color = vec3(0.30, 0.50, 0.95);
uniform float intensity: hint_range(0.0, 3.0) = 1.15;
uniform float falloff: hint_range(0.5, 8.0) = 3.4;

void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), falloff);
	ALBEDO = vec3(0.0);
	EMISSION = atmo_color * fres * intensity;
}
