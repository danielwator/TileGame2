// ============================================================
//  AEONS — per-fragment terrain (ported from the original
//  TileGame project's WorldGenerator.ClassifyTile + palette)
//
//  The CPU generates 1024x512 field grids (elevation, moisture,
//  geo/volcanic, temperature-variation) plus a post-process mask
//  (rivers, lakes, coastal shallows, island/lake fills). This
//  shader bilinearly samples the fields, re-runs the original
//  classification per pixel (their hi-res "RevealAll" trick) and
//  paints with the original tile palette — crisp at any zoom.
//
//  Palette order = WorldGen.TT enum (fixed contract).
// ============================================================
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D fields: filter_linear, repeat_enable;  // r=elev g=moist b=geo a=tvar
uniform sampler2D mask_tex: filter_nearest, repeat_enable; // post-process overrides
uniform vec4 palette[25];
uniform float sea = 0.52;
uniform float temp_bias = 0.0;
uniform float moist_bias = 0.0;
uniform vec3 noise_off = vec3(0.0);

const float SHALLOW_OFFSET = 0.05;
const float BEACH_OFFSET = 0.03;
const float MOUNTAIN_LEVEL = 0.78;
const float SNOW_PEAK_LEVEL = 0.88;
const float VOLCANIC_RATE = 0.78;
const float TV_STRENGTH = 0.42;

// tile type ids (WorldGen.TT)
const int T_OCEAN = 0;
const int T_SHALLOW = 1;
const int T_CORAL = 2;
const int T_BEACH = 3;
const int T_MANGROVE = 4;
const int T_SWAMP = 5;
const int T_ICECAP = 6;
const int T_TUNDRA = 7;
const int T_TAIGA = 8;
const int T_PINE = 9;
const int T_GRASS = 10;
const int T_STEPPE = 11;
const int T_TFOREST = 12;
const int T_SHRUB = 13;
const int T_JUNGLE = 14;
const int T_TROPFOREST = 15;
const int T_SAVANNA = 16;
const int T_DESERT = 17;
const int T_SALT = 18;
const int T_ALPINE = 19;
const int T_MOUNTAIN = 20;
const int T_VOLCANO = 21;
const int T_SNOWPEAK = 22;
const int T_LAKE = 23;
const int T_RIVER = 24;

// mask values (WorldGen.MASK)
const int M_NONE = 0;
const int M_RIVER = 1;
const int M_LAKE = 2;
const int M_SHALLOW = 3;
const int M_LAND_FILL = 4;
const int M_OCEAN_FILL = 5;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z) * 2.0 - 1.0;
}

vec3 srgb2lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// direct port of WorldGenerator.ClassifyTile
int classify(float e, float latitude, float moisture, float geo, float tv) {
	moisture = clamp(moisture + moist_bias, 0.0, 1.0);
	float sea_temp = 1.0 - latitude;

	if (e < sea - SHALLOW_OFFSET) { return T_OCEAN; }
	if (e < sea) {
		return (latitude < 0.14 && moisture < 0.52) ? T_CORAL : T_SHALLOW;
	}
	if (e < sea + BEACH_OFFSET) {
		if (latitude < 0.22 && moisture > 0.62) { return T_MANGROVE; }
		if (moisture > 0.72 && sea_temp > 0.38) { return T_SWAMP; }
		return T_BEACH;
	}
	if (e < sea + BEACH_OFFSET + 0.05 && moisture > 0.76 && sea_temp > 0.38) { return T_SWAMP; }

	float alt_chill = max(0.0, (e - sea) / (MOUNTAIN_LEVEL - sea)) * 0.5;
	float temp = clamp(1.0 - latitude - alt_chill + temp_bias + (tv - 0.5) * TV_STRENGTH, 0.0, 1.0);
	float temp_no_alt = clamp(1.0 - latitude + temp_bias + (tv - 0.5) * TV_STRENGTH, 0.0, 1.0);
	if (temp_no_alt < 0.12) { return T_ICECAP; }

	if (e >= SNOW_PEAK_LEVEL) { return temp_no_alt <= 0.55 ? T_SNOWPEAK : T_MOUNTAIN; }
	if (e >= MOUNTAIN_LEVEL) { return geo > VOLCANIC_RATE ? T_VOLCANO : T_MOUNTAIN; }
	if (e >= MOUNTAIN_LEVEL - 0.08) {
		float alpine_temp = clamp(1.0 - latitude - 0.35, 0.0, 1.0);
		return alpine_temp > 0.22 ? T_ALPINE : T_TUNDRA;
	}

	if (temp < 0.28) { return moisture > 0.48 ? T_TAIGA : T_TUNDRA; }
	if (temp < 0.46) {
		if (moisture > 0.60) { return T_TAIGA; }
		if (moisture > 0.42) { return T_PINE; }
		if (moisture > 0.26) { return T_GRASS; }
		return moisture > 0.12 ? T_STEPPE : T_TUNDRA;
	}
	if (temp < 0.68) {
		if (moisture > 0.70) { return T_SWAMP; }
		if (moisture > 0.50) { return T_TFOREST; }
		if (moisture > 0.34) { return T_GRASS; }
		if (moisture > 0.20) { return T_SHRUB; }
		return T_DESERT;
	}
	if (moisture > 0.68) { return T_JUNGLE; }
	if (moisture > 0.48) { return T_TROPFOREST; }
	if (moisture > 0.32) { return T_SAVANNA; }
	if (moisture > 0.22) { return T_SHRUB; }
	if (moisture > 0.07) { return T_DESERT; }
	return T_SALT;
}

bool is_water(int t) {
	return t == T_OCEAN || t == T_SHALLOW || t == T_CORAL || t == T_LAKE;
}

void fragment() {
	vec2 tex_size = vec2(textureSize(fields, 0));
	vec3 dir = normalize(v_dir);
	float lat = asin(clamp(dir.y, -1.0, 1.0));
	float lon = atan(dir.x, dir.z);          // matches grid convention (sin lon, ..., cos lon)
	float u = fract(lon / TAU);
	float v = clamp((lat + PI * 0.5) / PI, 0.5 / tex_size.y, 1.0 - 0.5 / tex_size.y);
	vec2 uv = vec2(u, v);

	vec4 f = texture(fields, uv);
	float e = f.r;
	float m = f.g;
	float geo = f.b;
	float tv = f.a;
	float latitude = abs(v * 2.0 - 1.0);

	// sub-cell detail: breaks up bilinear plateaus without moving coastlines far
	vec3 dn = dir + noise_off;
	e += vnoise(dn * 42.0) * 0.008 + vnoise(dn * 95.0) * 0.004;
	m = clamp(m + vnoise(dn * 27.0) * 0.035, 0.0, 1.0);

	int t = classify(e, latitude, m, geo, tv);

	// post-process overrides carved by the CPU passes (their RevealAll rule:
	// rivers/lakes win over reclassification)
	int mk = int(texture(mask_tex, uv).r * 255.0 + 0.5);
	if (mk == M_RIVER) { t = T_RIVER; }
	else if (mk == M_LAKE) { t = T_LAKE; }
	else if (mk == M_SHALLOW) { if (t == T_OCEAN) { t = T_SHALLOW; } }
	else if (mk == M_LAND_FILL) { if (is_water(t)) { t = T_GRASS; } }
	else if (mk == M_OCEAN_FILL) { if (!is_water(t)) { t = T_OCEAN; } }

	vec3 col = palette[t].rgb;
	// faint per-pixel grain keeps large fields from looking flat
	col = clamp(col + vec3(vnoise(dn * 160.0) * 0.012), 0.0, 1.0);

	ALBEDO = srgb2lin(col);
}
