# ============================================================
#  AEONS — globe renderer
#
#  Terrain: a sphere shaded by shaders/terrain.gdshader, which
#  re-classifies the ported 1024x512 field grids per fragment
#  (the original TileGame project's globe look).
#
#  Layers above it (all on the gameplay tile geometry):
#   grid      — subtle tile edge lines
#   overlay   — per-tile translucent tint: fog of war + nation color
#   borders   — nation border ribbons along tile edges
#   outlines  — selection / hover tile outlines
# ============================================================
class_name GlobeMesh
extends Node3D

const R := 100.0
const GRID_R := R * 1.004
const OVERLAY_R := R * 1.008
const BORDER_R := R * 1.012
const OUTLINE_R := R * 1.016

var world: Dictionary
var t_radius: PackedFloat32Array   # kept for markers API (flat sphere: all R)

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
	t_radius = PackedFloat32Array()
	t_radius.resize(world.NT)
	t_radius.fill(R)
	_build_terrain()
	_build_atmosphere()
	_build_grid_lines()
	_build_overlay()
	sel_line = _make_outline(Color(1, 1, 1, 0.95))
	hover_line = _make_outline(Color(1, 0.9, 0.43, 0.6))


# ---------------- terrain (field-grid sphere) ----------------

func _build_terrain() -> void:
	var grid: Dictionary = world.grid
	var W: int = grid.W
	var H: int = grid.H

	# pack the four field grids into one RGBAF image
	var fields := PackedFloat32Array()
	fields.resize(W * H * 4)
	var elev: PackedFloat32Array = grid.elev
	var moist: PackedFloat32Array = grid.moist
	var geo: PackedFloat32Array = grid.geo
	var tvar: PackedFloat32Array = grid.tvar
	for i in range(W * H):
		var o := i * 4
		fields[o] = elev[i]
		fields[o + 1] = moist[i]
		fields[o + 2] = geo[i]
		fields[o + 3] = tvar[i]
	var f_img := Image.create_from_data(W, H, false, Image.FORMAT_RGBAF, fields.to_byte_array())
	var f_tex := ImageTexture.create_from_image(f_img)

	var m_img := Image.create_from_data(W, H, false, Image.FORMAT_R8, grid.mask)
	var m_tex := ImageTexture.create_from_image(m_img)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("fields", f_tex)
	mat.set_shader_parameter("mask_tex", m_tex)
	var pal := PackedColorArray()
	pal.resize(WorldGen.TT_COUNT)
	for k in range(WorldGen.TT_COUNT):
		pal[k] = WorldGen.TT_COLORS[k]
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("sea", world.sea)
	mat.set_shader_parameter("temp_bias", world.temp_bias)
	mat.set_shader_parameter("moist_bias", world.moist_bias)
	var sh := hash(str(world.seed) + "|shader")
	mat.set_shader_parameter("noise_off", Vector3(
		float(sh % 289), float((sh / 289) % 289), float((sh / 83521) % 289)) * 0.031)

	var sphere := SphereMesh.new()
	sphere.radius = R
	sphere.height = R * 2.0
	sphere.radial_segments = 128
	sphere.rings = 64
	sphere.material = mat
	terrain = MeshInstance3D.new()
	terrain.mesh = sphere
	add_child(terrain)


func _build_atmosphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = R * 1.17
	sphere.height = R * 2.34
	sphere.radial_segments = 48
	sphere.rings = 24
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/atmosphere.gdshader")
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	add_child(mi)


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

## owner_of(tile)->int (-1 none), color_of(nation)->Color, show(tile)->bool,
## city_of(tile)->int (-1 if not part of a city) draws bright inner city rings
func set_borders(owner_of: Callable, color_of: Callable, show: Callable,
		city_of := Callable()) -> void:
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
	const CITY_INSET := 0.13
	var has_city_fn := city_of.is_valid()
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
		var my_city: int = city_of.call(ti) if has_city_fn else -1
		for e in range(off[ti], off[ti + 1]):
			var nb := nbr[e]
			var national_edge: bool = owner_of.call(nb) != o
			# city ring: between this city's tiles and anything not in the same city
			var city_edge: bool = my_city >= 0 and (not has_city_fn or city_of.call(nb) != my_city)
			if not national_edge and not city_edge:
				continue
			var ca := edge_a[e]
			var cb := edge_b[e]
			if ca < 0:
				continue
			var use_c := c
			var inset := INSET
			if city_edge and not national_edge:
				use_c = c.lerp(Color(1, 1, 1), 0.55)
				use_c.a = 0.9
				inset = CITY_INSET
			elif city_edge and national_edge:
				use_c = c.lerp(Color(1, 1, 1), 0.35)
				use_c.a = 0.9
			var p1: Vector3 = poly[ca] * BORDER_R
			var p2: Vector3 = poly[cb] * BORDER_R
			var q1 := p1.lerp(ctr, inset)
			var q2 := p2.lerp(ctr, inset)
			var base := pos.size()
			pos.append(p1); pos.append(p2); pos.append(q2); pos.append(q1)
			for k in range(4):
				col.append(use_c)
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
	var c := origin.dot(origin) - R * R
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
	return world.tiles.centers[ti] * (R + lift)
