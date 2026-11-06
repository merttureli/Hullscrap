extends SceneTree
## Not a test (the runner only loads test_*.gd). The drone bench of docs/DRONES.md section 9: a starter with a drone bay and Pulse Drone Mk I (it replaces the
## starter's weakest gun) against the stage 1 and 2 enemies, against the same starter as it is (with that gun). Both through the real arena, the pilots on the AI
## (the player's bay launches by the same rule as an enemy's: Drones.ai_launch); the table says who wins, how long it takes, and what the hull lost.
##   godot --headless --path . --script res://tests/tool_drone_bench.gd [-- seeds=8 kit=pulse_drone_mk1 only=courier,prism,rustbucket stages=1,2 cap=150]
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Threat = preload("res://scripts/space/threat.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Standoff = preload("res://tests/tool_standoff.gd")

const STEP := 1.0 / 60.0
const SIM_EVERY := 12
const PLAYER_EVERY := 3

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var seeds := int(args.get("seeds", 8))
	var kit := str(args.get("kit", "pulse_drone_mk1"))
	var cap := float(args.get("cap", 150.0))
	var names: Array = str(args.get("only", "courier,prism,rustbucket")).split(",")
	var stages: Array = str(args.get("stages", "1,2")).split(",")
	for name in names:
		var probe = variant(name, true, kit)
		if probe == null:
			print("%s: no room for a bay, even without its weakest gun" % name)
			continue
		print("== %s: bay '%s' replaces %s" % [name, kit, probe.get_meta("bench_removed", "?")])
		for st in stages:
			var stage := int(st)
			var list: Array = Standoff.starter_enemies(name, stage, seeds)
			var rows := {"bay": [], "gun": []}
			for e in list:
				for which in ["bay", "gun"]:
					rows[which].append(fight(name, which == "bay", kit, e, cap))
			print("stage %d, %d fights each (threat 2 and 3 pirates)" % [stage, list.size()])
			for which in ["gun", "bay"]:
				print("  %-4s %s" % [which, summary(rows[which])])
	quit()


## The starter `name` as it is (bay false), or with its weakest gun swapped for a bay loaded with `kit` and 6 drone parts (null when no bay fits).
static func variant(name: String, bay: bool, kit: String):
	var ship = Session.load_ship(Standoff.STARTERS[name])
	if not bay:
		return ship
	var weakest := -1
	var low := INF
	var weapons = Weapons.new()
	for uid in ship.components.instances:
		var id := str(ship.components.instances[uid]["id"])
		if str(ship.components.def(id).get("family", "")) == "weapon" and weapons.has(id):
			var w: Dictionary = weapons.def(id)
			var dps := float(w["damage"]) * maxf(1.0, float(w["shots"])) / maxf(float(w["cooldown"]), 0.1)
			if dps < low:
				low = dps
				weakest = uid
	if weakest < 0:
		return null
	ship.set_meta("bench_removed", str(ship.components.instances[weakest]["id"]))
	ship.components.remove_uid(weakest)
	var tier := int(Drones.kit(kit)["drone"]["tier"])
	var uid := Shipgen.add_bay(ship, "drone_bay_mk%d" % maxi(tier, 1), kit, [1, 3, 2, 0])
	if uid < 0:
		return null
	ship.inventory.add(kit, 1)
	ship.inventory.add(Drones.PART, 6)
	return ship


func fight(name: String, bay: bool, kit: String, e: Dictionary, cap: float) -> Dictionary:
	var player = variant(name, bay, kit)
	var enemy = Session.load_ship(e["spec"])
	var row := {"state": "error", "t": 0.0}
	if player == null or enemy == null:
		return row
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var n := 0
	var ticks := int(cap * 60.0)
	while sess.state() == "fighting" and n < ticks:
		if n % PLAYER_EVERY == 0:
			pilot.think(STEP * PLAYER_EVERY)
		Drones.ai_launch(a, Session.PLAYER, Session.ENEMY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n % SIM_EVERY == 0:
			sim.step(SIM_EVERY * STEP)
	var shots := 0
	var lost := 0
	var downs := 0
	for ev in a.events:
		if ev["type"] == "drone_shot" and ev["ship"] == Session.PLAYER:
			shots += 1
		elif ev["type"] == "drone_down" and ev["ship"] == Session.PLAYER:
			downs += 1
	row.merge({"state": sess.state(), "t": n * STEP, "foe_hull": Structure.structure_fraction(a.ships[Session.ENEMY]), "hull": Structure.structure_fraction(a.ships[Session.PLAYER]),
		"drone_shots": shots, "drone_lost": downs, "launches": a.events.filter(func(ev): return ev["type"] == "drone_launch" and ev["ship"] == Session.PLAYER).size()}, true)
	sim.free()
	return row


static func summary(rows: Array) -> String:
	var won := 0
	var lost := 0
	var t := 0.0
	var hull := 0.0
	var foe := 0.0
	var shots := 0
	var launches := 0
	for r in rows:
		won += 1 if r["state"] in ["won", "captured", "spared", "escaped"] else 0
		lost += 1 if r["state"] == "lost" else 0
		t += float(r["t"])
		hull += float(r.get("hull", 1.0))
		foe += float(r.get("foe_hull", 1.0))
		shots += int(r.get("drone_shots", 0))
		launches += int(r.get("launches", 0))
	var n := float(maxi(rows.size(), 1))
	return "won %d  lost %d  other %d of %d   mean time %.0f s   own hull left %.0f%%   foe hull left %.0f%%   drone shots %.1f and launches %.1f a fight" % [won, lost, rows.size() - won - lost, rows.size(), t / n, 100.0 * hull / n, 100.0 * foe / n, shots / n, launches / n]
