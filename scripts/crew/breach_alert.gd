extends RefCounted
## The breach alert (playtest 2, K2). Watches the player's ship: when the pressure of a room falls under crew.json breach.pressure
## because the room is open to space (a breach), and there are crew in it or on the way to it, a prompt is raised: "Breach: <room>
## [R] Repair  [V] Evacuate". For the first prompt in the queue the game runs at breach.time_scale (time_scale()) for up to
## breach.prompt_s REAL seconds, or until the player answers. Repair, or no answer, changes nothing: the crew go and repair as
## ever. Evacuate gives the room up (Evacuate.abandon). At most one slow-down every breach.gap_s real seconds: a prompt that comes
## sooner waits its turn behind the one on show and does not slow time again. breach.slow_down false turns the slow-down off
## (the prompts stay). Time here is REAL seconds: the caller (breach_prompt.gd) passes the unscaled frame time and applies
## time_scale() to Engine.time_scale, so this stays plain logic that tests can drive. A room is alerted once per breach: it is
## armed again when its pressure climbs back over the limit.

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Evacuate = preload("res://scripts/crew/evacuate.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Rooms = preload("res://scripts/sim/rooms.gd")

var queue: Array = []  ## prompts waiting, the first is on show: {key: room key cell, name, left (real seconds), slow (bool)}
var since_slow := 1.0e9  ## real seconds since the last slow-down began
var slowed_total := 0  ## how many slow-downs there have been (for tests)
var _armed := {}  # room key cell -> true while its pressure is over the limit
var _shown := false  # the first prompt has had its slow-down decided


static func cfg() -> Dictionary:
	return CrewMember.config().get("breach", {})


## The prompt on show, {} when none.
func current() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


## The speed the game should run at: breach.time_scale while the prompt on show slows time, else 1.
func time_scale() -> float:
	var c := current()
	return float(cfg().get("time_scale", 0.25)) if not c.is_empty() and bool(c["slow"]) else 1.0


## Advance by `real_dt` real seconds on `ship` (the player's). `paused`: the world stands still (build mode), so nothing is
## raised and the clock of the prompt waits.
func update(ship, real_dt: float, paused := false) -> void:
	if paused or ship == null:
		return
	since_slow += real_dt
	if not queue.is_empty():
		queue[0]["left"] = float(queue[0]["left"]) - real_dt
		if float(queue[0]["left"]) <= 0.0:
			_next()  # no answer is Repair
	_scan(ship)
	if not queue.is_empty() and not _shown:
		_show()


## The player answers the prompt on show: "repair" or "evacuate". Returns what to tell the player ("" when there is no prompt).
func respond(ship, choice: String) -> String:
	var c := current()
	if c.is_empty():
		return ""
	var line := ""
	if choice == "evacuate":
		var id: int = ship.atmosphere.room_at(c["key"])
		var who := Evacuate.abandon(ship, id) if id >= 0 else []
		line = "%s abandoned%s" % [c["name"], ": " + ", ".join(who) + " walk out" if not who.is_empty() else ""]
		ship.log_event(line)
	else:
		line = "Crew sealing the breach: %s" % c["name"]
	_next()
	return line


## Forget everything (a new ship, a loaded game).
func reset() -> void:
	queue.clear()
	_armed.clear()
	_shown = false
	since_slow = 1.0e9


func _next() -> void:
	queue.pop_front()
	_shown = false
	if not queue.is_empty():
		_show()


## The first prompt of the queue comes on show: it slows time if the last slow-down is over `gap_s` ago.
func _show() -> void:
	_shown = true
	var c: Dictionary = queue[0]
	c["left"] = float(cfg().get("prompt_s", 3.0))
	c["slow"] = bool(cfg().get("slow_down", true)) and since_slow >= float(cfg().get("gap_s", 10.0))
	if c["slow"]:
		since_slow = 0.0
		slowed_total += 1


## Look at the rooms: raise a prompt for each one that just fell under the limit with crew in it or on the way.
func _scan(ship) -> void:
	var at = ship.atmosphere
	var limit := float(cfg().get("pressure", 0.6))
	var seen := {}
	for r in at.rooms:
		if r["cells"].is_empty():
			continue
		var key := Rooms.key_of(r)
		seen[key] = true
		if bool(r.get("abandoned", false)):
			_armed.erase(key)
			continue
		var p: float = at.pressure_of(int(r["id"]))
		if p >= limit:
			_armed[key] = true
		elif _armed.has(key) and not bool(r["sealed"]) and _crew_in_or_heading(ship, int(r["id"])):
			_armed.erase(key)
			if not queue.any(func(q): return q["key"] == key):
				queue.append({"key": key, "name": Fire.room_name(ship, int(r["id"])), "left": 0.0, "slow": false})
	for key in _armed.keys():
		if not seen.has(key):
			_armed.erase(key)


## Is anybody (the soldier too, but no drone) in room `room_id`, or on the way to it (their job's spot, or the end of their path)?
func _crew_in_or_heading(ship, room_id: int) -> bool:
	var at = ship.atmosphere
	for m in ship.crew:
		if m.is_drone():
			continue
		if at.room_at(m.cell()) == room_id:
			return true
		var to: Vector2i = m.path.back() if not m.path.is_empty() else (m.job["spot"] if not m.job.is_empty() and m.job.has("spot") else Vector2i(-1, -1))
		if to != Vector2i(-1, -1) and Evacuate.room_at_anchor(ship, to, m.body_size) == room_id:
			return true
	return false
