extends SceneTree
## Not a test (the runner only loads test_*.gd). The measurement of the `repairs` track: how long crew last without air, how long their jobs take, and
## what the crews do in real fights (the same fights as tests/tool_standoff.gd flies, through the real arena and ShipSim).
##   godot --headless --path . --script res://tests/tool_repairs.gd [-- key=value ...]
## Output, in order:
##  1. breath: per kind of crew, seconds from full hp in an airless room until air.hurt_below and until down (crew.json damage_per_s.no_air x the
##     trait's damage_taken.no_air x suffocate_mult; "-" = takes no harm), and the work seconds of each job at a plain crew member's rate, side by side.
##  2. fights (the starters at stage 1, 3 skulls, `seeds` each; `s3` and `s5` fights of the stage 3 and stage 5 player-like ship, half plain, half shielded
##     enemies): crew downed from no air, crew-seconds in airless rooms, jobs started in an airless room and how many were finished, repair hp a
##     second against the damage a second each side takes, rooms lost (Jobs lost_rooms) and the end of the fight.
##  3. the Concord case: the Rustbucket against Concord pirates of 3 skulls at stage 1 (`concord` fights), the enemy crew's repair rate against the
##     player's damage, and the Rustbucket's result.
## What-ifs for this run (crew.json in memory): under_s, under_mult (under_fire), lost_min, lost_share (lost), margin (air.breath_margin).
## Keys: seeds (per starter, default 24), s3 / s5 (default 12 each), concord (default 15; 0 skips), cap (s, default 180), jobs (processes, default 3),
## only (starters, e.g. rustbucket,prism), breath=0 (skip the table), out (JSON of every row), sum (print the tables of out files, sum=a.json,b.json).
## Internal: shard (k/n), rows. A job "started in an airless room" is one whose room had less air than crew.json no_air_below the first time it was seen
## on a crew member; "finished" means it left the board with its work all but done (within 0.8 s of work) when it was last sampled.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Standoff = preload("res://tests/tool_standoff.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Content = preload("res://scripts/data/content.gd")
const Evacuate = preload("res://scripts/crew/evacuate.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const SIM_DT := SIM_EVERY * STEP

var args := {}
var rows: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var cfg := CrewMember.config()
	if args.has("under_s"):
		cfg["under_fire"]["seconds"] = float(args["under_s"])
	if args.has("under_mult"):
		cfg["under_fire"]["mult"] = float(args["under_mult"])
	if args.has("lost_min"):
		cfg["lost"]["min_open"] = int(args["lost_min"])
	if args.has("lost_share"):
		cfg["lost"]["share"] = float(args["lost_share"])
	if args.has("margin"):
		cfg["air"]["breath_margin"] = float(args["margin"])
	_run.call_deferred()


func _run() -> void:
	if args.has("sum"):
		for path in str(args["sum"]).split(","):
			rows.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
		print(tables(rows))
		quit(0)
		return
	if not args.has("shard"):
		if str(args.get("breath", "1")) != "0":
			print(breath_table())
	var jobs := int(args.get("jobs", 3))
	if jobs > 1 and not args.has("shard"):
		_fan_out(jobs)
	else:
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var k := 0
		for item in plan():
			k += 1
			if (k - 1) % shard[1] != shard[0]:
				continue
			var row := fight(item)
			rows.append(row)
			print("%s %s seed %d: %s in %.0f s" % [row["set"], row["kind"], row["seed"], row["state"], row["t"]])
	if args.has("rows"):
		_write(str(args["rows"]), JSON.stringify(rows))
	if args.has("out"):
		_write(str(args["out"]), JSON.stringify(rows))
	if not args.has("shard"):
		print(tables(rows))
	quit(0)


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["seeds", "s3", "s5", "concord", "cap", "only", "under_s", "under_mult", "lost_min", "lost_share", "margin"]:
		if args.has(key):
			pass_on.append("%s=%s" % [key, args[key]])
	for k in jobs:
		var path := OS.get_cache_dir().path_join("hullscrap_repairs_%d_%d.json" % [OS.get_process_id(), k])
		files.append(path)
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_repairs.gd", "--",
			"shard=%d/%d" % [k, jobs], "rows=" + path, "breath=0"] + pass_on))
	print("repairs: %d processes %s" % [jobs, str(pids)])
	while pids.any(func(p): return OS.is_process_running(p)):
		OS.delay_msec(500)
	for path in files:
		var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if got is Array:
			rows.append_array(got)
		else:
			printerr("repairs: a shard wrote nothing: " + path)


# --- the breath table ------------------------------------------------------------------------------

## The kinds of crew: a plain human, then one per trait of the library that changes breathing (o2_use, suffocate_mult, vacuum_walk, damage_taken.no_air).
static func kinds() -> Array:
	var out: Array = [["plain human", []], ["suit (EVA)", ["suit"]]]
	var lib = Content.read("res://data/traits.json")
	var traits: Dictionary = lib.get("traits", {}) if lib is Dictionary else {}
	var ids: Array = traits.keys()
	ids.sort()
	for id in ids:
		var t: Dictionary = traits[id]
		if id == "suit" or not (t is Dictionary):
			continue
		var dt: Dictionary = t.get("damage_taken", {}) if t.get("damage_taken") is Dictionary else {}
		if t.has("o2_use") or t.has("suffocate_mult") or t.has("vacuum_walk") or dt.has("no_air"):
			out.append(["%s" % id, [id]])
	return out


## Hp a second a crew member with `gear` loses in an airless room (0 = none).
static func suffocation(gear: Array) -> float:
	var m := CrewMember.new("T", Vector2.ZERO, "human")
	m.gear_traits = gear.duplicate()
	var t := TraitSet.of(m)
	if float(t["o2_use"]) <= 0.0 or bool(t["vacuum_walk"]):
		return 0.0
	return float(CrewMember.config()["damage_per_s"]["no_air"]) * float(t["damage_taken"]["no_air"]) * float(t["suffocate_mult"])


## Table 1: the seconds each kind of crew lasts, and the work of each job.
func breath_table() -> String:
	var cfg := CrewMember.config()
	var hurt := float(cfg["air"]["hurt_below"])
	var L: Array[String] = ["=== breath: full hp, an airless room (no_air %s hp/s, hurt_below %.2f, hp %s) ===" % [cfg["damage_per_s"]["no_air"], hurt, cfg["hp"]]]
	var window := 1.0e9
	var plain_hurt := 0.0
	for k in kinds():
		var r := suffocation(k[1])
		var hp := float(cfg["hp"])
		var t_hurt := (hp * (1.0 - hurt)) / r if r > 0.0 else -1.0
		var t_down := hp / r if r > 0.0 else -1.0
		if k[0] == "plain human":
			plain_hurt = t_hurt
		L.append("  %-14s %s  to hurt_below %s  to down %s" % [k[0], "%.2f hp/s" % r if r > 0.0 else "no harm  ", "%6.1f s" % t_hurt if t_hurt >= 0.0 else "     -", "%6.1f s" % t_down if t_down >= 0.0 else "     -"])
		window = minf(window, t_hurt) if t_hurt >= 0.0 else window
	var ship: Ship = Session.load_ship(Standoff.STARTERS["rustbucket"])
	var j: Dictionary = cfg["jobs"]
	var mult := float(ship.lines["standard"]["repair"])
	var rows_: Array = []
	rows_.append(["repair_breach (standard wall)", float(j["repair_breach"]["seconds"]) * mult])
	for tile in [["wall", 4.0, "standard"], ["scrap_plate", 3.0, "scrap"], ["heavy_armor", 10.0, "standard"], ["ram_plating", 12.0, "standard"]]:
		rows_.append(["repair_block %s from 0 hp (%d hp)" % [tile[0], int(tile[1])], float(j["repair_block"]["seconds_per_hp"]) * tile[1] * float(ship.lines[tile[2]]["repair"])])
	for id in ["laser_mk1", "shield_mk1", "reactor_mk1"]:
		if ship.components.has_def(id) if ship.components.has_method("has_def") else true:
			rows_.append(["repair_component %s" % id, float(j["repair_component"]["seconds"]) * float(ship.effective(id)["repair_mult"])])
	L.append("  work seconds at a plain crew member's rate (before walking), next to the plain human's %.1f s to hurt_below:" % plain_hurt)
	for r in rows_:
		var work: float = r[1]
		L.append("    %-44s %5.1f s   %s" % [r[0], work, "one breath (x1.25 with 2 s of walking)" if work * 1.0 + 2.0 <= plain_hurt / 1.25 else "NOT on one breath"])
	return "\n".join(L)


# --- the fights ------------------------------------------------------------------------------------

## What to fight: [{set, starter?, stage, e (enemy entry)}...]
func plan() -> Array:
	var out: Array = []
	var only: Array = str(args["only"]).split(",") if args.has("only") else []
	var n := int(args.get("seeds", 24))
	for name in Standoff.STARTERS:
		if not only.is_empty() and not only.has(name):
			continue
		var list := Standoff.starter_enemies(name, 1, n).filter(func(e): return int(e["skulls"]) == 3 and not str(e["kind"]).contains("dental"))
		for e in list.slice(0, n):
			out.append({"set": "starters", "starter": name, "stage": 1, "e": e})
	for st in [3, 5]:
		var m := int(args.get("s%d" % st, 12))
		if m <= 0:
			continue
		var list: Array = Standoff.enemies(st, "plain", m / 2) + Standoff.enemies(st, "shield", m - m / 2)
		for e in list:
			out.append({"set": "stage%d" % st, "stage": st, "e": e})
	var c := int(args.get("concord", 15))
	if c > 0 and (only.is_empty() or only.has("rustbucket")):
		var seen := {}
		for e in Standoff.starter_enemies("rustbucket", 1, 60):
			if e["faction"] == "concord" and int(e["skulls"]) == 3 and not str(e["kind"]).contains("dental") and not seen.has(e["seed"]):
				seen[e["seed"]] = true
				if seen.size() <= c:
					out.append({"set": "concord", "starter": "rustbucket", "stage": 1, "e": e})
	return out


## One fight, as tool_standoff.fight flies it, with the crews watched every sim step.
func fight(item: Dictionary) -> Dictionary:
	var e: Dictionary = item["e"]
	var starter: String = item.get("starter", "")
	var player: Ship = Session.load_ship(Standoff.STARTERS[starter]) if starter != "" else Standoff.build_player(int(item["stage"]))
	var enemy: Ship = Session.load_ship(e["spec"])
	var row := {"set": item["set"], "starter": starter, "stage": item["stage"], "kind": e["kind"], "faction": e["faction"], "seed": e["seed"]}
	if player == null or enemy == null:
		row["state"] = "error"
		row["t"] = 0.0
		return row
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(args.get("paim", Threat.config()["player_aim"]))})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var side := [_side(), _side()]
	var track := [{}, {}]
	var struct := [Structure.totals(player).x, Structure.totals(enemy).x]
	var cursor := 0
	var n := 0
	var ticks := int(float(args.get("cap", 180)) * 60.0)
	while sess.state() == "fighting" and n < ticks:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n % SIM_EVERY == 0:
			sim.step(SIM_DT)
			var dealt := [0.0, 0.0]
			var ev: Array = a.events
			for k in range(cursor, ev.size()):
				if str(ev[k]["type"]) == "hit":
					dealt[int(ev[k]["ship"])] += float(ev[k].get("dealt", 0.0))
			cursor = ev.size()
			for s in 2:
				var ship: Ship = a.ships[s].ship
				var now := Structure.totals(ship).x
				side[s]["dmg"] += dealt[s]
				side[s]["rep"] += maxf(now - struct[s] + dealt[s], 0.0)
				struct[s] = now
				_watch(ship, sim.jobs_of(ship), side[s], track[s])
	row.merge({"state": sess.state(), "t": n * STEP, "p": side[0], "e": side[1]})
	sim.free()
	return row


static func _side() -> Dictionary:
	return {"air_cs": 0.0, "down_air": 0, "down_air_job": 0, "air_started": 0, "air_done": 0, "rep": 0.0, "dmg": 0.0, "lost": 0, "lost_fight": 0, "_lost": {}, "peaks": {}, "took_downs": []}


## One sample of the crew of `ship`: time in airless rooms, downs from no air, airless jobs begun and finished, rooms lost.
func _watch(ship, jobs, d: Dictionary, tr: Dictionary) -> void:
	var at = ship.atmosphere
	var limit := float(CrewMember.config()["no_air_below"])
	for m in ship.crew:
		if m.is_drone():
			continue
		var exempt := Jobs.air_exempt(m)
		var room: int = at.room_at(m.cell())
		var airless: bool = room >= 0 and at.pressure_of(room) < limit
		var t: Dictionary = tr.get(m.name, {})
		if airless and not exempt:
			d["air_cs"] += SIM_DT
		var down: bool = m.is_down()
		if down and not t.get("down", false) and t.get("airless", false) and not exempt:
			d["down_air"] += 1
			if bool(t.get("took", false)):  # they took an airless job and have not been in air since
				d["down_air_job"] += 1
				d["took_downs"].append("%s hp %.0f job %s work %.1f left, t %.0f" % [m.name, float(t.get("hp", 0.0)), str(t.get("job", "")), float(t.get("work", 0.0)) - float(t.get("prog", 0.0)), ship.clock])
		var key := str(m.job.get("key", "")) if not m.job.is_empty() else ""
		var air_job: bool = bool(t.get("air_job", false))
		if key != str(t.get("job", "")):
			if air_job and not exempt and float(t.get("prog", 0.0)) >= float(t.get("work", 1.0e9)) - 0.8:
				d["air_done"] += 1
			air_job = false
			if key != "" and not exempt and float(m.job.get("work", 0.0)) > 0.0 and Jobs._job_airless(ship, m.job):
				d["air_started"] += 1
				air_job = true
		var took: bool = ((bool(t.get("took", false)) and airless) or air_job) and not down  # (one revived in the same room is no longer on a job of their own)
		t = {"hp": m.hp, "took": took, "down": down, "airless": airless, "job": key, "job_type": str(m.job.get("type", "")) if key != "" else "", "air_job": air_job,
			"prog": float(jobs.progress.get(key, 0.0)) if key != "" else 0.0, "work": float(m.job.get("work", 0.0)) if key != "" else 0.0}
		tr[m.name] = t
	for o in Evacuate.openings(ship):  # how open each room got, to tune crew.json lost: [open, edge] of the most open moment
		var k := "%d,%d" % [o["key"].x, o["key"].y]
		var prev: Array = d["peaks"].get(k, [0, 1])
		if o["open"] > prev[0]:
			d["peaks"][k] = [o["open"], o["edge"]]
	var lost = ship.get("lost_rooms")
	if lost is Array:
		for id in lost:
			if not d["_lost"].has(id):
				d["_lost"][id] = true
				d["lost"] += 1
		d["lost_fight"] = 1 if d["lost"] > 0 else 0


# --- the tables ------------------------------------------------------------------------------------

static func _mean(v: Array) -> float:
	var t := 0.0
	for x in v:
		t += float(x)
	return t / maxf(float(v.size()), 1.0)


static func _sum(list: Array, side: String, key: String) -> float:
	var t := 0.0
	for r in list:
		if r.has(side):
			t += float(r[side][key])
	return t


static func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if s.size() % 2 == 1 else (float(s[s.size() / 2 - 1]) + float(s[s.size() / 2])) / 2.0


## One group of rows: results, then the crew lines of each side.
static func block(title: String, list: Array) -> Array[String]:
	var L: Array[String] = []
	if list.is_empty():
		return L
	var won := list.filter(func(r): return not str(r["state"]) in ["lost", "fighting"]).size()  # (the audit's "non-loss": spared, captured, enemy fled; not a stalemate at the cap)
	var states := {}
	for r in list:
		states[r["state"]] = int(states.get(r["state"], 0)) + 1
	var ts: Array = list.map(func(r): return float(r["t"]))
	L.append("--- %s: %d fights, non-loss %d (%.0f%%; stalemates at the cap are not), median %.0f s, ends %s" % [title, list.size(), won, 100.0 * won / list.size(), _median(ts), JSON.stringify(states)])
	var T := _sum(list, "p", "air_cs") * 0.0 + _sum(list.map(func(r): return {"x": {"t": r["t"]}}), "x", "t")
	for s in [["p", "player"], ["e", "enemy "]]:
		var started := _sum(list, s[0], "air_started")
		L.append("    %s: downed from no air %d (after taking an airless job %d), crew-s in airless rooms %.0f, airless jobs started %d / finished %d, repair %.2f hp/s vs damage taken %.2f hp/s, rooms lost %d in %d fights" % [
			s[1], _sum(list, s[0], "down_air"), _sum(list, s[0], "down_air_job"), _sum(list, s[0], "air_cs"), started, _sum(list, s[0], "air_done"),
			_sum(list, s[0], "rep") / maxf(T, 1.0), _sum(list, s[0], "dmg") / maxf(T, 1.0), _sum(list, s[0], "lost"), _sum(list, s[0], "lost_fight")])
	return L


static func tables(list: Array) -> String:
	var L: Array[String] = ["=== fights ==="]
	for name in Standoff.STARTERS:
		L.append_array(block("%s, stage 1, 3 skulls" % name, list.filter(func(r): return r["set"] == "starters" and r["starter"] == name)))
	L.append_array(block("all three starters", list.filter(func(r): return r["set"] == "starters")))
	for st in [3, 5]:
		L.append_array(block("stage %d player-like ship" % st, list.filter(func(r): return r["set"] == "stage%d" % st)))
	L.append("=== the Concord case: Rustbucket against Concord pirates, 3 skulls, stage 1 ===")
	var c := list.filter(func(r): return r["starter"] == "rustbucket" and r["faction"] == "concord" and r["stage"] == 1 and r["set"] in ["concord", "starters"])
	var seen := {}
	var uniq: Array = []
	for r in c:
		if not seen.has(r["seed"]):
			seen[r["seed"]] = true
			uniq.append(r)
	L.append_array(block("rustbucket vs concord", uniq))
	if not uniq.is_empty():
		var T := 0.0
		for r in uniq:
			T += float(r["t"])
		L.append("    enemy crew repairs %.2f hp/s; the player deals %.2f hp/s to it (the enemy's damage taken); the player's crew repair %.2f hp/s against %.2f hp/s taken" % [
			_sum(uniq, "e", "rep") / T, _sum(uniq, "e", "dmg") / T, _sum(uniq, "p", "rep") / T, _sum(uniq, "p", "dmg") / T])
	return "\n".join(L)
