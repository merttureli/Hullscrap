extends RefCounted
## The events of the Drift (docs/CONTENT.md section 8): FTL-style text with choices, read from every
## data/events/*.json ({"events": [...]}) and from the events/*.json of every content pack, through the
## content loader (data/packs, scripts/data/content.gd). This script loads them, checks them (validate() names the
## file and the event in every message), picks the event of a node by weight with the campaign's
## seeded rng, filters the choices of an event (hidden, greyed or blue), rolls the outcome of a choice
## and applies its effects to the campaign and the ship. No nodes, no drawing; the event panel
## (scripts/ui/event_panel.gd) only shows what this returns.
## Rules in short:
## - An event's `type` is the node type it can happen at. A follow-up page (type `page`, weight 0, or any
##   event named by a `goto`) is never rolled at a node. `requires.node` matches a node type or a place id.
##   Type `debt` is no node: the debt clock (campaign.gd) picks those, by what their `requires` say.
##   Type `station` events are the greetings on docking: they ask for the flag at_<place> (set while docked
##   there) or for `node` a place id.
## - A `once` event is spent only when the outcome of the choice taken has non-empty effects, so a
##   "Leave" choice (no effects) does not burn a quest step.
## - A choice is hidden when its requirements are not met, greyed (with what it needs) when it only
##   lacks items or credits, and blue when it asks for a species, a trait or an installed component.
## - `items` and `credits` in a choice's requires must be held; they are paid only when `pay` is true
##   (in requires or on the choice).
## - `after_win` ({text, effects}) on an event, or on an outcome, runs after a won fight.
## - `requires.region` (a region id or a region's `events` tag, or a list of them: any one) and `stage_min` / `stage_max`
##   tie an event or a choice to the regions of the run (docs/CONTENT.md section 15, regions.gd).
## - `landmark` (true, or a title) on an event makes it a landmark (docs/CONTENT.md section 13): when a choice with
##   effects is taken (the rule of `once`) it is recorded in the profile (the first time ever) and in the run log. A landmark
##   does not end the run. The effect `unlock` (an id of data/unlocks.json, or a list) earns something for the next runs and
##   shows "Unlocked: <name>"; the effect `ending` (an id of data/endings.json) ends the run as a win: choose() and
##   apply() hand it back and the event panel opens the ending screen.
## - `fallback` (true) on an event keeps it out of every pick that has another eligible event: it is only rolled when nothing else
##   is (the repeatable filler quests of data/packs/story_1, so a quest beacon with no quest left still has something to give).
## - `c` below is the campaign (campaign.gd); it is not preloaded here, to avoid a cycle.

const Content = preload("res://scripts/data/content.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const Unlocks = preload("res://scripts/space/unlocks.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")

const DIR := "res://data/events"
const LOGS_DIR := "res://data/logs"
const NODE_TYPES: Array = ["station", "gate", "pirate", "wreck_field", "distress", "trader", "anomaly", "patrol", "asteroid_field", "empty"]
const EVENT_TYPES: Array = ["station", "gate", "pirate", "wreck_field", "distress", "trader", "anomaly", "patrol", "asteroid_field", "empty", "page", "debt", "quest", "hollow"]
const EVENT_KEYS: Array = ["id", "type", "weight", "once", "requires", "title", "text", "choices", "after_win", "landmark", "fallback"]
const EVENT_REQ_KEYS: Array = ["jumps_min", "jumps_max", "flag", "not_flag", "rep_min", "rep_max", "node", "fuel_max", "region", "stage_min", "stage_max"]
const CHOICE_KEYS: Array = ["text", "requires", "outcomes", "pay", "blue"]
const CHOICE_REQ_KEYS: Array = ["jumps_min", "jumps_max", "flag", "not_flag", "rep_min", "rep_max", "node", "fuel_max", "region", "stage_min", "stage_max", "species", "trait", "items", "pay", "component", "credits"]
const OUTCOME_KEYS: Array = ["weight", "text", "effects", "after_win"]
const AFTER_KEYS: Array = ["text", "effects"]
const EFFECT_KEYS: Array = ["items", "rep", "crew_hp", "hull", "flag", "clear_flag", "recruit", "lose_crew", "blueprint", "fight", "goto", "reveal", "debt", "log", "unlock", "ending"]
const RECRUIT_KEYS: Array = ["name", "species", "character"]
const TRAIT_LABELS := {"no_breath": "Doesn't breathe", "heat_resistant": "Heat-proof", "fast_repair": "Quick hands", "suit": "Suited"}
const SHIPS_DIR := "res://data/ships/"
const DEFAULT_WEIGHT := 10.0

static var _shared = null
static var _shared_key := ""

var events := {}  ## id -> the event dictionary as written
var logs := {}  ## derelict log id -> {id, title, ship, faction, text} (data/logs/*.json)
var files := {}  ## id -> the file it came from
var order: Array[String] = []  ## ids, in file name order then file order
var errors: Array[String] = []  ## problems met while loading (bad JSON, a missing id, a duplicate id)
var _pages := {}  # id -> true for every event some outcome names in a goto
var _recruiters := {}  # id -> "species" | "unique" | "ada" for every event some outcome of which adds crew (unique: a character)


## The events of data/events and the packs, loaded once (again if the content loader was pointed elsewhere).
static func shared():
	var key := Content.root + "|" + Content.packs_root
	if _shared == null or key != _shared_key:
		_shared = new()
		_shared_key = key
	return _shared


func _init(dir := DIR) -> void:
	load_dir(dir)


## Read the events: for the default folder everything the content loader knows (core files, then the
## packs'); for any other folder (tests) every *.json in it, in name order. Problems go to `errors`, they
## do not stop the load.
func load_dir(dir: String) -> void:
	events.clear()
	files.clear()
	order.clear()
	errors.clear()
	_pages.clear()
	if dir == DIR:
		for ev in Content.events():
			add(ev, Content.file_of("events", str(ev["id"])))
	else:
		var names: Array = Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json"))
		names.sort()
		for f in names:
			_load_file(dir + "/" + f)
	_load_logs()
	_index_pages()
	_index_recruiters()


## Remember which events are follow-up pages: every event some outcome names in a goto.
func _index_pages() -> void:
	_pages.clear()
	for id in order:
		var choices = events[id].get("choices")
		for ch in choices if choices is Array else []:
			var outcomes = ch.get("outcomes") if ch is Dictionary else null
			for o in outcomes if outcomes is Array else []:
				var eff = o.get("effects") if o is Dictionary else null
				if eff is Dictionary and eff.get("goto") is String:
					_pages[eff["goto"]] = true


## Read every data/logs/*.json ({"logs": [{id, title, ship, faction, text}]}) into `logs`, then each pack's
## logs.json and logs/*.json, in pack order.
func _load_logs() -> void:
	logs.clear()
	var paths: Array[String] = _json_files(LOGS_DIR)
	for p in Content.packs():
		if FileAccess.file_exists(p["dir"] + "/logs.json"):
			paths.append(p["dir"] + "/logs.json")
		paths.append_array(_json_files(p["dir"] + "/logs"))
	for path in paths:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("logs") is Array:
			for l in data["logs"]:
				if l is Dictionary and l.get("id") is String:
					logs[l["id"]] = l


static func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names: Array = Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".json"))
	names.sort()
	for f in names:
		out.append(dir + "/" + f)
	return out


func _load_file(path: String) -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s: not valid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return
	var data = json.data
	if not (data is Dictionary and data.get("events") is Array):
		errors.append("%s: expected an object with an \"events\" list" % path)
		return
	var n := 0
	for ev in data["events"]:
		n += 1
		if not (ev is Dictionary and ev.get("id") is String and ev["id"] != ""):
			errors.append("%s: event number %d has no id" % [path, n])
			continue
		add(ev, path)


## Add event `ev` (as if read from `file`); a duplicate id is reported in `errors` and not added.
func add(ev: Dictionary, file := "(code)") -> void:
	var id := str(ev["id"])
	if events.has(id):
		errors.append("%s: event '%s': the id is also used in %s" % [file, id, files[id]])
		return
	events[id] = ev
	files[id] = file
	order.append(id)
	_index_pages()


func has(id: String) -> bool:
	return events.has(id)


func get_event(id: String) -> Dictionary:
	return events.get(id, {})


## Is `id` a follow-up page (type page, or named by some goto)? Pages are never rolled at a node.
func is_page(id: String) -> bool:
	return _pages.has(id) or str(events.get(id, {}).get("type", "")) == "page"


## Remember which events add crew: "ada" when a recruit is Ada herself, "unique" when it is a unique character, else "species".
func _index_recruiters() -> void:
	_recruiters.clear()
	var ada := str(_dict(CrewMember.config().get("ada")).get("name", ""))
	for id in order:
		var ev: Dictionary = events[id]
		var effects: Array = [_dict(_dict(ev.get("after_win")).get("effects"))]
		for ch in _list(ev.get("choices")):
			for o in _list(_dict(ch).get("outcomes")):
				effects.append(_dict(_dict(o).get("effects")))
				effects.append(_dict(_dict(_dict(o).get("after_win")).get("effects")))
		var kind := ""
		for eff in effects:
			for r in _list(eff.get("recruit")):
				var rd := _dict(r)
				if str(rd.get("name", "")) == ada:
					kind = "ada"
				elif rd.has("character"):
					kind = "unique" if kind != "ada" else kind
				elif kind == "":
					kind = "species"
		if kind != "":
			_recruiters[id] = kind


## The chance (data/drift.json `crew`) that event `id`, eligible at a pick, may be rolled at all: 1 for an event that adds no
## crew and for Ada's; `unique_event` for one that brings a unique character; `station_event` for a station greeting that brings
## an ordinary recruit and `species_event` for any other such event. A gate on the chance, not a weight, so an event that is
## alone in its pool (a region's station greeting) is rarer too.
func crew_factor(id: String, c) -> float:
	var kind: String = _recruiters.get(id, "")
	if kind == "" or kind == "ada":
		return 1.0
	var key := "unique_event" if kind == "unique" else ("station_event" if str(events[id].get("type", "")) == "station" else "species_event")
	return float(_dict(c.cfg.get("crew")).get(key, 1.0))


# --- picking ------------------------------------------------------------------------------------------

## The event that happens at `node` ({id, type, place}): a weighted roll with the campaign's rng among
## the events of the node's type whose requirements hold and that have not been used up (`once`). An event that adds crew
## is in the pool only with the chance crew_factor() gives.
## `filter` (optional Callable(ev) -> bool) can narrow the pool further. {} when there is none.
func pick(c, node: Dictionary, ship = null, filter := Callable()) -> Dictionary:
	var pool: Array = []
	var spare: Array = []  # `fallback` events: in the pool only when nothing else is eligible
	for id in order:
		var ev: Dictionary = events[id]
		if str(ev.get("type", "")) != str(node.get("type", "")) or is_page(id):
			continue
		var w := _weight(ev.get("weight", DEFAULT_WEIGHT))
		if w <= 0.0 or not eligible(ev, c, node, ship) or (filter.is_valid() and not filter.call(ev)):
			continue
		var gate := crew_factor(id, c)
		if gate < 1.0 and c.rng.randf() >= gate:  # crew are rare: most of the time the event is not in the pool
			continue
		(spare if bool(ev.get("fallback", false)) else pool).append([ev, w])
	if pool.is_empty():
		pool = spare
	if pool.is_empty():
		return {}
	var total := 0.0
	for p in pool:
		total += p[1]
	var r: float = c.rng.randf() * total
	var chosen: Dictionary = pool[-1][0]
	for p in pool:
		r -= p[1]
		if r < 0.0:
			chosen = p[0]
			break
	return chosen


## May `ev` happen at `node` now (not used up, its requires hold)?
func eligible(ev: Dictionary, c, node: Dictionary, ship = null) -> bool:
	if bool(ev.get("once", false)) and c.used.has(str(ev.get("id", ""))):
		return false
	return _world_ok(_dict(ev.get("requires")), c, node, ship)


## What a debt event is for, judged by its requires: "miss" (it asks for the flag debt_missed: the
## collectors' talk), "first" (it asks for not_flag met_ma: Ma's first call), else "reminder".
static func debt_kind(ev: Dictionary) -> String:
	var req := _dict(ev.get("requires"))
	if _list(req.get("flag")).has("debt_missed"):
		return "miss"
	return "first" if _list(req.get("not_flag")).has("met_ma") else "reminder"


static func _weight(v) -> float:
	return float(v) if v is float or v is int else DEFAULT_WEIGHT


static func _dict(v) -> Dictionary:
	return v if v is Dictionary else {}


static func _list(v) -> Array:
	if v is Array:
		return v
	return [] if v == null else [v]


## The parts of `requires` that depend on the campaign (and the fuel in the hold): jumps, flags,
## reputation, node, fuel_max, region and stage.
func _world_ok(req: Dictionary, c, node: Dictionary, ship = null) -> bool:
	if req.has("stage_min") and c.stage < int(req["stage_min"]):
		return false
	if req.has("stage_max") and c.stage > int(req["stage_max"]):
		return false
	if req.has("region"):
		var tag := str(c.region_data.get("events", ""))
		if not _list(req["region"]).any(func(r): return str(r) == c.region_id or (tag != "" and str(r) == tag)):
			return false
	if req.has("fuel_max") and (ship.inventory.count("fuel") if ship != null else 0) > int(req["fuel_max"]):
		return false
	if req.has("jumps_min") and c.jumps < int(req["jumps_min"]):
		return false
	if req.has("jumps_max") and c.jumps > int(req["jumps_max"]):
		return false
	for f in _list(req.get("flag")):
		if not c.flags.has(str(f)):
			return false
	for f in _list(req.get("not_flag")):
		if c.flags.has(str(f)):
			return false
	var lo := _dict(req.get("rep_min"))
	for f in lo:
		if int(c.rep.get(f, 0)) < int(lo[f]):
			return false
	var hi := _dict(req.get("rep_max"))
	for f in hi:
		if int(c.rep.get(f, 0)) > int(hi[f]):
			return false
	if req.has("node"):
		var want := str(req["node"])
		if want != str(node.get("type", "")) and want != str(node.get("place", "")) and want != str(node.get("id", "")):
			return false
	return true


## The parts of `requires` that depend on the crew and the ship: species, trait, component.
func _crew_ok(req: Dictionary, ship) -> bool:
	for s in _list(req.get("species")):
		if not ship.crew.any(func(m): return not m.is_down() and str(m.species) == str(s)):
			return false
	for t in _list(req.get("trait")):
		if not ship.crew.any(func(m): return not m.is_down() and traits_of(m).has(str(t))):
			return false
	for id in _list(req.get("component")):
		if not ship.components.instances.values().any(func(i): return i["id"] == str(id)):
			return false
	return true


## The traits of crew member `m` (species, personal and gear traits: CrewMember.traits()).
static func traits_of(m) -> Array:
	return m.traits()


# --- choices ------------------------------------------------------------------------------------------

## Is the choice blue (it asks for a species, a trait or an installed component, or says `blue`: good standing at the exit)?
static func is_blue(ch: Dictionary) -> bool:
	var req := _dict(ch.get("requires"))
	return req.has("species") or req.has("trait") or req.has("component") or bool(ch.get("blue", false))


## The choices of `ev` that show, in order: {index (into ev.choices), text, blue, grey, need}. A
## choice whose requirements fail is left out; one that only lacks items or credits is `grey` with
## `need` saying what. A blue choice's text gets its reason in brackets if it has none.
func choice_view(ev: Dictionary, c, ship, node: Dictionary = {}) -> Array:
	var out := []
	var choices: Array = ev.get("choices", []) if ev.get("choices") is Array else []
	for i in choices.size():
		var ch: Dictionary = _dict(choices[i])
		var req := _dict(ch.get("requires"))
		if not _world_ok(req, c, node, ship) or not _crew_ok(req, ship):
			continue
		var short: Dictionary = ship.inventory.missing(needs(ch))
		var blue := is_blue(ch)
		var text := str(ch.get("text", ""))
		if blue and not text.begins_with("["):
			text = "[%s] %s" % [_reason(req, ship), text]
		out.append({"index": i, "text": text, "blue": blue, "grey": not short.is_empty(), "need": _need_text(needs(ch), ship) if not short.is_empty() else ""})
	return out


## What a choice asks to be held: item id -> count (`credits` counts as an item).
static func needs(ch: Dictionary) -> Dictionary:
	var req := _dict(ch.get("requires"))
	var out := {}
	var items := _dict(req.get("items"))
	for id in items:
		out[str(id)] = int(items[id])
	if req.has("credits"):
		out["credits"] = int(out.get("credits", 0)) + int(req["credits"])
	return out


## Does the choice spend what it asks for (`pay` in its requires or on the choice)?
static func pays(ch: Dictionary) -> bool:
	return bool(ch.get("pay", false)) or bool(_dict(ch.get("requires")).get("pay", false))


func _need_text(need: Dictionary, ship) -> String:
	var parts := []
	var ids: Array = need.keys()
	ids.sort()
	for id in ids:
		parts.append("%d %s" % [need[id], _name(ship, id)])
	return ", ".join(parts)


func _reason(req: Dictionary, ship) -> String:
	if req.has("species"):
		return " / ".join(_list(req["species"]).map(func(s): return str(s).capitalize()))
	if req.has("trait"):
		return " / ".join(_list(req["trait"]).map(func(t): return TRAIT_LABELS.get(t, TraitSet.library().get(str(t), {}).get("name", str(t).capitalize()))))
	return " / ".join(_list(req.get("component")).map(func(id): return ship.components.def(str(id)).get("name", str(id)) if ship.components.has(str(id)) else str(id)))


static func _name(ship, id: String) -> String:
	return ship.crafting.name_of(id, ship.components)


## Take choice `index` of `ev`: pay what it asks to pay, roll an outcome, apply its effects. Returns
## {ok, why, text, lines, goto, fight, ending, logs, after_win}; `lines` are the changes in words ("-40 credits"),
## `goto` an event id to show next, `fight` a design id or "tier" for the controller to start, `ending` the id of the
## ending the outcome reached ("" for none), `logs` the derelict logs found (each {id, title, ship, faction, text}) and
## `after_win` the {text, effects} to run if that fight is won. ok is false (and nothing changes) when
## the choice is not on offer or its price cannot be paid.
func choose(ev: Dictionary, index: int, c, ship, node: Dictionary = {}) -> Dictionary:
	var entry := {}
	for v in choice_view(ev, c, ship, node):
		if v["index"] == index:
			entry = v
	if entry.is_empty():
		return {"ok": false, "why": "not available"}
	if entry["grey"]:
		return {"ok": false, "why": "needs " + entry["need"]}
	var ch: Dictionary = ev["choices"][index]
	var lines := []
	if pays(ch):
		var cost := needs(ch)
		ship.inventory.spend(cost)
		var ids: Array = cost.keys()
		ids.sort()
		for id in ids:
			lines.append("-%d %s" % [cost[id], _name(ship, id)])
	var outcome := roll(ch.get("outcomes", []), c.rng)
	if bool(ev.get("once", false)) and not _dict(outcome.get("effects")).is_empty():
		c.used[str(ev["id"])] = true  # spent: an outcome that does something
	var mark := landmark_title(ev)
	if mark != "" and not _dict(outcome.get("effects")).is_empty() and c.note_landmark(str(ev["id"]), mark):
		lines.append("Landmark: " + mark)  # first, as it was met before what it gave
	var res := apply(_dict(outcome.get("effects")), c, ship, node)
	lines.append_array(res["lines"])
	var after: Dictionary = _dict(outcome.get("after_win")) if outcome.has("after_win") else _dict(ev.get("after_win"))
	return {"ok": true, "why": "", "text": str(outcome.get("text", "")), "lines": lines, "goto": res["goto"], "fight": res["fight"], "ending": res["ending"], "logs": res["logs"], "after_win": after}


## The title of landmark event `ev` ("" when it is not one): its `landmark` text, else its id as words.
static func landmark_title(ev: Dictionary) -> String:
	var v = ev.get("landmark")
	if v is String and v != "":
		return v
	return str(ev.get("id", "")).replace("_", " ").capitalize() if v is bool and v else ""


## One of `outcomes` ({weight, ...}) by weight, with `rng`. {} for an empty list.
static func roll(outcomes, rng: RandomNumberGenerator) -> Dictionary:
	if not (outcomes is Array) or outcomes.is_empty():
		return {}
	var total := 0.0
	for o in outcomes:
		total += maxf(_weight(_dict(o).get("weight", 1.0)), 0.0)
	if total <= 0.0:
		return _dict(outcomes[0])
	var r := rng.randf() * total
	for o in outcomes:
		r -= maxf(_weight(_dict(o).get("weight", 1.0)), 0.0)
		if r < 0.0:
			return _dict(o)
	return _dict(outcomes[-1])


# --- effects ------------------------------------------------------------------------------------------

## Apply `effects` to campaign `c` and `ship`. Returns {lines, goto, fight, ending, logs}: the changes in words,
## the follow-up page, the fight to start and the ending reached (each "" when there is none) and the derelict logs
## found. The fight is not started here, and the ending screen is not opened (the event panel does).
func apply(effects: Dictionary, c, ship, node: Dictionary = {}) -> Dictionary:
	var lines: Array = []
	var found: Array = []
	var items := _dict(effects.get("items"))
	var ids: Array = items.keys()
	ids.sort()
	for id in ids:
		var before: int = ship.inventory.count(str(id))
		ship.inventory.add(str(id), int(items[id]))
		var got: int = ship.inventory.count(str(id)) - before
		if got != 0:
			lines.append("%+d %s" % [got, _name(ship, str(id))])
	var rep := _dict(effects.get("rep"))
	var factions: Array = rep.keys()
	factions.sort()
	for f in factions:
		var d: int = c.add_rep(str(f), int(rep[f]))
		if d != 0:
			lines.append("%s reputation %+d" % [c.faction_name(str(f)), d])
	if effects.has("crew_hp"):
		var hp := int(effects["crew_hp"])
		for m in ship.crew:
			if hp < 0:
				m.hurt(float(-hp))
			else:
				m.heal(float(hp))
		if hp != 0 and not ship.crew.is_empty():
			lines.append("Crew %+d hp" % hp)
	if effects.has("hull"):
		var d: int = c.change_hull(ship, int(effects["hull"]))
		if d != 0:
			lines.append("Hull integrity %+d" % d)
	if effects.has("debt"):
		lines.append_array(c.add_debt(ship, int(effects["debt"])))
	for f in _list(effects.get("flag")):
		c.flags[str(f)] = true
	for f in _list(effects.get("clear_flag")):
		c.flags.erase(str(f))
	for id in _list(effects.get("reveal")):
		var label: String = c.reveal(str(id))
		if label != "":
			lines.append("On the map: " + label)
	for id in _list(effects.get("blueprint")):
		if ship.crafting.has(str(id)) and ship.crafting.unlock(str(id)):
			lines.append("Blueprint learned: " + _name(ship, str(ship.crafting.def(str(id))["output"]["item"])))
	for r in _list(effects.get("recruit")):
		var rd := _dict(r)
		var species := str(rd.get("species", "human"))
		var chr := Characters.entry(str(rd.get("character", "")))  # a unique character comes as themselves
		var who: String = c.add_crew(ship, str(rd.get("name", "")), species, str(rd.get("character", "")))
		if who != "":
			lines.append("%s (%s) joins the crew" % [who, Characters.label(chr) if not chr.is_empty() else species.capitalize()])
	if effects.has("lose_crew"):
		var count = effects["lose_crew"]
		var n: int = (1 if count else 0) if count is bool else int(count)
		for i in n:
			var gone: String = c.lose_crew(ship)
			if gone != "":
				lines.append("%s is lost" % gone)
	for id in _list(effects.get("log")):
		if logs.has(str(id)):
			var again: bool = c.logs_found.has(str(id))  # shown again, but kept once
			c.logs_found[str(id)] = true
			found.append(logs[str(id)])
			lines.append(("Log read again: " if again else "Log found: ") + str(logs[str(id)].get("title", id)))
	for id in _list(effects.get("unlock")):
		if Unlocks.has(str(id)) and c.unlock(str(id)):
			lines.append("Unlocked: " + Unlocks.name_of(str(id)))
	var ending := str(effects.get("ending", ""))
	if ending != "":
		c.finish(ending)
	return {"lines": lines, "goto": str(effects.get("goto", "")), "fight": str(effects.get("fight", "")), "ending": ending, "logs": found}


# --- validation ---------------------------------------------------------------------------------------

## Every problem in the loaded files, one message each, naming the file and the event
## ("res://data/events/x.json: event 'foo': unknown key 'bar'"). Empty when the pack is sound. Checks
## keys, node types, factions, item ids (items.json, components.json, materials.json, credits, fuel),
## species, traits, recipes for `blueprint`, place ids, ship designs and that every goto exists.
func validate() -> Array[String]:
	var errs: Array[String] = errors.duplicate()
	var known := _known()
	for id in order:
		_check_event(events[id], files[id], known, errs)
	return errs


static func _ids_of(path: String, key: String) -> Dictionary:
	var out := {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get(key) is Array:
		for e in data[key]:
			if e is Dictionary and e.has("id"):
				out[str(e["id"])] = true
	return out


static func _known() -> Dictionary:
	var items := {}  # core and pack items, components and materials
	for kind in ["items", "components", "materials"]:
		for id in Content.ids(kind):
			items[id] = true
	items["credits"] = true
	items["fuel"] = true
	var places := Regions.place_ids()  # the fixed places of every region
	var regions := {}  # region ids and event tags
	for r in Regions.all():
		regions[str(r["id"])] = true
		regions[str(r.get("events", r["id"]))] = true
	var factions := {}
	var fac = JSON.parse_string(FileAccess.get_file_as_string("res://data/factions.json"))
	if fac is Dictionary:
		for f in fac.get("factions", []):
			if not bool(f.get("hostile", false)):
				factions[str(f["id"])] = true
	var species := {}  # every species of data/species.json and the packs, and every trait of the library
	for id in Content.ids("species"):
		species[id] = true
	var traits := {}
	for id in TraitSet.library():
		traits[id] = true
	var unlocks := {}
	for id in Content.ids("unlocks"):
		unlocks[id] = true
	var endings := {}
	for id in Content.ids("endings"):
		endings[id] = true
	var characters := {}
	for id in Content.ids("characters"):
		characters[id] = true
	return {"characters": characters, "items": items, "components": _ids_of("res://data/components.json", "components"), "recipes": _ids_of("res://data/recipes.json", "recipes"),
		"places": places, "factions": factions, "species": species, "traits": traits, "unlocks": unlocks, "endings": endings, "regions": regions}


func _check_event(ev: Dictionary, path: String, known: Dictionary, errs: Array[String]) -> void:
	var id := str(ev["id"])
	var bad := func(msg: String) -> void: errs.append("%s: event '%s': %s" % [path, id, msg])
	if not _is_snake(id):
		bad.call("the id must be snake_case")
	_check_keys(ev, EVENT_KEYS, "", bad)
	if not EVENT_TYPES.has(ev.get("type")):
		bad.call("unknown node type '%s' (known: %s)" % [ev.get("type"), ", ".join(EVENT_TYPES)])
	if ev.has("weight") and not (_is_num(ev["weight"]) and ev["weight"] >= 0):
		bad.call("weight must be a number, 0 or more")
	if ev.has("once") and not ev["once"] is bool:
		bad.call("once must be true or false")
	if ev.has("fallback") and not ev["fallback"] is bool:
		bad.call("fallback must be true or false")
	if ev.has("landmark") and not (ev["landmark"] is bool or (ev["landmark"] is String and ev["landmark"] != "")):
		bad.call("landmark must be true, false or a title")
	if ev.has("requires"):
		_check_req(ev["requires"], EVENT_REQ_KEYS, "requires", known, bad)
	if not (ev.get("text") is String and ev["text"] != ""):
		bad.call("text must be a non-empty string")
	if ev.has("after_win"):
		_check_after(ev["after_win"], "after_win", known, bad)
	if _is_landmark(ev) and not _has_effects(ev):
		bad.call("a landmark needs a choice with effects (it is recorded when one is taken)")
	if not ev.has("choices"):
		return  # a text with no choices is allowed: the panel offers a way out
	var choices = ev["choices"]
	if not (choices is Array and not choices.is_empty()):
		bad.call("choices must be a non-empty list")
		return
	for i in choices.size():
		var where := "choice %d" % (i + 1)
		var ch = choices[i]
		if not ch is Dictionary:
			bad.call(where + " must be an object")
			continue
		_check_keys(ch, CHOICE_KEYS, where + ": ", bad)
		if not (ch.get("text") is String and ch["text"] != ""):
			bad.call(where + ": text must be a non-empty string")
		if ch.has("pay") and not ch["pay"] is bool:
			bad.call(where + ": pay must be true or false")
		if ch.has("requires"):
			_check_req(ch["requires"], CHOICE_REQ_KEYS, where + " requires", known, bad)
		var outcomes = ch.get("outcomes")
		if not (outcomes is Array and not outcomes.is_empty()):
			bad.call(where + ": outcomes must be a non-empty list")
			continue
		var total := 0.0
		for j in outcomes.size():
			var ow := "%s outcome %d" % [where, j + 1]
			var o = outcomes[j]
			if not o is Dictionary:
				bad.call(ow + " must be an object")
				continue
			_check_keys(o, OUTCOME_KEYS, ow + ": ", bad)
			if o.has("weight") and not (_is_num(o["weight"]) and o["weight"] >= 0):
				bad.call(ow + ": weight must be a number, 0 or more")
			else:
				total += float(o.get("weight", 1.0))
			if o.has("text") and not o["text"] is String:
				bad.call(ow + ": text must be a string")
			if o.has("effects"):
				_check_effects(o["effects"], ow + " effects", known, bad)
			if o.has("after_win"):
				_check_after(o["after_win"], ow + " after_win", known, bad)
		if total <= 0.0:
			bad.call(where + ": the outcome weights add up to nothing")


func _check_keys(d: Dictionary, allowed: Array, prefix: String, bad: Callable) -> void:
	for k in d:
		if not allowed.has(k):
			bad.call("%sunknown key '%s' (known: %s)" % [prefix, k, ", ".join(allowed)])


func _check_req(req, allowed: Array, where: String, known: Dictionary, bad: Callable) -> void:
	if not req is Dictionary:
		bad.call(where + " must be an object")
		return
	_check_keys(req, allowed, where + ": ", bad)
	for k in ["jumps_min", "jumps_max", "credits", "fuel_max", "stage_min", "stage_max"]:
		if req.has(k) and not _is_num(req[k]):
			bad.call("%s: %s must be a number" % [where, k])
	for r in _list(req.get("region")):
		if not known["regions"].has(r):
			bad.call("%s: region '%s' is neither a region id nor a region's events tag (data/regions)" % [where, r])
	for k in ["flag", "not_flag"]:
		for f in _list(req.get(k)):
			if not (f is String and f != ""):
				bad.call("%s: %s must be a flag name or a list of them" % [where, k])
	for k in ["rep_min", "rep_max"]:
		if req.has(k):
			if not req[k] is Dictionary:
				bad.call("%s: %s must map a faction to a number" % [where, k])
				continue
			for f in req[k]:
				if not known["factions"].has(f):
					bad.call("%s: %s names unknown faction '%s' (known: %s)" % [where, k, f, ", ".join(known["factions"].keys())])
				elif not _is_num(req[k][f]):
					bad.call("%s: %s for %s must be a number" % [where, k, f])
	if req.has("node") and not (NODE_TYPES.has(req["node"]) or known["places"].has(req["node"])):
		bad.call("%s: node '%s' is neither a node type nor a place id" % [where, req["node"]])
	for s in _list(req.get("species")):
		if not known["species"].has(s):
			bad.call("%s: unknown species '%s' (known: %s)" % [where, s, ", ".join(known["species"].keys())])
	for t in _list(req.get("trait")):
		if not known["traits"].has(t):
			bad.call("%s: unknown trait '%s' (known: %s)" % [where, t, ", ".join(known["traits"].keys())])
	for id in _list(req.get("component")):
		if not known["components"].has(id):
			bad.call("%s: unknown component '%s'" % [where, id])
	if req.has("items"):
		_check_items(req["items"], where + ": items", known, bad, true)
	if req.has("pay") and not req["pay"] is bool:
		bad.call(where + ": pay must be true or false")


func _check_items(items, where: String, known: Dictionary, bad: Callable, positive: bool) -> void:
	if not items is Dictionary:
		bad.call(where + " must map an item id to a count")
		return
	for id in items:
		if not known["items"].has(id):
			bad.call("%s: unknown item id '%s' (not an item, component or material of the core or a pack, credits or fuel)" % [where, id])
		if not _is_int(items[id]) or (positive and items[id] <= 0) or items[id] == 0:
			bad.call("%s: the count of '%s' must be a whole number%s" % [where, id, ", more than 0" if positive else ", not 0"])


func _check_after(after, where: String, known: Dictionary, bad: Callable) -> void:
	if not after is Dictionary:
		bad.call(where + " must be an object with text and effects")
		return
	_check_keys(after, AFTER_KEYS, where + ": ", bad)
	if after.has("text") and not after["text"] is String:
		bad.call(where + ": text must be a string")
	if after.has("effects"):
		_check_effects(after["effects"], where + " effects", known, bad)


func _check_effects(eff, where: String, known: Dictionary, bad: Callable) -> void:
	if not eff is Dictionary:
		bad.call(where + " must be an object")
		return
	_check_keys(eff, EFFECT_KEYS, where + ": ", bad)
	if eff.has("items"):
		_check_items(eff["items"], where + ": items", known, bad, false)
	if eff.has("rep"):
		if not eff["rep"] is Dictionary:
			bad.call(where + ": rep must map a faction to a number")
		else:
			for f in eff["rep"]:
				if not known["factions"].has(f):
					bad.call("%s: rep names unknown faction '%s' (known: %s)" % [where, f, ", ".join(known["factions"].keys())])
				elif not _is_int(eff["rep"][f]):
					bad.call("%s: rep for %s must be a whole number" % [where, f])
	for k in ["crew_hp", "hull", "debt"]:
		if eff.has(k) and not _is_int(eff[k]):
			bad.call("%s: %s must be a whole number" % [where, k])
	for k in ["flag", "clear_flag"]:
		for f in _list(eff.get(k)):
			if not (f is String and f != ""):
				bad.call("%s: %s must be a flag name or a list of them" % [where, k])
	for r in _list(eff.get("recruit")):
		if not r is Dictionary:
			bad.call(where + ": recruit must be {name?, species} or {character}")
			continue
		_check_keys(r, RECRUIT_KEYS, where + " recruit: ", bad)
		if r.has("character"):  # a unique character (data/characters.json) needs neither species nor name
			if not known["characters"].has(r["character"]):
				bad.call("%s: recruit has unknown character '%s' (known: %s)" % [where, r["character"], ", ".join(known["characters"].keys())])
		elif not known["species"].has(r.get("species")):
			bad.call("%s: recruit has unknown species '%s' (known: %s)" % [where, r.get("species"), ", ".join(known["species"].keys())])
	if eff.has("lose_crew") and not (eff["lose_crew"] is bool or _is_int(eff["lose_crew"])):
		bad.call(where + ": lose_crew must be true or a count")
	for b in _list(eff.get("blueprint")):
		if not known["recipes"].has(b):
			bad.call("%s: unknown blueprint (recipe) '%s'" % [where, b])
	if eff.has("fight"):
		var f = eff["fight"]
		if not (f is String and (f == "tier" or FileAccess.file_exists(SHIPS_DIR + f + ".json") or _is_foe(f))):
			bad.call("%s: fight must be \"tier\", a faction to meet (\"gen:barons\") or the id of a design in data/ships (got '%s')" % [where, f])
	if eff.has("goto") and not (eff["goto"] is String and events.has(eff["goto"])):
		bad.call("%s: goto '%s' is not an event id in data/events" % [where, eff["goto"]])
	for l in _list(eff.get("log")):
		if not logs.has(l):
			bad.call("%s: unknown log id '%s' (not in data/logs/*.json or a pack's logs)" % [where, l])
	for r in _list(eff.get("reveal")):
		if not (r is String and (known["places"].has(r) or _is_node_id(r) or NODE_TYPES.has(r))):
			bad.call("%s: reveal '%s' is not a place id, a node type or a node id like n07" % [where, r])
	for u in _list(eff.get("unlock")):
		if not known["unlocks"].has(u):
			bad.call("%s: unknown unlock id '%s' (not in data/unlocks.json or a pack's unlocks.json)" % [where, u])
	if eff.has("ending") and not (eff["ending"] is String and known["endings"].has(eff["ending"])):
		bad.call("%s: unknown ending id '%s' (not in data/endings.json or a pack's endings.json)" % [where, eff["ending"]])


## "gen:<faction>" or "gen:<faction>:ram": a faction of the enemy tables, whose ship Campaign.foe_of rolls.
static func _is_foe(f: String) -> bool:
	var p := f.split(":")
	return p.size() >= 2 and p.size() <= 3 and p[0] == "gen" and Shipgen.tables()["factions"].has(p[1]) and (p.size() == 2 or p[2] == "ram")


static func _is_landmark(ev: Dictionary) -> bool:
	var v = ev.get("landmark")
	return (v is bool and v) or (v is String and v != "")


## Does some outcome of some choice of `ev` have effects?
static func _has_effects(ev: Dictionary) -> bool:
	for ch in _list(ev.get("choices")):
		for o in _list(_dict(ch).get("outcomes")):
			if not _dict(_dict(o).get("effects")).is_empty():
				return true
	return false


static func _is_num(v) -> bool:
	return v is float or v is int


static func _is_int(v) -> bool:
	return (v is float and v == floorf(v)) or v is int


static func _is_snake(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9]+(_[a-z0-9]+)*$")
	return re.search(s) != null


static func _is_node_id(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^n[0-9]+$")
	return re.search(s) != null
