extends RefCounted
## Abilities of components (docs/CONTENT.md section 5), read from `abilities` in data/components.json.
## An ability is {id, name, type: active|passive, key: engine|shield|utility, duration, cooldown,
## effects, side_effects, operator_needs}. An active one is triggered, runs for `duration` seconds,
## then rests for `cooldown` seconds (counted from the end of the effect). A passive one runs for as
## long as its part works.
## - effects: stat_mult {thrust, power} (a factor on that part's own figure), shield_layer (extra
##   layers), charge_mult (a factor on every weapon's cooldown), evasion_add.
## - side_effects, per second while it runs: drain_o2 (fraction of the part's room air lost), heat,
##   power_spike (extra power draw, taken in the power solve), fire_risk (chance), self_damage (hp).
## - operator_needs: traits the crew member manning the part (ship.manned) must have; "a|b" means
##   either. Traits come from the crew member's species, data/crew.json and gear (CrewMember.traits()).
## State lives on the ship, in `ship.ability_state` (not saved): `slots` "uid:id" -> {uid, id, active,
## cd} (seconds left) and `rev`, which counts starts and ends so the power solve, the arena's thrust
## and its shield layers know to refresh. Everything here is static. tick() is driven by ShipSim
## outside a fight and by the arena inside one, never both. Deterministic: the only roll (fire_risk)
## comes from the rng the caller passes.

const Fire = preload("res://scripts/sim/fire.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")

const KEYS: Array[String] = ["engine", "shield", "utility"]  ## the combat keys: Shift, Space and Q
const EPS := 1e-9


static func fresh_state() -> Dictionary:
	return {"rev": 0, "slots": {}}


## How many starts and ends this ship's abilities have had.
static func rev(ship) -> int:
	return int(ship.ability_state["rev"])


static func slot_key(uid: int, ability_id: String) -> String:
	return "%d:%s" % [uid, ability_id]


## Ability `ability_id` ("" for the first) of part `uid`: its data entry, or {} when there is none.
static func find(ship, uid: int, ability_id := "") -> Dictionary:
	if not ship.components.instances.has(uid):
		return {}
	for a in ship.components.def(ship.components.instances[uid]["id"]).get("abilities", []):
		if ability_id == "" or a.get("id", "") == ability_id:
			return a
	return {}


## Every active ability of the ship as a slot for the UI, in key order and then part order:
## {uid, id, slot, key, name, part, ability}.
static func slots(ship) -> Array:
	var out := []
	for uid in _uids(ship):
		var inst: Dictionary = ship.components.instances[uid]
		var def: Dictionary = ship.components.def(inst["id"])
		for a in def.get("abilities", []):
			if a.get("type", "active") == "active":
				out.append({"uid": uid, "id": str(a["id"]), "slot": slot_key(uid, str(a["id"])), "key": str(a.get("key", "utility")),
					"name": str(a.get("name", a["id"])), "part": str(def.get("name", inst["id"])), "ability": a})
	out.sort_custom(func(x, y):
		var kx := KEYS.find(x["key"])
		var ky := KEYS.find(y["key"])
		return kx < ky or (kx == ky and (x["uid"] < y["uid"] or (x["uid"] == y["uid"] and x["id"] < y["id"]))))
	return out


# --- state ----------------------------------------------------------------------------------------

## Seconds the ability still runs (0 when it is not running).
static func active_left(ship, uid: int, ability_id: String) -> float:
	return float(_state(ship, uid, ability_id).get("active", 0.0))


## Seconds until the ability may be triggered again (0 when ready or running).
static func cooldown_left(ship, uid: int, ability_id: String) -> float:
	return float(_state(ship, uid, ability_id).get("cd", 0.0))


## The longest time left among the running abilities with key `key` (0 when none runs).
static func key_active_left(ship, key: String) -> float:
	var best := 0.0
	for s in slots(ship):
		if s["key"] == key:
			best = maxf(best, active_left(ship, s["uid"], s["id"]))
	return best


## 0 when an ability with key `key` is ready (or none exists), else the shortest cooldown left of those resting.
static func key_cooldown_left(ship, key: String) -> float:
	var best := INF
	for s in slots(ship):
		if s["key"] == key and active_left(ship, s["uid"], s["id"]) <= 0.0:
			best = minf(best, cooldown_left(ship, s["uid"], s["id"]))
	return 0.0 if best == INF else best


# --- triggering -----------------------------------------------------------------------------------

## "" when ability `ability_id` ("" for the first) of part `uid` can be triggered now, else why not:
## "no such ability", "passive", the part's status (disabled, overheated, malfunction), "unpowered",
## "already active", "on cooldown 12 s", or what the operator lacks.
static func can_trigger(ship, uid: int, ability_id := "") -> String:
	var a := find(ship, uid, ability_id)
	if a.is_empty():
		return "no such ability"
	if a.get("type", "active") != "active":
		return "passive"
	var inst: Dictionary = ship.components.instances[uid]
	if inst["status"] != "ok":
		return str(inst["status"])
	ship.refresh()
	if not ship.power_state.get("powered", {}).get(uid, false):
		return "unpowered"
	var id := str(a["id"])
	if active_left(ship, uid, id) > 0.0:
		return "already active"
	var cd := cooldown_left(ship, uid, id)
	if cd > 0.0:
		return "on cooldown %d s" % ceili(cd - 1e-6)
	return _operator_reason(ship, uid, a)


## Start the ability. "" when it started, else the reason from can_trigger.
static func trigger(ship, uid: int, ability_id := "") -> String:
	var why := can_trigger(ship, uid, ability_id)
	if why != "":
		return why
	var a := find(ship, uid, ability_id)
	var s := _slot(ship, uid, str(a["id"]))
	s["active"] = float(a.get("duration", 0.0))
	ship.ability_state["rev"] += 1
	ship.log_event("%s on" % a.get("name", a["id"]))
	return ""


## Advance every ability of `ship` by `dt` seconds: running ones apply their side effects and
## count down (then rest for their cooldown), resting ones cool down, and passive ones apply their
## side effects while their part works. A running ability stops when its part goes out of action.
## `rng`: for fire_risk; without one no fire is ever started.
static func tick(ship, dt: float, rng: RandomNumberGenerator = null) -> void:
	if dt <= 0.0:
		return
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var table: Dictionary = ship.ability_state["slots"]
	var keys: Array = table.keys()
	keys.sort()
	for k in keys:
		var s: Dictionary = table[k]
		var a := find(ship, s["uid"], s["id"])
		if a.is_empty():  # the part was taken away
			table.erase(k)
			ship.ability_state["rev"] += 1
			continue
		if s["active"] > 0.0:
			var inst: Dictionary = ship.components.instances[s["uid"]]
			if inst["status"] != "ok" or not powered.get(s["uid"], false):
				_end(ship, a, s)
				continue
			_side_effects(ship, s["uid"], a, dt, rng)
			s["active"] -= dt
			if s["active"] <= EPS:
				_end(ship, a, s)
		elif s["cd"] > 0.0:
			s["cd"] = maxf(s["cd"] - dt, 0.0)
		if s["active"] <= 0.0 and s["cd"] <= 0.0:
			table.erase(k)
	for uid in _uids(ship):
		var inst: Dictionary = ship.components.instances[uid]
		if inst["status"] != "ok" or not powered.get(uid, false):
			continue
		for a in ship.components.def(inst["id"]).get("abilities", []):
			if a.get("type", "active") == "passive":
				_side_effects(ship, uid, a, dt, rng)


# --- what the running abilities change ------------------------------------------------------------

## The abilities in effect now: [{uid, ability}]. Active ones that are running, and the passive ones
## of working parts (powered too when `need_power`; the power solve itself passes false).
static func running(ship, need_power := true) -> Array:
	var out := []
	var table: Dictionary = ship.ability_state["slots"]
	var keys: Array = table.keys()
	keys.sort()
	for k in keys:
		var s: Dictionary = table[k]
		if s["active"] > 0.0:
			var a := find(ship, s["uid"], s["id"])
			if not a.is_empty():
				out.append({"uid": s["uid"], "ability": a})
	var powered: Dictionary = ship.power_state.get("powered", {})
	for uid in _uids(ship):
		var inst: Dictionary = ship.components.instances[uid]
		if inst["status"] != "ok" or (need_power and not powered.get(uid, false)):
			continue
		for a in ship.components.def(inst["id"]).get("abilities", []):
			if a.get("type", "active") == "passive":
				out.append({"uid": uid, "ability": a})
	return out


## part uid -> the factor `stat_mult` gives its stat `stat` ("thrust", "power"); parts without one are absent.
static func stat_mults(ship, stat: String, need_power := true) -> Dictionary:
	var out := {}
	for r in running(ship, need_power):
		var m = r["ability"].get("effects", {}).get("stat_mult", {})
		if m is Dictionary and m.has(stat):
			out[r["uid"]] = float(out.get(r["uid"], 1.0)) * float(m[stat])
	return out


## part uid -> thrust factor, for Flight.thrust_of's `boost`.
static func thrust_boost(ship) -> Dictionary:
	return stat_mults(ship, "thrust")


## What the power solve needs: {mult: part uid -> factor on its power figure, extra: part uid -> power_spike draw}.
static func power_mods(ship) -> Dictionary:
	var extra := {}
	for r in running(ship, false):
		for s in r["ability"].get("side_effects", []):
			if s.get("type", "") == "power_spike":
				extra[r["uid"]] = float(extra.get(r["uid"], 0.0)) + float(s.get("rate", 0.0))
	return {"mult": stat_mults(ship, "power", false), "extra": extra}


## Extra shield layers the running abilities give.
static func extra_layers(ship) -> int:
	var n := 0
	for r in running(ship):
		n += int(r["ability"].get("effects", {}).get("shield_layer", 0))
	return n


## The factor on every weapon's cooldown (below 1 is faster).
static func charge_mult(ship) -> float:
	var m := 1.0
	for r in running(ship):
		m *= float(r["ability"].get("effects", {}).get("charge_mult", 1.0))
	return m


## Evasion the running abilities add. Nothing in the arena dodges yet (Jobs.evasion_bonus has no reader either).
static func evasion_add(ship) -> float:
	var v := 0.0
	for r in running(ship):
		v += float(r["ability"].get("effects", {}).get("evasion_add", 0.0))
	return v


## The HUD line for the abilities running now ("" when none): "Abilities: Afterburn 5 s, Overcharge 2 s".
static func hud_line(ship) -> String:
	var parts: Array[String] = []
	for s in slots(ship):
		var left := active_left(ship, s["uid"], s["id"])
		if left > 0.0:
			parts.append("%s %d s" % [s["name"], ceili(left - 1e-6)])
	return "Abilities: " + ", ".join(parts) if not parts.is_empty() else ""


# --- operators ------------------------------------------------------------------------------------

## The crew member manning part `uid` (ship.manned) who is up and about, or null.
static func operator_of(ship, uid: int):
	var who = ship.manned.get(uid)
	if who == null:
		return null
	for m in ship.crew:
		if m.name == who and not m.is_down():
			return m
	return null


## The traits of a crew member: their species', their own (data/crew.json `traits`, by name) and
## those of worn gear, merged (CrewMember.traits()); [] when they have none.
static func traits_of(member) -> Array:
	return member.traits()


## Does `member` have, for every entry of `needs`, at least one of its traits ("a|b" is either)?
static func meets(member, needs: Array) -> bool:
	var have := traits_of(member)
	for need in needs:
		var ok := false
		for alt in str(need).split("|"):
			ok = ok or have.has(alt.strip_edges())
		if not ok:
			return false
	return true


static func _operator_reason(ship, uid: int, a: Dictionary) -> String:
	var needs: Array = a.get("operator_needs", [])
	if needs.is_empty():
		return ""
	var who = operator_of(ship, uid)
	if who != null and meets(who, needs):
		return ""
	var parts := PackedStringArray()
	for need in needs:
		parts.append(" or ".join(str(need).split("|")))
	var family := str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "part"))
	return "needs a crew member with %s at the %s" % [" and ".join(parts), family]


# --- internals ------------------------------------------------------------------------------------

static func _uids(ship) -> Array:
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	return uids


## The state of a slot, read only ({} when it never ran).
static func _state(ship, uid: int, ability_id: String) -> Dictionary:
	return ship.ability_state["slots"].get(slot_key(uid, ability_id), {})


## The state of a slot, made when it is missing.
static func _slot(ship, uid: int, ability_id: String) -> Dictionary:
	var k := slot_key(uid, ability_id)
	if not ship.ability_state["slots"].has(k):
		ship.ability_state["slots"][k] = {"uid": uid, "id": ability_id, "active": 0.0, "cd": 0.0}
	return ship.ability_state["slots"][k]


## The effect is over: rest for the cooldown.
static func _end(ship, a: Dictionary, s: Dictionary) -> void:
	s["active"] = 0.0
	s["cd"] = float(a.get("cooldown", 0.0))
	ship.ability_state["rev"] += 1
	ship.log_event("%s off" % a.get("name", a["id"]))


## One tick of the side effects of ability `a` of part `uid`.
static func _side_effects(ship, uid: int, a: Dictionary, dt: float, rng: RandomNumberGenerator) -> void:
	var inst: Dictionary = ship.components.instances[uid]
	var name: String = ship.components.def(inst["id"]).get("name", inst["id"])
	for se in a.get("side_effects", []):
		var rate := float(se.get("rate", 0.0))
		match str(se.get("type", "")):
			"drain_o2":
				var room: int = ship.atmosphere.room_at(inst["anchor"])
				ship.atmosphere.consume(room, ship.atmosphere.oxygen_of(room) * (1.0 - exp(-rate * dt)))
			"heat":
				inst["heat"] = minf(float(inst["heat"]) + rate * dt, ship.effective(inst["id"])["heat_limit"])
			"fire_risk":
				if rng != null and rng.randf() < rate * dt:
					ship.log_event("%s started a fire" % name)
					Fire.ignite_part(ship, uid)
			"self_damage":
				inst["hp"] = maxf(float(inst["hp"]) - rate * dt, 0.0)
				if inst["hp"] <= 0.0 and inst["status"] != "disabled":
					inst["status"] = "disabled"
					ship.log_event("%s is disabled" % name)
