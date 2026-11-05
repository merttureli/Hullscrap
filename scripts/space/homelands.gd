extends RefCounted
## Homelands: the capital of every race and the wonders of the ten major ones (data/homelands.json, docs/CONTENT.md section 23). Pure logic, no nodes.
## - A capital is a region place with `capital: true`; its race is the region's home_species. capital_of() / capital_at() find it, menu() leans its dock
##   menu to the race (the race trader and the race recruiter), station_opts() says how its station is built (station_gen.gd) and line() is the arrival line.
## - A wonder is a one-off POI of type `wonder` in the sector of the capital node (sector.gd): wonder_of() reads it, event() is the anomaly event it runs.

const Content = preload("res://scripts/data/content.gd")
const Regions = preload("res://scripts/space/regions.gd")

const PATH := "res://data/homelands.json"

static var _cfg := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("capital") is Dictionary, "bad homelands data: " + PATH)
		_cfg = data
	return _cfg


## Every capital: [{region, place, name, race}] in region order, from the regions' places with `capital: true`.
static func capitals() -> Array:
	var out := []
	for r in Regions.all():
		for p in r.get("places", []):
			if p is Dictionary and bool(p.get("capital", false)) and str(r.get("home_species", "")) != "":
				out.append({"region": str(r["id"]), "place": str(p["id"]), "name": str(p["name"]), "race": str(r["home_species"])})
	return out


## The capital that is place `place_id` ({} for a place that is none).
static func capital_of(place_id: String) -> Dictionary:
	for c in capitals():
		if c["place"] == place_id:
			return c
	return {}


## The capital of region `region_id` ({} for none).
static func capital_in(region_id: String) -> Dictionary:
	for c in capitals():
		if c["region"] == region_id:
			return c
	return {}


## The species name of `race` ("Kett").
static func race_name(race: String) -> String:
	var sp := Content.entry("species", race)
	return str(sp.get("name", race.capitalize()))


## The arrival log line of capital `cap`.
static func line(cap: Dictionary) -> String:
	return str(config()["capital"]["line"]) % [cap["name"], race_name(str(cap["race"]))]


## The options a capital's station is built with (station_gen.gd): its race, operational and friendly, and the capital size class.
static func station_opts(cap: Dictionary) -> Dictionary:
	return {"capital": str(cap["race"]), "state": "operational", "mood": "friendly"}


## The house line of `race` (id -> price), {} for none.
static func own(race: String) -> Dictionary:
	return config()["capitals"].get(race, {}).get("own", {})


## The dock menu of place `place_id` as the race trader and the race recruiter of its capital: `menu` itself for any other place. The house line is on the
## shelf at the capital's price, and the region's other stock is cut to as many items as the house line has (the shelf's first), so at least half of it is
## the race's. The recruit table gives the race `capital.recruit` of its weight.
static func menu(place_id: String, menu: Dictionary) -> Dictionary:
	var cap := capital_of(place_id)
	if cap.is_empty() or menu.is_empty():
		return menu
	var house := own(str(cap["race"]))
	if house.is_empty():
		return menu
	var cc: Dictionary = config()["capital"]
	var out := menu.duplicate(true)
	var stock: Dictionary = out.get("stock", {})
	var shelf := {}
	var others := 0
	for id in stock:
		if not house.has(id) and others < house.size():
			shelf[id] = stock[id]
			others += 1
	for id in house:
		shelf[id] = maxi(5, roundi(float(house[id]) * float(cc["price"]) / 5.0) * 5)
	out["stock"] = shelf
	if not out["services"].has("stock"):
		out["services"].append("stock")
	if not out["services"].has("recruit"):
		out["services"].append("recruit")
	var rec := {}
	var total := 0.0
	var old: Dictionary = out.get("recruit", {})
	for k in old:
		if k != str(cap["race"]):
			total += float(old[k])
	var share := float(cc["recruit"])
	rec[str(cap["race"])] = maxf(total * share / (1.0 - share), 1.0) if total > 0.0 else 1.0
	for k in old:
		if k != str(cap["race"]):
			rec[k] = old[k]
	out["recruit"] = rec
	return out


## The share of the shelf of `menu` that is the race's house line (0 to 1).
static func own_share(race: String, menu: Dictionary) -> float:
	var stock: Dictionary = menu.get("stock", {})
	if stock.is_empty():
		return 0.0
	var house := own(race)
	var n := 0
	for id in stock:
		if house.has(id):
			n += 1
	return float(n) / float(stock.size())


## The wonder of race `race` ({} for none), the entry of data/homelands.json `wonders` with `race` added.
static func wonder_of(race: String) -> Dictionary:
	var w: Dictionary = config()["wonders"].get(race, {})
	if w.is_empty():
		return {}
	var out := w.duplicate(true)
	out["race"] = race
	return out


## The wonder that sits in region `region_id` ({} for none): its home race's.
static func wonder_in(region_id: String) -> Dictionary:
	var cap := capital_in(region_id)
	return {} if cap.is_empty() else wonder_of(str(cap["race"]))


## The races that have a wonder, sorted.
static func wonder_races() -> Array:
	var ids: Array = config()["wonders"].keys()
	ids.sort()
	return ids
