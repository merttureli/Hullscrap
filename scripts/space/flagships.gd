extends RefCounted
## The race flagships (data/flagships.json, docs/CONTENT.md section 25): one named, hand-made boss ship for each of the ten major races, sailing in its
## homeland. A flagship is a design file (data/packs/flagships_1/ships/flagship_<race>.json, drawn with tests/tool_flagships.gd) and an entry of data/flagships.json.
## - attach() puts the flagship's beacon into ONE sector of the homeland's map (a POI of type `flagship`, sectors.json), only from the entry's `stage`
##   on, so it is met at most once in a run (a run crosses a region once). It never touches the exit and never blocks it: the player may fly past.
## - event() is the page the beacon opens: the warning, the hail, and the choice to engage or to stay clear. Winning (or sparing, or capturing)
##   it sets flag_of(race), pays the unique trophy part, credits and scrap, and leaves a log. Losing is any lost fight.
## - card_of() is what the contact card (foe_pic.gd) says about a flagship's design: the boss tag, the captain and one line.
## No nodes, no drawing. `c` below is the campaign (not preloaded here, to avoid a cycle).

const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/flagships.json"
const DESIGN := "res://data/packs/flagships_1/ships/flagship_%s.json"
const ENTRY_KEYS: Array[String] = ["region", "name", "captain", "design", "stage", "poi_name", "warning", "hail", "card", "codex", "gimmick", "role", "reward", "log", "lines"]
const REWARD_KEYS: Array[String] = ["part", "credits", "scrap"]
const LINE_KINDS: Array[String] = ["title", "hail", "surrender", "flee", "refuse"]

static var _cfg := {}


## data/flagships.json, read once.
static func config() -> Dictionary:
	if _cfg.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(data is Dictionary and data.get("flagships") is Dictionary, "bad flagship data: " + PATH)
		_cfg = data
	return _cfg


## The races that have a flagship, sorted.
static func races() -> Array:
	var out: Array = config()["flagships"].keys()
	out.sort()
	return out


## The entry of `race` ({} for a race with none).
static func entry(race: String) -> Dictionary:
	return config()["flagships"].get(race, {})


## The flag that says the flagship of `race` has been beaten (won, captured or spared).
static func flag_of(race: String) -> String:
	return "flagship_%s_beaten" % race


## The design file (a res:// path) of the flagship of `race`.
static func design_of(race: String) -> String:
	return DESIGN % race


## The race whose flagship has design `path` ("" for any other design).
static func race_of_design(path: String) -> String:
	for race in config()["flagships"]:
		if path == design_of(str(race)):
			return str(race)
	return ""


## The race that holds region `region` (its data) as its homeland and has a flagship, else "".
static func race_of_region(region: Dictionary) -> String:
	var home := str(region.get("home_species", ""))
	return home if home != "" and config()["flagships"].has(home) else ""


static func _fnv(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xFFFFFFFF
	return h


## The node of `map` (a Drift) that holds the flagship of a region run with seed `region_seed`: a random node (no fixed place, not the start, not the exit),
## picked by the seed alone. "" when the map has none.
static func node_for(region_seed: int, map) -> String:
	var ids: Array = map.ids().filter(func(id): return map.node(str(id)).get("place", "") == "" and str(map.node(str(id)).get("type", "")) != "exit" and str(id) != map.start_id())
	if ids.is_empty():
		return ""
	ids.sort()
	return str(ids[(_fnv("flagship") ^ (region_seed & 0x7FFFFFFF)) % ids.size()])


## The flagship POI of `race` (the sector adds it, Sector.add_boss).
static func poi_of(race: String) -> Dictionary:
	var e := entry(race)
	return {"id": "flagship", "type": "flagship", "name": str(e["poi_name"]), "pos": Vector2.ZERO, "visibility": "beacon", "event_type": "anomaly", "state": "new",
		"enemy": "", "main": false, "boss": race, "flag": flag_of(race)}


## Put the flagship into `sector` (a Sector just made for a node of `map` in a region with data `region_data` at run stage `stage`) when it belongs there.
static func attach(sector, region_data: Dictionary, stage: int, map, region_seed: int) -> void:
	var race := race_of_region(region_data)
	if race == "" or stage < int(entry(race)["stage"]) or sector.node_id != node_for(region_seed, map):
		return
	sector.add_boss(poi_of(race))


## The beacon's page for POI `poi` (a `boss` POI): the warning and the hail, then engage or stay clear. Engaging fights the flagship's design; a win
## (won, captured or spared) sets the beaten flag and pays the trophy, credits and scrap, and the log.
static func event(c, _ship, poi: Dictionary) -> Dictionary:
	var race := str(poi.get("boss", ""))
	var e := entry(race)
	if e.is_empty():
		return {}
	var flag := flag_of(race)
	var reward: Dictionary = e["reward"]
	var items := {"credits": int(reward["credits"]), "scrap": int(reward["scrap"]), str(reward["part"]): 1}
	var win := {"flag": [flag], "items": items, "log": [str(e["log"])]}
	var text := "%s\n\n%s" % [str(e["warning"]), str(e["hail"])]
	var choices := [
		{"text": "Engage the %s." % str(e["name"]), "outcomes": [{"weight": 1, "text": "You raise shields and turn to meet her.", "effects": {"fight": design_of(race)},
			"after_win": {"text": "The %s is finished. %s" % [str(e["name"]), str(e["codex"])], "effects": win}}]},
		{"text": "Stay clear.", "outcomes": [{"weight": 1, "text": "You turn away from the beacon. The %s does not follow, and will still be here." % str(e["name"]), "effects": {}}]}]
	return {"id": "flagship_" + race, "type": "flagship", "once": false, "title": str(e["name"]), "text": text, "choices": choices}


## What the contact card says about the ship of design `design` when it is a flagship: {title ("FLAGSHIP"), name, captain, line}; {} for any other design.
static func card_of(design: String) -> Dictionary:
	var race := race_of_design(design)
	if race == "":
		return {}
	var e := entry(race)
	return {"title": "FLAGSHIP", "name": str(e["name"]), "captain": str(e["captain"]), "line": str(e["card"]), "race": race}


# --- the validator -----------------------------------------------------------------------------------------------

## Every problem with data/flagships.json: a missing race, unknown keys, a region that is not that race's homeland, bad stages, texts, parts and lines.
static func problems() -> Array[String]:
	var out: Array[String] = []
	var cfg := config()
	var list: Dictionary = cfg["flagships"]
	var homes := {}
	for r in Content.regions():
		if str(r.get("home_species", "")) != "":
			homes[str(r["home_species"])] = r
	for race in list:
		var e = list[race]
		var at := "flagships.json: '%s'" % race
		if not e is Dictionary:
			out.append(at + " must be an object")
			continue
		for k in e:
			if not ENTRY_KEYS.has(k):
				out.append("%s: unknown key '%s'" % [at, k])
		for k in ["region", "name", "captain", "design", "poi_name", "warning", "hail", "card", "codex", "gimmick", "role"]:
			if not (e.get(k) is String and e[k] != ""):
				out.append("%s: %s must be a non-empty text" % [at, k])
		if not homes.has(race) or str(homes[race].get("id", "")) != str(e.get("region", "")):
			out.append("%s: region '%s' is not the homeland of %s" % [at, str(e.get("region", "")), race])
		elif not (e.get("stage") is float or e.get("stage") is int) or int(e["stage"]) < int(homes[race]["stages"][0]) or int(e["stage"]) > int(homes[race]["stages"][1]):
			out.append("%s: stage must be inside the region's stages %s" % [at, str(homes[race]["stages"])])
		if str(e.get("design", "")) != "flagship_" + str(race) or not FileAccess.file_exists(design_of(str(race))):
			out.append("%s: design must be 'flagship_%s' and %s must exist" % [at, race, design_of(str(race))])
		var reward = e.get("reward")
		if not reward is Dictionary:
			out.append(at + ": reward must be an object")
		else:
			for k in reward:
				if not REWARD_KEYS.has(k):
					out.append("%s: reward: unknown key '%s'" % [at, k])
			if not (reward.get("part") is String and Content.ids("components").has(reward["part"])):
				out.append("%s: reward.part must be a component of components.json or a pack" % at)
			for k in ["credits", "scrap"]:
				if not ((reward.get(k) is float or reward.get(k) is int) and reward[k] >= 0):
					out.append("%s: reward.%s must be a number, 0 or more" % [at, k])
		if not (e.get("log") is String and e["log"] != ""):
			out.append(at + ": log must be the id of a log (data/packs/flagships_1/logs.json)")
		var lines = e.get("lines")
		if not lines is Dictionary:
			out.append(at + ": lines must be an object")
		else:
			for k in LINE_KINDS:
				if not (lines.get(k) is Array and not lines[k].is_empty() and lines[k].all(func(l): return l is String and l != "")) and k != "title":
					out.append("%s: lines.%s must be a list of texts" % [at, k])
	return out
