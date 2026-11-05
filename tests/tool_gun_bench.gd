extends SceneTree
## Not a test (the runner only loads test_*.gd). The gun bench of docs/GUNS.md 9 (G2): are the new guns worth the same as their family's base, is any
## gun a dominant pick, and does each counter work?
##   godot --headless --path . --script res://tests/tool_gun_bench.gd -- mode=<values|solo|pairs|counters> [key=value ...]
## values: the table of the value model (tests/gun_value.gd) against each gun's band, no fights.
## solo: every gun of a tier (the new ones and the bases of their families) fires 3 copies at generated enemies of that tier's stage (plain and shielded,
##   `seeds` of each; a stationary target, the gun's ship faces it from 0.65 x range, at most 650 px off its hull) for `secs`: the damage dealt, the structure
##   lost and the shield layers stripped. Printed as the ratio to the base of its family: the fight value, next to the model's.
## pairs: for each tier the guns are rated by solo; then the best, and every gun against the median gun: identical generated hulls, each armed with 3 copies of its
##   gun, stationary, face to face for `secs`; the winner is the hull with more structure left. Win rate over the `seeds` hulls (plain and shielded).
## counters: point defence against missiles and slow shells (a hull with 3 pd_mk2 against the same hull without), shields against beams and lasers (the solo damage on
##   shielded hulls over plain ones, by family), and the armour table (the share of a gun's damage type the plating lets through).
## Keys: tiers (default 1,2,3), seeds (default 6 of each kind), secs (60), jobs (processes, default 4), out (write the rows), sum (print the tables of out files).
## Internal: shard (k/n), rows.

const Ship = preload("res://scripts/ship/ship.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Weapons = preload("res://scripts/combat/weapons.gd")
const Components = preload("res://scripts/ship/components.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Standoff = preload("res://tests/tool_standoff.gd")
const Session = preload("res://scripts/combat/combat_session.gd")
const GV = preload("res://tests/gun_value.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const STEP := 1.0 / 60.0
const STAGE_OF_TIER := {1: 1, 2: 2, 3: 4}  ## the standoff stage whose enemies are of that tier
const COPIES := 3
const BOW_CELL_Y := 1.5

var args := {}
var rows: Array = []
var weapons := Weapons.new()
var comps := Components.new()
var secs := 60.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	secs = float(args.get("secs", secs))
	comps.load_defs("res://data/components.json")
	_run.call_deferred()


func _tiers() -> Array:
	return Array(str(args.get("tiers", "1,2,3")).split(",")).map(func(x): return int(x))


func _run() -> void:
	var mode := str(args.get("mode", "values"))
	if mode == "values":
		print(values_table())
		quit(0)
		return
	if args.has("sum"):
		for path in str(args["sum"]).split(","):
			rows.append_array(JSON.parse_string(FileAccess.get_file_as_string(path)))
		print(report(mode))
		quit(0)
		return
	var jobs := int(args.get("jobs", 4))
	if jobs > 1 and not args.has("shard"):
		_fan_out(jobs)
	else:
		var shard := Array(str(args.get("shard", "0/1")).split("/")).map(func(x): return int(x))
		var tasks := tasks_for(mode)
		for k in tasks.size():
			if k % shard[1] == shard[0]:
				rows.append(run_task(tasks[k]))
	if args.has("rows"):
		_write(str(args["rows"]), JSON.stringify(rows))
	if args.has("shard"):
		quit(0)
		return
	if args.has("out"):
		_write(str(args["out"]), JSON.stringify(rows))
	print(report(mode))
	quit(0)


func _fan_out(jobs: int) -> void:
	var pids := []
	var files := []
	var pass_on := []
	for key in ["mode", "tiers", "seeds", "secs", "guns"]:
		if args.has(key):
			pass_on.append("%s=%s" % [key, args[key]])
	for k in jobs:
		var path := OS.get_cache_dir().path_join("hullscrap_gunbench_%d_%d.json" % [OS.get_process_id(), k])
		files.append(path)
		pids.append(OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/tool_gun_bench.gd", "--",
			"shard=%d/%d" % [k, jobs], "rows=" + path] + pass_on))
	while pids.any(func(p): return OS.is_process_running(p)):
		OS.delay_msec(500)
	for path in files:
		var got = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if got is Array:
			rows.append_array(got)
		else:
			printerr("gun bench: a shard wrote nothing: " + path)


static func _write(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(text)
	fa.close()


# --- the guns ----------------------------------------------------------------------------------------

## The guns the bench rates at `tier`: the new ones (those with a `family`) and the bases of their families that are guns of the data. Not point defence.
func guns_of(tier: int) -> Array:
	var out: Array = []
	for id in weapons.defs:
		var e: Dictionary = weapons.defs[id]
		if str(e.get("family", "")) in ["", "pd"] or str(id).begins_with("test_") or not comps.has(id) or int(comps.def(id)["tier"]) != tier:
			continue
		out.append(str(id))
	for fam in GV.BASES:
		var b = GV.BASES[fam].get(tier)
		if b is String and not out.has(b):
			out.append(b)
	out.sort()
	if args.has("guns"):  # guns=a,b: only these (and the bases of their families, which they are read against)
		var keep: Array = str(args["guns"]).split(",")
		out = out.filter(func(id): return id in keep or GV.BASES.get(family_of(id), {}).get(tier) == id and keep.any(func(k): return weapons.defs.has(k) and family_of(k) == family_of(id)))
	return out


func family_of(id: String) -> String:
	var f := str(weapons.defs[id].get("family", ""))
	if f != "":
		return f
	for fam in GV.BASES:
		if GV.BASES[fam].values().has(id):
			return fam
	return "?"


# --- the value table ---------------------------------------------------------------------------------

func values_table() -> String:
	var L: Array[String] = ["| id | family | version | tier | aim | arc/gimbal | damage | x | every s | range | power | hp | model value | band |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for tier in [1, 2, 3]:
		for id in guns_of(tier):
			var w := weapons.def(id)
			var d := comps.def(id)
			var r := GV.ratio(weapons, id, tier) if str(weapons.defs[id].get("family", "")) != "" else 1.0
			var band := float(GV.EXCEPT.get(id, GV.BAND))
			L.append("| %s | %s | %s | %d | %s | %s | %s | %d | %s | %d | %d | %d | %.2f | %s |" % [id, family_of(id), str(weapons.defs[id].get("version", "base")).get_slice(":", 0), tier, w["aim"],
				"%d°" % w["arc"] if w["turret"] else "±%d°" % w["gimbal"], String.num(float(weapons.defs[id]["damage"]), 3), int(w["shots"]), String.num(float(w["cooldown"]), 3), w["range"],
				d["power"], d["hp"], r, "ok" if absf(r - 1.0) <= band + 1e-9 or r < 1.0 and str(weapons.defs[id].get("version", "")).begins_with("Light") and absf(r - 1.0) <= 0.2 else "OUT"])
	return "\n".join(L)


# --- the fights --------------------------------------------------------------------------------------

func tasks_for(mode: String) -> Array:
	var out: Array = []
	var n := int(args.get("seeds", 6))
	for tier in _tiers():
		var specs: Array = []
		for kind in ["plain", "shield"]:
			for e in Standoff.enemies(STAGE_OF_TIER[tier], kind, n):
				specs.append(e)
		match mode:
			"solo", "counters":
				for id in guns_of(tier):
					for e in specs:
						out.append({"mode": "solo", "tier": tier, "gun": id, "spec": e["spec"], "kind": e["kind"], "seed": e["seed"]})
				if mode == "counters":
					for id in guns_of(tier):
						for e in specs.filter(func(x): return x["kind"] == "plain"):
							out.append({"mode": "solo", "tier": tier, "gun": id, "spec": e["spec"], "kind": "pd", "seed": e["seed"], "pd": "pd_mk%d" % tier})
			"pairs":
				var mid: String = args.get("median_%d" % tier, "")
				if mid == "":
					mid = _median_gun(tier)
				for id in guns_of(tier):
					if id != mid:
						for e in specs:
							out.append({"mode": "pair", "tier": tier, "a": id, "b": mid, "spec": e["spec"], "kind": e["kind"], "seed": e["seed"]})
	return out


## The median gun of `tier` by the model value (the pairs mode runs before any solo result exists when sharded).
func _median_gun(tier: int) -> String:
	var v: Array = []
	for id in guns_of(tier):
		v.append([GV.value(weapons.def(id)), id])
	v.sort()
	return str(v[v.size() / 2][1])


func run_task(t: Dictionary) -> Dictionary:
	if t["mode"] == "solo":
		return solo(t)
	return pair(t)


## A fresh arena with the attacker (a bare wall ship, never wrecked) at the origin facing up, and `spec` stationary above it.
func _arena(spec: String, seed_value: int, range_px: float) -> Dictionary:
	var a := Arena.new(seed_value)
	a.weapons = weapons
	var me := Wall.wall_ship(1)
	me.inventory.add("missile", 999)
	me.inventory.add("scrap", 999)
	var foe: Ship = Session.load_ship(spec)
	a.add_ship(me, Vector2.ZERO)
	var gap := clampf(0.65 * range_px, 250.0, 650.0)
	a.add_ship(foe, Vector2.ZERO)
	var co = a.ships[1]
	var bow: float = (a.ships[0].pivot.y - BOW_CELL_Y) * a.CELL
	co.flight.pos = Vector2(0.0, -(bow + gap + co.half.y * a.CELL))
	co.flight.angle = 0.0
	return {"a": a, "gap": gap}


func _mounts(a, idx: int, gun: String, y: float, dir: Vector2) -> Array:
	var out := []
	var c = a.ships[idx].pivot
	for i in COPIES:
		out.append(a.add_mount(idx, gun, Vector2(c.x + (i - 1) * 5.0, y), true, dir))
	return out


## The pilot's sweep: the ship at `idx` turns across the other hull (a fixed gun only reaches where the ship points), a slow side to side over 8 s.
func _sweep(a, idx: int, other: int, tick: int) -> void:
	var me = a.ships[idx]
	var to: Vector2 = a.ships[other].flight.pos - me.flight.pos
	var reach := atan2(0.6 * a.ships[other].half.x * a.CELL, to.length())
	me.flight.angle = Vector2.UP.angle_to(to) + reach * sin(TAU * float(tick) * STEP / 8.0 + float(idx) * PI)


func _fire_all(a, idx: int, uids: Array, other: int) -> void:
	var co = a.ships[idx]
	var aim: Vector2 = co.flight.pos + Vector2.UP.rotated(co.flight.angle) * co.flight.pos.distance_to(a.ships[other].flight.pos)  # where the sweeping ship points
	a.aim_points[idx] = aim
	for uid in uids:
		var m: Dictionary = co.mounts[uid]
		if a.weapons.def(m["id"])["turret"]:
			continue  # tracks and fires by itself
		a.weapons.point_barrel(a, idx, uid, aim)
		if a.cooldown_left(idx, uid) > 0.0 or a.weapons.holds_charge(a, idx, m, other):
			continue
		a.fire(idx, uid, aim)


func solo(t: Dictionary) -> Dictionary:
	var w := weapons.def(t["gun"])
	var r := _arena(t["spec"], 1 + int(t["seed"]) % 100000, float(w["range"]))
	var a: Arena = r["a"]
	var uids := _mounts(a, 0, t["gun"], BOW_CELL_Y, Vector2.UP)
	if t.has("pd"):
		weapons.defs.get(t["pd"])
		var c1 = a.ships[1].pivot
		for i in 3:
			a.add_mount(1, t["pd"], Vector2(c1.x + (i - 1) * 4.0, c1.y + 4.0), true, Vector2.DOWN)
		a.ships[1].mounts = a.ships[1].mounts.duplicate()
	var foe = a.ships[1]
	var s0 := Structure.structure_fraction(foe)
	var layers0: int = foe.layers
	var min_layers := layers0
	var down := 0.0
	var samples := 0
	a.aim_points[0] = foe.flight.pos
	var n := int(secs / STEP)
	var dealt := 0.0
	var cursor := 0
	for i in n:
		if i % 3 == 0:
			_sweep(a, 0, 1, i)
			_fire_all(a, 0, uids, 1)
		a.ships[0].wrecked = false
		a.step(STEP)
		if i % 30 == 0:
			min_layers = mini(min_layers, foe.layers)
			down += 1.0 - float(foe.layers) / float(maxi(layers0, 1))
			samples += 1
			for k in range(cursor, a.events.size()):
				var e: Dictionary = a.events[k]
				if str(e["type"]) == "hit" and int(e["ship"]) == 1:
					dealt += float(e.get("dealt", 0.0))
			cursor = a.events.size()
			a.events = []
			cursor = 0
		if foe.wrecked:
			break
	for e in a.events:
		if str(e["type"]) == "hit" and int(e["ship"]) == 1:
			dealt += float(e.get("dealt", 0.0))
	return {"mode": "solo", "tier": t["tier"], "gun": t["gun"], "kind": t["kind"], "seed": t["seed"], "dealt": dealt, "lost": s0 - Structure.structure_fraction(foe),
		"stripped": layers0 - min_layers, "layers": layers0, "down": down / float(maxi(samples, 1)), "t": float(i_end(a)) * STEP}


func i_end(a) -> int:
	return a.tick


func pair(t: Dictionary) -> Dictionary:
	var wa := weapons.def(t["a"])
	var wb := weapons.def(t["b"])
	var seed_v := 1 + int(t["seed"]) % 100000
	var a := Arena.new(seed_v)
	a.weapons = weapons
	var s1: Ship = Session.load_ship(t["spec"])
	var s2: Ship = Session.load_ship(t["spec"])
	a.add_ship(s1, Vector2.ZERO)
	a.add_ship(s2, Vector2.ZERO)
	for i in 2:
		a.ships[i].mounts = {}  # the hulls' own guns are out: only the bench guns fire
		a.ships[i].ship.inventory.add("missile", 999)
		a.ships[i].ship.inventory.add("scrap", 999)
	var gap := clampf(0.65 * minf(float(wa["range"]), float(wb["range"])), 250.0, 650.0)
	var bow: float = a.ships[0].half.y * a.CELL
	a.ships[0].flight.pos = Vector2.ZERO
	a.ships[1].flight.pos = Vector2(0.0, -(bow + gap + a.ships[1].half.y * a.CELL))
	a.ships[1].flight.angle = PI
	var ua := _mounts(a, 0, t["a"], a.ships[0].pivot.y - a.ships[0].half.y + 1.5, Vector2.UP)
	var ub := _mounts(a, 1, t["b"], a.ships[1].pivot.y - a.ships[1].half.y + 1.5, Vector2.UP)
	a.aim_points[0] = a.ships[1].flight.pos
	a.aim_points[1] = a.ships[0].flight.pos
	var n := int(secs / STEP)
	for i in n:
		if i % 3 == 0:
			_sweep(a, 0, 1, i)
			_sweep(a, 1, 0, i)
			_fire_all(a, 0, ua, 1)
			_fire_all(a, 1, ub, 0)
		a.step(STEP)
		if a.ships[0].wrecked or a.ships[1].wrecked:
			break
	var fa := Structure.structure_fraction(a.ships[0])
	var fb := Structure.structure_fraction(a.ships[1])
	return {"mode": "pair", "tier": t["tier"], "a": t["a"], "b": t["b"], "kind": t["kind"], "seed": t["seed"], "fa": fa, "fb": fb, "win": 1.0 if fa > fb + 1e-6 else (0.5 if absf(fa - fb) <= 1e-6 else 0.0)}


# --- the reports -------------------------------------------------------------------------------------

static func _mean(v: Array) -> float:
	var t := 0.0
	for x in v:
		t += float(x)
	return t / maxf(float(v.size()), 1.0)


func report(mode: String) -> String:
	var L: Array[String] = []
	if mode == "pairs":
		return pairs_report()
	L.append("## Solo (fight value against the family base, %d s, 3 copies; model value beside)" % int(secs))
	L.append("| tier | gun | family | dealt (hp) | structure lost | layers stripped | fight value | model value | within +-15% |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	for tier in _tiers():
		var by := {}
		for r in rows:
			if r["mode"] == "solo" and int(r["tier"]) == tier and r["kind"] in ["plain", "shield"]:
				if not by.has(r["gun"]):
					by[r["gun"]] = []
				by[r["gun"]].append(r)
		for id in guns_of(tier):
			if not by.has(id):
				continue
			var ion: bool = family_of(id) == "ion"  # ion does no structural damage: its value is the shield it keeps down (shielded hulls only)
			var key := "down" if ion else "dealt"
			var dealt := _mean(by[id].map(func(r): return r[key]))
			var lost := _mean(by[id].map(func(r): return r["lost"]))
			var strip := _mean(by[id].map(func(r): return r["stripped"]))
			var base := _base_id(id, tier)
			var bdealt := 0.0
			if by.has(base):
				bdealt = _mean(by[base].map(func(r): return r[key]))
			var fv := dealt / bdealt if bdealt > 0.0 else 0.0
			var mv := GV.ratio(weapons, id, tier) if str(weapons.defs[id].get("family", "")) != "" else 1.0
			L.append("| %d | %s | %s | %.1f | %.3f | %.2f | %.2f | %.2f | %s |" % [tier, id, family_of(id), dealt, lost, strip, fv, mv, "yes" if absf(fv - 1.0) <= 0.15 else "no"])
	if mode == "counters":
		L.append("")
		L.append(counters_report())
	return "\n".join(L)


func _base_id(id: String, tier: int) -> String:
	var b = GV.BASES.get(family_of(id), {}).get(tier)
	return b if b is String else id


func pairs_report() -> String:
	var L: Array[String] = ["## Pairs (win rate of each gun against the tier's median gun, hull structure left after %d s)" % int(secs), "| tier | gun | median | matches | win rate |", "|---|---|---|---|---|"]
	for tier in _tiers():
		var by := {}
		for r in rows:
			if r["mode"] == "pair" and int(r["tier"]) == tier:
				if not by.has(r["a"]):
					by[r["a"]] = []
				by[r["a"]].append(float(r["win"]))
		var best := 0.0
		var best_id := ""
		var mid := ""
		for id in by:
			mid = str(rows.filter(func(r): return r["mode"] == "pair" and r["a"] == id)[0]["b"])
			var wr := _mean(by[id])
			L.append("| %d | %s | %s | %d | %.0f%% |" % [tier, id, mid, by[id].size(), wr * 100.0])
			if wr > best:
				best = wr
				best_id = str(id)
		L.append("| %d | best: %s | | | %.0f%% (limit 60%%) |" % [tier, best_id, best * 100.0])
	return "\n".join(L)


## Point defence against the missiles and slow shells, shields against the beams and lasers, the plating table.
func counters_report() -> String:
	var L: Array[String] = ["## Counters", "| gun | family | no counter (hp) | with 3 PD Mk of its tier | share left | on shielded hulls vs plain |", "|---|---|---|---|---|---|"]
	for tier in _tiers():
		for id in guns_of(tier):
			var plain := rows.filter(func(r): return r["gun"] == id and r["kind"] == "plain" and r["mode"] == "solo")
			var shield := rows.filter(func(r): return r["gun"] == id and r["kind"] == "shield" and r["mode"] == "solo")
			var pd := rows.filter(func(r): return r["gun"] == id and r["kind"] == "pd")
			if plain.is_empty() or pd.is_empty():
				continue
			var p := _mean(plain.map(func(r): return r["dealt"]))
			var d := _mean(pd.map(func(r): return r["dealt"]))
			var s := _mean(shield.map(func(r): return r["dealt"])) if not shield.is_empty() else 0.0
			L.append("| %s | %s | %.1f | %.1f | %.0f%% | %.0f%% |" % [id, family_of(id), p, d, 100.0 * d / maxf(p, 1e-6), 100.0 * s / maxf(p, 1e-6)])
	L.append("")
	L.append("## Plating (share of the damage that gets through, data/tiles.json resist)")
	var tiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles.json"))
	var tl: Array = tiles["tiles"] if tiles is Dictionary else tiles
	L.append("| plating | kinetic | energy | explosive | ion |")
	L.append("|---|---|---|---|---|")
	for t in tl:
		if t is Dictionary and t.has("resist") and not (t["resist"] as Dictionary).is_empty():
			var rs: Dictionary = t["resist"]
			L.append("| %s | %.2f | %.2f | %.2f | %.2f |" % [t["id"], rs.get("kinetic", 1.0), rs.get("energy", 1.0), rs.get("explosive", 1.0), rs.get("ion", 1.0)])
	return "\n".join(L)
