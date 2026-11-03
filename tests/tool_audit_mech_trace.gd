extends SceneTree
## Not a test. Mechanics audit: one starter against one enemy spec in the real arena (as tests/tool_standoff.gd flies it), printing every `every`
## seconds: the starter's guns (status, outside hp), its structure, the enemy's structure and morale, the crew's jobs.
##   godot --headless --path . --script res://tests/tool_audit_mech_trace.gd -- starter=rustbucket spec=gen:concord:small:8051:1823:s1 [cap=120 every=10 paim=0.75]
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Threat = preload("res://scripts/space/threat.gd")

const STEP := 1.0 / 60.0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var player = Session.load_ship("res://data/ships/starter_%s.json" % args.get("starter", "rustbucket"))
	var enemy = Session.load_ship(str(args["spec"]))
	var cap := float(args.get("cap", 120))
	var every := float(args.get("every", 10))
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(args.get("seed", 7)))
	var pilot := PilotAI.new(sess.arena, Session.PLAYER, Session.ENEMY, {"aim_skill": float(args.get("paim", Threat.config()["player_aim"]))})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var n := 0
	var next := 0.0
	var early := int(args.get("early", 0))
	while sess.state() == "fighting" and n * STEP < cap:
		if n % 3 == 0:
			pilot.think(STEP * 3)
		if sess.morale.state == "offering":
			print("  offer -> accepted")
			sess.accept_surrender()
		sess.ai.think(STEP)
		a.step(STEP)
		sess.morale.tick(STEP)
		n += 1
		if n <= early:
			print("  tick ", n, " me=", Structure.structure_fraction(a.ships[Session.PLAYER]), " events=", a.events)
		if n % 12 == 0:
			sim.step(12 * STEP)
		if n * STEP >= next:
			next += every
			var co = a.ships[Session.PLAYER]
			var g := []
			for uid in co.mounts:
				var inst: Dictionary = player.components.instances[uid]
				g.append("%s:%s/out%d" % [str(inst["id"]).substr(0, 8), a.weapons.status_of(a, 0, uid), int(inst["out_hp"])])
			var jobs := []
			for m in player.crew:
				jobs.append("%s:%s" % [m.name, str(m.job.get("type", m.job.get("kind", "idle"))) + ("#%d" % int(m.hp))])
			var ej := []
			for m in enemy.crew:
				ej.append("%s:%s#%d" % [m.name, str(m.job.get("type", "idle")), int(m.hp)])
			print("  foe crew ", ej)
			var low := 1.0
			for pr in player.atmosphere.pressure:
				low = minf(low, pr)
			print("  me: fires=%d lowest room air=%.2f hurt-crew pos: %s" % [player.fires.size(), low, str(player.crew.filter(func(m): return m.hp < 90).map(func(m): return "%s@%s air %.2f" % [m.name, str(m.pos.round()), player.atmosphere.pressure_at(Vector2i(m.pos))]))])
			print("t=%3.0f me=%.3f foe=%.3f morale=%s guns=%s crew=%s" % [n * STEP, Structure.structure_fraction(co), Structure.structure_fraction(a.ships[Session.ENEMY]), sess.morale.state, g, jobs])
	print("end ", sess.state(), " t=", n * STEP)
	quit()
