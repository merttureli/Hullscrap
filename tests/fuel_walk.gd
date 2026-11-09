extends RefCounted
## Not a test (the runner only loads test_*.gd). The walk behind tests/tool_fuel_rate.gd (playtest 2, economy: fuel is scarce): how much
## fuel a run has at the end of each stage, how many jumps it can afford and how often it has to be towed. Each run is a seeded campaign
## played at the map level, like tests/crew_walk.gd (no flying, no arena): per stage it visits `nodes` nodes (a wander over unvisited
## neighbours, then the shortest way to the exit beacon), plays each node's event, the node's other POI half the time, stubs fights as
## won or fled, and docks at every station that sells fuel on the way.
## The player's policy, the same before and after a change to the economy:
## - Every jump pays the real jump cost. With no fuel it waits for a passing trader (up to `waits` times, the trader's event played),
##   then makes a drift jump (no fuel, 15 hull integrity; hull is repaired at the next station while credits last), and only with too
##   little hull for that calls the tow (back to the region start, 2 fuel, 2 tide steps).
## - At a station with fuel on sale it buys up to `buy_to` fuel while credits last (the stock a visit has, where there is one). With
##   less fuel than the way to the exit needs (and MARGIN to spare) it heads for the region's fuel station if it can reach it on what it
##   has (the map shows a station's beacon).
## - In an event it takes the choice with the most fuel in it while its fuel is below GREEDY_BELOW, else a random open one.
## - At the exit it crosses into a region whose station sells fuel when it has the choice.
## - Debris: each node visited is `fly_s` seconds of flight with an intake drawing `per_min` pieces a minute; the share of them that
##   are fuel canisters is the sector's own (its density and theme multipliers on data/debris.json).

const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Content = preload("res://scripts/data/content.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Regions = preload("res://scripts/space/regions.gd")

const GREEDY_BELOW := 5  ## below this much fuel the player picks the choice with the most fuel
const MARGIN := 2  ## a prudent player heads for a station that sells fuel when it has less than the way to the exit plus this much
const MAX_PAGES := 12
const STAGES := 8

var drift := true  ## false: a player who never makes a drift jump (the tow is the only way out)
var nodes := 3  ## nodes visited per stage before heading for the exit
var stock: Array = []  ## what-if: fuel on sale a visit, [least, most] (empty: data/drift.json)
var start := -1  ## fuel the run starts with (-1: the larger of what the ship carries and data/drift.json fuel.start)
var buy_to := 12  ## a sensible player tops up to this much fuel at a station
var waits := 1  ## times the player waits for a trader before calling the tow
var fly_s := 75.0  ## seconds of flight (an intake drawing pieces) per node visited
var per_min := 4.0  ## pieces an intake draws a minute (a Net Mouth: tests/test_drift_debris.gd measures about 3)
var _pick := RandomNumberGenerator.new()
var _c: Campaign
var _row := {}


## Run `i` (a seed) with `design`. Returns {stages (rows: start, end, jumps, from {start/stations/events/debris/tow/trader}), tows, waits, jumps,
## drifted (false), stuck}.
func run(i: int, design: String) -> Dictionary:
	_pick.seed = 7777 + i * 31
	_c = Campaign.new(9000 + i)
	if not stock.is_empty() and _c.cfg["fuel"].has("stock"):  # what-if: a different stock a visit
		_c.cfg["fuel"]["stock"] = stock
	var ship = Ship.from_design(design)
	if start >= 0:
		ship.inventory.counts["fuel"] = start
	else:  # as a run begins (run_start.gd fuel_up): at least fuel.start of data/drift.json
		ship.inventory.counts["fuel"] = maxi(ship.inventory.count("fuel"), int(_c.cfg["fuel"]["start"]))
	Jobs.spawn_crew(ship)
	var out := {"stages": [], "tows": 0, "waits": 0, "drifts": 0, "jumps": 0, "stuck": false}
	var guard := 0
	while _c.stage <= mini(_c.stages(), STAGES) and guard < 400:
		guard += 1
		var stage := _c.stage
		_row = {"start": ship.inventory.count("fuel"), "credits": ship.inventory.count("credits"), "end": 0, "jumps": 0, "tows": 0, "from": {"stations": 0, "events": 0, "debris": 0, "tow": 0}}
		_play_stage(ship, out)
		_row["end"] = ship.inventory.count("fuel")
		out["stages"].append(_row)
		if not _cross(ship) or _c.stage == stage:
			break
	out["jumps"] = 0
	for r in out["stages"]:
		out["jumps"] += int(r["jumps"])
	return out


func _fuel(ship) -> int:
	return ship.inventory.count("fuel")


func _play_stage(ship, out: Dictionary) -> void:
	var seen := {_c.current: true}
	_arrive(ship)
	var steps := 0
	while seen.size() < nodes and steps < 40:
		steps += 1
		if not _refuel_trip(ship, out):
			return
		var open: Array = _c.neighbours(_c.current).filter(func(o): return not seen.has(o) and _c.node(o)["type"] != "gate")
		if open.is_empty():
			open = _c.neighbours(_c.current).filter(func(o): return _c.node(o)["type"] != "gate")
		if open.is_empty():
			break
		var to: String = open[_pick.randi() % open.size()]
		if not _go(ship, to, out):
			return
		if not seen.has(to):
			seen[to] = true
			_arrive(ship)
	var guard := 0
	while _c.current != _c.drift.exit_id() and guard < 60:
		guard += 1
		if not _refuel_trip(ship, out):
			return
		var path := _path_to_exit()
		if path.is_empty():
			return
		if not _go(ship, path[0], out):
			return
		if _c.current != _c.drift.exit_id():
			_arrive(ship)


## One jump to `to`: waits for a trader, then the tow, when there is not the fuel for it. False when the run cannot go on.
func _go(ship, to: String, out: Dictionary) -> bool:
	var tries := 0
	while _c.jump_block(to, ship, false) != "":
		tries += 1
		if tries > 6:
			out["stuck"] = true
			return false
		if _c.jump_block(to, ship, false) != Campaign.NO_FUEL:
			return false
		if tries <= waits and _fuel(ship) < _c.jump_fuel(ship) and _fuel(ship) == 0:
			var w := _c.wait(ship)
			out["waits"] += 1
			if w["ok"]:
				_chain(w["event"], ship)
			continue
		if _fuel(ship) == 0 and drift and _c.jump_block(to, ship, true) == "":
			var d := _c._jump_now(to, ship, true)
			out["drifts"] += 1
			if d["ok"]:
				_row["jumps"] += 1
			return bool(d["ok"])
		if _fuel(ship) == 0:
			var t := _c.tow(ship)
			if not t["ok"]:
				out["stuck"] = true
				return false
			out["tows"] += 1
			_row["tows"] += 1
			_row["from"]["tow"] += Campaign.TOW_FUEL
			_arrive(ship)
			return true  # (the tow moved the ship: the caller plans from where it is)
		out["stuck"] = true  # (some fuel but not enough for a jump: a fractional cost; buy or wait are not modelled)
		return false
	var r := _c._jump_now(to, ship, false)
	if r["ok"]:
		_row["jumps"] += 1
	return bool(r["ok"])


## With LOW fuel or less: the way to the region's station that sells fuel, flown if the fuel in the hold covers it. False when the run is stuck.
func _refuel_trip(ship, out: Dictionary) -> bool:
	if _fuel(ship) >= _path_to_exit().size() + MARGIN:  # enough for the way out and a little to spare
		return true
	var goal := ""
	for n in _c.drift.nodes:
		var id := str(n["id"])
		var st: Dictionary = _c.station_cfg(id)
		if not st.is_empty() and st["services"].has("fuel") and _c.dock_block(id) == "":
			goal = id
	if goal == "" or goal == _c.current:
		return true
	var path := _path(goal)
	if path.is_empty() or path.size() > _fuel(ship):
		return true
	for to in path:
		if not _go(ship, to, out):
			return false
		_arrive(ship)
	return true


func _path_to_exit() -> Array:
	return _path(_c.drift.exit_id())


func _path(goal: String) -> Array:
	var came := {_c.current: ""}
	var queue: Array = [_c.current]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at == goal:
			var path := []
			while at != _c.current:
				path.push_front(at)
				at = came[at]
			return path
		for o in _c.neighbours(at):
			if not came.has(o) and _c.node(o)["type"] != "gate":
				came[o] = at
				queue.append(o)
	return []


## The node's own event, a station's fuel, the debris of the flight, and one other POI of the node's sector half the time.
func _arrive(ship) -> void:
	if _c.at_exit():
		return
	var a := _c.arrive(ship)
	if not a["refused"].is_empty() or not a["event"].is_empty():
		_chain(a["event"], ship)
	_dock(ship)
	_debris(ship)
	var s = _c.current_sector()
	var others: Array = s.pois.filter(func(p): return not p["main"] and p["state"] == Sector.NEW and str(p["event_type"]) != "")
	if not others.is_empty() and _pick.randf() < 0.5:
		var poi: Dictionary = others[_pick.randi() % others.size()]
		_chain(_c.events.pick(_c, {"id": _c.current, "type": str(poi["event_type"]), "place": ""}, ship), ship)


## At a station that sells fuel: buy up to BUY_TO while credits last (and the station has any).
func _dock(ship) -> void:
	var st: Dictionary = _c.station_cfg(_c.current)
	if st.is_empty() or _c.dock_block(_c.current) != "" or not st["services"].has("fuel"):
		return
	_row["docks"] = int(_row.get("docks", 0)) + 1
	if st["services"].has("repair"):
		_c.repair(ship, _c.current)  # (no hull pool since the structure rework: it mends every damaged block, when there is any)
	while _fuel(ship) < buy_to:
		var r := _c.buy_fuel(ship, _c.current, 1)
		if not r["ok"]:
			break
		_row["from"]["stations"] += 1
		_row["bought"] = int(_row.get("bought", 0)) + 1


## The fuel canisters an intake draws in the flight at this node: `pieces` draws, each a canister with the sector's share.
func _debris(ship) -> void:
	var cfg: Dictionary = _c.current_sector().debris_cfg(Content.read(DriftDebris.PATH))
	var total := 0.0
	var fuel_w := 0.0
	for t in cfg["types"]:
		total += float(t["weight"])
		if t["id"] == "fuel_canister":
			fuel_w = float(t["weight"])
	var pieces := fly_s / 60.0 * per_min
	var n := int(pieces) + (1 if _pick.randf() < pieces - floorf(pieces) else 0)
	for k in n:
		if _pick.randf() < fuel_w / maxf(total, 0.001):
			ship.inventory.add("fuel", 1)
			_row["from"]["debris"] += 1


func _chain(ev: Dictionary, ship) -> void:
	var queue: Array = [ev]
	var pages := 0
	while not queue.is_empty() and pages < MAX_PAGES:
		var e: Dictionary = queue.pop_front()
		if e.is_empty():
			continue
		pages += 1
		var view := _c.events.choice_view(e, _c, ship, _c.node(_c.current))
		var open: Array = view.filter(func(v): return not v["grey"])
		if open.is_empty():
			continue
		var v: Dictionary = open[_pick.randi() % open.size()]
		if _fuel(ship) < GREEDY_BELOW:
			var best := 0.0
			for w in open:
				var g := _fuel_in(e, int(w["index"]))
				if g > best:
					best = g
					v = w
		var before := _fuel(ship)
		var r := _c.events.choose(e, int(v["index"]), _c, ship, _c.node(_c.current))
		if not r["ok"]:
			continue
		_row["from"]["events"] += _fuel(ship) - before
		if str(r["fight"]) != "":
			var res := {"state": "won" if _pick.randf() < 0.7 else "fled", "enemy": r["fight"], "threat": 2}
			var done := _c.fight_done(res, ship, r["after_win"])
			if done["goto"] != "" and _c.events.has(done["goto"]):
				queue.append(_c.events.get_event(done["goto"]))
		elif str(r["goto"]) != "" and _c.events.has(r["goto"]):
			queue.append(_c.events.get_event(r["goto"]))


## The fuel choice `index` of `e` gives on average (its outcomes by weight).
func _fuel_in(e: Dictionary, index: int) -> float:
	var total := 0.0
	var got := 0.0
	for o in e["choices"][index].get("outcomes", []):
		var w := float(o.get("weight", 1.0))
		total += w
		var eff = o.get("effects", {})
		if eff is Dictionary and eff.get("items") is Dictionary:
			got += w * float(eff["items"].get("fuel", 0))
	return got / total if total > 0.0 else 0.0


func _cross(ship) -> bool:
	if _c.is_final():
		return false
	_c.current = _c.drift.exit_id()
	_c.visited[_c.current] = true
	_c._enter(_c.current, ship)
	if _c.warden_up():
		_c.flags[str(_c.warden["flag"])] = true
	var offers: Array = _c.region_offers()
	if offers.is_empty():
		return false
	var pick: String = offers[_pick.randi() % offers.size()]
	var fuelled: Array = offers.filter(func(r): return _sells_fuel(str(r)))
	if not fuelled.is_empty():  # a sensible player crosses into a region whose station sells fuel when there is a choice
		pick = fuelled[_pick.randi() % fuelled.size()]
	return bool(_c.cross(pick, ship)["ok"])


## Does the station of region `id` sell fuel?
func _sells_fuel(id: String) -> bool:
	for p in Regions.get_region(id).get("places", []):
		if str(p.get("type", "")) == "station":
			return _c.station_cfg(str(p["id"])).get("services", []).has("fuel")
	return false
