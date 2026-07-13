# ============================================================
#  AEONS — AI nations
#  Runs every 4 ticks. Personality comes from seeded aggression /
#  expansion drives; difficulty applies economic handicaps only.
#  Behaviors: expand borders, develop tiles, train settlers and
#  armies, found cities, wage war, sue for peace, trade.
# ============================================================
class_name NationAI
extends RefCounted

var game

const YIELD_WEIGHTS := {"food": 1.15, "materials": 1.1, "gold": 1.0, "science": 1.3,
	"influence": 0.9, "coal": 2.0, "oil": 2.0, "circuits": 2.5}


func _init(g) -> void:
	game = g


func tick() -> void:
	for n in range(game.nations.size()):
		var nat = game.nations[n]
		if not nat.alive or nat.is_human:
			continue
		# stagger workload
		if (game.tick_count / 4 + n) % 2 == 0:
			_act_economy(n)
		else:
			_act_military(n)
		_act_diplomacy(n)


# ---------------- economy ----------------

func _act_economy(n: int) -> void:
	var nat = game.nations[n]
	var rng: RandomNumberGenerator = game.rng

	# policies
	if rng.randf() < 0.3:
		var slots: int = nat.mod_int("maxPolicies")
		if nat.policies.size() < slots:
			var opts: Array = []
			for p: Dictionary in Data.policy_list:
				if not nat.policies.has(p.id) and (p.tech == null or nat.researched.has(p.tech)) \
					and nat.res.influence > float(p.cost) * 1.5:
					opts.append(p.id)
			if not opts.is_empty():
				game.enact_policy(n, opts[rng.randi_range(0, opts.size() - 1)])

	# border expansion
	if rng.randf() < nat.ai_expansion:
		var best_tile := -1
		var best_score := 0.0
		for i in range(game.world.NT):
			if game.owner[i] != -1:
				continue
			if game.can_claim(n, i) != "":
				continue
			var s := _tile_value(i)
			var cost: float = game.claim_cost(n, i)
			if nat.res.influence > cost * 1.4 and s / maxf(1.0, cost) > best_score:
				best_score = s / maxf(1.0, cost)
				best_tile = i
		if best_tile >= 0:
			game.claim_tile(n, best_tile)

	# annex territory into cities when capacity + resources allow, preferring
	# high-value compositions (deposits, food-rich biomes)
	if rng.randf() < 0.5:
		for c in game.cities_of(n):
			if c.tiles.size() >= game.city_tile_cap(n):
				continue
			var best_ax := -1
			var best_av := 0.0
			var tiles: Dictionary = game.world.tiles
			for ct: int in c.tiles:
				for e in range(tiles.nbr_off[ct], tiles.nbr_off[ct + 1]):
					var nb: int = tiles.nbr[e]
					if game.can_annex(n, nb) != "":
						continue
					var v := _tile_value(nb)
					if v > best_av:
						best_av = v
						best_ax = nb
			if best_ax >= 0:
				game.annex_tile(n, best_ax)
				break

	# construction: buildings only exist on city tiles — sample those
	var open_tiles: Array = []
	for c2 in game.cities_of(n):
		for ct2: int in c2.tiles:
			if game.tile_built_count(ct2) < game.slots_per_tile():
				open_tiles.append(ct2)
	if not open_tiles.is_empty():
		open_tiles.shuffle()
		var best_pick: Array = []      # [tile, slot, bid]
		var best_v := 0.0
		for k in range(mini(8, open_tiles.size())):
			var t: int = open_tiles[k]
			for s in range(game.slots_per_tile()):
				if game.slot_building(t, s) != null:
					continue
				for b: Dictionary in Data.building_list:
					if b.id == "cityCenter":
						continue
					if b.tech != null and not nat.researched.has(b.tech):
						continue
					if game.can_build(n, t, s, b.id) != "":
						continue
					var v := _building_value(n, t, s, b)
					if v > best_v:
						best_v = v
						best_pick = [t, s, b.id]
		if not best_pick.is_empty():
			game.start_building(n, best_pick[0], best_pick[1], best_pick[2])

	# settlers
	var my_cities: Array = game.cities_of(n)
	var want: int = 2 + nat.age / 2 + int(nat.ai_expansion * 3.0)
	var have_settler := false
	for u in game.units:
		if u.nation_id == n and u.type == "settler":
			have_settler = true
	var training_settler := false
	for c in my_cities:
		if c.training.get("unit") == "settler":
			training_settler = true
	if my_cities.size() < want and not have_settler and not training_settler and not my_cities.is_empty():
		game.train_unit(n, my_cities[0], "settler")

	# settler orders
	for u in game.units:
		if u.nation_id == n and u.type == "settler" and u.order.is_empty() and u.path.is_empty():
			var target := _find_city_site(n, u.tile)
			if target >= 0:
				game.order_unit(u, target, "found")

	# ark funding (science victory push)
	if nat.has_flag("scienceVictory") and game.can_fund_ark(n) == "":
		game.fund_ark_stage(n)


func _tile_value(i: int) -> float:
	var b: Dictionary = Data.biomes[game.world.t_biome[i]]
	var v := 0.0
	for k: String in b.yields:
		v += float(b.yields[k]) * YIELD_WEIGHTS.get(k, 1.0)
	if game.deposit[i] != "":
		v += 4.0
	return v + 0.5


func _building_value(n: int, t: int, s: int, bdef: Dictionary) -> float:
	var v := 0.0
	var bio: String = game.slot_biome(t, s)
	var bm := 1.0
	if bdef.biomeMul != null and bdef.biomeMul.has(bio):
		bm = float(bdef.biomeMul[bio])
	for k: String in bdef.yields:
		v += float(bdef.yields[k]) * YIELD_WEIGHTS.get(k, 1.0) * bm
	var dep: String = game.deposit[t]
	if dep != "" and Data.deposits[dep].worksWith.has(bdef.id):
		v += 5.0
	if bdef.housing > 0:
		v += float(bdef.housing) * 0.8
	if bdef.defense > 0:
		v += float(bdef.defense) * 0.05
	# prefer cheap early
	v /= (1.0 + float(bdef.cost.get("materials", 50)) / 200.0)
	return v


func _find_city_site(n: int, from: int) -> int:
	var dist := SphereGrid.bfs_distances(game.world.tiles, [from], 9)
	var best := -1
	var best_v := 0.0
	for i in range(game.world.NT):
		if dist[i] < 2 or dist[i] > 9:
			continue
		if game.can_found_city(n, i) != "":
			continue
		var v := _tile_value(i)
		var tiles: Dictionary = game.world.tiles
		for e in range(tiles.nbr_off[i], tiles.nbr_off[i + 1]):
			v += _tile_value(tiles.nbr[e]) * 0.35
		v /= 1.0 + dist[i] * 0.08
		if v > best_v:
			best_v = v
			best = i
	return best


# ---------------- military ----------------

func _act_military(n: int) -> void:
	var nat = game.nations[n]
	var my_cities: Array = game.cities_of(n)
	if my_cities.is_empty():
		return
	var power: float = game.nation_power(n)
	var threat: float = 30.0 + float(nat.age) * 40.0
	for b in range(game.nations.size()):
		if b != n and game.nations[b].alive and game.diplo.at_war(n, b):
			threat = maxf(threat, game.nation_power(b) * 1.1)

	# train
	if power < threat:
		var best_unit := ""
		var best_atk := 0.0
		var c = my_cities[game.rng.randi_range(0, my_cities.size() - 1)]
		for u: Dictionary in Data.unit_list:
			if u.cls == "civilian" or u.cls == "naval" or u.cls == "air":
				continue
			if game.unit_cost_ok(n, u.id, c) != "":
				continue
			if float(u.atk) > best_atk:
				best_atk = float(u.atk)
				best_unit = u.id
		if best_unit != "":
			game.train_unit(n, c, best_unit)

	# find an active war target
	var enemy := -1
	for b in range(game.nations.size()):
		if b != n and game.nations[b].alive and game.diplo.at_war(n, b):
			enemy = b
			break

	for u in game.units:
		if u.nation_id != n or u.type == "settler" or u.type == "scout":
			continue
		if not u.order.is_empty() or not u.path.is_empty():
			continue
		if enemy >= 0:
			# attack nearest enemy city
			var best_t := -1
			var best_d := 1e9
			for c2 in game.cities_of(enemy):
				var d: float = (game.world.tiles.centers[c2.tile] - game.world.tiles.centers[u.tile]).length()
				if d < best_d:
					best_d = d
					best_t = c2.tile
			if best_t >= 0:
				game.order_unit(u, best_t, "attack")
		else:
			# hunt nearby barbarians, else garrison
			var dist := SphereGrid.bfs_distances(game.world.tiles, [u.tile], 5)
			var barb := -1
			for v in game.units:
				if v.nation_id == -2 and dist[v.tile] >= 0:
					barb = v.tile
					break
			if barb >= 0:
				game.order_unit(u, barb, "attack")
			elif game.owner[u.tile] != n:
				game.order_unit(u, my_cities[0].tile, "move")

	# scouts explore
	for u in game.units:
		if u.nation_id == n and u.type == "scout" and u.path.is_empty():
			var t: int = game.rng.randi_range(0, game.world.NT - 1)
			if game.can_enter(n, "scout", t):
				game.order_unit(u, t, "move")


# ---------------- diplomacy ----------------

func _act_diplomacy(n: int) -> void:
	var nat = game.nations[n]
	var rng: RandomNumberGenerator = game.rng
	for b in range(game.nations.size()):
		if b == n or not game.nations[b].alive:
			continue
		var st: String = game.diplo.status(n, b)
		var r: float = game.diplo.rel(n, b)
		var to_human: bool = b == game.human_id
		# anything friendly aimed at the PLAYER is a proposal, never automatic
		# (war is the exception — nobody asks permission for that)
		if st == "war":
			var ratio: float = game.nation_power(n) / maxf(1.0, game.nation_power(b))
			if ratio < 0.7 or nat.war_weariness > 0.5:
				if rng.randf() < 0.4:
					if to_human:
						if game.diplo.prop_cooldown.get(str(n), 0) <= game.tick_count:
							game.queue_proposal(n, "peace")
					else:
						game.diplo.make_peace(n, b)
		else:
			var may_petition: bool = not to_human \
				or game.diplo.prop_cooldown.get(str(n), 0) <= game.tick_count
			if r > 20.0 and game.diplo.can_trade(n, b) and rng.randf() < 0.25 and may_petition:
				if to_human:
					game.queue_proposal(n, "trade")
				else:
					game.diplo.make_deal(n, b)
			if r > 60.0 and st == "peace" and rng.randf() < 0.08 and may_petition:
				if to_human:
					game.queue_proposal(n, "alliance")
				else:
					game.diplo.form_alliance(n, b)
			if r > 10.0 and st == "peace" and rng.randf() < 0.05 and to_human and may_petition:
				game.queue_proposal(n, "nap")
			if r < -35.0 and st == "peace" and rng.randf() < nat.ai_aggression * 0.15:
				var ratio2: float = game.nation_power(n) / maxf(1.0, game.nation_power(b))
				if ratio2 > 1.4:
					game.diplo.declare_war(n, b)
