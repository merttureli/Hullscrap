extends RefCounted
## What the player's ship says to the ear, read off its state once per look (audio.gd calls update about ten times a second): somebody
## repairing, a fire burning, a fire put out, a new fire, a crew member hurt, a drone starting a job, a crew member who came aboard, the
## soldier's boots, the drones hovering, a patient in the medbay, a smelter or the fabricator working, a rack restocked, and the reactor's
## load. Pure logic, no nodes, so the rules are tested headless. The first look at a ship only takes the baseline, and so does the first
## after the ship is replaced or loaded (a loaded save brings a new soldier with it, so the crew it holds are not "new aboard").

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const REPAIR_JOBS: Array[String] = ["repair_component", "repair_breach", "repair_belt", "repair_crew"]
const HURT := 1.0  ## hit points lost between two looks that count as hurt
const HAND_FRESH := 0.4  ## seconds a hand-work job (E held) counts as being worked after the last bit of work
const STRIDE := 1.5  ## cells the soldier walks per step of their boots
const TELEPORT := 4.0  ## cells moved between two looks that are a move of the body (a load, a new ship), not a walk

var _ship = null
var _player = null  # the soldier at the last look: another one means a load
var _hp := {}  # crew member -> hp at the last look
var _busy := {}  # drone -> it had a job at the last look
var _fires := 0
var _names := {}  # crew names aboard at the last look
var _at := Vector2.ZERO  # the soldier's position at the last look
var _walked := 0.0  # cells walked since the last step sounded
var _racks := {}  # ammo racks being restocked at the last look


## The name Ada goes by (data/crew.json).
static func ada_name() -> String:
	return str(CrewMember.config()["ada"]["name"])


## Look at `ship` (null = none): {repair (somebody is mending something now), fire (a fire burns), extinguished (fires fewer than last
## look), ignited (fires more than last look), hurt (crew members who lost hit points), beep (drones that started a job), joined (names
## of crew who came aboard), steps (boot steps the soldier took since the last look, at most 2), drones (drones hovering: aboard and not
## broken), healing (a medbay has a patient), smelting and fabricating (that station is working), restocked (racks that finished
## filling), load (the reactor's load, 0 to 1: power used over power made). `jobs` is the ship's Jobs (ShipSim.jobs_of), or null.
func update(ship, jobs = null) -> Dictionary:
	var out := {"repair": false, "fire": false, "extinguished": 0, "ignited": 0, "hurt": 0, "beep": 0, "joined": [], "steps": 0,
		"drones": 0, "healing": false, "smelting": false, "fabricating": false, "restocked": 0, "load": 0.0}
	if ship == null:
		_ship = null
		return out
	var soldier = null
	for m in ship.crew:
		if m.is_player:
			soldier = m
			break
	var first: bool = ship != _ship or soldier != _player
	if first:
		_ship = ship
		_player = soldier
		_hp = {}
		_busy = {}
		_names = {}
	var fires: int = ship.fires.size()
	out["fire"] = fires > 0
	if not first and fires < _fires:
		out["extinguished"] = _fires - fires
	elif not first and fires > _fires:
		out["ignited"] = fires - _fires
	_fires = fires
	var now := {}
	for m in ship.crew:
		now[m.name] = true
		if not first and not _names.has(m.name):
			out["joined"].append(m.name)
		var drone: bool = m.is_drone()
		if drone and not m.is_down():
			out["drones"] += 1
		if not first and _hp.has(m) and not drone and m.hp < float(_hp[m]) - HURT:
			out["hurt"] += 1
		_hp[m] = m.hp
		var job: Dictionary = m.job
		if drone:
			var busy: bool = not job.is_empty()
			if not first and busy and not _busy.get(m, false):
				out["beep"] += 1
			_busy[m] = busy
		if _repairing(ship, m, job):
			out["repair"] = true
	_names = now
	_look_at_the_boots(soldier, first, out)
	_look_at_the_works(ship, jobs, first, out)
	return out


## Is `m` working a repair now: on a repair job with nowhere left to walk (a hand-work job only while E keeps refreshing it)?
func _repairing(ship, m, job: Dictionary) -> bool:
	if job.is_empty() or not str(job.get("type", "")) in REPAIR_JOBS or m.is_down() or m.is_stunned():
		return false
	if bool(job.get("hand", false)):
		return float(ship.clock) - float(job.get("t", -1.0e9)) <= HAND_FRESH
	return m.path.is_empty()


## The soldier's steps: a step each STRIDE cells walked since the last, none for a move of the whole body or while they are down.
func _look_at_the_boots(soldier, first: bool, out: Dictionary) -> void:
	if soldier == null:
		return
	var d: float = soldier.pos.distance_to(_at)
	_at = soldier.pos
	if first or d > TELEPORT or soldier.is_down():
		_walked = 0.0
		return
	_walked += d
	var n := int(_walked / STRIDE)
	_walked -= n * STRIDE
	out["steps"] = mini(n, 2)


## The machines: the medbay's patient, the smelter and the fabricator at work, racks that were being restocked and are not now, the reactor's load.
func _look_at_the_works(ship, jobs, first: bool, out: Dictionary) -> void:
	if jobs != null:
		out["healing"] = not jobs.patients.is_empty()
		var racks: Dictionary = jobs.restocking.duplicate()
		if not first:
			for r in _racks:
				if not racks.has(r):
					out["restocked"] += 1
		_racks = racks
	var cr = ship.get("crafting")
	if cr != null:
		out["smelting"] = not cr.working.is_empty()
		out["fabricating"] = not cr.queue.is_empty() and not cr.paused
	var ps = ship.get("power_state")
	if ps is Dictionary:
		var supply := 0.0
		var used := 0.0
		for n in ps.get("networks", []):
			supply += float(n["supply"])
			used += float(n["used"])
		out["load"] = clampf(used / supply, 0.0, 1.0) if supply > 0.0 else 0.0
