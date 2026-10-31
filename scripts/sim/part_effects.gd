extends RefCounted
## The generic keys of the racial parts (docs/CONTENT.md section 17): what a part does depending on who stands
## in its room. They sit in an ability's `effects` / `side_effects` (data/components.json, see its _doc) and
## abilities.gd reads them: it owns the tick and the lists of what runs, this file owns the rules, the crew
## counting and the validator. Static, deterministic, no randomness.
## `effects` (a dictionary; crew_bonus and crew_needed may also be a list of them):
## - crew_bonus {who, stat, per, max}: each up crew member in the part's room who matches `who` adds `per` to
##   `stat` (power, thrust or shield_layer), at most `max` in all. Power is added to the part's output after its
##   factors, thrust to the engine's thrust, shield_layer to the layers of a shield part (rounded down).
## - crew_needed {count, stat, else_mult, who?}: unless `count` up crew (matching `who`, if given) stand in the
##   room, `stat` (power, thrust, shield_layer, recharge or evasion) is multiplied by `else_mult`. Layers are rounded
##   down; recharge is the speed at which the shield's used layers come back (0.5 = twice as long); evasion is
##   the ability's own `evasion_add` (a Resonance Helm).
## - room_wall_hp_mult: factor on the hp of the wall cells round the part's room (Abilities.wall_hp_mults).
## - heat_above {heat, shield_layer}: that many extra layers while the room's hottest part is above `heat`.
## - room_work_mult {mult, who?, else_mult?}: factor on the work speed of the crew in the room (Abilities.work_mult).
## `side_effects`, per second while the part works:
## - shock_organic (rate = hp/s): every up crew member in the room who is not `mechanical` takes that.
## - scorch (rate = hp/s): every crew member in the room without the `heat_resistant` trait takes that (the mirror of
##   shock_organic: an Emberkin crew runs a hot part free). It does not touch the part's own heat: `heat` does.
## - wet (rate = work factor): crew in the room work at that factor unless their work_mult.extinguish is above 1,
##   and every part in the room loses WET_COOLING heat at the start of each second.
## "Up" means not downed and not stunned. `who` is a species id, a trait id of the library or a flag of the
## resolved traits ("mechanical"); "a|b" means either. "Room" is the room of the part's anchor.

const TraitSet = preload("res://scripts/crew/traits.gd")

const ABILITY_KEYS: Array[String] = ["engine", "shield", "utility"]  ## the combat keys of an active ability (Abilities.KEYS)
const TOP_KEYS: Array[String] = ["id", "name", "type", "key", "duration", "cooldown", "effects", "side_effects", "operator_needs", "event", "blurb", "notes"]
const EFFECTS: Array[String] = ["stat_mult", "shield_layer", "charge_mult", "evasion_add", "crew_bonus", "crew_needed", "room_wall_hp_mult", "heat_above", "room_work_mult"]
const SIDE_EFFECTS: Array[String] = ["drain_o2", "heat", "power_spike", "fire_risk", "self_damage", "shock_organic", "scorch", "wet"]
const CREW_KEYS: Array[String] = ["crew_bonus", "crew_needed", "heat_above"]  ## the effects whose figures change with the crew or the heat
const BONUS_STATS: Array[String] = ["power", "thrust", "shield_layer"]
const NEEDED_STATS: Array[String] = ["power", "thrust", "shield_layer", "recharge", "evasion"]
const WET_COOLING := 30.0  ## heat every part of a wet room loses at the start of each second
const WET_PERIOD := 1.0
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


# --- crew in the room -----------------------------------------------------------------------------

## A dictionary as a one-entry list, a list as it is, anything else as [].
static func entries(v) -> Array:
	if v is Dictionary:
		return [v]
	return v if v is Array else []


## The room of part `uid` (its anchor's), -1 when it has none.
static func room_of_part(ship, uid: int) -> int:
	if not ship.components.instances.has(uid):  # a crew ability's effect (uid -1) is on no part
		return -1
	return ship.atmosphere.room_at(ship.components.instances[uid]["anchor"])


static func _up(m) -> bool:
	return not m.is_down() and not m.is_stunned()


## Is `m` what `who` names: a species id, a trait id, or a true flag of the resolved traits ("mechanical")? "" is anyone.
static func matches(m, who: String) -> bool:
	if who == "":
		return true
	for alt in who.split("|"):
		var id := alt.strip_edges()
		if id == "":
			continue
		if m.species == id or m.traits().has(id):
			return true
		var flag = TraitSet.of(m).get(id)
		if flag is bool and flag:
			return true
	return false


## How many up crew members matching `who` stand in the room of part `uid`.
static func crew_count(ship, uid: int, who := "") -> int:
	var room := room_of_part(ship, uid)
	if room < 0:
		return 0
	var n := 0
	for m in ship.crew:
		if _up(m) and ship.atmosphere.room_at(m.cell()) == room and matches(m, who):
			n += 1
	return n


## What a crew_bonus entry adds now: per x matching crew, at most max.
static func bonus_of(ship, uid: int, cb: Dictionary) -> float:
	return minf(float(cb.get("per", 0.0)) * crew_count(ship, uid, str(cb.get("who", ""))), float(cb.get("max", INF)))


## The factor a crew_needed entry gives its stat now: 1 with the crew there, else else_mult.
static func needed_mult(ship, uid: int, cn: Dictionary) -> float:
	return 1.0 if crew_count(ship, uid, str(cn.get("who", ""))) >= int(cn.get("count", 1)) else float(cn.get("else_mult", 1.0))


## The heat of the hottest part in room `room` (0 for a room with none).
static func room_heat(ship, room: int) -> float:
	var best := 0.0
	for uid in ship.components.instances:
		if ship.atmosphere.room_at(ship.components.instances[uid]["anchor"]) == room:
			best = maxf(best, float(ship.components.instances[uid]["heat"]))
	return best


## Do any of these `effects` change with the crew or the heat?
static func has_crew_effects(effects: Dictionary) -> bool:
	for k in CREW_KEYS:
		if effects.has(k):
			return true
	return false


## What the crew and heat effects of one ability come to now, as plain data to compare: each crew_bonus amount,
## whether each crew_needed is met, whether the room is above heat_above.
static func fingerprint(ship, uid: int, effects: Dictionary) -> Array:
	var out := []
	for cb in entries(effects.get("crew_bonus")):
		out.append(bonus_of(ship, uid, cb))
	for cn in entries(effects.get("crew_needed")):
		out.append(needed_mult(ship, uid, cn) == 1.0)
	var h = effects.get("heat_above")
	if h is Dictionary:
		out.append(room_heat(ship, room_of_part(ship, uid)) > float(h.get("heat", 0.0)))
	return out


## The layers a shield part gives: `base` (its stats.layers) times its crew_needed shield_layer factors, rounded
## down, plus its crew_bonus shield_layer (rounded down) and its heat_above layers while the room is hot enough.
static func layers_of(ship, uid: int, base: int, effects: Dictionary) -> int:
	var f := 1.0
	for cn in entries(effects.get("crew_needed")):
		if cn.get("stat") == "shield_layer":
			f *= needed_mult(ship, uid, cn)
	var n := floori(base * f + 1e-6)
	for cb in entries(effects.get("crew_bonus")):
		if cb.get("stat") == "shield_layer":
			n += floori(bonus_of(ship, uid, cb) + 1e-6)
	var h = effects.get("heat_above")
	if h is Dictionary and room_heat(ship, room_of_part(ship, uid)) > float(h.get("heat", 0.0)):
		n += int(h.get("shield_layer", 0))
	return n


## The factor an ability's room_work_mult and wet give the work of crew member `m`, who stands in its room.
static func work_of(m, a: Dictionary) -> float:
	var f := 1.0
	var w = a.get("effects", {}).get("room_work_mult")
	if w is Dictionary:
		f *= float(w.get("mult", 1.0)) if matches(m, str(w.get("who", ""))) else float(w.get("else_mult", 1.0))
	for se in a.get("side_effects", []):
		if se.get("type", "") == "wet" and float(TraitSet.of(m)["work_mult"]["extinguish"]) <= 1.0:
			f *= float(se.get("rate", 1.0))
	return f


# --- what a working part does to the room each second ---------------------------------------------

## shock_organic: `rate` hp a second for every crew member (stunned or not) in the room of part `uid` who is not mechanical.
static func shock(ship, uid: int, rate: float, dt: float) -> void:
	_hurt_room(ship, uid, rate * dt, func(m): return bool(TraitSet.of(m)["mechanical"]))


## scorch: `rate` hp a second for every crew member in the room of part `uid` who lacks the heat_resistant trait.
static func scorch(ship, uid: int, rate: float, dt: float) -> void:
	_hurt_room(ship, uid, rate * dt, func(m): return m.traits().has("heat_resistant"))


## Hurt every crew member in the room of part `uid` who is not down and for whom `immune` is false.
static func _hurt_room(ship, uid: int, amount: float, immune: Callable) -> void:
	var room := room_of_part(ship, uid)
	if room < 0:
		return
	for m in ship.crew:
		if m.is_down() or ship.atmosphere.room_at(m.cell()) != room or immune.call(m):
			continue
		m.hurt(amount)
		if m.is_down():
			m.job = {}
			m.path.clear()
			ship.log_event("%s is down" % m.name)


## wet: at the start of each second (and when it first works) every part in the room of part `uid` loses WET_COOLING heat.
## `key` names the pulse in ship.ability_state["pulse"] (seconds since the last one).
static func wet(ship, uid: int, key: String, dt: float) -> void:
	if not ship.ability_state.has("pulse"):
		ship.ability_state["pulse"] = {}
	var t: float = float(ship.ability_state["pulse"].get(key, WET_PERIOD)) + dt
	if t < WET_PERIOD - 1e-9:
		ship.ability_state["pulse"][key] = t
		return
	ship.ability_state["pulse"][key] = fmod(t, WET_PERIOD)
	var room := room_of_part(ship, uid)
	if room < 0:
		return
	for other in ship.components.instances:
		var inst: Dictionary = ship.components.instances[other]
		if ship.atmosphere.room_at(inst["anchor"]) == room:
			inst["heat"] = maxf(float(inst["heat"]) - WET_COOLING, 0.0)


## The wall cells round room `room`: solid tiles (not doors) beside its cells.
static func walls_round(ship, room: int) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for c in ship.atmosphere.rooms[room]["cells"]:
		for d in SIDES:
			var n: Vector2i = c + d
			var id: String = ship.grid.get_tile(n)
			if id != "" and not seen.has(n) and ship.grid.tile_flag(id, "solid") and not ship.grid.tile_flag(id, "door"):
				seen[n] = true
				out.append(n)
	return out


# --- the validator ---------------------------------------------------------------------------------

## Problems in one ability entry of a component, as messages (an empty list when it is fine): an unknown key
## anywhere, a wrong type, a figure out of range. `who_ids`: the ids `who` may name (species and traits; checked
## when not empty), `trait_ids`: the traits operator_needs may name (checked when not empty).
static func problems(a: Dictionary, who_ids: Array = [], trait_ids: Array = []) -> Array[String]:
	var out: Array[String] = []
	for k in a:
		if not TOP_KEYS.has(k):
			out.append("unknown ability key '%s' (known: %s)" % [k, ", ".join(TOP_KEYS)])
	if str(a.get("id", "")) == "":
		out.append("an ability needs an id")
	var type := str(a.get("type", "active"))
	if not ["active", "passive"].has(type):
		out.append("type must be active or passive, not '%s'" % type)
	if a.has("key") and not ABILITY_KEYS.has(str(a["key"])):
		out.append("key '%s' is not one of %s" % [a["key"], ", ".join(ABILITY_KEYS)])
	for k in ["duration", "cooldown"]:
		if a.has(k) and not (_num(a[k]) and float(a[k]) >= 0.0):
			out.append("%s must be a number of seconds, 0 or more" % k)
	if type == "active" and not (a.has("duration") and _num(a["duration"]) and float(a["duration"]) > 0.0):
		out.append("an active ability needs a duration above 0")
	var effects = a.get("effects", {})
	if effects is Dictionary:
		_effect_problems(effects, who_ids, out)
	else:
		out.append("effects must be an object")
	var side = a.get("side_effects", [])
	if side is Array:
		for s in side:
			_side_problems(s, out)
	else:
		out.append("side_effects must be a list")
	var needs = a.get("operator_needs", [])
	if needs is Array:
		for n in needs:
			if not n is String or n == "":
				out.append("operator_needs holds trait ids, not '%s'" % str(n))
				continue
			for alt in n.split("|"):
				if not trait_ids.is_empty() and not trait_ids.has(alt.strip_edges()):
					out.append("operator_needs: '%s' is not a trait of the library" % alt.strip_edges())
	else:
		out.append("operator_needs must be a list of trait ids")
	return out


## Problems in a whole component def: its abilities (prefixed with their id), a shield-only effect on a part that is not a
## shield, a `stats.malfunction_per_min` that is not a chance and a `stats.recharge` that is not a time.
static func component_problems(c: Dictionary, who_ids: Array = [], trait_ids: Array = []) -> Array[String]:
	var out: Array[String] = []
	var m = c.get("stats", {}).get("malfunction_per_min") if c.get("stats") is Dictionary else null
	if m != null and not (_num(m) and float(m) >= 0.0 and float(m) <= 1.0):
		out.append("stats.malfunction_per_min must be a chance from 0 to 1 per minute, not '%s'" % str(m))
	var rc = c.get("stats", {}).get("recharge") if c.get("stats") is Dictionary else null
	if rc != null and not (_num(rc) and float(rc) > 0.0):
		out.append("stats.recharge must be the seconds a used layer takes to come back (2.0 is normal), above 0, not '%s'" % str(rc))
	var list = c.get("abilities", [])
	if not list is Array:
		return out
	for a in list:
		if not a is Dictionary:
			out.append("an ability must be an object")
			continue
		for p in problems(a, who_ids, trait_ids):
			out.append("ability '%s': %s" % [a.get("id", "?"), p])
		var fx = a.get("effects", {})
		if fx is Dictionary and str(c.get("family", "shield")) != "shield" and _shield_only(fx):
			out.append("ability '%s': shield_layer and recharge effects (crew_bonus, crew_needed, heat_above) only work on a shield part" % a.get("id", "?"))
	return out


static func _shield_only(fx: Dictionary) -> bool:
	if fx.has("heat_above"):
		return true
	for k in ["crew_bonus", "crew_needed"]:
		for e in entries(fx.get(k)):
			if e is Dictionary and ["shield_layer", "recharge"].has(e.get("stat")):
				return true
	return false


static func _num(v) -> bool:
	return v is float or v is int


static func _effect_problems(fx: Dictionary, who_ids: Array, out: Array[String]) -> void:
	for k in fx:
		var v = fx[k]
		match str(k):
			"stat_mult":
				if not v is Dictionary:
					out.append("stat_mult must be an object like {\"thrust\": 1.4}")
					continue
				for s in v:
					if not ["thrust", "power"].has(s):
						out.append("stat_mult: '%s' is not thrust or power" % s)
					elif not (_num(v[s]) and float(v[s]) > 0.0):
						out.append("stat_mult.%s must be a number above 0" % s)
			"shield_layer":
				if not (_num(v) and float(v) >= 0.0):
					out.append("shield_layer must be a number of layers, 0 or more")
			"charge_mult":
				if not (_num(v) and float(v) > 0.0):
					out.append("charge_mult must be a number above 0")
			"evasion_add":
				if not _num(v):
					out.append("evasion_add must be a number")
			"crew_bonus":
				var list := entries(v)
				if list.is_empty():
					out.append("crew_bonus must be {who, stat, per, max} or a list of them")
				for e in list:
					_crew_entry(str(k), e, ["who", "stat", "per", "max"], ["who", "stat", "per", "max"], BONUS_STATS, who_ids, out)
					if e is Dictionary and _num(e.get("per")) and _num(e.get("max")) and float(e["max"]) < float(e["per"]):
						out.append("crew_bonus: max is below per, so it could never add one crew member's worth")
			"crew_needed":
				var list := entries(v)
				if list.is_empty():
					out.append("crew_needed must be {count, stat, else_mult, who?} or a list of them")
				for e in list:
					_crew_entry(str(k), e, ["count", "stat", "else_mult", "who"], ["count", "stat", "else_mult"], NEEDED_STATS, who_ids, out)
			"room_wall_hp_mult":
				if not (_num(v) and float(v) > 0.0):
					out.append("room_wall_hp_mult must be a factor above 0 (1.5 = 50% more wall hp)")
			"heat_above":
				if not v is Dictionary:
					out.append("heat_above must be {heat, shield_layer}")
					continue
				_keys(str(k), v, ["heat", "shield_layer"], ["heat", "shield_layer"], out)
				if not (_num(v.get("heat")) and float(v.get("heat", -1)) >= 0.0):
					out.append("heat_above.heat must be a heat of 0 or more")
				if not (_num(v.get("shield_layer")) and float(v.get("shield_layer", 0)) >= 1.0 and float(v["shield_layer"]) == floorf(float(v["shield_layer"]))):
					out.append("heat_above.shield_layer must be a whole number of layers, 1 or more")
			"room_work_mult":
				if not v is Dictionary:
					out.append("room_work_mult must be {mult, who?, else_mult?}")
					continue
				_keys(str(k), v, ["mult", "who", "else_mult"], ["mult"], out)
				for f in ["mult", "else_mult"]:
					if v.has(f) and not (_num(v[f]) and float(v[f]) >= 0.0):
						out.append("room_work_mult.%s must be a factor, 0 or more" % f)
				if v.has("who"):
					_who(str(k), v["who"], who_ids, out)
				if v.has("else_mult") and not v.has("who"):
					out.append("room_work_mult.else_mult needs a who (without one everybody gets mult)")
			_:
				out.append("unknown effect '%s' (known: %s)" % [k, ", ".join(EFFECTS)])


static func _side_problems(s, out: Array[String]) -> void:
	if not s is Dictionary:
		out.append("a side effect must be an object {type, rate}")
		return
	var t := str(s.get("type", ""))
	if not SIDE_EFFECTS.has(t):
		out.append("unknown side effect type '%s' (known: %s)" % [t, ", ".join(SIDE_EFFECTS)])
	for k in s:
		if k != "type" and k != "rate":
			out.append("side effect '%s': unknown key '%s' (only type and rate)" % [t, k])
	var r = s.get("rate")
	if not _num(r) or float(r) < 0.0:
		out.append("side effect '%s' needs a rate of 0 or more" % t)
	elif ["drain_o2", "fire_risk", "wet"].has(t) and float(r) > 1.0:
		out.append("side effect '%s': rate is a fraction (0 to 1), not %s" % [t, str(r)])


## The keys of dictionary `v` (effect `name`) must be among `known`, and `required` ones must be there.
static func _keys(name: String, v: Dictionary, known: Array, required: Array, out: Array[String]) -> void:
	for k in v:
		if not known.has(k):
			out.append("%s: unknown key '%s' (known: %s)" % [name, k, ", ".join(known)])
	for k in required:
		if not v.has(k):
			out.append("%s needs '%s'" % [name, k])


static func _who(name: String, who, who_ids: Array, out: Array[String]) -> void:
	if not who is String or who.strip_edges() == "":
		out.append("%s.who must be a species or trait id" % name)
		return
	if who_ids.is_empty():
		return
	for alt in who.split("|"):
		if not who_ids.has(alt.strip_edges()):
			out.append("%s.who: '%s' is not a species, a trait or a trait flag" % [name, alt.strip_edges()])


static func _crew_entry(name: String, e, known: Array, required: Array, stats: Array, who_ids: Array, out: Array[String]) -> void:
	if not e is Dictionary:
		return
	_keys(name, e, known, required, out)
	if e.has("stat") and not stats.has(e["stat"]):
		out.append("%s.stat '%s' is not one of %s" % [name, str(e["stat"]), ", ".join(stats)])
	if e.has("who") or name == "crew_bonus":
		_who(name, e.get("who"), who_ids, out)
	if name == "crew_bonus":
		for f in ["per", "max"]:
			if e.has(f) and not (_num(e[f]) and float(e[f]) > 0.0):
				out.append("crew_bonus.%s must be a number above 0" % f)
	else:
		if e.has("count") and not (_num(e["count"]) and float(e["count"]) >= 1.0 and float(e["count"]) == floorf(float(e["count"]))):
			out.append("crew_needed.count must be a whole number of crew, 1 or more")
		if e.has("else_mult") and not (_num(e["else_mult"]) and float(e["else_mult"]) >= 0.0):
			out.append("crew_needed.else_mult must be a factor, 0 or more")
