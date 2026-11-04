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

## Beta 3 enemy identity: every race tech part (data/packs/tech_*, faction_*) enemies now carry is on the bench too (races=0 to leave them out), and the table
## flags a race gun whose plain hp/s is over 30% above the mean of the base guns of its tier.
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
	var guns: Array = str(args["guns"]).split(",") if args.has("guns") else GUNS.duplicate()
	var races: Array = []
	if not args.has("guns") and str(args.get("races", "1")) != "0":
		races = race_guns()
		guns.append_array(races)
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
	var plain := {}
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
			if k == "plain":
				plain[g] = hp / m / secs
			if k == "shield2":
				line += " | %5.3f" % (used / m / secs)
		print(line)
	var by_tier := {}
	for g in GUNS:
		if plain.has(g):
			var t := int(Shipgen._comps().def(g).get("tier", 1))
			by_tier[t] = by_tier.get(t, []) + [plain[g]]
	for g in races:
		var t := int(Shipgen._comps().def(g).get("tier", 1))
		var base: Array = by_tier.get(t, [])
		if base.is_empty():
			continue
		var mean := 0.0
		for x in base:
			mean += x
		mean /= base.size()
		var ratio: float = plain[g] / maxf(mean, 0.0001)
		print("%-28s tier %d plain %.3f hp/s, x%.2f of the base guns of its tier (%.3f)%s" % [g, t, plain[g], ratio, mean, "   <-- over 30%" if ratio > 1.3 else ""])
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


## The weapon ids of the race and faction packs (data/packs/tech_*/weapons.json, faction_*/weapons.json).
static func race_guns() -> Array:
	var out: Array = []
	for dir in DirAccess.get_directories_at("res://data/packs"):
		if not (dir.begins_with("tech_") or dir.begins_with("faction_")):
			continue
		var path := "res://data/packs/%s/weapons.json" % dir
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var list = data.get("weapons", data) if data is Dictionary else data
		if list is Dictionary:
			for id in list:
				if not str(id).begins_with("_"):
					out.append(str(id))
		elif list is Array:
			for w in list:
				out.append(str(w["id"]))
	return out
