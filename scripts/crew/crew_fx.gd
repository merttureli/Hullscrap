extends RefCounted
## The timed effects that crew abilities leave on a ship (crew_abilities.gd starts them, ShipSim ticks them),
## kept in `ship.ability_state["fx"]` (not saved). An effect is {kind, left (seconds), who (the caster's name), ...}:
## - power: {uid, bonus}, the part gets +bonus power by hand (Ship.refresh passes it to Power.solve as `hand`).
## - overclock: {uid, mult, rest}, the part runs mult times faster; when it ends the part is offline for `rest` s.
## - offline: {uid}, the part neither makes nor uses power (Ship.disabled_uids): a hack, or an overclock's burn-out.
## - rally: {mult}, the others in the caster's room work mult times faster (TraitSet.work_rate).
## - shield_layer: {layers}, extra shield layers (through Abilities.running).
## - scan: the radar sees hidden contacts (Radar.contacts).
## - berserk: {mult}, the caster's melee damage multiplier (nothing reads it until on-foot fights).
## Every start and end bumps `ability_state["rev"]`, so the power solve and the arena's thrust and layers refresh.
## Queries only (no dependencies, so traits.gd, abilities.gd, jobs.gd and ship.gd can all ask here); duck-typed on
## the ship.

const EPS := 1e-9
const WAS_OVERCLOCK := "overclock"  ## the `why` of the offline effect an overclock leaves


## The effects on `ship` (the live array).
static func list(ship) -> Array:
	return ship.ability_state.get("fx", [])


## Start effect `fx` on `ship`.
static func add(ship, fx: Dictionary) -> void:
	if not ship.ability_state.has("fx"):
		ship.ability_state["fx"] = []
	ship.ability_state["fx"].append(fx)
	ship.ability_state["rev"] += 1


## Advance every effect by `dt` seconds. An overclock that ends leaves the part offline for its `rest`; effects of a
## part that is gone end.
static func tick(ship, dt: float) -> void:
	var fxs: Array = list(ship)
	if fxs.is_empty() or dt <= 0.0:
		return
	var keep := []
	var after := []
	var changed := false
	for fx in fxs:
		fx["left"] = float(fx["left"]) - dt
		var gone: bool = fx.has("uid") and not ship.components.instances.has(int(fx["uid"]))
		if float(fx["left"]) > EPS and not gone:
			keep.append(fx)
			continue
		changed = true
		if fx["kind"] == "overclock" and float(fx.get("rest", 0.0)) > 0.0 and not gone:
			after.append({"kind": "offline", "uid": fx["uid"], "left": float(fx["rest"]), "who": fx["who"], "why": WAS_OVERCLOCK})
			ship.log_event("%s burns out: offline %d s" % [part_name(ship, int(fx["uid"])), ceili(float(fx["rest"]) - 1e-6)])
	if changed:
		ship.ability_state["fx"] = keep + after
		ship.ability_state["rev"] += 1


static func part_name(ship, uid: int) -> String:
	if not ship.components.instances.has(uid):
		return "part"
	var id: String = ship.components.instances[uid]["id"]
	return str(ship.components.def(id).get("name", id))


## part uid -> power added by `power` effects.
static func power_bonus(ship) -> Dictionary:
	var out := {}
	for fx in list(ship):
		if fx["kind"] == "power":
			out[int(fx["uid"])] = float(out.get(int(fx["uid"]), 0.0)) + float(fx["bonus"])
	return out


## uid -> true for the parts held offline.
static func offline(ship) -> Dictionary:
	var out := {}
	for fx in list(ship):
		if fx["kind"] == "offline":
			out[int(fx["uid"])] = true
	return out


## Is part `uid` held offline by a crew ability?
static func is_offline(ship, uid: int) -> bool:
	for fx in list(ship):
		if fx["kind"] == "offline" and int(fx["uid"]) == uid:
			return true
	return false


## The effects as abilities for Abilities.running(): [{uid, ability}] with `effects` it reads. An overclocked engine
## gives thrust, a reactor (a part with power above 0) its power; weapons, shields and helms read overclock_mult.
## Extra shield layers come as uid -1.
static func running(ship) -> Array:
	var out := []
	for fx in list(ship):
		match fx["kind"]:
			"overclock":
				var uid := int(fx["uid"])
				if not ship.components.instances.has(uid):
					continue
				var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
				if str(def.get("family", "")) == "engine":
					out.append({"uid": uid, "ability": {"id": "overclock", "effects": {"stat_mult": {"thrust": float(fx["mult"])}}}})
				elif float(def.get("power", 0)) > 0.0:
					out.append({"uid": uid, "ability": {"id": "overclock", "effects": {"stat_mult": {"power": float(fx["mult"])}}}})
			"shield_layer":
				out.append({"uid": -1, "ability": {"id": "shield_layer", "effects": {"shield_layer": int(fx["layers"])}}})
	return out


## The speed factor of overclocks running on part `uid` (1.0 when none).
static func overclock_mult(ship, uid: int) -> float:
	var m := 1.0
	for fx in list(ship):
		if fx["kind"] == "overclock" and int(fx["uid"]) == uid:
			m = maxf(m, float(fx["mult"]))
	return m


## The best overclock factor on any part of `family` (1.0 when none).
static func family_mult(ship, family: String) -> float:
	var m := 1.0
	for fx in list(ship):
		if fx["kind"] == "overclock" and ship.components.instances.has(int(fx["uid"])):
			if str(ship.components.def(ship.components.instances[int(fx["uid"])]["id"]).get("family", "")) == family:
				m = maxf(m, float(fx["mult"]))
	return m


## The work speed factor rallies give crew member `m`, who stands in room `room`: the best rally of an up crew
## member (not `m`) who stands in that room too; 1.0 when none.
static func rally_factor(ship, m, room: int) -> float:
	var best := 1.0
	if room < 0:
		return best
	for fx in list(ship):
		if fx["kind"] != "rally" or float(fx["mult"]) <= best:
			continue
		for o in ship.crew:
			if o != m and o.name == fx["who"] and not o.is_down() and ship.atmosphere.room_at(o.cell()) == room:
				best = float(fx["mult"])
	return best


## The melee factor berserk gives crew member `m` (1.0 when not berserk).
static func berserk_mult(ship, m) -> float:
	var f := 1.0
	for fx in list(ship):
		if fx["kind"] == "berserk" and fx["who"] == m.name:
			f = maxf(f, float(fx["mult"]))
	return f


## Seconds of scan left (0 when none runs).
static func scan_left(ship) -> float:
	var left := 0.0
	for fx in list(ship):
		if fx["kind"] == "scan":
			left = maxf(left, float(fx["left"]))
	return left
