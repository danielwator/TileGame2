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
signal research_offer(nation_id: int)
signal victory(nation_id: int, victory_id: String)

const SAVE_VERSION := 3
# real-time pace: one simulation tick every 2.4 s at 1x speed
const TICK_SECONDS := 2.4
# uniform abstract calendar: every tick advances the same number of years
# regardless of era (eras are equal-length in ticks, gated purely by research)
const YEARS_PER_TICK := 1.0
const SCORE_VICTORY_YEAR := 4000.0
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
	var research_options: Array = []   # current draw of pickable techs
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
	# tiles that are PART of the city (buildable); grows via annexation,
	# capped by cityTiles research. Everything else you own is territory.
	var tiles: Array = []

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
var tile_city: PackedInt32Array     # tile -> nearest city id for territory (-1)
var city_tile_of: PackedInt32Array  # tile -> city id if the tile is PART of that city (-1)
var tile_prod := {}                 # tile -> {res: amount} produced last tick (UI)
# per tile: null | Array[SLOTS] of (null | {id, city, progress, time, done}).
# Slot k's allowed buildings depend on slot k's biome (world.t_slots) — a tile
# spanning several biomes offers a mix of slot types (Stellaris-style districts)
var buildings: Array = []
var built_index := {}               # city_id -> {building_id: done count}
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
var year := 1.0
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
	city_tile_of = PackedInt32Array(); city_tile_of.resize(nt); city_tile_of.fill(-1)
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

	for i in range(n_players):
		draw_research_options(i)

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


# ---------------- district slots ----------------

func slots_per_tile() -> int:
	return int(world.slots_per_tile)


func slot_biome(t: int, s: int) -> String:
	return Data.biome_order[world.t_slots[t][s]]


## slot array for a tile, creating it lazily
func _ensure_slots(t: int) -> Array:
	if buildings[t] == null:
		var arr: Array = []
		arr.resize(slots_per_tile())
		buildings[t] = arr
	return buildings[t]


func slot_building(t: int, s: int):
	var arr = buildings[t]
	return null if arr == null else arr[s]


## every non-null slot entry on a tile
func tile_buildings(t: int) -> Array:
	var out: Array = []
	var arr = buildings[t]
	if arr != null:
		for b in arr:
			if b != null:
				out.append(b)
	return out


func tile_built_count(t: int) -> int:
	return tile_buildings(t).size()


func _index_add(city_id: int, bid: String, delta: int) -> void:
	if not built_index.has(city_id):
		built_index[city_id] = {}
	var m: Dictionary = built_index[city_id]
	m[bid] = int(m.get(bid, 0)) + delta
	if m[bid] <= 0:
		m.erase(bid)


func city_built_count(city_id: int, bid: String) -> int:
	return int(built_index.get(city_id, {}).get(bid, 0))


func nation_has_built(n: int, bid: String) -> bool:
	for c in cities:
		if c.nation_id == n and city_built_count(c.id, bid) > 0:
			return true
	return false


func _rebuild_built_index() -> void:
	built_index = {}
	for t in range(world.NT):
		for b in tile_buildings(t):
			if b.done:
				_index_add(int(b.city), b.id, 1)


func city_max_pop(c) -> int:
	var cap := 5
	var m: Dictionary = built_index.get(c.id, {})
	for bid: String in m:
		cap += int(Data.buildings[bid].housing) * int(m[bid])
	return cap


func city_defense(c) -> float:
	var d := 10.0
	var m: Dictionary = built_index.get(c.id, {})
	for bid: String in m:
		d += float(Data.buildings[bid].defense) * int(m[bid])
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
		# unexplored reads as a dark slate planet surface, not a void:
		# per-tile brightness variation gives it a faint mapped-parchment feel
		var v := float((ti * 2654435761) % 997) / 997.0
		var g := 0.055 + v * 0.03
		return Color(g * 0.85, g * 1.0, g * 1.5, 0.97)
	if st == 1:
		var c := Color(0.01, 0.015, 0.03, 0.5)
		var o := owner[ti]
		if o >= 0:
			var oc: Color = nations[o].color
			c = c.lerp(Color(oc.r, oc.g, oc.b, 0.6), 0.25)
		return c
	var o2 := owner[ti]
	if o2 >= 0:
		var c2: Color = nations[o2].color
		if city_at(ti) != null:
			# city center: bright, whitened urban core
			var cc := c2.lerp(Color(1, 1, 1), 0.45)
			return Color(cc.r, cc.g, cc.b, 0.42)
		if city_tile_of[ti] >= 0:
			# city district tiles: clearly urban
			var cd := c2.lerp(Color(1, 1, 1), 0.25)
			return Color(cd.r, cd.g, cd.b, 0.32)
		# plain territory: faint wash
		return Color(c2.r, c2.g, c2.b, 0.10)
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
	c.tiles = [tile]
	city_tile_of[tile] = c.id
	# the city center occupies the tile's best settleable slot
	var arr := _ensure_slots(tile)
	var center_slot := 0
	for s in range(slots_per_tile()):
		var bio: Dictionary = Data.biomes[slot_biome(tile, s)]
		if not bio.water and bio.allowsCity:
			center_slot = s
			break
	arr[center_slot] = {"id": "cityCenter", "city": c.id, "progress": 0, "time": 0, "done": true}
	_index_add(c.id, "cityCenter", 1)
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
	# territory gets sharply more expensive the farther it lies from your cities
	return CLAIM_BASE * float(b.infMul) * (1.0 + 0.5 * (d - 1)) * maxf(0.2, 1.0 + nations[n].modv("claimCost"))


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
	# influence bankruptcy: the farthest TERRITORY tile reverts to neutral
	# (tiles that are part of a city are protected)
	var worst := -1
	var worst_d := -1
	for i in range(world.NT):
		if owner[i] != n or city_at(i) != null or city_tile_of[i] >= 0:
			continue
		var d := effective_dist(n, i)
		if d > worst_d:
			worst_d = d
			worst = i
	if worst >= 0:
		owner[worst] = -1
		for b in tile_buildings(worst):
			if b.done:
				_index_add(int(b.city), b.id, -1)
		buildings[worst] = null
		tile_city[worst] = -1
		map_dirty = true
		notify(n, "Border tile lost — influence upkeep unpaid!", "warn")


# ---------------- city expansion (annexation) ----------------
#
# Only tiles that are PART of a city can hold buildings. Growing a city
# means annexing adjacent owned territory into it — costing Materials,
# Gold and Influence (scaling with city size) and capped by research
# (the cityTiles modifier from techs like Masonry, Aqueducts, Guilds...).

func city_tile_cap(n: int) -> int:
	return 1 + nations[n].mod_int("cityTiles")


func is_city_tile(t: int) -> bool:
	return city_tile_of[t] >= 0


## cost of the NEXT annexation for this city
func annex_cost(c) -> Dictionary:
	var k: int = c.tiles.size()   # 1 = just the center
	return {
		"materials": 40.0 + 30.0 * (k - 1),
		"gold": 20.0 + 15.0 * (k - 1),
		"influence": 15.0 + 10.0 * (k - 1),
	}


## "" if `tile` can be annexed into nation n's adjacent city, else the reason
func can_annex(n: int, tile: int) -> String:
	if owner[tile] != n:
		return "Not your territory."
	if city_tile_of[tile] >= 0:
		return "Already part of a city."
	if world.t_land[tile] == 0:
		return "Cities cannot annex open water."
	# must touch one of this nation's city tiles
	var tiles: Dictionary = world.tiles
	var c = null
	for e in range(tiles.nbr_off[tile], tiles.nbr_off[tile + 1]):
		var nb: int = tiles.nbr[e]
		var cid := city_tile_of[nb]
		if cid >= 0 and cities[cid].nation_id == n:
			c = cities[cid]
			break
	if c == null:
		return "Must border one of your city's tiles."
	if c.tiles.size() >= city_tile_cap(n):
		return "%s is at its size limit (%d) — research urban technologies to grow further." % [c.cname, city_tile_cap(n)]
	var cost := annex_cost(c)
	var nat = nations[n]
	for k: String in cost:
		if nat.res.get(k, 0.0) < cost[k]:
			return "Not enough %s (%d needed)." % [k.capitalize(), int(cost[k])]
	return ""


## the city that would receive this tile if annexed (null if none)
func annex_target(n: int, tile: int):
	var tiles: Dictionary = world.tiles
	for e in range(tiles.nbr_off[tile], tiles.nbr_off[tile + 1]):
		var cid := city_tile_of[tiles.nbr[e]]
		if cid >= 0 and cities[cid].nation_id == n:
			return cities[cid]
	return null


func annex_tile(n: int, tile: int) -> bool:
	if can_annex(n, tile) != "":
		return false
	var c = annex_target(n, tile)
	if c == null:
		return false
	var cost := annex_cost(c)
	var nat = nations[n]
	for k: String in cost:
		nat.res[k] -= cost[k]
	c.tiles.append(tile)
	city_tile_of[tile] = c.id
	tile_city[tile] = c.id
	map_dirty = true
	notify(n, "%s annexed a new district tile (%d / %d)." % [c.cname, c.tiles.size(), city_tile_cap(n)], "good")
	return true


# ---------------- buildings ----------------

## Can `bid` be built in slot `slot` of `tile`? "" if yes, else the reason.
## Rules depend on the SLOT's biome: a tile spanning forest + coast offers
## forest slots (lumber camps...) and coast slots (fisheries, ports...).
func can_build(n: int, tile: int, slot: int, bid: String) -> String:
	var bdef: Dictionary = Data.buildings[bid]
	if owner[tile] != n:
		return "Not your territory."
	if city_tile_of[tile] == -1:
		return "Buildings need city tiles — annex this tile into a city first."
	if cities[city_tile_of[tile]].nation_id != n:
		return "This district belongs to another nation's city."
	if slot < 0 or slot >= slots_per_tile():
		return "Invalid slot."
	if slot_building(tile, slot) != null:
		return "Slot already developed."
	var nat = nations[n]
	if bdef.tech != null and not nat.researched.has(bdef.tech):
		return "Requires %s." % Data.techs[bdef.tech].name
	# slot-biome placement
	var bio: String = slot_biome(tile, slot)
	var place: Dictionary = bdef.place
	var on = place.get("on")
	var allowed := false
	if on is String and on == "land":
		allowed = not Data.biomes[bio].water and bio != "iceCap" and bio != "mountain" and bio != "wetland"
		if bio == "mountain" and nat.has_flag("mountainPass"):
			allowed = true
		if bio == "wetland" and nat.has_flag("buildOnWetland"):
			allowed = true
	elif on is Array:
		allowed = on.has(bio)
	if not allowed:
		return "Needs a different terrain slot (%s)." % Data.biomes[bio].name
	# tech-gated biomes
	if bdef.techFlags != null and bdef.techFlags.has(bio) and not nat.has_flag(bdef.techFlags[bio]):
		return "Requires %s to build here." % bio
	if place.get("deposit") != null:
		if deposit[tile] != place.deposit:
			return "Requires a %s deposit." % Data.deposits[place.deposit].name
		# one extractor per deposit tile
		for b in tile_buildings(tile):
			if b.id == bid:
				return "The deposit already has an extractor."
	if bdef.get("requiresNationDeposit") != null and not nation_has_deposit(n, bdef.requiresNationDeposit):
		return "Requires %s within your borders." % Data.deposits[bdef.requiresNationDeposit].name
	if bdef.get("equatorial", false) and absf(world.tiles.lat[tile]) > 15.0:
		return "Must be built within 15° of the equator."
	# uniqueness (done buildings via index + anything under construction)
	if bdef.unique != null:
		var cid := tile_city[tile]
		if bdef.unique == "city":
			if city_built_count(cid, bid) > 0 or _city_in_progress(cid, bid):
				return "This city already has one."
		elif bdef.unique == "nation":
			if nation_has_built(n, bid) or _nation_in_progress(n, bid):
				return "Already built (one per nation)."
	# cost
	for k: String in bdef.cost:
		var need: float = bdef.cost[k] * maxf(0.3, 1.0 + nat.modv("buildCost"))
		if nat.res.get(k, 0.0) < need:
			return "Not enough %s." % k.capitalize()
	return ""


func _city_in_progress(city_id: int, bid: String) -> bool:
	for t in range(world.NT):
		if tile_city[t] != city_id:
			continue
		for b in tile_buildings(t):
			if b.id == bid and not b.done:
				return true
	return false


func _nation_in_progress(n: int, bid: String) -> bool:
	for t in range(world.NT):
		if owner[t] != n:
			continue
		for b in tile_buildings(t):
			if b.id == bid and not b.done:
				return true
	return false


func start_building(n: int, tile: int, slot: int, bid: String) -> bool:
	if can_build(n, tile, slot, bid) != "":
		return false
	var bdef: Dictionary = Data.buildings[bid]
	var nat = nations[n]
	for k: String in bdef.cost:
		nat.res[k] -= bdef.cost[k] * maxf(0.3, 1.0 + nat.modv("buildCost"))
	var arr := _ensure_slots(tile)
	arr[slot] = {"id": bid, "city": tile_city[tile], "progress": 0, "time": int(bdef.time), "done": false}
	map_dirty = true
	return true


## first slot where `bid` is currently buildable (-1 if none)
func best_slot_for(n: int, tile: int, bid: String) -> int:
	for s in range(slots_per_tile()):
		if can_build(n, tile, s, bid) == "":
			return s
	return -1


func demolish(n: int, tile: int, slot: int) -> String:
	if owner[tile] != n:
		return "Not your territory."
	var b = slot_building(tile, slot)
	if b == null:
		return "Nothing here."
	if b.id == "cityCenter":
		return "Cannot demolish a city center."
	if b.done:
		_index_add(int(b.city), b.id, -1)
	buildings[tile][slot] = null
	map_dirty = true
	return ""


func wreck_random_building(n: int) -> void:
	var cand: Array = []
	for t in range(world.NT):
		if owner[t] != n or buildings[t] == null:
			continue
		for s in range(slots_per_tile()):
			var b = slot_building(t, s)
			if b != null and b.done and b.id != "cityCenter":
				cand.append([t, s])
	if cand.is_empty():
		return
	var pick: Array = cand[rng.randi_range(0, cand.size() - 1)]
	var wb: Dictionary = buildings[pick[0]][pick[1]]
	notify(n, "%s was destroyed!" % Data.buildings[wb.id].name, "warn")
	_index_add(int(wb.city), wb.id, -1)
	buildings[pick[0]][pick[1]] = null
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
			if city_built_count(cid, "barracks") > 0:
				u.exp = maxf(u.exp, 1.25)
			if city_built_count(cid, "militaryAcademy") > 0:
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
		if city_built_count(city.id, "port") == 0 and city_built_count(city.id, "harbor") == 0 \
			and city_built_count(city.id, "shipyard") == 0:
			return "Naval units need a Port in this city."
	if d.cls == "air":
		if city_built_count(city.id, "airfield") == 0 and city_built_count(city.id, "airport") == 0:
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
#
# Research is a DRAW: each nation is offered research_option_count()
# weighted options (base 3; techs like Writing add more). Weights lean
# toward the branches the nation is "spec'd into" — its researched-tech
# history, policies, perks and city specializations.

const BRANCH_IDS := ["agri", "craft", "mil", "com", "sci", "civ"]
const POLICY_TYPE_BRANCHES := {
	"economy": {"com": 0.8, "agri": 0.4, "craft": 0.4},
	"military": {"mil": 1.2},
	"society": {"civ": 0.8, "sci": 0.4},
}
const MOD_KEY_BRANCHES := {
	"food": "agri", "b:farm": "agri", "b:pasture": "agri", "b:fishery": "agri", "popGrowth": "agri",
	"materials": "craft", "b:factory": "craft", "buildCost": "craft",
	"gold": "com", "tradeCap": "com",
	"science": "sci", "researchOptions": "sci",
	"influence": "civ", "claimCost": "civ", "borderUpkeep": "civ", "maxPolicies": "civ",
	"atk": "mil", "def": "mil", "navalAtk": "mil", "unitCost": "mil", "unitUpkeep": "mil",
}
const SPEC_BRANCHES := {
	"breadbasket": "agri", "forgeCity": "craft", "tradeNexus": "com",
	"scholarHaven": "sci", "holyCity": "civ", "bastion": "mil",
	"navalBase": "mil", "garrisonCity": "mil", "culturalJewel": "civ", "techHub": "sci",
}


func research_option_count(n: int) -> int:
	return 3 + nations[n].mod_int("researchOptions")


## How strongly this nation leans toward each tech branch (0..1 per branch).
func branch_affinity(n: int) -> Dictionary:
	var nat = nations[n]
	var pts := {}
	for b in BRANCH_IDS:
		pts[b] = 0.0
	for tid: String in nat.researched:
		pts[Data.techs[tid].branch] += 1.0
	for pid: String in nat.policies:
		var per: Dictionary = POLICY_TYPE_BRANCHES.get(Data.policies[pid].type, {})
		for b2: String in per:
			pts[b2] += per[b2] * 3.0
	for perk_id: String in nat.perks:
		for k: String in Data.perks[perk_id].mod:
			var b3 = MOD_KEY_BRANCHES.get(k)
			if b3 != null:
				pts[b3] += 2.0
	for c in cities_of(n):
		if c.spec != "":
			var b4 = SPEC_BRANCHES.get(c.spec)
			if b4 != null:
				pts[b4] += 3.0
	var mx := 0.0
	for b5 in BRANCH_IDS:
		mx = maxf(mx, pts[b5])
	if mx <= 0.0:
		return pts
	for b6 in BRANCH_IDS:
		pts[b6] = pts[b6] / mx
	return pts


## Draw a fresh weighted offer of research options for this nation.
func draw_research_options(n: int) -> void:
	var nat = nations[n]
	var avail := available_techs(n)
	if avail.is_empty():
		nat.research_options = []
		return
	var aff := branch_affinity(n)
	var pool: Array = []   # [tid, weight]
	for tid: String in avail:
		var t: Dictionary = Data.techs[tid]
		var w: float = 1.0 + 2.0 * float(aff[t.branch])
		if int(t.age) == nat.age:
			w *= 1.25
		elif int(t.age) < nat.age:
			w *= 1.1   # catching up on old techs is slightly encouraged
		pool.append([tid, w])
	var count := mini(research_option_count(n), pool.size())
	var picked: Array = []
	for k in range(count):
		var total := 0.0
		for pr: Array in pool:
			total += pr[1]
		var r := rng.randf() * total
		for i in range(pool.size()):
			r -= pool[i][1]
			if r <= 0.0:
				picked.append(pool[i][0])
				pool.remove_at(i)
				break
	nat.research_options = picked
	if nat.is_human:
		research_offer.emit(n)


## Player/AI picks one of the offered options.
func pick_research(n: int, tid: String) -> bool:
	var nat = nations[n]
	if not nat.research_options.has(tid) or not tech_available(n, tid):
		return false
	nat.researching = tid
	nat.research_options = []
	notify(n, "Research began: %s" % Data.techs[tid].name)
	return true


func reroll_cost(n: int) -> float:
	return 8.0 + 4.0 * float(nations[n].age)


func reroll_research(n: int) -> String:
	var nat = nations[n]
	var cost := reroll_cost(n)
	if nat.res.influence < cost:
		return "Not enough Influence (%d)." % int(cost)
	nat.res.influence -= cost
	draw_research_options(n)
	return ""


## Debug/test helper — bypasses the draw (still respects prerequisites).
func set_research(n: int, tid: String) -> void:
	if tech_available(n, tid):
		nations[n].researching = tid
		nations[n].research_options = []


func _auto_pick_research(n: int) -> void:
	var nat = nations[n]
	if nat.research_options.is_empty():
		draw_research_options(n)
	if nat.research_options.is_empty():
		return
	# AI: personality-weighted choice among the drawn options
	var best := ""
	var best_w := -1.0
	for tid: String in nat.research_options:
		var t: Dictionary = Data.techs[tid]
		var w := 1.0
		if t.branch == "mil":
			w *= 0.7 + nat.ai_aggression
		elif t.branch == "civ" or t.branch == "agri":
			w *= 0.7 + nat.ai_expansion
		# cheaper options finish sooner — AIs value momentum
		w *= sqrt(60.0 / maxf(20.0, float(t.cost)))
		w *= rng.randf_range(0.8, 1.2)
		if w > best_w:
			best_w = w
			best = tid
	pick_research(n, best)


func _complete_tech(n: int, tid: String) -> void:
	var nat = nations[n]
	nat.researched[tid] = true
	nat.researching = ""
	nat.research_progress = 0.0
	nat.mods_dirty = true
	var t: Dictionary = Data.techs[tid]
	notify(n, "Research complete: %s" % t.name, "good")
	draw_research_options(n)
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
	if not nation_has_built(n, "orbitalElevator"):
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
	year += YEARS_PER_TICK

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

	# per-tile production is cached for the UI (tile panel / hover)
	var add_prod := func(t: int, k: String, amt: float) -> void:
		if not tile_prod.has(t):
			tile_prod[t] = {}
		tile_prod[t][k] = tile_prod[t].get(k, 0.0) + amt

	for c in cities_of(n):
		total_pop += c.pop
		# buildings live ONLY on the city's own tiles
		var blds: Array = []          # [tile, slot, entry]
		for t: int in c.tiles:
			tile_prod.erase(t)
			var arr = buildings[t]
			if arr == null:
				continue
			for s in range(slots_per_tile()):
				var b = arr[s]
				if b != null and b.done:
					blds.append([t, s, b])
		# 1 pop works 1 building (the city center is free)
		var work_frac: float = minf(1.0, float(c.pop) / maxf(1.0, float(blds.size() - 1)))
		var dep_granted := {}         # tile -> true once its deposit bonus is applied
		for trip: Array in blds:
			var t: int = trip[0]
			var s: int = trip[1]
			var b: Dictionary = trip[2]
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
			# output scales with the biome of the SLOT the building occupies
			var bio: String = slot_biome(t, s)
			var bm := 1.0
			if bdef.biomeMul != null and bdef.biomeMul.has(bio):
				bm = float(bdef.biomeMul[bio])
			for k: String in bdef.yields:
				var mult: float = 1.0 + nat.modv(k) + nat.modv("b:" + b.id) + c.spec_mod(k)
				var out: float = bdef.yields[k] * bm * maxf(0.0, mult) * frac
				income[k] = income.get(k, 0.0) + out
				add_prod.call(t, k, out)
			# deposit bonus: once per tile, to the first matching building
			var dep: String = deposit[t]
			if dep != "" and not dep_granted.has(t):
				var ddef: Dictionary = Data.deposits[dep]
				if ddef.worksWith.has(b.id):
					dep_granted[t] = true
					var dep_mult: float = 2.0 if b.id == "deepMine" else 1.0
					for k: String in ddef.yields:
						income[k] = income.get(k, 0.0) + ddef.yields[k] * frac * dep_mult
						add_prod.call(t, k, ddef.yields[k] * frac * dep_mult)
			# city center also harvests its tile's dominant biome
			if b.id == "cityCenter":
				var byields: Dictionary = Data.biomes[world.t_biome[t]].yields
				for k: String in byields:
					income[k] = income.get(k, 0.0) + float(byields[k]) * 0.5
					add_prod.call(t, k, float(byields[k]) * 0.5)

	# territory (and empty city tiles) trickle a small share of their biome yields
	for t in range(world.NT):
		if owner[t] != n:
			continue
		if tile_built_count(t) == 0:
			tile_prod.erase(t)
			var byields2: Dictionary = Data.biomes[world.t_biome[t]].yields
			for k: String in byields2:
				var amt := float(byields2[k]) * 0.2
				if amt > 0.0:
					income[k] = income.get(k, 0.0) + amt
					add_prod.call(t, k, amt)

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
		if nat.research_options.is_empty():
			draw_research_options(n)
		if not nat.has_meta("nagged_research"):
			nat.set_meta("nagged_research", true)
			notify(n, "Your scholars await direction — pick a research option.", "warn")
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
		var arr = buildings[t]
		if arr == null:
			continue
		for s in range(slots_per_tile()):
			var b = arr[s]
			if b == null or b.done:
				continue
			b.progress += 1
			if b.progress >= b.time:
				b.done = true
				_index_add(int(b.city), b.id, 1)
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
	# the whole city (all its district tiles) changes hands
	for ct: int in c.tiles:
		owner[ct] = n
		tile_city[ct] = c.id
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
	# score victory at the calendar cap
	if year >= SCORE_VICTORY_YEAR:
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
			for b in tile_buildings(t):
				if b.done:
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
		"version": SAVE_VERSION,
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
			"orig_cap": c.is_original_capital, "tiles": c.tiles})
	for u in units:
		data.units.append({"id": u.id, "type": u.type, "nation": u.nation_id, "tile": u.tile,
			"hp": u.hp, "exp": u.exp, "path": u.path, "order": u.order})
	for nat in nations:
		data.nations.append({"id": nat.id, "alive": nat.alive, "capital": nat.capital_tile,
			"res": nat.res, "researched": nat.researched.keys(), "researching": nat.researching,
			"options": nat.research_options,
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
	if int(data.get("version", 1)) != SAVE_VERSION:
		push_warning("Save file is from an incompatible version — ignoring.")
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
		var slots = data.buildings[t]
		if slots == null:
			continue
		var arr: Array = []
		arr.resize(slots_per_tile())
		for s in range(mini(int(slots.size()), slots_per_tile())):
			var b = slots[s]
			if b != null:
				arr[s] = {"id": b.id, "city": int(b.city), "progress": int(b.progress),
					"time": int(b.time), "done": b.done}
		buildings[t] = arr
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
		nat.research_options = nd.get("options", [])
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
		c.tiles = cd.get("tiles", [c.tile]).map(func(x): return int(x))
		cities.append(c)
	city_tile_of = PackedInt32Array()
	city_tile_of.resize(nt)
	city_tile_of.fill(-1)
	for c2 in cities:
		for ct: int in c2.tiles:
			city_tile_of[ct] = c2.id
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
	_rebuild_built_index()
	fog.recompute()
	map_dirty = true
