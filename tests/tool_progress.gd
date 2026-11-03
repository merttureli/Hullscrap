extends SceneTree
## Not a test (the runner only loads test_*.gd). The progression bot (Beta 3, track `progress`): a seeded, headless "sensible player" that
## drives a real campaign (campaign.gd, sector.gd, events, stores, the fabricator, the build session, the arena) through all 8 stages, and
## records, per stage, what the ship earned, spent and became, and how its fights went.
##   godot --headless --path . --script res://tests/tool_progress.gd [-- key=value ...]
## Keys: seeds (runs per ship, default 10), first (first seed, default 0), ships (starter ids, default the three open ones), policy (ladder,
## guns, turtle or idle; default ladder), stages (default 8), stay (seconds of debris collecting per node, default 90), nodes (nodes
## visited per stage, default 7), pois (POIs flown to per node besides the main one, default 5), jobs (processes, default 3), rows (write this run's rows there: JSON), out (write the report there),
## merge (row files to report on instead of playing), dump (write all rows there, JSON), v=1 (log each run).
## What the player does, per stage: it visits `nodes` nodes (a wander over unvisited neighbours, a station within 3 jumps once, then the way
## to the exit); at each node it plays every POI's event (a value-maximising choice that shuns fights rated 4+ skulls) and the ambient
## contacts, collects debris for `stay` seconds with the real intakes in the real DriftDebris (flying upstream at half the cruise terminal
## speed), then spends what it has by the policy's ladder (`next_intent`): intake, guns, shield / medbay, engines (so the ship does not fall behind its
## own mass), fabricator level, laser cutter and titanium, tier-2 parts as the blueprints allow, armour last. Parts are crafted when the recipe is known and
## the fabricator can run it, else bought when docked. At a station it sells the surplus of the common materials (a credit each), mends the hull, buys fuel.
## A blueprint on a salvage page is worth more than a part. A Trader's or Store's small shop is visited too (it buys the blueprints it lacks, keeping the toll and 40 credits),
## a dock tops the hold up to TANK fuel, and a part a fight wrecked is replaced when the ship cannot do without it (a helm: no flying; a reactor: the power margin under 0).
## It builds on the real ship through BuildSession (a part goes on a free spot, else in a new annex room; cables are laid; power is added).
## Fights run through the real arena, as tests/tool_balance.gd does, on the ship itself: its blocks keep their damage (structure.gd), the crew and the drone
## mend them in ShipSim time between fights (mend()), a station repairs the rest for credits. A fight is left (the 10 s jump spool) when the structure is under 30% of the way to the wreck line. The exit
## warden's toll is paid when it is affordable (scrap is sold for it on a trip to a station, which keeps the toll's credits), else fought (up to three rounds, with a trip to a station between). The output rows are one dictionary
## per run: its stages carry the ship before and after, the fights (rating, length, hull), the flows of every resource by source and the craft census.
## Not modelled: the real flying and aiming of a human, crew commands, boarding, the Hollow tide's pursuit (its debris thinning is, through the sector).

const Ship = preload("res://scripts/ship/ship.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Helm = preload("res://scripts/space/helm.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const RunStart = preload("res://scripts/space/run_start.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Balance = preload("res://tests/tool_balance.gd")
const Wardens = preload("res://scripts/space/wardens.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Shops = preload("res://scripts/space/shops.gd")
const Flight = preload("res://scripts/sim/flight.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const FIGHT_CAP := 180.0  ## simulated seconds before a fight is called a stand-off (the player breaks away); a warden gets WARDEN_CAP
const WARDEN_CAP := 300.0
const SAMPLE_S := 30.0  ## seconds of debris really simulated per node; the yield is scaled up to the stay
const STARTERS: Array[String] = ["starter_rustbucket", "starter_courier", "starter_prism"]
const WINS: Array[String] = ["won", "captured", "spared"]
const SEED_BASE := 9000
const TANK := 14  ## the fuel a dock tops the hold up to (fuel_up)
## What things are worth to the player (credits), for the choice of an event row and a salvage pick.
const WORTH := {"scrap": 0.5, "copper": 1.5, "polymer": 1.5, "titanium": 6.0, "silicon": 8.0, "crystal": 18.0, "plasma_cell": 25.0, "nanite_paste": 60.0, "credits": 1.0, "fuel": 8.0, "missile": 3.0, "steel": 5.0}
const SKULL_COST := {0: 0.0, 1: 5.0, 2: 25.0, 3: 90.0, 4: 700.0, 5: 3000.0}  ## what meeting a fight of that many skulls is worth, in credits
## Per policy: the targets by stage (index stage - 1). guns: powered weapons, layers: shield layers, fab: fabricator level, intakes, armour:
## cells of armour tile, medbay: want one, cutter: want the laser cutter once the fab is level 2.
const POLICIES := {
	"ladder": {"guns": [3, 4, 5, 6, 6, 7, 8, 8], "layers": [1, 1, 2, 2, 3, 3, 4, 4], "fab": [1, 2, 2, 3, 3, 3, 4, 4], "intakes": [1, 1, 2, 2, 2, 3, 3, 3], "armour": [0, 20, 40, 70, 100, 130, 160, 200], "medbay": true, "cutter": true},
	"guns": {"guns": [4, 6, 8, 10, 12, 14, 16, 18], "layers": [0, 0, 0, 0, 0, 0, 0, 0], "fab": [1, 1, 1, 1, 1, 1, 1, 1], "intakes": [1, 1, 1, 1, 1, 1, 1, 1], "armour": [0, 0, 0, 0, 0, 0, 0, 0], "medbay": false, "cutter": false},
	"turtle": {"guns": [2, 2, 2, 3, 3, 3, 4, 4], "layers": [1, 2, 3, 4, 5, 6, 7, 8], "fab": [1, 1, 2, 2, 2, 2, 2, 2], "intakes": [1, 1, 2, 2, 2, 2, 2, 2], "armour": [30, 70, 110, 150, 190, 230, 270, 310], "medbay": true, "cutter": false},
	"idle": {"guns": [0, 0, 0, 0, 0, 0, 0, 0], "layers": [0, 0, 0, 0, 0, 0, 0, 0], "fab": [1, 1, 1, 1, 1, 1, 1, 1], "intakes": [1, 1, 1, 1, 1, 1, 1, 1], "armour": [0, 0, 0, 0, 0, 0, 0, 0], "medbay": false, "cutter": false},
}

var args := {}
var rows: Array = []
var policy := "ladder"
var stages_n := 8
var stay := 90.0
var nodes_n := 7
var verbose := false
var weapons: Weapons
var _pick := RandomNumberGenerator.new()
var _reserve := 0  # credits a dock leaves alone: the warden's toll (and 40), on the trips made to sell for it
var _carry := {}  # item -> the fraction of a unit the scaled debris yield has not paid yet
# the state of the run being played
var c: Campaign
var ship: Ship
var run := {}
var st := {}  # the record of the stage being played
var _docked := ""  # the node whose station the ship is docked at ("" when not)
var _skip := {}  # intents that failed in this build phase
var _armour0 := 0  # the armour cells the starter had
var _engines0 := 0  # the engines the starter had: the ladder adds at most 1 + stage / 2 more
var _accel0 := 0.0  # the acceleration the starter had: the ladder adds engines before the ship falls far behind it
var _no_annex := {}  # size -> the ship's signature when no annex spot was found (the search is slow: not repeated for the same ship)
var _shop := Rect2i()  # the inner floor of the workshop annex of this run (empty until one is built)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	policy = str(args.get("policy", policy))
	stages_n = int(args.get("stages", stages_n))
	stay = float(args.get("stay", stay))
	nodes_n = int(args.get("nodes", nodes_n))
	verbose = args.has("v")
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	if args.has("merge"):
		for path in str(args["merge"]).split(","):
			rows.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
	elif int(args.get("jobs", 3)) > 1 and not args.has("shard"):
		_fan_out(int(args.get("jobs", 3)))
	else:
		weapons = Weapons.new()
		var ids: Array = Array(str(args["ships"]).split(",")) if args.has("ships") else STARTERS
		var seeds := int(args.get("seeds", 10))
		var first := int(args.get("first", 0))
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var k := 0
		for id in ids:
			for s in seeds:
				k += 1
				if (k - 1) % shard[1] != shard[0]:
					continue
				var r := play("res://data/ships/%s.json" % id, str(id), first + s)
				rows.append(r)
				if verbose or args.has("rows"):
					print("%s #%d: %s at stage %d (%s), %d min, %d s" % [id, first + s, r["end"], r["end_stage"], r["cause"], roundi(r["minutes"]), (Time.get_ticks_msec() - t0) / 1000])
		if args.has("rows"):
			_write(str(args["rows"]), JSON.stringify(rows))
			quit(0)
			return
	if args.has("dump"):
		_write(str(args["dump"]), JSON.stringify(rows))
	var text := report()
	if args.has("out"):
		_write(str(args["out"]), text)
	print(text)
	print("progress: %d runs in %.0f s" % [rows.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["seeds", "first", "ships", "policy", "stages", "stay", "nodes"]:
		if args.has(key):
			pass_on.append("%s=%s" % [key, args[key]])
	for k in jobs:
		var path := OS.get_cache_dir().path_join("hullscrap_progress_%d_%d.json" % [OS.get_process_id(), k])
		files.append(path)
		var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_progress.gd", "--", "shard=%d/%d" % [k, jobs], "rows=" + path] + pass_on
		pids.append(OS.create_process(OS.get_executable_path(), argv))
	print("progress: %d processes %s" % [jobs, str(pids)])
	while pids.any(func(p): return OS.is_process_running(p)):
		OS.delay_msec(500)
	for path in files:
		var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if got is Array:
			rows.append_array(got)
		else:
			printerr("progress: a shard wrote nothing: " + path)
		DirAccess.remove_absolute(path)


# --- one run ---------------------------------------------------------------------------------------

## Play one campaign of `seed_index` with the starter at `path`. Returns the run record.
func play(path: String, id: String, seed_index: int) -> Dictionary:
	_pick.seed = 777 + seed_index * 31
	_carry.clear()
	_shop = Rect2i()
	_no_annex.clear()
	c = Campaign.new(SEED_BASE + seed_index)
	ship = Ship.from_design(path)
	RunStart.apply_ship(ship, {}, null)  # the start of a real run: fuel.start fuel, recipes.json start_known, the drone (a design's own cargo has 6 fuel)
	Jobs.spawn_crew(ship)
	ship.refresh()
	_armour0 = int(stats_now()["armour"])
	_accel0 = float(Sector.flight_numbers(ship)["accel"])
	_engines0 = int(stats_now()["engines"])
	run = {"ship": id, "seed": seed_index, "policy": policy, "end": "won", "end_stage": 0, "cause": "", "minutes": 0.0, "stages": []}
	var guard := 0
	while c.stage <= mini(c.stages(), stages_n) and guard < 60:
		guard += 1
		var alive := play_stage()
		if not alive:
			return run
		if not cross():
			run["end"] = "died" if run["cause"] != "" else "stuck"
			if run["cause"] == "":
				run["cause"] = "no way out of stage %d (warden %s, %d skulls)" % [c.stage, st.get("warden", "?"), int(st.get("warden_skulls", 0))]
			run["end_stage"] = c.stage
			return run
	run["end_stage"] = mini(c.stage - 1, stages_n)
	return run


func new_stage() -> Dictionary:
	var rec := {"stage": c.stage, "region": c.region_id, "nodes": 0, "jumps": 0, "minutes": 0.0, "fights": [], "flow": {}, "pois": 0, "dock": 0, "fuel_bought": 0, "drift_jumps": 0, "tows": 0,
		"salvage": [], "bp_list": [], "crafted": {}, "installed": [], "failed": {}, "toll": 0, "warden": "", "intake_pieces": 0, "shops": 0, "seen": [], "dens": 0.0, "press": 0.0, "hollow": 0, "dens_n": 0, "slice_new": 0, "slice_old": 0, "speed_sum": 0.0, "fab_max": 0, "peak": {}}
	rec["start"] = snapshot()
	return rec


## One stage. False when the run ended (the ship was wrecked).
func play_stage() -> bool:
	st = new_stage()
	run["stages"].append(st)
	st["j0"] = c.jumps
	var seen := {c.current: true}
	if not visit_node():
		return end_stage(false)
	var steps := 0
	var docked_here := false
	while seen.size() < nodes_n and steps < 14:
		steps += 1
		var weak: bool = Structure.wreck_margin(ship) < 0.55
		var urgent: bool = ship.inventory.count("fuel") < 3 or weak
		if (urgent or not docked_here) and c.station_cfg(c.current).is_empty():
			var stn := nearest_station(6 if urgent else 3)
			if stn != "" and (urgent or ship.inventory.count("fuel") < 4 or Structure.missing_hp(ship) > 30.0 or ship.inventory.count("credits") > 200):
				for hop in path_to(stn):
					if not go(hop):
						return end_stage(false)
				seen[c.current] = true
				docked_here = true
				if not visit_node():
					return end_stage(false)
				continue
		var open: Array = c.neighbours(c.current).filter(func(o): return not seen.has(o) and c.node(o)["type"] != "gate")
		if open.is_empty():
			open = c.neighbours(c.current).filter(func(o): return c.node(o)["type"] != "gate")
		if open.is_empty():
			break
		var to: String = open[_pick.randi() % open.size()]
		if not go(to):
			return end_stage(false)
		if not seen.has(to):
			seen[to] = true
			if not visit_node():
				return end_stage(false)
		elif not c.station_cfg(c.current).is_empty():
			docked_here = true
	if c.warden_up() and ship.inventory.count("credits") < Wardens.toll_of(c.warden) + 40 and ship.inventory.count("scrap") > 900:
		var stn := nearest_station(6)  # sell the surplus for the toll before going to the beacon
		if stn != "":
			for hop in path_to(stn):
				if not go(hop):
					return end_stage(false)
			_reserve = Wardens.toll_of(c.warden) + 40
			dock()
			_reserve = 0
			_docked = ""
	for hop in path_to(c.drift.exit_id()):
		if not go(hop):
			return end_stage(false)
	return end_stage(true)


func end_stage(alive: bool) -> bool:
	st["jumps"] = c.jumps - int(st["j0"])
	st["end"] = snapshot()
	if not alive:
		run["end"] = "died" if run["cause"] != "" else "stuck"
		if run["cause"] == "":
			run["cause"] = "cannot move (no fuel or no lane)"
		run["end_stage"] = c.stage
	run["minutes"] = float(run["minutes"]) + float(st["minutes"])
	return alive


## The jump to `to` (one lane). Buys fuel when docked, drifts (hull) or is towed when there is none. False when the ship cannot move.
func go(to: String) -> bool:
	if ship.inventory.count("fuel") < 1 + int(c.jump_cost(ship) > 100):
		fuel_up()
	var r: Dictionary = c._jump_now(to, ship, false)
	if not r["ok"] and r["why"] == Campaign.NO_FUEL:
		if Structure.wreck_margin(ship) > 0.25:
			r = c._jump_now(to, ship, true)
			st["drift_jumps"] += 1
		else:
			var t: Dictionary = c.tow(ship)
			st["tows"] += int(t["ok"])
			r = {"ok": false}
			return bool(t["ok"]) and go(to)
	if r["ok"]:
		st["minutes"] += 0.4
	return bool(r["ok"])


## The nodes from here to `goal` (not counting here), by lanes, avoiding the dark gates.
func path_to(goal: String) -> Array:
	var came := {c.current: ""}
	var queue: Array = [c.current]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at == goal:
			var out := []
			while at != c.current:
				out.push_front(at)
				at = came[at]
			return out
		for o in c.neighbours(at):
			if not came.has(o) and c.node(o)["type"] != "gate":
				came[o] = at
				queue.append(o)
	return []


## The nearest station node within `hops` lanes ("" when none).
func nearest_station(hops: int) -> String:
	var dist := {c.current: 0}
	var queue: Array = [c.current]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at != c.current and not c.station_cfg(at).is_empty() and c.dock_block(at) == "":
			return at
		if dist[at] >= hops:
			continue
		for o in c.neighbours(at):
			if not dist.has(o) and c.node(o)["type"] != "gate":
				dist[o] = dist[at] + 1
				queue.append(o)
	return ""


## One go at the warden: pay the toll if it is affordable and worth it, else break through (two tries inside the round). False when the ship was wrecked.
func warden_round() -> bool:
	st["warden"] = str(c.warden.get("name", ""))
	var ev: Dictionary = c.warden_event(ship)
	var pay := -1
	var brk := -1
	for v in c.events.choice_view(ev, c, ship, c.node(c.current)):
		if str(v["text"]).begins_with("Pay the toll") and not v["grey"]:
			pay = int(v["index"])
		elif str(v["text"]).begins_with("Break through"):
			brk = int(v["index"])
	var foe: Ship = Session.load_ship(str(c.warden["spec"]))
	var th := Threat.rate(foe, ship)
	st["warden_skulls"] = th["skulls"]
	st["warden_ratio"] = th["ratio"]
	st["toll"] = Wardens.toll_of(c.warden)
	var pick := pay if pay >= 0 else brk  # a toll that can be paid is paid: the fight pays 50 credits a stage and costs hull
	var tries := 0
	while c.warden_up() and tries < 2:
		tries += 1
		var before := inv_copy()
		var r: Dictionary = c.events.choose(ev, pick, c, ship, c.node(c.current))
		flow("events", before)
		if not r["ok"]:
			return false
		if str(r["fight"]) != "":
			var next := fight_path(str(r["fight"]), r["after_win"], "warden")
			if next.get("dead", false):
				return false
		pick = brk  # (a toll that failed to clear it, or a stand-off: break through again)
	return true


## Back to the nearest station (6 lanes at most) to mend, sell and build, then to the exit again. False when there is none.
func regroup() -> bool:
	var exit_id: String = c.current
	var stn := nearest_station(6)
	if stn == "":
		return false
	for hop in path_to(stn):
		if not go(hop):
			return false
	_reserve = Wardens.toll_of(c.warden) + 40 if c.warden_up() else 0
	dock()
	_reserve = 0
	_docked = ""
	for hop in path_to(exit_id):
		if not go(hop):
			return false
	st["minutes"] += 1.0
	return c.current == exit_id


## Cross to the next region from the exit beacon: the warden first (toll or fight; up to three rounds, with a trip to a station between them
## to mend and sell). False when it cannot.
func cross() -> bool:
	if c.is_final():
		return true
	if c.current != c.drift.exit_id():
		return false
	c.visited[c.current] = true
	var rounds := 0
	while c.warden_up() and rounds < 3:
		rounds += 1
		st["warden_rounds"] = rounds
		if not warden_round():
			return false
		if c.warden_up() and (rounds >= 3 or not regroup()):
			return false
	var offers: Array = c.region_offers()
	if offers.is_empty():
		return false
	var best := ""
	for o in offers:  # the region on offer with the lowest danger: a cautious player
		if best == "" or float(Content.entry("regions", str(o)).get("danger", 1.0)) < float(Content.entry("regions", best).get("danger", 1.0)):
			best = str(o)
	var r: Dictionary = c.cross(best, ship)
	return bool(r["ok"])


# --- a node ----------------------------------------------------------------------------------------

## Arrive at the current node, play its sector (the POIs, the ambient contacts, the debris), spend. False when the ship was wrecked.
func visit_node() -> bool:
	st["nodes"] += 1
	if c.at_exit():
		return true
	var s = c.current_sector()
	s.set_flight(ship)
	var before := inv_copy()
	_docked = ""
	for poi in poi_plan(s):
		if poi["state"] != Sector.NEW:
			continue
		var res: Dictionary = s._event_for(c, ship, poi)
		st["pois"] += 1
		st["minutes"] += 0.35
		if not res["event"].is_empty() and not chain(res["event"]):
			return false
		var docks := not c.station_cfg(c.current).is_empty() and c.dock_block(c.current) == "" and (str(poi["type"]) in ["station", "store", "trader"] or bool(poi.get("main", false)))
		if docks:
			dock()
		if bool(s.cfg["poi_types"].get(str(poi["type"]), {}).get("shop", false)):
			shop_visit(c.shop_id(c.current, str(poi["id"])))
		s.resolve(str(poi["id"]))
	_docked = ""
	if not collect(s, stay):
		return false
	flow("events", before)
	build_phase()
	return true


## The POIs of sector `s` the player flies to: the main one, then up to `pois` others, beacons and trade first, nests last.
func poi_plan(s) -> Array:
	var rank := {"station": 0, "store": 0, "trader": 1, "distress": 2, "mining_field": 3, "wreck": 3, "abandoned_station": 4, "unknown": 4, "quest": 4, "pirate_nest": 6}
	var mains: Array = s.pois.filter(func(p): return bool(p.get("main", false)))
	var others: Array = s.pois.filter(func(p): return not bool(p.get("main", false)))
	others.sort_custom(func(a, b): return int(rank.get(str(a["type"]), 5)) < int(rank.get(str(b["type"]), 5)))
	return mains + others.slice(0, int(args.get("pois", 5)))


## The scrap a slice of debris brings in with spawn.max_alive `cap` and spawn.flow_min `floor_v`, the ship flying at `speed`; what it took in is undone.
func paired_slice(s, pos0: Vector2, ang: float, piv: Vector2, cur: Vector2, speed: float, slice: float, cap: int, floor_v: float) -> int:
	var base: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	base["spawn"]["max_alive"] = cap
	base["spawn"]["flow_min"] = floor_v
	var dd2 = DriftDebris.new(hash([c.seed_value, c.jumps, st["nodes"]]), s.debris_cfg(base))
	var pos2 := pos0
	dd2.frame = Helm.frame_of(ship, pos2, ang, piv)
	dd2.frame_vel = -cur.normalized() * speed
	dd2.view_centre = dd2.frame * ship.world_pos
	dd2.prewarm(ship)
	var keep: Dictionary = ship.inventory.counts.duplicate()
	var t2 := 0.0
	while t2 < slice:
		pos2 += dd2.frame_vel * 0.5
		dd2.frame = Helm.frame_of(ship, pos2, ang, piv)
		dd2.view_centre = dd2.frame * ship.world_pos
		dd2.step(ship, 0.5)
		t2 += 0.5
	var got: int = ship.inventory.count("scrap") - int(keep.get("scrap", 0))
	for id in ship.inventory.counts.keys().duplicate():  # (undo what it took in)
		var extra: int = int(ship.inventory.counts[id]) - int(keep.get(id, 0))
		if extra != 0:
			ship.inventory.add(id, -extra)
	return got


## Collect debris for `seconds` in sector `s` with the real intakes: a SAMPLE_S slice is simulated and scaled up. The ambient contacts come while
## the ship stays. False when a fight wrecked the ship.
func collect(s, seconds: float) -> bool:
	var before := inv_copy()
	ship.refresh()
	s.set_flight(ship)
	var dd = DriftDebris.for_sector(s, hash([c.seed_value, c.jumps, st["nodes"]]))
	st["dens"] += float(s.density) * lerpf(1.0, float(s.cfg["pressure"]["debris"]), s.pressure) * (float(s.cfg["ambient"].get("hollow", {}).get("debris", 1.0)) if s.hollow else 1.0)
	st["press"] += float(s.pressure)
	st["hollow"] += int(s.hollow)
	st["dens_n"] += 1
	var terminal: float = float(s.accel) * 1.8 / maxf(float(s.damping), 0.01)
	var speed := clampf(0.5 * minf(terminal, float(s.max_speed) * 1.8), 60.0, 500.0)
	var cur: Vector2 = s.current_dir()
	var out_rot := 0
	var best_pull := -1.0
	for m in dd.intakes(ship):
		if float(m["pull"]) > best_pull:
			best_pull = float(m["pull"])
			out_rot = int(ship.components.instances[m["uid"]]["rot"])
	var lead: Vector2 = Vector2(Mounts.OUTWARD[posmod(out_rot, 4)])
	var ang := (-cur).angle() - lead.angle()  # the mouth leads into the stream
	var piv: Vector2 = Helm.pivot_of(ship.grid)
	var pos := Vector2(s.size * 0.5, s.size * 0.5)
	var pos0 := pos
	dd.frame = Helm.frame_of(ship, pos, ang, piv)
	dd.frame_vel = -cur.normalized() * speed
	dd.view_centre = dd.frame * ship.world_pos
	dd.prewarm(ship)
	var slice := minf(seconds, SAMPLE_S)
	var t := 0.0
	var inv_before: Dictionary = ship.inventory.counts.duplicate()
	while t < slice:
		pos += dd.frame_vel * 0.5  # the ship flies on through the stream
		dd.frame = Helm.frame_of(ship, pos, ang, piv)
		dd.view_centre = dd.frame * ship.world_pos
		dd.step(ship, 0.5)
		t += 0.5
	st["slice_new"] += ship.inventory.count("scrap") - int(inv_before.get("scrap", 0))
	st["speed_sum"] += speed
	if args.has("paired"):  # the same ship and sector with other debris numbers or another speed: what the cap and the floor, and the speed, are worth here
		st["slice_old"] += paired_slice(s, pos0, ang, piv, cur, speed, slice, 70, 5.0)  # (the numbers from before this track)
		for sp in [60.0, 250.0]:
			st["slice_new_%d" % int(sp)] = int(st.get("slice_new_%d" % int(sp), 0)) + paired_slice(s, pos0, ang, piv, cur, sp, slice, 140, 5.5)
			st["slice_old_%d" % int(sp)] = int(st.get("slice_old_%d" % int(sp), 0)) + paired_slice(s, pos0, ang, piv, cur, sp, slice, 70, 5.0)
	if args.has("dbg"):
		print("collect: mouths %d picked %d pieces %d rot %d ang %.2f speed %.0f cur %s dens %.2f" % [dd.mouth_count, dd.picked, dd.pieces.size(), out_rot, ang, speed, str(cur), float(s.density)])
	st["intake_pieces"] += int(dd.picked * seconds / maxf(slice, 1.0))
	st["mouths"] = dd.mouth_count
	# scale what the slice brought up to the stay: the remainder is paid as more of the same
	var scale := seconds / maxf(slice, 1.0) - 1.0
	for id in ship.inventory.counts.keys():
		var got: int = int(ship.inventory.counts[id]) - int(inv_before.get(id, 0))
		if got > 0 and scale > 0.0:
			var extra: float = float(got) * scale + float(_carry.get(id, 0.0))
			var whole := floori(extra)
			_carry[id] = extra - whole
			ship.inventory.add(id, whole)
	st["minutes"] += seconds / 60.0
	mend(seconds)
	flow("debris", before)
	# the contacts that come by while the ship stays
	var step := 30.0
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += step
		var made: Array = s.tick(step, ship)
		c.linger(step)
		for contact in made:
			if contact.get("state", "") != Sector.NEW:
				continue
			var res: Dictionary = s._event_for(c, ship, contact)
			var b2 := inv_copy()
			var alive: bool = res["event"].is_empty() or chain(res["event"])
			flow("events", b2)
			s.resolve(str(contact["id"]))
			if not alive:
				return false
	return true


# --- events ----------------------------------------------------------------------------------------

## Play an event and its follow-ups. False when a fight wrecked the ship.
func chain(ev: Dictionary) -> bool:
	var queue: Array = [ev]
	var pages := 0
	while not queue.is_empty() and pages < 14:
		var e: Dictionary = queue.pop_front()
		if e.is_empty():
			continue
		pages += 1
		if pages == 1:
			st["seen"].append(str(e.get("id", "")))
		var view: Array = c.events.choice_view(e, c, ship, c.node(c.current))
		var open: Array = view.filter(func(v): return not v["grey"])
		if open.is_empty():
			continue
		var pick: Dictionary = open[0]
		var best := -INF
		for v in open:
			var val := choice_value(e, int(v["index"]))
			if val > best + 0.001 or (absf(val - best) <= 0.001 and _pick.randf() < 0.5):
				best = val
				pick = v
		var before := inv_copy()
		var known0: Dictionary = ship.crafting.known.duplicate()
		var r: Dictionary = c.events.choose(e, int(pick["index"]), c, ship, c.node(c.current))
		if not r["ok"]:
			continue
		flow("events", before)
		if str(e.get("id", "")) == "salvage":
			var scan_offered := open.any(func(v): return str(v["text"]).begins_with("Scan"))
			st["salvage"].append({"rows": open.size(), "scan_offered": scan_offered, "took": str(pick["text"]).substr(0, 24)})
		for rid in ship.crafting.known:
			if not known0.has(rid):
				st["bp_list"].append("%s@%s" % [rid, str(e.get("id", ""))])
		if str(e.get("type", "")) == "debt" and ship.inventory.count("credits") > 400 and c.debt > 0:
			c.pay_debt(ship, mini(100, c.debt))
		if str(r["fight"]) != "":
			var next := fight(str(r["fight"]), r["after_win"], str(e.get("id", "")))
			if next.get("dead", false):
				return false
			if str(next.get("goto", "")) != "" and c.events.has(next["goto"]):
				queue.append(c.events.get_event(next["goto"]))
			if str(next.get("salvage_id", "")) != "":
				queue.append(next["salvage"])
		elif str(r["goto"]) != "" and c.events.has(r["goto"]):
			queue.append(c.events.get_event(r["goto"]))
	return true


## What a row of `ev` is worth to this player, in credits: the outcomes' items, hull, blueprints, crew, less what it costs and the fights it risks.
func choice_value(ev: Dictionary, index: int) -> float:
	var ch: Dictionary = ev["choices"][index]
	var outs: Array = ch.get("outcomes", []) if ch.get("outcomes") is Array else []
	var total := 0.0
	for o in outs:
		total += maxf(float(o.get("weight", 1.0)), 0.0)
	var v := 0.0
	for o in outs:
		var w := maxf(float(o.get("weight", 1.0)), 0.0) / maxf(total, 0.001)
		var eff: Dictionary = o.get("effects", {}) if o.get("effects") is Dictionary else {}
		v += w * effects_value(eff, ev)
	if c.events.pays(ch):
		for id in c.events.needs(ch):
			v -= item_worth(str(id)) * float(c.events.needs(ch)[id])
	return v


func effects_value(eff: Dictionary, ev: Dictionary) -> float:
	var v := 0.0
	var items: Dictionary = eff.get("items", {}) if eff.get("items") is Dictionary else {}
	for id in items:
		v += item_worth(str(id)) * float(items[id])
	if eff.has("blueprint"):  # (an id or a list of ids: events.gd reads both)
		for rid in (eff["blueprint"] if eff["blueprint"] is Array else [eff["blueprint"]]):
			v += blueprint_worth(str(rid))
	v += 4.0 * float(eff.get("hull", 0)) + 0.6 * float(eff.get("crew_hp", 0))
	v += 220.0 * (eff["recruit"].size() if eff.get("recruit") is Array else 0)
	v -= 260.0 * float(eff.get("lose_crew", 0) if not eff.get("lose_crew") is bool else (1 if eff["lose_crew"] else 0))
	v -= 0.15 * float(eff.get("debt", 0))
	if eff.has("rep") and eff["rep"] is Dictionary:
		for f in eff["rep"]:
			v += 3.0 * float(eff["rep"][f])
	if eff.has("fight"):
		var weak: bool = Structure.wreck_margin(ship) < 0.4
		v -= SKULL_COST[rate_fight(str(eff["fight"]))] * (4.0 if weak else 1.0) - 40.0 + (300.0 if weak else 0.0)
	if eff.has("ending"):
		v += 500.0
	if str(eff.get("goto", "")) != "":
		v += 5.0
	return v


## What learning recipe `rid` is worth: nothing if it is known; a blueprint is for good, so more than a part, and most for what the ladder is short of.
func blueprint_worth(rid: String) -> float:
	if ship.crafting.is_known(rid):
		return 0.0
	var out: String = str(ship.crafting.def(rid).get("output", {}).get("item", ""))
	var d: Dictionary = ship.components.def(out)
	if d.is_empty():
		return 70.0
	return 150.0 + 60.0 * float(int(d.get("tier", 1)) - 1) + (50.0 if wanted_now(out) else 0.0)


func item_worth(id: String) -> float:
	if WORTH.has(id):
		return float(WORTH[id])
	if ship.components.has(id):
		var d: Dictionary = ship.components.def(id)
		return float(Campaign.config()["values"]["tier"].get(str(d.get("tier", 1)), 40)) * (1.5 if wanted_now(id) else 1.0)
	return 10.0


## The skulls of the enemy a `fight` effect sends, against the ship as it is now.
func rate_fight(value: String) -> int:
	var path: String = c.fight_path(value, str(c.node(c.current)["type"]))
	var foe: Ship = Session.load_ship(path)
	if foe == null:
		return 3
	return int(Threat.rate(foe, ship)["skulls"])


# --- fights ----------------------------------------------------------------------------------------

## Let the crew and the drone mend for up to `seconds` of ShipSim time (they stop when every block is whole).
func mend(seconds: float) -> void:
	if Structure.missing_hp(ship) <= Structure.EPS:
		return
	var sim := ShipSim.new()
	sim.ships = [ship]
	var t := 0.0
	while t < seconds and Structure.missing_hp(ship) > Structure.EPS:
		sim.step(0.2)
		t += 0.2
	sim.free()


## Fight the enemy a `fight` effect names. Returns {dead, goto, salvage...}. Runs the real arena, then the campaign's fight_done and the salvage pick.
func fight(value: String, after_win: Dictionary, why: String) -> Dictionary:
	var path: String = c.fight_path(value, str(c.node(c.current)["type"]))
	return fight_path(path, after_win, why, value)


func fight_path(path: String, after_win: Dictionary, why: String, value := "") -> Dictionary:
	var enemy: Ship = Session.load_ship(path)
	var out := {"dead": false, "goto": "", "salvage": {}, "salvage_id": ""}
	if enemy == null:
		return out
	var player := ship  # the ship itself: its blocks keep what the fight does to them
	var th := Threat.rate(enemy, player)
	var gen: Dictionary = enemy.get_meta("shipgen", {})
	var rec := {"why": why, "faction": str(gen.get("faction", "?")), "size": str(gen.get("size", "?")), "budget": float(gen.get("budget", 0.0)), "skulls": th["skulls"], "ratio": th["ratio"],
		"p_power": th["player"]["power"], "e_power": th["enemy"]["power"], "p_dps": th["player"]["dps"], "e_dps": th["enemy"]["dps"], "p_ehp": th["player"]["ehp"], "e_ehp": th["enemy"]["ehp"],
		"e_weapons": gen.get("weapons", []).size(), "e_shields": gen.get("shields", []).size(), "warden": value != "tier" and why == "warden"}
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	var sess := Session.new()
	sess.start(player, enemy, 1 + c.jumps * 31 + int(st["nodes"]) * 7 + run["seed"])
	var me = sess.arena.ships[Session.PLAYER]
	var hull0: float = 100.0 * Structure.wreck_margin(me)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var n := 0
	var ticks := int((WARDEN_CAP if why == "warden" else FIGHT_CAP) * 60.0)
	var flee_at := -1
	while sess.state() == "fighting" and n < ticks:
		if flee_at < 0 and Structure.wreck_margin(me) < 0.3 and Structure.wreck_margin(sess.arena.ships[Session.ENEMY]) > 0.3:
			flee_at = n + int(Session.JUMP_SPOOL * 60.0)  # the player turns for the jump drive: ten seconds to survive
		if flee_at >= 0 and n >= flee_at:
			break
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n % SIM_EVERY == 0:
			sim.step(SIM_EVERY * STEP)
	var state := sess.state()
	if state == "fighting":
		state = "fled"  # a stand-off, or a jump away from a lost cause: the player breaks away
	var foe = a.ships[Session.ENEMY]
	rec["state"] = state
	rec["t"] = n * STEP
	rec["hull0"] = hull0
	rec["hull_max"] = 100.0
	rec["hull_after"] = 100.0 * Structure.wreck_margin(me)
	rec["foe_hull"] = Structure.wreck_margin(foe)
	st["fights"].append(rec)
	st["minutes"] += n * STEP / 60.0 + 0.5
	var res := {"state": state, "enemy": enemy, "threat": th["skulls"]}
	sim.free()
	var before := inv_copy()
	var done: Dictionary = c.fight_done(res, ship, after_win)
	flow("loot", before)
	if state != "lost":
		mend(60.0)
	if state == "lost":
		run["cause"] = "%s %s (%d skulls, ratio %.2f) at stage %d, jump %d" % [rec["faction"], rec["size"], th["skulls"], th["ratio"], c.stage, c.jumps]
		rec["fatal"] = true
		out["dead"] = true
		return out
	out["goto"] = done["goto"]
	if str(done["fight"]) != "":
		var chained := fight(str(done["fight"]), {}, why)
		if chained["dead"]:
			out["dead"] = true
			return out
	if state in ["won", "captured"]:
		var sal := Salvage.event_for(enemy, state, c, ship, null, int(th["skulls"]))
		if not sal.is_empty():
			out["salvage"] = sal
			out["salvage_id"] = "salvage"
	return out


# --- stores and stations ---------------------------------------------------------------------------

## Dock at the current node's station: repair the hull, buy fuel, hire a recruit, then build with the stock.
func dock() -> void:
	var id: String = c.current
	var cfg: Dictionary = c.station_cfg(id)
	if cfg.is_empty() or c.dock_block(id) != "":
		return
	_docked = id
	st["dock"] += 1
	st["minutes"] += 0.7
	var before := inv_copy()
	var services: Array = cfg.get("services", [])
	if services.has("sell"):  # the surplus of the common materials sells at a credit each: credits are what the hull, fuel and tolls are paid in
		var keep := {"scrap": 600 + 250 * c.stage, "copper": 250 + 80 * c.stage, "polymer": 120}
		if policy != "idle" and c.warden_up():  # the toll is paid in credits and scrap sells a credit each: sell what it takes, whatever stock a person keeps
			var short: int = Wardens.toll_of(c.warden) + 40 - ship.inventory.count("credits")
			if short > 0:
				keep["scrap"] = mini(int(keep["scrap"]), ship.inventory.count("scrap") - short)
		for item in keep:
			var extra: int = ship.inventory.count(item) - int(keep[item])
			if extra > 0 and ship.inventory.count("credits") < 2500:
				c.sell(ship, item, mini(extra, 2500 - ship.inventory.count("credits")))
	if services.has("repair"):  # every damaged block, or nothing: the price is for the lot
		var cost: int = c.repair_cost(ship, id)
		if cost > 0 and ship.inventory.count("credits") - _reserve >= cost:
			c.repair(ship, id)
	fuel_up()
	if services.has("recruit") and not c.offers.get(id, []).is_empty():
		var price: int = c.price(int(c.cfg["prices"]["recruit"]), c._station_faction(id), ship)
		if ship.inventory.count("credits") >= price + 100 + _reserve:
			c.recruit(ship, id, 0)
	flow("shop", before)
	build_phase()
	if c.debt > 0 and c.debt_running() and ship.inventory.count("credits") > 500:
		c.pay_debt(ship, mini(100, c.debt))


## A Trader's or Store's small shop: the player buys the blueprints it lacks, best first, while the credits stay over the toll and a cushion of 40
## (the Ledger's own). Nothing else is shopped for here. The idle policy builds nothing and buys nothing.
func shop_visit(sid: String) -> void:
	var menu: Dictionary = c.station_cfg(sid)
	if menu.is_empty() or policy == "idle":
		return
	st["shops"] += 1
	var before := inv_copy()
	var picks: Array = []
	for item in menu.get("stock", {}):
		var rid := str(item).trim_prefix(Shops.BLUEPRINT)
		if str(item).begins_with(Shops.BLUEPRINT) and ship.crafting.def(rid).size() > 0 and not ship.crafting.is_known(rid):
			picks.append([blueprint_worth(rid), str(item)])
	picks.sort_custom(func(x, y): return x[0] > y[0])
	var keep := (Wardens.toll_of(c.warden) if not c.warden.is_empty() else 0) + 40
	for pick in picks:
		var price: int = c.stock_price(sid, pick[1], ship)
		if price > 0 and ship.inventory.count("credits") - price >= keep and c.buy(ship, sid, pick[1])["ok"]:
			st["bp_list"].append("%s@shop" % str(pick[1]).trim_prefix(Shops.BLUEPRINT))
	flow("shop", before)


## Buy fuel at the dock: every unit on sale up to a tank that crosses a stage (TANK: this player makes 11 to 15 jumps a stage, so a tank of 9, the
## first value of this tool, could not cover one even when full), while the credits allow.
func fuel_up() -> void:
	if _docked == "" or not c.station_cfg(_docked).get("services", []).has("fuel"):
		return
	var want := TANK - ship.inventory.count("fuel")
	while want > 0 and ship.inventory.count("credits") > 30 + _reserve:
		var r: Dictionary = c.buy_fuel(ship, _docked, 1)
		if not r["ok"]:
			break
		st["fuel_bought"] += 1
		want -= 1


# --- the build ladder ------------------------------------------------------------------------------

func target(key: String) -> int:
	var t: Array = POLICIES[policy][key]
	var v := int(t[clampi(c.stage - 1, 0, t.size() - 1)])
	if key == "armour":
		return v + _armour0  # (a starter's hull has plates already: the target is on top of them)
	if v > 0 and key in ["guns", "layers"] and policy != "idle":
		v += clampi((ship.inventory.count("scrap") - 1200) / 600, 0, 4)  # a hold full of scrap buys more of the same
	return v


## Spend what the ship has by the ladder, until nothing more can be done.
func build_phase() -> void:
	_skip.clear()
	var guard := 0
	while guard < 14:
		guard += 1
		var it := next_intent()
		if it.is_empty():
			break
		var done := false
		var opts: Array = it["ids"]
		for id in opts:
			var got := procure(str(id), it["kind"] == "titanium")
			if got == "" and it["kind"] == "titanium":
				done = true  # a material: nothing to place (the loop comes back for more until the stock is 60)
				break
			if got == "":
				var why := install(str(id), it)
				if why == "":
					st["installed"].append([str(id), c.stage])
					done = true
					break
				var fkey: String = "%s:%s" % [why, it["kind"]]
				st["failed"][fkey] = int(st["failed"].get(fkey, 0)) + 1
				_skip[it["kind"]] = true
				break
		if not done:
			_skip[it["kind"]] = true
	var sn := stats_now()  # the stage's end is after its last fights, which wreck parts that stay wrecked: what the ship was at its best in between is the peak
	var pk: Dictionary = st["peak"]
	for key in ["guns", "layers", "intakes", "medbays", "armour", "fab"]:
		pk[key] = maxi(int(pk.get(key, 0)), int(sn[key]))
	pk["power"] = maxf(float(pk.get("power", 0.0)), float(Threat.power(ship, float(Threat.config()["player_aim"]))["power"]))
	pk["known"] = maxi(int(pk.get("known", 0)), ship.crafting.known.size())
	st["fab_max"] = int(pk["fab"])


## The next thing the policy wants, {kind, ids (best first)}, skipping the kinds that failed this phase. {} when it wants nothing.
func next_intent() -> Dictionary:
	ship.refresh()
	var snap := stats_now()
	if policy != "idle":  # upkeep: a part wrecked in a fight stays wrecked, and a person replaces what the ship cannot do without
		if not _skip.has("helm") and Flight.new().can_fly(ship.components, ship.power_state.get("powered", {})) == "no powered helm":  # (without one it cannot fly: collect() would be at its slowest)
			return {"kind": "helm", "ids": ranked(["helm"], "helm")}
		if not _skip.has("power") and margin() < 0.0:  # (a reactor gone leaves the workshop and the guns dark)
			return {"kind": "power", "ids": ranked(["reactor_mk2", "reactor_mk1", "reactor_scrap_mk1"], "reactor")}
	if not _skip.has("intake") and snap["intakes"] < target("intakes"):
		return {"kind": "intake", "ids": ranked(["intake_mk3", "intake_mk2", "intake_mk1", "net_mouth_scrap"], "intake")}
	if not _skip.has("gun") and snap["guns"] < target("guns"):
		return {"kind": "gun", "ids": ranked(gun_ids(), "gun")}
	if not _skip.has("shield") and snap["layers"] < target("layers") and snap["layers"] < 1 + (POLICIES[policy]["layers"][clampi(c.stage - 1, 0, 7)] if POLICIES[policy]["layers"][clampi(c.stage - 1, 0, 7)] > 1 else 0) * int(c.stage > 3):
		return {"kind": "shield", "ids": ranked(["shield_mk2", "shield_mk1", "shield_scrap_mk1", "shield_neon_mk1"], "shield")}
	if not _skip.has("medbay") and bool(POLICIES[policy]["medbay"]) and snap["medbays"] < 1:
		return {"kind": "medbay", "ids": ["medbay"]}
	if not _skip.has("shield2") and snap["layers"] < target("layers"):
		return {"kind": "shield2", "ids": ranked(["shield_mk2", "shield_mk1", "shield_scrap_mk1", "shield_neon_mk1"], "shield")}
	if not _skip.has("engine") and policy != "idle" and snap["engines"] < _engines0 + 1 + c.stage / 2 and float(Sector.flight_numbers(ship)["accel"]) < 0.75 * _accel0:
		return {"kind": "engine", "ids": ranked(["engine_mk3", "engine_mk2", "engine_mk1", "engine_scrap_mk3", "engine_scrap_mk2", "engine_scrap_mk1"], "engine")}
	if not _skip.has("fab") and snap["fab"] < target("fab"):
		var fab_ids := ["robot_arm"]
		if snap["fab"] >= 2:
			fab_ids = ["assembly_rig"] if snap["rigs"] < 1 else ["robot_arm"] if snap["arms"] < 2 else ["nanoforge"]
		return {"kind": "fab", "ids": fab_ids}
	if not _skip.has("cutter") and bool(POLICIES[policy]["cutter"]) and snap["fab"] >= 2 and snap["cutters"] < 1:
		return {"kind": "cutter", "ids": ["laser_cutter"]}
	if not _skip.has("titanium") and snap["cutters"] >= 1 and ship.crafting.is_known("titanium") and ship.inventory.count("titanium") < 60 and ship.inventory.count("scrap") > 700 + 100 * c.stage:
		return {"kind": "titanium", "ids": ["titanium"]}
	if not _skip.has("armour") and snap["armour"] < target("armour"):
		return {"kind": "armour", "ids": ["armour"]}
	return {}


## `ids` of family `kind` the ship can get now (held, craftable or in the stock here), best first.
func ranked(ids: Array, kind: String) -> Array:
	var out := []
	for id in ids:
		if ship.components.has(str(id)) and can_get(str(id)):
			out.append(str(id))
	return out


func can_get(id: String) -> bool:
	if ship.inventory.count(id) > 0:
		return true
	var rid: String = Salvage.recipe_for(ship, id)
	if rid != "" and ship.crafting.is_known(rid):
		return true
	return _docked != "" and c.stock_price(_docked, id, ship) > 0 and ship.inventory.count("credits") >= c.stock_price(_docked, id, ship)


## Weapon ids the ship could get, best first by their damage per second.
func gun_ids() -> Array:
	var out := []
	for id in ship.components.ids():
		if str(ship.components.def(id).get("family", "")) == "weapon" and weapons.has(id) and can_get(id):
			out.append(id)
	out.sort_custom(func(x, y): return gun_score(x) > gun_score(y))
	return out


func gun_score(id: String) -> float:
	var cfg: Dictionary = Threat.config()
	var w: Dictionary = weapons.def(id)
	var dmg := float(w["damage"]) * float(w["shots"]) * float(cfg["kind_factor"].get(str(w["kind"]), 1.0))
	if str(w["damage_type"]) == "ion":
		dmg *= float(cfg["ion_factor"])
	var hit: float = clampf(float(w["accuracy"]) - float(cfg["turret_miss"]), 0.0, 1.0) if bool(w["turret"]) else float(cfg["fixed_hit"]) * 0.8
	var s := dmg * hit / maxf(float(w["cooldown"]), 0.1)
	if w.has("ammo"):
		s *= 0.7
	return s


## Is item `id` one the ladder is short of? (For the worth of a salvage pick.)
func wanted_now(id: String) -> bool:
	var fam := str(ship.components.def(id).get("family", ""))
	var snap := stats_now()
	match fam:
		"weapon":
			return snap["guns"] < target("guns")
		"shield":
			return snap["layers"] < target("layers")
		"medbay":
			return snap["medbays"] < 1
		"intake":
			return snap["intakes"] < target("intakes")
	return false


## Get item `id` into the hold: it is there, or craftable now (queued and finished: the time is counted), or bought here. "" when it is in the hold
## afterwards, else why not ("missing ..." when the materials are short).
func procure(id: String, force := false) -> String:
	if id == "armour":
		return ""
	if ship.inventory.count(id) > 0 and not force:
		return ""
	var rid: String = Salvage.recipe_for(ship, id)
	var fab: Dictionary = Workshop.best(ship)
	var why := "no recipe"
	if rid != "":
		why = ship.crafting.can_craft(rid, ship.inventory, fab)
		if why == "":
			var err: String = ship.crafting.enqueue(rid, ship.inventory, fab)
			if err == "":
				var rdef: Dictionary = ship.crafting.def(rid)
				ship.crafting.tick(float(rdef["time"]) + 1.0, ship.inventory, fab)
				st["crafted"][id] = int(st["crafted"].get(id, 0)) + 1
				st["fab_s"] = float(st.get("fab_s", 0.0)) + float(rdef["time"])
				flow_add("craft_out", rdef["materials"])
				return "" if ship.inventory.count(id) > 0 or force else "queue"
			return err
	if _docked != "":
		var price: int = c.stock_price(_docked, id, ship)
		if price > 0:
			if ship.inventory.count("credits") - _reserve < price:
				return "missing credits"
			var r: Dictionary = c.buy(ship, _docked, id, 1)
			if r["ok"]:
				flow_add("shop_out", {"credits": price})
				return ""
			return "missing credits"
	return why


func stats_now() -> Dictionary:
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var out := {"guns": 0, "engines": 0, "intakes": 0, "medbays": 0, "rigs": 0, "arms": 0, "cutters": 0, "armour": 0, "produce": 0, "consume": 0, "layers": 0, "fab": 0, "smelter": 0}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		var d: Dictionary = ship.components.def(inst["id"])
		var fam := str(d.get("family", ""))
		var on: bool = powered.get(uid, false) or int(d.get("power", 0)) >= 0
		if fam == "weapon" and on and powered.get(uid, false):
			out["guns"] += 1
		elif fam == "engine" and powered.get(uid, false):
			out["engines"] += 1
		elif fam == "intake" and on and ship.disabled_uids().get(uid, null) == null:
			out["intakes"] += 1
		elif fam == "medbay" and on:
			out["medbays"] += 1
		if str(inst["id"]) == "assembly_rig":
			out["rigs"] += 1
		elif str(inst["id"]) == "robot_arm":
			out["arms"] += 1
		elif str(inst["id"]) == "laser_cutter":
			out["cutters"] += 1
		var p := int(d.get("power", 0))
		if p > 0:
			out["produce"] += p
		elif p < 0:
			out["consume"] -= p
	for cell in ship.grid.tiles:
		var t: String = ship.grid.tiles[cell]
		if t != "wall" and ship.grid.tile_flag(t, "solid"):
			out["armour"] += 1
	out["layers"] = Shields.layers_of_ship(ship, powered)
	out["fab"] = int(Workshop.best(ship)["level"])
	return out


# --- placing parts ---------------------------------------------------------------------------------

## Put item `id` (in the hold) on the ship: a free spot, else a new annex room; cables laid; a reactor first when the power is short.
## "" when it stands powered, else why not.
func install(id: String, it: Dictionary) -> String:
	if id == "armour":
		return plate_armour()
	var bs := BuildSession.new(ship)
	var d: Dictionary = ship.components.def(id)
	var fam := str(d.get("family", ""))
	var need := -int(d.get("power", 0))
	var added := 0
	while need > 0 and fam != "reactor" and margin() < need and added < 2:
		added += 1
		var rid := ""
		for cand in ["reactor_mk2", "reactor_mk1", "reactor_scrap_mk1"]:
			if ship.components.has(cand) and (ship.inventory.count(cand) > 0 or can_get(cand)) and procure(cand) == "":
				rid = cand
				break
		if rid == "":
			return "no power"
		if place(bs, rid, false) != "":
			return "no place for a reactor"
		if install_check(rid) != "":
			return "reactor not powered"
	var is_module := fam == "workshop"
	var why2 := place(bs, id, is_module)
	if why2 != "":
		return why2
	return install_check(id)


## Is the newest part of `id` powered? "" or why not.
func install_check(id: String) -> String:
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var latest := -1
	for uid in ship.components.instances:
		if str(ship.components.instances[uid]["id"]) == id:
			latest = maxi(latest, int(uid))
	if latest < 0:
		return "lost"
	var d: Dictionary = ship.components.def(id)
	if int(d.get("power", 0)) < 0 and not powered.get(latest, false):
		return "unpowered"
	return ""


## Place item `id`: a spot on the ship as it is, else in a new annex room. "" or why not.
func place(bs: BuildSession, id: String, module: bool) -> String:
	var spot := find_spot(id, module)
	if spot.is_empty():
		var made := build_annex(bs, module)
		if made != "":
			return made
		spot = find_spot(id, module)
		if spot.is_empty():
			return "no place"
	var ch := [{"layer": "component", "id": id, "anchor": spot["anchor"], "rot": spot["rot"]}]
	if int(bs.apply(ch)["applied"]) == 0:
		return "refused"
	if int(ship.components.def(id).get("power", 0)) != 0 or str(ship.components.def(id).get("family", "")) == "fabricator":
		wire(bs, id)
	return ""


## The power network with the most supply ({} when the ship has none).
func main_net() -> Dictionary:
	ship.refresh()
	var best := {}
	for n in ship.power_state.get("networks", []):
		if best.is_empty() or float(n["supply"]) > float(best["supply"]):
			best = n
	return best


## Supply less demand of the main network.
func margin() -> float:
	var n := main_net()
	return float(n["supply"]) - float(n["demand"]) if not n.is_empty() else 0.0


## Lay cables from the main network to every part `id` that is on another: the shortest way over hull cells (tool_balance's _wire, but from the main
## network only, so a part never ends up on a cable of its own that no reactor feeds).
func wire(bs: BuildSession, id: String) -> void:
	var g = ship.grid
	var main := main_net()
	if main.is_empty():
		return
	var laid := {}
	for cell in main["cells"]:
		laid[cell] = true
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if str(inst["id"]) != id or int(ship.power_state["network_of"].get(uid, -1)) == int(main["id"]):
			continue
		var goal := {}
		for cell in inst["cells"]:
			goal[cell] = true
		var came := {}
		var queue: Array = []
		for cell in laid:
			came[cell] = cell
			queue.append(cell)
		var end := Vector2i(-1, -1)
		var head := 0
		while head < queue.size() and end.x < 0:
			var cell: Vector2i = queue[head]
			head += 1
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + d
				if came.has(n) or not g.in_hull(n):
					continue
				came[n] = cell
				if goal.has(n):
					end = n
					break
				queue.append(n)
		if end.x < 0:
			continue
		var changes := []
		var at := end
		while not laid.has(at):
			laid[at] = true
			changes.append({"layer": "cable", "cell": at})
			at = came[at]
		bs.apply(changes)
		ship.refresh()


## A free spot for `id`: {anchor, rot}, or {}. Mounts: an outside half in space against a wall with room inside; the rest: floor, near the cables.
func find_spot(id: String, module: bool) -> Dictionary:
	var g = ship.grid
	var comps = ship.components
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell in g.tiles:
		lo = lo.min(cell)
		hi = hi.max(cell)
	lo -= Vector2i(5, 5)
	hi += Vector2i(5, 5)
	var fam := str(comps.def(id).get("family", ""))
	var room_ok: Dictionary = {}
	if module:
		if _shop.size != Vector2i.ZERO:
			for yy in range(_shop.position.y, _shop.end.y):
				for xx in range(_shop.position.x, _shop.end.x):
					room_ok[Vector2i(xx, yy)] = true
		else:
			var fab: Dictionary = Workshop.best(ship)
			if int(fab["uid"]) < 0:
				return {}
			var rof: Dictionary = ship.atmosphere.room_of
			var room: int = rof.get(comps.instances[fab["uid"]]["anchor"], -1)
			for cell in rof:
				if rof[cell] == room:
					room_ok[cell] = true
	var cables: Array = ship.cables.cells.keys()
	var best := {}
	var best_score := INF
	var want_rot := 0 if fam in ["weapon", "intake"] else 2
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var a := Vector2i(x, y)
			for rot in 4:
				if comps.is_mount(id):
					var pl: Dictionary = comps.plan_mount(g, id, a, rot)
					if pl["why"] != "":
						continue
					var score := (0.0 if rot == want_rot else 50.0) + 20.0 * float(blocked_ahead(id, a, rot))
					score += float(Vector2(a).distance_to(Vector2(g.size) / 2.0)) * 0.1
					if score < best_score:
						best_score = score
						best = {"anchor": a, "rot": rot}
				elif rot < 2:
					if comps.can_place(g, id, a, rot) != "":
						continue
					if module and not room_ok.has(a):
						continue
					var near := 999.0
					for cc in cables:
						near = minf(near, float(Vector2(a).distance_to(Vector2(cc))))
						if near < 2.0:
							break
					if near < best_score:
						best_score = near
						best = {"anchor": a, "rot": rot}
	return best


## How many hull cells stand in front of the outside half of mount `id` (its top-left on `a`, turned `rot`), along its outward direction: a mouth or
## a gun behind the bow looks at its own ship.
func blocked_ahead(id: String, a: Vector2i, rot: int) -> int:
	var o: Array = ship.components.def(id)["mount"]["outside"]
	var w := int(o[1] if posmod(rot, 2) == 1 else o[0])
	var h := int(o[0] if posmod(rot, 2) == 1 else o[1])
	var d: Vector2i = Mounts.OUTWARD[posmod(rot, 4)]
	var n := 0
	for y in h:
		for x in w:
			for k in range(1, 40):
				if ship.grid.tiles.has(a + Vector2i(x, y) + d * k):
					n += 1
					break
	return n


## Build a new annex room against the hull: 12x12 for a workshop (with a fabricator in it), else 10x10. "" or why not.
func build_annex(bs: BuildSession, module: bool) -> String:
	var size := Vector2i(12, 12) if module else Vector2i(10, 10)
	var sig := ship.grid.tiles.size() + 1000 * ship.components.instances.size()
	var room := Rect2i()
	if _no_annex.get(size, -1) != sig:
		room = annex_spot(size)
		if room.size == Vector2i.ZERO:
			_no_annex[size] = sig
	if room.size == Vector2i.ZERO and module:
		size = Vector2i(10, 10)
		if _no_annex.get(size, -1) != sig:
			room = annex_spot(size)
			if room.size == Vector2i.ZERO:
				_no_annex[size] = sig
	if room.size == Vector2i.ZERO:
		if args.has("dbg"):
			var hull_free := 0
			for cell in ship.grid.tiles:
				hull_free += 1
			var parts := {}
			for uid in ship.components.instances:
				var inst: Dictionary = ship.components.instances[uid]
				parts[str(inst["id"])] = [inst["anchor"], inst["rot"], inst["cells"].size(), inst["out_cells"].size()]
			print("annex: no spot for %s (module %s), tiles %d; parts %s" % [str(size), str(module), hull_free, str(parts)])
		return "no room for an annex"
	var g = ship.grid
	var walls := BuildSession.room_changes(room.position, room.end - Vector2i.ONE, "wall", bs.floor_tile()).filter(func(ch): return g.get_tile(ch["cell"]) == "")
	var r := bs.apply(walls)
	if int(r["applied"]) == 0:
		return "annex: " + str(r["reason"])
	st["annexes"] = int(st.get("annexes", 0)) + 1
	if module:
		if ship.inventory.count("fabricator") < 1 and procure("fabricator") != "":
			return "no second fabricator"
		var spot := find_free_floor("fabricator", room.grow(-1))
		if spot.is_empty():
			return "no floor for the fabricator"
		bs.apply([{"layer": "component", "id": "fabricator", "anchor": spot["anchor"], "rot": spot["rot"]}])
		wire(bs, "fabricator")
		_shop = room.grow(-1)  # the modules go in here: its fabricator is the one that counts
	return ""


func find_free_floor(id: String, inner: Rect2i) -> Dictionary:
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			for rot in 2:
				if ship.components.can_place(ship.grid, id, Vector2i(x, y), rot) == "":
					return {"anchor": Vector2i(x, y), "rot": rot}
	return {}


## An empty `size` patch of the frame touching the ship's walls on at least 4 cells, the nearest to its middle. The annex's own wall then stands
## beside the old one (tool_balance's _annex_spot wants the two to be one wall, which leaves no spot once guns sit on the straight runs).
func annex_spot(size: Vector2i) -> Rect2i:
	var g = ship.grid
	var comps = ship.components
	var mid := Vector2.ZERO
	for cell in g.tiles:
		mid += Vector2(cell)
	mid /= maxf(g.tiles.size(), 1.0)
	var busy := {}  # cells the patch may not cover: tiles, parts, mount halves and the cells round a mount
	for cell in g.tiles:
		busy[cell] = true
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		for cell in inst["cells"] + inst["out_cells"]:
			busy[cell] = true
	var best := Rect2i()
	var best_score := -INF
	for y in range(1, g.size.y - size.y):
		for x in range(1, g.size.x - size.x):
			var r := Rect2i(Vector2i(x, y), size)
			var ok := true
			var touch := 0
			for cy in range(r.position.y - 1, r.end.y + 1):
				for cx in range(r.position.x - 1, r.end.x + 1):
					var cell := Vector2i(cx, cy)
					var inside := r.has_point(cell)
					if inside:
						if busy.has(cell) or not g.in_hull(cell) or comps.link_at(cell) >= 0:
							ok = false
							break
					elif g.tiles.has(cell) and g.tile_flag(str(g.tiles[cell]), "solid") and not ((cx < r.position.x or cx >= r.end.x) and (cy < r.position.y or cy >= r.end.y)):
						touch += 1  # a wall of the ship against the annex's edge
				if not ok:
					break
			if ok and touch >= 4:
				var score := touch * 10.0 - (Vector2(r.get_center()) - mid).length()
				if score > best_score:
					best_score = score
					best = r
	return best


## Armour: a new layer of plates round the hull, up to the policy's target (40 cells a visit), on the empty cells that touch a solid tile and
## keep clear of every mount's line of fire. The material is the best the hold affords: heavy armour for titanium, ablative plating for polymer,
## else scrap plate. "" when some were laid.
func plate_armour() -> String:
	var bs := BuildSession.new(ship)
	var want := mini(target("armour") - int(stats_now()["armour"]), 40)
	if want <= 0:
		return "enough"
	var g = ship.grid
	var tile := "scrap_plate"
	if ship.inventory.count("titanium") >= 40 and ship.inventory.count("scrap") > 200:
		tile = "heavy_armor"
	elif ship.inventory.count("polymer") >= 150 and ship.inventory.count("scrap") > 200:
		tile = "ablative_plating"
	if ship.inventory.count("scrap") < 150:
		return "no scrap for plates"
	var blocked := {}
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		if inst["out_cells"].is_empty():
			continue
		var d: Vector2i = Mounts.OUTWARD[posmod(int(inst["rot"]), 4)]
		for cell in inst["out_cells"] + inst["cells"]:
			for k in range(-1, 11):
				blocked[cell + d * k] = true
	var mid := Vector2(g.size) / 2.0
	var cands := []
	var seen := {}
	for cell in g.tiles:
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var o: Vector2i = cell + d
			if seen.has(o) or g.tiles.has(o) or blocked.has(o) or not g.in_hull(o) or ship.components.any_at(o) >= 0 or ship.components.at_out(o) >= 0 or ship.components.link_at(o) >= 0:
				continue
			seen[o] = true
			cands.append(o)
	cands.sort_custom(func(x, y): return Vector2(x).distance_to(mid) < Vector2(y).distance_to(mid))
	var laid := 0
	for o in cands:
		if laid >= want:
			break
		var r := bs.apply([{"layer": "tile", "cell": o, "to": tile}])
		laid += int(r["applied"])
		if int(r["applied"]) == 0 and ship.inventory.count("scrap") < 100:
			break
	if laid > 0:
		flow_add("armour", {tile: laid})
		return ""
	return "no cell for plates"


# --- records ---------------------------------------------------------------------------------------

func inv_copy() -> Dictionary:
	return ship.inventory.counts.duplicate()


## Record what changed in the hold since `before` under `src`: gains and losses.
func flow(src: String, before: Dictionary) -> void:
	var f: Dictionary = st["flow"]
	if not f.has(src):
		f[src] = {}
	var now: Dictionary = ship.inventory.counts
	if not f.has(src + "+"):
		f[src + "+"] = {}  # the gains alone: a toll or a fine inside the same step must not read as income
	for id in now:
		var d: int = int(now[id]) - int(before.get(id, 0))
		if d != 0:
			f[src][id] = int(f[src].get(id, 0)) + d
		if d > 0:
			f[src + "+"][id] = int(f[src + "+"].get(id, 0)) + d
	for id in before:
		if not now.has(id):
			f[src][id] = int(f[src].get(id, 0)) - int(before[id])


func flow_add(src: String, items: Dictionary) -> void:
	var f: Dictionary = st["flow"]
	if not f.has(src):
		f[src] = {}
	for id in items:
		f[src][id] = int(f[src].get(id, 0)) + int(items[id])


## The ship as the stage log wants it: power, guns, layers, engines, reactor margin, fabricator, blueprints, hold, crew.
func snapshot() -> Dictionary:
	var s := stats_now()
	var t := Threat.power(ship, float(Threat.config()["player_aim"]))
	var inv: Dictionary = ship.inventory.counts
	var held := {}
	for id in ["scrap", "copper", "polymer", "titanium", "silicon", "crystal", "plasma_cell", "nanite_paste", "credits", "fuel", "steel"]:
		held[id] = int(inv.get(id, 0))
	var part_count := 0
	for id in inv:
		if ship.components.has(str(id)):
			part_count += int(inv[id])
	var fab: Dictionary = Workshop.best(ship)
	var census := {"ok": 0, "bp_ready": 0, "bp_level": 0, "bp_tool": 0, "bp_materials": 0, "station": 0}  # ok: craftable now; bp_*: the blueprint is not known, and with it the recipe would be ready / short of fab level / short of a tool / short of materials
	for rid in ship.crafting.ids():
		if ship.crafting.station_of(rid) != "fabricator":
			census["station"] += 1
			continue
		var known: bool = ship.crafting.is_known(rid)
		ship.crafting.known[rid] = true
		var why: String = ship.crafting.can_craft(rid, ship.inventory, fab)
		if not known:
			ship.crafting.known.erase(rid)
		var key := "ready" if why == "" else ("level" if why.contains("level") or why.contains("offline") else ("tool" if why.begins_with("needs tool") else "materials"))
		census["ok" if known and key == "ready" else ("bp_" + key if not known else "ok_short")] = int(census.get("ok" if known and key == "ready" else ("bp_" + key if not known else "ok_short"), 0)) + 1
	var fabs: Array = []  # per fabricator: its level and the modules in its room (level 3 wants a Rig and two arms in ONE room)
	var room_of: Dictionary = ship.atmosphere.room_of
	var powered: Dictionary = ship.power_state.get("powered", {})
	for fuid in ship.components.instances:
		if str(ship.components.instances[fuid]["id"]) != "fabricator":
			continue
		var froom: int = room_of.get(ship.components.instances[fuid]["anchor"], -1)
		var mods := {"robot_arm": 0, "assembly_rig": 0, "robot_arm_off": 0, "assembly_rig_off": 0, "elsewhere": 0}
		for muid in ship.components.instances:
			var mid := str(ship.components.instances[muid]["id"])
			if mid in ["robot_arm", "assembly_rig"]:
				if room_of.get(ship.components.instances[muid]["anchor"], -1) == froom:
					mods[mid if powered.get(muid, false) else mid + "_off"] += 1
				else:
					mods["elsewhere"] += 1
		var cells := 0
		for cell in room_of:
			if room_of[cell] == froom:
				cells += 1
		fabs.append({"level": int(Workshop.level_of(ship.components, {"room_of": room_of}, fuid, powered)["level"]), "room_cells": cells, "mods": mods})
	return {"fabs": fabs, "census": census, "power": t["power"], "dps": t["dps"], "ehp": t["ehp"], "accel": t["accel"], "guns": s["guns"], "layers": s["layers"], "engines": s["engines"], "intakes": s["intakes"],
		"margin": int(s["produce"]) - int(s["consume"]), "fab": s["fab"], "arms": s["arms"], "rigs": s["rigs"], "cutters": s["cutters"], "armour": s["armour"], "medbays": s["medbays"], "known": ship.crafting.known.size(), "crew": ship.crew.size(),
		"hull_left": roundi(100.0 * Structure.wreck_margin(ship)), "hull_max": 100, "held": held, "spare_parts": part_count, "jumps": c.jumps, "debt": c.debt, "tier": c.tier()}


# --- the report ------------------------------------------------------------------------------------

func report() -> String:
	var L: Array[String] = []
	var n := rows.size()
	L.append("# Progression runs: %d runs, policy %s" % [n, policy])
	for ship_id in group_keys("ship"):
		var sub: Array = rows.filter(func(r): return r["ship"] == ship_id)
		var died := sub.filter(func(r): return r["end"] != "won").size()
		var reach: Array[String] = []
		for s in range(1, stages_n + 1):
			reach.append("%d" % sub.filter(func(r): return r["stages"].size() >= s).size())
		L.append("")
		L.append("## %s: %d runs, %d did not finish; runs that began stage 1..%d: %s" % [ship_id, sub.size(), died, stages_n, ", ".join(reach)])
	L.append("")
	L.append("## The curve by stage (all runs; end of stage unless said)")
	L.append("| stage | runs | fights | win % | skulls | p.power (start>end) | e.power | ratio e/p (cut at 10) | guns | layers | fab | known | scrap in | credits in | min | deaths |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for s in range(1, stages_n + 1):
		var recs := []
		var deaths := 0
		for r in rows:
			if r["stages"].size() >= s:
				recs.append(r["stages"][s - 1])
				if r["end"] != "won" and int(r["end_stage"]) == s:
					deaths += 1
		if recs.is_empty():
			continue
		var fights := []
		for sr in recs:
			fights.append_array(sr["fights"])
		var wins := fights.filter(func(f): return f["state"] in WINS).size()
		L.append("| %d | %d | %.1f | %s | %.1f | %.0f>%.0f | %.0f | %.2f | %.1f | %.1f | %.1f | %.0f | %.0f | %.0f | %.0f | %d |" % [s, recs.size(), float(fights.size()) / recs.size(), pct(wins, fights.size()),
			mean(fights, "skulls"), mean_of(recs, ["start", "power"]), mean_of(recs, ["end", "power"]), mean(fights, "e_power"), mean_capped(fights, "ratio", 10.0),
			mean_of(recs, ["end", "guns"]), mean_of(recs, ["end", "layers"]), mean_of(recs, ["end", "fab"]), mean_of(recs, ["end", "known"]),
			mean_flow(recs, "debris+", "scrap") + mean_flow(recs, "events+", "scrap") + mean_flow(recs, "loot+", "scrap"), mean_flow(recs, "events+", "credits") + mean_flow(recs, "loot+", "credits"),
			mean(recs, "minutes"), deaths])
	L.append("")
	L.append("## Where runs end")
	var causes := {}
	for r in rows:
		if r["end"] != "won":
			var k := "stage %d: %s" % [r["end_stage"], r["cause"]]
			causes[k] = int(causes.get(k, 0)) + 1
	for k in causes:
		L.append("- %s (%d)" % [k, causes[k]])
	return "\n".join(L)


func group_keys(key: String) -> Array:
	var out := []
	for r in rows:
		if not out.has(r[key]):
			out.append(r[key])
	return out


func pct(a: int, b: int) -> String:
	return "%d%%" % (100 * a / maxi(b, 1))


func mean(list: Array, key: String) -> float:
	var t := 0.0
	for x in list:
		t += float(x.get(key, 0.0))
	return t / maxf(list.size(), 1.0)


## The mean of `key`, each value cut at `top` (a ship with no power at all rates against 0.001 in Threat.rate: the ratio is then huge, not meaningful).
func mean_capped(list: Array, key: String, top: float) -> float:
	var t := 0.0
	for x in list:
		t += minf(float(x.get(key, 0.0)), top)
	return t / maxf(list.size(), 1.0)


func mean_of(list: Array, keys: Array) -> float:
	var t := 0.0
	for x in list:
		var v = x
		for k in keys:
			v = v[k]
		t += float(v)
	return t / maxf(list.size(), 1.0)


func mean_flow(list: Array, src: String, item: String) -> float:
	var t := 0.0
	for x in list:
		t += float(x["flow"].get(src, {}).get(item, 0))
	return t / maxf(list.size(), 1.0)
