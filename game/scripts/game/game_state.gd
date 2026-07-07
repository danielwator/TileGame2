# ============================================================
#  AEONS — game state & simulation core
#
#  Tick-based real-time simulation (1 tick ≈ 1.2 s at speed 1).
#  Owns nations, cities, buildings, units, resources, research,
#  influence borders, combat, events, diplomacy, fog and victory.
# ============================================================
class_name GameState
extends RefCounted

signal toast(msg: String, kind: String)
signal event_popup(nation_id: int, ev: Dictionary, has_choice: bool)
signal perk_offer(nation_id: int)
signal victory(nation_id: int, victory_id: String)

const TICK_SECONDS := 1.2
const WORK_RADIUS := 3
const CITY_MIN_DIST := 4
const CAPITAL_WEIGHT := 0.6
const CLAIM_BASE := 8.0
const BORDER_UPKEEP_BASE := 0.02
const GROWTH_BASE := 12.0
const GROWTH_PER_POP := 8.0
const ARK_STAGES_NEEDED := 5
const ARK_STAGE_COST := {"science": 2000.0, "materials": 1500.0, "circuits": 50.0}

const NATION_DEFS := [
	{"name": "Valdoria", "color": Color("#e74c3c")},
	{"name": "Kaethari", "color": Color("#3f8ef0")},
	{"name": "Meridia", "color": Color("#f1c40f")},
	{"name": "Ostrogar", "color": Color("#9b59b6")},
	{"name": "Zephyria", "color": Color("#e67e22")},
	{"name": "Thalassa", "color": Color("#17c3b2")},
	{"name": "Kharesh", "color": Color("#e84393")},
	{"name": "Vindhal", "color": Color("#8d99ae")},
]
const CITY_NAMES := [
	"Arden", "Bastia", "Corvale", "Deral", "Elowen", "Ferrun", "Galway", "Hestia",
	"Iskar", "Jorvik", "Kalder", "Lumen", "Morvane", "Nyssa", "Ostia", "Perth",
	"Quesse", "Ravel", "Solane", "Torvin", "Umbra", "Veles", "Wyndam", "Ythris", "Zarek",
]

# ---------------- inner classes ----------------

class Nation:
	var id: int
	var display_name: String
	var color: Color
	var is_human := false
	var alive := true
	var capital_tile := -1
	var res := {"food": 60.0, "materials": 80.0, "gold": 50.0, "influence": 20.0, "coal": 0.0, "oil": 0.0, "circuits": 0.0}
	var researched := {}          # tech id -> true
	var researching := ""
	var research_progress := 0.0
	var age := 1
	var perks: Array = []
	var pending_perks: Array = [] # offered perk ids awaiting a pick
	var policies: Array = []
	var temp_mods: Array = []     # {mod: Dictionary, until: tick}
	var war_weariness := 0.0
	var ark_stages := 0
	var bonus_mult := 1.0         # AI difficulty handicap
	var city_dist: PackedInt32Array   # effective distance-to-own-city map
	var mods_dirty := true
	var _mods_cache := {}
	# AI personality
	var ai_aggression := 0.5
	var ai_expansion := 0.5

	func _flags() -> Dictionary:
		var f := {}
		for tid: String in researched:
			var t: Dictionary = Data.techs[tid]
			if t.flag != null:
				for fl: String in t.flag:
					f[fl] = true
		return f

	func has_flag(fl: String) -> bool:
		if mods_dirty:
			_rebuild_mods()
		return _mods_cache.get("__flags", {}).has(fl)

	func _rebuild_mods() -> void:
		var m := {}
		var add_mod := func(mod: Dictionary) -> void:
			for k: String in mod:
				m[k] = m.get(k, 0.0) + mod[k]
		for tid: String in researched:
			var t: Dictionary = Data.techs[tid]
			if t.mod != null:
				add_mod.call(t.mod)
		for pid: String in policies:
			add_mod.call(Data.policies[pid].mod)
		for pid: String in perks:
			add_mod.call(Data.perks[pid].mod)
		for tm: Dictionary in temp_mods:
			add_mod.call(tm.mod)
		m["__flags"] = _flags()
		_mods_cache = m
		mods_dirty = false

	## additive modifier sum for a key ("food", "b:farm", "claimCost"...)
	func modv(key: String) -> float:
		if mods_dirty:
			_rebuild_mods()
		var v = _mods_cache.get(key, 0.0)
		return float(v) if not (v is Dictionary) else 0.0

	func mod_int(key: String) -> int:
		return int(modv(key))


class City:
	var id: int
	var tile: int
	var nation_id: int
	var cname: String
	var pop := 1
	var growth := 0.0
	var spec := ""            # specialization id
	var hp := 100.0
	var training := {}        # {unit: id, ticks: n}
	var is_original_capital := false

	func spec_mod(key: String) -> float:
		if spec == "":
			return 0.0
		return float(Data.specializations[spec].mod.get(key, 0.0))


class Army:
	var id: int
	var type: String
	var nation_id: int        # -2 = barbarians
	var tile: int
	var hp: float
	var max_hp: float
	var exp := 1.0
	var path: Array = []
	var move_progress := 0.0
	var order := {}           # {kind: "move"/"attack"/"found", target: tile}
	var fought_this_tick := false


# ---------------- state ----------------

var world: Dictionary
var params: Dictionary
var rng: RandomNumberGenerator

var nations: Array = []
var human_id := 0
var owner: PackedInt32Array
var tile_city: PackedInt32Array     # tile -> city id (-1)
var buildings: Array = []           # per tile: null | {id, city, progress, time, done}
var deposit: Array = []             # per tile deposit id or ""
var cities: Array = []
var units: Array = []
var world_capitals: Array = []      # starting capital tiles (domination victory)

var diplo: Diplomacy
var fog: FogOfWar
var events: EventSystem
var ai

var tick_count := 0
var speed := 1.0                    # 0 = paused
var _accum := 0.0
var year := -4000.0
var map_dirty := true
var over := false
var winner := -1
var victory_id := ""
var pending_choice := {}

var _next_id := 1
var _avg_edge := 0.0


func _init(w: Dictionary, p: Dictionary) -> void:
	world = w
	params = p
	rng = RandomNumberGenerator.new()
	rng.seed = hash(String(p.get("seed", "AEONS")) + "|game")


func setup() -> void:
	var nt: int = world.NT
	owner = PackedInt32Array(); owner.resize(nt); owner.fill(-1)
	tile_city = PackedInt32Array(); tile_city.resize(nt); tile_city.fill(-1)
	buildings.resize(nt)
	deposit = world.t_deposit.duplicate()

	var n_players: int = int(params.get("players", 5))
	human_id = 0
	var spawns := WorldGen.pick_spawns(world, n_players)
	var difficulty: String = params.get("difficulty", "normal")
	for i in range(n_players):
		var nat := Nation.new()
		nat.id = i
		nat.display_name = NATION_DEFS[i % NATION_DEFS.size()].name
		nat.color = NATION_DEFS[i % NATION_DEFS.size()].color
		nat.is_human = i == human_id
		if not nat.is_human:
			nat.bonus_mult = {"easy": 0.8, "normal": 1.0, "hard": 1.25}[difficulty]
			nat.ai_aggression = rng.randf_range(0.25, 0.85)
			nat.ai_expansion = rng.randf_range(0.4, 0.95)
		nations.append(nat)

	diplo = Diplomacy.new(self)
	fog = FogOfWar.new(self)
	events = EventSystem.new(self)
	var ai_script = load("res://scripts/game/ai.gd")
	ai = ai_script.new(self) if ai_script != null else null

	# found capitals + starting units
	for i in range(n_players):
		if i < spawns.size():
			var c = found_city(i, spawns[i], true)
			c.is_original_capital = true
			world_capitals.append(spawns[i])
			spawn_unit(i, "warrior", spawns[i])
			spawn_unit(i, "scout", spawns[i])
			spawn_unit(i, "settler", spawns[i])

	fog.recompute()
	map_dirty = true


# ---------------- helpers ----------------

func nid() -> int:
	_next_id += 1
	return _next_id


func fog_state(nation_id: int, tile: int) -> int:
	return fog.state(nation_id, tile)


func notify(n: int, msg: String, kind: String = "info") -> void:
	if n == human_id:
		toast.emit(msg, kind)


func notify_all(msg: String, kind: String = "info") -> void:
	toast.emit(msg, kind)


func emit_event_popup(n: int, ev: Dictionary, has_choice: bool) -> void:
	event_popup.emit(n, ev, has_choice)


func cities_of(n: int) -> Array:
	var out: Array = []
	for c in cities:
		if c.nation_id == n:
			out.append(c)
	return out


func random_city_of(n: int):
	var cs := cities_of(n)
	return cs[rng.randi_range(0, cs.size() - 1)] if not cs.is_empty() else null


func city_at(tile: int):
	var cid := tile_city[tile]
	if cid >= 0 and cid < cities.size():
		var c = cities[cid]
		if c.tile == tile:
			return c
	return null


func city_max_pop(c) -> int:
	var cap := 5
	for t in range(world.NT):
		var b = buildings[t]
		if b != null and b.done and b.city == c.id:
			cap += int(Data.buildings[b.id].housing)
	return cap


func city_defense(c) -> float:
	var d := 10.0
	for t in range(world.NT):
		var b = buildings[t]
		if b != null and b.done and b.city == c.id:
			d += float(Data.buildings[b.id].defense)
	return d * (1.0 + c.spec_mod("cityDefense") + nations[c.nation_id].modv("def"))


func units_on(tile: int) -> Array:
	var out: Array = []
	for u in units:
		if u.tile == tile:
			out.append(u)
	return out


func nation_power(n: int) -> float:
	var p := 0.0
	for u in units:
		if u.nation_id == n:
			var d: Dictionary = Data.units[u.type]
			p += (float(d.atk) + float(d.def)) * (u.hp / u.max_hp)
	return p


func tech_available(n: int, tid: String) -> bool:
	var nat = nations[n]
	if nat.researched.has(tid):
		return false
	var t: Dictionary = Data.techs[tid]
	for pre: String in t.pre:
		if not nat.researched.has(pre):
			return false
	return true


func available_techs(n: int) -> Array:
	var out: Array = []
	for t: Dictionary in Data.tech_list:
		if tech_available(n, t.id):
			out.append(t.id)
	return out


func deposit_visible(n: int, tile: int) -> bool:
	var dep: String = deposit[tile]
	if dep == "":
		return false
	var rt = Data.deposits[dep].revealTech
	return rt == null or nations[n].researched.has(rt)


func nation_has_deposit(n: int, dep_id: String) -> bool:
	for i in range(world.NT):
		if owner[i] == n and deposit[i] == dep_id:
			return true
	return false


# ---------------- overlay coloring (human view) ----------------

func overlay_color(ti: int) -> Color:
	var st := fog_state(human_id, ti)
	if st == 0:
		return Color(0.013, 0.02, 0.038, 1.0)
	if st == 1:
		var c := Color(0.01, 0.015, 0.03, 0.55)
		var o := owner[ti]
		if o >= 0:
			var oc: Color = nations[o].color
			c = c.lerp(Color(oc.r, oc.g, oc.b, 0.6), 0.25)
		return c
	var o2 := owner[ti]
	if o2 >= 0:
		var c2: Color = nations[o2].color
		var a := 0.30 if city_at(ti) != null else 0.15
		return Color(c2.r, c2.g, c2.b, a)
	return Color(0, 0, 0, 0)


# ---------------- city founding / borders ----------------

func can_found_city(n: int, tile: int) -> String:
	if world.t_land[tile] == 0:
		return "Cities need dry land."
	var b: Dictionary = Data.biomes[world.t_biome[tile]]
	if not b.allowsCity:
		return "Cannot settle on %s." % b.name
	if owner[tile] >= 0 and owner[tile] != n:
		return "This land belongs to another nation."
	var near := SphereGrid.bfs_distances(world.tiles, [tile], CITY_MIN_DIST - 1)
	for c in cities:
		if near[c.tile] >= 0:
			return "Too close to %s." % c.cname
	return ""


func found_city(n: int, tile: int, free := false):
	var c := City.new()
	c.id = cities.size()
	c.tile = tile
	c.nation_id = n
	c.cname = CITY_NAMES[(cities.size() * 7 + n * 3) % CITY_NAMES.size()]
	if not cities_of(n).is_empty():
		c.cname += " %s" % ["II", "III", "IV", "V", "VI", "VII"][mini(cities_of(n).size() - 1, 5)]
	cities.append(c)
	if nations[n].capital_tile == -1:
		nations[n].capital_tile = tile
	owner[tile] = n
	tile_city[tile] = c.id
	buildings[tile] = {"id": "cityCenter", "city": c.id, "progress": 0, "time": 0, "done": true}
	var tiles: Dictionary = world.tiles
	for e in range(tiles.nbr_off[tile], tiles.nbr_off[tile + 1]):
		var nb: int = tiles.nbr[e]
		if owner[nb] == -1:
			owner[nb] = n
			tile_city[nb] = c.id
	_recompute_city_dist(n)
	map_dirty = true
	notify(n, "Founded %s!" % c.cname, "good")
	return c


func _recompute_city_dist(n: int) -> void:
	var city_tiles: Array = []
	for c in cities:
		if c.nation_id == n:
			city_tiles.append(c.tile)
	if city_tiles.is_empty():
		nations[n].city_dist = PackedInt32Array()
		return
	var d_all := SphereGrid.bfs_distances(world.tiles, city_tiles)
	var cap: int = nations[n].capital_tile
	var d_cap := SphereGrid.bfs_distances(world.tiles, [cap]) if cap >= 0 else d_all
	var eff := PackedInt32Array()
	eff.resize(world.NT)
	for i in range(world.NT):
		var a: int = d_all[i] if d_all[i] >= 0 else 999
		var b: int = int(ceil(d_cap[i] * CAPITAL_WEIGHT)) if d_cap[i] >= 0 else 999
		eff[i] = mini(a, b)
	nations[n].city_dist = eff


func effective_dist(n: int, tile: int) -> int:
	var cd: PackedInt32Array = nations[n].city_dist
	if cd.is_empty():
		return 999
	return maxi(1, cd[tile])


func claim_cost(n: int, tile: int) -> float:
	var b: Dictionary = Data.biomes[world.t_biome[tile]]
	var d := effective_dist(n, tile)
	return CLAIM_BASE * float(b.infMul) * (1.0 + 0.35 * (d - 1)) * maxf(0.2, 1.0 + nations[n].modv("claimCost"))


func can_claim(n: int, tile: int) -> String:
	if owner[tile] != -1:
		return "Already claimed."
	var b: Dictionary = Data.biomes[world.t_biome[tile]]
	if b.water:
		var bid: String = world.t_biome[tile]
		if bid == "deepOcean" and nations[n].age < 6:
			return "Deep ocean cannot be claimed before the Modern era."
		if (bid == "ocean" or bid == "deepOcean") and not nations[n].has_flag("oceanTravel"):
			return "Requires ocean travel."
	if world.t_biome[tile] == "iceCap" and not nations[n].has_flag("iceTravel"):
		return "The ice is impassable."
	var tiles: Dictionary = world.tiles
	var adjacent := false
	for e in range(tiles.nbr_off[tile], tiles.nbr_off[tile + 1]):
		if owner[tiles.nbr[e]] == n:
			adjacent = true
			break
	if not adjacent:
		return "Must border your territory."
	if effective_dist(n, tile) > 8:
		return "Too far from your cities."
	return ""


func claim_tile(n: int, tile: int) -> bool:
	if can_claim(n, tile) != "":
		return false
	var cost := claim_cost(n, tile)
	var nat = nations[n]
	if nat.res.influence < cost:
		notify(n, "Not enough Influence (%d needed)." % int(cost), "warn")
		return false
	nat.res.influence -= cost
	owner[tile] = n
	# assign to nearest own city
	var best := -1
	var best_d := 9999
	for c in cities:
		if c.nation_id != n:
			continue
		var dd := SphereGrid.bfs_distances(world.tiles, [c.tile], WORK_RADIUS)
		if dd[tile] >= 0 and dd[tile] < best_d:
			best_d = dd[tile]
			best = c.id
	tile_city[tile] = best
	map_dirty = true
	return true


func border_upkeep(n: int) -> float:
	var total := 0.0
	for i in range(world.NT):
		if owner[i] != n or city_at(i) != null:
			continue
		var d := effective_dist(n, i)
		total += BORDER_UPKEEP_BASE * (1.0 + 0.3 * (d - 1))
	return total * maxf(0.2, 1.0 + nations[n].modv("borderUpkeep"))


func _decay_border(n: int) -> void:
	# influence bankruptcy: the farthest tile reverts to neutral
	var worst := -1
	var worst_d := -1
	for i in range(world.NT):
		if owner[i] != n or city_at(i) != null:
			continue
		var d := effective_dist(n, i)
		if d > worst_d:
			worst_d = d
			worst = i
	if worst >= 0:
		owner[worst] = -1
		if buildings[worst] != null:
			buildings[worst] = null
		tile_city[worst] = -1
		map_dirty = true
		notify(n, "Border tile lost — influence upkeep unpaid!", "warn")


# ---------------- buildings ----------------

func can_build(n: int, tile: int, bid: String) -> String:
	var bdef: Dictionary = Data.buildings[bid]
	if owner[tile] != n:
		return "Not your territory."
	if buildings[tile] != null:
		return "Tile already developed."
	if tile_city[tile] == -1:
		return "Too far from a city."
	var nat = nations[n]
	if bdef.tech != null and not nat.researched.has(bdef.tech):
		return "Requires %s." % Data.techs[bdef.tech].name
	# biome placement
	var bio: String = world.t_biome[tile]
	var place: Dictionary = bdef.place
	var on = place.get("on")
	var allowed := false
	if on is String and on == "land":
		allowed = world.t_land[tile] == 1 and bio != "iceCap" and bio != "mountain" and bio != "wetland"
		if bio == "mountain" and nat.has_flag("mountainPass"):
			allowed = true
		if bio == "wetland" and nat.has_flag("buildOnWetland"):
			allowed = true
	elif on is Array:
		allowed = on.has(bio)
	if not allowed:
		return "Cannot be built on %s." % Data.biomes[bio].name
	# tech-gated biomes
	if bdef.techFlags != null and bdef.techFlags.has(bio) and not nat.has_flag(bdef.techFlags[bio]):
		return "Requires %s to build here." % bio
	if place.get("deposit") != null and deposit[tile] != place.deposit:
		return "Requires a %s deposit." % Data.deposits[place.deposit].name
	if bdef.get("requiresNationDeposit") != null and not nation_has_deposit(n, bdef.requiresNationDeposit):
		return "Requires %s within your borders." % Data.deposits[bdef.requiresNationDeposit].name
	if bdef.get("equatorial", false) and absf(world.tiles.lat[tile]) > 15.0:
		return "Must be built within 15° of the equator."
	# uniqueness
	if bdef.unique != null:
		for t in range(world.NT):
			var ob = buildings[t]
			if ob == null or ob.id != bid:
				continue
			if bdef.unique == "nation" and owner[t] == n:
				return "Already built (one per nation)."
			if bdef.unique == "city" and ob.city == tile_city[tile]:
				return "This city already has one."
	# cost
	for k: String in bdef.cost:
		var need: float = bdef.cost[k] * maxf(0.3, 1.0 + nat.modv("buildCost"))
		if nat.res.get(k, 0.0) < need:
			return "Not enough %s." % k.capitalize()
	return ""


func start_building(n: int, tile: int, bid: String) -> bool:
	if can_build(n, tile, bid) != "":
		return false
	var bdef: Dictionary = Data.buildings[bid]
	var nat = nations[n]
	for k: String in bdef.cost:
		nat.res[k] -= bdef.cost[k] * maxf(0.3, 1.0 + nat.modv("buildCost"))
	buildings[tile] = {"id": bid, "city": tile_city[tile], "progress": 0, "time": int(bdef.time), "done": false}
	map_dirty = true
	return true


func wreck_random_building(n: int) -> void:
	var cand: Array = []
	for t in range(world.NT):
		var b = buildings[t]
		if b != null and b.done and b.id != "cityCenter" and owner[t] == n:
			cand.append(t)
	if cand.is_empty():
		return
	var t2: int = cand[rng.randi_range(0, cand.size() - 1)]
	notify(n, "%s was destroyed!" % Data.buildings[buildings[t2].id].name, "warn")
	buildings[t2] = null
	map_dirty = true


func find_new_deposit(n: int) -> void:
	var cand: Array = []
	for t in range(world.NT):
		if owner[t] == n and deposit[t] == "" and world.t_land[t] == 1:
			cand.append(t)
	if cand.is_empty():
		return
	var t2: int = cand[rng.randi_range(0, cand.size() - 1)]
	var bio: String = world.t_biome[t2]
	var opts: Array = []
	for dep_id: String in Data.deposits:
		if Data.deposits[dep_id].spawn.has(bio):
			opts.append(dep_id)
	if opts.is_empty():
		return
	deposit[t2] = opts[rng.randi_range(0, opts.size() - 1)]
	notify(n, "Prospectors found %s in your lands!" % Data.deposits[deposit[t2]].name, "good")


func exhaust_deposit(n: int) -> void:
	var cand: Array = []
	for t in range(world.NT):
		if owner[t] == n and deposit[t] != "":
			cand.append(t)
	if cand.is_empty():
		return
	var t2: int = cand[rng.randi_range(0, cand.size() - 1)]
	notify(n, "The %s deposit has been exhausted." % Data.deposits[deposit[t2]].name, "warn")
	deposit[t2] = ""


# ---------------- units ----------------

func spawn_unit(n: int, type: String, tile: int):
	var d: Dictionary = Data.units[type]
	var u := Army.new()
	u.id = nid()
	u.type = type
	u.nation_id = n
	u.tile = tile
	u.max_hp = float(d.hp)
	u.hp = u.max_hp
	if n >= 0:
		# barracks / academy experience
		var cid := tile_city[tile]
		if cid >= 0:
			for t in range(world.NT):
				var b = buildings[t]
				if b != null and b.done and b.city == cid:
					if b.id == "barracks":
						u.exp = maxf(u.exp, 1.25)
					elif b.id == "militaryAcademy":
						u.exp = maxf(u.exp, 1.5)
	units.append(u)
	return u


func unit_cost_ok(n: int, type: String, city) -> String:
	var d: Dictionary = Data.units[type]
	var nat = nations[n]
	if d.tech != null and not nat.researched.has(d.tech):
		return "Requires %s." % Data.techs[d.tech].name
	if d.needs != null and not nation_has_deposit(n, d.needs):
		return "Requires %s within your borders." % Data.deposits[d.needs].name
	if d.cls == "naval":
		var has_port := false
		for t in range(world.NT):
			var b = buildings[t]
			if b != null and b.done and b.city == city.id and (b.id == "port" or b.id == "harbor" or b.id == "shipyard"):
				has_port = true
		if not has_port:
			return "Naval units need a Port in this city."
	if d.cls == "air":
		var has_field := false
		for t in range(world.NT):
			var b = buildings[t]
			if b != null and b.done and b.city == city.id and (b.id == "airfield" or b.id == "airport"):
				has_field = true
		if not has_field:
			return "Air units need an Airfield in this city."
	var mult := _unit_cost_mult(n, city)
	for k: String in d.cost:
		if nat.res.get(k, 0.0) < d.cost[k] * mult:
			return "Not enough %s." % k.capitalize()
	return ""


func _unit_cost_mult(n: int, city) -> float:
	var m := maxf(0.3, 1.0 + nations[n].modv("unitCost") + (city.spec_mod("unitCostCity") if city != null else 0.0))
	return m


func train_unit(n: int, city, type: String) -> bool:
	if not city.training.is_empty():
		return false
	if unit_cost_ok(n, type, city) != "":
		return false
	var d: Dictionary = Data.units[type]
	var mult := _unit_cost_mult(n, city)
	for k: String in d.cost:
		nations[n].res[k] -= d.cost[k] * mult
	var ticks: int = maxi(2, int(float(d.cost.get("materials", 40)) / 12.0))
	city.training = {"unit": type, "ticks": ticks}
	return true


func can_enter(n: int, type: String, tile: int) -> bool:
	var d: Dictionary = Data.units[type]
	var bio: String = world.t_biome[tile]
	var b: Dictionary = Data.biomes[bio]
	var nat = nations[n] if n >= 0 else null
	if d.cls == "air":
		return true
	if b.water:
		if d.cls == "naval":
			if bio == "coast" or bio == "lake":
				return true
			if bio == "ocean":
				return nat != null and nat.has_flag("oceanTravel")
			if bio == "deepOcean":
				return nat != null and nat.has_flag("deepOcean")
			if bio == "iceCap":
				return nat != null and nat.has_flag("iceTravel")
			return false
		# land unit embarking
		if nat == null or not nat.has_flag("embark"):
			return false
		if bio == "coast" or bio == "lake":
			return true
		if bio == "ocean":
			return nat.has_flag("oceanTravel")
		if bio == "deepOcean":
			return nat.has_flag("deepOcean")
		return false
	else:
		if d.cls == "naval":
			return false
		if bio == "mountain":
			return nat != null and nat.has_flag("mountainPass")
		if bio == "iceCap":
			return nat != null and nat.has_flag("iceTravel")
		return b.passable


func move_cost(type: String, tile: int) -> float:
	var d: Dictionary = Data.units[type]
	if d.cls == "air" or type == "scout":
		return 1.0
	var b: Dictionary = Data.biomes[world.t_biome[tile]]
	var c := float(b.moveCost)
	if b.water and d.cls != "naval":
		c *= 1.5   # embarked
	return c


func find_path(n: int, type: String, from: int, to: int) -> Array:
	if from == to:
		return []
	var tiles: Dictionary = world.tiles
	var centers: PackedVector3Array = tiles.centers
	if _avg_edge == 0.0:
		_avg_edge = (centers[0] - centers[tiles.nbr[tiles.nbr_off[0]]]).length()
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var open := {from: 0.0}
	var g_score := {from: 0.0}
	var came := {}
	var target_pos := centers[to]
	var guard := 0
	while not open.is_empty() and guard < 20000:
		guard += 1
		# lowest f
		var cur := -1
		var best_f := 1e18
		for k: int in open:
			if open[k] < best_f:
				best_f = open[k]
				cur = k
		open.erase(cur)
		if cur == to:
			var path: Array = [to]
			var c2 := to
			while came.has(c2):
				c2 = came[c2]
				if c2 != from:
					path.push_front(c2)
			return path
		for e in range(off[cur], off[cur + 1]):
			var nb := nbr[e]
			if nb != to and not can_enter(n, type, nb):
				continue
			if nb == to and not can_enter(n, type, nb):
				continue
			var tentative: float = g_score[cur] + move_cost(type, nb)
			if tentative < g_score.get(nb, 1e18):
				g_score[nb] = tentative
				came[nb] = cur
				open[nb] = tentative + (centers[nb] - target_pos).length() / _avg_edge
	return []


func order_unit(u, target: int, kind := "auto") -> void:
	if kind == "auto":
		var has_enemy := false
		var tc = city_at(target)
		for e in units_on(target):
			if diplo.at_war(u.nation_id, e.nation_id):
				has_enemy = true
		if tc != null and diplo.at_war(u.nation_id, tc.nation_id):
			has_enemy = true
		kind = "attack" if has_enemy else "move"
	u.order = {"kind": kind, "target": target}
	u.path = find_path(u.nation_id, u.type, u.tile, target)
	if u.path.is_empty() and u.tile != target:
		u.order = {}


func cull_dead_units() -> void:
	for i in range(units.size() - 1, -1, -1):
		if units[i].hp <= 0:
			units.remove_at(i)


func spawn_hostiles(n: int, count: int) -> void:
	var barb_type: String = {1: "warrior", 2: "swordsman", 3: "pikeman", 4: "musketeer",
		5: "rifleman", 6: "infantry", 7: "mechInfantry", 8: "exoInfantry"}[nations[n].age]
	var cand: Array = []
	for i in range(world.NT):
		if owner[i] == -1 and world.t_land[i] == 1 and Data.biomes[world.t_biome[i]].passable:
			# near this nation's borders?
			var tiles: Dictionary = world.tiles
			for e in range(tiles.nbr_off[i], tiles.nbr_off[i + 1]):
				if owner[tiles.nbr[e]] == n:
					cand.append(i)
					break
	if cand.is_empty():
		return
	for k in range(count):
		var t: int = cand[rng.randi_range(0, cand.size() - 1)]
		spawn_unit(-2, barb_type, t)
	notify(n, "Raiders sighted near your borders!", "warn")


# ---------------- research / ages ----------------

func set_research(n: int, tid: String) -> void:
	if tech_available(n, tid):
		nations[n].researching = tid


func _auto_pick_research(n: int) -> void:
	var avail := available_techs(n)
	if avail.is_empty():
		return
	avail.sort_custom(func(a, b): return Data.techs[a].cost < Data.techs[b].cost)
	nations[n].researching = avail[0]
	notify(n, "Research began: %s" % Data.techs[avail[0]].name)


func _complete_tech(n: int, tid: String) -> void:
	var nat = nations[n]
	nat.researched[tid] = true
	nat.researching = ""
	nat.research_progress = 0.0
	nat.mods_dirty = true
	var t: Dictionary = Data.techs[tid]
	notify(n, "Research complete: %s" % t.name, "good")
	if t.flag != null and t.flag.has("revealMap"):
		fog.reveal_all(n)
		map_dirty = true
	# age advancement
	var in_age := 0
	for id2: String in nat.researched:
		if int(Data.techs[id2].age) == nat.age:
			in_age += 1
	var age_def: Dictionary = Data.age_by_id[nat.age]
	if in_age >= int(age_def.techsToAdvance) and nat.age < 8:
		nat.age += 1
		notify_all("%s has entered the %s!" % [nat.display_name, Data.age_by_id[nat.age].name],
			"good" if n == human_id else "info")
		_offer_perks(n)


func _offer_perks(n: int) -> void:
	var nat = nations[n]
	var eligible: Array = []
	for p: Dictionary in Data.perk_list:
		if not nat.perks.has(p.id) and nat.age >= int(p.get("minAge", 2)):
			eligible.append(p.id)
	if eligible.is_empty():
		return
	var offer: Array = []
	while offer.size() < 3 and not eligible.is_empty():
		var i := rng.randi_range(0, eligible.size() - 1)
		offer.append(eligible[i])
		eligible.remove_at(i)
	nat.pending_perks = offer
	if nat.is_human:
		perk_offer.emit(n)
	else:
		pick_perk(n, offer[rng.randi_range(0, offer.size() - 1)])


func pick_perk(n: int, perk_id: String) -> void:
	var nat = nations[n]
	if not nat.pending_perks.has(perk_id):
		return
	nat.perks.append(perk_id)
	nat.pending_perks = []
	nat.mods_dirty = true
	notify(n, "Perk gained: %s" % Data.perks[perk_id].name, "good")


func enact_policy(n: int, pid: String) -> String:
	var nat = nations[n]
	var p: Dictionary = Data.policies[pid]
	if nat.policies.has(pid):
		return "Already enacted."
	if p.tech != null and not nat.researched.has(p.tech):
		return "Requires %s." % Data.techs[p.tech].name
	var slots: int = nat.mod_int("maxPolicies")
	if nat.policies.size() >= slots:
		return "No free policy slots (%d)." % slots
	if nat.res.influence < float(p.cost):
		return "Not enough Influence."
	nat.res.influence -= float(p.cost)
	nat.policies.append(pid)
	nat.mods_dirty = true
	return ""


func revoke_policy(n: int, pid: String) -> void:
	nations[n].policies.erase(pid)
	nations[n].mods_dirty = true


func set_specialization(n: int, city, spec_id: String) -> String:
	var s: Dictionary = Data.specializations[spec_id]
	if city.pop < 5:
		return "City needs 5 population."
	if s.get("tech") != null and not nations[n].researched.has(s.tech):
		return "Requires %s." % Data.techs[s.tech].name
	var cost: float = s.cost * (2.0 if city.spec != "" else 1.0)
	if nations[n].res.influence < cost:
		return "Not enough Influence (%d)." % int(cost)
	nations[n].res.influence -= cost
	city.spec = spec_id
	return ""


# ---------------- ark project (science victory) ----------------

func can_fund_ark(n: int) -> String:
	var nat = nations[n]
	if not nat.has_flag("scienceVictory"):
		return "Requires the Ascension Program technology."
	var has_elevator := false
	for t in range(world.NT):
		var b = buildings[t]
		if b != null and b.done and b.id == "orbitalElevator" and owner[t] == n:
			has_elevator = true
	if not has_elevator:
		return "Requires an Orbital Elevator."
	if nat.res.materials < ARK_STAGE_COST.materials:
		return "Not enough Materials."
	if nat.res.circuits < ARK_STAGE_COST.circuits:
		return "Not enough Circuits."
	if nat.research_progress < ARK_STAGE_COST.science and nat.researching != "":
		return "Needs %d banked Science (pause research to accumulate)." % int(ARK_STAGE_COST.science)
	if nat.research_progress < ARK_STAGE_COST.science:
		return "Needs %d banked Science." % int(ARK_STAGE_COST.science)
	return ""


func fund_ark_stage(n: int) -> bool:
	if can_fund_ark(n) != "":
		return false
	var nat = nations[n]
	nat.res.materials -= ARK_STAGE_COST.materials
	nat.res.circuits -= ARK_STAGE_COST.circuits
	nat.research_progress -= ARK_STAGE_COST.science
	nat.ark_stages += 1
	notify_all("%s completed Starlight Ark stage %d of %d!" % [nat.display_name, nat.ark_stages, ARK_STAGES_NEEDED], "info")
	return true


# ---------------- main update / tick ----------------

func update(delta: float) -> void:
	if over or speed <= 0.0:
		return
	_accum += delta * speed
	while _accum >= TICK_SECONDS:
		_accum -= TICK_SECONDS
		_do_tick()


func _do_tick() -> void:
	tick_count += 1
	year += float(Data.age_by_id[nations[human_id].age].yearsPerTick)

	for n in range(nations.size()):
		if nations[n].alive:
			_economy_tick(n)
	_construction_tick()
	_training_tick()
	_movement_tick()
	_combat_tick()
	_healing_tick()
	_barbarian_tick()
	diplo.tick()
	events.tick()
	if ai != null and tick_count % 4 == 0:
		ai.tick()
	fog.recompute()
	map_dirty = true
	if tick_count % 10 == 0:
		_check_victory()
	cull_dead_units()
	_check_eliminations()


func _economy_tick(n: int) -> void:
	var nat = nations[n]
	var income := {"food": 0.0, "materials": 0.0, "gold": 0.0, "science": 0.0,
		"influence": 1.0, "coal": 0.0, "oil": 0.0, "circuits": 0.0}
	var upkeep_gold := 0.0
	var total_pop := 0

	for c in cities_of(n):
		total_pop += c.pop
		# collect this city's finished buildings
		var blds: Array = []
		for t in range(world.NT):
			var b = buildings[t]
			if b != null and b.done and b.city == c.id and owner[t] == n:
				blds.append([t, b])
		var work_frac: float = minf(1.0, float(c.pop) / maxf(1.0, float(blds.size() - 1)))  # city center is free
		for pair: Array in blds:
			var t: int = pair[0]
			var b: Dictionary = pair[1]
			var bdef: Dictionary = Data.buildings[b.id]
			var frac: float = 1.0 if b.id == "cityCenter" else work_frac
			upkeep_gold += float(bdef.upkeep) * maxf(0.3, 1.0 + nat.modv("upkeep"))
			# consumption gate
			var can_run := true
			if bdef.consumes != null:
				for k: String in bdef.consumes:
					if nat.res.get(k, 0.0) < bdef.consumes[k] * frac:
						can_run = false
			if not can_run:
				continue
			if bdef.consumes != null:
				for k: String in bdef.consumes:
					nat.res[k] -= bdef.consumes[k] * frac
			# biome multiplier
			var bio: String = world.t_biome[t]
			var bm := 1.0
			if bdef.biomeMul != null and bdef.biomeMul.has(bio):
				bm = float(bdef.biomeMul[bio])
			for k: String in bdef.yields:
				var mult: float = 1.0 + nat.modv(k) + nat.modv("b:" + b.id) + c.spec_mod(k)
				var out: float = bdef.yields[k] * bm * maxf(0.0, mult) * frac
				income[k] = income.get(k, 0.0) + out
			# deposit bonus
			var dep: String = deposit[t]
			if dep != "":
				var ddef: Dictionary = Data.deposits[dep]
				if ddef.worksWith.has(b.id):
					var dep_mult: float = 2.0 if b.id == "deepMine" else 1.0
					for k: String in ddef.yields:
						income[k] = income.get(k, 0.0) + ddef.yields[k] * frac * dep_mult
			# city center also harvests its tile's biome
			if b.id == "cityCenter":
				var byields: Dictionary = Data.biomes[bio].yields
				for k: String in byields:
					income[k] = income.get(k, 0.0) + float(byields[k]) * 0.5
		# owned undeveloped tiles trickle
		for t in range(world.NT):
			if owner[t] == n and tile_city[t] == c.id and buildings[t] == null:
				var byields2: Dictionary = Data.biomes[world.t_biome[t]].yields
				for k: String in byields2:
					income[k] = income.get(k, 0.0) + float(byields2[k]) * 0.2

	# unit upkeep
	var unit_upkeep := 0.0
	for u in units:
		if u.nation_id == n:
			unit_upkeep += float(Data.units[u.type].upkeep)
	unit_upkeep *= maxf(0.2, 1.0 + nat.modv("unitUpkeep"))

	# apply difficulty handicap
	for k: String in income:
		income[k] *= nat.bonus_mult

	# food & growth
	var net_food: float = income.food - float(total_pop)
	nat.res.food = maxf(0.0, nat.res.food + net_food)
	var cs := cities_of(n)
	if not cs.is_empty():
		var per_city := net_food / cs.size()
		for c in cs:
			c.growth += maxf(per_city, -3.0) + (0.3 if per_city > 0 else 0.0)
			var thresh: float = GROWTH_BASE + GROWTH_PER_POP * float(c.pop)
			var grow_mult: float = 1.0 + nat.modv("popGrowth")
			if c.growth >= thresh / maxf(0.2, grow_mult):
				c.growth = 0.0
				if c.pop < city_max_pop(c):
					c.pop += 1
					notify(n, "%s grew to %d population." % [c.cname, c.pop])
			elif c.growth < -thresh * 0.5:
				c.growth = 0.0
				if c.pop > 1:
					c.pop -= 1
					notify(n, "Starvation in %s!" % c.cname, "warn")

	# strategic + core resources
	nat.res.materials += income.materials
	nat.res.coal += income.coal
	nat.res.oil += income.oil
	nat.res.circuits += income.circuits
	nat.res.gold += income.gold - upkeep_gold - unit_upkeep
	if nat.res.gold < 0.0:
		nat.res.gold = 0.0
		for u in units:
			if u.nation_id == n:
				u.hp -= u.max_hp * 0.02   # unpaid armies desert
		notify(n, "Treasury empty — armies are deserting!", "warn")

	# influence & border upkeep
	var b_up := border_upkeep(n)
	nat.res.influence += income.influence - b_up
	if nat.res.influence < 0.0:
		nat.res.influence = 0.0
		if tick_count % 4 == 0:
			_decay_border(n)

	# research
	if nat.researching == "" and not nat.is_human:
		_auto_pick_research(n)
	elif nat.researching == "" and nat.is_human:
		if not nat.has_meta("nagged_research"):
			nat.set_meta("nagged_research", true)
			notify(n, "Choose a technology to research (Tech button).", "warn")
	elif nat.researching != "" and nat.is_human:
		nat.remove_meta("nagged_research")
	nat.research_progress += income.science
	if nat.researching != "":
		var t: Dictionary = Data.techs[nat.researching]
		if nat.research_progress >= float(t.cost):
			nat.research_progress -= float(t.cost)
			_complete_tech(n, nat.researching)

	nat.war_weariness = maxf(0.0, nat.war_weariness - 0.001)

	# cache last income for UI
	nat.set_meta("income", income)
	nat.set_meta("upkeep", {"gold": upkeep_gold + unit_upkeep, "influence": b_up})


func _construction_tick() -> void:
	for t in range(world.NT):
		var b = buildings[t]
		if b == null or b.done:
			continue
		b.progress += 1
		if b.progress >= b.time:
			b.done = true
			map_dirty = true
			if owner[t] == human_id:
				notify(human_id, "%s completed." % Data.buildings[b.id].name, "good")


func _training_tick() -> void:
	for c in cities:
		if c.training.is_empty():
			continue
		c.training.ticks -= 1
		if c.training.ticks <= 0:
			spawn_unit(c.nation_id, c.training.unit, c.tile)
			notify(c.nation_id, "%s trained in %s." % [Data.units[c.training.unit].name, c.cname])
			c.training = {}


func _movement_tick() -> void:
	for u in units:
		u.fought_this_tick = false
		if u.path.is_empty():
			continue
		var next: int = u.path[0]
		# stop before hostile tiles; combat handles them
		var blocked := false
		for e in units_on(next):
			if e.nation_id != u.nation_id and diplo.at_war(u.nation_id, e.nation_id):
				blocked = true
		var tc = city_at(next)
		if tc != null and diplo.at_war(u.nation_id, tc.nation_id):
			blocked = true
		if blocked:
			continue
		var d: Dictionary = Data.units[u.type]
		var nat_speed := 1.0
		if u.nation_id >= 0:
			nat_speed = 1.0 + nations[u.nation_id].modv("moveSpeed")
		u.move_progress += float(d.move) * nat_speed / move_cost(u.type, next)
		if u.move_progress >= 1.0:
			u.move_progress = 0.0
			u.tile = next
			u.path.pop_front()
			if u.path.is_empty():
				_on_unit_arrived(u)


func _on_unit_arrived(u) -> void:
	if u.order.get("kind") == "found" and u.type == "settler":
		if can_found_city(u.nation_id, u.tile) == "":
			found_city(u.nation_id, u.tile)
			u.hp = -1   # consumed
		else:
			notify(u.nation_id, "Settler cannot found a city here: %s" % can_found_city(u.nation_id, u.tile), "warn")
	u.order = {}


func _combat_tick() -> void:
	for u in units:
		if u.hp <= 0 or u.order.get("kind") != "attack":
			continue
		var target: int = u.order.target
		# adjacent or on target?
		var adjacent: bool = u.tile == target
		if not adjacent:
			var tiles: Dictionary = world.tiles
			for e in range(tiles.nbr_off[u.tile], tiles.nbr_off[u.tile + 1]):
				if tiles.nbr[e] == target:
					adjacent = true
		if not adjacent:
			continue
		var d: Dictionary = Data.units[u.type]
		var defenders: Array = []
		for e2 in units_on(target):
			if e2.hp > 0 and diplo.at_war(u.nation_id, e2.nation_id):
				defenders.append(e2)
		if not defenders.is_empty():
			_resolve_fight(u, defenders[0])
		else:
			var tc = city_at(target)
			if tc != null and diplo.at_war(u.nation_id, tc.nation_id):
				_resolve_siege(u, tc)
			else:
				u.order = {}


func _combat_mods(u) -> float:
	if u.nation_id < 0:
		return 1.0
	return 1.0 + nations[u.nation_id].modv("atk") + \
		(nations[u.nation_id].modv("navalAtk") if Data.units[u.type].cls == "naval" else 0.0)


func _resolve_fight(a, b) -> void:
	var da: Dictionary = Data.units[a.type]
	var db: Dictionary = Data.units[b.type]
	var anti_cav: bool = (b.type == "spearman" or b.type == "pikeman") and da.cls == "cavalry"
	var def_mods := 1.0
	if b.nation_id >= 0:
		def_mods += nations[b.nation_id].modv("def")
	var terrain: float = 1.0 + float(Data.biomes[world.t_biome[b.tile]].defense)
	var atk_power: float = float(da.atk) * a.exp * _combat_mods(a)
	var def_power: float = float(db.def) * b.exp * def_mods * terrain * (1.5 if anti_cav else 1.0)
	b.hp -= 9.0 * atk_power / maxf(1.0, atk_power + def_power) * (0.85 + rng.randf() * 0.3) * 3.0
	var notes_v = da.get("notes")
	var ranged: bool = notes_v != null and String(notes_v).contains("Ranged")
	if not ranged:
		var counter: float = float(db.atk) * b.exp * (1.5 if anti_cav else 1.0)
		a.hp -= 6.0 * counter / maxf(1.0, counter + float(da.def) * a.exp) * (0.85 + rng.randf() * 0.3) * 3.0
	a.exp = minf(2.0, a.exp + 0.02)
	b.exp = minf(2.0, b.exp + 0.02)
	a.fought_this_tick = true
	b.fought_this_tick = true
	if b.hp <= 0 and a.nation_id >= 0:
		notify(a.nation_id, "Enemy %s destroyed!" % db.name, "good")
	if b.hp <= 0 and b.nation_id == human_id:
		notify(human_id, "Our %s was destroyed!" % db.name, "warn")


func _resolve_siege(u, c) -> void:
	var d: Dictionary = Data.units[u.type]
	var siege_mult: float = float(d.get("siege", 1))
	var dmg: float = float(d.atk) * u.exp * _combat_mods(u) * siege_mult * 0.15
	c.hp -= dmg
	u.fought_this_tick = true
	# city returns fire
	u.hp -= city_defense(c) * 0.06
	if c.hp <= 0:
		c.hp = 0
		var can_capture: bool = d.cls == "melee" or d.cls == "cavalry"
		if can_capture and u.hp > 0:
			_capture_city(u.nation_id, c)
			u.tile = c.tile
			u.order = {}


func _capture_city(n: int, c) -> void:
	var old: int = c.nation_id
	notify_all("%s captured %s from %s!" % [nations[n].display_name, c.cname, nations[old].display_name], "warn")
	c.nation_id = n
	c.hp = city_defense(c) * 0.5
	c.pop = maxi(1, c.pop - 1)
	c.training = {}
	owner[c.tile] = n
	var tiles: Dictionary = world.tiles
	for e in range(tiles.nbr_off[c.tile], tiles.nbr_off[c.tile + 1]):
		var nb: int = tiles.nbr[e]
		if owner[nb] == old:
			owner[nb] = n
			tile_city[nb] = c.id
	if nations[old].capital_tile == c.tile:
		# relocate old capital if it has other cities
		var rest := cities_of(old)
		nations[old].capital_tile = rest[0].tile if not rest.is_empty() else -1
	_recompute_city_dist(n)
	_recompute_city_dist(old)
	map_dirty = true


func _healing_tick() -> void:
	for u in units:
		if u.fought_this_tick or u.hp >= u.max_hp or u.hp <= 0:
			continue
		if u.nation_id >= 0 and owner[u.tile] == u.nation_id:
			u.hp = minf(u.max_hp, u.hp + 3.0 * (1.0 + nations[u.nation_id].modv("healRate")))


func _barbarian_tick() -> void:
	for u in units:
		if u.nation_id != -2 or u.hp <= 0:
			continue
		if not u.order.is_empty() or not u.path.is_empty():
			continue
		# hunt the nearest unit or city within 6 tiles
		var dist := SphereGrid.bfs_distances(world.tiles, [u.tile], 6)
		var best := -1
		var best_d := 999
		for v in units:
			if v.nation_id >= 0 and dist[v.tile] >= 0 and dist[v.tile] < best_d:
				best_d = dist[v.tile]
				best = v.tile
		for c in cities:
			if dist[c.tile] >= 0 and dist[c.tile] < best_d:
				best_d = dist[c.tile]
				best = c.tile
		if best >= 0:
			order_unit(u, best, "attack")


func _check_eliminations() -> void:
	for nat in nations:
		if nat.alive and cities_of(nat.id).is_empty():
			nat.alive = false
			for i in range(units.size() - 1, -1, -1):
				if units[i].nation_id == nat.id:
					units.remove_at(i)
			for t in range(world.NT):
				if owner[t] == nat.id:
					owner[t] = -1
					tile_city[t] = -1
			notify_all("%s has been eliminated!" % nat.display_name, "warn")
			map_dirty = true


func _check_victory() -> void:
	if over:
		return
	var land_total: int = world.land_tiles.size()
	for nat in nations:
		if not nat.alive:
			continue
		# domination: own every starting capital tile
		var dom := true
		for cap_tile: int in world_capitals:
			var c = city_at(cap_tile)
			if c == null or c.nation_id != nat.id:
				dom = false
				break
		if dom and world_capitals.size() > 1:
			_win(nat.id, "domination")
			return
		# science
		if nat.ark_stages >= ARK_STAGES_NEEDED:
			_win(nat.id, "science")
			return
		# economic
		if nat.res.gold >= 75000.0 and diplo.deal_count(nat.id) >= 5:
			_win(nat.id, "economic")
			return
		# hegemony
		var owned_land := 0
		for t: int in world.land_tiles:
			if owner[t] == nat.id:
				owned_land += 1
		if owned_land >= int(land_total * 0.4):
			_win(nat.id, "hegemony")
			return
	# score victory at year 2200
	if year >= 2200.0:
		var best := -1
		var best_s := -1.0
		for nat in nations:
			if nat.alive and score(nat.id) > best_s:
				best_s = score(nat.id)
				best = nat.id
		if best >= 0:
			_win(best, "score")


func score(n: int) -> float:
	var s := 0.0
	for c in cities_of(n):
		s += c.pop * 3.0
	for t in range(world.NT):
		if owner[t] == n:
			s += 1.0
			if buildings[t] != null and buildings[t].done:
				s += 2.0
	s += nations[n].researched.size() * 5.0
	s += nations[n].res.gold / 100.0
	return s


func _win(n: int, vid: String) -> void:
	over = true
	winner = n
	victory_id = vid
	victory.emit(n, vid)


# ---------------- save / load ----------------

func save_game() -> void:
	var data := {
		"params": params, "tick": tick_count, "year": year,
		"owner": Array(owner), "tile_city": Array(tile_city),
		"deposit": deposit, "world_capitals": world_capitals,
		"buildings": [], "cities": [], "units": [], "nations": [],
		"diplo": {"relations": diplo.relations, "statuses": diplo.statuses, "deals": diplo.deals},
		"fog": [],
	}
	for t in range(world.NT):
		data.buildings.append(buildings[t])
	for c in cities:
		data.cities.append({"id": c.id, "tile": c.tile, "nation": c.nation_id, "name": c.cname,
			"pop": c.pop, "growth": c.growth, "spec": c.spec, "hp": c.hp, "training": c.training,
			"orig_cap": c.is_original_capital})
	for u in units:
		data.units.append({"id": u.id, "type": u.type, "nation": u.nation_id, "tile": u.tile,
			"hp": u.hp, "exp": u.exp, "path": u.path, "order": u.order})
	for nat in nations:
		data.nations.append({"id": nat.id, "alive": nat.alive, "capital": nat.capital_tile,
			"res": nat.res, "researched": nat.researched.keys(), "researching": nat.researching,
			"progress": nat.research_progress, "age": nat.age, "perks": nat.perks,
			"pending_perks": nat.pending_perks, "policies": nat.policies,
			"temp_mods": nat.temp_mods, "ww": nat.war_weariness, "ark": nat.ark_stages,
			"aggr": nat.ai_aggression, "expa": nat.ai_expansion, "bonus": nat.bonus_mult})
	for n in range(nations.size()):
		data.fog.append(Marshalls.raw_to_base64(fog.discovered[n]))
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	notify(human_id, "Game saved.", "good")


static func load_game():
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	if f == null:
		return null
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null:
		return null
	var world := WorldGen.generate(data.params)
	var g := GameState.new(world, data.params)
	g.setup_from_save(data)
	return g


func setup_from_save(data: Dictionary) -> void:
	var nt: int = world.NT
	owner = PackedInt32Array()
	for v in data.owner:
		owner.append(int(v))
	tile_city = PackedInt32Array()
	for v in data.tile_city:
		tile_city.append(int(v))
	deposit = data.deposit
	world_capitals = data.world_capitals.map(func(x): return int(x))
	tick_count = int(data.tick)
	year = float(data.year)
	buildings.resize(nt)
	for t in range(nt):
		var b = data.buildings[t]
		if b != null:
			buildings[t] = {"id": b.id, "city": int(b.city), "progress": int(b.progress),
				"time": int(b.time), "done": b.done}
	var difficulty: String = params.get("difficulty", "normal")
	for nd: Dictionary in data.nations:
		var nat := Nation.new()
		nat.id = int(nd.id)
		nat.display_name = NATION_DEFS[nat.id % NATION_DEFS.size()].name
		nat.color = NATION_DEFS[nat.id % NATION_DEFS.size()].color
		nat.is_human = nat.id == 0
		nat.alive = nd.alive
		nat.capital_tile = int(nd.capital)
		nat.res = nd.res
		for tid in nd.researched:
			nat.researched[tid] = true
		nat.researching = nd.researching
		nat.research_progress = float(nd.progress)
		nat.age = int(nd.age)
		nat.perks = nd.perks
		nat.pending_perks = nd.pending_perks
		nat.policies = nd.policies
		nat.temp_mods = nd.temp_mods
		nat.war_weariness = float(nd.ww)
		nat.ark_stages = int(nd.ark)
		nat.ai_aggression = float(nd.aggr)
		nat.ai_expansion = float(nd.expa)
		nat.bonus_mult = float(nd.bonus)
		nations.append(nat)
	human_id = 0
	for cd: Dictionary in data.cities:
		var c := City.new()
		c.id = int(cd.id)
		c.tile = int(cd.tile)
		c.nation_id = int(cd.nation)
		c.cname = cd.name
		c.pop = int(cd.pop)
		c.growth = float(cd.growth)
		c.spec = cd.spec
		c.hp = float(cd.hp)
		c.training = cd.training
		c.is_original_capital = cd.orig_cap
		cities.append(c)
	diplo = Diplomacy.new(self)
	diplo.relations = data.diplo.relations
	diplo.statuses = data.diplo.statuses
	diplo.deals = data.diplo.deals
	fog = FogOfWar.new(self)
	for n in range(nations.size()):
		if n < data.fog.size():
			fog.discovered[n] = Marshalls.base64_to_raw(data.fog[n])
	events = EventSystem.new(self)
	var ai_script = load("res://scripts/game/ai.gd")
	ai = ai_script.new(self) if ai_script != null else null
	for ud: Dictionary in data.units:
		var d: Dictionary = Data.units[ud.type]
		var u := Army.new()
		u.id = int(ud.id)
		u.type = ud.type
		u.nation_id = int(ud.nation)
		u.tile = int(ud.tile)
		u.hp = float(ud.hp)
		u.max_hp = float(d.hp)
		u.exp = float(ud.exp)
		u.path = ud.path.map(func(x): return int(x))
		u.order = ud.order
		units.append(u)
		_next_id = maxi(_next_id, u.id + 1)
	for n in range(nations.size()):
		if nations[n].alive:
			_recompute_city_dist(n)
	fog.recompute()
	map_dirty = true
