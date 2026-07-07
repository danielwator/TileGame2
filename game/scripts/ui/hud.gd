# ============================================================
#  AEONS — in-game HUD & screens
#  Top resource bar, tile/city panels, tech tree, policies,
#  diplomacy, event/perk/victory dialogs, pause menu, toasts.
# ============================================================
extends CanvasLayer

var main
var game

var selected_unit_id := -1

var _res_labels := {}
var _research_btn: Button
var _age_label: Label
var _toast_box: VBoxContainer
var _tile_panel: PanelContainer
var _tile_box: VBoxContainer
var _city_panel: PanelContainer
var _city_box: VBoxContainer
var _hover_label: Label
var _speed_btns: Array = []
var _win_layer: Control          # dim background for windows
var _window: PanelContainer      # current modal window
var _dialog: PanelContainer      # event/perk/victory dialog
var _refresh_accum := 0.0

const COL_BG := Color(0.055, 0.075, 0.115, 0.94)
const COL_ACCENT := Color(0.91, 0.76, 0.35)
const COL_ACCENT2 := Color(0.37, 0.73, 0.81)
const COL_DIM := Color(0.55, 0.6, 0.68)
const COL_GOOD := Color(0.49, 0.82, 0.49)
const COL_BAD := Color(0.88, 0.48, 0.42)

const RES_ORDER := ["food", "materials", "gold", "influence", "coal", "oil", "circuits"]
const RES_SHORT := {"food": "Food", "materials": "Mat", "gold": "Gold", "influence": "Inf",
	"coal": "Coal", "oil": "Oil", "circuits": "Circ"}
const RES_COLORS := {"food": Color(0.56, 0.81, 0.37), "materials": Color(0.79, 0.64, 0.37),
	"gold": Color(0.95, 0.79, 0.3), "influence": Color(0.71, 0.55, 0.88),
	"coal": Color(0.55, 0.55, 0.6), "oil": Color(0.45, 0.42, 0.4), "circuits": Color(0.37, 0.81, 0.63)}


func setup(m) -> void:
	main = m
	game = m.game
	_build_topbar()
	_build_toasts()
	_build_panels()
	_build_hover_label()
	_build_win_layer()
	game.toast.connect(_on_toast)
	game.event_popup.connect(_on_event_popup)
	game.perk_offer.connect(_on_perk_offer)
	game.victory.connect(_on_victory)


func _pstyle(border := Color(0.17, 0.21, 0.31)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(10)
	return s


# ================= top bar =================

func _build_topbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var st := _pstyle()
	st.set_corner_radius_all(0)
	st.set_content_margin_all(6)
	bar.add_theme_stylebox_override("panel", st)
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	for k in RES_ORDER:
		var l := Label.new()
		l.add_theme_color_override("font_color", RES_COLORS[k])
		l.add_theme_font_size_override("font_size", 14)
		h.add_child(l)
		_res_labels[k] = l

	_research_btn = Button.new()
	_research_btn.flat = true
	_research_btn.add_theme_color_override("font_color", COL_ACCENT2)
	_research_btn.pressed.connect(func() -> void: _open_tech_window())
	h.add_child(_research_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_age_label = Label.new()
	_age_label.add_theme_color_override("font_color", COL_ACCENT)
	h.add_child(_age_label)

	for cfg in [["II", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := Button.new()
		b.text = cfg[0]
		b.custom_minimum_size = Vector2(34, 0)
		var spd: float = cfg[1]
		b.pressed.connect(func() -> void: _set_speed(spd))
		h.add_child(b)
		_speed_btns.append([b, spd])

	for cfg2: Array in [["Tech", "tech"], ["Policies", "policy"], ["Diplomacy", "diplo"], ["Menu", "pause"]]:
		var b2 := Button.new()
		b2.text = cfg2[0]
		var which: String = cfg2[1]
		b2.pressed.connect(func() -> void: _open(which))
		h.add_child(b2)


func _open(which: String) -> void:
	match which:
		"tech": _open_tech_window()
		"policy": _open_policy_window()
		"diplo": _open_diplo_window()
		"pause": _open_pause_menu()


func _set_speed(s: float) -> void:
	game.speed = s
	for pair: Array in _speed_btns:
		var b: Button = pair[0]
		b.modulate = Color(1.4, 1.3, 0.9) if pair[1] == s else Color(1, 1, 1)


func tick_update(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < 0.25:
		return
	_refresh_accum = 0.0
	var nat = game.nations[game.human_id]
	var income: Dictionary = nat.get_meta("income") if nat.has_meta("income") else {}
	var upkeep: Dictionary = nat.get_meta("upkeep") if nat.has_meta("upkeep") else {}
	for k in RES_ORDER:
		var l: Label = _res_labels[k]
		if (k == "coal" and nat.age < 5) or (k == "oil" and nat.age < 6) or (k == "circuits" and nat.age < 7):
			l.visible = false
			continue
		l.visible = true
		var rate: float = income.get(k, 0.0)
		if k == "gold":
			rate -= upkeep.get("gold", 0.0)
		elif k == "influence":
			rate -= upkeep.get("influence", 0.0)
		elif k == "food":
			var pop := 0
			for c in game.cities_of(game.human_id):
				pop += c.pop
			rate -= pop
		l.text = "%s %d (%s%.1f)" % [RES_SHORT[k], int(nat.res[k]), "+" if rate >= 0 else "", rate]
	# research
	if nat.researching != "":
		var t: Dictionary = Data.techs[nat.researching]
		_research_btn.text = "Sci: %s  %d/%d (+%.1f)" % [t.name, int(nat.research_progress), int(t.cost), income.get("science", 0.0)]
	else:
		_research_btn.text = "Sci: CHOOSE RESEARCH (+%.1f)" % income.get("science", 0.0)
	var age_def: Dictionary = Data.age_by_id[nat.age]
	var yr := int(absf(game.year))
	_age_label.text = "%s  •  %d %s" % [age_def.short, yr, "BC" if game.year < 0 else "AD"]
	# refresh open panels
	if _tile_panel.visible:
		_refresh_tile_panel()
	if _city_panel.visible:
		_refresh_city_panel()


# ================= toasts =================

func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(0, 46)
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toast_box)


func _on_toast(msg: String, kind: String) -> void:
	var p := PanelContainer.new()
	var border := COL_ACCENT2
	if kind == "warn":
		border = COL_BAD
	elif kind == "good":
		border = COL_GOOD
	p.add_theme_stylebox_override("panel", _pstyle(border))
	var l := Label.new()
	l.text = msg
	p.add_child(l)
	_toast_box.add_child(p)
	if _toast_box.get_child_count() > 5:
		_toast_box.get_child(0).queue_free()
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


# ================= hover label =================

func _build_hover_label() -> void:
	_hover_label = Label.new()
	_hover_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hover_label.position = Vector2(10, -30)
	_hover_label.add_theme_color_override("font_color", COL_DIM)
	_hover_label.add_theme_font_size_override("font_size", 13)
	add_child(_hover_label)


func on_hover_tile(t: int) -> void:
	if t < 0:
		_hover_label.text = ""
		return
	var bio: Dictionary = Data.biomes[game.world.t_biome[t]]
	var txt: String = bio.name
	var o: int = game.owner[t]
	if o >= 0 and game.fog_state(game.human_id, t) >= 1:
		txt += "  •  " + game.nations[o].display_name
	if game.deposit_visible(game.human_id, t):
		txt += "  •  " + Data.deposits[game.deposit[t]].name
	_hover_label.text = txt


# ================= tile & city panels =================

func _build_panels() -> void:
	_tile_panel = PanelContainer.new()
	_tile_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_tile_panel.position = Vector2(-330, 46)
	_tile_panel.custom_minimum_size = Vector2(320, 0)
	_tile_panel.add_theme_stylebox_override("panel", _pstyle())
	_tile_panel.visible = false
	add_child(_tile_panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 0)
	_tile_panel.add_child(sc)
	_tile_box = VBoxContainer.new()
	_tile_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_tile_box)

	_city_panel = PanelContainer.new()
	_city_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_city_panel.position = Vector2(10, 46)
	_city_panel.custom_minimum_size = Vector2(340, 0)
	_city_panel.add_theme_stylebox_override("panel", _pstyle())
	_city_panel.visible = false
	add_child(_city_panel)
	var sc2 := ScrollContainer.new()
	sc2.custom_minimum_size = Vector2(320, 0)
	_city_panel.add_child(sc2)
	_city_box = VBoxContainer.new()
	_city_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(_city_box)


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _lbl(box: Container, text: String, color := Color(0.82, 0.86, 0.92), size := 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _btn(box: Container, text: String, cb: Callable, enabled := true, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func on_select_tile(t: int) -> void:
	selected_unit_id = -1
	if t < 0:
		_tile_panel.visible = false
		_city_panel.visible = false
		return
	_tile_panel.visible = true
	_refresh_tile_panel()
	var c = game.city_at(t)
	_city_panel.visible = c != null and game.fog_state(game.human_id, t) == 2
	if _city_panel.visible:
		_refresh_city_panel()


func _refresh_tile_panel() -> void:
	var t: int = main.selected_tile
	if t < 0:
		_tile_panel.visible = false
		return
	_clear(_tile_box)
	var fogst: int = game.fog_state(game.human_id, t)
	var bio: Dictionary = Data.biomes[game.world.t_biome[t]]
	_lbl(_tile_box, bio.name, COL_ACCENT, 16)
	var o: int = game.owner[t]
	if o >= 0:
		_lbl(_tile_box, "Territory of %s" % game.nations[o].display_name, game.nations[o].color)
	# yields
	var ytxt := ""
	for k: String in bio.yields:
		if float(bio.yields[k]) > 0:
			ytxt += "%s +%s  " % [RES_SHORT.get(k, k), str(bio.yields[k])]
	if ytxt != "":
		_lbl(_tile_box, "Base yields: " + ytxt, COL_DIM)
	if game.deposit_visible(game.human_id, t):
		var dep: Dictionary = Data.deposits[game.deposit[t]]
		_lbl(_tile_box, "Deposit: %s — %s" % [dep.name, dep.effect], Color(0.95, 0.85, 0.4))
	if fogst < 2:
		_lbl(_tile_box, "(Intel only — tile is not currently visible)", COL_DIM, 11)
		return

	# building
	var b = game.buildings[t]
	if b != null:
		var bdef: Dictionary = Data.buildings[b.id]
		if b.done:
			_lbl(_tile_box, "Building: %s" % bdef.name, COL_ACCENT2)
		else:
			_lbl(_tile_box, "Constructing %s  (%d/%d)" % [bdef.name, b.progress, b.time], COL_ACCENT2)

	# units on tile
	var here: Array = game.units_on(t)
	if not here.is_empty():
		_lbl(_tile_box, "Units:", COL_DIM)
		for u in here:
			if u.nation_id != game.human_id and game.fog_state(game.human_id, t) < 2:
				continue
			var d: Dictionary = Data.units[u.type]
			var owner_tag: String = "" if u.nation_id == game.human_id else (
				" [%s]" % (game.nations[u.nation_id].display_name if u.nation_id >= 0 else "Raiders"))
			var uid: int = u.id
			var btn := _btn(_tile_box, "%s%s  %d/%d HP%s" % [d.name, owner_tag, int(u.hp), int(u.max_hp),
				"  ◄" if selected_unit_id == u.id else ""],
				func() -> void: _select_unit(uid), u.nation_id == game.human_id,
				"Select, then right-click a destination to move or attack.")
			if u.nation_id != game.human_id:
				btn.disabled = true

	# unit actions
	var su = _selected_unit()
	if su != null and su.tile == t:
		if su.type == "settler":
			var why: String = game.can_found_city(game.human_id, t)
			_btn(_tile_box, "Found City here", func() -> void: _found_city_now(), why == "", why)
		_btn(_tile_box, "Disband unit", func() -> void: _disband_unit())

	# claim
	if o == -1:
		var why2: String = game.can_claim(game.human_id, t)
		if why2 == "":
			var cost := int(game.claim_cost(game.human_id, t))
			_btn(_tile_box, "Claim tile (%d Influence)" % cost, func() -> void:
				game.claim_tile(game.human_id, t)
				_refresh_tile_panel(), true)
		else:
			_lbl(_tile_box, why2, COL_DIM, 11)

	# build menu
	if o == game.human_id and b == null and game.tile_city[t] >= 0:
		_lbl(_tile_box, "Construct:", COL_DIM)
		var nat = game.nations[game.human_id]
		var shown := 0
		for bdef2: Dictionary in Data.building_list:
			if bdef2.id == "cityCenter":
				continue
			if bdef2.tech != null and not nat.researched.has(bdef2.tech):
				continue
			var why3: String = game.can_build(game.human_id, t, bdef2.id)
			if why3 != "" and not why3.begins_with("Not enough"):
				continue
			shown += 1
			var cost_txt := ""
			for k2: String in bdef2.cost:
				if float(bdef2.cost[k2]) > 0:
					cost_txt += "%d %s  " % [int(bdef2.cost[k2]), RES_SHORT.get(k2, k2)]
			var out_txt := ""
			for k3: String in bdef2.yields:
				out_txt += "+%s %s  " % [str(bdef2.yields[k3]), RES_SHORT.get(k3, k3)]
			var bid: String = bdef2.id
			_btn(_tile_box, "%s  (%s)" % [bdef2.name, cost_txt.strip_edges()],
				func() -> void:
					game.start_building(game.human_id, t, bid)
					_refresh_tile_panel(),
				why3 == "",
				"%s\n%s%s" % [bdef2.desc, out_txt, ("\n" + why3) if why3 != "" else ""])
		if shown == 0:
			_lbl(_tile_box, "Nothing can be built here yet.", COL_DIM, 11)


func _selected_unit():
	for u in game.units:
		if u.id == selected_unit_id:
			return u
	return null


func _select_unit(uid: int) -> void:
	selected_unit_id = uid if selected_unit_id != uid else -1
	_refresh_tile_panel()


func _found_city_now() -> void:
	var su = _selected_unit()
	if su == null:
		return
	if game.can_found_city(game.human_id, su.tile) == "":
		game.found_city(game.human_id, su.tile)
		su.hp = -1
		game.cull_dead_units()
		selected_unit_id = -1
		on_select_tile(main.selected_tile)


func _disband_unit() -> void:
	var su = _selected_unit()
	if su != null:
		su.hp = -1
		game.cull_dead_units()
		selected_unit_id = -1
		_refresh_tile_panel()


func on_right_click_tile(t: int) -> void:
	if t < 0:
		return
	var su = _selected_unit()
	if su == null or su.nation_id != game.human_id:
		return
	if su.type == "settler" and game.can_found_city(game.human_id, t) == "":
		game.order_unit(su, t, "found")
		_on_toast("Settler heading out to found a city.", "info")
		return
	game.order_unit(su, t, "auto")
	if su.path.is_empty() and su.tile != t:
		_on_toast("No route there for this unit.", "warn")
	else:
		_on_toast("Order given.", "info")


func _refresh_city_panel() -> void:
	var t: int = main.selected_tile
	var c = game.city_at(t) if t >= 0 else null
	if c == null:
		_city_panel.visible = false
		return
	_clear(_city_box)
	var nat = game.nations[c.nation_id]
	_lbl(_city_box, "%s %s" % ["★" if c.is_original_capital else "", c.cname], COL_ACCENT, 17)
	_lbl(_city_box, nat.display_name, nat.color)
	_lbl(_city_box, "Population %d / %d    Growth %d%%" % [c.pop, game.city_max_pop(c),
		int(clampf(c.growth / (12.0 + 8.0 * c.pop), 0, 1) * 100.0)])
	_lbl(_city_box, "Defense %d    HP %d" % [int(game.city_defense(c)), int(c.hp)])
	if c.nation_id != game.human_id:
		return
	# specialization
	if c.spec != "":
		_lbl(_city_box, "Specialization: %s" % Data.specializations[c.spec].name, COL_ACCENT2)
	if c.pop >= 5:
		_lbl(_city_box, "Specialize:", COL_DIM)
		var row := HBoxContainer.new()
		_city_box.add_child(row)
		var opt := OptionButton.new()
		var ids: Array = []
		for s: Dictionary in Data.spec_list:
			if s.id == c.spec:
				continue
			opt.add_item("%s (%d Inf)" % [s.name, int(s.cost * (2.0 if c.spec != "" else 1.0))])
			ids.append(s.id)
		row.add_child(opt)
		_btn(row, "Set", func() -> void:
			if opt.selected >= 0:
				var err: String = game.set_specialization(game.human_id, c, ids[opt.selected])
				if err != "":
					_on_toast(err, "warn")
				_refresh_city_panel())
	# training
	if not c.training.is_empty():
		var ud: Dictionary = Data.units[c.training.unit]
		_lbl(_city_box, "Training %s — %d ticks left" % [ud.name, int(c.training.ticks)], COL_ACCENT2)
	else:
		_lbl(_city_box, "Train units:", COL_DIM)
		var nat2 = game.nations[game.human_id]
		for u: Dictionary in Data.unit_list:
			if u.tech != null and not nat2.researched.has(u.tech):
				continue
			# hide obsolete units of the same class from ages 2+ back
			if int(u.age) < nat2.age - 1 and u.cls != "civilian":
				continue
			var why: String = game.unit_cost_ok(game.human_id, u.id, c)
			var cost_txt := ""
			for k: String in u.cost:
				if float(u.cost[k]) > 0:
					cost_txt += "%d %s " % [int(u.cost[k]), RES_SHORT.get(k, k)]
			var uid2: String = u.id
			_btn(_city_box, "%s (%s)" % [u.name, cost_txt.strip_edges()],
				func() -> void:
					game.train_unit(game.human_id, c, uid2)
					_refresh_city_panel(),
				why == "",
				"%s\nATK %s  DEF %s  HP %s  MOVE %s%s" % [u.desc, str(u.atk), str(u.def), str(u.hp), str(u.move),
					("\n" + why) if why != "" else ""])


# ================= modal windows =================

func _build_win_layer() -> void:
	_win_layer = ColorRect.new()
	(_win_layer as ColorRect).color = Color(0, 0, 0, 0.45)
	_win_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_layer.visible = false
	_win_layer.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_window())
	add_child(_win_layer)


func _close_window() -> void:
	if _window != null:
		_window.queue_free()
		_window = null
	_win_layer.visible = false


func _new_window(title: String, size: Vector2) -> VBoxContainer:
	_close_window()
	_win_layer.visible = true
	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", _pstyle(COL_ACCENT * 0.6))
	_window.custom_minimum_size = size
	add_child(_window)
	_window.resized.connect(func() -> void:
		if is_instance_valid(_window):
			_window.position = (get_viewport().get_visible_rect().size - _window.size) / 2.0)
	_window.position = (get_viewport().get_visible_rect().size - size) / 2.0
	var v := VBoxContainer.new()
	_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_color_override("font_color", COL_ACCENT)
	tl.add_theme_font_size_override("font_size", 18)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.pressed.connect(_close_window)
	head.add_child(x)
	return v


# ---------- tech tree ----------

func _fx_text(t: Dictionary) -> String:
	var parts: Array = []
	if t.mod != null:
		for k: String in t.mod:
			var v: float = t.mod[k]
			if k in ["vision", "maxPolicies", "tradeCap"]:
				parts.append("+%d %s" % [int(v), k])
			else:
				parts.append("%s%d%% %s" % ["+" if v > 0 else "", int(v * 100), k])
	if t.unlockB != null:
		for b: String in t.unlockB:
			parts.append("Unlocks " + Data.buildings[b].name)
	if t.unlockU != null:
		for u: String in t.unlockU:
			parts.append("Unlocks " + Data.units[u].name)
	if t.flag != null:
		parts.append(", ".join(t.flag))
	return " • ".join(parts)


func _open_tech_window() -> void:
	var size := get_viewport().get_visible_rect().size * 0.92
	var v := _new_window("Technology — %s" % Data.age_by_id[game.nations[game.human_id].age].name, size)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(size.x - 40, size.y - 80)
	v.add_child(sc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	sc.add_child(h)
	var nat = game.nations[game.human_id]
	for age: Dictionary in Data.ages:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(240, 0)
		h.add_child(col)
		var head := Label.new()
		head.text = age.name
		head.add_theme_color_override("font_color", Color(age.color))
		head.add_theme_font_size_override("font_size", 15)
		col.add_child(head)
		for t: Dictionary in Data.tech_list:
			if int(t.age) != int(age.id):
				continue
			var branch: Dictionary = Data.tech_branches[t.branch]
			var b := Button.new()
			b.text = "%s  [%s, %d]" % [t.name, branch.name, int(t.cost)]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = "%s\n%s" % [t.desc, _fx_text(t)]
			var tid: String = t.id
			if nat.researched.has(tid):
				b.modulate = Color(0.55, 0.95, 0.55)
				b.disabled = true
			elif nat.researching == tid:
				b.modulate = Color(0.5, 0.85, 1.0)
			elif game.tech_available(game.human_id, tid):
				b.modulate = Color(1, 1, 1)
			else:
				b.modulate = Color(0.55, 0.55, 0.6)
				var missing: Array = []
				for pre: String in t.pre:
					if not nat.researched.has(pre):
						missing.append(Data.techs[pre].name)
				b.tooltip_text += "\nRequires: " + ", ".join(missing)
			b.pressed.connect(func() -> void:
				if game.tech_available(game.human_id, tid):
					game.set_research(game.human_id, tid)
					_close_window())
			col.add_child(b)


# ---------- policies ----------

func _open_policy_window() -> void:
	var nat = game.nations[game.human_id]
	var v := _new_window("Policies  (%d / %d slots)" % [nat.policies.size(), nat.mod_int("maxPolicies")], Vector2(900, 620))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(860, 540)
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	for p: Dictionary in Data.policy_list:
		var card := Button.new()
		card.custom_minimum_size = Vector2(270, 86)
		card.clip_text = true
		var locked: bool = p.tech != null and not nat.researched.has(p.tech)
		var active: bool = nat.policies.has(p.id)
		var fx := ""
		for k: String in p.mod:
			var val: float = p.mod[k]
			if k in ["tradeCap", "maxPolicies", "vision"]:
				fx += "+%d %s  " % [int(val), k]
			else:
				fx += "%s%d%% %s  " % ["+" if val > 0 else "", int(val * 100), k]
		card.text = "%s [%s]\n%s\nCost %d Inf" % [p.name, p.type, fx.strip_edges(), int(p.cost)]
		card.tooltip_text = p.desc + ("\nRequires " + Data.techs[p.tech].name if locked else "")
		if active:
			card.modulate = Color(0.55, 0.95, 0.55)
		elif locked:
			card.modulate = Color(0.5, 0.5, 0.55)
			card.disabled = true
		var pid: String = p.id
		card.pressed.connect(func() -> void:
			if nat.policies.has(pid):
				game.revoke_policy(game.human_id, pid)
			else:
				var err: String = game.enact_policy(game.human_id, pid)
				if err != "":
					_on_toast(err, "warn")
			_open_policy_window())
		grid.add_child(card)


# ---------- diplomacy ----------

func _open_diplo_window() -> void:
	var v := _new_window("Diplomacy", Vector2(860, 560))
	var me: int = game.human_id
	for n in range(game.nations.size()):
		if n == me:
			continue
		var nat = game.nations[n]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _pstyle())
		v.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var swatch := ColorRect.new()
		swatch.color = nat.color
		swatch.custom_minimum_size = Vector2(22, 22)
		h.add_child(swatch)
		var name_l := Label.new()
		name_l.text = "%s%s" % [nat.display_name, "" if nat.alive else " (eliminated)"]
		name_l.custom_minimum_size = Vector2(150, 0)
		h.add_child(name_l)
		if not nat.alive:
			continue
		var st: String = game.diplo.status(me, n)
		var r: float = game.diplo.rel(me, n)
		var info := Label.new()
		info.text = "%s  •  rel %d  •  %s" % [st.to_upper(), int(r), Data.age_by_id[nat.age].short]
		info.add_theme_color_override("font_color",
			COL_BAD if st == "war" else (COL_GOOD if r > 20 else COL_DIM))
		info.custom_minimum_size = Vector2(220, 0)
		h.add_child(info)
		var nn := n
		if st == "war":
			_btn(h, "Offer Peace", func() -> void: _try_peace(nn))
		else:
			_btn(h, "Declare War", func() -> void:
				game.diplo.declare_war(me, nn)
				_open_diplo_window())
			_btn(h, "Trade Deal", func() -> void: _try_trade(nn), game.diplo.can_trade(me, nn))
			if st == "peace":
				_btn(h, "Non-Aggression", func() -> void: _try_nap(nn))
			if st != "alliance":
				_btn(h, "Alliance", func() -> void: _try_alliance(nn))
	var deals_l := Label.new()
	deals_l.text = "Active trade deals: %d / %d" % [game.diplo.deal_count(me), game.diplo.trade_cap(me)]
	deals_l.add_theme_color_override("font_color", COL_DIM)
	v.add_child(deals_l)


func _try_peace(n: int) -> void:
	var me: int = game.human_id
	var ratio: float = game.nation_power(n) / maxf(1.0, game.nation_power(me))
	if ratio < 0.8 or game.nations[n].war_weariness > 0.4 or game.diplo.rel(me, n) > -20:
		game.diplo.make_peace(me, n)
	else:
		_on_toast("%s refuses — they think they're winning." % game.nations[n].display_name, "warn")
	_open_diplo_window()


func _try_trade(n: int) -> void:
	var me: int = game.human_id
	if game.diplo.rel(me, n) > -10 and game.diplo.can_trade(me, n):
		game.diplo.make_deal(me, n)
	else:
		_on_toast("%s declines the deal." % game.nations[n].display_name, "warn")
	_open_diplo_window()


func _try_nap(n: int) -> void:
	var me: int = game.human_id
	if game.diplo.rel(me, n) > 0:
		game.diplo.sign_nap(me, n)
	else:
		_on_toast("%s doesn't trust you enough." % game.nations[n].display_name, "warn")
	_open_diplo_window()


func _try_alliance(n: int) -> void:
	var me: int = game.human_id
	if game.diplo.rel(me, n) > 55:
		game.diplo.form_alliance(me, n)
	else:
		_on_toast("%s needs closer relations first (55+)." % game.nations[n].display_name, "warn")
	_open_diplo_window()


# ---------- pause menu ----------

func _open_pause_menu() -> void:
	var v := _new_window("AEONS", Vector2(340, 320))
	_btn(v, "Resume", _close_window)
	_btn(v, "Save Game", func() -> void:
		game.save_game()
		_close_window())
	var nat = game.nations[game.human_id]
	if nat.has_flag("scienceVictory"):
		var why: String = game.can_fund_ark(game.human_id)
		_btn(v, "Fund Starlight Ark stage (%d/%d)" % [nat.ark_stages, 5],
			func() -> void:
				game.fund_ark_stage(game.human_id)
				_open_pause_menu(),
			why == "", why)
	_btn(v, "Exit to Main Menu", func() -> void:
		_close_window()
		main.to_menu())
	_btn(v, "Quit Game", func() -> void: get_tree().quit())


# ---------- dialogs (event / perk / victory) ----------

func _dialog_box(title: String, color := COL_ACCENT) -> VBoxContainer:
	if _dialog != null:
		_dialog.queue_free()
	_dialog = PanelContainer.new()
	_dialog.add_theme_stylebox_override("panel", _pstyle(color))
	_dialog.custom_minimum_size = Vector2(480, 0)
	add_child(_dialog)
	# recenter once the container has computed its real height
	_dialog.resized.connect(func() -> void:
		if is_instance_valid(_dialog):
			_dialog.position = (get_viewport().get_visible_rect().size - _dialog.size) / 2.0)
	_dialog.position = (get_viewport().get_visible_rect().size - Vector2(480, 200)) / 2.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_dialog.add_child(v)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_color_override("font_color", color)
	tl.add_theme_font_size_override("font_size", 17)
	v.add_child(tl)
	return v


func _close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


func _on_event_popup(_n: int, ev: Dictionary, has_choice: bool) -> void:
	var v := _dialog_box("%s" % ev.name, COL_GOOD if ev.good else COL_BAD)
	var d := Label.new()
	d.text = ev.desc
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(440, 0)
	v.add_child(d)
	if has_choice:
		for i in range(ev.choice.size()):
			var idx := i
			_btn(v, ev.choice[i].label, func() -> void:
				game.events.apply_choice(game.human_id, idx)
				_close_dialog())
	else:
		_btn(v, "Very well", _close_dialog)


func _on_perk_offer(_n: int) -> void:
	var nat = game.nations[game.human_id]
	var v := _dialog_box("A new age dawns — choose a national perk")
	for pid: String in nat.pending_perks:
		var p: Dictionary = Data.perks[pid]
		var pid2 := pid
		_btn(v, "%s — %s" % [p.name, p.desc], func() -> void:
			game.pick_perk(game.human_id, pid2)
			_close_dialog())


func _on_victory(n: int, vid: String) -> void:
	var vdef: Dictionary = Data.victories[vid]
	var win: bool = n == game.human_id
	var v := _dialog_box("%s — %s!" % [game.nations[n].display_name, vdef.name],
		COL_GOOD if win else COL_BAD)
	var d := Label.new()
	d.text = ("Victory! " if win else "Defeat. ") + vdef.desc
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(440, 0)
	v.add_child(d)
	_btn(v, "Continue watching", func() -> void:
		game.over = false
		_close_dialog())
	_btn(v, "Main Menu", func() -> void:
		_close_dialog()
		main.to_menu())


# ---------- input shortcuts ----------

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_set_speed(0.0 if game.speed > 0.0 else 1.0)
			KEY_ESCAPE:
				if _window != null:
					_close_window()
				else:
					selected_unit_id = -1
					main.selected_tile = -1
					main.globe.set_selection(-1)
					on_select_tile(-1)
			KEY_F5:
				game.save_game()
			KEY_T:
				_open_tech_window()
