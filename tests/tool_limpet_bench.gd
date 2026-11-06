extends SceneTree
## Not a test (the runner only loads test_*.gd). The limpet and boarder bench of docs/DRONES.md section 9: a starter with a bay and a limpet or pod kit (it replaces the starter's weakest
## gun, as tool_drone_bench.gd) fights the stage 2 and 3 enemies through the real arena, both pilots on the AI (the bay throws by the enemy's rule, Drones.ai_launch). Reports the
## launches, how many stuck, were shot down or lost, the robots delivered, what the enemy lost (systems out, crew down) and the win rate. With pd=1 the enemy also carries `pd` point-defence turrets.
##   godot --headless --path . --script res://tests/tool_limpet_bench.gd -- kits=fire_limpet_mk1,boarder_pod_mk1 seeds=6 stages=2,3 only=rustbucket pd=0 cap=120
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Threat = preload("res://scripts/space/threat.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Bench = preload("res://tests/tool_drone_bench.gd")
const Standoff = preload("res://tests/tool_standoff.gd")

const STEP := 1.0 / 60.0
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var seeds := int(args.get("seeds", 6))
	var cap := float(args.get("cap", 120.0))
	var pd := int(args.get("pd", 0))
	var name := str(args.get("only", "rustbucket"))
	for kit in str(args.get("kits", "fire_limpet_mk1,poison_limpet_mk1,heat_limpet_mk1,boarder_pod_mk1")).split(","):
		for st in str(args.get("stages", "2,3")).split(","):
			var list: Array = Standoff.starter_enemies(name, int(st), seeds)
			var rows := []
			for e in list:
				rows.append(fight(name, kit, e, cap, pd))
			print("%-18s stage %s pd %d  %s" % [kit, st, pd, summary(rows)])
	quit()


func fight(name: String, kit: String, e: Dictionary, cap: float, pd: int) -> Dictionary:
	var player = Bench.variant(name, true, kit)
	var enemy = load("res://scripts/space/shipgen.gd").from_spec(e["spec"]) if false else Session.load_ship(e["spec"])
	var row := {"state": "error"}
	if player == null or enemy == null:
		return row
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	var a = sess.arena
	var crew0: int = enemy.crew.size()
	for i in pd:  # point-defence turrets round the enemy's hull
		a.add_mount(1, str(args.get("pdw", "kett_drone_picket")), Vector2(a.ships[1].pivot) + Vector2.from_angle(float(i) * 2.1) * 9.0, true)
	var pilot := PilotAI.new(a, Session.PLAYER, Session.ENEMY, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var n := 0
	var ticks := int(cap * 60.0)
	while sess.state() == "fighting" and n < ticks:
		if n % 3 == 0:
			pilot.think(STEP * 3)
		Drones.ai_launch(a, Session.PLAYER, Session.ENEMY)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n % 12 == 0:
			sim.step(12 * STEP)
	var c := func(t: String) -> int: return a.events.filter(func(ev): return ev["type"] == t and ev["ship"] == Session.PLAYER).size()
	var out := 0
	for uid in enemy.components.instances:
		if str(enemy.components.instances[uid]["status"]) != "ok":
			out += 1
	var down := 0
	for m in enemy.crew:
		down += 1 if m.is_down() else 0
	var mine_robots := 0
	for ev in a.events:
		if ev["type"] == "pod_breach" and ev["ship"] == Session.ENEMY:
			mine_robots += int(ev["robots"])
	var fires: int = enemy.events.filter(func(ev): return str(ev["text"]).begins_with("Fire in")).size()
	row.merge({"state": sess.state(), "t": n * STEP, "launch": c.call("drone_launch"), "stuck": a.events.filter(func(ev): return ev["type"] == "limpet_stick" and ev["ship"] == Session.ENEMY).size(),
		"shot": c.call("drone_down"), "lost": c.call("limpet_lost"), "robots": mine_robots, "out": out, "down": down, "crew": crew0, "fires": fires,
		"foe_hull": Structure.structure_fraction(a.ships[Session.ENEMY]), "hull": Structure.structure_fraction(a.ships[Session.PLAYER]),
		"robots_left": enemy.intruders.size(), "robots_dead": enemy.intruder_dead.size()}, true)
	sim.free()
	return row


static func summary(rows: Array) -> String:
	var won := 0
	var lost := 0
	var s := {"t": 0.0, "launch": 0, "stuck": 0, "shot": 0, "lost": 0, "robots": 0, "out": 0, "down": 0, "fires": 0, "foe_hull": 0.0, "hull": 0.0, "robots_dead": 0}
	for r in rows:
		won += 1 if r["state"] in ["won", "captured", "spared", "escaped"] else 0
		lost += 1 if r["state"] == "lost" else 0
		for k in s:
			s[k] += r.get(k, 0)
	var n := float(maxi(rows.size(), 1))
	var l := maxf(float(s["launch"]), 1.0)
	return "won %d lost %d of %d  %.0f s  launches %.1f: stuck %.0f%% shot down %.0f%% lost %.0f%%  robots %.1f (dead %.1f)  enemy systems out %.1f crew down %.1f fires %.1f  foe hull %.0f%% own hull %.0f%%" % [won, lost, rows.size(), s["t"] / n,
		float(s["launch"]) / n, 100.0 * float(s["stuck"]) / l, 100.0 * float(s["shot"]) / l, 100.0 * float(s["lost"]) / l, float(s["robots"]) / n, float(s["robots_dead"]) / n,
		float(s["out"]) / n, float(s["down"]) / n, float(s["fires"]) / n, 100.0 * float(s["foe_hull"]) / n, 100.0 * float(s["hull"]) / n]
