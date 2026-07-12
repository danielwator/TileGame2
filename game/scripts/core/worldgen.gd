# ============================================================
#  AEONS — world generation
#
#  PORTED FROM THE ORIGINAL TileGame PROJECT (C# WorldGenerator):
#  an equirectangular 1024x512 tile grid over the sphere with
#   * hidden tectonic plates (domain-warped Voronoi, drift stress)
#   * continental + detail + ridged elevation noise, polar caps
#   * moisture with ITCZ/Hadley bands and tectonic rain shadows
#   * Whittaker classification into 25 tile types
#   * lake filling/smoothing, tiny-island culling, coastal shallows
#   * depression-filled river routing with meanders
#
#  The gameplay layer is unchanged: Goldberg hex/pentagon tiles
#  sample the grid beneath them — each tile's district slots come
#  from the composition of grid cells it spans.
# ============================================================
class_name WorldGen
extends RefCounted

const GRID_W := 1024
const GRID_H := 512

# --- tuning constants (mirroring the original project's exports) ---
const SEA_LEVEL := 0.52
const SHALLOW_OFFSET := 0.05
const BEACH_OFFSET := 0.03
const MOUNTAIN_LEVEL := 0.78
const SNOW_PEAK_LEVEL := 0.88
const CONTINENTAL_FREQ := 2.0
const DETAIL_FREQ := 4.5
const MOISTURE_FREQ := 2.8
const MOISTURE_DETAIL_FREQ := 7.0
const MOISTURE_DETAIL_BLEND := 0.28
const TEMP_VARIATION_FREQ := 2.5
const TEMP_VARIATION_STRENGTH := 0.42
const VOLCANIC_RATE := 0.78
const MIN_ISLAND_SIZE := 500
const PLATE_COUNT := 14
const COASTAL_STRIP_WIDTH := 3
const RIVER_STRIDE := 60
const MIN_LAKE_SIZE := 30
const MAX_LAKE_SIZE := 2000

# building slots per gameplay tile (Stellaris-style districts)
const SLOTS_PER_TILE := 8

# --- tile types (order matches the original C# enum & shader palette) ---
enum TT {
	OCEAN, SHALLOW, CORAL,
	BEACH, MANGROVE,
	SWAMP,
	ICECAP, TUNDRA, TAIGA, PINE_FOREST,
	GRASSLAND, STEPPE, TEMPERATE_FOREST, SHRUBLAND,
	JUNGLE, TROPICAL_FOREST, SAVANNA,
	DESERT, SALT_FLAT,
	ALPINE_MEADOW, MOUNTAIN, VOLCANO, SNOW_PEAK,
	LAKE, RIVER,
}
const TT_COUNT := 25

# original project's globe palette (GlobeRenderer.cs TileColors)
const TT_COLORS: Array[Color] = [
	Color(0.05, 0.14, 0.44),   # Ocean
	Color(0.10, 0.26, 0.62),   # ShallowWater
	Color(0.06, 0.40, 0.52),   # CoralReef
	Color(0.88, 0.82, 0.58),   # Beach
	Color(0.12, 0.42, 0.24),   # Mangrove
	Color(0.20, 0.28, 0.14),   # Swamp
	Color(0.88, 0.94, 1.00),   # IceCap
	Color(0.62, 0.68, 0.58),   # Tundra
	Color(0.16, 0.36, 0.26),   # Taiga
	Color(0.10, 0.34, 0.18),   # PineForest
	Color(0.45, 0.65, 0.22),   # Grassland
	Color(0.68, 0.60, 0.28),   # Steppe
	Color(0.16, 0.50, 0.16),   # TemperateForest
	Color(0.56, 0.60, 0.24),   # Shrubland
	Color(0.02, 0.20, 0.04),   # Jungle
	Color(0.04, 0.30, 0.06),   # TropicalForest
	Color(0.80, 0.68, 0.28),   # Savanna
	Color(0.90, 0.76, 0.36),   # Desert
	Color(0.92, 0.90, 0.84),   # SaltFlat
	Color(0.55, 0.65, 0.38),   # AlpineMeadow
	Color(0.54, 0.48, 0.42),   # Mountain
	Color(0.18, 0.08, 0.06),   # Volcano
	Color(0.96, 0.97, 1.00),   # SnowPeak
	Color(0.15, 0.35, 0.66),   # Lake
	Color(0.16, 0.34, 0.68),   # River
]

# their tile types -> AEONS gameplay biome ids (data/biomes.js unchanged)
const TT_TO_BIOME := {
	TT.OCEAN: "deepOcean", TT.SHALLOW: "coast", TT.CORAL: "coast",
	TT.BEACH: "plains", TT.MANGROVE: "wetland",
	TT.SWAMP: "wetland",
	TT.ICECAP: "iceCap", TT.TUNDRA: "tundra", TT.TAIGA: "boreal", TT.PINE_FOREST: "boreal",
	TT.GRASSLAND: "grassland", TT.STEPPE: "steppe",
	TT.TEMPERATE_FOREST: "forest", TT.SHRUBLAND: "steppe",
	TT.JUNGLE: "rainforest", TT.TROPICAL_FOREST: "forest", TT.SAVANNA: "savanna",
	TT.DESERT: "desert", TT.SALT_FLAT: "desert",
	TT.ALPINE_MEADOW: "highlands", TT.MOUNTAIN: "mountain",
	TT.VOLCANO: "volcanic", TT.SNOW_PEAK: "mountain",
	TT.LAKE: "lake", TT.RIVER: "grassland",   # rivers = fertile floodplains
}

# display-mask overrides carved by post-processing (shader honours these)
enum MASK { NONE = 0, RIVER = 1, LAKE = 2, SHALLOW = 3, LAND_FILL = 4, OCEAN_FILL = 5 }


static func default_params() -> Dictionary:
	return {
		"seed": "AEONS",
		"tile_freq": 20,        # 10f^2+2 gameplay tiles
		"players": 5,
		"sea_level": SEA_LEVEL, # menu ocean slider maps here
		"temperature": 0.0,     # TemperatureBias
		"humidity": 0.0,        # MoistureBias
		"resource_richness": 1.0,
	}


static func _noise(seed_i: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_i
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.1
	n.fractal_gain = 0.48
	return n


static func generate(user_params: Dictionary) -> Dictionary:
	var P := default_params()
	P.merge(user_params, true)
	var seed_str: String = P.seed
	var seed_i: int = hash(seed_str)
	var sea: float = float(P.get("sea_level", SEA_LEVEL))
	var t0 := Time.get_ticks_msec()

	var tiles := SphereGrid.build_goldberg(int(P.tile_freq))
	var NT: int = tiles.n

	var W := GRID_W
	var H := GRID_H
	var N := W * H
	var elev := PackedFloat32Array(); elev.resize(N)
	var moist := PackedFloat32Array(); moist.resize(N)
	var geo := PackedFloat32Array(); geo.resize(N)
	var tvar := PackedFloat32Array(); tvar.resize(N)
	var ttype := PackedByteArray(); ttype.resize(N)
	var mask := PackedByteArray(); mask.resize(N)
	var stress := PackedFloat32Array(); stress.resize(N)
	var tec_field := PackedFloat32Array(); tec_field.resize(N)

	# ---------------- tectonic plates ----------------
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i ^ 0x2C3D4E
	var centers := PackedVector3Array()
	var is_conti: Array[bool] = []
	var drifts := PackedVector3Array()
	var min_sep_sq := 1.2 / PLATE_COUNT
	for i in range(PLATE_COUNT):
		var c := Vector3.ZERO
		for tries in range(8):
			var u := rng.randf() * 2.0 - 1.0
			var theta := rng.randf() * TAU
			var r := sqrt(maxf(0.0, 1.0 - u * u))
			c = Vector3(r * cos(theta), u, r * sin(theta))
			var ok := true
			for k in range(i):
				if (c - centers[k]).length_squared() < min_sep_sq:
					ok = false
					break
			if ok:
				break
		centers.append(c)
		is_conti.append(rng.randf() < 0.42)
		var da := rng.randf() * TAU
		var refv := Vector3.UP if absf(c.y) < 0.9 else Vector3.RIGHT
		var t1 := c.cross(refv).normalized()
		var t2 := c.cross(t1).normalized()
		drifts.append(t1 * cos(da) + t2 * sin(da))

	# noise stack (seeds mirror the original offsets)
	var n_cont := _noise(seed_i, CONTINENTAL_FREQ, 3)
	var n_detail := _noise(seed_i + 777, DETAIL_FREQ, 5)
	var n_moist := _noise(seed_i + 3333, MOISTURE_FREQ, 4)
	var n_mdetail := _noise(seed_i + 4444, MOISTURE_DETAIL_FREQ, 3)
	var n_geo := _noise(seed_i + 9999, 3.0, 2)
	var n_ridge := _noise(seed_i + 5555, 1.8, 5)
	n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var n_tv := _noise(seed_i + 1111, TEMP_VARIATION_FREQ, 3)
	var w_lo_x := _noise(seed_i ^ 0x1A2B3C, 0.65, 3)
	var w_lo_y := _noise(seed_i ^ 0x4D5E6F, 0.65, 3)
	var w_lo_z := _noise(seed_i ^ 0x7A8B9C, 0.65, 3)
	var w_hi_x := _noise(seed_i ^ 0xB1C2D3, 2.80, 4)
	var w_hi_y := _noise(seed_i ^ 0xE4F5A6, 2.80, 4)
	var w_hi_z := _noise(seed_i ^ 0x09C8D7, 2.80, 4)

	var ctx := {
		"W": W, "H": H, "sea": sea,
		"temp_bias": float(P.temperature), "moist_bias": float(P.humidity),
		"elev": elev, "moist": moist, "geo": geo, "tvar": tvar,
		"ttype": ttype, "stress": stress, "tec_field": tec_field,
		"centers": centers, "is_conti": is_conti, "drifts": drifts,
		"n_cont": n_cont, "n_detail": n_detail, "n_moist": n_moist,
		"n_mdetail": n_mdetail, "n_geo": n_geo, "n_ridge": n_ridge, "n_tv": n_tv,
		"w_lo_x": w_lo_x, "w_lo_y": w_lo_y, "w_lo_z": w_lo_z,
		"w_hi_x": w_hi_x, "w_hi_y": w_hi_y, "w_hi_z": w_hi_z,
	}
	var chunks: int = clampi(OS.get_processor_count(), 2, 16)
	ctx.chunks = chunks

	# pass 1: tectonic field (stress must exist before rain shadows)
	var g1 := WorkerThreadPool.add_group_task(func(c: int) -> void: _tectonic_chunk(ctx, c), chunks)
	WorkerThreadPool.wait_for_group_task_completion(g1)
	var t_tec := Time.get_ticks_msec()

	# pass 2: elevation / moisture / classification
	var g2 := WorkerThreadPool.add_group_task(func(c: int) -> void: _fill_chunk(ctx, c), chunks)
	WorkerThreadPool.wait_for_group_task_completion(g2)
	var t_fill := Time.get_ticks_msec()

	# post passes (ported: lakes, smoothing, islands, coastal water, rivers)
	_fill_lakes(ttype, mask, W, H)
	_smooth_lakes(ttype, mask, W, H, ctx)
	_remove_tiny_islands(ttype, mask, W, H)
	_ensure_coastal_water(ttype, mask, W, H)
	var route_elev := _fill_depressions(elev, sea, W, H)
	_generate_rivers(ttype, mask, elev, route_elev, seed_i, W, H)
	var t_post := Time.get_ticks_msec()

	# ---------------- gameplay tile aggregation ----------------
	# every grid cell contributes to its nearest Goldberg tile (hill-climb
	# through tile adjacency — coherent scan makes this near-O(1) per cell)
	var tally := PackedInt32Array()
	tally.resize(NT * TT_COUNT)
	var t_elev_sum := PackedFloat32Array(); t_elev_sum.resize(NT)
	var t_cnt := PackedInt32Array(); t_cnt.resize(NT)
	var t_river := PackedByteArray(); t_river.resize(NT)
	var centers_t: PackedVector3Array = tiles.centers
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var cur_tile := 0
	for x in range(W):
		var lon := (float(x) + 0.5) / W * TAU
		for y in range(H):
			var lat := (float(y) + 0.5) / H * PI - PI / 2.0
			var cos_lat := cos(lat)
			var p := Vector3(cos_lat * sin(lon), sin(lat), cos_lat * cos(lon))
			# hill-climb to the nearest tile center
			var best := cur_tile
			var best_d := centers_t[best].dot(p)
			var improved := true
			while improved:
				improved = false
				for e in range(off[best], off[best + 1]):
					var cand := nbr[e]
					var d := centers_t[cand].dot(p)
					if d > best_d:
						best_d = d
						best = cand
						improved = true
			cur_tile = best
			var idx := y * W + x
			tally[best * TT_COUNT + ttype[idx]] += 1
			t_elev_sum[best] += elev[idx]
			t_cnt[best] += 1
			if ttype[idx] == TT.RIVER:
				t_river[best] = 1

	# dominant type, biome mapping, district slots (largest remainder)
	var t_biome: Array = []
	t_biome.resize(NT)
	var t_ttype := PackedByteArray(); t_ttype.resize(NT)
	var t_land := PackedByteArray(); t_land.resize(NT)
	var t_slots: Array = []
	t_slots.resize(NT)
	for ti in range(NT):
		var best_tt := 0
		var best_c := -1
		var total := 0
		for b in range(TT_COUNT):
			var c := tally[ti * TT_COUNT + b]
			total += c
			if c > best_c:
				best_c = c
				best_tt = b
		if total == 0:
			# tiny tile got no cells (shouldn't happen at 1024x512 vs <6k tiles)
			best_tt = TT.OCEAN
			tally[ti * TT_COUNT + TT.OCEAN] = 1
			total = 1
		t_ttype[ti] = best_tt
		var bid: String = TT_TO_BIOME[best_tt]
		t_biome[ti] = bid
		t_land[ti] = 0 if Data.biomes[bid].water else 1
		# --- largest-remainder apportionment into SLOTS_PER_TILE slots ---
		var quotas: Array = []
		var assigned := 0
		for b in range(TT_COUNT):
			var c := tally[ti * TT_COUNT + b]
			if c == 0:
				continue
			var exact := float(c) * SLOTS_PER_TILE / float(total)
			var fl := int(floor(exact))
			quotas.append([b, fl, exact - fl])
			assigned += fl
		quotas.sort_custom(func(a, b): return a[2] > b[2])
		var qi := 0
		while assigned < SLOTS_PER_TILE and not quotas.is_empty():
			quotas[qi % quotas.size()][1] += 1
			assigned += 1
			qi += 1
		quotas.sort_custom(func(a, b): return a[1] > b[1])
		var slots := PackedInt32Array()
		for q: Array in quotas:
			var slot_bid: String = TT_TO_BIOME[q[0]]
			var bio_idx: int = Data.biome_index[slot_bid]
			for k in range(q[1]):
				slots.append(bio_idx)
		while slots.size() > SLOTS_PER_TILE:
			slots.remove_at(slots.size() - 1)
		while slots.size() < SLOTS_PER_TILE:
			slots.append(Data.biome_index[bid])
		t_slots[ti] = slots

	# ---------------- tile deposits (biome-weighted, seeded) ----------------
	var dep_rng := RandomNumberGenerator.new()
	dep_rng.seed = hash(seed_str + "|deposits")
	var t_deposit: Array = []
	t_deposit.resize(NT)
	var dep_base: float = 0.020 * float(P.resource_richness)
	for ti in range(NT):
		t_deposit[ti] = ""
		var b: String = t_biome[ti]
		var cands: Array = []
		var total_w := 0.0
		for dep_id: String in Data.deposits:
			var dep: Dictionary = Data.deposits[dep_id]
			if dep.spawn.has(b):
				var w: float = dep.spawn[b]
				cands.append([dep_id, w])
				total_w += w
		if cands.is_empty():
			continue
		if dep_rng.randf() < clampf(total_w * dep_base, 0.0, 0.5):
			var r := dep_rng.randf() * total_w
			for cd: Array in cands:
				r -= cd[1]
				if r <= 0.0:
					t_deposit[ti] = cd[0]
					break

	var land_tiles := PackedInt32Array()
	for ti in range(NT):
		if t_land[ti] == 1:
			land_tiles.append(ti)

	print("worldgen(port): tec %dms | fill %dms | post %dms | aggregate+slots %dms | %d tiles (%d land)" % [
		t_tec - t0, t_fill - t_tec, t_post - t_fill, Time.get_ticks_msec() - t_post, NT, land_tiles.size()])

	return {
		"params": P, "seed": seed_str, "sea": sea,
		"tiles": tiles, "NT": NT,
		"grid": {"W": W, "H": H, "elev": elev, "moist": moist, "geo": geo,
			"tvar": tvar, "ttype": ttype, "mask": mask},
		"t_biome": t_biome, "t_ttype": t_ttype, "t_land": t_land,
		"t_deposit": t_deposit, "t_river": t_river,
		"t_slots": t_slots, "slots_per_tile": SLOTS_PER_TILE,
		"land_tiles": land_tiles,
		"temp_bias": float(P.temperature), "moist_bias": float(P.humidity),
	}


# ---------------- pass 1: tectonic field ----------------

static func _tectonic_chunk(ctx: Dictionary, chunk: int) -> void:
	var W: int = ctx.W
	var H: int = ctx.H
	var x0: int = W * chunk / int(ctx.chunks)
	var x1: int = W * (chunk + 1) / int(ctx.chunks)
	var centers: PackedVector3Array = ctx.centers
	var is_conti: Array = ctx.is_conti
	var drifts: PackedVector3Array = ctx.drifts
	var stress: PackedFloat32Array = ctx.stress
	var field: PackedFloat32Array = ctx.tec_field
	var lo_x: FastNoiseLite = ctx.w_lo_x
	var lo_y: FastNoiseLite = ctx.w_lo_y
	var lo_z: FastNoiseLite = ctx.w_lo_z
	var hi_x: FastNoiseLite = ctx.w_hi_x
	var hi_y: FastNoiseLite = ctx.w_hi_y
	var hi_z: FastNoiseLite = ctx.w_hi_z
	const CONTI_BASE := 0.06
	const OCEAN_BASE := -0.05
	const MOUNTAIN_BONUS := 0.18
	const RIFT_DEPTH := 0.04
	const BOUNDARY_WIDTH := 0.07
	const WARP_LO := 0.38
	const WARP_HI := 0.11
	const BLEND_WIDTH := 0.16

	for x in range(x0, x1):
		var lon := float(x) / W * TAU
		for y in range(H):
			var idx := y * W + x
			var lat := float(y) / H * PI - PI / 2.0
			var cos_lat := cos(lat)
			var p := Vector3(cos_lat * sin(lon), sin(lat), cos_lat * cos(lon))
			var pw := Vector3(
				p.x + lo_x.get_noise_3dv(p) * WARP_LO + hi_x.get_noise_3dv(p) * WARP_HI,
				p.y + lo_y.get_noise_3dv(p) * WARP_LO + hi_y.get_noise_3dv(p) * WARP_HI,
				p.z + lo_z.get_noise_3dv(p) * WARP_LO + hi_z.get_noise_3dv(p) * WARP_HI
			).normalized()

			var d1 := 1e30
			var d2 := 1e30
			var i1 := 0
			var i2 := 1
			for k in range(PLATE_COUNT):
				var d := (pw - centers[k]).length_squared()
				if d < d1:
					d2 = d1; i2 = i1
					d1 = d; i1 = k
				elif d < d2:
					d2 = d; i2 = k

			var d_bound := sqrt(d2) - sqrt(d1)
			var alpha := clampf(d_bound / BLEND_WIDTH, 0.0, 1.0)
			var sm := alpha * alpha * (3.0 - 2.0 * alpha)
			var base1: float = CONTI_BASE if is_conti[i1] else OCEAN_BASE
			var base2: float = CONTI_BASE if is_conti[i2] else OCEAN_BASE
			var e := base1 * sm + (base1 + base2) * 0.5 * (1.0 - sm)

			var bdp := maxf(0.0, 1.0 - d_bound / BOUNDARY_WIDTH)
			var conv := 0.0
			if bdp > 0.0:
				var b_norm := (centers[i2] - centers[i1]).normalized()
				conv = (drifts[i1] - drifts[i2]).dot(b_norm)
				if conv > 0.0 and (is_conti[i1] or is_conti[i2]):
					e += MOUNTAIN_BONUS * bdp * minf(conv, 1.0)
				elif conv < 0.0 and not is_conti[i1] and not is_conti[i2]:
					e -= RIFT_DEPTH * bdp * minf(-conv, 1.0)

			stress[idx] = conv * bdp
			field[idx] = e


# ---------------- pass 2: fill (elevation / moisture / classify) ----------------

static func _fill_chunk(ctx: Dictionary, chunk: int) -> void:
	var W: int = ctx.W
	var H: int = ctx.H
	var x0: int = W * chunk / int(ctx.chunks)
	var x1: int = W * (chunk + 1) / int(ctx.chunks)
	var sea: float = ctx.sea
	var temp_bias: float = ctx.temp_bias
	var moist_bias: float = ctx.moist_bias
	var elev: PackedFloat32Array = ctx.elev
	var moist: PackedFloat32Array = ctx.moist
	var geo_a: PackedFloat32Array = ctx.geo
	var tvar: PackedFloat32Array = ctx.tvar
	var ttype: PackedByteArray = ctx.ttype
	var stress: PackedFloat32Array = ctx.stress
	var tec_field: PackedFloat32Array = ctx.tec_field
	var n_cont: FastNoiseLite = ctx.n_cont
	var n_detail: FastNoiseLite = ctx.n_detail
	var n_moist: FastNoiseLite = ctx.n_moist
	var n_mdetail: FastNoiseLite = ctx.n_mdetail
	var n_geo: FastNoiseLite = ctx.n_geo
	var n_ridge: FastNoiseLite = ctx.n_ridge
	var n_tv: FastNoiseLite = ctx.n_tv

	for x in range(x0, x1):
		var lon := float(x) / W * TAU
		for y in range(H):
			var idx := y * W + x
			var lat := float(y) / H * PI - PI / 2.0
			var cos_lat := cos(lat)
			var p := Vector3(cos_lat * sin(lon), sin(lat), cos_lat * cos(lon))
			var latitude := absf(float(y) / H * 2.0 - 1.0)

			var c := (n_cont.get_noise_3dv(p) + 1.0) * 0.5
			var d := (n_detail.get_noise_3dv(p) + 1.0) * 0.5
			var r := (n_ridge.get_noise_3dv(p) + 1.0) * 0.5
			var e := c * 0.65 + d * 0.35

			# polar icecap: jittered land-lift keeps the cap edge organic
			var pole_jitter := (c * 0.6 + d * 0.4 - 0.5) * 0.06
			var pole_land := clampf((latitude + pole_jitter - 0.92) / 0.05, 0.0, 1.0)
			pole_land = pole_land * pole_land * (3.0 - 2.0 * pole_land)
			e += pole_land * 0.16
			# gentle polar depression keeps poles ocean-dominated elsewhere
			e -= pow(latitude, 4.0) * 0.08

			e += maxf(0.0, e - sea) * r * 1.2
			e += tec_field[idx]

			var m_global := (n_moist.get_noise_3dv(p) + 1.0) * 0.5
			var m_local := (n_mdetail.get_noise_3dv(p) + 1.0) * 0.5
			var m_raw := m_global * (1.0 - MOISTURE_DETAIL_BLEND) + m_local * MOISTURE_DETAIL_BLEND
			var itcz := exp(-latitude * latitude * 15.0) * 0.18
			var hadley := exp(-(latitude - 0.25) * (latitude - 0.25) * 30.0) * 0.32
			var moisture := clampf(m_raw * 0.72 + (0.24 + itcz - hadley) * 0.28, 0.0, 1.0)

			# tectonic rain shadow (upwind stress by latitude band)
			var tec_stress := stress[idx]
			if tec_stress > 0.05:
				var wind_sign := 1.0 if (latitude < 0.33 or latitude > 0.65) else -1.0
				var up_x := posmod(x + int(wind_sign * 5.0), W)
				var up_stress := stress[y * W + up_x]
				moisture = clampf(moisture - maxf(tec_stress, up_stress) * 0.22, 0.0, 1.0)

			var geo := (n_geo.get_noise_3dv(p) + 1.0) * 0.5
			if tec_stress > 0.08:
				geo = clampf(geo + tec_stress * 0.45, 0.0, 1.0)

			var tv := (n_tv.get_noise_3dv(p) + 1.0) * 0.5

			elev[idx] = e
			moist[idx] = moisture
			geo_a[idx] = geo
			tvar[idx] = tv
			ttype[idx] = classify(e, latitude, moisture, geo, tv, sea, temp_bias, moist_bias)


## Whittaker classification — direct port of ClassifyTile
static func classify(e: float, latitude: float, moisture: float, geo: float, tv: float,
		sea: float, temp_bias: float, moist_bias: float) -> int:
	moisture = clampf(moisture + moist_bias, 0.0, 1.0)
	var sea_temp := 1.0 - latitude

	if e < sea - SHALLOW_OFFSET:
		return TT.OCEAN
	if e < sea:
		return TT.CORAL if (latitude < 0.14 and moisture < 0.52) else TT.SHALLOW
	if e < sea + BEACH_OFFSET:
		if latitude < 0.22 and moisture > 0.62:
			return TT.MANGROVE
		if moisture > 0.72 and sea_temp > 0.38:
			return TT.SWAMP
		return TT.BEACH
	if e < sea + BEACH_OFFSET + 0.05 and moisture > 0.76 and sea_temp > 0.38:
		return TT.SWAMP

	var alt_chill := maxf(0.0, (e - sea) / (MOUNTAIN_LEVEL - sea)) * 0.5
	var temp := clampf(1.0 - latitude - alt_chill + temp_bias + (tv - 0.5) * TEMP_VARIATION_STRENGTH, 0.0, 1.0)
	var temp_no_alt := clampf(1.0 - latitude + temp_bias + (tv - 0.5) * TEMP_VARIATION_STRENGTH, 0.0, 1.0)
	if temp_no_alt < 0.12:
		return TT.ICECAP

	if e >= SNOW_PEAK_LEVEL:
		return TT.SNOW_PEAK if temp_no_alt <= 0.55 else TT.MOUNTAIN
	if e >= MOUNTAIN_LEVEL:
		return TT.VOLCANO if geo > VOLCANIC_RATE else TT.MOUNTAIN
	if e >= MOUNTAIN_LEVEL - 0.08:
		var alpine_temp := clampf(1.0 - latitude - 0.35, 0.0, 1.0)
		return TT.ALPINE_MEADOW if alpine_temp > 0.22 else TT.TUNDRA

	if temp < 0.28:
		return TT.TAIGA if moisture > 0.48 else TT.TUNDRA
	if temp < 0.46:
		if moisture > 0.60: return TT.TAIGA
		if moisture > 0.42: return TT.PINE_FOREST
		if moisture > 0.26: return TT.GRASSLAND
		return TT.STEPPE if moisture > 0.12 else TT.TUNDRA
	if temp < 0.68:
		if moisture > 0.70: return TT.SWAMP
		if moisture > 0.50: return TT.TEMPERATE_FOREST
		if moisture > 0.34: return TT.GRASSLAND
		if moisture > 0.20: return TT.SHRUBLAND
		return TT.DESERT
	if moisture > 0.68: return TT.JUNGLE
	if moisture > 0.48: return TT.TROPICAL_FOREST
	if moisture > 0.32: return TT.SAVANNA
	if moisture > 0.22: return TT.SHRUBLAND
	if moisture > 0.07: return TT.DESERT
	return TT.SALT_FLAT


static func is_water_tt(t: int) -> bool:
	return t == TT.OCEAN or t == TT.SHALLOW or t == TT.CORAL or t == TT.LAKE


# ---------------- post passes (ports) ----------------

static func _fill_lakes(ttype: PackedByteArray, mask: PackedByteArray, W: int, H: int) -> void:
	var N := W * H
	var main_ocean := PackedByteArray()
	main_ocean.resize(N)
	# flood water (+icecap) from the top and bottom rows — the polar oceans
	var q := PackedInt32Array()
	for x in range(W):
		for start_i in [x, (H - 1) * W + x]:
			var t := ttype[start_i]
			if main_ocean[start_i] == 0 and (is_water_tt(t) or t == TT.ICECAP):
				main_ocean[start_i] = 1
				q.append(start_i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		var y := i / W
		for nb in [y * W + posmod(x - 1, W), y * W + posmod(x + 1, W),
				(y - 1) * W + x if y > 0 else -1, (y + 1) * W + x if y < H - 1 else -1]:
			if nb < 0 or main_ocean[nb] == 1:
				continue
			var t2 := ttype[nb]
			if is_water_tt(t2) or t2 == TT.ICECAP:
				main_ocean[nb] = 1
				q.append(nb)

	# classify disconnected water bodies
	var processed := PackedByteArray()
	processed.resize(N)
	var body := PackedInt32Array()
	for i in range(N):
		if processed[i] == 1 or main_ocean[i] == 1 or not is_water_tt(ttype[i]):
			continue
		body.clear()
		var bq := PackedInt32Array([i])
		processed[i] = 1
		var bh := 0
		while bh < bq.size():
			var ci := bq[bh]
			bh += 1
			body.append(ci)
			var cx := ci % W
			var cy := ci / W
			for nb2 in [cy * W + posmod(cx - 1, W), cy * W + posmod(cx + 1, W),
					(cy - 1) * W + cx if cy > 0 else -1, (cy + 1) * W + cx if cy < H - 1 else -1]:
				if nb2 < 0 or processed[nb2] == 1 or main_ocean[nb2] == 1:
					continue
				if is_water_tt(ttype[nb2]):
					processed[nb2] = 1
					bq.append(nb2)
		var fill: int
		var m: int
		if body.size() >= MAX_LAKE_SIZE:
			fill = TT.OCEAN
			m = MASK.NONE
		elif body.size() >= MIN_LAKE_SIZE:
			fill = TT.LAKE
			m = MASK.LAKE
		else:
			fill = TT.GRASSLAND
			m = MASK.LAND_FILL
		for bi in body:
			ttype[bi] = fill
			mask[bi] = m


static func _smooth_lakes(ttype: PackedByteArray, mask: PackedByteArray, W: int, H: int, ctx: Dictionary) -> void:
	var N := W * H
	var to_change := PackedByteArray()
	to_change.resize(N)
	for iter in range(4):
		for i in range(N):
			to_change[i] = 0
		var sctx := {"W": W, "H": H, "ttype": ttype, "to_change": to_change, "chunks": ctx.chunks}
		var gid := WorkerThreadPool.add_group_task(func(c: int) -> void: _smooth_check_chunk(sctx, c), int(ctx.chunks))
		WorkerThreadPool.wait_for_group_task_completion(gid)
		for i in range(N):
			if to_change[i] == 1:
				ttype[i] = TT.LAKE
				mask[i] = MASK.LAKE
			elif to_change[i] == 2:
				ttype[i] = TT.GRASSLAND
				mask[i] = MASK.LAND_FILL


static func _smooth_check_chunk(ctx: Dictionary, chunk: int) -> void:
	var W: int = ctx.W
	var H: int = ctx.H
	var x0: int = W * chunk / int(ctx.chunks)
	var x1: int = W * (chunk + 1) / int(ctx.chunks)
	var ttype: PackedByteArray = ctx.ttype
	var to_change: PackedByteArray = ctx.to_change
	for x in range(x0, x1):
		for y in range(H):
			var lake_nb := 0
			var total := 0
			for dy in range(-1, 2):
				var ny := y + dy
				if ny < 0 or ny >= H:
					continue
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					total += 1
					if ttype[ny * W + posmod(x + dx, W)] == TT.LAKE:
						lake_nb += 1
			if total == 0:
				continue
			var frac := float(lake_nb) / total
			var i := y * W + x
			var t := ttype[i]
			if t == TT.LAKE and frac < 0.30:
				to_change[i] = 2
			elif t != TT.LAKE and not is_water_tt(t) and t != TT.RIVER and frac >= 0.65:
				to_change[i] = 1


static func _remove_tiny_islands(ttype: PackedByteArray, mask: PackedByteArray, W: int, H: int) -> void:
	var N := W * H
	var visited := PackedByteArray()
	visited.resize(N)
	var body := PackedInt32Array()
	for i in range(N):
		if visited[i] == 1:
			continue
		if is_water_tt(ttype[i]):
			visited[i] = 1
			continue
		body.clear()
		var q := PackedInt32Array([i])
		visited[i] = 1
		var head := 0
		while head < q.size():
			var ci := q[head]
			head += 1
			body.append(ci)
			var cx := ci % W
			var cy := ci / W
			for nb in [cy * W + posmod(cx - 1, W), cy * W + posmod(cx + 1, W),
					(cy - 1) * W + cx if cy > 0 else -1, (cy + 1) * W + cx if cy < H - 1 else -1]:
				if nb < 0 or visited[nb] == 1:
					continue
				if not is_water_tt(ttype[nb]):
					visited[nb] = 1
					q.append(nb)
		if body.size() < MIN_ISLAND_SIZE:
			for bi in body:
				ttype[bi] = TT.OCEAN
				mask[bi] = MASK.OCEAN_FILL


static func _ensure_coastal_water(ttype: PackedByteArray, mask: PackedByteArray, W: int, H: int) -> void:
	var N := W * H
	var depth := PackedInt32Array()
	depth.resize(N)
	depth.fill(-1)
	var q := PackedInt32Array()
	for i in range(N):
		if not is_water_tt(ttype[i]):
			depth[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var d := depth[i]
		if d >= COASTAL_STRIP_WIDTH:
			continue
		var x := i % W
		var y := i / W
		for nb in [y * W + posmod(x - 1, W), y * W + posmod(x + 1, W),
				(y - 1) * W + x if y > 0 else -1, (y + 1) * W + x if y < H - 1 else -1]:
			if nb < 0 or depth[nb] != -1:
				continue
			if ttype[nb] != TT.OCEAN:
				continue
			depth[nb] = d + 1
			ttype[nb] = TT.SHALLOW
			mask[nb] = MASK.SHALLOW
			q.append(nb)


## Priority-Flood depression filling (Barnes et al.) — binary heap port
static func _fill_depressions(elev: PackedFloat32Array, sea: float, W: int, H: int) -> PackedFloat32Array:
	var N := W * H
	var filled := elev.duplicate()
	var in_queue := PackedByteArray()
	in_queue.resize(N)
	# binary min-heap of (key, idx)
	var heap_k := PackedFloat32Array()
	var heap_i := PackedInt32Array()

	var push := func(idx: int, key: float) -> void:
		heap_k.append(key)
		heap_i.append(idx)
		var c := heap_k.size() - 1
		while c > 0:
			var par := (c - 1) >> 1
			if heap_k[par] <= heap_k[c]:
				break
			var tk := heap_k[par]; heap_k[par] = heap_k[c]; heap_k[c] = tk
			var ti := heap_i[par]; heap_i[par] = heap_i[c]; heap_i[c] = ti
			c = par

	for i in range(N):
		if elev[i] < sea:
			in_queue[i] = 1
			push.call(i, elev[i])

	while heap_k.size() > 0:
		var e := heap_k[0]
		var idx := heap_i[0]
		# pop-min
		var last := heap_k.size() - 1
		heap_k[0] = heap_k[last]
		heap_i[0] = heap_i[last]
		heap_k.remove_at(last)
		heap_i.remove_at(last)
		var par2 := 0
		while true:
			var l := par2 * 2 + 1
			if l >= heap_k.size():
				break
			var sm := l
			if l + 1 < heap_k.size() and heap_k[l + 1] < heap_k[l]:
				sm = l + 1
			if heap_k[par2] <= heap_k[sm]:
				break
			var tk2 := heap_k[par2]; heap_k[par2] = heap_k[sm]; heap_k[sm] = tk2
			var ti2 := heap_i[par2]; heap_i[par2] = heap_i[sm]; heap_i[sm] = ti2
			par2 = sm

		var x := idx % W
		var y := idx / W
		for ni in [y * W + posmod(x - 1, W), y * W + posmod(x + 1, W),
				(y - 1) * W + x if y > 0 else -1, (y + 1) * W + x if y < H - 1 else -1]:
			if ni < 0 or in_queue[ni] == 1:
				continue
			in_queue[ni] = 1
			filled[ni] = maxf(filled[ni], e)
			push.call(ni, filled[ni])
	return filled


static func _river_source_bias(t: int) -> float:
	match t:
		TT.ICECAP, TT.SNOW_PEAK: return -999.0
		TT.TUNDRA, TT.DESERT: return -0.10
		TT.SALT_FLAT: return -0.12
		TT.STEPPE: return -0.05
		TT.SHRUBLAND: return -0.02
		TT.TAIGA: return 0.03
		TT.PINE_FOREST: return 0.04
		TT.TEMPERATE_FOREST, TT.TROPICAL_FOREST: return 0.05
		TT.JUNGLE: return 0.06
		TT.SAVANNA: return 0.01
		TT.SWAMP: return 0.03
		TT.MANGROVE: return 0.02
		_: return 0.0


static func _generate_rivers(ttype: PackedByteArray, mask: PackedByteArray,
		orig_elev: PackedFloat32Array, route_elev: PackedFloat32Array, seed_i: int, W: int, H: int) -> void:
	var src_threshold := MOUNTAIN_LEVEL - 0.14
	const MAX_LEN := 600
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i ^ 0x1A2B3C

	var bx := 0
	while bx < W:
		var by := 0
		while by < H:
			var best_e := -1e30
			var best_i := -1
			for x in range(bx, mini(bx + RIVER_STRIDE, W)):
				for y in range(by, mini(by + RIVER_STRIDE, H)):
					var i := y * W + x
					var e := orig_elev[i]
					if e < src_threshold:
						continue
					var t := ttype[i]
					if is_water_tt(t) or t == TT.RIVER:
						continue
					var score := e + _river_source_bias(t)
					if score > best_e:
						best_e = score
						best_i = i
			if best_i >= 0:
				_flow_river(ttype, mask, route_elev, best_i, MAX_LEN, rng, W, H)
			by += RIVER_STRIDE
		bx += RIVER_STRIDE


static func _nb8(i: int, W: int, H: int) -> PackedInt32Array:
	var x := i % W
	var y := i / W
	var out := PackedInt32Array()
	for dy in range(-1, 2):
		var ny := y + dy
		if ny < 0 or ny >= H:
			continue
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			out.append(ny * W + posmod(x + dx, W))
	return out


static func _flow_river(ttype: PackedByteArray, mask: PackedByteArray, route_elev: PackedFloat32Array,
		source: int, max_len: int, rng: RandomNumberGenerator, W: int, H: int) -> void:
	var best_e := route_elev[source]
	var first := -1
	for nb in _nb8(source, W, H):
		if route_elev[nb] < best_e:
			best_e = route_elev[nb]
			first = nb
	if first < 0:
		return

	var current := first
	var visited := {source: true}
	var wide_start := max_len / 5
	var wider_start := max_len / 2

	for step in range(max_len):
		if visited.has(current):
			break
		var t := ttype[current]
		if is_water_tt(t) or t == TT.RIVER or t == TT.ICECAP:
			break
		visited[current] = true
		ttype[current] = TT.RIVER
		mask[current] = MASK.RIVER

		if step >= wide_start:
			var x := current % W
			var y := current / W
			var width_nbs: Array
			if step >= wider_start:
				width_nbs = Array(_nb8(current, W, H))
			else:
				width_nbs = [y * W + posmod(x - 1, W), y * W + posmod(x + 1, W)]
				if y > 0: width_nbs.append((y - 1) * W + x)
				if y < H - 1: width_nbs.append((y + 1) * W + x)
			for nb2: int in width_nbs:
				if visited.has(nb2):
					continue
				var nt := ttype[nb2]
				if not is_water_tt(nt) and nt != TT.RIVER and nt != TT.ICECAP:
					ttype[nb2] = TT.RIVER
					mask[nb2] = MASK.RIVER

		var cur_e := route_elev[current]
		var steepest := -1
		var steepest_e := 1e30
		var downhill := PackedInt32Array()
		for nb3 in _nb8(current, W, H):
			if visited.has(nb3):
				continue
			var nb_e := route_elev[nb3]
			if nb_e < cur_e:
				downhill.append(nb3)
				if nb_e < steepest_e:
					steepest_e = nb_e
					steepest = nb3
		if downhill.size() == 0:
			break
		if downhill.size() > 1 and rng.randf() < 0.25:
			current = downhill[rng.randi_range(0, downhill.size() - 1)]
		else:
			current = steepest


# ---------------- spawn points ----------------

## Fertile, well-spread nation start tiles (on the gameplay tile layer).
static func pick_spawns(world: Dictionary, count: int) -> PackedInt32Array:
	var tiles: Dictionary = world.tiles
	var NT: int = world.NT
	var t_biome: Array = world.t_biome
	var t_deposit: Array = world.t_deposit
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var centers: PackedVector3Array = tiles.centers
	var score := PackedFloat32Array()
	score.resize(NT)
	for i in range(NT):
		var b: Dictionary = Data.biomes[t_biome[i]]
		if b.water or not b.allowsCity:
			continue
		var s: float = b.yields.food * 2.0 + b.yields.materials + b.yields.gold * 0.5
		if world.t_river[i] == 1:
			s += 2.0
		var coastal := false
		for e in range(off[i], off[i + 1]):
			var nb_i := nbr[e]
			var nb_b: Dictionary = Data.biomes[t_biome[nb_i]]
			s += (nb_b.yields.food * 1.2 + nb_b.yields.materials + nb_b.yields.gold * 0.5) * 0.4
			if t_deposit[nb_i] != "":
				s += 1.5
			if t_biome[nb_i] == "coast" or t_biome[nb_i] == "lake":
				coastal = true
		if coastal:
			s += 2.5
		score[i] = s
	var cand: Array = []
	for i in range(NT):
		if score[i] > 0:
			cand.append(i)
	cand.sort_custom(func(a, b): return score[a] > score[b])
	cand = cand.slice(0, maxi(count * 12, 120))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(world.seed) + "|spawns")
	var picked: Array = []
	if cand.is_empty():
		return PackedInt32Array()
	picked.append(cand[rng.randi_range(0, mini(9, cand.size() - 1))])
	while picked.size() < count:
		var best := -1
		var best_d := -1.0
		for ci: int in cand:
			if picked.has(ci):
				continue
			var min_d := 1e9
			for pi: int in picked:
				min_d = minf(min_d, 1.0 - centers[ci].dot(centers[pi]))
			var sc: float = min_d * (1.0 + score[ci] * 0.01)
			if sc > best_d:
				best_d = sc
				best = ci
		if best == -1:
			break
		picked.append(best)
	return PackedInt32Array(picked)
