extends SceneTree
## Not a test (the runner only loads test_*.gd). The fight stand-off measurement of the Beta 3 `fixes4` track: is a stage 3-6 fight that
## runs to the cap (docs/audit/progression.md section 12) the game's doing, or the progression bot's?
## It builds a player-like ship for a stage from data/progression.json's median row (its guns, shield layers and power), with a human mix of
## weapons (lasers and the pulse line, what the shops and blueprints offer by then), and fights it through the real arena (as
## tests/tool_balance.gd does: both pilots on the AI, the crews in ShipSim, morale ending fights the way the game does, the player takes any
## surrender) against generated enemies of that stage that carry no shield, enemies that do, and Hollow ghosts, N seeds each.
##   godot --headless --path . --script res://tests/tool_standoff.gd [-- key=value ...]
## Keys: stages (default 3,4,5), seeds (per stage and kind, default 20), cap (s, default 180), kinds (plain,shield,ghost), jobs (processes, default 2),
## out (a JSON of every fight's row), sum (print the table of an out file instead of fighting: sum=<path,path>). Internal: shard (k/n), rows.
## What-ifs, for this run only (data/morale.json held in memory): break=<x> (break_structure), ghost_flee=<share> (the Hollow style: that share of
## the rolls flee, the rest fight on), shield_recharge=<x> (every shield part's recharge, seconds a layer), shield_cap (not here: stages 4+ have none).
## Each row: the end, the time, the enemy's shield layers, the shots of the player and where they went (shield layer, hull, part), the
## structure the enemy lost, the time the guns were in range, and the enemy's own damage and shield use.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Morale = preload("res://scripts/combat/morale.gd")
const Shields = preload("res://scripts/combat/shields.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const JUMPS_A_STAGE := 12.5  ## the progression bot's stages (docs/audit/progression.md): about this many jumps each
const FACTIONS := ["rustfangs", "concord", "lumen", "clans"]  ## the pirates a stage 3-6 region sends (the Hollow's ghosts are their own kind)
const MAX_TRIES := 600  ## seeds looked at to fill the plain / shield quotas of a stage

## The player-like ship of each stage: size, weapons, shields, armour layers. Guns and shield layers are the median row of
## data/progression.json (stage 3: 5 guns, 2 layers; 4: 6 and 2; 5: 7 and 3; 6: 7 and 3), the mix is the one a shop and the blueprints
## give: Laser Mk1 and Mk2, Pulse Mk1 and Mk2 on the bow, the Laser Turret on the flanks. No missile, no ion: the bot never asks for one either.
const BUILDS := {
	3: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	4: {"size": "large", "weapons": ["laser_mk2", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	5: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk2", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
	6: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk2", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
}

var args := {}
var cap := 180.0
var rows: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	cap = float(args.get("cap", cap))
	if args.has("break"):
		Morale.config()["break_structure"] = float(args["break"])
	if args.has("ghost_flee"):
		Morale.config()["styles"]["hollow"] = {"surrender": 0.0, "flee": float(args["ghost_flee"]), "fight": 1.0 - float(args["ghost_flee"])}
	_run.call_deferred()


func _run() -> void:
	if args.has("sum"):
		for path in str(args["sum"]).split(","):
			rows.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
		print(table(rows))
		quit(0)
		return
	var jobs := int(args.get("jobs", 2))
	if jobs > 1 and not args.has("shard"):
		_fan_out(jobs)
	else:
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var stages: Array = Array(str(args.get("stages", "3,4,5")).split(",")).map(func(x): return int(x))
		var kinds: Array = Array(str(args.get("kinds", "plain,shield,ghost")).split(","))
		var n := int(args.get("seeds", 20))
		var k := 0
		for st in stages:
			var player_info := {}
			for kind in kinds:
				for e in enemies(st, kind, n):
					k += 1
					if (k - 1) % shard[1] != shard[0]:
						continue
					var row := fight(st, e)
					rows.append(row)
					print("stage %d %-6s seed %d: %s in %.0f s (shield layers %d)" % [st, kind, e["seed"], row["state"], row["t"], row["e_layers"]])
	if args.has("rows"):
		_write(str(args["rows"]), JSON.stringify(rows))
	if args.has("out"):
		_write(str(args["out"]), JSON.stringify(rows))
	if not args.has("shard"):
		print(table(rows))
	quit(0)


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["stages", "seeds", "cap", "kinds", "break", "ghost_flee"]:
		if args.has(key):
			pass_on.append("%s=%s" % [key, args[key]])
	for k in jobs:
		var path := OS.get_cache_dir().path_join("hullscrap_standoff_%d_%d.json" % [OS.get_process_id(), k])
		files.append(path)
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_standoff.gd", "--",
			"shard=%d/%d" % [k, jobs], "rows=" + path] + pass_on))
	print("standoff: %d processes %s" % [jobs, str(pids)])
	while pids.any(func(p): return OS.is_process_running(p)):
		OS.delay_msec(500)
	for path in files:
		var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if got is Array:
			rows.append_array(got)
		else:
			printerr("standoff: a shard wrote nothing: " + path)


# --- the ships -------------------------------------------------------------------------------------

## The player-like ship of `stage`: Shipgen's own pipeline (the hull grammar of the Concord, the real mount rules, cables, validation)
## with the loadout of BUILDS instead of a bought one. Null when it cannot be built.
static func build_player(stage: int) -> Ship:
	var b: Dictionary = BUILDS[stage]
	var f: Dictionary = Shipgen.tables()["factions"]["concord"]
	var sz: Dictionary = Shipgen.tables()["sizes"][b["size"]]
	Shipgen._comps()
	var weapons: Array = b["weapons"]
	for attempt in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + stage * 100 + attempt
		var lo := {"weapons": weapons.duplicate(), "engines": ["engine_mk1", "engine_mk1", "engine_mk1"], "shields": b["shields"].duplicate(), "systems": [], "reactors": [],
			"armour": int(b["armour"]), "crew": 4, "skill": 0.75, "beds": 2, "spent": 0.0, "helm": "helm", "o2": str(f["parts"]["base"]["o2"])}
		lo["reactors"] = Shipgen._reactors(f, lo, sz["max"], 1.0e9)["ids"]
		var t: int = int(lo["armour"]) + 1
		var prow := rng.randi_range(int(f["hull"]["prow"][0]), int(f["hull"]["prow"][1]))
		var tail := rng.randi_range(int(f["hull"]["tail"][0]), int(f["hull"]["tail"][1]))
		var ras := {}
		var bands: Array = []
		for boost in 4:
			bands = Shipgen._plan(lo, sz, f, boost, prow, tail)
			var y := t
			var avoid: Array = []
			for bd in bands:
				bd["y0"] = y
				bd["y1"] = y + int(bd["h"]) - 1
				y = int(bd["y1"]) + 2
				if bd["rooms"].any(func(r): return r["kind"] == "turret"):
					avoid.append([bd["y0"], bd["y1"]])
			var rows_n: int = y - 1 + t
			Shipgen.Hullgen.extents(f, bands, int(sz["max_interior"]), rng, boost, t)
			var hull = Shipgen.Hullgen.make(f, bands, t, rows_n, rng, {"level": 2, "ram": false, "avoid": avoid, "boost": boost})
			var r = Shipgen.Hullgen.raster(hull["outline"])
			if r["errors"].is_empty() and Shipgen.Hullgen.fill_ratio(r["cells"]) < Shipgen.MAX_FILL:
				ras = r
				break
		if ras.is_empty():
			continue
		var made := Shipgen._construct(f, "concord", lo, bands, ras["cells"], t, false, rng)
		if made["ship"] == null:
			continue
		var ship: Ship = made["ship"]
		if not Shipgen.validate(ship).is_empty():
			continue
		ship.name = "Bench %d" % stage
		return ship
	return null


## The campaign's danger of the first region whose pirates are `faction` (tool_balance.gd danger_for).
static func danger_for(faction: String) -> float:
	var best := INF
	for r in Content.regions():
		if str(r.get("enemies", "")) == faction:
			best = minf(best, float(r.get("danger", 1.0)))
	return best if best < INF else 1.0


## `n` enemies of `kind` ("plain": no shield part, "shield": at least one, "ghost": the Hollow's) for stage `stage`: [{spec, faction, seed, layers}].
## The budget is the campaign's for the jump in the middle of the stage; the faction goes round the pirates of the stage's regions.
static func enemies(stage: int, kind: String, n: int) -> Array:
	var out: Array = []
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	var tries := 0
	while out.size() < n and tries < MAX_TRIES:
		var seed_value := 101 + tries * 7919 + stage * 31
		var faction: String = "hollow" if kind == "ghost" else FACTIONS[tries % FACTIONS.size()]
		tries += 1
		var budget := Shipgen.budget_for(tier, j, danger_for(faction), "normal", stage)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var spec := Shipgen.spec(faction, Shipgen.pick_size(budget, rng), seed_value, budget, false, stage)
		var ship: Ship = Session.load_ship(spec)
		if ship == null:
			continue
		var layers := Shields.layers_of_ship(ship, ship.power_state.get("powered", {}))
		if kind == "plain" and layers > 0 or kind == "shield" and layers == 0:
			continue
		out.append({"spec": spec, "faction": faction, "seed": seed_value, "layers": layers, "kind": kind})
	if out.size() < n:
		printerr("standoff: stage %d %s: only %d of %d found in %d tries" % [stage, kind, out.size(), n, MAX_TRIES])
	return out


# --- one fight -------------------------------------------------------------------------------------

func fight(stage: int, e: Dictionary) -> Dictionary:
	var player := build_player(stage)
	var enemy: Ship = Session.load_ship(e["spec"])
	var row := {"stage": stage, "kind": e["kind"], "faction": e["faction"], "seed": e["seed"], "spec": e["spec"], "e_layers": e["layers"]}
	if player == null or enemy == null:
		row["state"] = "error"
		row["t"] = 0.0
		return row
	var th := Threat.rate(enemy, player)
	var pw := Threat.power(player, 0.75)
	var ew := Threat.power(enemy, 0.75)
	row.merge({"skulls": th["skulls"], "ratio": th["ratio"], "p_power": pw["power"], "e_power": ew["power"], "e_dps": ew["dps"], "e_ehp": ew["ehp"], "p_dps": pw["dps"],
		"p_ehp": pw["ehp"], "size": enemy.get_meta("shipgen", {}).get("size", "?"), "e_guns": enemy.get_meta("shipgen", {}).get("weapons", []).size()})
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var d := {"p_shots": 0, "e_shots": 0, "p_hull": 0.0, "e_hull": 0.0, "p_part": 0.0, "e_part": 0.0, "p_shield": 0, "e_shield": 0, "p_hits": 0, "e_hits": 0,
		"in_range": 0, "samples": 0, "gap": 0.0, "t_half": -1.0, "t_break": -1.0}
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
			var fs := Structure.structure_fraction(a.ships[Session.ENEMY])
			if d["t_half"] < 0.0 and fs <= 0.75:
				d["t_half"] = n * STEP
			if d["t_break"] < 0.0 and sess.morale.state != "" and sess.morale.state != "fighting" and sess.morale.state != "calm":
				d["t_break"] = n * STEP
		cursor = _scan(a, cursor, d)
	cursor = _scan(a, cursor, d)
	var st := sess.state()
	var foe = a.ships[Session.ENEMY]
	row.merge({"state": st, "t": n * STEP, "foe_hull": Structure.structure_fraction(foe), "hull": Structure.structure_fraction(a.ships[Session.PLAYER]), "morale": sess.morale.state})
	row.merge(d)
	sim.free()
	return row


func _sample(sess: Session, pilot: PilotAI, d: Dictionary) -> void:
	var a = sess.arena
	var co = a.ships[Session.PLAYER]
	d["samples"] += 1
	var to_foe: Vector2 = a.ships[Session.ENEMY].flight.pos - co.flight.pos
	d["gap"] += to_foe.length() - pilot.extent(0, to_foe.normalized()) - pilot.extent(1, -to_foe.normalized())
	var reach := false
	for uid in co.mounts:
		var m: Dictionary = co.mounts[uid]
		if a.weapons.status_of(a, 0, uid) != "ok" or not co.powered.get(uid, false):
			continue
		var w: Dictionary = a.weapons.def(m["id"])
		if a.weapons.muzzle_of(a, 0, m).distance_to(pilot.aim_for(m, false)) <= float(w["range"]):
			reach = true
	d["in_range"] += int(reach)


## Count the arena's new events into `d`, by attacker (p: the player, e: the enemy): shots, shots a shield layer stopped, hits, the damage of
## the hits on hull and on parts. A shot that is none of those missed.
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
				d[other + "_hits"] += 1
				if e.get("kind", "") == "component":
					d[other + "_part"] += float(e.get("dealt", 0.0))
				else:
					d[other + "_hull"] += float(e.get("dealt", 0.0))
			"shield":
				d[other + "_shield"] += 1  # a shot of `other` stopped by a shield layer of `who`
	return ev.size()


# --- the table -------------------------------------------------------------------------------------

static func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return float(s[s.size() / 2]) if s.size() % 2 == 1 else (float(s[s.size() / 2 - 1]) + float(s[s.size() / 2])) / 2.0


static func _mean(v: Array) -> float:
	var t := 0.0
	for x in v:
		t += float(x)
	return t / maxf(float(v.size()), 1.0)


## The table: per (stage, kind) the number of fights, the median and mean length, the share over 110 s and at the cap, how they ended,
## and for the long ones (over 110 s) what the shots did.
static func table(list: Array) -> String:
	var L: Array[String] = []
	L.append("| stage | kind | n | median s | mean s | over 110 s | at cap | decided (wreck/capt/spared/escaped) | enemy layers | p.power | e.power | p.dps | e.ehp |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	var keys := {}
	for r in list:
		keys["%d|%s" % [int(r["stage"]), str(r["kind"])]] = [int(r["stage"]), str(r["kind"])]
	var ks := keys.keys()
	ks.sort()
	for key in ks:
		var s: int = keys[key][0]
		var kind: String = keys[key][1]
		var sel := list.filter(func(r): return int(r["stage"]) == s and str(r["kind"]) == kind and str(r["state"]) != "error")
		if sel.is_empty():
			continue
		var ts := sel.map(func(r): return float(r["t"]))
		var over110 := sel.filter(func(r): return float(r["t"]) > 110.0).size()
		var capped := sel.filter(func(r): return str(r["state"]) == "fighting").size()
		var ends := {}
		for r in sel:
			ends[str(r["state"])] = int(ends.get(str(r["state"]), 0)) + 1
		L.append("| %d | %s | %d | %.0f | %.0f | %d%% | %d%% | %s | %.1f | %.0f | %.0f | %.1f | %.0f |" % [s, kind, sel.size(), _median(ts), _mean(ts), roundi(100.0 * over110 / sel.size()), roundi(100.0 * capped / sel.size()),
			str(ends), _mean(sel.map(func(r): return r["e_layers"])), _mean(sel.map(func(r): return r["p_power"])), _mean(sel.map(func(r): return r["e_power"])), _mean(sel.map(func(r): return r["p_dps"])), _mean(sel.map(func(r): return r["e_ehp"]))])
	L.append("")
	L.append("Why the long ones (over 110 s) are long: per (stage, kind), the means of the fights over 110 s.")
	L.append("")
	L.append("| stage | kind | n | p.shots | stopped by a shield % | hit hull or part % | missed % | hp dealt | enemy structure left | in range % | mean gap px | enemy shots | enemy shots on my shield % |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for key in ks:
		var s: int = keys[key][0]
		var kind: String = keys[key][1]
		var sel := list.filter(func(r): return int(r["stage"]) == s and str(r["kind"]) == kind and str(r["state"]) != "error" and float(r["t"]) > 110.0)
		if sel.is_empty():
			continue
		var shots := _mean(sel.map(func(r): return r["p_shots"]))
		var sh := _mean(sel.map(func(r): return r["p_shield"]))
		var hits := _mean(sel.map(func(r): return r["p_hits"]))
		var es := _mean(sel.map(func(r): return r["e_shots"]))
		L.append("| %d | %s | %d | %.0f | %.0f | %.0f | %.0f | %.0f | %.2f | %.0f | %.0f | %.0f | %.0f |" % [s, kind, sel.size(), shots, 100.0 * sh / maxf(shots, 1.0), 100.0 * hits / maxf(shots, 1.0),
			100.0 * maxf(shots - sh - hits, 0.0) / maxf(shots, 1.0), _mean(sel.map(func(r): return float(r["p_hull"]) + float(r["p_part"]))), _mean(sel.map(func(r): return r["foe_hull"])),
			100.0 * _mean(sel.map(func(r): return float(r["in_range"]) / maxf(float(r["samples"]), 1.0))), _mean(sel.map(func(r): return float(r["gap"]) / maxf(float(r["samples"]), 1.0))), es,
			100.0 * _mean(sel.map(func(r): return r["e_shield"])) / maxf(es, 1.0)])
	return "\n".join(L)
