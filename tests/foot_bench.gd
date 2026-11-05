extends RefCounted
## The on-foot fight bench (not a test): a scripted soldier walks a real generated boarding site and fights the foes it meets, and the run is tallied.
## Used by tests/tool_foot_bench.gd (the report) and tests/test_foot_balance.gd (a short run).
## The soldier model (all dice are the bench's own, seeded from the site seed, so a site and a seed always give the same run):
## - Route: the rooms of the site, nearest first, walked at the soldier's speed along the crew pathfinder. Locked rooms are skipped.
## - He sees a foe that is lit (flashlight beam, small light or a red room) within his gun's range across a clear line, and reacts after 0.25-0.45 s.
## - He stops and fires at the nearest such foe, again as soon as the gun is ready; he reloads when the magazine is empty (or under half with nobody in view).
## - Aim: the angle to the foe plus a normal error of AIM_SD radians (3.4 degrees), x1.6 when the foe moved last tick, on top of the weapon's own spread.
## - Hunted by foes he cannot see he stands still facing the nearest, for at most HOLD_S seconds, then goes on. He never uses cover or retreats (cover by accident only).
## - A medic sash is used (G) when his health is under 55%.

const Site = preload("res://scripts/board/site.gd")
const WreckSite = preload("res://scripts/board/wreck_site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const GearActive = preload("res://scripts/board/gear_active.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const DT := 0.05
const AIM_SD := 0.06  ## radians
const HOLD_S := 6.0
const MAX_S := 420.0  ## simulated seconds of a run, at most
const SITES := ["derelict", "wreck", "nest", "station", "station_abandoned", "station_half", "station_operational", "won_fight"]

const GEAR := {
	"start": {},
	"basic": {"weapons": ["service_pistol", ""], "body": "basic_armor", "mods": ["", ""]},
	"exo": {"weapons": ["service_pistol", ""], "body": "exosuit", "mods": ["", ""]},
	"medic": {"weapons": ["service_pistol", ""], "body": "medic_sash", "mods": ["", ""]},
}


static func ship(rounds: int, crew: int) -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	for i in crew:
		s.crew.append(CrewMember.new("Aid%d" % i, Vector2(10 + 2 * i, 10), "human"))
	s.inventory.add("hand_ammo", rounds - s.inventory.count("hand_ammo"))
	return s


## The session for site kind `kind` and `seed_value` ("station_<state>" is a module station in that state; "won_fight" a beaten enemy ship's wreck).
static func session(kind: String, seed_value: int, gear: String, rounds: int, followers: int):
	var sh := ship(rounds, followers)
	var s = Boarding.start(null, null, "b%d" % seed_value, {"kind": "wreck" if kind in ["wreck", "won_fight"] else kind.split("_")[0]}, sh)
	var site = null
	match kind:
		"station_abandoned", "station_half", "station_operational":
			site = Site.make(seed_value, "station", {"faction": "clans", "gen": "modules", "state": kind.substr(8), "region": "clan_space"})
		"station":
			site = Site.make(seed_value, "station", {"faction": "clans", "gen": "classic"})
		"won_fight":
			var fac: String = ["rustfangs", "concord", "lumen", "wardens", "clans"][seed_value % 5]
			var e: Ship = Shipgen.build(fac, "medium", seed_value, 150.0)
			Jobs.spawn_enemy_crew(e)
			var hr := RandomNumberGenerator.new()
			hr.seed = seed_value
			for m in e.crew:  # (they come through a fight: a quarter to three quarters of their health)
				m.hp = maxf(m.max_hp * hr.randf_range(0.25, 0.75), 1.0)
			site = WreckSite.make(seed_value, JSON.parse_string(JSON.stringify(e.to_dict())), {"fight": "won"})
		_:
			site = Site.make(seed_value, kind, {"faction": "clans"})
	if site == null or (kind != "won_fight" and not site.ok):
		return null
	s.site = site
	s.soldier.pos = site.airlock["spawn"]
	if GEAR[gear].size() > 0:
		s.soldier.kit = GEAR[gear].duplicate(true)
		s.rearm(s.soldier)
	s.foes = Foes.new(s)
	s.rng.seed = Site._mix(seed_value, "fight", 0)
	s.foes.spawn_site({"crew": 3 if kind == "wreck" else 0})
	s.join_party(Party.eligible(sh).map(func(m): return m.name).slice(0, followers))
	return s


static func _path(s, to: Vector2) -> Array[Vector2i]:
	var m = s.soldier
	var walk = s.site.walk
	var pas: Callable = s.soldier_passable()
	var from := Pathfinder.anchor_of(m.pos, m.body_size)
	if not Pathfinder.body_ok(walk, from, pas, m.body_size):
		from = Pathfinder.nearest_walkable(walk, m.pos, pas, Pathfinder.NO_CELL, m.body_size)
	var goal := Pathfinder.anchor_of(to, m.body_size)
	if not Pathfinder.body_ok(walk, goal, pas, m.body_size):
		goal = Pathfinder.nearest_walkable(walk, to, pas, Pathfinder.NO_CELL, m.body_size)
	if from == Pathfinder.NO_CELL or goal == Pathfinder.NO_CELL:
		return []
	return Pathfinder.find_path(walk, from, goal, pas, m.body_size)


static func _gauss(r: RandomNumberGenerator) -> float:
	return sqrt(-2.0 * log(maxf(r.randf(), 1.0e-9))) * cos(TAU * r.randf())


## One run. Returns {kills: {kind: n}, lost: {kind: hp}, lost_total, ttk: [seconds], died, cleared, time, foes, rounds_left, dry_s (seconds with an empty gun
## and nothing to load), party_down (followers down at the end), party_n, hp_pool (the hp of everyone who went in), shots, hits}.
static func run(kind: String, seed_value: int, gear := "start", rounds := 60, followers := 0) -> Dictionary:
	var s = session(kind, seed_value, gear, rounds, followers)
	if s == null:
		return {}
	var r := RandomNumberGenerator.new()
	r.seed = Site._mix(seed_value, "bot", 0)
	var out := {"kills": {}, "lost": {}, "lost_total": 0.0, "ttk": [], "died": false, "cleared": false, "time": 0.0, "foes": s.foes.live().size(), "dry_s": 0.0,
		"party_n": s.party.size() + 1, "hp_pool": 0.0, "shots": 0, "hits": 0, "kind": kind, "medkits": 0}
	var people: Array = [s.soldier]
	for p in s.party:
		people.append(p["m"])
	for m in people:
		out["hp_pool"] += m.max_hp
	var prev := {}
	for m in people:
		prev[m] = m.hp
	var first_hit := {}
	# the route
	var left: Array = []
	for rm in s.site.rooms:
		if int(rm["id"]) != int(s.site.airlock["room"]) and not rm.get("locked", false) and str(rm["purpose"]) != "gone":
			left.append(rm)
	var have_goal := false
	var react := 0.0
	var seen_before := false
	var hold := 0.0
	var t := 0.0
	var aim := 0.0
	var range_c: float = float(s.gun()["w"]["range"]) * 0.95
	var last_kinds: Array = []
	while t < MAX_S:
		t += DT
		var sol = s.soldier
		# who he can see
		var tgt = null
		var td := INF
		for f in s.foes.live():
			if f["hidden"]:
				continue
			var d: float = sol.pos.distance_to(f["m"].pos)
			if d <= range_c and d < td and s.site.clear_line(sol.pos, f["m"].pos) and s.foes.seen(f):
				tgt = f
				td = d
		var want_move := true
		var fire_dir := NAN
		if tgt != null:
			if not seen_before:
				react = r.randf_range(0.25, 0.45)
			seen_before = true
			want_move = false
			var to: Vector2 = tgt["m"].pos - sol.pos
			aim = to.angle()
			sol.path.clear()
			sol.facing = to.normalized()
			react -= DT
			if react <= 0.0:
				var sd := AIM_SD * (1.6 if bool(tgt["moved"]) else 1.0)
				fire_dir = aim + _gauss(r) * sd
			hold = 0.0
		else:
			seen_before = false
			var hunters: Array = s.foes.live().filter(func(f): return f["mode"] in ["hunt", "attack", "cover"] and f["m"].pos.distance_to(sol.pos) < 22.0)
			if not hunters.is_empty() and hold < HOLD_S:
				hold += DT
				want_move = false
				sol.path.clear()
				hunters.sort_custom(func(a, b): return a["m"].pos.distance_to(sol.pos) < b["m"].pos.distance_to(sol.pos))
				aim = (hunters[0]["m"].pos - sol.pos).angle()
			elif hunters.is_empty():
				hold = 0.0
		if want_move:
			if sol.path.is_empty():
				have_goal = false
				while not left.is_empty() and not have_goal:
					var rm: Dictionary = left.pop_front()
					var anchors: Array = s.site.free_anchors(int(rm["id"]))
					if anchors.is_empty():
						continue
					var a: Vector2i = anchors[anchors.size() / 2]
					var p := _path(s, Pathfinder.centre_of(a, sol.body_size))
					if p.is_empty():
						continue
					sol.path = p
					have_goal = true
					left.sort_custom(func(x, y): return Vector2(x["rect"].get_center()).distance_to(Vector2(a)) < Vector2(y["rect"].get_center()).distance_to(Vector2(a)))
				if not have_goal and s.foes.live().filter(func(f): return f["mode"] in ["hunt", "attack", "cover", "flee"]).is_empty():
					break
			if not sol.path.is_empty():
				sol.step(DT)
				aim = sol.facing.angle()
		# the gun
		var g: Dictionary = s.gun()
		var mag_empty: bool = int(g["mag"]) <= 0
		if (mag_empty or (tgt == null and int(g["mag"]) < int(g["w"]["mag"]) / 2)) and float(g["reload"]) <= 0.0:
			s.reload()
		if mag_empty and s.reserve() <= 0 and float(g["reload"]) <= 0.0:
			out["dry_s"] += DT
		if not is_nan(fire_dir):
			if s.fire(fire_dir) == "shot":
				out["shots"] += 1
		if gear == "medic" and sol.hp < sol.max_hp * 0.55 and s.active_cd <= 0.0:
			if bool(GearActive.use(s, aim)["ok"]):
				out["medkits"] += 1
		s.tick(DT, aim, true)
		# tally
		var hurt_by: Array = []
		for e in s.take_events():
			match str(e["type"]):
				"shot":
					if str(e.get("who", "")) == "foe" and str(e.get("team", "")) == "foe":
						last_kinds.append(str(e.get("foe", "")))
				"melee":
					last_kinds.append(str(e.get("kind", "")))
				"hurt":
					hurt_by.append(last_kinds.pop_back() if not last_kinds.is_empty() else "other")
				"hit":
					out["hits"] += 1
					if not first_hit.has(e["foe"]):
						first_hit[e["foe"]] = t
				"down":
					if e.has("foe"):
						var k := str(e["kind"])
						out["kills"][k] = int(out["kills"].get(k, 0)) + 1
						if first_hit.has(e["foe"]):
							out["ttk"].append(t - float(first_hit[e["foe"]]))
		last_kinds.clear()
		var lost := 0.0
		for m in people:
			lost += maxf(prev[m] - m.hp, 0.0)
			prev[m] = m.hp
		if lost > 0.0:
			out["lost_total"] += lost
			for k in hurt_by:
				out["lost"][k] = float(out["lost"].get(k, 0.0)) + lost / hurt_by.size()
			if hurt_by.is_empty():
				out["lost"]["other"] = float(out["lost"].get("other", 0.0)) + lost
		if s.soldier.is_down():
			out["died"] = true
			break
	out["time"] = t
	out["cleared"] = s.foes.live().is_empty()
	out["rounds_left"] = s.reserve() + int(s.gun()["mag"])
	out["party_down"] = s.party.filter(func(p): return p["m"].is_down()).size()
	return out
