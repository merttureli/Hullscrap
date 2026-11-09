extends RefCounted
## The endings (docs/CONTENT.md section 13): the catalogue (data/endings.json and the endings.json of every pack,
## through the content loader), the score of a finished run and the report the ending screen shows. An ending is
## {id, title, epilogue, base_score, par_jumps?}; the event effect `ending` ends the run as a win with one (events.gd).
## The score is the ending's base, plus credits / 10, crew alive x 50, points of interest done x 10, landmarks x 100,
## minus the jumps over par; the numbers are the `score` object of data/endings.json. No nodes, no drawing.

const Content = preload("res://scripts/data/content.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Regions = preload("res://scripts/space/regions.gd")

const KEYS: Array[String] = ["id", "title", "epilogue", "base_score", "par_jumps", "coda", "override", "reason"]
const DEFAULT_SCORE := {"credits_per_point": 10, "per_crew": 50, "per_poi": 10, "per_landmark": 100, "per_jump_over": 1, "par_jumps": 40}


static func all() -> Array:
	return Content.list("endings")


static func has(id: String) -> bool:
	return Content.has("endings", id)


## The entry of `id`, {} when there is none.
static func entry(id: String) -> Dictionary:
	return Content.entry("endings", id)


## The title of ending `id`; an unknown id reads "The End".
static func title_of(id: String) -> String:
	return str(entry(id).get("title", "The End"))


## The score numbers: data/endings.json `score` over DEFAULT_SCORE.
static func score_config() -> Dictionary:
	var out := DEFAULT_SCORE.duplicate()
	var d = Content.read(Content.root + "/endings.json")
	if d is Dictionary and d.get("score") is Dictionary:
		for k in d["score"]:
			if out.has(k) and (d["score"][k] is float or d["score"][k] is int):
				out[k] = d["score"][k]
	return out


## The jumps a run to ending `id` should take: its own par_jumps, else the common one.
static func par_of(id: String) -> int:
	var cfg := score_config()
	var e := entry(id)
	return int(e["par_jumps"]) if e.get("par_jumps") is float or e.get("par_jumps") is int else int(cfg["par_jumps"])


# --- the run ------------------------------------------------------------------------------------------------

## The names of the crew alive on `ship` (above 0 hp).
static func crew_alive(ship) -> Array:
	var out := []
	if ship != null:
		for m in ship.crew:
			if m.hp > 0.0 and not m.is_drone():  # (a repair drone is no crew)
				out.append(str(m.name))
	return out


## Points of interest the run finished: the generated POIs of every sector visited that are done.
static func pois_done(c) -> int:
	var n := 0
	for id in c.sectors:
		for p in c.sectors[id].pois:
			n += int(p["state"] == Sector.DONE)
	return n


## The names of the regions the run crossed, in order (the campaign's route, data/regions).
static func regions_visited(c) -> Array:
	return c.route.map(func(id): return str(Regions.get_region(str(id)).get("name", id)))


## How a run to `ending_id` adds up: {total, rows: [{label, detail, points}]}. The total is never below 0.
static func score(c, ship, ending_id: String) -> Dictionary:
	var cfg := score_config()
	var credits: int = ship.inventory.count("credits") if ship != null else 0
	var alive := crew_alive(ship).size()
	var pois := pois_done(c)
	var marks: int = c.landmarks.size()
	var par := par_of(ending_id)
	var over := maxi(c.jumps - par, 0)
	var rows := [
		{"label": title_of(ending_id), "detail": "ending", "points": int(entry(ending_id).get("base_score", 0))},
		{"label": "Credits", "detail": "%d / %d" % [credits, int(cfg["credits_per_point"])], "points": credits / maxi(int(cfg["credits_per_point"]), 1)},
		{"label": "Crew alive", "detail": "%d x %d" % [alive, int(cfg["per_crew"])], "points": alive * int(cfg["per_crew"])},
		{"label": "POIs done", "detail": "%d x %d" % [pois, int(cfg["per_poi"])], "points": pois * int(cfg["per_poi"])},
		{"label": "Landmarks", "detail": "%d x %d" % [marks, int(cfg["per_landmark"])], "points": marks * int(cfg["per_landmark"])},
		{"label": "Jumps over par", "detail": "%d over %d" % [over, par], "points": -over * int(cfg["per_jump_over"])},
	]
	var total := 0
	for r in rows:
		total += int(r["points"])
	return {"total": maxi(total, 0), "rows": rows}


## The epilogue of ending `e` with its `coda` lines after it: each {text, flag?} whose flag the run holds; "{crew}" in a text is the
## names of the crew alive (a line that names the crew is left out when nobody is).
static func epilogue_of(e: Dictionary, c, ship) -> String:
	var out := str(e.get("epilogue", ""))
	var names := crew_alive(ship)
	for x in e.get("coda", []):
		if x.has("flag") and not c.flags.has(str(x["flag"])):
			continue
		var text := str(x.get("text", ""))
		if text.contains("{crew}"):
			if names.is_empty():
				continue
			var list: String = names[0] if names.size() == 1 else ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]
			text = text.replace("{crew}", list)
		out += " " + text
	return out


## What the ending screen shows about a finished run: {ending {id, title, epilogue}, ship (its name), jumps, par, fights, credits,
## pois_done, crew (names alive), regions (labels), landmarks [{id, title, jumps}], log [{jumps, kind, text}] (the run log, in
## order: landmarks, unlocks, the ending), unlocks [{id, name, kind}] (earned in this run), score (score())}.
static func report(c, ship, ending_id: String) -> Dictionary:
	var e := entry(ending_id)
	var marks := []
	var log := []
	for x in c.chronicle:
		var line := {"jumps": int(x.get("jumps", 0)), "kind": str(x.get("kind", "")), "text": str(x.get("text", ""))}
		match line["kind"]:
			"landmark":
				marks.append({"id": str(x.get("id", "")), "title": line["text"], "jumps": line["jumps"]})
			"unlock":
				line["text"] = Unlocks.name_of(str(x.get("id", "")))
			"ending":
				line["text"] = title_of(str(x.get("id", "")))
		log.append(line)
	var earned := []
	for id in c.unlocks_earned:
		earned.append({"id": str(id), "name": Unlocks.name_of(str(id)), "kind": str(Unlocks.entry(str(id)).get("kind", ""))})
	return {"ending": {"id": ending_id, "title": title_of(ending_id), "epilogue": epilogue_of(e, c, ship)},
		"ship": ship.name if ship != null else "?", "jumps": c.jumps, "par": par_of(ending_id), "fights": c.fights_won,
		"credits": ship.inventory.count("credits") if ship != null else 0, "pois_done": pois_done(c), "crew": crew_alive(ship),
		"regions": regions_visited(c), "landmarks": marks, "log": log, "unlocks": earned, "score": score(c, ship, ending_id)}


## The design `ship` goes into the hall of ships as (profile.gd): its save format plus the crew alive, so it can be
## copied to data/ships as a premade.
static func design_of(ship) -> Dictionary:
	var d: Dictionary = ship.to_dict()
	var crew := []
	for m in ship.crew:
		if m.hp > 0.0 and not m.is_drone():  # (a new run brings its own drone: RunStart.add_drone)
			crew.append({"name": str(m.name), "species": str(m.species)})
	d["crew"] = crew
	for k in ["crew_state", "dead_crew", "crew_plan"]:  # a design is a start, not a saved run: the crew come from its list
		d.erase(k)
	return d


# --- validation ---------------------------------------------------------------------------------------------

## Every problem in the catalogue, one message each naming the file and the ending. Empty when it is sound.
static func validate() -> Array[String]:
	var out: Array[String] = []
	for e in all():
		var id := str(e["id"])
		var file := Content.file_of("endings", id)
		var bad := func(msg: String) -> void: out.append("%s: ending '%s': %s" % [file if file != "" else "(inline data)", id, msg])
		for k in e:
			if not KEYS.has(k):
				bad.call("unknown key '%s' (known: %s)" % [k, ", ".join(KEYS)])
		for k in ["title", "epilogue"]:
			if not (e.get(k) is String and e[k] != ""):
				bad.call("%s must be a non-empty string" % k)
		for x in (e.get("coda", []) if e.get("coda") is Array else []):
			if not (x is Dictionary and x.get("text") is String and x["text"] != "" and (not x.has("flag") or x["flag"] is String)):
				bad.call("coda must be a list of {text, flag?}")
		if e.has("coda") and not e["coda"] is Array:
			bad.call("coda must be a list")
		if not (e.get("base_score") is float or e.get("base_score") is int):
			bad.call("base_score must be a number")
		if e.has("par_jumps") and not (e["par_jumps"] is float or e["par_jumps"] is int):
			bad.call("par_jumps must be a number")
	return out
