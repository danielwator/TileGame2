# ============================================================
#  AEONS — 3D markers: city labels/bases, unit tokens, deposits
#  Pooled nodes updated per frame; respects the human's fog.
# ============================================================
class_name Markers
extends Node3D

var main
var _city_nodes := {}     # city id -> Node3D
var _unit_nodes := {}     # unit id -> Node3D
var _dep_nodes := {}      # tile -> Label3D

const UNIT_COLORS := {
	"civilian": Color(0.9, 0.9, 0.9),
	"melee": Color(0.95, 0.4, 0.35),
	"ranged": Color(0.95, 0.7, 0.3),
	"cavalry": Color(0.85, 0.5, 0.9),
	"siege": Color(0.6, 0.6, 0.6),
	"naval": Color(0.4, 0.7, 0.95),
	"air": Color(0.6, 0.9, 0.95),
}


func setup(m) -> void:
	main = m


func _process(_delta: float) -> void:
	if main == null or main.game == null:
		return
	_update_cities()
	_update_units()
	_update_deposits()


func _update_cities() -> void:
	var game = main.game
	var globe = main.globe
	var seen := {}
	for c in game.cities:
		var st: int = game.fog_state(game.human_id, c.tile)
		if st == 0:
			continue
		seen[c.id] = true
		var node: Node3D = _city_nodes.get(c.id)
		if node == null:
			node = _make_city_node()
			add_child(node)
			_city_nodes[c.id] = node
		var nat = game.nations[c.nation_id]
		var label := node.get_node("L") as Label3D
		label.text = "%s%s\n%s  •  %d" % [
			"★ " if c.is_original_capital else "", c.cname, nat.display_name, c.pop]
		label.modulate = Color(1, 1, 1)
		label.outline_modulate = Color(nat.color.r * 0.4, nat.color.g * 0.4, nat.color.b * 0.4)
		var base := node.get_node("B") as MeshInstance3D
		(base.mesh as CylinderMesh).material.albedo_color = nat.color
		var pos: Vector3 = globe.tile_world_pos(c.tile, 1.2)
		node.position = pos
		node.look_at(Vector3.ZERO)
		# damaged city indicator
		var hp_max: float = game.city_defense(c) * 2.0
		if c.hp < hp_max and c.hp > 0:
			label.text += "  ⚠"
	for id in _city_nodes.keys():
		if not seen.has(id):
			_city_nodes[id].queue_free()
			_city_nodes.erase(id)


func _make_city_node() -> Node3D:
	var node := Node3D.new()
	var base := MeshInstance3D.new()
	base.name = "B"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	base.mesh = cyl
	base.rotation_degrees = Vector3(90, 0, 0)
	node.add_child(base)
	var label := Label3D.new()
	label.name = "L"
	label.font_size = 52
	label.outline_size = 14
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.028
	label.position = Vector3(0, 0, -2.6)
	label.no_depth_test = true
	node.add_child(label)
	return node


func _update_units() -> void:
	var game = main.game
	var globe = main.globe
	var seen := {}
	# group by tile for fan-out offsets
	var idx_on_tile := {}
	for u in game.units:
		if u.hp <= 0:
			continue
		var visible: bool = u.nation_id == game.human_id or game.fog_state(game.human_id, u.tile) == 2
		if not visible:
			continue
		seen[u.id] = true
		var node: Node3D = _unit_nodes.get(u.id)
		if node == null:
			node = _make_unit_node()
			add_child(node)
			_unit_nodes[u.id] = node
		var d: Dictionary = Data.units[u.type]
		var col: Color
		if u.nation_id == -2:
			col = Color(0.25, 0.22, 0.2)
		else:
			col = game.nations[u.nation_id].color
		var body := node.get_node("M") as MeshInstance3D
		(body.mesh as CylinderMesh).material.albedo_color = col
		var ring := node.get_node("R") as MeshInstance3D
		(ring.mesh as TorusMesh).material.albedo_color = UNIT_COLORS.get(d.cls, Color.WHITE)
		var k: int = idx_on_tile.get(u.tile, 0)
		idx_on_tile[u.tile] = k + 1
		var pos: Vector3 = globe.tile_world_pos(u.tile, 1.0)
		var side := pos.cross(Vector3.UP).normalized() * (k * 1.3)
		node.position = pos + side
		node.look_at(Vector3.ZERO)
		# hp bar via label
		var lbl := node.get_node("H") as Label3D
		var frac: float = u.hp / u.max_hp
		lbl.text = "▮".repeat(clampi(int(ceil(frac * 5.0)), 0, 5))
		lbl.modulate = Color(1.0 - frac, frac, 0.15)
		var sel: bool = main.hud != null and main.hud.selected_unit_id == u.id
		lbl.text += " ◄" if sel else ""
	for id in _unit_nodes.keys():
		if not seen.has(id):
			_unit_nodes[id].queue_free()
			_unit_nodes.erase(id)


func _make_unit_node() -> Node3D:
	var node := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "M"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone.material = mat
	body.mesh = cone
	body.rotation_degrees = Vector3(-90, 0, 0)
	body.position = Vector3(0, 0, -0.8)
	node.add_child(body)
	var ring := MeshInstance3D.new()
	ring.name = "R"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.75
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = rmat
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	node.add_child(ring)
	var lbl := Label3D.new()
	lbl.name = "H"
	lbl.font_size = 30
	lbl.pixel_size = 0.02
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 0, -2.2)
	lbl.no_depth_test = true
	node.add_child(lbl)
	return node


func _update_deposits() -> void:
	var game = main.game
	var globe = main.globe
	var seen := {}
	for t in range(game.world.NT):
		var dep: String = game.deposit[t]
		if dep == "":
			continue
		if game.fog_state(game.human_id, t) == 0:
			continue
		if not game.deposit_visible(game.human_id, t):
			continue
		seen[t] = true
		var lbl: Label3D = _dep_nodes.get(t)
		if lbl == null:
			lbl = Label3D.new()
			lbl.font_size = 34
			lbl.outline_size = 10
			lbl.pixel_size = 0.024
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(lbl)
			_dep_nodes[t] = lbl
		lbl.text = "◆"
		var col := Color(0.95, 0.85, 0.4)
		match dep:
			"metals": col = Color(0.75, 0.75, 0.8)
			"coalDep": col = Color(0.35, 0.35, 0.38)
			"oilDep": col = Color(0.2, 0.2, 0.22)
			"rareEarth": col = Color(0.5, 0.9, 0.75)
			"fish": col = Color(0.5, 0.75, 0.95)
			"fertile": col = Color(0.55, 0.85, 0.4)
			"game": col = Color(0.7, 0.55, 0.35)
			"horses": col = Color(0.85, 0.7, 0.5)
			"gems": col = Color(0.9, 0.5, 0.85)
			"stone": col = Color(0.7, 0.68, 0.62)
		lbl.modulate = col
		lbl.position = globe.tile_world_pos(t, 1.0)
	for t in _dep_nodes.keys():
		if not seen.has(t):
			_dep_nodes[t].queue_free()
			_dep_nodes.erase(t)
