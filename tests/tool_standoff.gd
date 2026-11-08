extends SceneTree
## Not a test (the runner only loads test_*.gd). The fight stand-off measurement of the Beta 3 `fixes4` track: is a stage 3-6 fight that
## runs to the cap (docs/audit/progression.md section 12) the game's doing, or the progression bot's?
## It builds a player-like ship for a stage from data/progression.json's median row (its guns, shield layers and power), with a human mix of
## weapons (lasers and the pulse line, what the shops and blueprints offer by then), and fights it through the real arena (as
## tests/tool_balance.gd does: both pilots on the AI, the crews in ShipSim, morale ending fights the way the game does, the player takes any
## surrender) against generated enemies of that stage that carry no shield, enemies that do, Hollow ghosts, and the Lattice wardens (the
## faction of morale style `hollow`, which never breaks: the control that a morale change must leave as it was), N seeds each.
##   godot --headless --path . --script res://tests/tool_standoff.gd [-- key=value ...]
## Keys: paim (what-if: the player pilot's aim_skill; 0.8+ snipes guns first), stages (default 3,4,5; 1 to 5 have a build), seeds (per stage and kind, default 20), cap (s, default 180), kinds (plain,shield,ghost,warden), jobs (processes, default 2),
## out (a JSON of every fight's row), sum (print the table of an out file instead of fighting: sum=<path,path>). Internal: shard (k/n), rows.
## What-ifs, for this run only (data/morale.json held in memory): break=<x> (break_structure), ghost_flee=<share> (the Hollow style: that share of
## the rolls flee, the rest fight on), shield_recharge=<x> (every shield part's recharge, seconds a layer), shield_cap (not here: stages 4+ have none).
## starters=1 (instead of the stages and kinds): the three starter ships as built (data/ships/starter_*.json) against generated stage 1 and 2
## pirates of threat 2 and 3 (rated against that starter, Threat.rate) and the authored Dental Plan, `seeds` each, through the arena's normal player AI;
## (only=courier,prism keeps just those starters) it prints the starter table: who wins, how long, and when the starter's first gun (and its last) is disabled. Not for a stage's player-like ship.
## Each row: the end, the time, the enemy's shield layers, the shots of the player and where they went (shield layer, hull, part), the
## structure the enemy lost, the time the guns were in range, and the enemy's own damage and shield use.
## cells=1 (the fights-end measurement, 2026-11): every (stage, faction, role) cell of `stages` (default 1,2,3,4,5) x `factions` (default the six base ones,
## CELL_FACTIONS) x the roles each flies (`roles`=a,b to keep some; a role the stage or the hull size never rolls, Shipgen.pick_role, is left out), `seeds`
## (default 12) enemies a cell, of any threat. Stages 1 to 3: the three starters take turns; stages 4 and 5: the prepared build (pbuild, default 7). Every fight carries the probe of tests/fight_probe.gd (what each
## side's shots did, guns, distance) and a capped one its class (FightProbe.classify). jsonl=<path>: each fight is a line appended as it ends, and a
## run started again skips the fights (and enemy searches) already in it, so a restarted machine loses one fight a process; run the shards yourself
## (shard=k/n, one jsonl each) and print the tables with sum=<path,path> (lines or JSON arrays).

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
const Probe = preload("res://tests/fight_probe.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const JUMPS_A_STAGE := 12.5  ## the progression bot's stages (docs/audit/progression.md): about this many jumps each
const FACTIONS := ["rustfangs", "concord", "lumen", "clans"]  ## the pirates a stage 3-6 region sends (the Hollow's ghosts are their own kind)
const MAX_TRIES := 600  ## seeds looked at to fill the plain / shield quotas of a stage
const FULL_TRIES := 100  ## hulls a build tries for one that mounts all its guns and shields
const STARTERS := {"courier": "res://data/ships/starter_courier.json", "rustbucket": "res://data/ships/starter_rustbucket.json", "prism": "res://data/ships/starter_prism.json"}
const DENTAL := "res://data/ships/dental_plan.json"  ## the authored stage-1 pirate QA met (threat 3, one shield layer)
const CELL_FACTIONS := ["rustfangs", "concord", "lumen", "wardens", "clans", "hollow"]  ## the six base factions of data/enemy_tables.json (cells=1)

## The player-like ship of each stage: size, weapons, shields, armour layers. Guns and shield layers are the median row of
## data/progression.json (stage 3: 5 guns, 2 layers; 4: 6 and 2; 5: 7 and 3; 6: 7 and 3), the mix is the one a shop and the blueprints
## give: Laser Mk1 and Mk2, Pulse Mk1 and Mk2 on the bow, the Laser Turret on the flanks. No missile, no ion: the bot never asks for one either.
## Every build mounts every gun it lists (build_from; tests/test_bench_builds.gd). Shipgen fits three bow guns and three flank turrets on these
## hulls, never a fourth of either, so the builds that listed four (5 to 7, until 2026-11) carry the same listed dps in fewer guns: 5 and 6 a Pulse
## Mk3 for the Pulse Mk2 and the fourth turret (12.27 hp/s listed, was 12.10), 7 two Laser Mk3 for two of its Laser Mk2, and no fourth turret
## (14.41, was 14.67). Build 1 takes a wider medium frame (30 wide), the only one of its seeds' hulls that mounts all four.
const BUILDS := {
	1: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1"], "shields": ["shield_mk1"], "armour": 0, "frame": {"width": 30, "max_interior": 26}},
	2: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1"], "shields": ["shield_mk1"], "armour": 1},
	3: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	4: {"size": "large", "weapons": ["laser_mk2", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	5: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk3", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
	6: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk3", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
	7: {"size": "large", "weapons": ["laser_mk3", "laser_mk3", "pulse_mk2", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk2", "shield_mk1"], "armour": 3},  # a well-prepared ship (the flagship bench pstage=7): better guns, a third layer and a plate more than the stage 6 median
}

var args := {}
static var style_only := ""  ## style=<id>: the enemies of the starters= mode are all of this faction or race (Beta 3 enemy identity)
static var role_only := ""  ## role=<id>: every enemy of the run is this role (a spec with :role:<id>)
static var want_skulls := 0  ## want=3: only the enemies of that threat (default: 2 and 3)
var cap := 180.0
var rows: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	cap = float(args.get("cap", cap))
	style_only = str(args.get("style", ""))
	want_skulls = int(args.get("want", 0))
	role_only = str(args.get("role", ""))
	if args.has("break"):
		Morale.config()["break_structure"] = float(args["break"])
	if args.has("ghost_flee"):
		Morale.config()["styles"]["hollow"] = {"surrender": 0.0, "flee": float(args["ghost_flee"]), "fight": 1.0 - float(args["ghost_flee"])}
	_run.call_deferred()


func _run() -> void:
	if args.has("sum"):
		for path in str(args["sum"]).split(","):
			rows.append_array(read_rows(path))
		if rows.any(func(r): return r.has("cell")):
			print(cells_table(rows))
			quit(0)
			return
		print(table(rows))
		if rows.any(func(r): return r.has("starter")):
			print(starter_table(rows))
		quit(0)
		return
	if args.has("cells"):
		run_cells()
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
		if args.has("starters"):
			for name in STARTERS:
				if args.has("only") and not str(args["only"]).split(",").has(name):  # only=rustbucket,prism: just those starters
					continue
				for st in Array(str(args.get("starter_stages", "1,2")).split(",")).map(func(x): return int(x)):
					for e in starter_enemies(name, st, n):
						k += 1
						if (k - 1) % shard[1] != shard[0]:
							continue
						var row := fight(st, e, name)
						rows.append(row)
						print("%s stage %d %-12s seed %d: %s in %.0f s (first gun out at %.0f s)" % [name, st, e["kind"], e["seed"], row["state"], row["t"], row.get("t_gun1", -1.0)])
			stages = []
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
		if rows.any(func(r): return r.has("starter")):
			print(starter_table(rows))
	quit(0)


## The rows of a file: a JSON array, or one JSON object a line (jsonl; lines that are no fight, the cached enemy searches, are left out).
static func read_rows(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var got = JSON.parse_string(text) if text.begins_with("[") else null
	if got is Array:
		return got
	var out: Array = []
	for line in text.split("\n", false):
		var r = JSON.parse_string(line)
		if r is Dictionary and r.has("state"):
			out.append(r)
	return out


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["stages", "seeds", "cap", "kinds", "break", "ghost_flee", "starters", "paim", "only", "style", "want", "starter_stages", "role"]:
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
	return build_from(stage, BUILDS[stage])


## The ship of build `b` (a BUILDS entry) for `stage` (its seeds): the first of FULL_TRIES hulls that mounts every gun and shield of it.
## Shipgen drops a gun that finds no wall to mount through, so a build's `frame` (keys of a data/enemy_tables.json size, `max` merged
## key by key) widens its size class until all of them fit.
static func build_from(stage: int, b: Dictionary) -> Ship:
	var f: Dictionary = Shipgen.tables()["factions"]["concord"]
	var sz: Dictionary = Shipgen.tables()["sizes"][b["size"]].duplicate(true)
	for k in b.get("frame", {}):
		if k == "max":
			sz["max"].merge(b["frame"]["max"], true)
		else:
			sz[k] = b["frame"][k]
	Shipgen._comps()
	var weapons: Array = b["weapons"]
	for attempt in FULL_TRIES:
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
		if not _has_all(ship, weapons + b["shields"]):
			continue
		ship.name = "Bench %d" % stage
		return ship
	return null


## Does `ship` carry every part of `ids` (with repeats)?
static func _has_all(ship: Ship, ids: Array) -> bool:
	var got := {}
	for uid in ship.components.instances:
		var id := str(ship.components.instances[uid]["id"])
		got[id] = int(got.get(id, 0)) + 1
	for id in ids:
		got[id] = int(got.get(id, 0)) - 1
		if int(got[id]) < 0:
			return false
	return true


## The campaign's danger of the first region whose pirates are `faction` (tool_balance.gd danger_for).
static func danger_for(faction: String) -> float:
	var best := INF
	for r in Content.regions():
		if str(r.get("enemies", "")) == faction:
			best = minf(best, float(r.get("danger", 1.0)))
	return best if best < INF else 1.0


## `n` enemies of `kind` ("plain": no shield part, "shield": at least one, "ghost": the Hollow's, "warden": the Lattice wardens', whose style never
## breaks) for stage `stage`: [{spec, faction, seed, layers}].
## The budget is the campaign's for the jump in the middle of the stage; the faction goes round the pirates of the stage's regions.
static func enemies(stage: int, kind: String, n: int) -> Array:
	var out: Array = []
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	var tries := 0
	while out.size() < n and tries < MAX_TRIES:
		var seed_value := 101 + tries * 7919 + stage * 31
		var faction: String = "hollow" if kind == "ghost" else ("wardens" if kind == "warden" else (style_only if style_only != "" else FACTIONS[tries % FACTIONS.size()]))
		tries += 1
		var budget := Shipgen.budget_for(tier, j, danger_for(str(Shipgen.tables()["factions"][faction].get("lines_as", faction))), "normal", stage)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var spec := Shipgen.spec(faction, Shipgen.pick_size(budget, rng), seed_value, budget, false, stage) + (":role:" + role_only if role_only != "" else "")
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


## Enemies for the starter ship `name` at stage `stage`: `n` generated pirates (the factions of FACTIONS in turn, shielded or not) of threat 2 and `n` of threat 3
## (rated against this starter), then `n` runs of the authored Dental Plan; [{spec, faction, seed, layers, kind, skulls}], kind "<name> t<skulls>" or "<name> dental".
static func starter_enemies(name: String, stage: int, n: int) -> Array:
	var mine: Ship = Session.load_ship(STARTERS[name])
	var out: Array = []
	var got := {2: 0, 3: 0}
	if want_skulls != 0:
		for k in got:
			got[k] = 0 if k == want_skulls else n  # only the wanted threat is looked for
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	var tries := 0
	while (got[2] < n or got[3] < n or (want_skulls < 0 and out.size() < n)) and tries < MAX_TRIES:
		var seed_value := 101 + tries * 7919 + stage * 31
		var faction: String = style_only if style_only != "" else FACTIONS[tries % FACTIONS.size()]
		tries += 1
		var budget := Shipgen.budget_for(tier, j, danger_for(str(Shipgen.tables()["factions"][faction].get("lines_as", faction))), "normal", stage)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var spec := Shipgen.spec(faction, Shipgen.pick_size(budget, rng), seed_value, budget, false, stage) + (":role:" + role_only if role_only != "" else "")
		var ship: Ship = Session.load_ship(spec)
		if ship == null:
			continue
		var sk: int = Threat.rate(ship, mine)["skulls"]
		if want_skulls < 0:  # want=-1 (a style that cannot reach three skulls at stage 1): the first n of any threat up to 3
			if sk > 3 or out.size() >= n:
				continue
			got[2] = n
			got[3] = n
			out.append({"spec": spec, "faction": faction, "seed": seed_value, "layers": Shields.layers_of_ship(ship, ship.power_state.get("powered", {})), "kind": "%s t%d" % [name, sk], "skulls": sk})
			continue
		if not got.has(sk) or got[sk] >= n:
			continue
		got[sk] += 1
		out.append({"spec": spec, "faction": faction, "seed": seed_value, "layers": Shields.layers_of_ship(ship, ship.power_state.get("powered", {})), "kind": "%s t%d" % [name, sk], "skulls": sk})
	if got[2] < n or got[3] < n:
		printerr("standoff: %s stage %d: threat 2: %d, threat 3: %d of %d in %d tries" % [name, stage, got[2], got[3], n, MAX_TRIES])
	if stage == 1 and style_only == "":
		var dental: Ship = Session.load_ship(DENTAL)
		var dsk: int = Threat.rate(dental, mine)["skulls"]
		for i in n:
			out.append({"spec": DENTAL, "faction": "rustfangs", "seed": 5000 + i * 131, "layers": Shields.layers_of_ship(dental, dental.power_state.get("powered", {})), "kind": "%s dental t%d" % [name, dsk], "skulls": dsk})
	return out


# --- the cells (cells=1) ---------------------------------------------------------------------------

## Does a ship of `size` at `stage` ever fly `role` (Shipgen.pick_role's rules: the least size, the first stage, no bay role where a stage's enemies carry none)?
static func role_fits(role: String, size: String, stage: int) -> bool:
	var r: Dictionary = Shipgen.tables()["roles"]["list"][role]
	var order: Array = ["small", "medium", "large"]
	var no_bay := float(Shipgen.tables().get("drones", {}).get("stage_mult", {}).get(str(stage), 1.0)) <= 0.0
	return order.find(size) >= order.find(str(r.get("min_size", "small"))) and not (no_bay and r.has("bay")) and stage >= int(r.get("min_stage", 0))


## `n` enemies of the cell (stage, faction, role), the seeds of enemies() for one faction, of any threat (the campaign rates nothing when it
## picks a fight, Campaign.gen_spec): [{spec, faction, role, seed, layers, size, kind, skulls, starter}]. With starters (stages 1 to 3) they take turns.
static func cell_enemies(stage: int, faction: String, role: String, n: int, starters: Array) -> Array:
	var out: Array = []
	var j := roundi(JUMPS_A_STAGE * (float(stage) - 0.5))
	var tier := 3 if j >= 25 else (2 if j >= 10 else 1)
	var budget := Shipgen.budget_for(tier, j, danger_for(str(Shipgen.tables()["factions"][faction].get("lines_as", faction))), "normal", stage)
	var mine := {}
	for name in starters:
		mine[name] = Session.load_ship(STARTERS[name])
	for tries in MAX_TRIES:
		if out.size() >= n:
			break
		var seed_value := 101 + tries * 7919 + stage * 31
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var size := Shipgen.pick_size(budget, rng)
		if not role_fits(role, size, stage):
			continue
		var spec := Shipgen.spec(faction, size, seed_value, budget, false, stage) + ":role:" + role
		var ship: Ship = Session.load_ship(spec)
		if ship == null or str(ship.get_meta("shipgen", {}).get("role", "")) != role:
			continue  # (a carrier that found no wall for its bay is a gunboat)
		var name: String = starters[out.size() % starters.size()] if not starters.is_empty() else ""
		out.append({"spec": spec, "faction": faction, "role": role, "seed": seed_value, "layers": Shields.layers_of_ship(ship, ship.power_state.get("powered", {})), "size": size,
			"kind": "%s %s" % [faction, role], "skulls": Threat.rate(ship, mine[name])["skulls"] if name != "" else -1, "starter": name})
	if out.size() < n:
		printerr("standoff: stage %d %s %s: %d of %d enemies in %d tries" % [stage, faction, role, out.size(), n, MAX_TRIES])
	return out


## The cells of cells=1, in order: [stage, faction, role].
func cells() -> Array:
	var out: Array = []
	for st in Array(str(args.get("stages", "1,2,3,4,5")).split(",")).map(func(x): return int(x)):
		for faction in (Array(str(args["factions"]).split(",")) if args.has("factions") else CELL_FACTIONS):
			for role in Shipgen.roles_of(str(faction)):
				if args.has("roles") and not str(args["roles"]).split(",").has(role):
					continue
				out.append([st, str(faction), str(role)])
	return out


## cells=1: this shard's cells (shard=k/n: every n-th cell), each fight a line of `jsonl` as it ends; what a line already holds is skipped.
func run_cells() -> void:
	var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
	var n := int(args.get("seeds", 12))
	var path := str(args.get("jsonl", OS.get_cache_dir().path_join("hullscrap_cells.jsonl")))
	var done := {}
	var searched := {}
	if FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var r = JSON.parse_string(line)
			if r is Dictionary and r.has("cell") and r.has("enemies"):
				searched[r["cell"]] = r["enemies"]
			elif r is Dictionary and r.has("key"):
				done[r["key"]] = true
				rows.append(r)
	var fa := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	fa.seek_end()
	var all := cells()
	for c in all.size():
		if c % shard[1] != shard[0]:
			continue
		var st: int = all[c][0]
		var key := "%d|%s|%s|%d" % [st, all[c][1], all[c][2], n]
		var foes: Array
		if searched.has(key):
			foes = searched[key]
		else:
			foes = cell_enemies(st, all[c][1], all[c][2], n, STARTERS.keys() if st <= 3 else [])
			fa.store_line(JSON.stringify({"cell": key, "enemies": foes}))
			fa.flush()
		for e in foes:
			var who: String = e["starter"] if e["starter"] != "" else "build%d" % int(args.get("pbuild", 7))
			var fkey := "%s|%d|%s|%s|%d" % [who, st, e["faction"], e["role"], int(e["seed"])]
			if done.has(fkey):
				continue
			var row := fight(st, e, str(e["starter"]), int(args.get("pbuild", 7)) if e["starter"] == "" else 0)
			row.merge({"key": fkey, "cell": "%d|%s|%s" % [st, e["faction"], e["role"]], "role": e["role"], "who": who, "esize": e["size"]})
			if row["state"] == "fighting":
				row["class"] = Probe.classify(row)
			rows.append(row)
			fa.store_line(JSON.stringify(row))
			fa.flush()
			print("%s stage %d %s %s seed %d: %s in %.0f s%s" % [who, st, e["faction"], e["role"], e["seed"], row["state"], row["t"], " (%s)" % row["class"] if row.has("class") else ""])
	fa.close()


# --- one fight -------------------------------------------------------------------------------------

## One fight of the player-like ship of `stage` (or of build `pbuild`, or the starter `starter`) against enemy `e`, `cap` seconds at most: its row.
func fight(stage: int, e: Dictionary, starter := "", pbuild := 0) -> Dictionary:
	var player: Ship = Session.load_ship(STARTERS[starter]) if starter != "" else build_player(pbuild if pbuild > 0 else stage)
	var enemy: Ship = Session.load_ship(e["spec"])
	var row := {"stage": stage, "kind": e["kind"], "faction": e["faction"], "seed": e["seed"], "spec": e["spec"], "e_layers": e["layers"]}
	if starter != "":
		row["starter"] = starter
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
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(args.get("paim", Threat.config()["player_aim"]))})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var d := {"p_shots": 0, "e_shots": 0, "p_hull": 0.0, "e_hull": 0.0, "p_part": 0.0, "e_part": 0.0, "p_shield": 0, "e_shield": 0, "p_hits": 0, "e_hits": 0,
		"in_range": 0, "samples": 0, "gap": 0.0, "cdist": 0.0, "bow30": 0, "t_half": -1.0, "t_break": -1.0, "t_gun1": -1.0, "t_guns": -1.0}
	var cursor := 0
	var n := 0
	var ticks := int(cap * 60.0)
	var probe := Probe.new(a, pilot)
	var brk := {}
	while sess.state() == "fighting" and n < ticks:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
			_sample(sess, pilot, d, n * STEP)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		var was: String = sess.morale.state
		sess.morale.tick(STEP)
		probe.step()
		if was == "steady" and sess.morale.state != "steady" and brk.is_empty():  # the enemy broke: when, why, and what it rolled
			brk = {"m_t": a.time(), "m_rolled": sess.morale.state, "m_at": Structure.structure_fraction(a.ships[Session.ENEMY]),
				"m_why": "unarmed" if sess.morale._unarmed >= float(sess.morale.cfg["unarmed_s"]) - 1e-6 else ("late" if sess.morale.break_after > 0.0 and a.time() >= sess.morale.break_after else "structure")}
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
	if st == "escaped" and sess.morale.style == "ghost":
		st = "faded"  # a ghost that thinned back into the Hollow: a won fight with nothing to salvage (Campaign.fight_done)
	row.merge({"state": st, "t": n * STEP, "foe_hull": Structure.structure_fraction(foe), "hull": Structure.structure_fraction(a.ships[Session.PLAYER]), "morale": sess.morale.state,
		"style": sess.morale.style, "e_aim": float(foe.ship.get_meta("ai", {}).get("aim_skill", -1.0)), "e_pilot": str(foe.ship.get_meta("ai", {}).get("style", ""))})
	row.merge(d)
	row.merge(probe.result())
	row.merge(brk)
	sim.free()
	return row


func _sample(sess: Session, pilot: PilotAI, d: Dictionary, t: float) -> void:
	var a = sess.arena
	var co = a.ships[Session.PLAYER]
	d["samples"] += 1
	var out := 0
	for uid in co.mounts:
		out += int(a.weapons.status_of(a, 0, uid) == "disabled")
	if out > 0 and d["t_gun1"] < 0.0:
		d["t_gun1"] = t  # the first gun of the player's ship disabled
	if out > 0 and out == co.mounts.size() and d["t_guns"] < 0.0:
		d["t_guns"] = t  # and the last
	var to_foe: Vector2 = a.ships[Session.ENEMY].flight.pos - co.flight.pos
	d["gap"] += to_foe.length() - pilot.extent(0, to_foe.normalized()) - pilot.extent(1, -to_foe.normalized())
	d["cdist"] += to_foe.length()  # centre to centre, and whether the foe's bow is within 30 degrees of pointing at us
	d["bow30"] += int(absf(angle_difference(a.ships[Session.ENEMY].flight.angle, (to_foe * -1.0).angle() + PI * 0.5)) < deg_to_rad(30.0))
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


## The table: per (stage, kind) the number of fights, the median and mean length, the share over 110 s and at the cap, how they ended (percent),
## and for the long ones (over 110 s) what the shots did.
static func table(list: Array) -> String:
	var L: Array[String] = []
	L.append("| stage | kind | n | median s | mean s | over 110 s | at cap | ends % (wreck / captured / spared / fled / faded / cap / lost) | enemy layers | p.power | e.power | p.dps | e.ehp |")
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
		var shares: Array[String] = []
		for end in ["won", "captured", "spared", "escaped", "faded", "fighting", "lost"]:
			shares.append(str(roundi(100.0 * int(ends.get(end, 0)) / sel.size())))
		L.append("| %d | %s | %d | %.0f | %.0f | %d%% | %d%% | %s | %.1f | %.0f | %.0f | %.1f | %.0f |" % [s, kind, sel.size(), _median(ts), _mean(ts), roundi(100.0 * over110 / sel.size()), roundi(100.0 * capped / sel.size()),
			" / ".join(shares), _mean(sel.map(func(r): return r["e_layers"])), _mean(sel.map(func(r): return r["p_power"])), _mean(sel.map(func(r): return r["e_power"])), _mean(sel.map(func(r): return r["p_dps"])), _mean(sel.map(func(r): return r["e_ehp"]))])
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



## The starter table: per (starter, stage, kind) the fights, the median length, who wins (the starter wrecks it, takes its surrender or capture, or it flees or fades;
## the starter is wrecked; neither at the cap), and the first gun disabled: the share of fights it happens in, and its median time (all guns: the same).
static func starter_table(list: Array) -> String:
	var L: Array[String] = []
	L.append("| starter | stage | enemy | n | median s | mean s | starter wins % | starter lost % | stalemate % | first gun out in % | at (median s) | all guns out in % | at (median s) | enemy dmg landed /s |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	var keys := {}
	for r in list:
		if r.has("starter"):
			keys["%s|%d|%s" % [r["starter"], int(r["stage"]), str(r["kind"])]] = [str(r["starter"]), int(r["stage"]), str(r["kind"])]
	var ks := keys.keys()
	ks.sort()
	for key in ks:
		var sel := list.filter(func(r): return r.get("starter", "") == keys[key][0] and int(r["stage"]) == keys[key][1] and str(r["kind"]) == keys[key][2] and str(r["state"]) != "error")
		if sel.is_empty():
			continue
		var n := float(sel.size())
		var lost := sel.filter(func(r): return str(r["state"]) == "lost").size()
		var cap := sel.filter(func(r): return str(r["state"]) == "fighting").size()
		var g1 := sel.filter(func(r): return float(r["t_gun1"]) >= 0.0).map(func(r): return float(r["t_gun1"]))
		var gall := sel.filter(func(r): return float(r["t_guns"]) >= 0.0).map(func(r): return float(r["t_guns"]))
		L.append("| %s | %d | %s | %d | %.0f | %.0f | %d | %d | %d | %d | %s | %d | %s | %s |" % [keys[key][0], keys[key][1], keys[key][2], sel.size(), _median(sel.map(func(r): return float(r["t"]))), _mean(sel.map(func(r): return float(r["t"]))),
			roundi(100.0 * (n - lost - cap) / n), roundi(100.0 * lost / n), roundi(100.0 * cap / n), roundi(100.0 * g1.size() / n), "%.0f" % _median(g1) if not g1.is_empty() else "-",
			roundi(100.0 * gall.size() / n), "%.0f" % _median(gall) if not gall.is_empty() else "-",
			"%.2f" % _mean(sel.map(func(r): return (float(r["p_hull"]) + float(r["p_part"])) / maxf(float(r["t"]), 1.0)))])
	return "\n".join(L)


## The cells table (cells=1 rows): per stage, then per (stage, faction) and per (stage, role), the fights, who wins (any end but a loss or the cap,
## as starter_table), the losses, the cap share and how the capped ones split into the classes of FightProbe.classify (percent of all the fights).
static func cells_table(list: Array) -> String:
	var L: Array[String] = ["| stage | group | n | wins % | lost % | at cap % | " + " | ".join(Probe.CLASSES) + " |", "|---|---|---|---|---|---|" + "---|".repeat(Probe.CLASSES.size())]
	var groups := {}
	for r in list:
		if str(r["state"]) == "error":
			continue
		for g in ["all", str(r["faction"]), "role " + str(r["role"]), "player " + str(r["who"])]:
			var k := "%d|%s" % [int(r["stage"]), g]
			if not groups.has(k):
				groups[k] = []
			groups[k].append(r)
	var ks := groups.keys()
	ks.sort_custom(func(x, y): return [int(x.get_slice("|", 0)), x.get_slice("|", 1) != "all", x.get_slice("|", 1)] < [int(y.get_slice("|", 0)), y.get_slice("|", 1) != "all", y.get_slice("|", 1)])
	for k in ks:
		var sel: Array = groups[k]
		var n := float(sel.size())
		var lost := sel.filter(func(r): return str(r["state"]) == "lost").size()
		var capped := sel.filter(func(r): return str(r["state"]) == "fighting")
		var bits: Array[String] = []
		for c in Probe.CLASSES:
			bits.append(str(roundi(100.0 * capped.filter(func(r): return Probe.classify(r) == c).size() / n)))
		L.append("| %s | %s | %d | %d | %d | %d | %s |" % [k.get_slice("|", 0), k.get_slice("|", 1), sel.size(), roundi(100.0 * (n - lost - capped.size()) / n), roundi(100.0 * lost / n),
			roundi(100.0 * capped.size() / n), " | ".join(bits)])
	return "\n".join(L)
