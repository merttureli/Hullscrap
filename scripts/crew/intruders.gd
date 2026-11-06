extends RefCounted
## Boarding robots in a ship's crew sim (docs/DRONES.md section 6). A robot is a CrewMember of a species with `robot: true` (data/packs/drones_2/species.json: hp 40, 60 and 90),
## kept in `ship.intruders` (not in ship.crew: it is no crew, has no bed, counts for no morale, is not saved). It fights the crew in reach (species `intruder.dps`, a
## melee a second); otherwise it walks to the nearest powered system and wrecks it (`sabotage_dps` of the part's hp a second; at 0 the part is disabled and a crew member
## repairs it), then the next; the shock robot (`intruder.ion`) also ion-locks the part it works on. The crew answer with the "intruder" response (Jobs.tick calls
## `respond`): a crew member in reach fights, one within `intruder.chase` cells goes, a posted one only fights what comes to it, and the player's soldier fights what is in
## reach and goes for what is within `soldier_chase`. A dead robot leaves debris (ship.intruder_dead) and is gone: it never goes home. Data: data/crew.json `intruder`.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Fire = preload("res://scripts/sim/fire.gd")

const NO_SYSTEM := ["", "wall", "cable"]  ## families a robot does not bother with
const LOOK := {"suit": "#c0392b", "hair": "#3a1410", "tool": "#e8a030"}  ## the owner tint (theirs: red)


static func cfg() -> Dictionary:
	return CrewMember.config().get("intruder", {})


## A new robot of `species` stands in the room cell near `near` (cell coordinates) of `ship`. Returns it (null when there is no room to stand).
static func spawn(ship, species: String, near: Vector2, _rng = null):
	var Jobs = load("res://scripts/crew/jobs.gd")
	var spot: Vector2i = Jobs._free_spot(ship.grid, near, [])
	if spot == Pathfinder.NO_CELL:
		return null
	var n: int = ship.intruders.size() + ship.intruder_dead.size() + 1
	var m = CrewMember.new("%s %d" % [str(cfg().get("robot_label", "boarding robot")).capitalize(), n], Pathfinder.centre_of(spot), species)
	m.look = LOOK.duplicate()
	ship.intruders.append(m)
	return m


## The spec numbers of robot `m` ({dps, reach, sabotage_dps, ion}).
static func spec(m) -> Dictionary:
	return CrewMember.species_def(m.species).get("intruder", {"dps": 6.0, "reach": 1.6, "sabotage_dps": 4.0})


static func alive(ship) -> Array:
	return ship.intruders.filter(func(r): return not r.is_down())


## Straight-line distance in cells between two bodies, and whether they share a room (or are touching).
static func _near(ship, a, b, reach: float) -> bool:
	if a.pos.distance_to(b.pos) > reach:
		return false
	var ra: int = ship.atmosphere.room_at(a.cell())
	return ra == ship.atmosphere.room_at(b.cell()) or a.pos.distance_to(b.pos) < 1.3


## One tick of every robot of `ship`: the dead are removed, the rest fight or sabotage. `jobs` is the ship's Jobs (for stand spots).
static func tick(ship, jobs, dt: float) -> void:
	if ship.intruders.is_empty():
		return
	for r in ship.intruders.duplicate():
		if r.is_down():
			ship.intruders.erase(r)
			ship.intruder_dead.append({"pos": r.pos, "species": r.species, "t": ship.clock})
			ship.log_event("A boarding robot was destroyed")
			continue
		_think(ship, jobs, r, dt)
		r.step(dt)
	while ship.intruder_dead.size() > 6:
		ship.intruder_dead.pop_front()


static func _think(ship, jobs, r, dt: float) -> void:
	var sp := spec(r)
	var reach := float(sp.get("reach", 1.6))
	var foe = null
	var best := INF
	for m in ship.crew:
		if m.is_down() or m.is_drone():
			continue
		var d: float = r.pos.distance_to(m.pos)
		if d < best and _near(ship, r, m, reach):
			best = d
			foe = m
	if foe != null:  # a fight: it stands and hits
		r.path.clear()
		r.facing = (foe.pos - r.pos).normalized()
		r.job = {"type": "attack", "t": ship.clock}
		var was: bool = foe.is_down()
		foe.hurt(float(sp.get("dps", 6.0)) * float(TraitSet.of(foe)["damage_taken"]["melee"]) * dt)
		if foe.is_down() and not was:
			foe.job = {}
			foe.path.clear()
			ship.log_event("%s is down" % foe.name)
		return
	var sab = r.get_meta("sab") if r.has_meta("sab") else null
	if sab != null and (not ship.components.instances.has(sab) or ship.components.instances[sab]["status"] == "disabled"):
		sab = null
		r.set_meta("sab", null)
	if sab == null:
		sab = _pick_system(ship, r)
		r.set_meta("sab", sab)
		r.path.clear()
	if sab == null:
		r.job = {}
		return
	var inst: Dictionary = ship.components.instances[sab]
	var job := {"cells": inst["cells"], "type": "sabotage"}
	if jobs.in_reach(r, job):
		r.path.clear()
		r.job = {"type": "attack", "t": ship.clock}
		r.facing = (Pathfinder.centre_of(inst["cells"][0], 1) - r.pos).normalized()
		_sabotage(ship, sab, float(sp.get("sabotage_dps", 4.0)) * dt, bool(sp.get("ion", false)))
	elif r.path.is_empty():
		r.job = {}
		var ok := false
		for spot in jobs.stand_spots(ship, job):
			if r.go_to(ship.grid, spot):
				ok = true
				break
		if not ok:  # no way there: forget this one for now
			var skip: Array = r.get_meta("skip") if r.has_meta("skip") else []
			skip.append(sab)
			r.set_meta("skip", skip)
			r.set_meta("sab", null)


## The nearest powered, working system of `ship` to robot `r` that it has not given up on.
static func _pick_system(ship, r):
	var powered: Dictionary = ship.power_state.get("powered", {})
	var skip: Array = r.get_meta("skip") if r.has_meta("skip") else []
	var best = null
	var best_d := INF
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if skip.has(uid) or inst["status"] == "disabled" or not powered.get(uid, false):
			continue
		if str(ship.components.def(inst["id"]).get("family", "")) in NO_SYSTEM:
			continue
		var d: float = r.pos.distance_squared_to(Pathfinder.centre_of(inst["anchor"], 1))
		if d < best_d:
			best_d = d
			best = uid
	return best


## The robot damages part `uid`; at 0 hp it is disabled (and a crew member repairs it). `ion`: the part is also locked for a few seconds.
static func _sabotage(ship, uid: int, hp: float, ion: bool) -> void:
	var inst: Dictionary = ship.components.instances[uid]
	var name := str(ship.components.def(inst["id"]).get("name", inst["id"]))
	var cur := float(inst.get("hp", ship.components.def(inst["id"]).get("hp", 4.0)))
	if ion:
		Abilities.ion_lock(ship, uid)
	inst["hp"] = maxf(cur - hp, 0.0)
	ship.hit_at[uid] = ship.clock
	if cur > 0.0 and float(inst["hp"]) <= 0.0:
		inst["status"] = "disabled"
		ship.mark_dirty()
		ship.log_event("%s was wrecked by a boarding robot" % name)


# --- the crew's answer ---------------------------------------------------------------------------

## The intruder response for crew member `m` (the soldier too): true when they are busy with one (fighting or on the way), so they take no other job this tick.
static func respond(ship, jobs, m, dt: float) -> bool:
	var c := cfg()
	var foe = null
	var best := INF
	for r in ship.intruders:
		if r.is_down():
			continue
		var d: float = m.pos.distance_to(r.pos)
		if d < best:
			best = d
			foe = r
	if foe == null or m.is_down():
		if str(m.job.get("type", "")) == "intruder":
			m.job = {}
			m.path.clear()
		return false
	var soldier: bool = m.is_player
	var reach := float(spec(foe).get("reach", 1.6))
	if _near(ship, m, foe, reach):
		m.path.clear()
		m.facing = (foe.pos - m.pos).normalized()
		m.job = {"key": "intruder", "type": "intruder", "label": str(CrewMember.config().get("labels", {}).get("intruder", "fighting")), "t": ship.clock}
		var dps := float(c.get("soldier_dps", 14.0) if soldier else c.get("crew_dps", 7.0))
		foe.hurt(dps * float(TraitSet.of(foe)["damage_taken"]["melee"]) * dt)
		return true
	var chase := float(c.get("soldier_chase", 14) if soldier else c.get("chase", 9))
	if m.post >= 0 and not soldier:
		return false
	if best <= chase and (not soldier or m.path.is_empty()):
		if m.path.is_empty() or int(ship.clock * 2.0) != (int(m.get_meta("chase_t")) if m.has_meta("chase_t") else -1):
			m.set_meta("chase_t", int(ship.clock * 2.0))
			m.go_to(ship.grid, foe.anchor())
		m.job = {"key": "intruder", "type": "intruder", "label": str(CrewMember.config().get("labels", {}).get("intruder", "fighting")), "t": ship.clock}
		if soldier:
			m.step(dt)
		return not soldier
	return false
