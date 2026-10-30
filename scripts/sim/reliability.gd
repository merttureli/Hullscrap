extends RefCounted
## Malfunctions (docs/CONTENT.md section 2). Each running component (powered, status ok) rolls
## malfunction_per_min / 60 x dt per tick, from the line. A malfunction puts it out of action until
## it is repaired (Ship.repair). A quarter of malfunctions also cost 1 hp, and at 0 hp the status is
## "disabled"; 30% start a fire in the room (fires are not implemented yet: the chronicle says so).
## Deterministic: all rolls come from the rng the caller passes, in uid order.

const DAMAGE_CHANCE := 0.25  ## a malfunction also deals 1 damage
const FIRE_CHANCE := 0.3


## Roll for every running component of `ship` over `dt` seconds. Components are visited in uid order;
## those whose line never malfunctions use no rolls.
static func tick(ship, dt: float, rng: RandomNumberGenerator) -> void:
	if dt <= 0.0:
		return
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if inst["status"] != "ok" or not powered.get(uid, false):
			continue
		var rate: float = ship.effective(inst["id"])["malfunction_per_min"]
		if rate <= 0.0 or rng.randf() >= rate / 60.0 * dt:
			continue
		var name: String = ship.components.def(inst["id"]).get("name", inst["id"])
		inst["status"] = "malfunction"
		ship.log_event("%s malfunctioned" % name)
		if rng.randf() < DAMAGE_CHANCE:
			inst["hp"] = maxi(0, int(inst["hp"]) - 1)
			if inst["hp"] <= 0:
				inst["status"] = "disabled"
				ship.log_event("%s is disabled" % name)
		if rng.randf() < FIRE_CHANCE:  # only logged for now
			ship.log_event("%s started a fire" % name)
