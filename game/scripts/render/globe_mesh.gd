# ============================================================
#  AEONS — globe renderer
#
#  Layers (bottom to top):
#   terrain   — high-res fine-field mesh, vertex colors + relief
#   grid      — subtle tile edge lines (the gameplay layer)
#   overlay   — per-tile translucent tint: fog of war + nation color
#   borders   — nation border ribbons along tile edges
#   outlines  — selection / hover tile outlines
# ============================================================
class_name GlobeMesh
extends Node3D

const R := 100.0
const GRID_R := R * 1.052
const OVERLAY_R := R * 1.056
const BORDER_R := R * 1.062
const OUTLINE_R := R * 1.068

var world: Dictionary
var f_radius: PackedFloat32Array
var t_radius: PackedFloat32Array

var terrain: MeshInstance3D
var grid_lines: MeshInstance3D
var overlay: MeshInstance3D
var borders: MeshInstance3D
var sel_line: MeshInstance3D
var hover_line: MeshInstance3D

var _overlay_pos: PackedVector3Array
var _overlay_idx: PackedInt32Array
var _overlay_col: PackedColorArray
var _overlay_vstart: PackedInt32Array
var _overlay_vcount: PackedInt32Array

func build(w: Dictionary) -> void:
	world = w
	for c in get_children():
		c.queue_free()
	_build_terrain()
	_build_grid_lines()
	_build_overlay()
	sel_line = _make_outline(Color(1, 1, 1, 0.95))
	hover_line = _make_outline(Color(1, 0.9, 0.43, 0.6))


# ---------------- terrain (fine field) ----------------

func _build_terrain() -> void:
	var render: Dictionary = world.render
	var NR: int = world.NR
	var rverts: PackedVector3Array = render.verts
	var tris: PackedInt32Array = render.tris
	var r_land: PackedByteArray = world.r_land
	var r_hland: PackedFloat32Array = world.r_hland
	var r_colors: PackedColorArray = world.r_colors

	var pos := PackedVector3Array()
	pos.resize(NR)
	for i in range(NR):
		pos[i] = rverts[i] * (R * (1.0 + (r_hland[i] * 0.04 if r_land[i] == 1 else 0.0)))
	var col := r_colors

	# per-tile mean render radius (markers sit on this) — from the sim grid
	var NF: int = world.NF
	var f_hland: PackedFloat32Array = world.f_hland
	var f_land: PackedByteArray = world.f_land
	f_radius = PackedFloat32Array()
	f_radius.resize(NF)
	for i in range(NF):
		f_radius[i] = R * (1.0 + (f_hland[i] * 0.04 if f_land[i] == 1 else 0.0))
	var NT: int = world.NT
	t_radius = PackedFloat32Array()
	t_radius.resize(NT)
	var cnt := PackedInt32Array()
	cnt.resize(NT)
	var tof: PackedInt32Array = world.tile_of_fine
	for i in range(NF):
		t_radius[tof[i]] += f_radius[i]
		cnt[tof[i]] += 1
	for ti in range(NT):
		t_radius[ti] = t_radius[ti] / maxf(1.0, float(cnt[ti]))

	# smooth normals accumulated from faces (source tris are CCW-from-outside,
	# so this cross product points outward)
	var nrm := PackedVector3Array()
	nrm.resize(NR)
	for t in range(0, tris.size(), 3):
		var a := tris[t]; var b := tris[t + 1]; var c := tris[t + 2]
		var fn := (pos[b] - pos[a]).cross(pos[c] - pos[a])
		nrm[a] += fn; nrm[b] += fn; nrm[c] += fn
	for i in range(NR):
		nrm[i] = nrm[i].normalized()

	# Godot front faces are CLOCKWISE (opposite of the CCW source data):
	# flip each triangle so the outside is front-facing and back-culling works
	var idx := PackedInt32Array()
	idx.resize(tris.size())
	for t in range(0, tris.size(), 3):
		idx[t] = tris[t]
		idx[t + 1] = tris[t + 2]
		idx[t + 2] = tris[t + 1]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	terrain = MeshInstance3D.new()
	terrain.mesh = mesh
	add_child(terrain)


# ---------------- tile grid lines ----------------

func _build_grid_lines() -> void:
	var tiles: Dictionary = world.tiles
	var pos := PackedVector3Array()
	var seen := {}
	for ti in range(world.NT):
		var poly: PackedVector3Array = tiles.corners[ti]
		var L := poly.size()
		for k in range(L):
			var a: Vector3 = poly[k]
			var b: Vector3 = poly[(k + 1) % L]
			var ka := SphereGrid._key(a)
			var kb := SphereGrid._key(b)
			var ek := str(ka) + "|" + str(kb) if str(ka) < str(kb) else str(kb) + "|" + str(ka)
			if seen.has(ek):
				continue
			seen[ek] = true
			pos.append(a * GRID_R)
			pos.append(b * GRID_R)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)
	grid_lines = MeshInstance3D.new()
	grid_lines.mesh = mesh
	add_child(grid_lines)


# ---------------- per-tile overlay (fog + political tint) ----------------

func _build_overlay() -> void:
	var tiles: Dictionary = world.tiles
	var NT: int = world.NT
	_overlay_pos = PackedVector3Array()
	_overlay_col = PackedColorArray()
	var idx: Array = []
	_overlay_vstart = PackedInt32Array(); _overlay_vstart.resize(NT)
	_overlay_vcount = PackedInt32Array(); _overlay_vcount.resize(NT)
	for ti in range(NT):
		var poly: PackedVector3Array = tiles.corners[ti]
		var base := _overlay_pos.size()
		_overlay_vstart[ti] = base
		_overlay_vcount[ti] = poly.size() + 1
		_overlay_pos.append(tiles.centers[ti] * OVERLAY_R)
		for c in poly:
			_overlay_pos.append(c * OVERLAY_R)
		var L := poly.size()
		for k in range(L):
			# corners are CCW-from-outside; emit CW for Godot front-facing
			idx.append(base)
			idx.append(base + 1 + ((k + 1) % L))
			idx.append(base + 1 + k)
	_overlay_idx = PackedInt32Array(idx)
	_overlay_col.resize(_overlay_pos.size())
	for i in range(_overlay_col.size()):
		_overlay_col[i] = Color(0, 0, 0, 0)
	overlay = MeshInstance3D.new()
	add_child(overlay)
	_rebuild_overlay_mesh()


func _rebuild_overlay_mesh() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _overlay_pos
	arrays[Mesh.ARRAY_COLOR] = _overlay_col
	arrays[Mesh.ARRAY_INDEX] = _overlay_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mesh.surface_set_material(0, mat)
	overlay.mesh = mesh


## color_fn(tile_index) -> Color (alpha 0 = fully see-through)
func set_overlay_colors(color_fn: Callable) -> void:
	for ti in range(world.NT):
		var c: Color = color_fn.call(ti)
		var s := _overlay_vstart[ti]
		for v in range(_overlay_vcount[ti]):
			_overlay_col[s + v] = c
	_rebuild_overlay_mesh()


# ---------------- nation borders ----------------

## owner_of(tile)->int (-1 none), color_of(nation)->Color, show(tile)->bool
func set_borders(owner_of: Callable, color_of: Callable, show: Callable) -> void:
	if borders != null:
		borders.queue_free()
		borders = null
	var tiles: Dictionary = world.tiles
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var edge_a: PackedInt32Array = tiles.edge_a
	var edge_b: PackedInt32Array = tiles.edge_b
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var idx: Array = []
	const INSET := 0.22
	for ti in range(world.NT):
		var o: int = owner_of.call(ti)
		if o < 0:
			continue
		if not show.call(ti):
			continue
		var c: Color = color_of.call(o)
		c.a = 0.85
		var poly: PackedVector3Array = tiles.corners[ti]
		var ctr: Vector3 = tiles.centers[ti] * BORDER_R
		for e in range(off[ti], off[ti + 1]):
			if owner_of.call(nbr[e]) == o:
				continue
			var ca := edge_a[e]
			var cb := edge_b[e]
			if ca < 0:
				continue
			var p1: Vector3 = poly[ca] * BORDER_R
			var p2: Vector3 = poly[cb] * BORDER_R
			var q1 := p1.lerp(ctr, INSET)
			var q2 := p2.lerp(ctr, INSET)
			var base := pos.size()
			pos.append(p1); pos.append(p2); pos.append(q2); pos.append(q1)
			for k in range(4):
				col.append(c)
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if pos.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(idx)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	borders = MeshInstance3D.new()
	borders.mesh = mesh
	add_child(borders)


# ---------------- outlines ----------------

func _make_outline(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.visible = false
	mi.set_meta("color", color)
	add_child(mi)
	return mi


func _set_outline(mi: MeshInstance3D, ti: int, lift: float) -> void:
	if ti < 0:
		mi.visible = false
		return
	var poly: PackedVector3Array = world.tiles.corners[ti]
	var pos := PackedVector3Array()
	var L := poly.size()
	for k in range(L):
		pos.append(poly[k] * (OUTLINE_R + lift))
		pos.append(poly[(k + 1) % L] * (OUTLINE_R + lift))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = mi.get_meta("color")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.visible = true


func set_selection(ti: int) -> void:
	_set_outline(sel_line, ti, 0.4)


func set_hover(ti: int) -> void:
	_set_outline(hover_line, ti, 0.2)


# ---------------- picking / positions ----------------

## Ray-sphere intersection then nearest tile center. -1 if missed.
func tile_from_ray(origin: Vector3, dir: Vector3) -> int:
	var b := 2.0 * origin.dot(dir)
	var c := origin.dot(origin) - R * R * 1.045 * 1.045
	var disc := b * b - 4.0 * c
	if disc < 0.0:
		return -1
	var t := (-b - sqrt(disc)) / 2.0
	if t < 0.0:
		return -1
	var hit := (origin + dir * t).normalized()
	var centers: PackedVector3Array = world.tiles.centers
	var best := -1
	var best_d := -2.0
	for i in range(world.NT):
		var d := centers[i].dot(hit)
		if d > best_d:
			best_d = d
			best = i
	return best


func tile_world_pos(ti: int, lift: float = 0.0) -> Vector3:
	return world.tiles.centers[ti] * (maxf(t_radius[ti], R) + lift)
