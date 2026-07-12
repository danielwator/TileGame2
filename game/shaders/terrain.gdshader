// ============================================================
//  AEONS — per-fragment terrain classification
//
//  The mesh carries smooth interpolated FIELDS (elevation, temp,
//  moisture, volcanism, lake mask, land distance) as CUSTOM0/1.
//  Biome classification + shading run here, per pixel, so
//  coastlines, lakes and islands are crisp at any zoom instead of
//  being smeared by vertex-color interpolation. Mirrors the CPU
//  logic in worldgen._render_chunk (kept for tile aggregation).
//
//  Biome palette order (fixed contract with globe_mesh.gd):
//   0 iceCap    1 lake      2 coast     3 ocean     4 deepOcean
//   5 mountain  6 volcanic  7 highlands 8 tundra    9 boreal
//  10 wetland  11 desert   12 steppe   13 plains   14 grassland
//  15 forest   16 savanna  17 rainforest
// ============================================================
shader_type spatial;
render_mode cull_back;

uniform vec4 palette[18];
uniform float sea = 0.5;
uniform float emax = 1.0;
uniform float emin = 0.0;
uniform float mcut = 0.8;
uniform float hcut = 0.6;
uniform vec3 noise_off = vec3(0.0);

varying vec3 v_dir;
varying vec4 v_f0; // elev(pre-relief), temp, moist, volcanism
varying vec2 v_f1; // lake mask, land distance

void vertex() {
	v_dir = normalize(VERTEX);
	v_f0 = CUSTOM0;
	v_f1 = CUSTOM1.xy;
}

// same hash as worldgen._stable_rand
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

// matches CPU relief noise shape: 3-octave fBm, lacunarity 2.1, gain 0.52
float fbm3(vec3 p) {
	float a = 1.0;
	float s = 0.0;
	float norm = 0.0;
	for (int k = 0; k < 3; k++) {
		s += vnoise(p) * a;
		norm += a;
		a *= 0.52;
		p *= 2.1;
	}
	return s / norm;
}

vec3 srgb2lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 dir = normalize(v_dir);
	// relief detail applied here (per fragment) — coastline wiggle and small
	// islands emerge below triangle resolution
	float e = v_f0.x + fbm3((dir + noise_off) * 14.0) * 0.035;
	float t = v_f0.y;
	float m = v_f0.z;
	float volc = v_f0.w;
	float lakem = v_f1.x;
	float landd = v_f1.y;
	// medium-scale moisture pockets break up large uniform biome patches
	m = clamp(m + vnoise((dir + noise_off) * 7.0) * 0.09, 0.0, 1.0);

	bool land = e >= sea;
	float h = 0.0;
	float hd = 0.0;
	if (land) {
		h = clamp((e - sea) / max(1e-6, emax - sea), 0.0, 1.1);
	} else {
		hd = clamp((sea - e) / max(1e-6, sea - emin), 0.0, 1.1);
	}

	// stable quantized dither cells ~ render-vertex spacing, so volcano /
	// wetland speckle looks like the CPU per-vertex dither, not pixel noise
	vec3 cell = floor((dir + noise_off) * 160.0);
	float dith = hash13(cell);
	float dith2 = hash13(cell * 1.7 + 3.7);

	// ---- biome classification (same thresholds as worldgen) ----
	int b;
	if (!land) {
		if (t < 0.12) { b = 0; }
		else if (lakem > 0.5) { b = 1; }
		else if (hd < 0.09 && landd <= 1.4) { b = 2; }
		else if (hd < 0.45) { b = 3; }
		else { b = 4; }
	}
	else if (h > mcut) { b = 5; }
	else if (volc > 0.60 && h > 0.12 && dith < 0.4) { b = 6; }
	else if (t < 0.13) { b = 0; }
	else if (h > hcut) { b = 7; }
	else if (t < 0.24) { b = 8; }
	else if (t < 0.42) { b = m > 0.42 ? 9 : 8; }
	else if (m > 0.82 && h < 0.08 && t < 0.75 && dith2 < 0.55) { b = 10; }
	else if (t < 0.70) {
		if (m < 0.18) { b = 11; }
		else if (m < 0.34) { b = 12; }
		else if (m < 0.50) { b = 13; }
		else if (m < 0.64) { b = 14; }
		else { b = 15; }
	}
	else {
		if (m < 0.16) { b = 11; }
		else if (m < 0.42) { b = 16; }
		else if (m < 0.60) { b = 14; }
		else if (m < 0.78) { b = 13; }
		else { b = 17; }
	}

	// ---- terrain shading (sRGB space, matching the CPU color math) ----
	vec3 col = palette[b].rgb;
	vec3 SNOW = vec3(0.94, 0.95, 0.97);
	vec3 SAND = vec3(0.90, 0.85, 0.66);
	vec3 ICE_TINT = vec3(0.8, 0.87, 0.93);
	vec3 ocean_col = palette[3].rgb;
	vec3 deep_col = palette[4].rgb;
	vec3 mnt_col = palette[5].rgb;

	if (!land) {
		if (b == 2) { col = mix(col, ocean_col, clamp(hd * 6.0, 0.0, 0.6)); }
		else if (b == 3) { col = mix(col, deep_col, smoothstep(0.09, 0.55, hd)); }
		else if (b == 4) { col = mix(col, deep_col * 0.85, smoothstep(0.5, 1.0, hd)); }
		else if (b == 0) { col = mix(col, ICE_TINT, 0.25); }
	} else {
		if (b == 5) { col = mix(col, SNOW, smoothstep(0.55, 0.9, h + (0.24 - min(t, 0.24)))); }
		else if (b == 7) { col = mix(col, mnt_col, smoothstep(hcut, mcut, h) * 0.5); }
		// hypsometric tint: lowlands keep their biome hue, then tan
		// highlands, bare rock, and snow above — the atlas look
		vec3 TAN = vec3(0.82, 0.74, 0.55);
		vec3 ROCK = vec3(0.63, 0.57, 0.50);
		col = mix(col, TAN, smoothstep(0.30, 0.72, h) * 0.42);
		col = mix(col, ROCK, smoothstep(0.55, 0.95, h) * 0.60);
		col = mix(col, SNOW, smoothstep(0.80, 1.02, h + max(0.0, 0.20 - t) * 0.8));
		if (t < 0.20 && b != 0) { col = mix(col, SNOW, (0.20 - t) / 0.20 * 0.55); }
		// shoreline beaches
		if (h < 0.035 && t > 0.30 && b != 5 && b != 7 && b != 10) {
			col = mix(col, SAND, 0.55 * (1.0 - h / 0.035));
		}
	}
	// soft cartographic grading: mild desaturation + lift toward white
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), 0.18);
	col = mix(col, vec3(1.0), 0.08);
	float j = vnoise((dir - noise_off) * 26.0) * 0.025 + (hash13(cell + 17.0) - 0.5) * 0.012;
	col = clamp(col + vec3(j), 0.0, 1.0);

	ALBEDO = srgb2lin(col);
	// water takes a specular sun glint; land stays matte
	if (land) {
		ROUGHNESS = 0.95;
		SPECULAR = 0.12;
	} else if (b == 0) {           // sea ice: soft sheen
		ROUGHNESS = 0.55;
		SPECULAR = 0.35;
	} else {
		ROUGHNESS = mix(0.34, 0.20, clamp(hd * 2.0, 0.0, 1.0));
		SPECULAR = 0.55;
	}
}
