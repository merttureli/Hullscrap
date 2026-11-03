extends SceneTree
## Not a test. Mechanics audit: a weapon bench. One gun (a virtual mount, any weapons.json id) fires as fast as it can at a stationary generated ship for
## `secs` seconds in the real arena (no pilot, no crew, no morale; the target's shields recharge as in a fight). Prints, per gun and target kind, the structure hp the
## target lost (hp of its blocks), the shield layers the shots used, and the hp per second per 100 materials of the recipe.
##   godot --headless --path . --script res://tests/tool_audit_mech_bench.gd -- [secs=90 targets=3 guns=laser_mk1,laser_mk2 faction=lumen stage=4 budget=12000]
const Arena = preload("res://scripts/combat/arena.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const FixtureShip = preload("res://tests/fixture_ship.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")

const GUNS := ["laser_mk1", "laser_mk2", "pulse_mk1", "pulse_mk2", "laser_turret_mk1", "rattle_burst_scrap", "shrapnel_cannon_scrap", "bolt_thrower_scrap", "artemis_mk1", "ion_blast_mk1", "heat_lance_neon"]
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var secs := float(args.get("secs", 90))
	var n := int(args.get("targets", 3))
	var fac := str(args.get("faction", "lumen"))
	var stage := int(args.get("stage", 4))
	var budget := int(args.get("budget", 12000))
	var guns: Array = str(args["guns"]).split(",") if args.has("guns") else GUNS
	var kinds := {"plain": [], "shield2": []}  # the same ships: "plain" has its shield layers stripped before the bench
	for seed_value in range(1, 600):
		var spec := "gen:%s:medium:%d:%d:s%d" % [fac, seed_value, budget, stage]
		var s = Shipgen.from_spec(spec)
		if s == null:
			continue
		var layers := Shields.layers_of_ship(s, s.power_state.get("powered", {}))
		if layers >= 2 and kinds["shield2"].size() < n:
			kinds["shield2"].append(spec)
			kinds["plain"].append(spec)
	print("targets ", kinds)
	var w := Weapons.new()
	print("gun | kind | plain hp dealt/s | shield2 hp dealt/s | shield2 layers used/s")
	for g in guns:
		var line := "%-22s %-8s" % [g, w.def(g)["kind"]]
		for k in ["plain", "shield2"]:
			var hp := 0.0
			var used := 0.0
			for spec in kinds[k]:
				var r := _bench(g, spec, secs, k == "plain")
				hp += r[0]
				used += r[1]
			var m := float(maxi(kinds[k].size(), 1))
			line += " | %6.3f" % (hp / m / secs)
			if k == "shield2":
				line += " | %5.3f" % (used / m / secs)
		print(line)
	quit()


## [structure hp lost, shield hits] of `spec` after `secs` s under one `gun`.
func _bench(gun: String, spec: String, secs: float, strip := false) -> Array:
	var a := Arena.new(11)
	var shooter := FixtureShip.room_ship()
	shooter.inventory.add("missile", 999)  # ammo for the Artemis, the Bolt Thrower (scrap) and the rest
	shooter.inventory.add("scrap", 999)
	var si := a.add_ship(shooter, Vector2.ZERO, 0.0)
	var target = Session.load_ship(spec)
	var ti := a.add_ship(target, Vector2(0.0, 0.0), PI)
	a.ships[ti].flight.pos = Vector2(496.0 + 320.0 + maxf(a.ships[ti].half.x, a.ships[ti].half.y) * Arena.CELL, 0.0)  # 320 px of space between the muzzle and its hull
	if strip:
		for sct in a.ships[ti].sectors:
			a.ships[ti].sector_layers[sct] = 0.0
			a.ships[ti].sector_timers[sct] = []
	var uid := a.add_mount(si, gun, Vector2(31, 15.5), true, Vector2.RIGHT)
	var tot: Vector2 = Structure.totals(target)
	var steps := int(secs * 60.0)
	var hits := 0
	var fired := 0
	for i in steps:
		if a.cooldown_left(si, uid) <= 0.0:
			fired += int(a.fire(si, uid, a.ships[ti].flight.pos))
		a.step(1.0 / 60.0)
	for e in a.events:
		if e["type"] == "shield" and e["ship"] == ti:
			hits += 1
	if args.has("v"):
		var types := {}
		for e in a.events:
			types[e["type"]] = int(types.get(e["type"], 0)) + 1
		print("  layers=", a.ships[ti].layers, " sectors=", a.ships[ti].sectors, " types=", types)
	if args.has("v"):
		print("  ", gun, " fired ", fired, " at ", spec, " strip=", strip, " events=", a.events.size())
	return [tot.y - Structure.totals(target).x, float(hits)]
