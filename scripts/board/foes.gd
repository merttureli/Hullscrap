extends RefCounted
## Everyone hostile aboard (docs/BOARDING.md, stage B2): who stands where (spawn_site), how they notice, chase, shoot, take cover, flee and hide, the
## sentry turrets (hackable) and the crawler in the vents. Pure logic: the session (boarding.gd) owns one and ticks it; board_view.gd draws.
## A foe is a Dictionary {id, kind, d (its data/boarding.json entry), m (a CrewMember: pos, hp, facing, path), team ("foe", or "player" for a hacked
## sentry), mode, dead, hidden, moved, ...}. Modes of a walker: idle, hunt (heads for `target`), attack (has a line on someone), cover (pirates), flee
## (scavengers hurt), search (reached the last known spot, looks about), regroup (walks home). A sentry sweeps then tracks; a crawler is hidden at a
## vent, stalks (it only moves while no light is on it), lunges, then retreats to a vent.
## Senses: a sight cone and a range that depends on the light (dark / a room with an emergency light / in the beam of the flashlight), and noise (a shot
## alerts every foe within 12 cells). Pathing is the crew pathfinder on the site's walk grid with the session's door rule. All randomness is the session's rng.

const Site = preload("res://scripts/board/site.gd")
const Arms = preload("res://scripts/board/arms.gd")
const BoardLight = preload("res://scripts/board/board_light.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Themes = preload("res://scripts/board/themes.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const SEARCH_S := 4.0  ## seconds a hunter looks about at the last place it saw someone
const LOSE_S := 5.0  ## seconds without a line before a hunter gives up the chase at its target
const COVER_S := 2.5  ## seconds behind a prop
const COVER_CD := 7.0  ## seconds before the same pirate takes cover again
const HIT_MEMORY := 1.5  ## seconds a foe counts as "under fire" after a hit
const SHOT_RANGE := 16.0  ## cells a foe's ray travels
const SEE_HUNT := 18.0  ## cells a hunter sees its quarry across a clear line
const STALK_MAX := 30.0  ## seconds a crawler stalks before it goes back to its vent

var s  ## the session (boarding.gd)
var list: Array = []  ## every foe, dead ones too (they lie where they fell)
var vents: Array = []  ## [Vector2] the vent cells (middles) of the site
var soldier_moving := false
var _next := 0
var _clock := 0.0
var _aim := 0.0
var _light := true
var _prev_soldier := Vector2.ZERO
var _anchors := {}  # room id -> free anchors
var _red := {}  # room id -> true: the rooms with an emergency light


func _init(p_session = null) -> void:
	s = p_session
	if s != null:
		for l in s.site.lights:
			if l["color"] == "red":
				_red[l["room"]] = true
		_prev_soldier = s.soldier.pos


static func def(kind: String) -> Dictionary:
	return Site.config()["enemies"][kind]


static func kinds() -> Array:
	return Site.config()["enemies"].keys().filter(func(k): return not k.begins_with("_"))


func find(id: int) -> Dictionary:
	for f in list:
		if f["id"] == id:
			return f
	return {}


## The foes that are up (not dead) and on the hostile side.
func live() -> Array:
	return list.filter(func(f): return not f["dead"] and f["team"] == "foe")


# --- spawning -------------------------------------------------------------------------------------------------------

## Fill the site: the count and mix of its kind (data/boarding.json spawn), picked by the room's purpose, seeded by the site alone. `ctx`: {hollow
## (the place is the Hollow's), crew (a wreck's survivors), mem (what an earlier visit left: {hollow, dead: [ids]})}.
func spawn_site(ctx := {}) -> void:
	list.clear()
	vents.clear()
	_next = 0
	var site = s.site
	var sc: Dictionary = Site.config()["spawn"]
	var rng := RandomNumberGenerator.new()
	rng.seed = Site._mix(site.seed_value, "spawn", 0)
	_make_vents(rng)
	var kc: Dictionary = sc["kinds"].get(site.kind, {"count": [0, 0], "mix": {"scavenger": 1}})
	var n := mini(int(ctx.get("crew", 0)), int(sc["crew_max"])) if site.kind == "wreck" else Themes.foe_count(site.theme, rng.randi_range(int(kc["count"][0]), int(kc["count"][1])))
	var mix: Dictionary = Themes.foe_mix(site.theme, kc["mix"])  # (the theme's tilt of who stands here)
	var spots := _spots(float(sc["min_from_airlock"]))
	if spots.is_empty():
		spots = _spots(4.0)
	var hollow := bool(ctx.get("hollow", false))
	for i in n:
		var kind := _pick(mix, rng)
		if hollow and rng.randf() < float(sc["hollow_share"]):
			kind = "hollow_touched"
		var spot := _spot(spots, rng)
		if spot.is_empty():
			break
		add(kind, spot["pos"], int(spot["room"]))
	if not vents.is_empty() and rng.randf() < float(sc["crawler"]["chance"]):
		var v: Vector2 = vents[rng.randi() % vents.size()]
		add("crawler", v, site.room_at(v))
	var mem: Dictionary = ctx.get("mem", {})
	if bool(mem.get("hollow", false)) == hollow:
		for id in mem.get("dead", []):
			var f := find(int(id))
			if not f.is_empty():
				f["dead"] = true
				f["mode"] = "dead"
				f["m"].hp = 0.0


## What a later visit finds: the foes that were beaten.
func memory() -> Dictionary:
	var dead := []
	for f in list:
		if f["dead"] and f["spawned"]:
			dead.append(f["id"])
	return {"hollow": s.hollow_place, "dead": dead}


## A foe of `kind` standing at `pos` (cells). Returns it. `spawned` is false for one that did not stand here from the start (it is not in the site's memory of the dead).
func add(kind: String, pos: Vector2, room := -1, spawned := true) -> Dictionary:
	var d: Dictionary = def(kind)
	var m := CrewMember.new(str(d["name"]), pos, "human")
	m.max_hp = float(d["hp"])
	m.hp = m.max_hp
	m.speed = CrewMember.BASE_SPEED * float(d["speed"])
	m.look = d.get("look", {})
	if kind == "crawler":
		m.body_size = 1
	var site = s.site
	var base := 0.0
	if room >= 0:
		var r: Rect2i = site.rooms[room]["rect"]
		base = (Vector2(r.position) + Vector2(r.size) / 2.0 - pos).angle()
	m.facing = Vector2.from_angle(base)
	var f := {"id": _next, "kind": kind, "d": d, "m": m, "team": "foe", "mode": "idle", "dead": false, "hidden": false, "moved": false, "spawned": spawned,
		"room": room, "home": pos, "target": pos, "seen_at": pos, "notice": 0.0, "lost": 0.0, "wait": 0.0, "repath": 0.0, "cd": s.rng.randf_range(0.2, 0.9),
		"hurt_t": 0.0, "cover_cd": 0.0, "cover_pos": pos, "refuge": pos, "base": base, "aim": base, "track": 0.0, "tpos": pos, "spoke": false,
		"stalk_t": 0.0, "seen_t": 0.0, "lunge": 0.0, "lunge_cd": 1.5, "bites": 0, "frozen": false, "hack": 0.0}
	_next += 1
	if kind == "crawler":
		f["mode"] = "hidden"
		f["hidden"] = true
		f["wait"] = s.rng.randf_range(2.0, 6.0)
	list.append(f)
	return f


func _anchors_of(rid: int) -> Array:
	if not _anchors.has(rid):
		_anchors[rid] = s.site.free_anchors(rid) if rid >= 0 else []
	return _anchors[rid]


## Spots foes may stand on: [{room, pos}] at least `min_d` cells from where the soldier arrives, never in the airlock's own room.
func _spots(min_d: float) -> Array:
	var out := []
	var site = s.site
	var w: Dictionary = Site.config()["spawn"]["room_weights"]
	for r in site.rooms:
		if r["purpose"] == "gone" or r["id"] == site.airlock["room"] or float(w.get(r["purpose"], 0.5)) <= 0.0:
			continue
		for a in _anchors_of(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			if p.distance_to(site.airlock["spawn"]) >= min_d:
				out.append({"room": r["id"], "pos": p, "w": float(w.get(r["purpose"], 0.5))})
	return out


## One of `spots` (a room by its weight, then a spot not close to a foe already there), removed from the list; {} when none is left.
func _spot(spots: Array, rng: RandomNumberGenerator) -> Dictionary:
	if spots.is_empty():
		return {}
	var rooms := {}
	for sp in spots:
		rooms[sp["room"]] = sp["w"]
	var rid := int(_pick_weighted(rooms, rng))
	var here := spots.filter(func(sp): return sp["room"] == rid)
	var pick: Dictionary = here[rng.randi() % here.size()]
	for k in 6:
		var cand: Dictionary = here[rng.randi() % here.size()]
		if not list.any(func(f): return f["m"].pos.distance_to(cand["pos"]) < 3.5):
			pick = cand
			break
	spots.erase(pick)
	return pick


## A key of the weighted dictionary `w` ({key: weight}).
static func _pick_weighted(w: Dictionary, rng: RandomNumberGenerator):
	var total := 0.0
	for k in w:
		total += float(w[k])
	var roll := rng.randf() * total
	var last = null
	for k in w:
		last = k
		roll -= float(w[k])
		if roll < 0.0:
			return k
	return last


static func _pick(w: Dictionary, rng: RandomNumberGenerator) -> String:
	return str(_pick_weighted(w, rng))


## Vents: a few floor cells by a wall in rooms that are not the airlock or a corridor (where a crawler hides, drawn as a grate).
func _make_vents(rng: RandomNumberGenerator) -> void:
	var site = s.site
	var rooms: Array = site.rooms.filter(func(r): return r["purpose"] != "gone" and r["purpose"] != "airlock" and not r["corridor"])
	var want := rng.randi_range(int(Site.config()["spawn"]["crawler"]["vents"][0]), int(Site.config()["spawn"]["crawler"]["vents"][1]))
	for i in range(rooms.size() - 1, 0, -1):  # shuffled by the rng
		var j := rng.randi() % (i + 1)
		var t = rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = t
	for r in rooms:
		if vents.size() >= want:
			break
		var rect: Rect2i = r["rect"]
		var cells := []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, y)
				var ring: bool = x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
				if ring and site.grid.get_tile(c) == "floor" and not site.prop_of.has(c) and not site.door_of.has(c) and Pathfinder.body_ok(site.walk, c, Callable(), 1):
					cells.append(c)
		if not cells.is_empty():
			var pick: Vector2i = cells[rng.randi() % cells.size()]
			vents.append(Vector2(pick) + Vector2(0.5, 0.5))


# --- what a shot can hit, what the tracker sees ----------------------------------------------------------------------

## What the soldier's shots (and a hacked sentry's) can hit: [{pos, r, ref}] the foes that are up, in the open and on the hostile side.
func bodies() -> Array:
	var out := []
	var r: float = float(Site.config()["combat"]["hit_r"])
	for f in list:
		if not f["dead"] and not f["hidden"] and f["team"] == "foe":
			var shrink := 0.7 if f["kind"] == "crawler" else (0.55 if f["mode"] == "cover" and f["m"].path.is_empty() else 1.0)  # a small body, or one behind a prop
			out.append({"pos": f["m"].pos, "r": r * shrink, "ref": f})
	return out


## What the motion tracker is shown: [{pos, moving}] the foes that are up and out of their vents (the crawler only shows when it moves).
func contacts() -> Array:
	var out := []
	for f in list:
		if not f["dead"] and not f["hidden"] and f["team"] == "foe":
			out.append({"pos": f["m"].pos, "moving": f["moved"]})
	return out


## The cells of the vents the view draws.
func vent_cells() -> Array:
	return vents


# --- hits and noise --------------------------------------------------------------------------------------------------

## `amount` damage to foe `f`, struck at `at`.
func hurt(f: Dictionary, amount: float, at: Vector2) -> void:
	if f["dead"]:
		return
	var m: CrewMember = f["m"]
	m.hurt(amount)
	f["hurt_t"] = HIT_MEMORY
	s.events.append({"type": "hit", "pos": at, "foe": f["id"], "kind": f["kind"]})
	if m.hp <= 0.0:
		f["dead"] = true
		f["mode"] = "dead"
		m.path.clear()
		s.events.append({"type": "down", "pos": m.pos, "foe": f["id"], "kind": f["kind"]})
		return
	match str(f["kind"]):
		"crawler":
			s.events.append({"type": "screech", "pos": m.pos})
			if f["mode"] == "stalk" and s.rng.randf() < 0.4:
				f["mode"] = "retreat"
		"sentry":
			f["track"] = 1.5
			f["tpos"] = s.soldier.pos
		_:
			if f["mode"] in ["idle", "search", "regroup"]:
				_alert(f, s.soldier.pos)


## A noise at `at` (a shot, a swing): every foe within `radius` cells that is not already in the fight heads there.
func noise(at: Vector2, radius: float) -> void:
	for f in list:
		if f["dead"] or f["hidden"] or f["team"] != "foe" or f["kind"] in ["sentry", "crawler"]:
			continue
		if f["mode"] in ["idle", "search", "regroup"] and f["m"].pos.distance_to(at) <= radius:
			_alert(f, at)


## Foe `f` knows where someone is: it hunts there, and calls the mates close by.
func _alert(f: Dictionary, at: Vector2) -> void:
	if f["mode"] in ["idle", "search", "regroup"]:
		f["mode"] = "hunt"
	f["target"] = at
	f["lost"] = 0.0
	f["notice"] = float(Site.config()["combat"]["sight"]["notice_s"])
	s.events.append({"type": "notice", "pos": f["m"].pos, "foe": f["id"], "kind": f["kind"]})
	var d: Dictionary = f["d"]
	if d.has("lines") and not f["spoke"]:
		f["spoke"] = true
		var lines: Array = d["lines"]
		s.events.append({"type": "line", "pos": f["m"].pos, "text": str(lines[s.rng.randi() % lines.size()]), "foe": f["id"]})
	var call_r := float(d.get("alert_r", 0.0))
	if call_r <= 0.0:
		return
	for g in list:
		if g != f and not g["dead"] and g["team"] == "foe" and g["mode"] in ["idle", "search", "regroup"] and not (g["kind"] in ["sentry", "crawler"]) \
				and g["m"].pos.distance_to(f["m"].pos) <= call_r:
			g["mode"] = "hunt"
			g["target"] = at
			g["lost"] = 0.0
			g["notice"] = float(Site.config()["combat"]["sight"]["notice_s"])


## The Hollow takes the place while the soldier is aboard: hollow_touched appear on the airlock side, already hunting him.
func hollow_arrives() -> void:
	var site = s.site
	var hc: Dictionary = Site.config()["combat"]["hollow"]
	var n: int = s.rng.randi_range(int(hc["count"][0]), int(hc["count"][1]))
	var spots := []
	var from: Vector2 = site.airlock["spawn"]
	for r in site.rooms:
		if r["purpose"] == "gone":
			continue
		for a in _anchors_of(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			if p.distance_to(s.soldier.pos) >= 4.5:
				spots.append({"room": r["id"], "pos": p, "d": p.distance_to(from)})
	spots.sort_custom(func(x, y): return x["d"] < y["d"])
	for i in n:
		var spot: Dictionary = {}
		for sp in spots:  # the nearest spot to the airlock that is not close to a foe already there
			if not list.any(func(f): return f["m"].pos.distance_to(sp["pos"]) < 2.5):
				spot = sp
				break
		if spot.is_empty():
			break
		var f := add("hollow_touched", spot["pos"], int(spot["room"]), false)
		f["mode"] = "hunt"
		f["target"] = s.soldier.pos
		f["spoke"] = true


## Foe `f` is after the soldier at once (a person who turned on him, an ambush).
func provoke(f: Dictionary) -> void:
	f["mode"] = "hunt"
	f["target"] = s.soldier.pos
	f["lost"] = 0.0
	f["notice"] = float(Site.config()["combat"]["sight"]["notice_s"])
	f["spoke"] = true


## `n` foes of `kind` come at the soldier from out of sight: the free spots 5 to 11 cells from him (people.fight.from), the nearest of them to a point
## `from` first, hunting. Returns how many came.
func ambush(kind: String, n: int, from: Vector2) -> int:
	var span: Array = Site.config()["people"]["fight"]["from"]
	var spots := []
	for r in s.site.rooms:
		if r["purpose"] == "gone":
			continue
		for a in _anchors_of(r["id"]):
			var p := Vector2(a) + Vector2.ONE
			var d := p.distance_to(s.soldier.pos)
			if d >= float(span[0]) and d <= float(span[1]) and not list.any(func(f): return f["m"].pos.distance_to(p) < 2.5):
				spots.append({"room": r["id"], "pos": p, "d": p.distance_to(from)})
	spots.sort_custom(func(x, y): return x["d"] < y["d"])
	var came := 0
	for sp in spots:
		if came >= n:
			break
		if list.any(func(f): return f["m"].pos.distance_to(sp["pos"]) < 3.0):
			continue
		provoke(add(kind, sp["pos"], int(sp["room"]), false))
		came += 1
	return came


# --- the tick --------------------------------------------------------------------------------------------------------

## `dt` seconds pass. `aim` is where the flashlight points (radians), `light_on` whether it is lit.
func tick(dt: float, aim: float, light_on: bool) -> void:
	_clock += dt
	_aim = aim
	_light = light_on
	soldier_moving = s.soldier.pos.distance_to(_prev_soldier) > 0.001
	_prev_soldier = s.soldier.pos
	for f in list:
		if f["dead"]:
			continue
		var prev: Vector2 = f["m"].pos
		f["cd"] = maxf(float(f["cd"]) - dt, 0.0)
		f["hurt_t"] = maxf(float(f["hurt_t"]) - dt, 0.0)
		f["cover_cd"] = maxf(float(f["cover_cd"]) - dt, 0.0)
		match str(f["kind"]):
			"sentry":
				_sentry(f, dt)
			"crawler":
				_crawler(f, dt)
			_:
				_walker(f, dt)
		f["moved"] = f["m"].pos.distance_to(prev) > 0.002
	_separate()


## Foes that stand on each other drift apart.
func _separate() -> void:
	var pas: Callable = s.door_passable()
	for f in list:
		if f["dead"] or f["hidden"] or f["kind"] == "sentry" or not f["moved"]:
			continue
		for g in list:
			if g == f or g["dead"] or g["hidden"] or g["kind"] == "sentry":
				continue
			var off: Vector2 = f["m"].pos - g["m"].pos
			if off.length() < 1.1:
				var push: Vector2 = (off.normalized() if off.length() > 0.001 else Vector2.RIGHT) * 0.04
				if f["m"].fits(s.site.walk, f["m"].pos + push, pas):
					f["m"].pos += push


# --- seeing ---------------------------------------------------------------------------------------------------------

## How far a foe at `from` sees the party member `t` ({pos, ref}), in cells: the dark, a room with an emergency light, or the soldier's beam on it.
func _sight(t: Dictionary, from: Vector2) -> float:
	var sc: Dictionary = Site.config()["combat"]["sight"]
	var r := float(sc["dark"])
	if _red.has(s.site.room_at(t["pos"])):
		r = maxf(r, float(sc["red"]))
	if t["ref"] == s.soldier and _in_beam(from):
		r = maxf(r, float(sc["lit"]))
	return r


## Is point `p` in the soldier's flashlight beam (lit, within its reach, inside its cone, a clear line)?
func _in_beam(p: Vector2) -> bool:
	if not _light:
		return false
	var off: Vector2 = p - s.soldier.pos
	return off.length() <= float(Site.config()["combat"]["flash_range"]) and absf(angle_difference(_aim, off.angle())) <= BoardLight.CONE_HALF \
		and s.site.clear_line(s.soldier.pos, p)


## Is a point lit enough for the soldier to see something there: in his beam, or close enough for the small light round him.
func lit(p: Vector2) -> bool:
	var sc: Dictionary = Site.config()["combat"]
	if s.soldier.pos.distance_to(p) <= float(sc["self_range"]) and s.site.clear_line(s.soldier.pos, p):
		return true
	return _in_beam(p)


## The nearest party member (the soldier, or a follower who is up) within `maxd` cells of foe `f` across a clear line, {} for none.
func _best_target(f: Dictionary, maxd: float) -> Dictionary:
	var best := {}
	var bd := INF
	for t in s.party_bodies():
		var d: float = f["m"].pos.distance_to(t["pos"])
		if d <= maxd and d < bd and s.site.clear_line(f["m"].pos, t["pos"]):
			best = t
			bd = d
	return best


## An idle foe watches: anyone in its cone inside its sight range is noticed after notice_s, sooner when close.
func _watch(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	var sc: Dictionary = Site.config()["combat"]["sight"]
	var fov := deg_to_rad(float(f["d"].get("fov_deg", 120.0))) / 2.0
	var seen := false
	var gain := 0.0
	for t in s.party_bodies():
		var off: Vector2 = t["pos"] - m.pos
		var d := off.length()
		var reach := _sight(t, m.pos)
		if d > reach or (d > 2.0 and absf(angle_difference(m.facing.angle(), off.angle())) > fov):
			continue
		if not s.site.clear_line(m.pos, t["pos"]):
			continue
		seen = true
		gain = maxf(gain, 1.0 + 2.0 * (1.0 - d / reach))
		f["seen_at"] = t["pos"]
	if seen:
		f["notice"] = float(f["notice"]) + dt * gain
		if float(f["notice"]) >= float(sc["notice_s"]):
			_alert(f, f["seen_at"])
	else:
		f["notice"] = maxf(float(f["notice"]) - dt * 0.5, 0.0)


# --- walkers --------------------------------------------------------------------------------------------------------

func path_to(f: Dictionary, to: Vector2) -> void:
	var m: CrewMember = f["m"]
	var walk = s.site.walk
	var pas: Callable = s.door_passable()
	var body: int = m.body_size
	var from := Pathfinder.anchor_of(m.pos, body)
	if not Pathfinder.body_ok(walk, from, pas, body):
		from = Pathfinder.nearest_walkable(walk, m.pos, pas, Pathfinder.NO_CELL, body)
	var goal := Pathfinder.anchor_of(to, body)
	if not Pathfinder.body_ok(walk, goal, pas, body):
		goal = Pathfinder.nearest_walkable(walk, to, pas, Pathfinder.NO_CELL, body)
	m.path = [] if from == Pathfinder.NO_CELL or goal == Pathfinder.NO_CELL else Pathfinder.find_path(walk, from, goal, pas, body)


## Walk toward `to`, finding the way again every half second or so.
func _chase(f: Dictionary, dt: float, to: Vector2) -> void:
	f["repath"] = float(f["repath"]) - dt
	if float(f["repath"]) <= 0.0:
		path_to(f, to)
		f["repath"] = 0.5 + 0.1 * float(int(f["id"]) % 4)
	f["m"].step(dt)


func _face(f: Dictionary, at: Vector2) -> void:
	var off: Vector2 = at - f["m"].pos
	if off.length() > 0.01:
		f["m"].facing = off.normalized()


func _walker(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	var d: Dictionary = f["d"]
	var at: Dictionary = d["attack"]
	var melee := bool(d.get("melee", false))
	var mode: String = f["mode"]
	if mode != "flee" and float(d.get("flee_below", 0.0)) > 0.0 and m.hp <= m.max_hp * float(d["flee_below"]):
		mode = "flee"
		f["mode"] = "flee"
		f["wait"] = 0.0
		f["refuge"] = m.pos
		_refuge(f)
	var vis := _best_target(f, SEE_HUNT) if mode in ["hunt", "attack", "cover", "flee"] else {}
	var reach := float(at["range"])
	var hold := reach if melee else reach * float(d.get("hold", 0.7))
	match mode:
		"idle":
			_idle(f, dt)
			_watch(f, dt)
		"search":
			_chase(f, dt, f["target"])
			if m.path.is_empty():
				f["wait"] = float(f["wait"]) + dt
				m.facing = m.facing.rotated(dt * 0.9)
				if float(f["wait"]) > SEARCH_S:
					f["mode"] = "regroup"
					f["repath"] = 0.0
			_watch(f, dt)
		"regroup":
			_chase(f, dt, f["home"])
			if m.pos.distance_to(f["home"]) < 1.2 or m.path.is_empty():
				f["mode"] = "idle"
				f["wait"] = 1.0
			_watch(f, dt)
		"hunt":
			if not vis.is_empty():
				f["target"] = vis["pos"]
				f["lost"] = 0.0
				if m.pos.distance_to(vis["pos"]) <= hold:
					f["mode"] = "attack"
					m.path.clear()
				else:
					_chase(f, dt, vis["pos"])
			else:
				f["lost"] = float(f["lost"]) + dt
				_chase(f, dt, f["target"])
				if float(f["lost"]) > LOSE_S and (m.path.is_empty() or m.pos.distance_to(f["target"]) < 1.5):
					f["mode"] = "search"
					f["wait"] = 0.0
		"attack":
			if vis.is_empty():
				f["mode"] = "hunt"
				return
			f["target"] = vis["pos"]
			f["lost"] = 0.0
			var dist: float = m.pos.distance_to(vis["pos"])
			_face(f, vis["pos"])
			if melee:
				if dist > reach + 0.6:
					f["mode"] = "hunt"
				elif float(f["cd"]) <= 0.0:
					_melee(f, vis)
				return
			if dist > hold + 1.0:
				_chase(f, dt, vis["pos"])
				_face(f, vis["pos"])
			if dist <= reach + 1.0 and float(f["cd"]) <= 0.0:
				_shoot(f, vis)
			if d.get("cover", false) and float(f["hurt_t"]) > 0.0 and float(f["cover_cd"]) <= 0.0:
				_take_cover(f, vis)
		"cover":
			if m.path.is_empty():
				f["wait"] = float(f["wait"]) + dt
				if not vis.is_empty():
					_face(f, vis["pos"])
					if float(f["cd"]) <= 0.0 and m.pos.distance_to(vis["pos"]) <= reach + 1.0:
						_shoot(f, vis)
				if float(f["wait"]) >= COVER_S:
					f["mode"] = "hunt"
			else:
				m.step(dt)
		"flee":
			if not m.path.is_empty():
				m.step(dt)
			else:
				f["wait"] = float(f["wait"]) + dt
				if not vis.is_empty():
					var dd: float = m.pos.distance_to(vis["pos"])
					_face(f, vis["pos"])
					if dd < 7.0 and float(f["wait"]) > 1.5:
						f["wait"] = 0.0
						_refuge(f)  # it was found: it runs again
					if dd <= 3.5 and float(f["cd"]) <= 0.0:
						_shoot(f, vis)  # cornered, it fights


## A pirate looks for a spot in its room right beside a prop that stands between it and the target, and goes there. False when there is none.
## Behind a prop it shows less of itself (bodies()).
func _take_cover(f: Dictionary, vis: Dictionary) -> bool:
	var m: CrewMember = f["m"]
	var rid: int = s.site.room_at(m.pos)
	var props: Array = s.site.props.filter(func(p): return p["room"] == rid and p["blocks"])
	var best := Vector2.ZERO
	var bd := INF
	var reach := float(f["d"]["attack"]["range"])
	for a in _anchors_of(rid):
		var c := Vector2(a) + Vector2.ONE
		var dd := c.distance_to(m.pos)
		var ds := c.distance_to(vis["pos"])
		if dd > 7.0 or dd < 0.8 or dd >= bd or ds < 3.0 or ds > reach:
			continue
		for p in props:
			var pc: Vector2 = s.site.centre_of(p)
			var dp := c.distance_to(pc)
			if dp >= 1.2 and dp <= 2.4 and pc.distance_to(vis["pos"]) <= ds - 0.8 and absf(angle_difference((pc - c).angle(), (vis["pos"] - c).angle())) <= 0.95:
				best = c
				bd = dd
				break
	f["cover_cd"] = COVER_CD
	if bd == INF:
		return false
	f["cover_pos"] = best
	f["mode"] = "cover"
	f["wait"] = 0.0
	path_to(f, best)
	return true


## Where a hurt scavenger runs: the middle of one of the four rooms farthest from the soldier, the first whose way there does not pass close to him.
func _refuge(f: Dictionary) -> void:
	var m: CrewMember = f["m"]
	var rooms: Array = s.site.rooms.filter(func(r): return r["purpose"] != "gone" and not _anchors_of(r["id"]).is_empty())
	var from: Vector2 = s.soldier.pos
	rooms.sort_custom(func(a, b): return _centre(a).distance_to(from) > _centre(b).distance_to(from))
	var fallback := Vector2.ZERO
	var fallback_path: Array[Vector2i] = []
	for k in mini(4, rooms.size()):
		var anchors := _anchors_of(rooms[k]["id"])
		var a: Vector2i = anchors[anchors.size() / 2]
		var to := Vector2(a) + Vector2.ONE
		if to.distance_to(m.pos) > 40.0:
			continue
		path_to(f, to)
		if m.path.is_empty():
			continue
		if m.path.all(func(c): return (Vector2(c) + Vector2.ONE).distance_to(from) >= 3.0):
			f["refuge"] = to
			return
		if fallback_path.is_empty():
			fallback = to
			fallback_path = m.path.duplicate()
	m.path = fallback_path
	f["refuge"] = fallback


static func _centre(r: Dictionary) -> Vector2:
	var rect: Rect2i = r["rect"]
	return Vector2(rect.position) + Vector2(rect.size) / 2.0


func _idle(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	if str(f["d"].get("patrol", "stand")) == "wander":
		if not m.path.is_empty():
			m.step(dt)
			return
		f["wait"] = float(f["wait"]) - dt
		if float(f["wait"]) <= 0.0:
			f["wait"] = s.rng.randf_range(3.0, 6.0)
			var anchors := _anchors_of(int(f["room"]))
			if not anchors.is_empty():
				var a: Vector2i = anchors[s.rng.randi() % anchors.size()]
				path_to(f, Vector2(a) + Vector2.ONE)
	else:  # stands and looks about
		m.facing = Vector2.from_angle(float(f["base"]) + sin(_clock * 0.5 + float(f["id"])) * 0.7)


# --- attacks --------------------------------------------------------------------------------------------------------

## The sound class of foe `f`'s shot (its weapon's class), "rifle" for a turret.
func _snd(f: Dictionary) -> String:
	var w := Arms.weapon(str(f["d"].get("weapon", "")))
	return str(w.get("class", "rifle")) if not w.is_empty() else "rifle"


## Foe `f` fires at `t` ({pos, moving}): a ray with the error of its data, stopped by walls, doors and props, that hits the first body on the other side.
func _shoot(f: Dictionary, t: Dictionary) -> void:
	var m: CrewMember = f["m"]
	var at: Dictionary = f["d"]["attack"]
	f["cd"] = 1.0 / float(at["rate"])
	var err := float(f["d"]["inacc"]) * (1.3 if bool(t.get("moving", false)) else 1.0)
	var dir: float = (t["pos"] - m.pos).angle() + s.rng.randf_range(-err, err)
	var to_party: bool = f["team"] == "foe"
	var r := Arms.trace(s.site, m.pos, dir, SHOT_RANGE, s.party_bodies() if to_party else bodies(), s.rng, f)
	s.events.append({"type": "shot", "from": m.pos + Vector2.from_angle(dir) * 0.9, "to": r["end"], "who": "foe", "class": _snd(f), "kind": r["kind"]})
	if r["ref"] != null:
		if to_party:
			s.hurt_member(r["ref"], float(at["damage"]), m.pos)
		else:
			hurt(r["ref"], float(at["damage"]), r["end"])


## A melee foe strikes the party member `t`.
func _melee(f: Dictionary, t: Dictionary) -> void:
	var at: Dictionary = f["d"]["attack"]
	f["cd"] = 1.0 / float(at["rate"])
	s.events.append({"type": "melee", "pos": f["m"].pos, "foe": f["id"], "kind": f["kind"]})
	s.hurt_member(t["ref"], float(at["damage"]), f["m"].pos)


# --- sentries -------------------------------------------------------------------------------------------------------

func _turn(f: Dictionary, to: float, max_step: float) -> void:
	f["aim"] = float(f["aim"]) + clampf(angle_difference(float(f["aim"]), to), -max_step, max_step)


func _sentry(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	var d: Dictionary = f["d"]
	var hacked: bool = f["team"] == "player"
	var cone := deg_to_rad(float(d["cone_deg"])) / 2.0
	var reach := float(d["attack"]["range"])
	var tracking: bool = float(f["track"]) > 0.0
	var best := {}
	var bd := INF
	for t in (bodies() if hacked else s.party_bodies()):
		var off: Vector2 = t["pos"] - m.pos
		var dist := off.length()
		if dist > reach or dist >= bd:
			continue
		if not tracking and (absf(angle_difference(float(f["aim"]), off.angle())) > cone or (not hacked and dist > _sight(t, m.pos))):
			continue
		if is_same(t["ref"], f) or not s.site.clear_line(m.pos, t["pos"]):
			continue
		best = t
		bd = dist
	if not best.is_empty():
		if not tracking:
			s.events.append({"type": "whir", "pos": m.pos})
		f["track"] = 1.5
		f["tpos"] = best["pos"]
		var want: float = (best["pos"] - m.pos).angle()
		_turn(f, want, float(d["turn"]) * dt)
		if absf(angle_difference(float(f["aim"]), want)) < 0.14 and float(f["cd"]) <= 0.0:
			_shoot(f, best)
	elif tracking:
		f["track"] = float(f["track"]) - dt
		_turn(f, (f["tpos"] - m.pos).angle(), float(d["turn"]) * dt)
	else:
		_turn(f, float(f["base"]) + deg_to_rad(float(d["sweep_deg"])) * sin(_clock * float(d["sweep"]) + float(f["id"])), float(d["turn"]) * 0.4 * dt)
	m.facing = Vector2.from_angle(float(f["aim"]))


## Can the soldier at `p` hack sentry `f` now: it is up, still the enemy's, within reach and he stands behind it (outside its cone)?
func can_hack(f: Dictionary, p: Vector2) -> bool:
	var c: Dictionary = Site.config()["combat"]
	if f["kind"] != "sentry" or f["dead"] or f["team"] != "foe" or f["m"].pos.distance_to(p) > float(c["revive_reach"]):
		return false
	return absf(angle_difference(float(f["aim"]), (p - f["m"].pos).angle())) >= deg_to_rad(float(c["hack_back_deg"]))


## The soldier turns sentry `f` to his side.
func hack(f: Dictionary) -> void:
	f["team"] = "player"
	f["track"] = 0.0
	s.events.append({"type": "hacked", "pos": f["m"].pos, "foe": f["id"]})


## The nearest sentry the soldier can hack from `p`, null for none.
func hackable(p: Vector2):
	var best = null
	var bd := INF
	for f in list:
		if can_hack(f, p) and f["m"].pos.distance_to(p) < bd:
			best = f
			bd = f["m"].pos.distance_to(p)
	return best


# --- the crawler ----------------------------------------------------------------------------------------------------

func _crawler(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	var d: Dictionary = f["d"]
	var sold: CrewMember = s.soldier
	var lg: Dictionary = d["lunge"]
	f["lunge_cd"] = float(f["lunge_cd"]) - dt
	if float(f["lunge"]) > 0.0:  # a lunge, once begun, is not stopped by light
		_lunge(f, dt)
		return
	var seen: bool = _in_beam(m.pos) and not f["hidden"]  # only the beam freezes it: the glow round his feet is not looking
	match str(f["mode"]):
		"hidden":
			f["wait"] = float(f["wait"]) - dt
			if float(f["wait"]) <= 0.0:
				f["wait"] = 1.0
				if not sold.is_down():
					_emerge(f)
		"stalk":
			f["stalk_t"] = float(f["stalk_t"]) + dt
			if float(f["stalk_t"]) > STALK_MAX:
				f["mode"] = "retreat"
				return
			if seen:  # it freezes while the light is on it
				f["seen_t"] = float(f["seen_t"]) + dt
				f["frozen"] = true
				_face(f, sold.pos)
				return
			f["frozen"] = false
			f["seen_t"] = 0.0
			var dist: float = m.pos.distance_to(sold.pos)
			if dist <= float(d["attack"]["range"]) and s.site.clear_line(m.pos, sold.pos):
				_face(f, sold.pos)
				if float(f["cd"]) <= 0.0:
					f["cd"] = 1.0 / float(d["attack"]["rate"])
					f["bites"] = int(f["bites"]) + 1
					s.events.append({"type": "melee", "pos": m.pos, "foe": f["id"], "kind": "crawler"})
					s.hurt_member(sold, float(d["attack"]["damage"]), m.pos)
					if int(f["bites"]) >= 2:
						f["mode"] = "retreat"
			elif dist <= float(lg["range"]) and float(f["lunge_cd"]) <= 0.0 and s.site.clear_line(m.pos, sold.pos):
				f["lunge"] = float(lg["time"])
				f["lunge_dir"] = (sold.pos - m.pos).normalized()
				f["lunge_cd"] = float(lg["cooldown"])
				s.events.append({"type": "screech", "pos": m.pos})
			else:
				_chase(f, dt, sold.pos)
				if m.path.is_empty():
					_face(f, sold.pos)
		"retreat":
			if seen:
				f["frozen"] = true
				return
			f["frozen"] = false
			var vent := _nearest_vent(m.pos)
			if m.pos.distance_to(vent) < 0.9:
				f["mode"] = "hidden"
				f["hidden"] = true
				f["wait"] = s.rng.randf_range(8.0, 14.0)
				f["bites"] = 0
				s.events.append({"type": "vanish", "pos": m.pos})
				m.pos = vent
				return
			_chase(f, dt, vent)


func _lunge(f: Dictionary, dt: float) -> void:
	var m: CrewMember = f["m"]
	var lg: Dictionary = f["d"]["lunge"]
	var sold: CrewMember = s.soldier
	f["lunge"] = float(f["lunge"]) - dt
	var step: Vector2 = f["lunge_dir"] * float(lg["speed"]) * dt
	if m.fits(s.site.walk, m.pos + step, s.door_passable()):
		m.pos += step
	m.facing = f["lunge_dir"]
	if m.pos.distance_to(sold.pos) <= 1.3:
		f["lunge"] = 0.0
		f["bites"] = 1
		s.events.append({"type": "melee", "pos": m.pos, "foe": f["id"], "kind": "crawler"})
		s.hurt_member(sold, float(lg["damage"]), m.pos)


## The crawler comes out of the vent nearest the soldier that is far enough, near enough and in the dark.
func _emerge(f: Dictionary) -> bool:
	var sc: Dictionary = f["d"]
	var best := Vector2.ZERO
	var bd := INF
	for v in vents:
		var dist: float = v.distance_to(s.soldier.pos)
		if dist >= 7.0 and dist <= float(sc["emerge"]) and dist < bd and not lit(v):
			best = v
			bd = dist
	if bd == INF:
		return false
	var m: CrewMember = f["m"]
	m.pos = best
	f["hidden"] = false
	f["mode"] = "stalk"
	f["stalk_t"] = 0.0
	f["seen_t"] = 0.0
	f["lunge_cd"] = 1.5
	f["repath"] = 0.0
	f["bites"] = 0
	s.events.append({"type": "emerge", "pos": best})
	return true


func _nearest_vent(p: Vector2) -> Vector2:
	var best := p
	var bd := INF
	for v in vents:
		if v.distance_to(p) < bd:
			best = v
			bd = v.distance_to(p)
	return best
