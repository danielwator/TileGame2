# ============================================================
#  AEONS — parametric world generation (seeded, deterministic)
#
#  The terrain FIELD is computed per fine-grid vertex (high res),
#  fully independent of the gameplay tile layer. Pipeline:
#   1. tectonic plates    — domain-warped weighted Voronoi with
#                           per-plate motion vectors
#   2. boundary stress    — convergent -> mountain belts / arcs,
#                           divergent -> rifts / ridges
#   3. elevation          — plate base + fBm + stress + hotspots
#   4. sea level          — percentile cut at target ocean fraction
#   5. temperature        — latitude curve, altitude lapse, noise
#   6. moisture           — prevailing-wind advection from oceans,
#                           orographic rain shadows, ITCZ + horse
#                           latitudes, rank-normalized spread
#   7. biomes             — Whittaker temp x moisture matrix with
#                           percentile mountain/highland cuts
#  Tiles then AGGREGATE the field (majority biome) and get deposits.
# ============================================================
class_name WorldGen
extends RefCounted

# climate/plates simulate at tile_freq * SIM_DETAIL; the render mesh is
# tile_freq * detail (must be a multiple of SIM_DETAIL) with fields
# interpolated + re-classified per render vertex
const SIM_DETAIL := 3
# building slots per gameplay tile (Stellaris-style districts)
const SLOTS_PER_TILE := 8


static func default_params() -> Dictionary:
	return {
		"seed": "AEONS",
		"tile_freq": 20,        # 10f^2+2 tiles
		"detail": 12,           # RENDER mesh frequency multiplier (6/9/12/15)
		"ocean_fraction": 0.62,
		"plates": 14,
		"temperature": 0.0,     # -0.15 ice age .. +0.15 hothouse
		"humidity": 0.0,
		"resource_richness": 1.0,
	}


static func _seeded_rng(seed_str: String, phase: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_str + "|" + phase)
	return r


static func _stable_rand(p: Vector3) -> float:
	var x: float = sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return x - floor(x)


static func generate(user_params: Dictionary) -> Dictionary:
	var P := default_params()
	P.merge(user_params, true)
	if int(P.detail) % SIM_DETAIL != 0 or int(P.detail) < SIM_DETAIL:
		P.detail = 9
	var seed_str: String = P.seed
	var t0 := Time.get_ticks_msec()

	var tiles := SphereGrid.build_goldberg(P.tile_freq)
	var fine := SphereGrid.build_geodesic(P.tile_freq * SIM_DETAIL, true)
	var tile_of := SphereGrid.map_fine_to_tiles(fine, tiles)
	var NF: int = fine.n
	var NT: int = tiles.n
	var fverts: PackedVector3Array = fine.verts
	var foff: PackedInt32Array = fine.nbr_off
	var fnbr: PackedInt32Array = fine.nbr

	# ---------------- noise sources ----------------
	var nz_elev := FastNoiseLite.new()
	nz_elev.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_elev.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_elev.fractal_octaves = 5
	nz_elev.fractal_lacunarity = 2.1
	nz_elev.fractal_gain = 0.52
	nz_elev.frequency = 1.9
	nz_elev.seed = hash(seed_str + "|elev")

	var nz_detail := FastNoiseLite.new()
	nz_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_detail.fractal_octaves = 3
	nz_detail.fractal_lacunarity = 2.2
	nz_detail.fractal_gain = 0.5
	nz_detail.frequency = 4.8
	nz_detail.seed = hash(seed_str + "|detail")

	# ridged fractal for mountain ranges + rugged land texture
	var nz_ridge := FastNoiseLite.new()
	nz_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nz_ridge.fractal_octaves = 4
	nz_ridge.frequency = 1.8
	nz_ridge.seed = hash(seed_str + "|ridge")

	var nz_warp := FastNoiseLite.new()
	nz_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_warp.fractal_type = FastNoiseLite.FRACTAL_NONE
	nz_warp.frequency = 3.1
	nz_warp.seed = hash(seed_str + "|warp")

	var nz_clim := FastNoiseLite.new()
	nz_clim.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_clim.fractal_type = FastNoiseLite.FRACTAL_NONE
	nz_clim.frequency = 2.7
	nz_clim.seed = hash(seed_str + "|clim")

	var nz_moist := FastNoiseLite.new()
	nz_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_moist.fractal_type = FastNoiseLite.FRACTAL_NONE
	nz_moist.frequency = 3.3
	nz_moist.seed = hash(seed_str + "|moistn")

	# ---------------- 1. plates ----------------
	var rng := _seeded_rng(seed_str, "plates")
	var n_plates: int = P.plates
	var plate_seed := PackedVector3Array()
	var plate_oceanic := PackedByteArray()
	var plate_base := PackedFloat32Array()
	var plate_motion := PackedVector3Array()
	var plate_growth := PackedFloat32Array()
	for pi in range(n_plates):
		# spread seeds: best of 16 candidates by min-distance
		var best := Vector3.ZERO
		var best_score := -1.0
		for c in range(16):
			var cand := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var min_d := 10.0
			for s in range(pi):
				min_d = minf(min_d, 1.0 - cand.dot(plate_seed[s]))
			var score := min_d if pi > 0 else 1.0
			if score > best_score:
				best_score = score
				best = cand
		plate_seed.append(best)
		var oceanic := rng.randf() < 0.55
		plate_oceanic.append(1 if oceanic else 0)
		plate_base.append(rng.randf_range(-0.9, -0.45) if oceanic else rng.randf_range(0.08, 0.4))
		var up := Vector3(0, 1, 0) if absf(best.y) < 0.99 else Vector3(1, 0, 0)
		var t1 := up.cross(best).normalized()
		var t2 := best.cross(t1)
		var ang := rng.randf_range(0, TAU)
		plate_motion.append((t1 * cos(ang) + t2 * sin(ang)) * rng.randf_range(0.4, 1.0))
		plate_growth.append(rng.randf_range(0.75, 1.35))

	# domain-warped weighted nearest-seed assignment
	var plate_of := PackedInt32Array()
	plate_of.resize(NF)
	var O1 := Vector3(31.4, 0, 0)
	var O2 := Vector3(0, 47.2, 0)
	var O3 := Vector3(0, 0, 12.9)
	for i in range(NF):
		var p := fverts[i]
		var w := Vector3(
			nz_warp.get_noise_3dv(p + O1),
			nz_warp.get_noise_3dv(p + O2),
			nz_warp.get_noise_3dv(p + O3))
		var q := (p + w * 0.22).normalized()
		var best_pl := 0
		var best_d := 1e9
		for s in range(n_plates):
			var d := (1.0 - q.dot(plate_seed[s])) / plate_growth[s]
			if d < best_d:
				best_d = d
				best_pl = s
		plate_of[i] = best_pl

	# ---------------- 2. boundary stress ----------------
	var stress := PackedFloat32Array()
	stress.resize(NF)
	var volcanism := PackedFloat32Array()
	volcanism.resize(NF)
	for i in range(NF):
		var pi := plate_of[i]
		for e in range(foff[i], foff[i + 1]):
			var nb := fnbr[e]
			var pj := plate_of[nb]
			if pj == pi:
				continue
			var dir := (fverts[nb] - fverts[i]).normalized()
			var conv := -(plate_motion[pj] - plate_motion[pi]).dot(dir)
			var oi := plate_oceanic[pi] == 1
			var oj := plate_oceanic[pj] == 1
			if conv > 0.08:
				if not oi and not oj:
					stress[i] += conv * 1.5
				elif oi != oj:
					if not oi:
						stress[i] += conv * 1.1
						volcanism[i] += conv
					else:
						stress[i] -= conv * 0.5
				else:
					stress[i] += conv * 0.7
					volcanism[i] += conv * 0.8
			elif conv < -0.08:
				stress[i] += conv * 0.45
				if oi and oj:
					stress[i] += 0.04   # mid-ocean ridge stays submarine
	# diffuse stress a few hops inland
	for pass_i in range(3):
		var nxt := PackedFloat32Array()
		nxt.resize(NF)
		for i in range(NF):
			var s := stress[i]
			var cnt := 1.0
			for e in range(foff[i], foff[i + 1]):
				s += stress[fnbr[e]] * 0.55
				cnt += 0.55
			nxt[i] = s / cnt
		stress = nxt

	# ---------------- 3. elevation ----------------
	var elev := PackedFloat32Array()
	elev.resize(NF)
	for i in range(NF):
		var p := fverts[i]
		elev[i] = plate_base[plate_of[i]] \
			+ nz_elev.get_noise_3dv(p) * 0.55 \
			+ nz_detail.get_noise_3dv(p) * 0.12 \
			+ stress[i] * 0.6
	# hotspot island chains
	var hs_rng := _seeded_rng(seed_str, "hotspots")
	for h in range(hs_rng.randi_range(4, 7)):
		var t := hs_rng.randi_range(0, NF - 1)
		if plate_oceanic[plate_of[t]] == 0:
			continue
		var c0 := fverts[t]
		var up := Vector3(0, 1, 0) if absf(c0.y) < 0.99 else Vector3(1, 0, 0)
		var t1 := up.cross(c0).normalized()
		var t2 := c0.cross(t1)
		var ang := hs_rng.randf_range(0, TAU)
		var dirv := t1 * cos(ang) + t2 * sin(ang)
		var bump := hs_rng.randf_range(0.55, 0.85)
		var steps: int = hs_rng.randi_range(3, 8) * SIM_DETAIL
		bump_walk(t, dirv, bump, steps, elev, volcanism, fine, SIM_DETAIL)

	# ridged uplift — fractal mountain ranges and rugged land texture.
	# Lifts only terrain above the provisional sea level, so the land mask
	# from the percentile cut below is unchanged (ocean fraction preserved).
	var sorted0 := Array(elev)
	sorted0.sort()
	var sea0: float = sorted0[int(NF * float(P.ocean_fraction))]
	for i in range(NF):
		var above := elev[i] - sea0
		if above > 0.0:
			elev[i] += above * (nz_ridge.get_noise_3dv(fverts[i]) + 1.0) * 0.55

	# ---------------- 4. sea level ----------------
	var sorted := Array(elev)
	sorted.sort()
	var sea: float = sorted[int(NF * float(P.ocean_fraction))]
	var emax: float = sorted[NF - 1]
	var emin: float = sorted[0]
	var h_land := PackedFloat32Array(); h_land.resize(NF)
	var h_depth := PackedFloat32Array(); h_depth.resize(NF)
	var is_land := PackedByteArray(); is_land.resize(NF)
	for i in range(NF):
		if elev[i] >= sea:
			h_land[i] = (elev[i] - sea) / maxf(1e-6, emax - sea)
			is_land[i] = 1
		else:
			h_depth[i] = (sea - elev[i]) / maxf(1e-6, sea - emin)

	# lakes: small disconnected water bodies (on the fine graph)
	var is_lake := PackedByteArray(); is_lake.resize(NF)
	var comp := PackedInt32Array(); comp.resize(NF); comp.fill(-1)
	var comp_size: Array = []
	var n_comp := 0
	for i in range(NF):
		if is_land[i] == 1 or comp[i] != -1:
			continue
		var q: Array = [i]
		comp[i] = n_comp
		var head := 0
		var size := 0
		while head < q.size():
			var cur: int = q[head]
			head += 1
			size += 1
			for e in range(foff[cur], foff[cur + 1]):
				var nb := fnbr[e]
				if is_land[nb] == 0 and comp[nb] == -1:
					comp[nb] = n_comp
					q.append(nb)
		comp_size.append(size)
		n_comp += 1
	var lake_max: int = 12 * SIM_DETAIL * SIM_DETAIL
	for i in range(NF):
		if is_land[i] == 0 and comp_size[comp[i]] <= lake_max:
			is_lake[i] = 1

	# ---------------- 5. temperature ----------------
	var temp := PackedFloat32Array(); temp.resize(NF)
	for i in range(NF):
		var p := fverts[i]
		var latd: float = rad_to_deg(asin(clampf(p.y, -1.0, 1.0)))
		var t: float = pow(maxf(0.0, cos(deg_to_rad(latd))), 1.15)
		t += nz_clim.get_noise_3dv(p + Vector3(31, 0, 0)) * 0.07
		t -= h_land[i] * 0.52
		t += float(P.temperature)
		temp[i] = clampf(t, 0.0, 1.0)

	# ---------------- 6. moisture ----------------
	var moist := PackedFloat32Array(); moist.resize(NF)
	var wind := PackedVector3Array(); wind.resize(NF)
	for i in range(NF):
		var p := fverts[i]
		var latd: float = rad_to_deg(asin(clampf(p.y, -1.0, 1.0)))
		var east := p.cross(Vector3(0, 1, 0)).normalized()
		var northv := east.cross(p).normalized()
		var a := absf(latd)
		var sgn: float = 1.0 if latd >= 0 else -1.0
		var ew: float; var ns: float
		if a < 30.0:
			ew = -0.85; ns = -0.35 * sgn
		elif a < 60.0:
			ew = 0.85; ns = 0.25 * sgn
		else:
			ew = -0.8; ns = -0.2 * sgn
		wind[i] = (east * ew + northv * ns).normalized()
		if is_land[i] == 0:
			moist[i] = clampf(0.55 + temp[i] * 0.55, 0.0, 1.05)
	# advect moisture inland along the wind, with orographic decay
	var land_idx := PackedInt32Array()
	for i in range(NF):
		if is_land[i] == 1:
			land_idx.append(i)
	var passes: int = 9 * SIM_DETAIL
	for pass_i in range(passes):
		var changed := false
		for li in range(land_idx.size()):
			var i := land_idx[li]
			var best := moist[i]
			var pv := fverts[i]
			for e in range(foff[i], foff[i + 1]):
				var nb := fnbr[e]
				var carry := wind[nb].dot((pv - fverts[nb]).normalized())
				if carry <= 0.15:
					continue
				var climb := maxf(0.0, h_land[i] - h_land[nb])
				var barrier: float = 0.30 if h_land[i] > 0.45 else 0.0
				# per-hop decay adjusted for sim-grid resolution
				var decay: float = 1.0 - (0.045 + climb * 0.9 + barrier * carry) / SIM_DETAIL
				var m: float = moist[nb] * clampf(decay, 0.3, 0.995) * (0.55 + 0.45 * carry)
				if m > best:
					best = m
					changed = true
			moist[i] = best
		if not changed:
			break
	for li in range(land_idx.size()):
		var i := land_idx[li]
		var p := fverts[i]
		var latd: float = rad_to_deg(asin(clampf(p.y, -1.0, 1.0)))
		var m: float = moist[i] + nz_moist.get_noise_3dv(p - Vector3(17, 0, 0)) * 0.10 + float(P.humidity)
		m += exp(-pow(latd / 12.0, 2.0)) * 0.14                    # ITCZ rains
		m -= exp(-pow((absf(latd) - 25.0) / 9.0, 2.0)) * 0.16      # horse latitudes
		moist[i] = clampf(m, 0.0, 1.0)
	# rank-normalize blend: every world keeps a full dry-to-wet spread
	var order := Array(land_idx)
	order.sort_custom(func(a, b): return moist[a] < moist[b])
	var Lm := maxf(1.0, float(order.size() - 1))
	for r in range(order.size()):
		var i: int = order[r]
		moist[i] = clampf(moist[i] * 0.55 + (float(r) / Lm) * 0.45, 0.0, 1.0)

	# ---------------- 7. biomes (fine field) ----------------
	# percentile-based rugged cuts
	var land_h := []
	for li in range(land_idx.size()):
		land_h.append(h_land[land_idx[li]])
	land_h.sort()
	var mountain_cut := 0.52
	var hill_cut := 0.30
	if land_h.size() > 20:
		mountain_cut = maxf(land_h[int(land_h.size() * 0.92)], 0.28)
		hill_cut = maxf(land_h[int(land_h.size() * 0.78)], 0.18)

	var bidx: Dictionary = Data.biome_index
	var f_biome := PackedInt32Array(); f_biome.resize(NF)
	for i in range(NF):
		var t := temp[i]
		var m := moist[i]
		var h := h_land[i]
		var b: String
		if is_land[i] == 0:
			if t < 0.12: b = "iceCap"
			elif is_lake[i] == 1: b = "lake"
			elif h_depth[i] < 0.16 and _has_land_nbr(i, foff, fnbr, is_land): b = "coast"
			elif h_depth[i] < 0.45: b = "ocean"
			else: b = "deepOcean"
		elif h > mountain_cut: b = "mountain"
		elif volcanism[i] > 0.55 and h > 0.06 and _stable_rand(fverts[i]) < 0.5: b = "volcanic"
		elif t < 0.13: b = "iceCap"
		elif h > hill_cut: b = "highlands"
		elif t < 0.24: b = "tundra"
		elif t < 0.42: b = "boreal" if m > 0.42 else "tundra"
		elif m > 0.82 and h < 0.08 and t < 0.75 and _stable_rand(fverts[i] * 1.7) < 0.55: b = "wetland"
		elif t < 0.70:
			if m < 0.18: b = "desert"
			elif m < 0.34: b = "steppe"
			elif m < 0.50: b = "plains"
			elif m < 0.64: b = "grassland"
			else: b = "forest"
		else:
			if m < 0.16: b = "desert"
			elif m < 0.42: b = "savanna"
			elif m < 0.60: b = "grassland"
			elif m < 0.78: b = "plains"
			else: b = "rainforest"
		f_biome[i] = bidx[b]

	# ---------------- tile aggregation ----------------
	var n_biomes: int = Data.biome_order.size()
	var tally := PackedInt32Array()
	tally.resize(NT * n_biomes)
	for i in range(NF):
		tally[tile_of[i] * n_biomes + f_biome[i]] += 1
	var t_biome: Array = []
	t_biome.resize(NT)
	var t_land := PackedByteArray(); t_land.resize(NT)
	# district slots: each tile gets SLOTS building slots apportioned from the
	# biome composition it spans (largest-remainder method) — e.g. a tile that
	# is 70% forest / 20% ocean / 10% desert -> 5 forest, 2 ocean, 1 desert
	var t_slots: Array = []
	t_slots.resize(NT)
	for ti in range(NT):
		var best_b := 0
		var best_c := -1
		var total := 0
		for b in range(n_biomes):
			var c := tally[ti * n_biomes + b]
			total += c
			if c > best_c:
				best_c = c
				best_b = b
		var bid: String = Data.biome_order[best_b]
		t_biome[ti] = bid
		t_land[ti] = 0 if Data.biomes[bid].water else 1
		# --- largest-remainder apportionment into SLOTS_PER_TILE slots ---
		var quotas: Array = []   # [biome_idx, floor_count, remainder]
		var assigned := 0
		for b in range(n_biomes):
			var c := tally[ti * n_biomes + b]
			if c == 0:
				continue
			var exact: float = float(c) * SLOTS_PER_TILE / maxf(1.0, float(total))
			var fl := int(floor(exact))
			quotas.append([b, fl, exact - fl])
			assigned += fl
		quotas.sort_custom(func(x, y): return x[2] > y[2])
		var qi := 0
		while assigned < SLOTS_PER_TILE and not quotas.is_empty():
			quotas[qi % quotas.size()][1] += 1
			assigned += 1
			qi += 1
		# emit slots grouped by count (dominant biome first)
		quotas.sort_custom(func(x, y): return x[1] > y[1])
		var slots := PackedInt32Array()
		for q: Array in quotas:
			for k in range(q[1]):
				slots.append(q[0])
		while slots.size() > SLOTS_PER_TILE:
			slots.remove_at(slots.size() - 1)
		while slots.size() < SLOTS_PER_TILE:
			slots.append(best_b)
		t_slots[ti] = slots

	# tile deposits (biome-weighted, seeded)
	var dep_rng := _seeded_rng(seed_str, "deposits")
	var t_deposit: Array = []
	t_deposit.resize(NT)
	var dep_base: float = 0.020 * float(P.resource_richness) * 0.0
	dep_base = 0.020 * float(P.resource_richness)
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

	var t_sim := Time.get_ticks_msec() - t0

	# ============ HIGH-RESOLUTION RENDER FIELD ============
	# land proximity over water (for coast classification at render res)
	var land_dist := PackedFloat32Array()
	land_dist.resize(NF)
	land_dist.fill(99.0)
	var ld_q: Array = []
	for i in range(NF):
		if is_land[i] == 1:
			land_dist[i] = 0.0
			ld_q.append(i)
	var ld_head := 0
	while ld_head < ld_q.size():
		var cur: int = ld_q[ld_head]
		ld_head += 1
		if land_dist[cur] >= 6.0:
			continue
		for e in range(foff[cur], foff[cur + 1]):
			var nb := fnbr[e]
			if land_dist[nb] > land_dist[cur] + 1.0:
				land_dist[nb] = land_dist[cur] + 1.0
				ld_q.append(nb)

	var render := SphereGrid.build_render_grid(P.tile_freq * int(P.detail))
	var NR: int = render.n

	# detail noises evaluated per render vertex
	var nz_relief := FastNoiseLite.new()
	nz_relief.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_relief.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz_relief.fractal_octaves = 3
	nz_relief.frequency = 14.0
	nz_relief.seed = hash(seed_str + "|relief")
	var nz_jit := FastNoiseLite.new()
	nz_jit.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nz_jit.fractal_type = FastNoiseLite.FRACTAL_NONE
	nz_jit.frequency = 26.0
	nz_jit.seed = hash(seed_str + "|jitter")

	# biome color LUT + special indices for the shading pass
	var n_biomes2: int = Data.biome_order.size()
	var biome_cols := PackedColorArray()
	biome_cols.resize(n_biomes2)
	for b2 in range(n_biomes2):
		biome_cols[b2] = Color(Data.biomes[Data.biome_order[b2]].color)

	var ctx := {
		"NR": NR, "M": P.tile_freq * SIM_DETAIL, "k2": float(int(P.detail) / SIM_DETAIL),
		"rverts": render.verts, "vface": render.vface, "vi": render.vi, "vj": render.vj,
		"face_grids": fine.face_grids,
		"s_elev": elev, "s_temp": temp, "s_moist": moist, "s_volc": volcanism,
		"s_lake": is_lake, "s_landd": land_dist,
		"sea": sea, "emax": emax, "emin": emin,
		"mcut": mountain_cut, "hcut": hill_cut,
		"nz_relief": nz_relief, "nz_jit": nz_jit,
		"bidx": Data.biome_index, "bcols": biome_cols,
		"results": [],
	}
	var n_chunks: int = clampi(OS.get_processor_count(), 2, 16)
	ctx.chunks = n_chunks
	for c2 in range(n_chunks):
		ctx.results.append(null)
	var gid := WorkerThreadPool.add_group_task(func(chunk: int) -> void: _render_chunk(ctx, chunk), n_chunks)
	WorkerThreadPool.wait_for_group_task_completion(gid)

	var r_biome := PackedInt32Array()
	var r_hland := PackedFloat32Array()
	var r_hdepth := PackedFloat32Array()
	var r_land := PackedByteArray()
	var r_temp := PackedFloat32Array()
	var r_colors := PackedColorArray()
	var r_elev := PackedFloat32Array()
	var r_moist := PackedFloat32Array()
	var r_volc := PackedFloat32Array()
	var r_lake := PackedFloat32Array()
	var r_landd := PackedFloat32Array()
	for c3 in range(n_chunks):
		var res: Dictionary = ctx.results[c3]
		r_biome.append_array(res.biome)
		r_hland.append_array(res.hland)
		r_hdepth.append_array(res.hdepth)
		r_land.append_array(res.land)
		r_temp.append_array(res.temp)
		r_colors.append_array(res.colors)
		r_elev.append_array(res.elev)
		r_moist.append_array(res.moist)
		r_volc.append_array(res.volc)
		r_lake.append_array(res.lakem)
		r_landd.append_array(res.landd)

	print("worldgen: sim %d verts in %d ms | render %d verts in %d ms | %d tiles (%d land)" % [
		NF, t_sim, NR, Time.get_ticks_msec() - t0 - t_sim, NT, land_tiles.size()])

	return {
		"params": P, "seed": seed_str,
		"fine": fine, "tiles": tiles, "tile_of_fine": tile_of,
		"NF": NF, "NT": NT,
		"f_elev": elev, "f_hland": h_land, "f_hdepth": h_depth,
		"f_land": is_land, "f_lake": is_lake, "f_temp": temp, "f_moist": moist,
		"f_biome": f_biome, "f_plate": plate_of, "f_volcanism": volcanism,
		"mountain_cut": mountain_cut, "hill_cut": hill_cut,
		"t_biome": t_biome, "t_land": t_land, "t_deposit": t_deposit,
		"t_slots": t_slots, "slots_per_tile": SLOTS_PER_TILE,
		"land_tiles": land_tiles,
		"render": render, "NR": NR,
		"r_biome": r_biome, "r_hland": r_hland, "r_hdepth": r_hdepth,
		"r_land": r_land, "r_temp": r_temp, "r_colors": r_colors,
		"r_elev": r_elev, "r_moist": r_moist, "r_volc": r_volc,
		"r_lake": r_lake, "r_landd": r_landd,
		"sea": sea, "emax": emax, "emin": emin,
	}


## Threaded per-render-vertex pass: barycentric interpolation of the sim
## fields, relief detail noise, biome classification and terrain shading.
static func _render_chunk(ctx: Dictionary, chunk: int) -> void:
	var NR: int = ctx.NR
	var chunks: int = ctx.chunks
	var start: int = NR * chunk / chunks
	var end: int = NR * (chunk + 1) / chunks
	var count: int = end - start

	var rverts: PackedVector3Array = ctx.rverts
	var vface: PackedInt32Array = ctx.vface
	var vi_a: PackedInt32Array = ctx.vi
	var vj_a: PackedInt32Array = ctx.vj
	var face_grids: Array = ctx.face_grids
	var s_elev: PackedFloat32Array = ctx.s_elev
	var s_temp: PackedFloat32Array = ctx.s_temp
	var s_moist: PackedFloat32Array = ctx.s_moist
	var s_volc: PackedFloat32Array = ctx.s_volc
	var s_lake: PackedByteArray = ctx.s_lake
	var s_landd: PackedFloat32Array = ctx.s_landd
	var M: int = ctx.M
	var k2: float = ctx.k2
	var sea: float = ctx.sea
	var emax: float = ctx.emax
	var emin: float = ctx.emin
	var mcut: float = ctx.mcut
	var hcut: float = ctx.hcut
	var nz_relief: FastNoiseLite = ctx.nz_relief
	var nz_jit: FastNoiseLite = ctx.nz_jit
	var bidx: Dictionary = ctx.bidx
	var bcols: PackedColorArray = ctx.bcols

	# biome int ids
	var B_ICE: int = bidx["iceCap"]
	var B_LAKE: int = bidx["lake"]
	var B_COAST: int = bidx["coast"]
	var B_OCEAN: int = bidx["ocean"]
	var B_DEEP: int = bidx["deepOcean"]
	var B_MOUNTAIN: int = bidx["mountain"]
	var B_VOLC: int = bidx["volcanic"]
	var B_HIGH: int = bidx["highlands"]
	var B_TUNDRA: int = bidx["tundra"]
	var B_BOREAL: int = bidx["boreal"]
	var B_WET: int = bidx["wetland"]
	var B_DESERT: int = bidx["desert"]
	var B_STEPPE: int = bidx["steppe"]
	var B_PLAINS: int = bidx["plains"]
	var B_GRASS: int = bidx["grassland"]
	var B_FOREST: int = bidx["forest"]
	var B_SAV: int = bidx["savanna"]
	var B_RAIN: int = bidx["rainforest"]

	var SNOW := Color(0.94, 0.95, 0.97)
	var SAND := Color(0.90, 0.85, 0.66)
	var ICE_TINT := Color(0.8, 0.87, 0.93)
	var deep_col: Color = bcols[B_DEEP]
	var deep_dark := deep_col * 0.72
	var ocean_col: Color = bcols[B_OCEAN]
	var mnt_col: Color = bcols[B_MOUNTAIN]

	var o_biome := PackedInt32Array(); o_biome.resize(count)
	var o_hland := PackedFloat32Array(); o_hland.resize(count)
	var o_hdepth := PackedFloat32Array(); o_hdepth.resize(count)
	var o_land := PackedByteArray(); o_land.resize(count)
	var o_temp := PackedFloat32Array(); o_temp.resize(count)
	var o_cols := PackedColorArray(); o_cols.resize(count)
	# raw fields for the per-fragment terrain shader (elev pre-relief-noise:
	# the shader adds its own high-frequency relief so coastlines stay crisp
	# below triangle resolution)
	var o_elev := PackedFloat32Array(); o_elev.resize(count)
	var o_moist := PackedFloat32Array(); o_moist.resize(count)
	var o_volc := PackedFloat32Array(); o_volc.resize(count)
	var o_lakem := PackedFloat32Array(); o_lakem.resize(count)
	var o_landd := PackedFloat32Array(); o_landd.resize(count)

	for v in range(start, end):
		var o := v - start
		var p := rverts[v]
		# ---- barycentric weights within the sim-grid triangle ----
		var u: float = float(vi_a[v]) / k2
		var w: float = float(vj_a[v]) / k2
		var I0 := clampi(int(floor(u)), 0, M - 1)
		var J0 := clampi(int(floor(w)), 0, M - 1)
		# the face grid is triangular (row i has M+1-i entries), so the cell
		# must satisfy I0 + J0 <= M - 1; vertices on the diagonal edge
		# (u + w == M) would otherwise index past the row ends
		if I0 + J0 > M - 1:
			if J0 >= I0:
				J0 = M - 1 - I0
			else:
				I0 = M - 1 - J0
		var fu := u - I0
		var fv := w - J0
		var grid: Array = face_grids[vface[v]]
		var ia: int; var ib: int; var ic: int
		var wa: float; var wb: float; var wc: float
		# diagonal cells only contain a lower triangle — never take the
		# upper-triangle branch there even if float error pushes fu+fv past 1
		if fu + fv <= 1.0 or I0 + J0 == M - 1:
			ia = grid[I0][J0]; ib = grid[I0 + 1][J0]; ic = grid[I0][J0 + 1]
			wa = 1.0 - fu - fv; wb = fu; wc = fv
		else:
			ia = grid[I0 + 1][J0 + 1]; ib = grid[I0][J0 + 1]; ic = grid[I0 + 1][J0]
			wa = fu + fv - 1.0; wb = 1.0 - fu; wc = 1.0 - fv

		var e: float = wa * s_elev[ia] + wb * s_elev[ib] + wc * s_elev[ic]
		var t: float = wa * s_temp[ia] + wb * s_temp[ib] + wc * s_temp[ic]
		var m: float = wa * s_moist[ia] + wb * s_moist[ib] + wc * s_moist[ic]
		var volc: float = wa * s_volc[ia] + wb * s_volc[ib] + wc * s_volc[ic]
		var lakem: float = wa * s_lake[ia] + wb * s_lake[ib] + wc * s_lake[ic]
		var landd: float = wa * s_landd[ia] + wb * s_landd[ib] + wc * s_landd[ic]

		o_elev[o] = e
		o_moist[o] = m
		o_volc[o] = volc
		o_lakem[o] = lakem
		o_landd[o] = landd

		# render-scale relief detail (coastline wiggle, ridge texture)
		e += nz_relief.get_noise_3dv(p) * 0.035

		var land: bool = e >= sea
		var h := 0.0
		var hd := 0.0
		if land:
			h = clampf((e - sea) / maxf(1e-6, emax - sea), 0.0, 1.1)
		else:
			hd = clampf((sea - e) / maxf(1e-6, sea - emin), 0.0, 1.1)

		# ---- biome classification (render resolution) ----
		var b: int
		if not land:
			if t < 0.12: b = B_ICE
			elif lakem > 0.5: b = B_LAKE
			elif hd < 0.16 and landd <= 1.7: b = B_COAST
			elif hd < 0.45: b = B_OCEAN
			else: b = B_DEEP
		elif h > mcut: b = B_MOUNTAIN
		elif volc > 0.55 and h > 0.06 and _stable_rand(p) < 0.5: b = B_VOLC
		elif t < 0.13: b = B_ICE
		elif h > hcut: b = B_HIGH
		elif t < 0.24: b = B_TUNDRA
		elif t < 0.42: b = B_BOREAL if m > 0.42 else B_TUNDRA
		elif m > 0.82 and h < 0.08 and t < 0.75 and _stable_rand(p * 1.7) < 0.55: b = B_WET
		elif t < 0.70:
			if m < 0.18: b = B_DESERT
			elif m < 0.34: b = B_STEPPE
			elif m < 0.50: b = B_PLAINS
			elif m < 0.64: b = B_GRASS
			else: b = B_FOREST
		else:
			if m < 0.16: b = B_DESERT
			elif m < 0.42: b = B_SAV
			elif m < 0.60: b = B_GRASS
			elif m < 0.78: b = B_PLAINS
			else: b = B_RAIN

		# ---- terrain shading ----
		var col: Color = bcols[b]
		if not land:
			if b == B_COAST:
				col = col.lerp(ocean_col, clampf(hd * 3.5, 0.0, 0.55))
			elif b == B_OCEAN:
				col = col.lerp(deep_col, smoothstep(0.16, 0.5, hd))
			elif b == B_DEEP:
				col = col.lerp(deep_dark, smoothstep(0.5, 1.0, hd))
			elif b == B_ICE:
				col = col.lerp(ICE_TINT, 0.25)
		else:
			if b == B_MOUNTAIN:
				col = col.lerp(SNOW, smoothstep(0.55, 0.9, h + (0.24 - minf(t, 0.24))))
			elif b == B_HIGH:
				col = col.lerp(mnt_col, smoothstep(hcut, mcut, h) * 0.5)
			if t < 0.20 and b != B_ICE:
				col = col.lerp(SNOW, (0.20 - t) / 0.20 * 0.55)
			# shoreline beaches
			if h < 0.02 and t > 0.30 and b != B_MOUNTAIN and b != B_HIGH and b != B_WET:
				col = col.lerp(SAND, 0.5 * (1.0 - h / 0.02))
		var j: float = nz_jit.get_noise_3dv(p) * 0.05 + (_stable_rand(p * 3.1) - 0.5) * 0.03
		col = Color(clampf(col.r + j, 0, 1), clampf(col.g + j, 0, 1), clampf(col.b + j, 0, 1))

		o_biome[o] = b
		o_hland[o] = h
		o_hdepth[o] = hd
		o_land[o] = 1 if land else 0
		o_temp[o] = t
		o_cols[o] = col

	ctx.results[chunk] = {
		"biome": o_biome, "hland": o_hland, "hdepth": o_hdepth,
		"land": o_land, "temp": o_temp, "colors": o_cols,
		"elev": o_elev, "moist": o_moist, "volc": o_volc,
		"lakem": o_lakem, "landd": o_landd,
	}


static func _has_land_nbr(i: int, foff: PackedInt32Array, fnbr: PackedInt32Array, is_land: PackedByteArray) -> bool:
	for e in range(foff[i], foff[i + 1]):
		if is_land[fnbr[e]] == 1:
			return true
	return false


static func bump_walk(start: int, dirv: Vector3, bump0: float, steps: int, elev: PackedFloat32Array, volcanism: PackedFloat32Array, fine: Dictionary, detail: int) -> void:
	var t := start
	var bump := bump0
	var fverts: PackedVector3Array = fine.verts
	var foff: PackedInt32Array = fine.nbr_off
	var fnbr: PackedInt32Array = fine.nbr
	var decay: float = pow(0.78, 1.0 / detail)
	for s in range(steps):
		elev[t] += bump
		volcanism[t] += 0.5
		for e in range(foff[t], foff[t + 1]):
			elev[fnbr[e]] += bump * 0.3
		bump *= decay
		var best := -1
		var best_d := -1e9
		for e in range(foff[t], foff[t + 1]):
			var nb := fnbr[e]
			var d := (fverts[nb] - fverts[t]).normalized().dot(dirv)
			if d > best_d:
				best_d = d
				best = nb
		t = best


## Fertile, well-spread nation start tiles.
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
	var rng := _seeded_rng(world.seed, "spawns")
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
