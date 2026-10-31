extends SceneTree
## Not a test (the runner only loads test_*.gd). The balance harness (docs/CONTENT.md 14): AI-vs-AI fights in the real arena
## of every hangar starter (packs included) against generated enemies (Shipgen) of each faction at jumps 5, 15, 25 and 35, N
## seeds each, capped at `cap` simulated seconds. Both ships are flown by the pilot AI (the player's thinks every 3rd tick at
## the threat table's player_aim, as a human is slower but aims better than the soak's default), their crews run in ShipSim,
## morale ends fights the ways the game does (the player takes any surrender). It writes docs/BALANCE_REPORT.md: win / loss /
## draw by ship, jump and faction, time to end, hull left, how fights end, the threat rating against the measured win rate,
## and what the guns did.
##   godot --headless --path . --script res://tests/tool_balance.gd [-- key=value ...]
## Keys: seeds (per pairing, default 1), cap (s, default 180), jumps (5,15,25,35), factions (all), ships (hangar ids, or
## "all" for every hangar ship, packs included; default the ones open from the start), kit_jumps (the jumps at which each
## ship also fights with the upgrade kit, default 15; "none" for never),
## jobs (run in this many processes at once, default 3), out (res://docs/BALANCE_REPORT.md), save (a JSON of the numbers, for a
## later compare), compare (such a JSON: adds a before / after table), label (the run's name in the report), dump (write
## every fight's row there, JSON), out_hp (a
## what-if: every weapon's outside_hp times this, on both ships, for this run only). Internal: shard
## (k/n: only every n-th pairing from the k-th) and rows (write the fights' rows there instead of a report), merge (row files).
## The upgrade kit ("a few upgrades", apply_kit()): an annex room built onto the core in the starter's empty frame, holding the
## shield generator the starter carries in its hold, a Mk1 reactor to power it and a Mk1 laser turret through the annex's
## outer wall, wired to the ship's network, all through the build rules (BuildSession). A kitted ship is "<name> + kit".
## A fight's budget is Shipgen.budget_for(tier of the jump, jump, the danger of the faction's first region, normal); the enemy
## is Shipgen.build(faction, pick_size(budget), seed, budget), the same ship for every starter.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Hangar = preload("res://scripts/space/hangar.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Morale = preload("res://scripts/combat/morale.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12  ## substeps between ShipSim steps (0.2 s, as the soak)
const PLAYER_EVERY := 3  ## the player's pilot thinks every this many substeps (as the soak)
const WIN_STATES: Array[String] = ["won", "captured", "spared"]
const ENDS: Array[String] = ["wreck", "capture", "surrender", "escape", "lost", "draw"]
const END_OF := {"won": "wreck", "captured": "capture", "spared": "surrender", "escaped": "escape", "lost": "lost", "fighting": "draw"}
## Targets (the balance brief) for the flags of the reading: jump -> [low, high] projected win share, and which ships they are
## for: a bare starter about 80% at jump 5, 50-60% with a few upgrades (the kit) at jump 15, clearly outmatched bare at jump 35.
const TARGETS := {5: [0.7, 0.9, false], 15: [0.45, 0.65, true], 35: [0.0, 0.3, false]}
const CUT_SCORES: Array[float] = [0.85, 0.65, 0.35, 0.15]  ## the result (won 1, drawn 0.5) between 1|2, 2|3, 3|4 and 4|5 skulls
const KIT_PARTS: Array[String] = ["laser_turret_mk1", "reactor_mk1"]  ## bought for the kit (the shield comes from the hold)
const KIT_STOCK := {"scrap": 5000, "copper": 600, "titanium": 400, "silicon": 400, "crystal": 200, "polymer": 200}
const ANNEX := Vector2i(10, 10)  ## the annex room, walls included: 8 x 8 floor

var seeds := 1
var cap := 180.0
var jumps: Array = [5, 15, 25, 35]
var factions: Array = []
var ships: Array = []  ## [{id, name, path}]
var out_path := "res://docs/BALANCE_REPORT.md"
var save_path := ""
var compare_path := ""
var label := ""
var tier2 := 10
var tier3 := 25
var rows: Array = []  ## one dictionary per fight
var kit_jumps: Array = [15]
var out_hp := 1.0  ## the what-if multiplier of every weapon's outside_hp
var _kit_plans := {}  # ship id -> the kit's build steps (apply_kit), found once
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	seeds = int(args.get("seeds", seeds))
	out_hp = float(args.get("out_hp", out_hp))
	cap = float(args.get("cap", cap))
	if args.has("jumps"):
		jumps = Array(str(args["jumps"]).split(",")).map(func(s): return int(s))
	factions = Array(str(args["factions"]).split(",")) if args.has("factions") else Shipgen.factions()
	out_path = str(args.get("out", out_path))
	save_path = str(args.get("save", ""))
	compare_path = str(args.get("compare", ""))
	label = str(args.get("label", ""))
	var drift = JSON.parse_string(FileAccess.get_file_as_string("res://data/drift.json"))
	tier2 = int(drift["danger"]["tier2_from"])
	tier3 = int(drift["danger"]["tier3_from"])
	if args.has("kit_jumps"):
		kit_jumps = [] if str(args["kit_jumps"]) == "none" else Array(str(args["kit_jumps"]).split(",")).map(func(x): return int(x))
	var want: Array = Array(str(args["ships"]).split(",")) if args.has("ships") else []
	for s in Hangar.starters():
		if want.has(s["id"]) or want == ["all"] or (want.is_empty() and str(s["unlock"]) == ""):
			ships.append({"id": s["id"], "name": s["name"], "path": s["path"], "kit": false})
	if not kit_jumps.is_empty():
		for sh in ships.duplicate():
			ships.append({"id": sh["id"] + "+kit", "name": sh["name"] + " + kit", "path": sh["path"], "kit": true})
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var jobs := int(args.get("jobs", 3))
	if args.has("merge"):
		for path in str(args["merge"]).split(","):
			rows.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
	elif jobs > 1 and not args.has("shard"):
		_fan_out(jobs)
	else:
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var kits := ships.filter(func(x): return x["kit"]).size()
		var total := ((ships.size() - kits) * jumps.size() + kits * jumps.filter(func(j): return kit_jumps.has(j)).size()) * factions.size() * seeds
		print("balance: %d ships x %d factions x %d jumps x %d seeds = %d fights, cap %d s, shard %s" % [ships.size(), factions.size(), jumps.size(), seeds, total, cap, str(shard)])
		var k := 0
		for f in factions:
			for j in jumps:
				for s in seeds:
					k += 1
					if (k - 1) % shard[1] != shard[0]:
						continue
					var spec := _spec(f, j, 101 + s * 7919 + j * 31)
					for sh in ships:
						if not sh["kit"] or kit_jumps.has(j):
							rows.append(fight(sh, spec, f, j, s))
			print("  %s done, %d fights, %d s" % [f, rows.size(), (Time.get_ticks_msec() - t0) / 1000])
		if args.has("rows"):
			_write(str(args["rows"]), JSON.stringify(rows))
			quit(0)
			return
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	_write(out_path, report(secs))
	if save_path != "":
		_write(save_path, JSON.stringify(summary(), "\t"))
	if args.has("dump"):
		_write(str(args["dump"]), JSON.stringify(rows))
	print("balance: wrote %s in %.0f s" % [out_path, secs])
	quit(0)


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


## Run the fights in `jobs` processes of this tool at once (each a shard that writes its rows), wait, and read their rows.
func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["seeds", "cap", "jumps", "factions", "ships", "kit_jumps", "out_hp"]:
		if args.has(key):
			pass_on.append("%s=%s" % [key, args[key]])
	for k in jobs:
		var path := OS.get_cache_dir().path_join("hullscrap_balance_%d_%d.json" % [OS.get_process_id(), k])
		files.append(path)
		var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_balance.gd", "--",
			"shard=%d/%d" % [k, jobs], "rows=" + path] + pass_on
		pids.append(OS.create_process(OS.get_executable_path(), argv))
	print("balance: %d processes %s" % [jobs, str(pids)])
	while pids.any(func(p): return OS.is_process_running(p)):
		OS.delay_msec(500)
	for path in files:
		var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if got is Array:
			rows.append_array(got)
		else:
			printerr("balance: a shard wrote nothing: " + path)
		DirAccess.remove_absolute(path)


# --- one fight ------------------------------------------------------------------------------------

## The danger of the first region (data/regions) whose pirates are `faction`, 1.0 when none is.
static func danger_for(faction: String) -> float:
	var best := INF
	for r in Content.regions():
		if str(r.get("enemies", "")) == faction:
			best = minf(best, float(r.get("danger", 1.0)))
	return best if best < INF else 1.0


## The campaign's tier at jump `j` (data/drift.json).
func tier_at(j: int) -> int:
	return 3 if j >= tier3 else (2 if j >= tier2 else 1)


## The enemy of (faction, jump, seed) as a spec string, as the campaign rolls it.
func _spec(faction: String, j: int, seed_value: int) -> String:
	var budget := Shipgen.budget_for(tier_at(j), j, danger_for(faction))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Shipgen.spec(faction, Shipgen.pick_size(budget, rng), seed_value, budget)


## One fight of ship `sh` against the enemy `spec`. Returns its row.
func fight(sh: Dictionary, spec: String, faction: String, j: int, s: int) -> Dictionary:
	var player: Ship = Ship.from_design(sh["path"])
	var enemy: Ship = Session.load_ship(spec)
	var row := {"ship": sh["id"], "faction": faction, "jump": j, "seed": s, "spec": spec}
	if player != null and sh["kit"]:
		var why := apply_kit(player, sh["id"])
		if why != "":
			printerr("balance: no kit for %s: %s" % [sh["name"], why])
			player = null
	if player == null or enemy == null:
		row["state"] = "error"
		return row
	if not is_equal_approx(out_hp, 1.0):  # each ship holds its own copy of the part data
		for each in [player, enemy]:
			var done := {}
			for uid in each.components.instances:
				var inst: Dictionary = each.components.instances[uid]
				var dd: Dictionary = each.components.by_id[inst["id"]]
				if str(dd.get("family", "")) != "weapon" or not dd.has("mount"):
					continue
				if not done.has(inst["id"]):
					done[inst["id"]] = true
					dd["mount"]["outside_hp"] = roundi(float(dd["mount"]["outside_hp"]) * out_hp)
				inst["out_hp"] = dd["mount"]["outside_hp"]
	var gen: Dictionary = enemy.get_meta("shipgen", {})
	row.merge({"size": gen.get("size", "?"), "budget": gen.get("budget", 0.0), "ram": gen.get("ram", false),
		"e_weapons": gen.get("weapons", []).size(), "e_shields": gen.get("shields", []).size(), "e_armour": gen.get("armour", 0)})
	var th := Threat.rate(enemy, player)
	row["skulls"] = th["skulls"]
	row["ratio"] = th["ratio"]
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + s * 1009 + j)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var d := {"p_shots": 0, "e_shots": 0, "p_hull": 0.0, "e_hull": 0.0, "p_part": 0.0, "e_part": 0.0, "p_shield": 0, "e_shield": 0,
		"in_range": 0, "armed": 0, "samples": 0, "gap": 0.0, "gun_lost": -1.0}
	var cursor := 0
	var n := 0
	var ticks := int(cap * 60.0)
	while sess.state() == "fighting" and n < ticks:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
			_sample(sess, pilot, d)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n % SIM_EVERY == 0:
			sim.step(SIM_EVERY * STEP)
		cursor = _scan(a, cursor, d)
	cursor = _scan(a, cursor, d)
	var st := sess.state()
	var me = a.ships[Session.PLAYER]
	var foe = a.ships[Session.ENEMY]
	row.merge({"state": st, "end": END_OF.get(st, "draw"), "t": n * STEP, "hull": me.hull / maxf(me.hull_max, 1.0),
		"foe_hull": foe.hull / maxf(foe.hull_max, 1.0), "hp": me.hull, "foe_hp": foe.hull, "foe_hp_max": foe.hull_max, "morale": sess.morale.state})
	row.merge(d)
	sim.free()
	return row


# --- the upgrade kit ------------------------------------------------------------------------------

## Fit the upgrade kit to `ship` (see the top). "" when every kit part stands powered, else why not. The build steps are found
## once per `key` (the room's place, the parts' places, the cables) and replayed through BuildSession after that.
func apply_kit(ship: Ship, key: String) -> String:
	var shield := ""
	for id in ship.inventory.counts:
		if ship.components.has(str(id)) and str(ship.components.def(str(id)).get("family", "")) == "shield":
			shield = str(id)
	if shield == "":
		return "no shield generator in the hold"
	for id in KIT_STOCK:
		ship.inventory.add(id, KIT_STOCK[id])
	for id in KIT_PARTS:
		ship.inventory.add(id, 1)
	var bs := BuildSession.new(ship)
	if not _kit_plans.has(key):
		_kit_plans[key] = _plan_kit(ship, bs, shield)
		if _kit_plans[key] is String:
			return _kit_plans[key]
		return _kit_check(ship, shield)
	if _kit_plans[key] is String:
		return _kit_plans[key]
	for step in _kit_plans[key]:
		bs.apply(step)
	return _kit_check(ship, shield)


func _kit_check(ship: Ship, shield: String) -> String:
	ship.refresh()
	for want in [shield] + KIT_PARTS:
		var ok := false
		for uid in ship.components.instances:
			ok = ok or (ship.components.instances[uid]["id"] == want and ship.power_state["powered"].get(uid, false))
		if not ok:
			return want + " is not powered"
	return ""


## Build the kit on `ship` and return the steps it took (each a BuildSession change list), or why it cannot be built.
func _plan_kit(ship: Ship, bs: BuildSession, shield: String):
	var g = ship.grid
	var comps = ship.components
	var room := _annex_spot(ship)
	if room.size == Vector2i.ZERO:
		return "no place for the annex in the frame"
	var steps: Array = []
	var walls := BuildSession.room_changes(room.position, room.end - Vector2i.ONE, "wall", bs.floor_tile()).filter(func(ch): return g.get_tile(ch["cell"]) == "")
	bs.apply(walls)
	steps.append(walls)
	var inner := room.grow(-1)
	var best := []
	for y in range(room.position.y - 4, room.end.y + 4):  # the turret: its breech on the annex floor, its barrel in space
		for x in range(room.position.x - 4, room.end.x + 4):
			for rot in 4:
				var pl: Dictionary = comps.plan_mount(g, "laser_turret_mk1", Vector2i(x, y), rot)
				if pl["why"] == "" and pl["cells"].all(func(c): return inner.has_point(c)):
					best = [Vector2i(x, y), rot]
					break
			if not best.is_empty():
				break
		if not best.is_empty():
			break
	if best.is_empty():
		return "no wall of the annex takes the turret"
	var mount := [{"layer": "component", "id": "laser_turret_mk1", "anchor": best[0], "rot": best[1]}]
	if bs.apply(mount)["applied"] == 0:
		return "the turret would not go on"
	steps.append(mount)
	if not _fit(ship, bs, [shield, "reactor_mk1"], inner, steps):
		return "no floor in the annex for the shield and the reactor"
	var cables := _wire(ship, [shield] + KIT_PARTS)
	if cables.is_empty():
		return "no cable path to the annex"
	bs.apply(cables)
	steps.append(cables)
	return steps


## Place the parts `ids` on the floor of `inner`, each somewhere the rest still fit (a search that undoes what leads nowhere).
## True when all are placed; their changes are appended to `steps`.
static func _fit(ship: Ship, bs: BuildSession, ids: Array, inner: Rect2i, steps: Array) -> bool:
	if ids.is_empty():
		return true
	for y in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			for rot in 2:
				if ship.components.can_place(ship.grid, ids[0], Vector2i(x, y), rot) != "":
					continue
				var ch := [{"layer": "component", "id": ids[0], "anchor": Vector2i(x, y), "rot": rot}]
				if bs.apply(ch)["applied"] == 0:
					continue
				steps.append(ch)
				if _fit(ship, bs, ids.slice(1), inner, steps):
					return true
				steps.pop_back()
				bs.undo()
	return false


## The annex room (ANNEX, walls included): hull cells of the frame that are empty, sharing as much wall as
## it can with the core (at least 4 cells), nearest the core's middle on a tie. A zero rect when nothing fits.
static func _annex_spot(ship: Ship) -> Rect2i:
	var g = ship.grid
	var comps = ship.components
	var mid := Vector2.ZERO
	for c in g.tiles:
		mid += Vector2(c)
	mid /= maxf(g.tiles.size(), 1.0)
	var best := Rect2i()
	var best_score := -INF
	var size := ANNEX
	for y in range(0, g.size.y - size.y + 1):
		for x in range(0, g.size.x - size.x + 1):
			var r := Rect2i(Vector2i(x, y), size)
			var shared := 0
			var ok := true
			for cy in range(r.position.y, r.end.y):
				for cx in range(r.position.x, r.end.x):
					var c := Vector2i(cx, cy)
					var edge := cx == r.position.x or cy == r.position.y or cx == r.end.x - 1 or cy == r.end.y - 1
					var t: String = g.get_tile(c)
					if not g.in_hull(c) or comps.any_at(c) >= 0 or comps.link_at(c) >= 0:
						ok = false
					elif t != "":
						if edge and g.tile_flag(t, "solid") and not g.tile_flag(t, "door") and g.shape_of(c).is_empty():
							shared += 1
						else:
							ok = false
					if not ok:
						break
				if not ok:
					break
			if ok and shared >= 4:
				var score := shared * 100.0 - (Vector2(r.get_center()) - mid).length()
				if score > best_score:
					best_score = score
					best = r
	return best


## Cables from the ship's network to every part of `ids` that is on none: the shortest path over hull cells from any cable
## cell to one of the part's cells. The change list, or [] when a part cannot be reached.
static func _wire(ship: Ship, ids: Array) -> Array:
	var g = ship.grid
	var out := []
	var laid := {}
	for c in ship.cables.cells:
		laid[c] = true
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var cells: Array = ship.components.instances[uid]["cells"]
		if not ids.has(ship.components.instances[uid]["id"]) or cells.any(func(c): return laid.has(c)):
			continue
		var goal := {}
		for c in cells:
			goal[c] = true
		var came := {}
		var queue: Array = []
		for c in laid:
			came[c] = c
			queue.append(c)
		var end := Vector2i(-1, -1)
		var head := 0
		while head < queue.size() and end.x < 0:
			var c: Vector2i = queue[head]
			head += 1
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if came.has(n) or not g.in_hull(n):
					continue
				came[n] = c
				if goal.has(n):
					end = n
					break
				queue.append(n)
		if end.x < 0:
			return []
		var at := end
		while not laid.has(at):
			laid[at] = true
			out.append({"layer": "cable", "cell": at})
			at = came[at]
	return out


## What the player's guns can do now: one sample every PLAYER_EVERY substeps.
func _sample(sess: Session, pilot: PilotAI, d: Dictionary) -> void:
	var a = sess.arena
	var co = a.ships[Session.PLAYER]
	d["samples"] += 1
	var to_foe: Vector2 = a.ships[Session.ENEMY].flight.pos - co.flight.pos
	d["gap"] += to_foe.length() - pilot.extent(0, to_foe.normalized()) - pilot.extent(1, -to_foe.normalized())
	var armed := false
	var reach := false
	var intact := false  # a gun not shot out (a jam or the heat only stops it a while)
	for uid in co.mounts:
		var m: Dictionary = co.mounts[uid]
		var st: String = a.weapons.status_of(a, 0, uid)
		intact = intact or not st in ["disabled", "offline"]
		if st != "ok" or not co.powered.get(uid, false):
			continue
		armed = true
		var w: Dictionary = a.weapons.def(m["id"])
		if a.weapons.muzzle_of(a, 0, m).distance_to(pilot.aim_for(m, false)) <= float(w["range"]):
			reach = true
	d["armed"] += int(armed)
	d["in_range"] += int(reach)
	if not intact and d["gun_lost"] < 0.0:
		d["gun_lost"] = a.time()


## Count the arena's new events into `d`: shots by the shooter, hits by the target (walls and doors are hull, parts are parts).
func _scan(a, cursor: int, d: Dictionary) -> int:
	var ev: Array = a.events
	for k in range(cursor, ev.size()):
		var e: Dictionary = ev[k]
		var who := "p" if int(e["ship"]) == 0 else "e"
		var other := "e" if who == "p" else "p"
		match str(e["type"]):
			"shot":
				d[who + "_shots"] += 1
			"hit":
				if e.get("kind", "") == "component":
					d[other + "_part"] += float(e.get("dealt", 0.0))
				else:
					d[other + "_hull"] += float(e.get("dealt", 0.0))
			"shield":
				d[other + "_shield"] += 1
	return ev.size()


# --- the report -----------------------------------------------------------------------------------

func _sel(filter: Callable) -> Array:
	return rows.filter(func(r): return r.get("state", "error") != "error" and filter.call(r))


static func _rate(list: Array) -> Dictionary:
	var w := 0
	var l := 0
	var ahead := 0
	var t := 0.0
	var hull := 0.0
	for r in list:
		t += float(r["t"])
		if r["state"] in WIN_STATES:
			w += 1
			hull += float(r["hull"])
		elif r["state"] == "lost":
			l += 1
		elif _lean(r) > 0.5:
			ahead += 1  # a draw it was winning (_lean)
	var n := list.size()
	return {"n": n, "w": w, "l": l, "d": n - w - l, "win": float(w) / maxf(n, 1), "draw": float(n - w - l) / maxf(n, 1),
		"t": t / maxf(n, 1), "hull": hull / maxf(w, 1), "ahead": ahead, "proj": float(w + ahead) / maxf(n, 1)}


## A fight's result as a number: won 1, lost 0, an escape 0.5; a draw (the cap) by projection at the rates of the fight: 1
## when the player would have brought the enemy to its morale break (break_hull of its hull) before the enemy wrecked it,
## 0 when not, 0.5 when neither was hurting the other.
static func _lean(r: Dictionary) -> float:
	if r["state"] in WIN_STATES:
		return 1.0
	if r["state"] == "lost":
		return 0.0
	if r["state"] == "escaped" or not r.has("hp"):
		return 0.5
	var t := maxf(float(r["t"]), 1.0)
	var mine := float(r["p_hull"]) / t  # hull a second the player takes off the enemy
	var theirs := float(r["e_hull"]) / t
	var t_win := maxf(float(r["foe_hp"]) - float(Morale.config().get("break_hull", 0.35)) * float(r["foe_hp_max"]), 0.0) / mine if mine > 1e-3 else INF
	var t_lose := float(r["hp"]) / theirs if theirs > 1e-3 else INF
	if t_win == INF and t_lose == INF:
		return 0.5
	return 1.0 if t_win < t_lose else 0.0


static func _cell(r: Dictionary) -> String:
	if r["n"] == 0:
		return "-"
	return "%d%% (%d/%d/%d) %ds" % [roundi(100.0 * r["win"]), r["w"], r["l"], r["d"], roundi(r["t"])]


static func _proj(r: Dictionary) -> String:
	return "-" if r["n"] == 0 else "%d%%" % roundi(100.0 * r["proj"])


static func _mean(list: Array, key: String) -> float:
	var s := 0.0
	for r in list:
		s += float(r[key])
	return s / maxf(list.size(), 1)


## The numbers a later run compares against: overall and by jump (the ships without the kit), by ship and jump, by skulls.
func summary() -> Dictionary:
	var bare := func(r): return not str(r["ship"]).ends_with("+kit")
	var out := {"label": label, "all": _rate(_sel(bare)), "jump": {}, "ship_jump": {}, "skulls": {}}
	for j in jumps:
		out["jump"][str(j)] = _rate(_sel(func(r): return r["jump"] == j and bare.call(r)))
		for sh in ships:
			out["ship_jump"]["%s@%d" % [sh["id"], j]] = _rate(_sel(func(r): return r["jump"] == j and r["ship"] == sh["id"]))
	for k in range(1, 6):
		out["skulls"][str(k)] = _rate(_sel(func(r): return r["skulls"] == k))
	return out


func report(secs: float) -> String:
	var L: Array[String] = []
	var all := _rate(_sel(func(r): return true))
	L.append("# Balance report")
	L.append("")
	L.append("Written by `tests/tool_balance.gd`%s (docs/CONTENT.md 14). %d fights: %d ships x %d factions x jumps %s x %d seeds (the kitted ships at jumps %s), capped at %d s, run in %d s." % [
		" (run: %s)" % label if label != "" else "", rows.size(), ships.size(), factions.size(), str(jumps), seeds, str(kit_jumps), cap, secs])
	L.append("Both ships are flown by the pilot AI (the player's at aim %.2f, thinking every %d ticks); crews run in ShipSim; morale can end a fight (the player takes every surrender). A cell is `win%% (won/lost/drawn) mean seconds`; a draw is the cap or an enemy that escaped. Budgets: Shipgen.budget_for(tier, jump, danger of the faction's first region): %s." % [
		float(Threat.config()["player_aim"]), PLAYER_EVERY, ", ".join(factions.map(func(f): return "%s %.2f" % [f, danger_for(f)]))])
	L.append("")
	L.append("**All fights**: won %d%%, lost %d%%, drawn %d%%, mean %d s." % [roundi(100 * all["win"]), roundi(100.0 * all["l"] / maxf(all["n"], 1)), roundi(100 * all["draw"]), roundi(all["t"])])
	L.append("")
	L.append("## Win rate by ship and jump")
	L.append("")
	L.append("| ship | " + " | ".join(jumps.map(func(j): return "jump %d (budget ~%d)" % [j, roundi(Shipgen.budget_for(tier_at(j), j, 1.0))])) + " |")
	L.append("|---|" + "---|".repeat(jumps.size()))
	for sh in ships:
		L.append("| %s | " % sh["name"] + " | ".join(jumps.map(func(j): return _cell(_rate(_sel(func(r): return r["ship"] == sh["id"] and r["jump"] == j))))) + " |")
	L.append("| **all** | " + " | ".join(jumps.map(func(j): return _cell(_rate(_sel(func(r): return r["jump"] == j))))) + " |")
	L.append("")
	L.append("Projected win rate: the wins plus the draws the player was winning, by the rates of the fight (it would have brought the enemy to its morale break, 35% of its hull, before the enemy wrecked it). The cap cuts many fights short; this is the curve the budgets are tuned on.")
	L.append("")
	L.append("| ship | " + " | ".join(jumps.map(func(j): return "jump %d" % j)) + " |")
	L.append("|---|" + "---|".repeat(jumps.size()))
	for sh in ships:
		L.append("| %s | " % sh["name"] + " | ".join(jumps.map(func(j): return _proj(_rate(_sel(func(r): return r["ship"] == sh["id"] and r["jump"] == j))))) + " |")
	L.append("")
	if compare_path != "" and FileAccess.file_exists(compare_path):
		_compare(L)
	L.append("## By faction (all ships)")
	L.append("")
	L.append("| faction | " + " | ".join(jumps.map(func(j): return "jump %d" % j)) + " |")
	L.append("|---|" + "---|".repeat(jumps.size()))
	for f in factions:
		L.append("| %s | " % f + " | ".join(jumps.map(func(j): return _cell(_rate(_sel(func(r): return r["faction"] == f and r["jump"] == j))))) + " |")
	L.append("")
	L.append("## Every pairing: won-lost-drawn, mean skulls, mean hull left after a win")
	L.append("")
	L.append("| ship | faction | " + " | ".join(jumps.map(func(j): return "jump %d" % j)) + " |")
	L.append("|---|---|" + "---|".repeat(jumps.size()))
	for sh in ships:
		for f in factions:
			var cells := []
			for j in jumps:
				var list := _sel(func(r): return r["ship"] == sh["id"] and r["faction"] == f and r["jump"] == j)
				var r := _rate(list)
				cells.append("-" if r["n"] == 0 else "%d-%d-%d, %.1f sk, %d%% hull" % [r["w"], r["l"], r["d"], _mean(list, "skulls"), roundi(100 * r["hull"])])
			L.append("| %s | %s | %s |" % [sh["name"], f, " | ".join(cells)])
	L.append("")
	L.append("## Threat rating against the result")
	L.append("")
	L.append("The rating the radar shows (threat.gd, cuts %s) for each fight, against how the fight went. Target: 1 skull a sure win, 3 even, 5 a likely loss." % str(Threat.config()["cuts"]))
	L.append("")
	L.append("| skulls | fights | won | lost | drawn | mean power ratio |")
	L.append("|---|---|---|---|---|---|")
	for k in range(1, 6):
		var list := _sel(func(r): return r["skulls"] == k)
		var r := _rate(list)
		L.append("| %d | %d | %d%% | %d%% | %d%% | %.2f |" % [k, r["n"], roundi(100 * r["win"]), roundi(100.0 * r["l"] / maxf(r["n"], 1)), roundi(100 * r["draw"]), _mean(list, "ratio")])
	L.append("")
	L.append("Cuts these fights suggest: %s (a falling fit of the result, won 1, lost 0, a draw 1 or 0 by its projection, against the power ratio, cut where it crosses %s)." % [
		str(suggest_cuts().map(func(c): return snappedf(c, 0.01))), str(CUT_SCORES)])
	L.append("")
	L.append("## How fights end")
	L.append("")
	L.append("| jump | " + " | ".join(ENDS) + " | mean time | enemy hull left |")
	L.append("|---|" + "---|".repeat(ENDS.size() + 2))
	for j in jumps:
		var list := _sel(func(r): return r["jump"] == j)
		L.append("| %d | " % j + " | ".join(ENDS.map(func(e): return str(list.filter(func(r): return r["end"] == e).size()))) + " | %d s | %d%% |" % [roundi(_mean(list, "t")), roundi(100 * _mean(list, "foe_hull"))])
	L.append("")
	L.append("## What the guns did (means per fight)")
	L.append("")
	L.append("Shots fired; damage to the hull pool (walls, doors) and to parts; shield layers spent; the share of the time the player had a working gun, and had the pilot's target within a gun's range; the mean hull-to-hull gap (along the line between the centres, PilotAI.extent(); the before run measured it between the bounding circles); when the player's last gun was shot out (disabled or cut off, not jammed).")
	L.append("")
	L.append("| ship | jump | shots (you/foe) | hull dmg (you/foe) | part dmg (you/foe) | shields hit (you/foe) | armed | in range | gap px | guns out at |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	for sh in ships:
		for j in jumps:
			var list := _sel(func(r): return r["ship"] == sh["id"] and r["jump"] == j)
			if list.is_empty():
				continue
			var lost := list.filter(func(r): return float(r["gun_lost"]) >= 0.0)
			L.append("| %s | %d | %d / %d | %.0f / %.0f | %.0f / %.0f | %.0f / %.0f | %d%% | %d%% | %d | %s |" % [sh["name"], j, roundi(_mean(list, "p_shots")), roundi(_mean(list, "e_shots")),
				_mean(list, "p_hull"), _mean(list, "e_hull"), _mean(list, "p_part"), _mean(list, "e_part"), _mean(list, "p_shield"), _mean(list, "e_shield"),
				roundi(100.0 * _share(list, "armed")), roundi(100.0 * _share(list, "in_range")), roundi(_mean_ratio(list, "gap")),
				"%d of %d fights, ~%d s" % [lost.size(), list.size(), roundi(_mean(lost, "gun_lost"))] if not lost.is_empty() else "never"])
	L.append("")
	L.append("## Reading")
	L.append("")
	for line in reading():
		L.append("- " + line)
	L.append("")
	return "\n".join(L)


## The power ratios at which the measured result crosses CUT_SCORES: a non-increasing fit (pool adjacent violators) of the
## score of every fight (_lean()) over its ratio, cut halfway between the last fight above a score and the
## first below it. A score nothing falls under gets a cut past the highest ratio seen.
func suggest_cuts() -> Array:
	var pts := _sel(func(r): return true).map(func(r): return [float(r["ratio"]), _lean(r)])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	var blocks := []  # [score sum, count, lowest ratio, highest ratio]
	for p in pts:
		blocks.append([p[1], 1.0, p[0], p[0]])
		while blocks.size() > 1 and blocks[-2][0] / blocks[-2][1] < blocks[-1][0] / blocks[-1][1] - 1e-9:
			var b: Array = blocks.pop_back()
			blocks[-1][0] += b[0]
			blocks[-1][1] += b[1]
			blocks[-1][3] = b[3]
	var cuts := []
	var top: float = pts[-1][0] * 1.25 if not pts.is_empty() else 1.0
	for score in CUT_SCORES:
		var cut := top
		for k in blocks.size():
			if blocks[k][0] / blocks[k][1] < score:
				cut = (blocks[k][2] + blocks[k - 1][3]) / 2.0 if k > 0 else blocks[k][2] * 0.9
				break
		cuts.append(maxf(cut, cuts[-1] + 0.01) if not cuts.is_empty() else cut)
	return cuts


static func _share(list: Array, key: String) -> float:
	var s := 0.0
	var n := 0.0
	for r in list:
		s += float(r[key])
		n += float(r["samples"])
	return s / maxf(n, 1.0)


static func _mean_ratio(list: Array, key: String) -> float:
	return _share(list, key)


func _compare(L: Array[String]) -> void:
	var before = JSON.parse_string(FileAccess.get_file_as_string(compare_path))
	if not before is Dictionary:
		return
	var now := summary()
	L.append("## Before / after (%s -> %s)" % [str(before.get("label", "before")), label if label != "" else "now"])
	L.append("")
	L.append("Won, drawn and mean time over the ships without the kit; then each ship's win rate (one number: no earlier run had it).")
	L.append("")
	L.append("| | " + " | ".join(jumps.map(func(j): return "jump %d" % j)) + " | all |")
	L.append("|---|" + "---|".repeat(jumps.size() + 1))
	for key in ["win", "draw", "t"]:
		var cells := []
		for j in jumps:
			var b: Dictionary = before["jump"].get(str(j), {})
			var a: Dictionary = now["jump"][str(j)]
			cells.append(_delta(key, b, a))
		cells.append(_delta(key, before["all"], now["all"]))
		L.append("| %s | %s |" % [{"win": "won", "draw": "drawn", "t": "mean time"}[key], " | ".join(cells)])
	for sh in ships:
		var cells := []
		for j in jumps:
			var k := "%s@%d" % [sh["id"], j]
			var b: Dictionary = before["ship_jump"].get(k, {})
			cells.append(_delta("win", b, now["ship_jump"][k]) if int(b.get("n", 0)) > 0 else "%d%%" % roundi(100.0 * float(now["ship_jump"][k]["win"])) if int(now["ship_jump"][k]["n"]) > 0 else "-")
		L.append("| %s won | %s | |" % [sh["name"], " | ".join(cells)])
	L.append("")


static func _delta(key: String, b: Dictionary, a: Dictionary) -> String:
	if b.is_empty() or int(b.get("n", 0)) == 0:
		return "-"
	if key == "t":
		return "%d s -> %d s" % [roundi(b["t"]), roundi(a["t"])]
	return "%d%% -> %d%%" % [roundi(100.0 * float(b[key])), roundi(100.0 * float(a[key]))]


## Short flags against the targets: projected win rates by jump against TARGETS, the draw rate, the threat rating's order.
func reading() -> Array:
	var out := []
	var all := _rate(_sel(func(r): return true))
	out.append("Draws are %d%% of all fights%s; %d%% of all fights are won or were being won at the cap." % [roundi(100 * all["draw"]),
		" (many: fights are long, the cap cuts them short)" if all["draw"] > 0.15 else "", roundi(100 * all["proj"])])
	for j in jumps:
		if not TARGETS.has(j):
			continue
		var band: Array = TARGETS[j]
		var r := _rate(_sel(func(x): return x["jump"] == j and str(x["ship"]).ends_with("+kit") == band[2]))
		if r["n"] == 0:
			continue
		var inside: bool = r["proj"] >= band[0] - 1e-6 and r["proj"] <= band[1] + 1e-6
		out.append("Jump %d, the starters %s: projected %d%% (won %d%%), target %d-%d%%: %s." % [j, "with the kit" if band[2] else "bare",
			roundi(100 * r["proj"]), roundi(100 * r["win"]), roundi(100 * band[0]), roundi(100 * band[1]), "on target" if inside else "OFF TARGET"])
		for sh in ships:
			var rs := _rate(_sel(func(x): return x["ship"] == sh["id"] and x["jump"] == j))
			if rs["n"] > 0 and (rs["proj"] < band[0] - 0.15 or rs["proj"] > band[1] + 0.15):
				out.append("  %s at jump %d: projected %d%%, well outside it." % [sh["name"], j, roundi(100 * rs["proj"])])
	var last := 2.0
	for k in range(1, 6):
		var r := _rate(_sel(func(x): return x["skulls"] == k))
		if r["n"] >= 3:
			if r["win"] > last + 0.05:
				out.append("%d skulls win more often (%d%%) than fewer skulls: the cuts are out of order." % [k, roundi(100 * r["win"])])
			last = r["win"]
	return out
