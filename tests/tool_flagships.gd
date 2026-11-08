extends SceneTree
## Not a test (the runner only loads test_*.gd). The flagship workshop (data/flagships.json, data/packs/flagships_1/ships/flagship_<race>.json):
##   godot --headless --path . --script res://tests/tool_flagships.gd -- make [races=kett,basalt]
##     builds each flagship's hull and fit-out from SPECS below with Shipgen's own hull grammar, real mount rules and checks (a larger
##     frame than any generated class), applies its hand edits and writes the design file. The designs are committed; this is how they were drawn.
##   godot --headless --path . --script res://tests/tool_flagships.gd -- bench [races=kett] [seeds=12] [cap=180] [stage=3] [jobs=2]
##     fights each flagship against the player-like ship of its stage (tests/tool_standoff.gd BUILDS) and prints win rate, mean time, stalemates.
##     Every fight carries the probe of tests/fight_probe.gd and a capped one its class. designs=<dir>: the flagship_<race>.json files of that folder
##     instead of the pack's; late=0: no time-based yield (the design's break_after_s is dropped); jsonl=<path>: each fight a line appended as it ends,
##     and a run started again skips what the file holds (run the shards yourself: shard=k/n, one jsonl each); sum=<path,path>: the tables of jsonl files.
##     What-ifs on the designs as they are (no new hull): aim=<x> (the flagship pilot's aim_skill), yield=<frac> (it yields after losing that share of its blocks),
##     style=<id> (its pilot style, pilot_ai.gd), hold=<x> (its ai.hold_fraction: the share of its guns' range it holds at), gun_hp=<x> (every gun of both
##     ships that many times as tough, the inside and the outside half).
##     run=<structure>: the bench player jumps away as a player would (J, the 10 s spool and its holds) once its structure is at or under that (0.75:
##     half way to the wreck line, where the hull creaks) or it has had no working gun for RUN_UNARMED_S; the fight then ends "fled", a loss.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Threat = preload("res://scripts/space/threat.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Standoff = preload("res://tests/tool_standoff.gd")
const Specs = preload("res://tests/flagship_specs.gd")
const Probe = preload("res://tests/fight_probe.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const OUT := "res://data/packs/flagships_1/ships/flagship_%s.json"
const RUN_UNARMED_S := 10.0  ## run=: seconds with no working gun after which the bench player jumps away
## The frame of a flagship: wider and deeper than the generated `large` class (data/enemy_tables.json sizes).
const FRAME := {"width": 42, "k_mid": 3, "max_interior": 36, "max": {"bow": 6, "flank": 6, "engine": 4, "reactor": 5, "shield": 3, "armour": 4, "crew": 14, "beds": 4}}

## Per race: the fit-out (weapons, engines, shields, systems, reactors, armour layers, crew, aim skill), the hull seed to start trying
## from, the ram flag, the crew species (weighted by repetition), the captain, and the morale style of its ai.
var SPECS := {}

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	SPECS = Specs.SPECS
	_run.call_deferred()


func _races() -> Array:
	var all: Array = SPECS.keys()
	all.sort()
	return Array(str(args["races"]).split(",")) if args.has("races") else all


func _run() -> void:
	if args.has("make"):
		for r in _races():
			make(str(r))
	elif args.has("sum"):
		var rows: Array = []
		for path in str(args["sum"]).split(","):
			rows.append_array(Standoff.read_rows(path))
		print(summary(rows))
		print(class_table(rows))
	elif args.has("bench"):
		bench()
	elif args.has("power"):
		for r in _races():
			power(str(r))
	quit(0)


# --- making ----------------------------------------------------------------------------------------

func make(race: String) -> void:
	var sp: Dictionary = SPECS[race]
	var ship: Ship = null
	var seed_used := 0
	for k in int(args.get("tries", 12)):
		seed_used = int(sp["hull_seed"]) + k
		ship = build(race, sp, seed_used)
		if ship != null:
			break
	if ship == null:
		printerr("flagship %s: no hull built; last: %s" % [race, str(Shipgen.last_failed)])
		return
	if sp.has("ammo"):  # a flagship carries its guns' ammo in plenty (Shipgen stocks 40 of each kind, which a slug mortar spends in 13 shots)
		for uid in ship.components.instances:
			var wid := str(ship.components.instances[uid]["id"])
			var ammo := str(Shipgen._weapons.def(wid).get("ammo", "")) if Shipgen._weapons.has(wid) else ""
			if ammo != "" and ship.inventory.count(ammo) < int(sp["ammo"]):
				ship.inventory.add(ammo, int(sp["ammo"]) - ship.inventory.count(ammo))
	var d := ship.to_dict()
	d["name"] = str(sp["ship"])
	d["crew_plan"] = []
	var species: Array = sp["crew"]
	var names: Array = sp["names"]
	for i in names.size():
		d["crew_plan"].append({"name": names[i], "species": species[i % species.size()]})
	d["ai"] = {"aim_skill": float(sp["aim"]), "morale": str(sp["morale"]), "faction": "flagship_" + race, "captain": str(sp["captain"]), "break_structure": snappedf(1.0 - (float(sp["yield_hp"]) / maxf(Structure.totals(ship).y, 1.0) if sp.has("yield_hp") else float(sp.get("yield_frac", 0.1))), 0.001)}  # it yields after losing yield_frac of its blocks (or yield_hp of them)
	if float(sp.get("after_s", 0.0)) > 0.0:
		d["ai"]["break_after_s"] = float(sp["after_s"])  # a time-based yield (none since fights-end 2026-11: a flagship yields on damage only)
	if sp.has("hold"):
		d["ai"]["hold_fraction"] = float(sp["hold"])  # it fights closer than the 0.7 of its guns' range others keep (pilot_ai.gd)
	if bool(sp.get("ram", false)):
		d["ai"]["style"] = "rammer"
	d["flagship"] = {"race": race, "role": str(sp.get("role", "flagship"))}
	var fl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/flagships.json"))["flagships"].get(race, {})
	d["blurb"] = "%s: %s" % [str(fl.get("name", sp["ship"])), str(fl.get("gimmick", ""))]
	d.erase("crew_state")
	d.erase("dead_crew")
	var f := FileAccess.open(OUT % race, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "", true, true))
	f.close()
	var lo: Dictionary = ship.get_meta("shipgen")
	print("flagship %s: built (hull seed %d, tries %d), %d parts, hull %s" % [race, seed_used, int(lo.get("attempts", 0)), ship.components.instances.size(), str(ship.grid.size)])


## The ship of `sp` for hull seed `seed_value`, or null.
func build(race: String, sp: Dictionary, seed_value: int) -> Ship:
	var f: Dictionary = Shipgen.tables()["factions"][race]
	var sz := FRAME.duplicate(true)
	sz["max_interior"] = int(sp.get("interior", FRAME["max_interior"]))
	Shipgen._comps()
	var ram := bool(sp.get("ram", false))
	for attempt in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 31 + attempt
		var lo := {"weapons": sp["weapons"].duplicate(), "engines": sp["engines"].duplicate(), "shields": sp["shields"].duplicate(), "systems": sp["systems"].duplicate(),
			"reactors": sp["reactors"].duplicate(), "armour": int(sp["armour"]), "crew": sp["names"].size(), "skill": float(sp["aim"]), "beds": int(sp.get("beds", 2)), "spent": 0.0,
			"helm": str(sp.get("helm", f["parts"]["base"]["helm"])), "o2": str(sp.get("o2", f["parts"]["base"]["o2"]))}
		while lo["reactors"].size() < 5 and _supply(lo) < Shipgen._demand(f, lo) + 2.0:
			lo["reactors"].append("reactor_mk2")  # the power has to cover the demand without the crew, or Shipgen trims the last guns
		var t: int = int(lo["armour"]) + 1
		var prow := rng.randi_range(int(f["hull"]["prow"][0]), int(f["hull"]["prow"][1])) + int(sp.get("prow_add", 1))
		var tail := rng.randi_range(int(f["hull"]["tail"][0]), int(f["hull"]["tail"][1])) + 1
		if ram:
			prow = maxi(prow, 5)
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
			var hull = Shipgen.Hullgen.make(f, bands, t, rows_n, rng, {"level": 2, "ram": ram, "avoid": avoid, "boost": boost})
			var r = Shipgen.Hullgen.raster(hull["outline"])
			if r["errors"].is_empty() and Shipgen.Hullgen.fill_ratio(r["cells"]) < float(f["hull"].get("max_fill", Shipgen.MAX_FILL)):
				ras = r
				break
		if ras.is_empty():
			if args.has("v"):
				print("  seed %d attempt %d: no outline" % [seed_value, attempt])
			continue
		var made := Shipgen._construct(f, race, lo, bands, ras["cells"], t, ram, rng)
		if made["ship"] == null:
			if args.has("v"):
				print("  seed %d attempt %d: %s" % [seed_value, attempt, made["why"]])
			continue
		var ship: Ship = made["ship"]
		edit(ship, sp)
		var want := {}
		for id in lo["weapons"] + lo["engines"] + lo["shields"] + lo["systems"] + lo["reactors"]:
			want[id] = int(want.get(id, 0)) + 1
		var got := {}
		for uid in ship.components.instances:
			var gid := str(ship.components.instances[uid]["id"])
			got[gid] = int(got.get(gid, 0)) + 1
		var missing := false
		for id in want:
			missing = missing or int(got.get(id, 0)) < int(want[id])
		if missing:
			if args.has("v"):
				var net: Array = ship.power_state["networks"]
				var diff := []
				for id in want:
					if int(got.get(id, 0)) < int(want[id]):
						diff.append("%s %d/%d" % [id, int(got.get(id, 0)), int(want[id])])
				print("  seed %d attempt %d: dropped %s; power %s" % [seed_value, attempt, str(diff), str(net.map(func(n): return "%s/%s" % [str(n["supply"]), str(n["demand"])]))])
			continue  # a mount that found no clean wall is dropped silently by Shipgen: a flagship keeps every part it was drawn with
		var why :=Shipgen.validate(ship, minf(float(f["hull"].get("max_fill", Shipgen.MAX_FILL)) + 0.01, 0.9))  # (tests/test_flagships.gd checks 0.9)
		if not why.is_empty():
			if args.has("v"):
				print("  seed %d attempt %d: invalid %s" % [seed_value, attempt, str(why[0])])
			continue
		ship.set_meta("shipgen", {"attempts": attempt + 1})
		return ship
	return null


## The power the reactors of `lo` give with nobody in their rooms.
static func _supply(lo: Dictionary) -> float:
	var total := 0.0
	for id in lo["reactors"]:
		total += Shipgen._power(str(id))
	return total


## The hand edits after the hull is built (a thin rear band, and so on): `edits` of the spec.
func edit(ship: Ship, sp: Dictionary) -> void:
	for e in sp.get("edits", []):
		match str(e["op"]):
			"rear_tiles":  # the outer armour of the last `rows` rows becomes `tile`
				var g = ship.grid
				var hi := 0
				for c in g.tiles:
					hi = maxi(hi, c.y)
				for c in g.tiles.keys():
					if c.y > hi - int(e["rows"]) and str(g.get_tile(c)) == str(e["from"]):
						g.force_tile(c, str(e["tile"]), {})
	ship.mark_dirty()
	ship.refresh()


## Threat.power of the design file of `race` against the player-like ship of its stage (no fight): a quick look while tuning.
func power(race: String) -> void:
	var stage := int(args.get("stage", SPECS[race]["stage"]))
	var foe: Ship = Session.load_ship(OUT % race)
	var mine: Ship = Standoff.build_player(stage)
	var f := Threat.power(foe, float(SPECS[race]["aim"]))
	var p := Threat.power(mine, 0.75)
	print("POWER %-10s s%d  dps %.2f (%.2f)  ehp %.0f (%.0f)  power %.1f (%.1f)  ratio %.2f  grid %s" % [race, stage, f["dps"], p["dps"], f["ehp"], p["ehp"], f["power"], p["power"], float(f["power"]) / float(p["power"]), str(foe.grid.size)])


# --- the bench -------------------------------------------------------------------------------------

func bench() -> void:
	var seeds := int(args.get("seeds", 12))
	var cap := float(args.get("cap", 180))
	var jobs := int(args.get("jobs", 1))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/flagships.json"))["flagships"] if FileAccess.file_exists("res://data/flagships.json") else {}
	var rows := []
	if jobs > 1 and not args.has("shard"):
		var files := []
		var pids := []
		var pass_on := []
		for key in ["races", "seeds", "cap", "stage", "first", "v", "pstage", "lag", "designs", "late", "aim", "yield", "run", "style", "hold", "gun_hp"]:
			if args.has(key):
				pass_on.append("%s=%s" % [key, args[key]])
		for k in jobs:
			var path := OS.get_cache_dir().path_join("hullscrap_flagships_%d_%d.json" % [OS.get_process_id(), k])
			files.append(path)
			pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_flagships.gd", "--", "bench",
				"shard=%d/%d" % [k, jobs], "rows=" + path] + pass_on))
		while pids.any(func(p): return OS.is_process_running(p)):
			OS.delay_msec(500)
		for path in files:
			var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			if got is Array:
				rows.append_array(got)
			else:
				printerr("a shard wrote nothing: " + path)
	else:
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var k := 0
		var done := {}
		var fa: FileAccess = null
		if args.has("jsonl"):
			if FileAccess.file_exists(str(args["jsonl"])):
				for r in Standoff.read_rows(str(args["jsonl"])):
					done[r["key"]] = true
					rows.append(r)
			fa = FileAccess.open(str(args["jsonl"]), FileAccess.READ_WRITE if FileAccess.file_exists(str(args["jsonl"])) else FileAccess.WRITE)
			fa.seek_end()
		for race in _races():
			var stage := int(args.get("stage", meta[race]["stage"] if meta.has(race) else 3))
			for s in range(int(args.get("first", 0)), int(args.get("first", 0)) + seeds):
				k += 1
				if (k - 1) % shard[1] != shard[0]:
					continue
				var key := "%s|%s|%d" % [race, str(args.get("pstage", stage)), s]
				if done.has(key):
					continue
				var row := fight(str(race), stage, s, cap)
				row.merge({"race": race, "stage": stage, "seed": s, "key": key, "pstage": int(args.get("pstage", stage))})
				if row["state"] == "fighting":
					row["class"] = Probe.classify(row)
				rows.append(row)
				if fa != null:
					fa.store_line(JSON.stringify(row))
					fa.flush()
					print("%s seed %d (player %s): %s in %.0f s%s" % [race, s, str(row["pstage"]), row["state"], row["t"], " (%s)" % row["class"] if row.has("class") else ""])
		if fa != null:
			fa.close()
		if args.has("rows"):
			var f := FileAccess.open(str(args["rows"]), FileAccess.WRITE)
			f.store_string(JSON.stringify(rows))
			f.close()
			return
	if args.has("v"):
		rows.sort_custom(func(x, y): return [x["race"], x["seed"]] < [y["race"], y["seed"]])
		for row in rows:
			print("  %s seed %d: %s in %.0f s (foe hull %.2f, mine %.2f) shots p/e %d/%d, shields stopped p/e %d/%d, dealt hull p/e %.0f/%.0f, parts %.0f/%.0f" % [row["race"], row["seed"], row["state"], row["t"], row["foe_hull"], row["hull"], row["p_shots"], row["e_shots"], row["p_shield"], row["e_shield"], row["p_hull"], row["e_hull"], row["p_part"], row["e_part"]])
	print(summary(rows))
	print(class_table(rows))


## Per (race, player build): the fights, the wins (won, captured, spared), the losses (wrecked, or fled with run=), the cap share and the classes of the capped ones (FightProbe.classify),
## the mean time, and the hp each side landed a second on the other's blocks (p: the player).
static func class_table(rows: Array) -> String:
	var L: Array[String] = ["| race | player | n | win % | lost % | cap % | " + " | ".join(Probe.CLASSES) + " | mean s | p hp/s | e hp/s |", "|---|---|---|---|---|---|" + "---|".repeat(Probe.CLASSES.size() + 3)]
	var by := {}
	for r in rows:
		var k := "%s|%s" % [r["race"], str(r.get("pstage", r["stage"]))]
		if not by.has(k):
			by[k] = []
		by[k].append(r)
	var ks := by.keys()
	ks.sort()
	for k in ks:
		var sel: Array = by[k]
		var n := float(sel.size())
		var capped := sel.filter(func(r): return str(r["state"]) == "fighting")
		var bits: Array[String] = []
		for c in Probe.CLASSES:
			bits.append(str(roundi(100.0 * capped.filter(func(r): return Probe.classify(r) == c).size() / n)))
		var mean := func(f: Callable) -> float: return sel.reduce(func(acc, r): return acc + float(f.call(r)), 0.0) / n
		L.append("| %s | %s | %d | %d | %d | %d | %s | %.0f | %.2f | %.2f |" % [k.get_slice("|", 0), k.get_slice("|", 1), sel.size(), roundi(100.0 * sel.filter(func(r): return r["state"] in ["won", "captured", "spared"]).size() / n),
			roundi(100.0 * sel.filter(func(r): return r["state"] in ["lost", "fled"]).size() / n), roundi(100.0 * capped.size() / n), " | ".join(bits), mean.call(func(r): return r["t"]),
			mean.call(func(r): return (float(r.get("p_hull", 0.0)) + float(r.get("p_part", 0.0))) / maxf(float(r["t"]), 1.0)), mean.call(func(r): return (float(r.get("e_hull", 0.0)) + float(r.get("e_part", 0.0))) / maxf(float(r["t"]), 1.0))])
	return "\n".join(L)


static func summary(rows: Array) -> String:
	var by := {}
	for r in rows:
		if not by.has(r["race"]):
			by[r["race"]] = []
		by[r["race"]].append(r)
	var keys: Array = by.keys()
	keys.sort()
	var out: Array[String] = []
	for race in keys:
		var list: Array = by[race]
		var wins := 0
		var stale := 0
		var total := 0.0
		var ends := {}
		for r in list:
			ends[r["state"]] = int(ends.get(r["state"], 0)) + 1
			wins += int(r["state"] in ["won", "captured", "spared"])
			stale += int(r["state"] == "fighting")
			total += float(r["t"])
		out.append("BENCH %-10s stage %d: win %d/%d (%.0f%%), mean %.0f s, stalemate %d/%d, ends %s" % [race, int(list[0]["stage"]), wins, list.size(), 100.0 * wins / list.size(), total / list.size(), stale, list.size(), JSON.stringify(ends)])
	return "\n".join(out)


## The what-if gun_hp=: the hp of every gun of `ship` (its parts' and their outside halves') times `k`.
static func _scale_guns(ship: Ship, k: float) -> void:
	var comps = ship.components
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var d: Dictionary = comps.by_id.get(str(inst["id"]), {})
		if str(d.get("family", "")) != "weapon":
			continue
		if not d.has("_scaled"):
			d["hp"] = roundi(float(d.get("hp", 5)) * k)
			d["_scaled"] = true
		inst["hp"] = float(inst["hp"]) * k
		inst["out_hp"] = float(inst["out_hp"]) * k


## Count the arena's new events into `d` by attacker (p: the player, e: the flagship): shots, shots a shield layer stopped, the damage on hull and on parts.
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


func fight(race: String, stage: int, s: int, cap: float) -> Dictionary:
	var player: Ship = Standoff.build_player(int(args["pstage"]) if args.has("pstage") else maxi(stage - int(args.get("lag", 0)), 1))  # pstage=<n>, or lag=<k> (the stage k below the flagship's): a lighter player-like ship, "a starter and a few upgrades"
	var enemy: Ship = Session.load_ship(str(args["designs"]).path_join("flagship_%s.json" % race) if args.has("designs") else OUT % race)
	var row := {"state": "error", "t": 0.0, "foe_hull": 1.0, "hull": 1.0}
	if player == null or enemy == null:
		return row
	if args.has("aim"):
		enemy.get_meta("ai")["aim_skill"] = float(args["aim"])
	if args.has("style"):
		enemy.get_meta("ai")["style"] = str(args["style"])
	if args.has("hold"):
		enemy.get_meta("ai")["hold_fraction"] = float(args["hold"])
	if args.has("gun_hp"):  # what-if: every gun of both ships (inside and outside half) that many times as tough
		for sh in [player, enemy]:
			_scale_guns(sh, float(args["gun_hp"]))
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + s * 7919)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	if str(args.get("late", "")) == "0":
		sess.morale.break_after = 0.0  # no time-based yield: it yields on damage only
	if args.has("yield"):
		sess.morale.break_at = 1.0 - float(args["yield"])
	var a = sess.arena
	var n := 0
	var ticks := int(cap * 60.0)
	var d := {"p_shots": 0, "e_shots": 0, "p_hull": 0.0, "e_hull": 0.0, "p_part": 0.0, "e_part": 0.0, "p_shield": 0, "e_shield": 0}
	var cursor := 0
	var probe := Probe.new(a, pilot)
	var run_at := float(args.get("run", -1.0))
	var unarmed := 0.0
	var fled := false
	while sess.state() == "fighting" and n < ticks and not fled:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		probe.step()
		n += 1
		if run_at > 0.0 and sess.jump_charge < 0.0:
			unarmed = unarmed + STEP if probe.working(Session.PLAYER) == 0 else 0.0
			if unarmed >= RUN_UNARMED_S or (n % SIM_EVERY == 0 and Structure.structure_fraction(a.ships[Session.PLAYER]) <= run_at + 1e-6):
				sess.start_jump()
				row["t_run"] = n * STEP
		if sess.jump_charge >= 0.0 and sess.state() == "fighting" and sess.jump_hold() == "":
			sess.jump_charge += STEP
			fled = sess.jump_ready()
		if n % SIM_EVERY == 0:
			sim.step(SIM_EVERY * STEP)
			cursor = _scan(a, cursor, d)
	cursor = _scan(a, cursor, d)
	row.merge(d)
	row.merge(probe.result())
	row["break_at"] = sess.morale.break_at
	row["morale"] = sess.morale.state
	row["state"] = "fled" if fled else sess.state()
	row["t"] = n * STEP
	row["foe_hull"] = Structure.structure_fraction(a.ships[Session.ENEMY])
	row["hull"] = Structure.structure_fraction(a.ships[Session.PLAYER])
	sim.free()
	return row
