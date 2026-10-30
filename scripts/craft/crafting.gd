extends RefCounted
## Recipes (data/recipes.json), the blueprints the player knows and the fabricator's job queue.
## Materials are spent when a job is queued and refunded if it is cancelled. Pure data, no nodes.

const VERSION := 1
const QUEUE_MAX := 8
const ITEMS_PATH := "res://data/items.json"  ## names of ammo, gear and special items

var recipes := {}    # id -> {id, output {item, count}, materials, fab_level, tools, time, category}
var order: Array[String] = []
var materials := {}  # id -> {id, name, color, rarity}
var known := {}      # recipe id -> true; the blueprints the player has (a set)
var queue: Array = []  # FIFO jobs: {recipe, progress (seconds done), paid (materials spent)}
var paused := false  ## the first job could not run during the last tick (fabricator offline or too weak); not saved
var _start_known: Array[String] = []
var _item_names := {}  # item id -> name (data/items.json)


## Load the recipes and materials. Resets the known blueprints to `start_known` and empties the queue.
func load(recipes_path: String, materials_path: String) -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(materials_path))
	assert(m is Dictionary and m.has("materials"), "bad material data: " + materials_path)
	var r = JSON.parse_string(FileAccess.get_file_as_string(recipes_path))
	assert(r is Dictionary and r.has("recipes"), "bad recipe data: " + recipes_path)
	materials.clear()
	recipes.clear()
	order.clear()
	known.clear()
	queue.clear()
	paused = false
	_start_known.clear()
	_item_names.clear()
	if FileAccess.file_exists(ITEMS_PATH):
		var it = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
		if it is Dictionary and it.get("items") is Array:
			for d in it["items"]:
				_item_names[str(d["id"])] = str(d.get("name", d["id"]))
	for d in m["materials"]:
		materials[d["id"]] = d
	for d in r["recipes"]:
		d["fab_level"] = int(d["fab_level"])
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


## Forget the unlocked blueprints and empty the queue, as after load().
func reset() -> void:
	known.clear()
	for id in _start_known:
		known[id] = true
	queue.clear()
	paused = false


func ids() -> Array[String]:
	return order


## The display name of item, material or component `id` (`components`: a components.gd instance, optional).
func name_of(id: String, components = null) -> String:
	if components != null and components.has(id):
		return str(components.def(id).get("name", id))
	if materials.has(id):
		return str(materials[id].get("name", id))
	return str(_item_names.get(id, id))


func has(id: String) -> bool:
	return recipes.has(id)


func def(id: String) -> Dictionary:
	return recipes.get(id, {})


func is_known(id: String) -> bool:
	return known.has(id)


## Learn a blueprint. False when the recipe does not exist or is already known.
func unlock(id: String) -> bool:
	if not recipes.has(id) or known.has(id):
		return false
	known[id] = true
	return true


## Why `recipe_id` cannot be crafted now, or "" when it can. `fab` is workshop.gd's level_of result.
## Gives the first failing reason: unknown recipe, blueprint, offline, level, tool, materials.
func can_craft(recipe_id: String, inventory, fab: Dictionary) -> String:
	if not recipes.has(recipe_id):
		return "unknown recipe"
	if not known.has(recipe_id):
		return "blueprint not known"
	var r: Dictionary = recipes[recipe_id]
	var level := int(fab.get("level", 0))
	if level <= 0:
		return "fabricator offline"
	if level < r["fab_level"]:
		return "needs fabricator level %d" % r["fab_level"]
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
	if queue.size() >= QUEUE_MAX:
		return "queue full"
	var paid: Dictionary = recipes[recipe_id]["materials"].duplicate()
	inventory.spend(paid)
	queue.append({"recipe": recipe_id, "progress": 0.0, "paid": paid})
	return ""


## Advance the first job by `dt` seconds. It only progresses while the fabricator has the level and
## tools it needs (so it pauses when power drops). Finished items go into `inventory`; spare time
## carries on into the next job. Returns the recipe ids finished, in order. `paused` says whether the
## first job was stopped by the fabricator.
func tick(dt: float, inventory, fab: Dictionary) -> Array[String]:
	var done: Array[String] = []
	var left := dt
	paused = false
	while left > 0.0 and not queue.is_empty():
		var job: Dictionary = queue[0]
		var r: Dictionary = recipes[job["recipe"]]
		if not _can_run(r, fab):
			paused = true
			break
		var need: float = r["time"] - job["progress"]
		if left < need:
			job["progress"] += left
			break
		left -= need
		inventory.add(r["output"]["item"], r["output"]["count"])
		done.append(job["recipe"])
		queue.pop_front()
	return done


## Drop the job at `index` and give back everything it cost. False when there is no such job.
func cancel(index: int, inventory) -> bool:
	if index < 0 or index >= queue.size():
		return false
	inventory.refund(queue[index]["paid"])
	queue.remove_at(index)
	if queue.is_empty():
		paused = false
	return true


func to_dict() -> Dictionary:
	var ids_known: Array = known.keys()
	ids_known.sort()
	var jobs := []
	for j in queue:
		jobs.append({"recipe": j["recipe"], "progress": j["progress"], "paid": j["paid"].duplicate()})
	return {"version": VERSION, "known": ids_known, "queue": jobs}


## Replace the known blueprints and the queue with a saved set. Returns "" on success, else the
## reason (nothing changes then).
func load_dict(d: Dictionary) -> String:
	var r := _read(d)
	if r.has("error"):
		return r["error"]
	known = r["known"]
	queue = r["queue"]
	paused = false
	return ""


## Is `d` a saved set load_dict would take? "" or the reason.
func check_dict(d: Dictionary) -> String:
	return str(_read(d).get("error", ""))


## Parse a saved set: {known, queue}, or {error} for the first problem.
func _read(d: Dictionary) -> Dictionary:
	if int(d.get("version", 0)) != VERSION:
		return {"error": "unsupported crafting version"}
	var fresh_known := {}
	for id in d.get("known", []):
		if not recipes.has(str(id)):
			return {"error": "unknown recipe " + str(id)}
		fresh_known[str(id)] = true
	var jobs: Array = d.get("queue", [])
	if jobs.size() > QUEUE_MAX:
		return {"error": "queue too long"}
	var fresh_queue := []
	for j in jobs:
		if not (j is Dictionary and recipes.has(str(j.get("recipe", "")))):
			return {"error": "bad job in the queue"}
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
	return {"known": fresh_known, "queue": fresh_queue}


## True when the fabricator is level enough and has every tool this recipe needs.
func _can_run(r: Dictionary, fab: Dictionary) -> bool:
	if int(fab.get("level", 0)) < r["fab_level"]:
		return false
	for t in r["tools"]:
		if not fab.get("tools", []).has(t):
			return false
	return true
