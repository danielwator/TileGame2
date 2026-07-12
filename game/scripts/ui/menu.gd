# ============================================================
#  AEONS — main menu / new game screen
# ============================================================
extends CanvasLayer

var main

var _seed_edit: LineEdit
var _size_opt: OptionButton
var _players_spin: SpinBox
var _ocean_slider: HSlider
var _ocean_label: Label
var _climate_opt: OptionButton
var _diff_opt: OptionButton
var _detail_opt: OptionButton
var _start_btn: Button

const SEED_WORDS := ["AZURE", "TERRA", "ORION", "DELTA", "EMBER", "FROST", "GALE", "IONIA",
	"KRONO", "LUMEN", "MIRA", "NOVA", "ONYX", "PYRRH", "QUARTZ", "RIFT", "SOLIS", "TITAN", "UMBRA", "VELA"]


func setup(m) -> void:
	main = m
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.038)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.055, 0.075, 0.115, 0.97)
	st.border_color = Color(0.24, 0.3, 0.42)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	# center manually once the viewport is known
	panel.position = (get_viewport().get_visible_rect().size - Vector2(520, 560)) / 2.0

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := Label.new()
	title.text = "A E O N S"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.91, 0.76, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var tag := Label.new()
	tag.text = "one planet  •  eight ages  •  every age a war for tomorrow"
	tag.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	v.add_child(HSeparator.new())

	# seed
	var row := _field(v, "World Seed")
	_seed_edit = LineEdit.new()
	_seed_edit.text = _random_seed()
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seed_edit)
	var rnd := Button.new()
	rnd.text = "Random"
	rnd.pressed.connect(func() -> void: _seed_edit.text = _random_seed())
	row.add_child(rnd)

	# size
	var row2 := _field(v, "World Size")
	_size_opt = OptionButton.new()
	_size_opt.add_item("Small — 2,562 tiles")
	_size_opt.add_item("Standard — 4,002 tiles")
	_size_opt.add_item("Large — 5,762 tiles")
	_size_opt.selected = 1
	_size_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_size_opt)

	# players
	var row3 := _field(v, "Nations")
	_players_spin = SpinBox.new()
	_players_spin.min_value = 3
	_players_spin.max_value = 8
	_players_spin.value = 5
	row3.add_child(_players_spin)
	var hint := Label.new()
	hint.text = "(you + AI opponents)"
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	row3.add_child(hint)

	# ocean
	var row4 := _field(v, "Ocean Coverage")
	_ocean_slider = HSlider.new()
	_ocean_slider.min_value = 0.5
	_ocean_slider.max_value = 0.75
	_ocean_slider.step = 0.01
	_ocean_slider.value = 0.62
	_ocean_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ocean_slider.custom_minimum_size = Vector2(200, 0)
	row4.add_child(_ocean_slider)
	_ocean_label = Label.new()
	_ocean_label.text = "62%"
	row4.add_child(_ocean_label)
	_ocean_slider.value_changed.connect(func(val: float) -> void:
		_ocean_label.text = "%d%%" % int(val * 100))

	# terrain detail
	var rowD := _field(v, "Terrain Detail")
	_detail_opt = OptionButton.new()
	_detail_opt.add_item("Standard — 6× tile resolution")
	_detail_opt.add_item("High — 9× tile resolution")
	_detail_opt.add_item("Ultra — 12× tile resolution")
	_detail_opt.add_item("Extreme — 15× tile resolution")
	_detail_opt.selected = 2
	_detail_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rowD.add_child(_detail_opt)

	# climate
	var row5 := _field(v, "Climate")
	_climate_opt = OptionButton.new()
	_climate_opt.add_item("Ice Age")
	_climate_opt.add_item("Temperate")
	_climate_opt.add_item("Hothouse")
	_climate_opt.selected = 1
	_climate_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row5.add_child(_climate_opt)

	# difficulty
	var row6 := _field(v, "Difficulty")
	_diff_opt = OptionButton.new()
	_diff_opt.add_item("Settler (easy)")
	_diff_opt.add_item("Monarch (normal)")
	_diff_opt.add_item("Immortal (hard)")
	_diff_opt.selected = 1
	_diff_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row6.add_child(_diff_opt)

	v.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	v.add_child(actions)

	if FileAccess.file_exists("user://save.json"):
		var cont := Button.new()
		cont.text = "  Continue  "
		cont.pressed.connect(func() -> void: main.continue_game())
		actions.add_child(cont)

	_start_btn = Button.new()
	_start_btn.text = "  Begin History  "
	_start_btn.add_theme_font_size_override("font_size", 17)
	_start_btn.pressed.connect(_on_start)
	actions.add_child(_start_btn)

	var note := Label.new()
	note.text = "Drag to rotate  •  wheel to zoom  •  left-click select  •  right-click order\nGame reference: reference.html in the project folder"
	note.add_theme_color_override("font_color", Color(0.45, 0.5, 0.58))
	note.add_theme_font_size_override("font_size", 12)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


func _field(parent: Container, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(130, 0)
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.83))
	row.add_child(l)
	return row


func _random_seed() -> String:
	return SEED_WORDS[randi() % SEED_WORDS.size()] + "-" + str(randi_range(1000, 9999))


func _on_start() -> void:
	var params := {
		"seed": _seed_edit.text if _seed_edit.text != "" else _random_seed(),
		"tile_freq": [16, 20, 24][_size_opt.selected],
		"detail": [6, 9, 12, 15][_detail_opt.selected],
		"players": int(_players_spin.value),
		"ocean_fraction": _ocean_slider.value,
		"temperature": [-0.12, 0.0, 0.12][_climate_opt.selected],
		"difficulty": ["easy", "normal", "hard"][_diff_opt.selected],
	}
	# show generation feedback before the (seconds-long) synchronous build
	_start_btn.text = "  Forging the world…  "
	_start_btn.disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	main.start_game(params)
