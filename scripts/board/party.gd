extends RefCounted
## The crew who come along on a boarding visit (docs/BOARDING.md, stage B2). Up to `party_max` unposted crew follow the soldier, shoot (or swing) with
## their species' sidearm and revive whoever is down. Pure logic, static functions on the session (boarding.gd), whose `party` array holds them:
## {m (a copy of the crew member: pos, hp, path), src (the ship's own CrewMember, written back on leaving), gun (arms.gd), cd, repath, revive (seconds
## spent reviving someone), moving, rest (their spare rounds: see give_ammo)}. A crew member who is down when the soldier leaves is lost (boarding.gd leave()).
## - A follower whose weapon has a magazine shoots from rounds of their own: a COPY of the soldier's spare rounds when they come aboard (never fewer than
##   boarding.json combat.follower_ammo_min), nothing taken from the hold. They reload from them, and with none left they do not shoot (a melee follower swings).
##   What is left is gone when the visit ends.

const Arms = preload("res://scripts/board/arms.gd")
const Site = preload("res://scripts/board/site.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Kit = preload("res://scripts/board/kit.gd")
const Mods = preload("res://scripts/board/mods.gd")
const Bolts = preload("res://scripts/board/bolts.gd")
const Air = preload("res://scripts/board/air.gd")

const ERR := 0.12  ## radians of error in a follower's shot
const SEE := 14.0  ## cells a follower looks for something to shoot
const MELEE_GO := 8.0  ## cells within which a melee follower goes for a foe


## The crew the soldier may take: not the soldier, not a drone, not posted to a part, and up.
static func eligible(ship) -> Array:
	var out := []
	if ship == null:
		return out
	for m in ship.crew:
		if not m.is_player and not m.is_drone() and m.post < 0 and not m.is_down():
			out.append(m)
	return out


## Take the crew named in `names` (at most party_max, in the order of the ship's crew) aboard; returns the party. They stand by the airlock.
static func join(s, names: Array) -> Array:
	var out := []
	var cap := int(Arms.cfg()["party_max"])
	var spots: Array = s.site.free_anchors(s.site.airlock["room"])
	spots = spots.filter(func(a): return (Vector2(a) + Vector2.ONE).distance_to(s.soldier.pos) >= 2.3)
	spots.sort_custom(func(a, b): return (Vector2(a) + Vector2.ONE).distance_to(s.soldier.pos) < (Vector2(b) + Vector2.ONE).distance_to(s.soldier.pos))
	for src in eligible(s.ship):
		if out.size() >= cap:
			break
		if not names.has(src.name):
			continue
		var m = CrewMember.from_dict(src.to_dict())
		if m == null:
			continue
		m.is_player = false
		m.job = {}
		m.path.clear()
		if spots.size() > out.size():
			m.pos = Pathfinder.centre_of(spots[out.size()], m.body_size)
		else:
			m.pos = s.soldier.pos
		var g = Arms.make_gun(str(Kit.weapons_of(m)[0]), false, Kit.gear_num(m, "mag", 1.0))  # (a follower fights with the first weapon of their kit)
		if g == null:
			g = Arms.make_gun("service_pistol", false)
		var p := {"m": m, "src": src, "gun": g, "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false}
		give_ammo(p, s.reserve())
		out.append(p)
	return out


## Load the follower's weapon and give them a copy of `spare` rounds (at least follower_ammo_min) to reload from; a weapon with no magazine needs none.
static func give_ammo(p: Dictionary, spare: int) -> void:
	var g: Dictionary = p["gun"]
	p["rest"] = 0
	p["out"] = false
	if not Arms.has_mag(g):
		return
	var total := maxi(spare, int(Arms.cfg()["follower_ammo_min"]))
	g["mag"] = mini(int(g["w"]["mag"]), total)
	p["rest"] = total - int(g["mag"])


## The rounds a follower has in all (magazine and spare), -1 for a weapon with no magazine.
static func rounds(p: Dictionary) -> int:
	return int(p["gun"]["mag"]) + int(p.get("rest", 0)) if Arms.has_mag(p["gun"]) else -1


## Magazines a follower has left, the one in the weapon counting as a fraction (1.0 = one full magazine): the card turns amber at 1 or less.
static func mags_left(p: Dictionary) -> float:
	return float(rounds(p)) / maxf(float(p["gun"]["w"]["mag"]), 1.0)


## A person met aboard (people.gd `npc_follow`) walks with the soldier until he leaves: a follower with no crew member behind it (`src` is null, `temp` true),
## a sidearm of its own (`people.follow.gun`) and `people.follow.hp` health. Added to the party; returns the entry.
static func add_temp(s, m: CrewMember) -> Dictionary:
	var pc: Dictionary = Site.config()["people"]["follow"]
	var g = Arms.make_gun(str(pc["gun"]), false)
	m.max_hp = float(pc["hp"])
	m.hp = minf(m.hp, m.max_hp)
	m.is_player = false
	m.job = {}
	m.path.clear()
	var p := {"m": m, "src": null, "temp": true, "gun": g, "cd": 0.0, "repath": 0.0, "revive": 0.0, "moving": false}
	give_ammo(p, s.reserve())
	s.party.append(p)
	return p


## The crew of the party who are down.
static func downed(s) -> Array:
	return s.party.filter(func(p): return p["m"].is_down())


## `dt` seconds pass for every follower.
static func tick(s, dt: float) -> void:
	for p in s.party:
		var m: CrewMember = p["m"]
		var prev: Vector2 = m.pos
		p["cd"] = maxf(float(p["cd"]) - dt, 0.0)
		if Arms.has_mag(p["gun"]):
			Arms.tick(p["gun"], dt, func(n: int) -> int:
				var k := mini(maxi(n, 0), int(p["rest"]))
				p["rest"] = int(p["rest"]) - k
				return k)
		if m.is_down():
			m.path.clear()
			p["revive"] = 0.0
		elif int(p.get("bed", -1)) < 0:  # (one lying on a bed rests there: beds.gd)
			_act(s, p, dt)
		p["moving"] = m.pos.distance_to(prev) > 0.002


static func _act(s, p: Dictionary, dt: float) -> void:
	var m: CrewMember = p["m"]
	var w: Dictionary = p["gun"]["w"]
	var c := Arms.cfg()
	var foe := _target(s, m, w)
	if not foe.is_empty():
		p["revive"] = 0.0
		var off: Vector2 = foe["pos"] - m.pos
		m.facing = off.normalized() if off.length() > 0.01 else m.facing
		if bool(w["melee"]):
			var reach := float(w["range"]) + 0.9
			if off.length() > reach:
				_go(s, p, foe["pos"], dt)
			elif float(p["cd"]) <= 0.0:
				p["cd"] = 1.0 / float(w["rate"])
				s.events.append({"type": "swing", "from": m.pos, "dir": off.angle(), "reach": reach, "who": "ally", "look": Bolts.look(str(w["id"]), Mods.bolt_size(m))})
				s.foes.hurt(foe["ref"], float(w["damage"]) * Mods.damage_mult(m), foe["pos"])
				s.foes.noise(m.pos, float(c["noise_swing"]))
		else:
			var g: Dictionary = p["gun"]
			if Arms.has_mag(g) and int(g["mag"]) <= 0 and float(g["reload"]) <= 0.0:  # an empty magazine: reload from their own rounds, or they are out
				if not Arms.start_reload(g, int(p["rest"])) and not bool(p["out"]):
					p["out"] = true
					s.events.append({"type": "line", "text": "%s is out of rounds." % m.name, "pos": m.pos})
			if float(p["cd"]) <= 0.0 and float(g["reload"]) <= 0.0 and (not Arms.has_mag(g) or int(g["mag"]) > 0):
				p["cd"] = 1.0 / float(w["rate"])
				if Arms.has_mag(g):
					g["mag"] = int(g["mag"]) - 1
				s.shoot(m, "ally", m.pos + Vector2.from_angle(off.angle()) * 0.9, off.angle() + s.rng.randf_range(-ERR, ERR), w, s.foes.bodies())
				s.foes.noise(m.pos, float(c["noise_gun"]))
			if m.pos.distance_to(s.soldier.pos) > float(c["follow_far"]) * 1.8:
				_go(s, p, s.soldier.pos, dt)  # not too far from him to shoot
		return
	var down := _nearest_down(s, p)
	if not down.is_empty():
		if m.pos.distance_to(down["m"].pos) > 1.9:
			p["revive"] = 0.0
			_go(s, p, down["m"].pos, dt)
		else:
			p["revive"] = float(p["revive"]) + dt
			if float(p["revive"]) >= float(c["revive_s"]):
				p["revive"] = 0.0
				s.revive_member(down["m"])
		return
	p["revive"] = 0.0
	var away: float = m.pos.distance_to(s.soldier.pos)
	if away > float(c["follow_far"]) or (away > float(c["follow_near"]) and not m.path.is_empty()):
		_go(s, p, s.soldier.pos, dt)
	else:
		m.path.clear()


## The nearest foe a follower can shoot (across a clear line, within its weapon's reach) or, with a melee weapon, within MELEE_GO cells: {pos, ref} or {}.
static func _target(s, m: CrewMember, w: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	var reach := MELEE_GO if bool(w["melee"]) else minf(float(w["range"]), SEE)
	for b in s.foes.bodies():
		var d: float = m.pos.distance_to(b["pos"])
		if d <= reach and d < bd and s.site.clear_line(m.pos, b["pos"]):
			best = b
			bd = d
	return best


## The nearest party member (not `p`) who is down, within 14 cells: the follower itself, or the soldier's party only.
static func _nearest_down(s, p: Dictionary) -> Dictionary:
	var best := {}
	var bd := 14.0
	for q in s.party:
		if q != p and q["m"].is_down():
			var d: float = p["m"].pos.distance_to(q["m"].pos)
			if d < bd:
				best = q
				bd = d
	return best


static func _go(s, p: Dictionary, to: Vector2, dt: float) -> void:
	p["repath"] = float(p["repath"]) - dt
	if float(p["repath"]) <= 0.0:
		s.foes.path_to(p, to)
		p["repath"] = 0.5
	if Air.wait(s, p):  # no sealed suit: it waits at the door of an airless room
		return
	p["m"].step(dt)
