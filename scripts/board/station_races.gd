extends RefCounted
## Who built a station (data/station_races.json): the races of a station, the race of each section, and what a race's body lets a section be.
## Pure logic. A race changes the skin of a section, never its footprint, doors, lanes or containers (station_gen.gd builds those without it).

const Content = preload("res://scripts/data/content.gd")
const Traits = preload("res://scripts/crew/traits.gd")
const Regions = preload("res://scripts/space/regions.gd")

const PATH := "res://data/station_races.json"

static var _cfg := {}
static var _traits := {}
static var forced: Array = []  ## a test sets it: the races every station has


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(d is Dictionary and d.get("races") is Dictionary, "bad station races: " + PATH)
		_cfg = d
	return _cfg


## The builder races (species ids with a skin), sorted.
static func ids() -> Array:
	var out: Array = config()["races"].keys()
	out.sort()
	return out


static func skin(race: String) -> Dictionary:
	return config()["races"].get(race, config()["races"]["human"])["skin"]


## The art variant a race draws fixture `fixture` with ("" for the plain one).
static func variant(race: String, fixture: String) -> String:
	return str(config()["races"].get(race, {}).get("variants", {}).get(fixture, ""))


## The home race of region `id` ("" for none).
static func home_of(region: String) -> String:
	if region == "" or not Regions.has(region):
		return ""
	var h := str(Regions.get_region(region).get("home_species", ""))
	return h if config()["races"].has(h) else ""


## The trait set of a race (its species entry and its listed traits, merged as traits.gd does).
static func traits_of(race: String) -> Dictionary:
	if not _traits.has(race):
		Traits.library()
		var sp := Content.entry("species", race)
		var out := Traits._fresh()
		Traits._merge(out, Traits.bag_of(sp))
		for t in sp.get("traits", []):
			Traits._merge(out, Traits.bag_of(Traits.library().get(str(t), {})))
		_traits[race] = out
	return _traits[race]


## Does the race need no air (its sections may be operational and airless)?
static func airless_ok(race: String) -> bool:
	var t := traits_of(race)
	return float(t["o2_use"]) <= 0.0 or bool(t["vacuum_walk"])


## x the chance one of the race's sections has power in a half-active station (its power traits).
static func power_mult(race: String) -> float:
	var t := traits_of(race)
	var m := 1.0
	var sp := Content.entry("species", race)
	var keys: Array = sp.get("traits", []).duplicate()
	for k in config()["power"]:
		if keys.has(k) or bool(t.get(k, false)):
			m = maxf(m, float(config()["power"][k]))
	return m


## "hot", "cold" or "" for a race's sections (shown in the dressing only).
static func climate(race: String) -> String:
	var t := traits_of(race)
	if float(t["dries_out"]["hp_per_s"]) > 0.0:  # (one that dries out in the heat keeps cool rooms)
		return "cold"
	if float(t["damage_taken"].get("fire", 1.0)) <= 0.3 or float(t["heat_speed"]["hot"]) > 1.0:
		return "hot"
	return ""


## The tag a race's items carry in a room of that race (loot.gd).
static func tag(race: String) -> String:
	return "race_" + race


## Does item `id` belong to `race`: its gear (data), or a part or recipe whose id starts with its prefix?
static func owns(race: String, id: String) -> bool:
	var rd: Dictionary = config()["races"].get(race, {})
	if rd.is_empty():
		return false
	if rd["items"].has(id):
		return true
	var p := str(rd.get("prefix", ""))
	return p != "" and id.begins_with(p + "_")


## The races of a station: a list, the first the dock's. A stream of its own, from the type, the region.
static func roll(r: RandomNumberGenerator, region: String, type: String) -> Array:
	if not forced.is_empty():
		return forced.duplicate()
	var cfg := config()
	var home := home_of(region)
	var pool: Dictionary = cfg["neighbours"].get(region, cfg["default_neighbours"]).duplicate()
	pool["human"] = float(pool.get("human", 0.0)) + float(cfg["human_weight"])
	pool.erase(home)
	var pk: Array = pool.keys()
	for k in pk:
		if not cfg["races"].has(k):
			pool.erase(k)
	var single := r.randf() < float(cfg["single"].get(type, 0.5))
	if home != "" and single:
		return [home]
	var span: Array = cfg["mixed"].get(type, [2, 2])
	var n := r.randi_range(int(span[0]), int(span[1]))
	var out: Array = []
	if home != "":
		out.append(home)
	while out.size() < n and not pool.is_empty():
		var k := _pick(pool, r)
		out.append(k)
		pool.erase(k)
	return out


## A key of `w` by weight, in sorted key order.
static func _pick(w: Dictionary, r: RandomNumberGenerator) -> String:
	var keys: Array = w.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(w[k])
	var roll := r.randf() * total
	for k in keys:
		roll -= float(w[k])
		if roll < 0.0:
			return str(k)
	return str(keys[-1])
