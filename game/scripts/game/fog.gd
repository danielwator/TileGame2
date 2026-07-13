# ============================================================
#  TileGame2 — fog of war (tile layer)
#
#  Vision is NOT permanent. Each tick a nation sees only:
#   * its territory        (+1 ring)
#   * its city tiles       (+3 rings — cities watch farther)
#   * its units            (unit sight radius; scouts see farther)
#   * everything its allies currently see
#  Tiles outside that are UNKNOWN again — armies and borders can
#  slip out of view. The one exception: the Satellites technology
#  grants permanent (dimmed) terrain intel of the whole globe.
# ============================================================
class_name FogOfWar
extends RefCounted

const TERRITORY_RANGE := 1
const CITY_RANGE := 3

var game
var discovered: Array = []   # per nation PackedByteArray — satellite intel only
var visible: Array = []


func _init(g) -> void:
	game = g
	var nt: int = g.world.NT
	for n in range(g.nations.size()):
		var d := PackedByteArray(); d.resize(nt)
		var v := PackedByteArray(); v.resize(nt)
		discovered.append(d)
		visible.append(v)


func _spread(vis: PackedByteArray, sources: Array, rng_hops: int) -> void:
	var tiles: Dictionary = game.world.tiles
	var off: PackedInt32Array = tiles.nbr_off
	var nbr: PackedInt32Array = tiles.nbr
	var dist := {}
	var q: Array = []
	for s: int in sources:
		if not dist.has(s):
			dist[s] = 0
			vis[s] = 1
			q.append(s)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var d: int = dist[cur]
		if d >= rng_hops:
			continue
		for e in range(off[cur], off[cur + 1]):
			var nb := nbr[e]
			if not dist.has(nb):
				dist[nb] = d + 1
				vis[nb] = 1
				q.append(nb)


func recompute() -> void:
	var nt: int = game.world.NT
	for n in range(game.nations.size()):
		var nat = game.nations[n]
		var vis: PackedByteArray = visible[n]
		for i in range(nt):
			vis[i] = 0
		if not nat.alive:
			continue
		var bonus: int = nat.mod_int("vision")
		var territory: Array = []
		var city_tiles: Array = []
		for i in range(nt):
			if game.owner[i] != n:
				continue
			if game.city_tile_of[i] >= 0:
				city_tiles.append(i)
			else:
				territory.append(i)
		_spread(vis, territory, TERRITORY_RANGE + bonus)
		_spread(vis, city_tiles, CITY_RANGE + bonus)
		for u in game.units:
			if u.nation_id == n:
				_spread(vis, [u.tile], int(Data.units[u.type].sight) + bonus)
	# allied shared vision
	for a in range(game.nations.size()):
		for b in range(a + 1, game.nations.size()):
			if game.diplo.status(a, b) == "alliance":
				var va: PackedByteArray = visible[a]
				var vb: PackedByteArray = visible[b]
				for i in range(nt):
					var u2 := va[i] | vb[i]
					va[i] = u2
					vb[i] = u2


## Satellites etc.: permanent (dimmed) terrain intel of the whole map.
func reveal_all(nation_id: int) -> void:
	var d: PackedByteArray = discovered[nation_id]
	for i in range(d.size()):
		d[i] = 1


func state(nation_id: int, tile: int) -> int:
	if visible[nation_id][tile] == 1:
		return 2
	if discovered[nation_id][tile] == 1:
		return 1
	return 0
