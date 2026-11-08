extends RefCounted
## Not a test (the runner only loads test_*.gd): the fight probe of tests/tool_standoff.gd and tests/tool_flagships.gd. It watches an arena
## fight of ship 0 (the player) against ship 1 (the enemy) from the arena's events and records, per side as the attacker ("p", "e"):
## - its shots, and the hp its hits took off the other's blocks: hull (walls and doors), parts, and the guns among the parts;
## - what the other's shield took (shield HP) and let through, and its ricochets and deflects;
## - what the other's plating ate, rebuilt from each wall or door hit: the hit dealt `dealt` = raw x slope x resist (damage.gd), so the slope
##   (a kinetic or explosive hit at an angle keeps clamp(cos, 0.5, 1) of it: the kinetic floor) ate raw x (1 - slope) and the plating's resist
##   raw x slope x (1 - resist), negative where the plate is weak to the type (scrap plate and explosives);
## - the hp it dealt in each second, the time of its last hit (on blocks or on the shield) and its last shot;
## - its guns (every gun but point defence that it began with) that work: ok, powered and fed (morale.gd's test), each second;
## and every TRACK_S the centre and hull-to-hull distance and both structures. classify() puts a fight that ran to the cap in one class.
## No change to the game: it reads the arena only.

const Ammo = preload("res://scripts/sim/ammo.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Structure = preload("res://scripts/ship/structure.gd")
const Volley = preload("res://scripts/combat/volley.gd")

const TRACK_S := 5.0  ## seconds between the distance samples
const LAST_S := 60.0  ## the end window classify() reads
const X_SHARE := 1.0 / 360.0  ## of the target's block hp, a second: under it, a side lands too little to end the fight (whole to the wreck line, 0.5, takes the 180 s cap; see classify)
const CLASSES: Array[String] = ["wall", "no finish", "out of reach", "grind", "both disarmed"]

var arena
var pilot  ## a PilotAI of ship 0 (for the hull gap), or null (the gap is then -1)
var r := {}
var _cursor := 0
var _guns: Array = [[], []]  # the gun uids each side began with (no point defence)
var _next_track := 0.0
var _sec := -1


func _init(p_arena, p_pilot = null) -> void:
	arena = p_arena
	pilot = p_pilot
	for s in 2:
		var x := _side(s)
		for k in ["shots", "hull", "part", "gunpart", "shield_hp", "shield_n", "passed", "plate", "slope", "bounce", "hits"]:
			r[x + k] = 0.0
		for k in ["last_hit", "last_shot", "t_first_out", "t_all_out"]:
			r[x + k] = -1.0
		r[x + "sec"] = []  # hp dealt in each whole second
		r[x + "armed"] = []  # 1 where a gun of it worked at the end of that second, else 0
		var co = arena.ships[s]
		for uid in co.mounts:
			if not Volley.is_pd(arena.weapons.def(co.mounts[uid]["id"])):
				_guns[s].append(uid)
		r[x + "guns"] = _guns[s].size()
		r[x + "blocks"] = Structure.totals(co.ship).y
	r["track"] = []  # [t, centre distance, hull gap, structure 0, structure 1, working guns 0, working guns 1]
	_cursor = arena.events.size()


static func _side(s: int) -> String:
	return "p_" if s == 0 else "e_"


## Read the events since the last call (call it after every arena step).
func step() -> void:
	var t: float = arena.time()
	var ev: Array = arena.events
	var tiles := {}  # (ship, cell, tick) -> the tile a breach of this batch took away
	for k in range(_cursor, ev.size()):
		if str(ev[k]["type"]) == "breach":
			tiles[[int(ev[k]["ship"]), ev[k]["cell"], int(ev[k]["tick"])]] = str(ev[k].get("tile", ""))
	for k in range(_cursor, ev.size()):
		var e: Dictionary = ev[k]
		var hit_on := int(e["ship"])
		var x := _side(1 - hit_on)  # the attacker of a hit, a shield hit or a bounce on ship hit_on
		match str(e["type"]):
			"shot":
				r[_side(hit_on) + "shots"] += 1  # (the shooter, for a shot)
				r[_side(hit_on) + "last_shot"] = t
			"hit":
				if e.get("hazard", false):
					continue
				var dealt := float(e.get("dealt", 0.0))
				r[x + "hits"] += 1
				r[x + "last_hit"] = t
				_bucket(x, t, dealt)
				if str(e.get("kind", "")) == "component":
					r[x + "part"] += dealt
					var inst = arena.ships[hit_on].ship.components.instances.get(arena.ships[hit_on].ship.components.at(e["cell"]))
					if inst == null:
						inst = arena.ships[hit_on].ship.components.instances.get(arena.ships[hit_on].ship.components.at_out(e["cell"]))
					if inst != null and str(arena.ships[hit_on].ship.components.def(inst["id"]).get("family", "")) == "weapon":
						r[x + "gunpart"] += dealt
				else:
					r[x + "hull"] += dealt
					_plating(x, hit_on, e, dealt, tiles)
			"shield":
				r[x + "shield_hp"] += float(e.get("hp", 0.0))
				r[x + "passed"] += float(e.get("passed", 0.0))
				r[x + "shield_n"] += 1
				r[x + "last_hit"] = t
			"ricochet", "deflect":
				r[x + "bounce"] += 1
	_cursor = ev.size()
	if int(t) != _sec:
		_sec = int(t)
		for s in 2:
			var a: Array = r[_side(s) + "armed"]
			while a.size() <= _sec:
				a.append(0)
			var w := working(s)
			a[_sec] = int(w > 0)
			if w < _guns[s].size() and r[_side(s) + "t_first_out"] < 0.0:
				r[_side(s) + "t_first_out"] = t
			if w == 0 and r[_side(s) + "t_all_out"] < 0.0:
				r[_side(s) + "t_all_out"] = t
	if t >= _next_track - 1e-6:
		_next_track = t + TRACK_S
		var p0: Vector2 = arena.ships[0].flight.pos
		var to: Vector2 = arena.ships[1].flight.pos - p0
		var gap := -1.0
		if pilot != null and to.length() > 1.0:
			gap = to.length() - pilot.extent(0, to.normalized()) - pilot.extent(1, -to.normalized())
		r["track"].append([snappedf(t, 0.1), roundf(to.length()), roundf(gap), snappedf(Structure.structure_fraction(arena.ships[0]), 0.001),
			snappedf(Structure.structure_fraction(arena.ships[1]), 0.001), working(0), working(1)])


func _bucket(x: String, t: float, dealt: float) -> void:
	var a: Array = r[x + "sec"]
	while a.size() <= int(t):
		a.append(0.0)
	a[int(t)] = snappedf(float(a[int(t)]) + dealt, 0.01)


## A wall or door hit: what the slope and the plating's resist ate (see the top). The tile is the one a breach of this batch took, else the one there now.
func _plating(x: String, idx: int, e: Dictionary, dealt: float, tiles: Dictionary) -> void:
	var dtype := str(e.get("dtype", ""))
	if dealt <= 0.0 or dtype == "ion":
		return
	var grid = arena.ships[idx].ship.grid
	var key := [idx, e["cell"], int(e["tick"])]
	var tile: String = tiles[key] if tiles.has(key) else grid.get_tile(e["cell"])
	if tile == "" or grid.defs == null:
		return
	var resist := float(grid.defs.get_def(tile).get("resist", {}).get(dtype, 1.0)) / Damage.corrode_mult(arena, idx, e["cell"])
	var slope := 1.0
	if e.has("n") and e.has("dir") and Vector2(e["n"]) != Vector2.ZERO:
		slope = Damage.slope_factor(dtype, clampf(-Vector2(e["dir"]).dot(Vector2(e["n"])), 0.0, 1.0))
	if resist * slope <= 0.0:
		return
	var raw := dealt / (resist * slope)
	r[x + "slope"] += raw * (1.0 - slope)
	r[x + "plate"] += raw * slope * (1.0 - resist)


## The guns of ship `s` (of those it began with) that could fire now: ok, powered and fed.
func working(s: int) -> int:
	var co = arena.ships[s]
	var n := 0
	for uid in _guns[s]:
		var m = co.mounts.get(uid)
		if m == null or arena.weapons.status_of(arena, s, uid) != "ok" or not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
			continue
		var ammo := str(arena.weapons.def(m["id"])["ammo"])
		n += int(ammo == "" or Ammo.can_supply(co.ship, uid, ammo, 1))
	return n


## The record, for the row of the fight.
func result() -> Dictionary:
	return r


# --- the classes ------------------------------------------------------------------------------------

## The hp side `x` ("p_" or "e_") dealt to blocks in the last `secs` seconds of a fight `t` long, a second.
static func rate(row: Dictionary, x: String, secs := LAST_S) -> float:
	var a: Array = row.get(x + "sec", [])
	var t := float(row["t"])
	var sum := 0.0
	for i in a.size():
		if float(i) >= t - secs - 1e-6:
			sum += float(a[i])
	return sum / maxf(minf(secs, t), 1.0)


## The share of the last `secs` seconds in which side `x` had a working gun.
static func armed_share(row: Dictionary, x: String, secs := LAST_S) -> float:
	var a: Array = row.get(x + "armed", [])
	var t := float(row["t"])
	var n := 0
	var on := 0
	for i in a.size():
		if float(i) >= t - secs - 1e-6:
			n += 1
			on += int(a[i])
	return float(on) / float(maxi(n, 1))


## The class of a fight that ran to the cap, from its last LAST_S seconds. X, the least a side must land a second, is `share` (X_SHARE) of the
## target's block hp (FightProbe records them at the start: p_blocks, e_blocks):
## - "out of reach": no hit either way (on blocks or on a shield);
## - "no finish": one side had a working gun for under half of it, and the other landed under X on its blocks;
## - "both disarmed": neither had a working gun for half of it;
## - "wall": both armed, each landing under X;
## - "grind": a side lands X or more and the other still stands (it had far to fall, or crew mend it).
static func classify(row: Dictionary, share := X_SHARE) -> String:
	var t := float(row["t"])
	if float(row.get("p_last_hit", -1.0)) < t - LAST_S and float(row.get("e_last_hit", -1.0)) < t - LAST_S:
		return "out of reach"
	var pa := armed_share(row, "p_") >= 0.5
	var ea := armed_share(row, "e_") >= 0.5
	var pr := rate(row, "p_") / maxf(share * float(row.get("e_blocks", 1.0)), 1e-6)  # in X of the target
	var er := rate(row, "e_") / maxf(share * float(row.get("p_blocks", 1.0)), 1e-6)
	if not pa and not ea:
		return "both disarmed"
	if not pa or not ea:
		return "no finish" if (er if not pa else pr) < 1.0 else "grind"
	return "wall" if pr < 1.0 and er < 1.0 else "grind"
