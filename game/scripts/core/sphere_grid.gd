# ============================================================
#  AEONS — sphere grids
#
#  Two independent layers:
#   * fine geodesic grid  — the terrain FIELD: worldgen is computed
#     and rendered per fine vertex (freq = tile_freq * detail)
#   * Goldberg tile layer — gameplay hex/pentagon tiles; each tile
#     aggregates the fine vertices that fall inside it
#
#  Geodesic vertex counts: 10*f^2 + 2
#  (tiles f=20 -> 4,002 tiles; fine f=60 -> 36,002 field verts)
# ============================================================
class_name SphereGrid
extends RefCounted

const PHI := 1.618033988749895

static var ICO_V := [
	Vector3(-1, PHI, 0), Vector3(1, PHI, 0), Vector3(-1, -PHI, 0), Vector3(1, -PHI, 0),
	Vector3(0, -1, PHI), Vector3(0, 1, PHI), Vector3(0, -1, -PHI), Vector3(0, 1, -PHI),
	Vector3(PHI, 0, -1), Vector3(PHI, 0, 1), Vector3(-PHI, 0, -1), Vector3(-PHI, 0, 1),
]
static var ICO_F := [
	[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
	[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
	[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
]


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(int(round(p.x * 100000.0)), int(round(p.y * 100000.0)), int(round(p.z * 100000.0)))


## Subdivided icosahedron. Returns:
##  verts: PackedVector3Array (unit), tris: PackedInt32Array,
##  nbr_off/nbr: CSR adjacency, cache: quantized pos -> vert index, n: count,
##  face_grids (when keep_grids): per icosa face, rows of vertex indices
static func build_geodesic(freq: int, keep_grids := false) -> Dictionary:
	var verts := PackedVector3Array()
	var cache := {}
	var tris := PackedInt32Array()
	var face_grids: Array = []

	for f: Array in ICO_F:
		var A: Vector3 = ICO_V[f[0]]
		var B: Vector3 = ICO_V[f[1]]
		var C: Vector3 = ICO_V[f[2]]
		var grid: Array = []
		for i in range(freq + 1):
			var row := PackedInt32Array()
			for j in range(freq + 1 - i):
				var p := (A + (B - A) * (float(i) / freq) + (C - A) * (float(j) / freq)).normalized()
				var k := _key(p)
				var idx: int
				if cache.has(k):
					idx = cache[k]
				else:
					idx = verts.size()
					verts.append(p)
					cache[k] = idx
				row.append(idx)
			grid.append(row)
		for i in range(freq):
			for j in range(freq - i):
				tris.append(grid[i][j]); tris.append(grid[i + 1][j]); tris.append(grid[i][j + 1])
				if j < freq - i - 1:
					tris.append(grid[i + 1][j]); tris.append(grid[i + 1][j + 1]); tris.append(grid[i][j + 1])
		if keep_grids:
			face_grids.append(grid)

	var n := verts.size()
	var nbr_sets: Array = []
	nbr_sets.resize(n)
	for i in range(n):
		nbr_sets[i] = {}
	for t in range(0, tris.size(), 3):
		var a := tris[t]; var b := tris[t + 1]; var c := tris[t + 2]
		nbr_sets[a][b] = true; nbr_sets[a][c] = true
		nbr_sets[b][a] = true; nbr_sets[b][c] = true
		nbr_sets[c][a] = true; nbr_sets[c][b] = true
	var off := PackedInt32Array()
	off.resize(n + 1)
	var total := 0
	for i in range(n):
		total += nbr_sets[i].size()
	var lst := PackedInt32Array()
	lst.resize(total)
	var pos := 0
	for i in range(n):
		off[i] = pos
		for k2: int in nbr_sets[i].keys():
			lst[pos] = k2
			pos += 1
	off[n] = pos

	return {"verts": verts, "tris": tris, "nbr_off": off, "nbr": lst, "cache": cache, "n": n,
		"face_grids": face_grids}


## High-resolution RENDER grid — arithmetic vertex dedup (corners / edges /
## interiors), no dictionaries or adjacency, so it stays fast at 500k+ verts.
## Also records (face, i, j) per vertex so climate fields computed on the
## coarser simulation grid can be barycentrically interpolated onto it.
static func build_render_grid(freq: int) -> Dictionary:
	var n_interior: int = maxi(0, (freq - 1) * (freq - 2) / 2)
	var n_total: int = 12 + 30 * (freq - 1) + 20 * n_interior
	var verts := PackedVector3Array(); verts.resize(n_total)
	var vface := PackedInt32Array(); vface.resize(n_total)
	var vi := PackedInt32Array(); vi.resize(n_total)
	var vj := PackedInt32Array(); vj.resize(n_total)

	# corners (shared icosa vertices)
	for c in range(12):
		verts[c] = (ICO_V[c] as Vector3).normalized()

	# canonical edges: 30 unique (p<q), positions from the canonical direction
	var edge_slot := {}
	var edge_ends: Array = []
	for f: Array in ICO_F:
		for pair: Array in [[f[0], f[1]], [f[0], f[2]], [f[1], f[2]]]:
			var p: int = mini(pair[0], pair[1])
			var q: int = maxi(pair[0], pair[1])
			var key: int = p * 12 + q
			if not edge_slot.has(key):
				edge_slot[key] = edge_ends.size()
				edge_ends.append([p, q])
	for e in range(edge_ends.size()):
		var P: Vector3 = ICO_V[edge_ends[e][0]]
		var Q: Vector3 = ICO_V[edge_ends[e][1]]
		var base: int = 12 + e * (freq - 1)
		for t in range(1, freq):
			verts[base + t - 1] = (P + (Q - P) * (float(t) / freq)).normalized()

	# interior row offsets (rows i = 1 .. freq-2, j = 1 .. freq-1-i)
	var row_start := PackedInt32Array(); row_start.resize(freq)
	var acc := 0
	for i in range(1, freq - 1):
		row_start[i] = acc
		acc += freq - 1 - i
	var interior_base: int = 12 + 30 * (freq - 1)

	var tris := PackedInt32Array()
	tris.resize(20 * freq * freq * 3)
	var tp := 0

	for fi in range(20):
		var f: Array = ICO_F[fi]
		var a_id: int = f[0]; var b_id: int = f[1]; var c_id: int = f[2]
		var A: Vector3 = ICO_V[a_id]; var B: Vector3 = ICO_V[b_id]; var C: Vector3 = ICO_V[c_id]
		var f_base: int = interior_base + fi * n_interior

		# per-face index resolver as row arrays (also fills positions/coords)
		var grid: Array = []
		for i in range(freq + 1):
			var row := PackedInt32Array()
			row.resize(freq + 1 - i)
			for j in range(freq + 1 - i):
				var idx: int
				if i == 0 and j == 0: idx = a_id
				elif i == freq and j == 0: idx = b_id
				elif i == 0 and j == freq: idx = c_id
				elif j == 0:
					idx = _edge_vert(edge_slot, a_id, b_id, i, freq)
				elif i == 0:
					idx = _edge_vert(edge_slot, a_id, c_id, j, freq)
				elif i + j == freq:
					idx = _edge_vert(edge_slot, b_id, c_id, j, freq)
				else:
					idx = f_base + row_start[i] + (j - 1)
					verts[idx] = (A + (B - A) * (float(i) / freq) + (C - A) * (float(j) / freq)).normalized()
				vface[idx] = fi
				vi[idx] = i
				vj[idx] = j
				row[j] = idx
			grid.append(row)

		for i in range(freq):
			for j in range(freq - i):
				tris[tp] = grid[i][j]; tris[tp + 1] = grid[i + 1][j]; tris[tp + 2] = grid[i][j + 1]
				tp += 3
				if j < freq - i - 1:
					tris[tp] = grid[i + 1][j]; tris[tp + 1] = grid[i + 1][j + 1]; tris[tp + 2] = grid[i][j + 1]
					tp += 3

	return {"verts": verts, "tris": tris, "n": n_total, "freq": freq,
		"vface": vface, "vi": vi, "vj": vj}


static func _edge_vert(edge_slot: Dictionary, va: int, vb: int, t_from_a: int, freq: int) -> int:
	var p: int = mini(va, vb)
	var q: int = maxi(va, vb)
	var e: int = edge_slot[p * 12 + q]
	var t: int = t_from_a if va == p else freq - t_from_a
	return 12 + e * (freq - 1) + (t - 1)


## Goldberg tile layer (dual of the geodesic at tile frequency).
## Returns: centers, corners (Array[PackedVector3Array], CCW from outside),
##  nbr_off/nbr CSR, pent: PackedByteArray, n, lat: PackedFloat32Array,
##  edge_corner_a/b: flattened per (tile, nbr-slot) corner indices for border ribbons
static func build_goldberg(freq: int) -> Dictionary:
	var geo := build_geodesic(freq)
	var verts: PackedVector3Array = geo.verts
	var tris: PackedInt32Array = geo.tris
	var n: int = geo.n

	# face centroids
	var n_faces := tris.size() / 3
	var centroids := PackedVector3Array()
	centroids.resize(n_faces)
	var vert_faces: Array = []
	vert_faces.resize(n)
	for i in range(n):
		vert_faces[i] = PackedInt32Array()
	for fi in range(n_faces):
		var a := tris[fi * 3]; var b := tris[fi * 3 + 1]; var c := tris[fi * 3 + 2]
		centroids[fi] = (verts[a] + verts[b] + verts[c]).normalized()
		vert_faces[a].append(fi)
		vert_faces[b].append(fi)
		vert_faces[c].append(fi)

	# order corners around each tile center
	var corners: Array = []
	corners.resize(n)
	var pent := PackedByteArray()
	pent.resize(n)
	var lat := PackedFloat32Array()
	lat.resize(n)
	for vi in range(n):
		var c: Vector3 = verts[vi]
		lat[vi] = rad_to_deg(asin(clampf(c.y, -1.0, 1.0)))
		var up := Vector3(0, 1, 0) if absf(c.y) < 0.99 else Vector3(1, 0, 0)
		var t1 := up.cross(c).normalized()
		var t2 := c.cross(t1)
		var fcs: PackedInt32Array = vert_faces[vi]
		var order: Array = []
		for fi in fcs:
			var d := centroids[fi] - c
			order.append([atan2(d.dot(t2), d.dot(t1)), fi])
		order.sort()
		var poly := PackedVector3Array()
		for o: Array in order:
			poly.append(centroids[o[1]])
		# ensure CCW seen from outside
		if poly.size() >= 3:
			var e1 := poly[1] - poly[0]
			var e2 := poly[2] - poly[0]
			if e1.cross(e2).dot(c) < 0:
				poly.reverse()
		corners[vi] = poly
		pent[vi] = 1 if poly.size() == 5 else 0

	# edge lookup: for tile i and neighbor slot -> the two consecutive corner
	# indices of tile i's polygon shared with that neighbor (for border ribbons)
	var corner_tiles := {}
	for vi in range(n):
		var poly: PackedVector3Array = corners[vi]
		for ci in range(poly.size()):
			var k := _key(poly[ci])
			if not corner_tiles.has(k):
				corner_tiles[k] = []
			corner_tiles[k].append(vi)
	var off: PackedInt32Array = geo.nbr_off
	var nbr: PackedInt32Array = geo.nbr
	var edge_a := PackedInt32Array()
	var edge_b := PackedInt32Array()
	edge_a.resize(nbr.size()); edge_a.fill(-1)
	edge_b.resize(nbr.size()); edge_b.fill(-1)
	for vi in range(n):
		var poly: PackedVector3Array = corners[vi]
		var L := poly.size()
		for ci in range(L):
			var c1 := poly[ci]
			var c2 := poly[(ci + 1) % L]
			var t1_list: Array = corner_tiles[_key(c1)]
			var t2_list: Array = corner_tiles[_key(c2)]
			for tj: int in t1_list:
				if tj != vi and t2_list.has(tj):
					# find slot of tj in vi's CSR neighbors
					for e in range(off[vi], off[vi + 1]):
						if nbr[e] == tj:
							edge_a[e] = ci
							edge_b[e] = (ci + 1) % L
							break
					break

	return {
		"centers": verts, "corners": corners, "nbr_off": off, "nbr": nbr,
		"pent": pent, "n": n, "lat": lat, "cache": geo.cache,
		"edge_a": edge_a, "edge_b": edge_b,
	}


## Assign every fine vertex to its nearest tile (BFS Voronoi on the fine graph;
## tile centers coincide with fine vertices when fine_freq % tile_freq == 0).
static func map_fine_to_tiles(fine: Dictionary, tiles: Dictionary) -> PackedInt32Array:
	var n_f: int = fine.n
	var tile_of := PackedInt32Array()
	tile_of.resize(n_f)
	tile_of.fill(-1)
	var queue: Array = []
	var centers: PackedVector3Array = tiles.centers
	var fcache: Dictionary = fine.cache
	for ti in range(tiles.n):
		var fi: int = fcache.get(_key(centers[ti]), -1)
		if fi == -1:
			# fallback: nearest fine vertex by direction (should be rare)
			var bd := -2.0
			var fverts: PackedVector3Array = fine.verts
			for j in range(n_f):
				var d := fverts[j].dot(centers[ti])
				if d > bd:
					bd = d
					fi = j
		tile_of[fi] = ti
		queue.append(fi)
	var off: PackedInt32Array = fine.nbr_off
	var nbr: PackedInt32Array = fine.nbr
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var t := tile_of[cur]
		for e in range(off[cur], off[cur + 1]):
			var nb := nbr[e]
			if tile_of[nb] == -1:
				tile_of[nb] = t
				queue.append(nb)
	return tile_of


## BFS hop distances from a set of source tiles (optionally passable-filtered).
static func bfs_distances(tiles: Dictionary, sources: Array, max_dist: int = 1000000) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(tiles.n)
	dist.fill(-1)
	var queue: Array = []
	for s: int in sources:
		if dist[s] == -1:
			dist[s] = 0
			queue.append(s)
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		if dist[cur] >= max_dist:
			continue
		for e in range(off[cur], off[cur + 1]):
			var nb := nbr[e]
			if dist[nb] == -1:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist
