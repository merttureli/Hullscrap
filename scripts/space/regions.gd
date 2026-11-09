extends RefCounted
## The regions of a run (docs/CONTENT.md section 15): a run crosses `stages` (8) regions, each a Drift map of 16 to 20
## places, and at a region's exit beacon you choose the next one from 2 or 3 on offer. Pure data and logic, no nodes.
## - Region data: data/regions/<id>.json and the packs' regions/*.json (Content.regions()); the fields are in FIELDS and
##   problems() checks them. The run's rules are data/drift.json `run`.
## - The graph: stage 1 is always `run.start` (Clan space). At the exit of stage s < stages, offers() rolls 2 or 3 regions
##   valid for stage s + 1 (their `stages` band holds it), by `weight` x the `run.rarity` factor of their rarity, never one
##   the run has been to. The exit of the last stage leads to `run.ending`, the ending region (for now the Gate
##   approaches), which has no exit of its own. Everything is rolled from the run seed and the stage, so the same seed
##   and the same choices give the same offers.
## - A region's map: make_map() rolls drift.gd's map from the region seed with data/drift.json `map` and `node_weights`
##   as defaults (a region may override any `map` key and the weights), the region's `places`, an arrival node at the
##   left edge when no place is the start (`run.entry`) and the exit beacon at the far side (`run.exit`).
## - Stations: station() is the menu of a station place: its data/drift.json `stations` entry, else one made of its
##   region's faction, `stock` and `recruit`; a region's `stock` is laid over a drift.json menu and its `recruit` replaces
##   that menu's when given.

const Content = preload("res://scripts/data/content.gd")
const Drift = preload("res://scripts/space/drift.gd")

const DRIFT_PATH := "res://data/drift.json"
const SECTORS_PATH := "res://data/sectors.json"
const DEBRIS_PATH := "res://data/debris.json"
const FACTIONS_PATH := "res://data/factions.json"
const NEBULA_PATH := "res://art/space/nebula_%s.png"
const RARITIES: Array[String] = ["common", "uncommon", "rare", "very_rare", "legendary"]
const HAZARDS: Array[String] = ["ion_storm", "gas_cloud", "debris_surge", "radiation", "star_heat"]
const AMBIENT_KINDS: Array[String] = ["trader", "patrol", "pirate"]
const SERVICES: Array[String] = ["sell", "stock", "repair", "recruit"]  ## a region station's services when it has no drift.json menu (fuel is added where data/drift.json fuel.stations lists the place)
const FIELDS: Array[String] = ["id", "name", "home_species", "faction", "stages", "weight", "rarity", "danger", "palette", "map", "node_weights",
	"places", "debris", "pois", "ambient", "stock", "recruit", "enemies", "race_share", "hazards", "events", "blurb", "override", "reason", "_doc"]
const REQUIRED: Array[String] = ["id", "name", "home_species", "faction", "stages", "weight", "rarity", "danger", "palette", "ambient", "enemies", "events", "blurb"]
const PLACE_KEYS: Array[String] = ["id", "name", "type", "faction", "pos", "jitter", "hidden_until", "start", "beacon", "capital"]
const BARGE := "gantry_barge"  ## Ma's barge: run.barge in data/drift.json, a station in every region
const FIXED_TYPES: Array[String] = ["station", "gate", "exit"]  ## node types only fixed places have (never rolled by weight)

static var _key := ""
static var _places := {}  # place id -> {region (id), place (the entry)}


## Every region, core first, then the packs (copies).
static func all() -> Array:
	return Content.regions()


static func has(id: String) -> bool:
	return Content.has("regions", id)


## A copy of region `id`, {} when there is none.
static func get_region(id: String) -> Dictionary:
	return Content.entry("regions", id)


## data/drift.json `run` of the campaign config `cfg`.
static func run_of(cfg: Dictionary) -> Dictionary:
	return cfg.get("run", {})


## The stages of a run (8).
static func stages(cfg: Dictionary) -> int:
	return int(run_of(cfg).get("stages", 8))


## May region `r` be a stage-`stage` region (its `stages` band holds it)?
static func valid_for(r: Dictionary, stage: int) -> bool:
	var band = r.get("stages", [])
	return band is Array and band.size() == 2 and stage >= int(band[0]) and stage <= int(band[1])


## The seed of the region of stage `stage` in the run of seed `run_seed` (FNV-1a of "stage:id", mixed with the seed).
static func seed_for(run_seed: int, stage: int, id: String) -> int:
	var h := 2166136261
	for b in ("%d:%s" % [stage, id]).to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return (run_seed * 1000003) ^ h


## The regions on offer at the exit beacon of stage `stage` (ids, in the order rolled): for stage < stages, 2 or 3
## (`run.offers`) of the regions valid for stage + 1 that `route` (the regions of the run so far) does not hold, picked
## by weight x rarity factor; for the last stage, the ending region alone; past it, none.
static func offers(run_seed: int, stage: int, route: Array, cfg: Dictionary) -> Array:
	var run := run_of(cfg)
	var last := stages(cfg)
	if stage > last:
		return []
	if stage == last:
		return [str(run["ending"])]
	var pool := {}
	for r in all():
		var w := float(r.get("weight", 0.0)) * float(run["rarity"].get(str(r.get("rarity", "")), 0.0))
		if w > 0.0 and not route.has(r["id"]) and valid_for(r, stage + 1):
			pool[str(r["id"])] = w
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(run_seed, stage + 1, "offers")
	var span: Array = run["offers"]
	var count := rng.randi_range(int(span[0]), int(span[1]))
	var out := []
	while out.size() < count and not pool.is_empty():
		var pick := _pick(rng, pool)
		out.append(pick)
		pool.erase(pick)
	return out


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	var total := 0.0
	for k in keys:
		total += float(weights[k])
	var x := rng.randf() * total
	for k in keys:
		x -= float(weights[k])
		if x < 0.0:
			return str(k)
	return str(keys[-1])


## The drift.gd config of region `r`'s map: `cfg` (data/drift.json) with the region's `map` keys and `node_weights` laid
## over, and its places: the region's own, the arrival node (`run.entry`) when none is the start, Ma's barge (`run.barge`, in every
## region) and the exit beacon
## (`run.exit`) unless `final` (the ending region has no way on).
static func map_cfg(r: Dictionary, cfg: Dictionary, final := false) -> Dictionary:
	var out := cfg.duplicate(true)
	var over: Dictionary = r.get("map", {})
	for k in over:
		out["map"][k] = over[k]
	if r.get("node_weights") is Dictionary and not r["node_weights"].is_empty():
		out["node_weights"] = r["node_weights"].duplicate()
	var places: Array = r.get("places", []).duplicate(true)
	if not places.any(func(p): return bool(p.get("start", false))):
		var entry: Dictionary = run_of(cfg)["entry"].duplicate(true)
		entry["start"] = true
		places.push_front(entry)
	if run_of(cfg).has("barge"):
		places.append(run_of(cfg)["barge"].duplicate(true))  # Ma's barge: one in every region, toward the exit
	if not final:
		places.append(run_of(cfg)["exit"].duplicate(true))
	out["places"] = places
	return out


## Region `r`'s map, rolled from `region_seed`.
static func make_map(r: Dictionary, cfg: Dictionary, region_seed: int, final := false):
	var rng := RandomNumberGenerator.new()
	rng.seed = region_seed
	return Drift.generate(rng, map_cfg(r, cfg, final))


## The danger of region `r` as 1 to 5 skulls (its `danger`, the enemy budget factor of docs/CONTENT.md section 14:
## 1.0 is one skull, each 0.12 more adds one).
static func skulls(r: Dictionary) -> int:
	return clampi(1 + roundi((float(r.get("danger", 1.0)) - 1.0) / 0.12), 1, 5)


# --- places and stations ------------------------------------------------------------------------------------

static func _index() -> Dictionary:
	var key := Content.root + "|" + Content.packs_root
	if key != _key:
		_key = key
		_places = {}
		for r in all():
			for p in r.get("places", []):
				if p is Dictionary and p.get("id") is String:
					_places[p["id"]] = {"region": str(r["id"]), "place": p}
	return _places


## Every fixed place of every region: place id -> the id of its region.
static func place_ids() -> Dictionary:
	var out := {}
	var idx := _index()
	for id in idx:
		out[id] = idx[id]["region"]
	return out


## The station menu of place `place` ({faction, services, stock (id -> price), recruit (species -> weight)}), {} when it
## is no station. See the header for how a region's stock and recruits meet a data/drift.json menu.
static func station(place: String, cfg: Dictionary) -> Dictionary:
	var base: Dictionary = cfg.get("stations", {}).get(place, {})
	var at: Dictionary = _index().get(place, {})
	if at.is_empty():
		return _with_fuel(base, place, cfg)
	var p: Dictionary = at["place"]
	if str(p.get("type", "")) != "station":
		return {}
	var r := get_region(str(at["region"]))
	var out: Dictionary = base.duplicate(true) if not base.is_empty() else {"faction": str(p.get("faction", r.get("faction", ""))),
		"services": SERVICES.duplicate(), "stock": {}, "recruit": {}}
	var stock: Dictionary = r.get("stock", {})
	for id in stock:
		out["stock"][id] = stock[id]
	if r.get("recruit") is Dictionary and not r["recruit"].is_empty():
		out["recruit"] = r["recruit"].duplicate()
	return _with_fuel(out, place, cfg)


## `menu` with the fuel service when `place` is one of data/drift.json fuel.stations (about 40% of the stations sell fuel; {} stays {}).
static func _with_fuel(menu: Dictionary, place: String, cfg: Dictionary) -> Dictionary:
	if menu.is_empty() or not (cfg.get("fuel", {}).get("stations", []) as Array).has(place):
		return menu
	var out := menu.duplicate(true)
	if not out["services"].has("fuel"):
		out["services"].insert(0, "fuel")
	return out


# --- the validator -----------------------------------------------------------------------------------------------

static func _json(path: String) -> Dictionary:
	var d = Content.read(path)
	return d if d is Dictionary else {}


static func _is_num(v) -> bool:
	return v is float or v is int


static func _is_int(v) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _snake(s) -> bool:
	if not s is String:
		return false
	var re := RegEx.new()
	re.compile("^[a-z0-9]+(_[a-z0-9]+)*$")
	return re.search(s) != null


## What the rules check against: drift.json (map keys, node types, the run), the POI and debris types, factions, species
## and cargo ids.
static func known(cfg: Dictionary = {}) -> Dictionary:
	var drift: Dictionary = cfg if not cfg.is_empty() else _json(DRIFT_PATH)
	var cargo := {}
	for kind in ["components", "items", "materials"]:
		for id in Content.ids(kind):
			cargo[id] = true
	var debris := {}
	for t in _json(DEBRIS_PATH).get("types", []):
		debris[str(t["id"])] = true
	var factions := {}
	for f in _json(FACTIONS_PATH).get("factions", []):
		factions[str(f["id"])] = true
	var species := {}
	for id in Content.ids("species"):
		species[id] = true
	return {"drift": drift, "pois": _json(SECTORS_PATH).get("poi_types", {}), "debris": debris, "factions": factions, "species": species, "cargo": cargo}


## Every problem with the regions `list` (default: all of them), each naming the file and the region: unknown keys,
## missing fields, ids that do not exist, bad numbers, a place id used twice, and a run that could run out of choices.
static func problems(list = null, k: Dictionary = {}) -> Array[String]:
	var regions: Array = list if list is Array else all()
	var kn := k if not k.is_empty() else known()
	var out: Array[String] = []
	var seen_places := {}
	for r in regions:
		out.append_array(_region_problems(r, kn, seen_places))
	out.append_array(_graph_problems(regions, kn["drift"]))
	return out


static func _region_problems(r: Dictionary, kn: Dictionary, seen_places: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := str(r.get("id", "?"))
	var file := Content.file_of("regions", id)
	var at := "%s: region '%s'" % [file if file != "" else "(inline data)", id]
	var bad := func(msg: String) -> void: out.append("%s: %s" % [at, msg])
	var drift: Dictionary = kn["drift"]
	for key in r:
		if not FIELDS.has(key):
			bad.call("unknown key '%s' (known: %s)" % [key, ", ".join(FIELDS)])
	for key in REQUIRED:
		if not r.has(key):
			bad.call("missing field '%s'" % key)
	if not _snake(id):
		bad.call("the id must be snake_case")
	if file != "" and file.get_file().get_basename() != id:
		bad.call("the file must be named after the id (%s.json)" % id)
	for key in ["name", "blurb"]:
		if r.has(key) and not (r[key] is String and r[key] != ""):
			bad.call("%s must be a non-empty text" % key)
	var home = r.get("home_species", "")
	if not (home is String and (home == "" or kn["species"].has(home))):
		bad.call("home_species '%s' is not a species (\"\" for none)" % home)
	var fac = r.get("faction", "")
	if not (fac is String and (fac == "" or kn["factions"].has(fac))):
		bad.call("faction '%s' is not in factions.json (\"\" for none)" % fac)
	var band = r.get("stages")
	var last := int(drift.get("run", {}).get("stages", 8))
	if r.has("stages") and not (band is Array and band.size() == 2 and _is_int(band[0]) and _is_int(band[1]) and int(band[0]) >= 1 and int(band[0]) <= int(band[1]) and int(band[1]) <= last):
		bad.call("stages must be [first, last] within 1..%d" % last)
	if r.has("weight") and not (_is_num(r["weight"]) and r["weight"] > 0):
		bad.call("weight must be a number above 0")
	if r.has("rarity") and not RARITIES.has(r["rarity"]):
		bad.call("rarity '%s' is not one of %s" % [r["rarity"], ", ".join(RARITIES)])
	if r.has("danger") and not (_is_num(r["danger"]) and r["danger"] > 0):
		bad.call("danger must be a number above 0 (the enemy budget factor)")
	var pal = r.get("palette")
	if r.has("palette"):
		if not (pal is Dictionary and pal.get("tint") is String and Color.html_is_valid(pal["tint"]) and pal.get("nebula") is String):
			bad.call("palette must be {tint: \"#rrggbb\", nebula: id}")
		elif not ResourceLoader.exists(NEBULA_PATH % pal["nebula"]):
			bad.call("palette nebula '%s' has no art (%s)" % [pal["nebula"], NEBULA_PATH % pal["nebula"]])
	var m = r.get("map", {})
	if not m is Dictionary:
		bad.call("map must be an object of data/drift.json map keys")
	else:
		for key in m:
			if not drift.get("map", {}).has(key):
				bad.call("map key '%s' is not one of data/drift.json map" % key)
	var types: Dictionary = drift.get("types", {})
	_weights(r, "node_weights", func(t): return types.has(t) and not FIXED_TYPES.has(t), "a node type that is rolled", bad)
	if r.get("node_weights") is Dictionary and not r["node_weights"].is_empty() and r["node_weights"].values().all(func(w): return not (_is_num(w) and w > 0)):
		bad.call("node_weights must give some type a weight above 0")
	_weights(r, "debris", func(t): return kn["debris"].has(t), "a debris type of data/debris.json", bad)
	_weights(r, "pois", func(t): return kn["pois"].has(t), "a POI type of data/sectors.json", bad)
	_weights(r, "ambient", func(t): return AMBIENT_KINDS.has(t), "trader, patrol or pirate", bad)
	_weights(r, "recruit", func(t): return kn["species"].has(t), "a species", bad)
	var stock = r.get("stock", {})
	if not stock is Dictionary:
		bad.call("stock must map an item id to a price")
	else:
		for item in stock:
			if not kn["cargo"].has(item):
				bad.call("stock: unknown item '%s'" % item)
			elif not (_is_int(stock[item]) and stock[item] > 0):
				bad.call("stock: the price of '%s' must be a whole number above 0" % item)
	if r.has("enemies") and not (r["enemies"] is String and kn["factions"].has(r["enemies"])):
		bad.call("enemies must be the id of a faction's enemy table (a faction id)")
	var hz = r.get("hazards", [])
	if not (hz is Array and hz.all(func(h): return HAZARDS.has(h))):
		bad.call("hazards must be a list of %s" % ", ".join(HAZARDS))
	if r.has("events") and not _snake(r["events"]):
		bad.call("events must be a snake_case event pool tag")
	var places = r.get("places", [])
	if not places is Array:
		bad.call("places must be a list")
		return out
	var starts := 0
	for p in places:
		if not (p is Dictionary and _snake(p.get("id")) and p.get("name") is String and p["name"] != "" and types.has(p.get("type")) and p.get("pos") is Array and p["pos"].size() == 2):
			bad.call("place %s must have an id, a name, a node type and a pos [x, y]" % str(p.get("id", "?") if p is Dictionary else p))
			continue
		for key in p:
			if not PLACE_KEYS.has(key):
				bad.call("place '%s': unknown key '%s' (known: %s)" % [p["id"], key, ", ".join(PLACE_KEYS)])
		if p["type"] == "exit":
			bad.call("place '%s': the exit beacon is added by the run (data/drift.json run.exit)" % p["id"])
		if p.has("faction") and not (p["faction"] is String and (p["faction"] == "" or kn["factions"].has(p["faction"]))):
			bad.call("place '%s': unknown faction '%s'" % [p["id"], p["faction"]])
		if seen_places.has(p["id"]):
			bad.call("place id '%s' is also used by region '%s'" % [p["id"], seen_places[p["id"]]])
		seen_places[p["id"]] = id
		starts += int(bool(p.get("start", false)))
	if starts > 1:
		bad.call("only one place may be the start")
	if str(home) != "" and not places.any(func(p): return p is Dictionary and p.get("type") == "station"):
		bad.call("a homeland needs its race station (a place of type station)")
	return out


static func _weights(r: Dictionary, key: String, ok: Callable, what: String, bad: Callable) -> void:
	if not r.has(key):
		return
	if not r[key] is Dictionary:
		bad.call("%s must map %s to a number" % [key, what])
		return
	for t in r[key]:
		if not ok.call(t):
			bad.call("%s: '%s' is not %s" % [key, t, what])
		elif not (_is_num(r[key][t]) and r[key][t] >= 0):
			bad.call("%s: the number for '%s' must be 0 or more" % [key, t])


## The run's own rules: the start region exists and is the only stage-1 region, the ending exists, and every stage
## 2..stages has enough regions that a run which took others before can still be offered the least number of choices
## (stage s needs s - 2 + offers min).
static func _graph_problems(regions: Array, drift: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var run: Dictionary = drift.get("run", {})
	if run.is_empty():
		return out
	var ids := {}
	for r in regions:
		ids[str(r.get("id", ""))] = r
	var start := str(run.get("start", ""))
	var ending := str(run.get("ending", ""))
	if not ids.has(start):
		out.append("data/drift.json run: start region '%s' does not exist" % start)
	elif not valid_for(ids[start], 1):
		out.append("data/drift.json run: start region '%s' is not valid for stage 1" % start)
	if not ids.has(ending):
		out.append("data/drift.json run: ending region '%s' does not exist" % ending)
	var least := int(run.get("offers", [2, 3])[0])
	for s in range(2, int(run.get("stages", 8)) + 1):
		var n := 0
		for r in regions:
			n += int(str(r.get("id", "")) != start and valid_for(r, s))
		if n < s - 2 + least:
			out.append("stage %d: only %d regions may appear there; a run that took others before could be offered fewer than %d" % [s, n, least])
	return out
