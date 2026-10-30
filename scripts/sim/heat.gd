extends RefCounted
## Heat per component (docs/CONTENT.md section 3). A running part (powered, status ok) gains
## heat_per_s x line heat each second; every part loses cooling plus the cooling bonus of the
## radiators running in its room. At heat_limit a part overheats: it is out of action (unpowered)
## until its heat drops below half the limit, and the trip may start a fire (fire.gd) on the part's
## first cell. Deterministic: the fire roll comes from the rng the caller passes (ShipSim's).

const Fire = preload("res://scripts/sim/fire.gd")

const FIRE_CHANCE := 0.2  ## on tripping the limit
const RECOVER_AT := 0.5  ## an overheated part works again below this fraction of its limit


## Advance the heat of every component of `ship` by `dt` seconds. Components are visited in uid order.
## `rng`: a RandomNumberGenerator for the fire roll; without one no fire is ever started.
static func tick(ship, dt: float, rng: RandomNumberGenerator = null) -> void:
	if dt <= 0.0:
		return
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var bonus := room_bonus(ship)
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		var e: Dictionary = ship.effective(inst["id"])
		var heat: float = inst["heat"]
		if inst["status"] == "ok" and powered.get(uid, false):
			heat += e["heat_per_s"] * dt
		heat -= (e["cooling"] + float(bonus.get(ship.atmosphere.room_at(inst["anchor"]), 0.0))) * dt
		heat = clampf(heat, 0.0, e["heat_limit"])
		inst["heat"] = heat
		var name: String = ship.components.def(inst["id"]).get("name", inst["id"])
		if inst["status"] == "ok" and heat >= e["heat_limit"]:
			inst["status"] = "overheated"
			ship.log_event("%s overheated" % name)
			if rng != null and rng.randf() < FIRE_CHANCE:
				ship.log_event("%s started a fire" % name)
				Fire.ignite_part(ship, uid)
		elif inst["status"] == "overheated" and heat < e["heat_limit"] * RECOVER_AT:
			inst["status"] = "ok"
			ship.log_event("%s cooled down" % name)


## Cooling bonus per room id: the sum of `cooling_bonus` over the radiators that are running.
static func room_bonus(ship) -> Dictionary:
	var out := {}
	var powered: Dictionary = ship.power_state.get("powered", {})
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		var b := float(ship.components.def(inst["id"]).get("stats", {}).get("cooling_bonus", 0.0))
		var room: int = ship.atmosphere.room_at(inst["anchor"])
		if b > 0.0 and room >= 0 and inst["status"] == "ok" and powered.get(uid, false):
			out[room] = float(out.get(room, 0.0)) + b
	return out
