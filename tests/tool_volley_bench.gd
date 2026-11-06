extends SceneTree
## Not a test (the runner only loads test_*.gd). The Volley against Ripple bench of docs/GUNS.md 14: a stage player-like ship
## (tests/tool_standoff.gd BUILDS) with a strong or a weak shield, every fire group in Ripple or in Volley (and optionally Piercing on
## its rapid guns), against the same generated enemies; per cell: wins, mean fight seconds, the player's hull at the end, and the share
## of the fight the player's sector facing the enemy was open (it had just fired) and was down (no shield HP).
##   godot --headless --path . --script res://tests/tool_volley_bench.gd [-- stages=3,5 seeds=8 kinds=shield,plain cap=120 out=<path>]
## Shields: strong = the best the stage's shop sells, twice; weak = one scrap generator.

const Ship = preload("res://scripts/ship/ship.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Standoff = preload("res://tests/tool_standoff.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3
const SHIELDS := {"strong": ["shield_mk2", "shield_mk2"], "weak": ["shield_scrap_mk1"]}

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var stages: Array = str(args.get("stages", "3,5")).split(",")
	var kinds: Array = str(args.get("kinds", "shield,plain")).split(",")
	var seeds := int(args.get("seeds", 8))
	var out := []
	for st in stages:
		for kind in kinds:
			var foes: Array = Standoff.enemies(int(st), kind, seeds)
			for sh in ["strong", "weak"]:
				for mode in ["ripple", "volley", "volley+ap"]:
					var rows := []
					for e in foes:
						rows.append(_fight(int(st), sh, mode, e))
					out.append(_cell(int(st), kind, sh, mode, rows))
					print(out[-1]["line"])
	if args.has("out"):
		var f := FileAccess.open(str(args["out"]), FileAccess.WRITE)
		f.store_string(JSON.stringify(out))
	quit()


const BUILDS := {
	1: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1"], "shields": ["shield_mk1"], "armour": 0},
	2: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1"], "shields": ["shield_mk1"], "armour": 1},
	3: {"size": "medium", "weapons": ["laser_mk1", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	4: {"size": "large", "weapons": ["laser_mk2", "laser_mk1", "pulse_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2"], "armour": 1},
	5: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk2", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
	6: {"size": "large", "weapons": ["laser_mk2", "laser_mk2", "pulse_mk2", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1", "laser_turret_mk1"], "shields": ["shield_mk2", "shield_mk1"], "armour": 2},
}


static func build_player(stage: int, shields: Array) -> Ship:
	var b: Dictionary = BUILDS[stage].duplicate()
	b["shields"] = shields
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



func _fight(stage: int, shield: String, mode: String, e: Dictionary) -> Dictionary:
	var player: Ship = build_player(stage, SHIELDS[shield])
	var enemy: Ship = Session.load_ship(e["spec"])
	var row := {"state": "error", "t": 0.0, "hull": 0.0, "open": 0.0, "down": 0.0}
	if player == null or enemy == null:
		return row
	if mode != "ripple":
		for g in [0, 1, 2, 3]:
			player.volley_groups[g] = true
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	if mode == "volley+ap":
		player.inventory.add("piercing_rounds", 400)
		for uid in sess.arena.ships[0].mounts:
			sess.arena.weapons.set_ap(sess.arena, 0, uid, true)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": 0.75})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var n := 0
	var open := 0
	var down := 0
	var ticks := int(float(args.get("cap", 120)) * 60.0)
	while sess.state() == "fighting" and n < ticks:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		var co = a.ships[0]
		if co.layers_cap > 0 and not co.wrecked:
			var s := Shields.sector_of_world_dir(co, a.ships[1].flight.pos - co.flight.pos)
			open += int(Shields.sector_open(co, s, a.tick))
			down += int(float(co.sector_layers[s]) <= Shields.EPS)
		if n % SIM_EVERY == 0:
			sim.step(SIM_EVERY * STEP)
	var st := sess.state()
	row.merge({"state": st, "t": n * STEP, "hull": Structure.structure_fraction(a.ships[0]), "open": float(open) / maxf(n, 1.0), "down": float(down) / maxf(n, 1.0)}, true)
	sim.free()
	return row


func _cell(stage: int, kind: String, shield: String, mode: String, rows: Array) -> Dictionary:
	var wins := 0
	var t := 0.0
	var hull := 0.0
	var open := 0.0
	var down := 0.0
	for r in rows:
		wins += int(r["state"] in ["won", "captured", "spared", "escaped"])
		t += r["t"]
		hull += r["hull"]
		open += r["open"]
		down += r["down"]
	var k := float(maxi(rows.size(), 1))
	var line := "stage %d | foe %-6s | %-6s shield | %-9s | wins %d/%d | fight %5.1fs | hull %3.0f%% | facing sector open %4.1f%% down %4.1f%%" % [stage, kind, shield, mode, wins, rows.size(), t / k, 100.0 * hull / k, 100.0 * open / k, 100.0 * down / k]
	return {"stage": stage, "kind": kind, "shield": shield, "mode": mode, "wins": wins, "n": rows.size(), "t": t / k, "hull": hull / k, "open": open / k, "down": down / k, "line": line}


