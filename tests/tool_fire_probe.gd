extends SceneTree
## Not a test (the runner only loads test_*.gd). Why does a ship fire less than its listed dps (fights-end, 2026-11; docs/GUNS.md 15)? Per gun, every
## substep of tool_standoff-style fights: cooling (it fired), out (disabled, offline, unpowered) or why a ready gun does not fire (can_fire, out of
## range, out of gimbal and not lined on the hull, the shield hold, a turret out of arc or range), summed over the fights.
##   godot --headless --path . --script res://tests/tool_fire_probe.gd -- [stage=4] [build=7] [n=3] [secs=120] [factions=rustfangs,concord,wardens] [role=gunboat]
##   ... -- race=<flagship race> [build=4] [side=1]: the flagship against the build, side 1 probes the flagship's guns.

const Standoff = preload("res://tests/tool_standoff.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Threat = preload("res://scripts/space/threat.gd")
const Shields = preload("res://scripts/combat/shields.gd")

var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var st := int(args.get("stage", 4))
	var n := int(args.get("n", 3))
	var secs := float(args.get("secs", 120))
	var total := {}
	if args.has("race"):
		for sd in int(args.get("n", 2)):
			var r := fight({"spec": "res://data/packs/flagships_1/ships/flagship_%s.json" % args["race"], "seed": sd * 7919}, int(args.get("build", 4)), secs)
			for k in r:
				total[k] = float(total.get(k, 0.0)) + float(r[k])
	for faction in ([] if args.has("race") else str(args.get("factions", "rustfangs,concord,wardens")).split(",")):
		for e in Standoff.cell_enemies(st, faction, str(args.get("role", "gunboat")), n, []):
			var r := fight(e, int(args.get("build", 7)), secs)
			for k in r:
				total[k] = float(total.get(k, 0.0)) + float(r[k])
	var keys := total.keys()
	keys.sort()
	for k in keys:
		print("%-40s %.0f" % [k, total[k]])
	quit(0)


func fight(e: Dictionary, build: int, secs: float) -> Dictionary:
	var player = Standoff.build_player(build)
	var enemy = Session.load_ship(e["spec"])
	var sim := ShipSim.new()
	sim.ships = [player, enemy]
	Jobs.spawn_crew(player)
	var sess := Session.new()
	sess.start(player, enemy, 1 + int(e["seed"]) % 100000)
	var pilot := PilotAI.new(sess.arena, 0, 1, {"aim_skill": float(Threat.config()["player_aim"])})
	pilot.foe_morale = sess.morale
	var a = sess.arena
	var out := {}
	var side := int(args.get("side", 0))
	var co = a.ships[side]
	var pil = pilot if side == 0 else sess.ai
	for i in int(secs * 60.0):
		if sess.state() != "fighting":
			break
		if i % 3 == 0:
			pilot.think(3.0 / 60.0)
		if sess.morale.state == "offering":
			sess.accept_surrender()
		sess.ai.think(1.0 / 60.0)
		for uid in co.mounts:
			var m: Dictionary = co.mounts[uid]
			var w: Dictionary = a.weapons.def(m["id"])
			var kind := "turret" if w["turret"] else "fixed"
			var why := _why(a, pil, uid, m, w, side)
			var key := "%s %s %s" % [kind, m["id"], why]
			out[key] = float(out.get(key, 0.0)) + 1.0
		var before: int = a.events.size()
		a.step(1.0 / 60.0)
		sess.morale.tick(1.0 / 60.0)
		for k in range(before, a.events.size()):
			var ev: Dictionary = a.events[k]
			if ev["type"] == "shot" and int(ev["ship"]) == side:
				var key := "shots %s" % ev["weapon"]
				out[key] = float(out.get(key, 0.0)) + 1.0
		if i % 12 == 0:
			sim.step(12.0 / 60.0)
	out["seconds"] = a.time()
	sim.free()
	return out


func _why(a, pilot, uid: int, m: Dictionary, w: Dictionary, side := 0) -> String:
	var co = a.ships[side]
	var status: String = a.weapons.status_of(a, side, uid)
	if status != "ok":
		return "x " + status
	if not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
		return "x unpowered"
	if a.cooldown_left(side, uid) > 0.0:
		return "cooling"
	var aim: Vector2 = pilot.aim_for(m, false)
	var cf: String = a.weapons.can_fire(a, side, uid, aim)
	if cf != "" and cf != "out of arc":
		return "ready: " + cf
	var origin: Vector2 = a.weapons.muzzle_of(a, side, m)
	if w["turret"]:
		if cf == "out of arc":
			return "ready: turret out of arc"
		if not a.weapons._in_range(a, side, m, w, 1 - side):
			return "ready: turret out of range"
		return "ready: turret tracking or firing"
	if origin.distance_to(aim) > float(w["range"]):
		return "ready: out of range"
	var tag := ""
	if not a.weapons.in_arc(a, side, m, aim):
		if not pilot.on_hull(origin, Vector2(m["aim"]).rotated(co.flight.angle), float(w["range"])):
			return "ready: out of gimbal, not lined on the hull"
		tag = " (out of gimbal, lined on the hull)"
	if co.sectors > 1 and co.layers > 0 and Shields.drop_seconds(w) > 0.0:
		var danger: Array = pilot._exposed_sectors()
		var s := Shields.outgoing_sector(co, m["pos"], (aim - origin).rotated(-co.flight.angle))
		if s in danger:
			return "ready: shield hold" + tag
	return "ready: bears" + tag
