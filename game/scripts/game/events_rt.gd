# ============================================================
#  AEONS — random event system (runtime)
#  Rolls per nation per tick; applies data-driven effects.
#  Flat resource deltas scale with era: x 1.6^(age-1).
# ============================================================
class_name EventSystem
extends RefCounted

var game
var roll_chance := 0.012


func _init(g) -> void:
	game = g


func tick() -> void:
	for n in range(game.nations.size()):
		var nat = game.nations[n]
		if not nat.alive:
			continue
		var luck: float = nat.modv("eventLuck")
		if game.rng.randf() < roll_chance:
			var ev := _pick_event(n, luck)
			if not ev.is_empty():
				trigger(n, ev)
	# expire temp modifiers
	for nat in game.nations:
		var dirty := false
		for i in range(nat.temp_mods.size() - 1, -1, -1):
			if nat.temp_mods[i].until <= game.tick_count:
				nat.temp_mods.remove_at(i)
				dirty = true
		if dirty:
			nat.mods_dirty = true


func _pick_event(n: int, luck: float) -> Dictionary:
	var nat = game.nations[n]
	var pool: Array = []
	var total := 0.0
	for ev: Dictionary in Data.event_list:
		if nat.age < int(ev.minAge) or nat.age > int(ev.maxAge):
			continue
		if not _cond_ok(n, ev):
			continue
		var w: float = ev.weight
		# luck shifts weight toward good events
		w *= (1.0 + luck * 2.0) if ev.good else maxf(0.2, 1.0 - luck * 2.0)
		pool.append([ev, w])
		total += w
	if pool.is_empty():
		return {}
	var r: float = game.rng.randf() * total
	for p: Array in pool:
		r -= p[1]
		if r <= 0.0:
			return p[0]
	return pool[-1][0]


func _cond_ok(n: int, ev: Dictionary) -> bool:
	var cond = ev.get("cond")
	if cond == null:
		return true
	var parts: PackedStringArray = String(cond).split(":")
	match parts[0]:
		"atWar":
			for b in range(game.nations.size()):
				if game.diplo.at_war(n, b):
					return true
			return false
		"coastal":
			for c in game.cities:
				if c.nation_id != n:
					continue
				var tiles: Dictionary = game.world.tiles
				for e in range(tiles.nbr_off[c.tile], tiles.nbr_off[c.tile + 1]):
					var b2: String = game.world.t_biome[tiles.nbr[e]]
					if b2 == "coast" or b2 == "lake":
						return true
			return false
		"hasBiome":
			for i in range(game.world.NT):
				if game.owner[i] == n and game.world.t_biome[i] == parts[1]:
					return true
			return false
		"hasBuilding":
			return game.nation_has_built(n, parts[1])
		"hasDeposit":
			for i in range(game.world.NT):
				if game.owner[i] == n and game.deposit[i] == parts[1]:
					return true
			return false
		"minCities":
			var cnt := 0
			for c in game.cities:
				if c.nation_id == n:
					cnt += 1
			return cnt >= int(parts[1])
	return true


func trigger(n: int, ev: Dictionary) -> void:
	var nat = game.nations[n]
	if ev.get("choice") != null:
		if nat.is_human:
			game.pending_choice = {"nation": n, "event": ev}
			game.emit_event_popup(n, ev, true)
		else:
			apply_fx(n, ev.choice[game.rng.randi_range(0, ev.choice.size() - 1)].fx, ev)
		return
	apply_fx(n, ev.fx, ev)
	if nat.is_human:
		game.emit_event_popup(n, ev, false)


func apply_choice(n: int, choice_idx: int) -> void:
	if game.pending_choice.is_empty():
		return
	var ev: Dictionary = game.pending_choice.event
	apply_fx(n, ev.choice[choice_idx].fx, ev)
	game.pending_choice = {}


func apply_fx(n: int, fx: Dictionary, ev: Dictionary) -> void:
	var nat = game.nations[n]
	var scale: float = pow(1.6, nat.age - 1)
	if fx.has("res"):
		for k: String in fx.res:
			var amt: float = fx.res[k] * scale
			if k == "science":
				nat.research_progress += amt
			else:
				nat.res[k] = maxf(0.0, nat.res.get(k, 0.0) + amt)
	if fx.has("mod"):
		var dur: int = int(ev.get("duration", 20))
		nat.temp_mods.append({"mod": fx.mod, "until": game.tick_count + dur})
		nat.mods_dirty = true
	if fx.has("pop"):
		var delta: int = int(fx.pop)
		var city = game.random_city_of(n)
		if city != null:
			city.pop = clampi(city.pop + delta, 1, game.city_max_pop(city))
	if fx.has("hostiles"):
		game.spawn_hostiles(n, int(fx.hostiles))
	if fx.has("wreckBuilding"):
		game.wreck_random_building(n)
	if fx.has("armyDamage"):
		for u in game.units:
			if u.nation_id == n:
				u.hp *= (1.0 - float(fx.armyDamage))
		game.cull_dead_units()
	if fx.has("findDeposit"):
		game.find_new_deposit(n)
	if fx.has("exhaustDeposit"):
		game.exhaust_deposit(n)
	game.map_dirty = true
