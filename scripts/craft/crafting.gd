extends RefCounted
## Recipes (data/recipes.json), the blueprints the player knows and the job queues of the ship's stations: the
## fabricator's (`queue`) and the smelter's (`others["smelter"]`, docs/CONTENT.md section 12). A recipe names the
## `station` that runs it (default "fabricator"); `fab_level` and `tools` are then the level and tools of that station.
## Each station has its own queue, and the station a recipe needs is asked of the `fab` dictionary a caller passes in
## (`station`, default "fabricator"; `speed`, default 1: work done per second), see workshop.gd and processing.gd.
## Materials are spent when a job is queued and refunded if it is cancelled. Pure data, no nodes.

const Content = preload("res://scripts/data/content.gd")
const VERSION := 1
const QUEUE_MAX := 8
const ITEMS_PATH := "res://data/items.json"  ## names of ammo, gear and special items
const FABRICATOR := "fabricator"
const STATIONS := {"fabricator": "Fabricator", "smelter": "Smelter"}  ## the stations a recipe can name -> their names

var recipes := {}    # id -> {id, output {item, count}, materials, fab_level, tools, time, category}
var order: Array[String] = []
var materials := {}  # id -> {id, name, color, rarity}
var known := {}      # recipe id -> true; the blueprints the player has (a set)
var seen := {}       # recipe id -> true; the known blueprints the player has looked at on the Blueprints tab (the rest are NEW); saved
var queue: Array = []  # the fabricator's FIFO jobs: {recipe, progress (seconds of work done), paid (materials spent)}
var paused := false  ## the first job could not run during the last tick (fabricator offline or too weak); not saved
var others := {}  ## station id -> its FIFO jobs, for every station but the fabricator (the smelter); read through queue_of()
var paused_at := {}  ## station id -> true: its first job could not run during the last tick; not saved
var working := {}  ## part uid -> true: the smelters that worked during the last tick (heat.gd reads it); not saved
var lead := {}  ## station id -> uid of the part running that station's queue during the last tick (crew man it: jobs.gd); not saved
var _start_known: Array[String] = []
var _item_names := {}  # item id -> name (data/items.json)
var _item_defs := {}  # item id -> its row of data/items.json


## Load the recipes and materials. Resets the known blueprints to `start_known` and empties the queue.
func load(recipes_path: String, materials_path: String) -> void:
	var m = Content.read(materials_path)
	assert(m is Dictionary and m.has("materials"), "bad material data: " + materials_path)
	var r = Content.read(recipes_path)
	assert(r is Dictionary and r.has("recipes"), "bad recipe data: " + recipes_path)
	materials.clear()
	recipes.clear()
	order.clear()
	known.clear()
	queue.clear()
	_clear_stations()
	_start_known.clear()
	_item_names.clear()
	_item_defs.clear()
	if FileAccess.file_exists(ITEMS_PATH):
		var it = Content.read(ITEMS_PATH)
		if it is Dictionary and it.get("items") is Array:
			for d in it["items"]:
				_item_names[str(d["id"])] = str(d.get("name", d["id"]))
				_item_defs[str(d["id"])] = d
	for d in m["materials"]:
		materials[d["id"]] = d
	for d in r["recipes"]:
		d["fab_level"] = int(d["fab_level"])
		d["station"] = str(d.get("station", FABRICATOR))
		assert(STATIONS.has(d["station"]), "recipe %s has an unknown station %s" % [d["id"], d["station"]])
		d["time"] = float(d["time"])
		d["output"] = {"item": str(d["output"]["item"]), "count": int(d["output"]["count"])}
		var cost := {}
		for id in d["materials"]:
			cost[id] = int(d["materials"][id])
		d["materials"] = cost
		if not recipes.has(d["id"]):
			order.append(d["id"])
		recipes[d["id"]] = d
	for id in r.get("start_known", []):
		assert(recipes.has(id), "start_known has an unknown recipe: " + str(id))
		known[str(id)] = true
		_start_known.append(str(id))
	mark_seen()


## Forget the unlocked blueprints and empty the queue, as after load().
func reset() -> void:
	known.clear()
	for id in _start_known:
		known[id] = true
	mark_seen()
	queue.clear()
	_clear_stations()


func ids() -> Array[String]:
	return order


## The display name of item, material or component `id` (`components`: a components.gd instance, optional).
func name_of(id: String, components = null) -> String:
	if components != null and components.has(id):
		return str(components.def(id).get("name", id))
	if materials.has(id):
		return str(materials[id].get("name", id))
	return str(_item_names.get(id, id))


## The row of item `id` in data/items.json ({} for a part or a material).
func item_def(id: String) -> Dictionary:
	return _item_defs.get(id, {})


func has(id: String) -> bool:
	return recipes.has(id)


func def(id: String) -> Dictionary:
	return recipes.get(id, {})


## The station that runs recipe `id` ("fabricator" for an unknown one).
func station_of(id: String) -> String:
	return str(recipes.get(id, {}).get("station", FABRICATOR))


## The jobs queued at `station` (the live array: the fabricator's `queue`, or the station's own, made on first use).
func queue_of(station: String) -> Array:
	if station == FABRICATOR:
		return queue
	if not others.has(station):
		others[station] = []
	return others[station]


## Did the first job of `station` stop during the last tick (the station offline or too weak)?
func is_paused(station: String) -> bool:
	return paused if station == FABRICATOR else bool(paused_at.get(station, false))


func is_known(id: String) -> bool:
	return known.has(id)


## Learn a blueprint. False when the recipe does not exist or is already known.
func unlock(id: String) -> bool:
	if not recipes.has(id) or known.has(id):
		return false
	known[id] = true
	return true


## Everything known so far has been looked at: no blueprint is NEW.
func mark_seen() -> void:
	seen = known.duplicate()


## The known blueprints not looked at yet (NEW), in recipe order.
func fresh() -> Array[String]:
	var out: Array[String] = []
	for id in order:
		if known.has(id) and not seen.has(id):
			out.append(id)
	return out


## The line that says a blueprint was learned and where to make it: "Blueprint: Laser Mk2. Make it at the fabricator (C)."
func learned_line(id: String, components = null) -> String:
	return "Blueprint: %s. Make it at the %s (C)." % [name_of(str(def(id)["output"]["item"]), components), str(STATIONS.get(station_of(id), "fabricator")).to_lower()]


## Why `recipe_id` cannot be crafted now, or "" when it can. `fab` is the station's result (workshop.gd level_of or
## processing.gd best): {level, tools, station (default "fabricator")}.
## Gives the first failing reason: unknown recipe, blueprint, wrong station, offline, level, tool, materials.
func can_craft(recipe_id: String, inventory, fab: Dictionary) -> String:
	if not recipes.has(recipe_id):
		return "unknown recipe"
	if not known.has(recipe_id):
		return "blueprint not known"
	var r: Dictionary = recipes[recipe_id]
	if r["station"] != str(fab.get("station", FABRICATOR)):
		return "needs a " + str(STATIONS[r["station"]]).to_lower()
	var sname := str(STATIONS[r["station"]]).to_lower()
	var level := int(fab.get("level", 0))
	if level <= 0:
		return sname + " offline"
	if level < r["fab_level"]:
		return "needs %s level %d" % [sname, r["fab_level"]]
	var tools := PackedStringArray()
	for t in r["tools"]:
		if not fab.get("tools", []).has(t):
			tools.append(t)
	if not tools.is_empty():
		return "needs tool: " + ", ".join(tools)
	var short: Dictionary = inventory.missing(r["materials"])
	if not short.is_empty():
		var parts := PackedStringArray()
		for id in r["materials"]:
			if short.has(id):
				parts.append("%d %s" % [short[id], id])
		return "missing: " + ", ".join(parts)
	return ""


## Queue a craft: pays the materials now. Returns "" or the reason it was refused.
func enqueue(recipe_id: String, inventory, fab: Dictionary) -> String:
	var why := can_craft(recipe_id, inventory, fab)
	if why != "":
		return why
	var jobs := queue_of(recipes[recipe_id]["station"])
	if jobs.size() >= QUEUE_MAX:
		return "queue full"
	var paid: Dictionary = recipes[recipe_id]["materials"].duplicate()
	inventory.spend(paid)
	jobs.append({"recipe": recipe_id, "progress": 0.0, "paid": paid})
	return ""


## Advance the first job of the station `fab` describes by `dt` seconds (times `fab.speed`, default 1: a manned
## smelter works faster). It only progresses while the station has the level and tools it needs (so it pauses when
## power drops). Finished items go into `inventory`; spare time carries on into the next job. Returns the recipe ids
## finished, in order. `paused` (is_paused) says whether the first job was stopped by the station.
func tick(dt: float, inventory, fab: Dictionary) -> Array[String]:
	var station := str(fab.get("station", FABRICATOR))
	var jobs := queue_of(station)
	var done: Array[String] = []
	var left := dt * float(fab.get("speed", 1.0))
	_pause(station, false)
	while not jobs.is_empty():
		var job: Dictionary = jobs[0]
		var r: Dictionary = recipes[job["recipe"]]
		if not _can_run(r, fab):
			_pause(station, true)
			break
		if left <= 0.0:
			break
		var need: float = r["time"] - job["progress"]
		if left < need:
			job["progress"] += left
			break
		left -= need
		inventory.add(r["output"]["item"], r["output"]["count"])
		done.append(job["recipe"])
		jobs.pop_front()
	return done


## Drop the job at `index` of `station`'s queue and give back everything it cost. False when there is no such job.
func cancel(index: int, inventory, station := FABRICATOR) -> bool:
	var jobs := queue_of(station)
	if index < 0 or index >= jobs.size():
		return false
	inventory.refund(jobs[index]["paid"])
	jobs.remove_at(index)
	if jobs.is_empty():
		_pause(station, false)
	return true


func to_dict() -> Dictionary:
	var ids_known: Array = known.keys()
	ids_known.sort()
	var ids_seen: Array = seen.keys()
	ids_seen.sort()
	var d := {"version": VERSION, "known": ids_known, "queue": _jobs_out(queue), "seen": ids_seen}  # "seen" is optional when reading: a save without it has seen everything
	var extra := {}  # optional, like a save's belts: only written when another station has work
	for st in others:
		if not others[st].is_empty():
			extra[st] = _jobs_out(others[st])
	if not extra.is_empty():
		d["queues"] = extra
	return d


## Replace the known blueprints and the queues with a saved set. Returns "" on success, else the
## reason (nothing changes then).
func load_dict(d: Dictionary) -> String:
	var r := _read(d)
	if r.has("error"):
		return r["error"]
	known = r["known"]
	for id in _start_known:  # what every run starts knowing, even a set saved before it was added (a starter's design, an old save)
		known[id] = true
	seen = r["seen"]
	queue = r["queue"]
	others = r["queues"]
	paused = false
	paused_at.clear()
	working.clear()
	lead.clear()
	return ""


## Is `d` a saved set load_dict would take? "" or the reason.
func check_dict(d: Dictionary) -> String:
	return str(_read(d).get("error", ""))


## Parse a saved set: {known, queue, queues}, or {error} for the first problem.
func _read(d: Dictionary) -> Dictionary:
	if int(d.get("version", 0)) != VERSION:
		return {"error": "unsupported crafting version"}
	var fresh_known := {}
	for id in d.get("known", []):
		if not recipes.has(str(id)):
			return {"error": "unknown recipe " + str(id)}
		fresh_known[str(id)] = true
	var fresh_seen := fresh_known.duplicate()
	if d.has("seen") and d["seen"] is Array:
		fresh_seen = {}
		for id in d["seen"]:
			if fresh_known.has(str(id)):
				fresh_seen[str(id)] = true
	var fab := _read_jobs(d.get("queue", []), FABRICATOR)
	if fab.has("error"):
		return fab
	var fresh_others := {}
	var extra = d.get("queues", {})
	if not extra is Dictionary:
		return {"error": "bad station queues"}
	for st in extra:
		if not STATIONS.has(str(st)) or str(st) == FABRICATOR:
			return {"error": "unknown station " + str(st)}
		var r := _read_jobs(extra[st], str(st))
		if r.has("error"):
			return r
		fresh_others[str(st)] = r["jobs"]
	return {"known": fresh_known, "seen": fresh_seen, "queue": fab["jobs"], "queues": fresh_others}


## Parse one saved queue of `station`: {jobs}, or {error}.
func _read_jobs(jobs, station: String) -> Dictionary:
	if not jobs is Array:
		return {"error": "bad job list"}
	if jobs.size() > QUEUE_MAX:
		return {"error": "queue too long"}
	var fresh_queue := []
	for j in jobs:
		if not (j is Dictionary and recipes.has(str(j.get("recipe", "")))):
			return {"error": "bad job in the queue"}
		if station_of(str(j["recipe"])) != station:
			return {"error": "job %s is in the wrong queue" % str(j["recipe"])}
		var p = j.get("progress", -1)
		if not (p is int or p is float) or p < 0:
			return {"error": "bad job progress"}
		var paid := {}
		if not (j.get("paid") is Dictionary):
			return {"error": "bad job cost"}
		for id in j["paid"]:
			var v = j["paid"][id]
			if not (v is int or v is float) or v < 0 or v != floorf(v):
				return {"error": "bad job cost for " + str(id)}
			paid[str(id)] = int(v)
		fresh_queue.append({"recipe": str(j["recipe"]), "progress": float(p), "paid": paid})
	return {"jobs": fresh_queue}


func _jobs_out(jobs: Array) -> Array:
	var out := []
	for j in jobs:
		out.append({"recipe": j["recipe"], "progress": j["progress"], "paid": j["paid"].duplicate()})
	return out


func _pause(station: String, on: bool) -> void:
	if station == FABRICATOR:
		paused = on
	else:
		paused_at[station] = on


## Forget every other station's queue and the runtime state of all of them.
func _clear_stations() -> void:
	paused = false
	others.clear()
	paused_at.clear()
	working.clear()
	lead.clear()


## True when the station is level enough and has every tool this recipe needs.
func _can_run(r: Dictionary, fab: Dictionary) -> bool:
	if int(fab.get("level", 0)) < r["fab_level"]:
		return false
	for t in r["tools"]:
		if not fab.get("tools", []).has(t):
			return false
	return true
