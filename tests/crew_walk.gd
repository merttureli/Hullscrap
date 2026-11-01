extends RefCounted
## Not a test (the runner only loads test_*.gd). The walk behind tests/tool_crew_rate.gd and tests/test_alone.gd (playtest 2, A1 + A2): how many
## crew a run gains, and how often it meets Ada. Each run is a seeded campaign played at the map level, without flying or the arena: per stage it visits NODES nodes (a
## wander over unvisited neighbours, then the shortest way to the exit beacon), plays the node's event (it takes a recruit when a
## choice offers one, else a random open choice), the node's other POI half the time, stubs fights as won or fled, hires at a
## station when a recruit is on offer and the ship can pay 100 more than the price, clears the exit warden and crosses.

const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Sector = preload("res://scripts/space/sector.gd")

const NODES := 7  ## nodes visited per stage before heading for the exit
const CHECKPOINTS: Array[int] = [2, 4, 8]
const MAX_PAGES := 12

var roam := false  ## true: every other POI of a node's sector is played, not one of them half the time (endless space: far POIs too)
var _pick := RandomNumberGenerator.new()
var seen := {}  ## event id -> times it was shown, over all runs
var from := {}  ## where a recruit came from: "event:<id>", "station" -> times


## Run `i` (a seed): a campaign of `last_stage` stages with `design`. Returns {start (crew at the start), crew (stage -> crew aboard at the end of
## it, for the stages in CHECKPOINTS and `last_stage`), met_ada, took_ada, distress12 (distress events met in stages 1-2)}.
func run(i: int, design: String, last_stage := 8) -> Dictionary:
	_pick.seed = 4242 + i * 31
	var c := Campaign.new(9000 + i)
	var ship = Ship.from_design(design)
	Jobs.spawn_crew(ship)
	var out := {"start": ship.crew.size(), "crew": {}, "met_ada": false, "took_ada": false, "distress12": 0}
	var guard := 0
	while c.stage <= mini(c.stages(), last_stage) and guard < 400:
		guard += 1
		var stage := c.stage
		_play_stage(c, ship, out)
		if stage in CHECKPOINTS or stage == last_stage:
			out["crew"][stage] = ship.crew.size()
		if not _cross(c, ship) or c.stage == stage:
			break
	for s in CHECKPOINTS:
		if s <= last_stage and not out["crew"].has(s):
			out["crew"][s] = ship.crew.size()
	out["took_ada"] = ship.crew.any(func(m): return m.name == "Ada") and out["met_ada"]
	return out


## One stage: the first node's event, then NODES nodes, then the way to the exit.
func _play_stage(c: Campaign, ship, out: Dictionary) -> void:
	var seen_nodes := {c.current: true}
	_arrive(c, ship, out)
	var steps := 0
	while seen_nodes.size() < NODES and steps < 40:
		steps += 1
		var open: Array = c.neighbours(c.current).filter(func(o): return not seen_nodes.has(o) and c.node(o)["type"] != "gate" and c.jump_block(o, ship, false) == "")
		if open.is_empty():
			open = c.neighbours(c.current).filter(func(o): return c.node(o)["type"] != "gate" and c.jump_block(o, ship, false) == "")
		if open.is_empty():
			break
		var to: String = open[_pick.randi() % open.size()]
		if not _go(c, ship, to, out):
			return
		if not seen_nodes.has(to):
			seen_nodes[to] = true
			_arrive(c, ship, out)
	for to in _path_to_exit(c):
		if not _go(c, ship, to, out):
			return


func _go(c: Campaign, ship, to: String, out: Dictionary) -> bool:
	ship.inventory.add("fuel", 3)
	var r := c._jump_now(to, ship, false)
	return bool(r["ok"])


func _path_to_exit(c: Campaign) -> Array:
	var goal: String = c.drift.exit_id()
	var came := {c.current: ""}
	var queue: Array = [c.current]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at == goal:
			var path := []
			while at != c.current:
				path.push_front(at)
				at = came[at]
			return path
		for o in c.neighbours(at):
			if not came.has(o) and c.node(o)["type"] != "gate":
				came[o] = at
				queue.append(o)
	return []


## The node's own event, a station's hires, and one other POI of the node's sector half the time.
func _arrive(c: Campaign, ship, out: Dictionary) -> void:
	if c.at_exit():
		return
	var a := c.arrive(ship)
	if not a["refused"].is_empty() or not a["event"].is_empty():
		_chain(a["event"], c, ship, out)
	_hire(c, ship)
	var s = c.current_sector()
	var others: Array = s.pois.filter(func(p): return not p["main"] and p["state"] == Sector.NEW and str(p["event_type"]) != "")
	if roam:
		for poi in others:
			_chain(c.events.pick(c, {"id": c.current, "type": str(poi["event_type"]), "place": ""}, ship), c, ship, out)
	elif not others.is_empty() and _pick.randf() < 0.5:
		var poi: Dictionary = others[_pick.randi() % others.size()]
		var ev: Dictionary = c.events.pick(c, {"id": c.current, "type": str(poi["event_type"]), "place": ""}, ship)
		_chain(ev, c, ship, out)


func _hire(c: Campaign, ship) -> void:
	var list: Array = c.offers.get(c.current, [])
	if list.is_empty() or c.station_cfg(c.current).is_empty() or c.dock_block(c.current) != "":
		return
	var price := c.price(int(c.cfg["prices"]["recruit"]), c._station_faction(c.current), ship)
	if ship.inventory.count("credits") >= price + 100:
		var before: int = ship.crew.size()
		var r := c.recruit(ship, c.current, 0)
		if r["ok"] and ship.crew.size() > before:
			from["station"] = int(from.get("station", 0)) + 1


func _chain(ev: Dictionary, c: Campaign, ship, out: Dictionary) -> void:
	var queue: Array = [ev]
	var pages := 0
	while not queue.is_empty() and pages < MAX_PAGES:
		var e: Dictionary = queue.pop_front()
		if e.is_empty():
			continue
		pages += 1
		var id := str(e.get("id", ""))
		seen[id] = int(seen.get(id, 0)) + 1
		if id == "ada_pod":
			out["met_ada"] = true
		if str(e.get("type", "")) == "distress" and c.stage <= 2:
			out["distress12"] += 1
		var view := c.events.choice_view(e, c, ship, c.node(c.current))
		var open: Array = view.filter(func(v): return not v["grey"])
		if open.is_empty():
			continue
		var wants: Array = open.filter(func(v): return _recruits(e, int(v["index"])))
		var v: Dictionary = wants[_pick.randi() % wants.size()] if not wants.is_empty() else open[_pick.randi() % open.size()]
		var before: int = ship.crew.size()
		var r := c.events.choose(e, int(v["index"]), c, ship, c.node(c.current))
		if not r["ok"]:
			continue
		if ship.crew.size() > before:
			var k := "event:" + id
			from[k] = int(from.get(k, 0)) + ship.crew.size() - before
		if str(r["fight"]) != "":
			var roll := _pick.randf()
			var res := {"state": "won" if roll < 0.7 else "fled", "enemy": r["fight"], "threat": 2}
			var done := c.fight_done(res, ship, r["after_win"])
			if done["goto"] != "" and c.events.has(done["goto"]):
				queue.append(c.events.get_event(done["goto"]))
		elif str(r["goto"]) != "" and c.events.has(r["goto"]):
			queue.append(c.events.get_event(r["goto"]))


## Does some outcome of choice `index` of `e` add crew?
func _recruits(e: Dictionary, index: int) -> bool:
	for o in e["choices"][index].get("outcomes", []):
		var eff = o.get("effects", {})
		if eff is Dictionary and eff.has("recruit"):
			return true
	return false


## At the exit beacon: the warden is cleared by fiat, then the crossing to the first region on offer (a random one).
func _cross(c: Campaign, ship) -> bool:
	if c.is_final():
		return false
	c.current = c.drift.exit_id()
	c.visited[c.current] = true
	c._enter(c.current, ship)
	if c.warden_up():
		c.flags[str(c.warden["flag"])] = true
	var offers: Array = c.region_offers()
	if offers.is_empty():
		return false
	var r := c.cross(offers[_pick.randi() % offers.size()], ship)
	return bool(r["ok"])
