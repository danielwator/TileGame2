# ============================================================
#  AEONS — diplomacy
#  Pairwise relations (-100..100), statuses (peace / war / nap /
#  alliance), gold-yielding trade deals, opinion drift.
# ============================================================
class_name Diplomacy
extends RefCounted

var game
var relations: Array = []    # 2D array [a][b] float
var statuses: Array = []     # 2D array [a][b] String
var deals: Array = []        # {a, b, ticks}
var prop_cooldown := {}      # AI id -> tick before it may petition the human again

const DEAL_TICKS := 100


func _init(g) -> void:
	game = g
	var n: int = g.nations.size()
	for a in range(n):
		var row_r: Array = []
		var row_s: Array = []
		for b in range(n):
			row_r.append(0.0)
			row_s.append("peace")
		relations.append(row_r)
		statuses.append(row_s)


func rel(a: int, b: int) -> float:
	return relations[a][b]


func status(a: int, b: int) -> String:
	if a == b or a < 0 or b < 0:
		return "self"
	return statuses[a][b]


func at_war(a: int, b: int) -> bool:
	if a == -2 or b == -2:      # barbarians hate everyone
		return a != b
	if a < 0 or b < 0 or a == b:
		return false
	return statuses[a][b] == "war"


func shift_rel(a: int, b: int, amount: float) -> void:
	relations[a][b] = clampf(relations[a][b] + amount, -100.0, 100.0)
	relations[b][a] = clampf(relations[b][a] + amount, -100.0, 100.0)


func declare_war(a: int, b: int) -> void:
	if at_war(a, b):
		return
	statuses[a][b] = "war"
	statuses[b][a] = "war"
	shift_rel(a, b, -60)
	_cancel_deals(a, b)
	game.notify_all("%s declared war on %s!" % [game.nations[a].display_name, game.nations[b].display_name], "warn")
	# defensive allies of b join
	for c in range(game.nations.size()):
		if c != a and c != b and statuses[b][c] == "alliance" and game.nations[c].alive:
			if not at_war(a, c):
				statuses[a][c] = "war"
				statuses[c][a] = "war"
				shift_rel(a, c, -40)


func make_peace(a: int, b: int) -> void:
	if not at_war(a, b):
		return
	statuses[a][b] = "peace"
	statuses[b][a] = "peace"
	shift_rel(a, b, 15)
	game.nations[a].war_weariness = maxf(0.0, game.nations[a].war_weariness - 0.4)
	game.nations[b].war_weariness = maxf(0.0, game.nations[b].war_weariness - 0.4)
	game.notify_all("%s and %s made peace." % [game.nations[a].display_name, game.nations[b].display_name], "good")


func form_alliance(a: int, b: int) -> void:
	statuses[a][b] = "alliance"
	statuses[b][a] = "alliance"
	shift_rel(a, b, 25)


func sign_nap(a: int, b: int) -> void:
	statuses[a][b] = "nap"
	statuses[b][a] = "nap"
	shift_rel(a, b, 10)


func deal_count(n: int) -> int:
	var c := 0
	for d in deals:
		if d.a == n or d.b == n:
			c += 1
	return c


func trade_cap(n: int) -> int:
	return 1 + game.nations[n].mod_int("tradeCap")


func can_trade(a: int, b: int) -> bool:
	return not at_war(a, b) and deal_count(a) < trade_cap(a) and deal_count(b) < trade_cap(b)


func make_deal(a: int, b: int) -> void:
	deals.append({"a": a, "b": b, "ticks": DEAL_TICKS})
	shift_rel(a, b, 12)
	game.notify_all("%s and %s signed a trade agreement." % [game.nations[a].display_name, game.nations[b].display_name], "good")


# ---------------- direct actions ----------------

## pay gold to sweeten relations
func send_gift(a: int, b: int, amount := 100.0) -> String:
	if game.nations[a].res.gold < amount:
		return "Not enough Gold."
	game.nations[a].res.gold -= amount
	game.nations[b].res.gold += amount * 0.5   # half arrives as actual goods
	shift_rel(a, b, 12)
	game.notify(b, "%s sent a gift of goods and gold." % game.nations[a].display_name, "good")
	return ""


## public condemnation: relations tank, your people rally
func denounce(a: int, b: int) -> void:
	shift_rel(a, b, -25)
	game.nations[a].res.influence += 15.0
	game.notify_all("%s denounced %s before the world!" % [
		game.nations[a].display_name, game.nations[b].display_name], "warn")


## strong-arm a weaker nation for gold
func demand_tribute(a: int, b: int) -> String:
	var ratio: float = game.nation_power(a) / maxf(1.0, game.nation_power(b))
	if ratio > 1.4 and rel(a, b) > -60.0:
		var tribute: float = minf(150.0, game.nations[b].res.gold * 0.25)
		game.nations[b].res.gold -= tribute
		game.nations[a].res.gold += tribute
		shift_rel(a, b, -15)
		game.notify(a, "%s pays %d Gold in tribute." % [game.nations[b].display_name, int(tribute)], "good")
		return ""
	shift_rel(a, b, -10)
	return "%s scoffs at your demand." % game.nations[b].display_name


## dissolve an alliance or non-aggression pact
func break_pact(a: int, b: int) -> String:
	if statuses[a][b] != "alliance" and statuses[a][b] != "nap":
		return "No pact to break."
	statuses[a][b] = "peace"
	statuses[b][a] = "peace"
	shift_rel(a, b, -20)
	game.notify_all("%s broke its pact with %s." % [
		game.nations[a].display_name, game.nations[b].display_name], "warn")
	return ""


func _cancel_deals(a: int, b: int) -> void:
	for i in range(deals.size() - 1, -1, -1):
		var d: Dictionary = deals[i]
		if (d.a == a and d.b == b) or (d.a == b and d.b == a):
			deals.remove_at(i)


## per-tick: deal income + slow opinion drift
func tick() -> void:
	for d in deals:
		var gain: float = 2.0 + game.nations[d.a].age
		game.nations[d.a].res.gold += gain
		game.nations[d.b].res.gold += gain
		d.ticks -= 1
	for i in range(deals.size() - 1, -1, -1):
		if deals[i].ticks <= 0:
			deals.remove_at(i)
	if game.tick_count % 10 != 0:
		return
	var n: int = game.nations.size()
	for a in range(n):
		for b in range(a + 1, n):
			if not game.nations[a].alive or not game.nations[b].alive:
				continue
			var drift := 0.0
			# borders touching create friction
			if _borders_touch(a, b):
				drift -= 0.3
			# same age = mutual respect; big age gap = contempt
			drift += 0.15 if game.nations[a].age == game.nations[b].age else -0.1
			if statuses[a][b] == "alliance":
				drift += 0.3
			elif statuses[a][b] == "war":
				drift -= 0.5
				game.nations[a].war_weariness += 0.002 * (1.0 + game.nations[a].modv("warWeariness"))
				game.nations[b].war_weariness += 0.002 * (1.0 + game.nations[b].modv("warWeariness"))
			# regression to neutral
			drift += -signf(relations[a][b]) * 0.05
			shift_rel(a, b, drift)


func _borders_touch(a: int, b: int) -> bool:
	var tiles: Dictionary = game.world.tiles
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	for i in range(game.world.NT):
		if game.owner[i] != a:
			continue
		for e in range(off[i], off[i + 1]):
			if game.owner[nbr[e]] == b:
				return true
	return false
