extends RefCounted
## Recipes (data/recipes.json), the blueprints the player knows and the fabricator's job queue.
## Materials are spent when a job is queued and refunded if it is cancelled. Pure data, no nodes.

const VERSION := 1
const QUEUE_MAX := 8

var recipes := {}    # id -> {id, output {item, count}, materials, fab_level, tools, time, category}
var order: Array[String] = []
var materials := {}  # id -> {id, name, color, rarity}
var known := {}      # recipe id -> true; the blueprints the player has (a set)
var queue: Array = []  # FIFO jobs: {recipe, progress (seconds done), paid (materials spent)}


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


func ids() -> Array[String]:
	return order


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
## carries on into the next job. Returns the recipe ids finished, in order.
func tick(dt: float, inventory, fab: Dictionary) -> Array[String]:
	var done: Array[String] = []
	var left := dt
	while left > 0.0 and not queue.is_empty():
		var job: Dictionary = queue[0]
		var r: Dictionary = recipes[job["recipe"]]
		if not _can_run(r, fab):
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
	if int(d.get("version", 0)) != VERSION:
		return "unsupported crafting version"
	var fresh_known := {}
	for id in d.get("known", []):
		if not recipes.has(str(id)):
			return "unknown recipe " + str(id)
		fresh_known[str(id)] = true
	var jobs: Array = d.get("queue", [])
	if jobs.size() > QUEUE_MAX:
		return "queue too long"
	var fresh_queue := []
	for j in jobs:
		if not (j is Dictionary and recipes.has(str(j.get("recipe", "")))):
			return "bad job in the queue"
		var p = j.get("progress", -1)
		if not (p is int or p is float) or p < 0:
			return "bad job progress"
		var paid := {}
		if not (j.get("paid") is Dictionary):
			return "bad job cost"
		for id in j["paid"]:
			var v = j["paid"][id]
			if not (v is int or v is float) or v < 0 or v != floorf(v):
				return "bad job cost for " + str(id)
			paid[str(id)] = int(v)
		fresh_queue.append({"recipe": str(j["recipe"]), "progress": float(p), "paid": paid})
	known = fresh_known
	queue = fresh_queue
	return ""


## True when the fabricator is level enough and has every tool this recipe needs.
func _can_run(r: Dictionary, fab: Dictionary) -> bool:
	if int(fab.get("level", 0)) < r["fab_level"]:
		return false
	for t in r["tools"]:
		if not fab.get("tools", []).has(t):
			return false
	return true
