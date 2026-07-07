# ============================================================
#  AEONS — application root
#  Wires world generation, globe rendering, camera, game state
#  and UI together. Debug helpers (env vars):
#   AEONS_SEED=<seed>  quick-start, skipping the menu
#   AEONS_SNAP=<path>  save a screenshot after startup
#   AEONS_SIM=<n>      run n ticks immediately (testing)
#   AEONS_QUIT=1       quit after snap/sim
# ============================================================
extends Node3D

var world: Dictionary
var globe: GlobeMesh
var orbit: OrbitCamera
var game: GameState = null
var hud = null
var menu = null
var markers: Markers = null

var hover_tile := -1
var selected_tile := -1
var _hover_accum := 0.0


func _ready() -> void:
	_setup_environment()
	var quick_seed := OS.get_environment("AEONS_SEED")
	if OS.get_environment("AEONS_TEST") == "1":
		_run_selftest()
		return
	if quick_seed != "":
		start_game({"seed": quick_seed})
		_maybe_sim()
		# debug: open a UI window before the screenshot (AEONS_UI=tech|diplo|policy)
		match OS.get_environment("AEONS_UI"):
			"tech": hud._open_tech_window()
			"diplo": hud._open_diplo_window()
			"policy": hud._open_policy_window()
	else:
		show_menu()
	_maybe_snap()


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.9
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.016, 0.022, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.85
	we.environment = env
	add_child(we)


func show_menu() -> void:
	_teardown()
	var menu_script = load("res://scripts/ui/menu.gd")
	menu = menu_script.new()
	add_child(menu)
	menu.setup(self)


func _teardown() -> void:
	for m in [globe, hud, markers, menu]:
		if m != null:
			m.queue_free()
	globe = null
	hud = null
	markers = null
	menu = null
	game = null
	selected_tile = -1
	hover_tile = -1


func start_game(params: Dictionary) -> void:
	_teardown()
	world = WorldGen.generate(params)
	globe = GlobeMesh.new()
	add_child(globe)
	globe.build(world)
	_ensure_camera()

	game = GameState.new(world, params)
	game.setup()
	_after_game_created()


func continue_game() -> void:
	_teardown()
	var g = GameState.load_game()
	if g == null:
		show_menu()
		return
	game = g
	world = game.world
	globe = GlobeMesh.new()
	add_child(globe)
	globe.build(world)
	_ensure_camera()
	_after_game_created()


func _after_game_created() -> void:
	var cap: int = game.nations[game.human_id].capital_tile
	if cap >= 0:
		orbit.focus_on(world.tiles.centers[cap])
	var hud_script = load("res://scripts/ui/hud.gd")
	hud = hud_script.new()
	add_child(hud)
	hud.setup(self)
	markers = Markers.new()
	add_child(markers)
	markers.setup(self)
	refresh_map()


func to_menu() -> void:
	show_menu()


func _ensure_camera() -> void:
	if orbit == null:
		orbit = OrbitCamera.new()
		add_child(orbit)
		orbit.tile_clicked.connect(_on_tile_clicked)
		orbit.cam.current = true


func refresh_map() -> void:
	if game == null or globe == null:
		return
	globe.set_overlay_colors(func(ti: int) -> Color: return game.overlay_color(ti))
	globe.set_borders(
		func(ti: int) -> int: return game.owner[ti],
		func(n: int) -> Color: return game.nations[n].color,
		func(ti: int) -> bool: return game.fog_state(game.human_id, ti) > 0)


func _process(delta: float) -> void:
	if orbit != null:
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun != null:
			sun.position = orbit.cam.position * 1.2
			sun.look_at(Vector3.ZERO, Vector3.UP)
	if game != null:
		game.update(delta)
		if game.map_dirty:
			game.map_dirty = false
			refresh_map()
		if hud != null:
			hud.tick_update(delta)
	# hover picking, throttled
	_hover_accum += delta
	if _hover_accum > 0.05 and globe != null and orbit != null and game != null:
		_hover_accum = 0.0
		var mp := get_viewport().get_mouse_position()
		var t := globe.tile_from_ray(orbit.ray_origin(mp), orbit.ray_dir(mp))
		if t >= 0 and game.fog_state(game.human_id, t) == 0:
			t = -1
		if t != hover_tile:
			hover_tile = t
			globe.set_hover(t)
			if hud != null:
				hud.on_hover_tile(t)


func _on_tile_clicked(screen_pos: Vector2, button: int) -> void:
	if globe == null or game == null:
		return
	var t := globe.tile_from_ray(orbit.ray_origin(screen_pos), orbit.ray_dir(screen_pos))
	if t >= 0 and game.fog_state(game.human_id, t) == 0:
		t = -1
	if button == MOUSE_BUTTON_LEFT:
		selected_tile = t
		globe.set_selection(t)
		if hud != null:
			hud.on_select_tile(t)
	elif button == MOUSE_BUTTON_RIGHT and hud != null:
		hud.on_right_click_tile(t)


# ---------------- debug: batch simulation ----------------

func _maybe_sim() -> void:
	var sim := OS.get_environment("AEONS_SIM")
	if sim == "" or game == null:
		return
	var ticks := int(sim)
	var t0 := Time.get_ticks_msec()
	for i in range(ticks):
		game._do_tick()
	print("SIM: %d ticks in %d ms, year %.0f" % [ticks, Time.get_ticks_msec() - t0, game.year])
	for nat in game.nations:
		var owned := 0
		for t in range(world.NT):
			if game.owner[t] == nat.id:
				owned += 1
		print("SIM %s alive=%s age=%d cities=%d tiles=%d pop=%d units=%d techs=%d gold=%d food=%d mat=%d inf=%d score=%d" % [
			nat.display_name, nat.alive, nat.age, game.cities_of(nat.id).size(), owned,
			game.cities_of(nat.id).reduce(func(acc, c): return acc + c.pop, 0),
			game.units.filter(func(u): return u.nation_id == nat.id).size(),
			nat.researched.size(), nat.res.gold, nat.res.food, nat.res.materials,
			nat.res.influence, game.score(nat.id)])
	print("SIM events/deals: deals=%d wars=%s" % [game.diplo.deals.size(), _war_pairs()])
	if OS.get_environment("AEONS_REVEAL") == "1":
		game.fog.reveal_all(game.human_id)
		refresh_map()
	var disc := 0
	var vis := 0
	for i in range(world.NT):
		if game.fog.discovered[game.human_id][i] == 1:
			disc += 1
		if game.fog.visible[game.human_id][i] == 1:
			vis += 1
	print("SIM fog human: discovered=%d visible=%d of %d" % [disc, vis, world.NT])
	if OS.get_environment("AEONS_QUIT") == "1" and OS.get_environment("AEONS_SNAP") == "":
		get_tree().quit()


func _war_pairs() -> String:
	var out := ""
	for a in range(game.nations.size()):
		for b in range(a + 1, game.nations.size()):
			if game.diplo.status(a, b) == "war":
				out += "%d-%d " % [a, b]
	return out


# ---------------- integration self-test ----------------
# Exercises the same functions the UI buttons call, asserting results.

var _test_pass := 0
var _test_fail := 0

func _check(label: String, cond: bool) -> void:
	if cond:
		_test_pass += 1
		print("  PASS  " + label)
	else:
		_test_fail += 1
		print("  FAIL  " + label)


func _run_selftest() -> void:
	print("=== AEONS self-test ===")
	start_game({"seed": "TESTBED", "players": 4, "tile_freq": 16, "detail": 6})
	var g := game
	var hu: int = g.human_id
	var nat = g.nations[hu]

	# --- research (branch-starter has no prereqs) ---
	g.set_research(hu, "hunting")
	_check("research selectable", nat.researching == "hunting")
	# grant a starter tech set so build/train/policy paths can be exercised
	for tid in ["hunting", "agriculture", "warbands", "tribalCouncil", "masonry", "bronzeWorking"]:
		nat.researched[tid] = true
	nat.mods_dirty = true

	# --- settler founds a city ---
	var settler = null
	for u in g.units:
		if u.nation_id == hu and u.type == "settler":
			settler = u
	_check("human starts with a settler", settler != null)
	var cities_before: int = g.cities_of(hu).size()
	# walk settler a few tiles away and found
	var site := -1
	var d := SphereGrid.bfs_distances(g.world.tiles, [nat.capital_tile], 6)
	for i in range(g.world.NT):
		if d[i] >= 4 and d[i] <= 6 and g.can_found_city(hu, i) == "":
			site = i
			break
	if site >= 0 and settler != null:
		settler.tile = site
		g.found_city(hu, site)
		settler.hp = -1
		g.cull_dead_units()
	_check("settler founded a second city", g.cities_of(hu).size() == cities_before + 1)

	# --- claim a tile ---
	nat.res.influence = 500.0
	var claim_target := -1
	for i in range(g.world.NT):
		if g.can_claim(hu, i) == "":
			claim_target = i
			break
	var inf_before: float = nat.res.influence
	var claimed: bool = claim_target >= 0 and g.claim_tile(hu, claim_target)
	_check("tile claimed with influence", claimed and g.owner[claim_target] == hu and nat.res.influence < inf_before)

	# --- build a farm on a valid tile ---
	nat.res.materials = 500.0
	var farm_tile := -1
	for i in range(g.world.NT):
		if g.owner[i] == hu and g.buildings[i] == null and g.can_build(hu, i, "farm") == "":
			farm_tile = i
			break
	var built: bool = farm_tile >= 0 and g.start_building(hu, farm_tile, "farm")
	_check("farm construction started", built)
	# run ticks until it finishes
	for t in range(20):
		g._do_tick()
	_check("farm finished building", farm_tile >= 0 and g.buildings[farm_tile] != null and g.buildings[farm_tile].done)

	# --- train a warrior ---
	var cap_city = g.city_at(g.nations[hu].capital_tile)
	nat.res.materials = 500.0
	var trained: bool = cap_city != null and g.train_unit(hu, cap_city, "warrior")
	_check("warrior training queued", trained)
	for t in range(12):
		g._do_tick()
	var warrior_count := 0
	for u in g.units:
		if u.nation_id == hu and u.type == "warrior":
			warrior_count += 1
	_check("warrior appeared", warrior_count >= 1)

	# --- economy produced yields ---
	_check("food stockpile positive", nat.res.food > 0.0)
	_check("nation still alive", nat.alive)

	# --- combat: pit two units against each other ---
	var atk = g.spawn_unit(hu, "swordsman", cap_city.tile)
	var enemy_tile := -1
	var tiles: Dictionary = g.world.tiles
	for e in range(tiles.nbr_off[cap_city.tile], tiles.nbr_off[cap_city.tile + 1]):
		if g.can_enter(hu, "swordsman", tiles.nbr[e]):
			enemy_tile = tiles.nbr[e]
			break
	var def = g.spawn_unit(1, "warrior", enemy_tile) if enemy_tile >= 0 else null
	if def != null:
		g.diplo.declare_war(hu, 1)
		atk.order = {"kind": "attack", "target": enemy_tile}
		var hp0: float = def.hp
		for t in range(6):
			g._combat_tick()
		_check("combat damages the defender", def.hp < hp0)

	# --- fog: human doesn't see the whole map ---
	var vis := 0
	for i in range(g.world.NT):
		if g.fog.visible[hu][i] == 1:
			vis += 1
	_check("fog hides most of the map", vis < g.world.NT / 2)

	# --- diplomacy trade deal ---
	g.diplo.make_peace(hu, 1)
	g.diplo.relations[hu][2] = 60.0
	g.diplo.relations[2][hu] = 60.0
	var deals0: int = g.diplo.deal_count(hu)
	g.diplo.make_deal(hu, 2)
	_check("trade deal created", g.diplo.deal_count(hu) == deals0 + 1)

	# --- policy enactment ---
	nat.researched["tribalCouncil"] = true
	nat.mods_dirty = true
	nat.res.influence = 200.0
	var perr: String = g.enact_policy(hu, "agrarianFocus")
	_check("policy enacted", perr == "" and nat.policies.has("agrarianFocus"))

	# --- save / load round trip ---
	g.save_game()
	var loaded = GameState.load_game()
	_check("save/load restores nation count", loaded != null and loaded.nations.size() == g.nations.size())
	_check("save/load restores cities", loaded != null and loaded.cities.size() == g.cities.size())
	_check("save/load restores research", loaded != null and loaded.nations[hu].researching == g.nations[hu].researching)

	# --- long-run stability: 400 ticks, no crash ---
	var ok := true
	for t in range(400):
		g._do_tick()
	_check("400-tick long run completed", ok)
	var any_age2 := false
	for n2 in g.nations:
		if n2.age >= 2:
			any_age2 = true
	_check("some nation advanced past Ancient age", any_age2)

	print("=== self-test: %d passed, %d failed ===" % [_test_pass, _test_fail])
	get_tree().quit(_test_fail)


# ---------------- debug screenshot ----------------

func _maybe_snap() -> void:
	var path := OS.get_environment("AEONS_SNAP")
	if path == "":
		return
	_snap_after_frames(path, 30)


func _snap_after_frames(path: String, frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SNAPPED " + path)
	if OS.get_environment("AEONS_QUIT") == "1":
		get_tree().quit()
