extends RefCounted
## What the player's ship says to the ear, read off its state once per look (audio.gd calls update about ten times a second): somebody
## repairing, a fire burning, a fire put out, a crew member hurt, a drone starting a job, a crew member who came aboard. Pure logic, no
## nodes, so the rules are tested headless. The first look at a ship only takes the baseline, and so does the first after the ship is
## replaced or loaded (a loaded save brings a new soldier with it, so the crew it holds are not "new aboard").

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const REPAIR_JOBS: Array[String] = ["repair_component", "repair_breach", "repair_belt", "repair_crew"]
const HURT := 1.0  ## hit points lost between two looks that count as hurt
const HAND_FRESH := 0.4  ## seconds a hand-work job (E held) counts as being worked after the last bit of work

var _ship = null
var _player = null  # the soldier at the last look: another one means a load
var _hp := {}  # crew member -> hp at the last look
var _busy := {}  # drone -> it had a job at the last look
var _fires := 0
var _names := {}  # crew names aboard at the last look


## The name Ada goes by (data/crew.json).
static func ada_name() -> String:
	return str(CrewMember.config()["ada"]["name"])


## Look at `ship` (null = none): {repair (somebody is mending something now), fire (a fire burns), extinguished (fires fewer than last
## look), hurt (crew members who lost hit points), beep (drones that started a job), joined (names of crew who came aboard)}.
func update(ship) -> Dictionary:
	var out := {"repair": false, "fire": false, "extinguished": 0, "hurt": 0, "beep": 0, "joined": []}
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
	_fires = fires
	var now := {}
	for m in ship.crew:
		now[m.name] = true
		if not first and not _names.has(m.name):
			out["joined"].append(m.name)
		var drone: bool = m.is_drone()
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
	return out


## Is `m` working a repair now: on a repair job with nowhere left to walk (a hand-work job only while E keeps refreshing it)?
func _repairing(ship, m, job: Dictionary) -> bool:
	if job.is_empty() or not str(job.get("type", "")) in REPAIR_JOBS or m.is_down() or m.is_stunned():
		return false
	if bool(job.get("hand", false)):
		return float(ship.clock) - float(job.get("t", -1.0e9)) <= HAND_FRESH
	return m.path.is_empty()
