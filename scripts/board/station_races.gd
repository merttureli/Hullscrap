extends RefCounted
## Who built a station (data/station_races.json): the races of a station, the race of each section, and what a race's body lets a section be.
## Pure logic. A race changes the skin of a section, never its footprint, doors, lanes or containers (station_gen.gd builds those without it).

const Content = preload("res://scripts/data/content.gd")
const Traits = preload("res://scripts/crew/traits.gd")
const Regions = preload("res://scripts/space/regions.gd")

const PATH := "res://data/station_races.json"
const STYLES_PATH := "res://data/ship_styles.json"

static var _cfg := {}
static var _traits := {}
static var _skins := {}
static var _palettes := {}
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


## The skin of a race: its floor, wall and lamp colours are the palette of its ships (data/ship_styles.json `style.palette`, the packs' too), so a race's ships
## and stations share them; the glyph and the style are this file's.
static func skin(race: String) -> Dictionary:
	var id := race if config()["races"].has(race) else "human"
	if not _skins.has(id):
		var sk: Dictionary = config()["races"][id]["skin"].duplicate()
		var pal: Dictionary = palette(id)
		for k in ["floor", "wall", "lamp"]:
			if pal.has(k):
				sk[k] = pal[k]
		_skins[id] = sk
	return _skins[id]


## The ship palette of race `id` ({} for none): data/ship_styles.json and every pack's ship_styles.json (a race already read is kept).
static func palette(id: String) -> Dictionary:
	if _palettes.is_empty():
		var files: Array = [STYLES_PATH]
		for p in Content.packs():
			files.append(p["dir"] + "/ship_styles.json")
		for path in files:
			var more = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			if more is Dictionary and more.get("races") is Dictionary:
				for rid in more["races"]:
					var pal = more["races"][rid].get("style", {}).get("palette")
					if pal is Dictionary and not _palettes.has(rid):
						_palettes[rid] = pal
	return _palettes.get(id, {})


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
