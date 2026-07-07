# ============================================================
#  AEONS — game data autoload (singleton `Data`)
#  Loads data/gamedata.json (single source of truth shared with
#  reference.html) and builds id-keyed lookup tables.
# ============================================================
extends Node

var ages: Array = []
var age_by_id: Dictionary = {}
var biomes: Dictionary = {}
var biome_order: Array = []           # stable index -> biome id
var biome_index: Dictionary = {}      # biome id -> stable index
var resources: Dictionary = {}
var deposits: Dictionary = {}
var techs: Dictionary = {}            # id -> tech
var tech_list: Array = []
var tech_branches: Dictionary = {}
var buildings: Dictionary = {}
var building_list: Array = []
var units: Dictionary = {}
var unit_list: Array = []
var policies: Dictionary = {}
var policy_list: Array = []
var perks: Dictionary = {}
var perk_list: Array = []
var specializations: Dictionary = {}
var spec_list: Array = []
var events: Dictionary = {}
var event_list: Array = []
var victories: Dictionary = {}
var changelog: Array = []


func _ready() -> void:
	var f := FileAccess.open("res://data/gamedata.json", FileAccess.READ)
	if f == null:
		push_error("Cannot open gamedata.json")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("gamedata.json failed to parse")
		return
	var d: Dictionary = parsed

	ages = d.ages
	for a in ages:
		age_by_id[int(a.id)] = a
	biomes = d.biomes
	biome_order = biomes.keys()
	for i in range(biome_order.size()):
		biome_index[biome_order[i]] = i
	resources = d.resources
	deposits = d.deposits
	tech_list = d.techs
	for t in tech_list:
		techs[t.id] = t
	tech_branches = d.techBranches
	building_list = d.buildings
	for b in building_list:
		buildings[b.id] = b
	unit_list = d.units
	for u in unit_list:
		units[u.id] = u
	policy_list = d.policies
	for p in policy_list:
		policies[p.id] = p
	perk_list = d.perks
	for p in perk_list:
		perks[p.id] = p
	spec_list = d.specializations
	for s in spec_list:
		specializations[s.id] = s
	event_list = d.events
	for e in event_list:
		events[e.id] = e
	victories = d.victories
	changelog = d.changelog
	print("Data loaded: %d techs, %d buildings, %d units, %d events" % [
		tech_list.size(), building_list.size(), unit_list.size(), event_list.size()])
