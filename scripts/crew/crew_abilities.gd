extends RefCounted
## The active abilities of crew members (docs/CONTENT.md section 16). A crew member carries one as
## `ability: {id, cooldown?, params?}` (CrewMember.ability: from their species entry, or from their unique
## character, characters.gd). The player selects them (crew_view.gd) and presses G, or clicks the ability on the
## crew card (crew_bar.gd); use() runs it. The vocabulary, with names, default cooldowns and params, is
## data/crew_abilities.json (its `_doc` says what each does). Instant ones act at once (heal_burst, repair_burst,
## extinguish, seal_breach, hack, phase); timed ones leave an effect on the ship (crew_fx.gd) that ShipSim ticks.
## Cooldowns count from the use and tick in tick(), which ShipSim calls for every ship each step, so they stand
## still when the world is paused (build mode). A refused use (no fire to put out ...) costs no cooldown.
## No randomness: every target is picked in uid / (y, x) order. Also here: the checks of the data (problems()).

const CrewMember = preload("res://scripts/crew/crew_member.gd")
const CrewFx = preload("res://scripts/crew/crew_fx.gd")
const Characters = preload("res://scripts/crew/characters.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/crew_abilities.json"
const ART_CREW := "res://art/crew/"
## The fx kinds (crew_fx.gd) that show an ability as running on its card.
const FX_OF := {"power_system": ["power"], "overclock": ["overclock"], "rally": ["rally"], "shield_layer": ["shield_layer"], "scan": ["scan"], "berserk": ["berserk"]}
const CHARACTER_KEYS: Array[String] = ["id", "name", "species", "unique_species", "rig", "traits", "ability", "obtained", "lore", "override", "reason"]
const SPECIES_KEYS: Array[String] = ["name", "hp", "speed", "traits", "rig", "sidearm", "notes"]  ## beside the trait keys, the keys of a unique_species
const RIG_KEYS: Array[String] = ["tint", "head"]
const ABILITY_KEYS: Array[String] = ["id", "cooldown", "params"]

static var _vocab := {}  # id -> entry of data/crew_abilities.json, read on first use


## The vocabulary: ability id -> {name, tag, color, blurb, cooldown, params} (data/crew_abilities.json).
static func vocabulary() -> Dictionary:
	if _vocab.is_empty() and FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary and data.get("abilities") is Dictionary:
			_vocab = data["abilities"]
	return _vocab


## The ability crew member `m` has, with the vocabulary's defaults filled in: {id, name, tag, color, blurb,
## cooldown, params}. {} when they have none (or one the vocabulary does not know).
static func of(m) -> Dictionary:
	var own: Dictionary = m.ability
	var base: Dictionary = vocabulary().get(str(own.get("id", "")), {})
	if base.is_empty():
		return {}
	var params: Dictionary = base.get("params", {}).duplicate(true)
	if own.get("params") is Dictionary:
		params.merge(own["params"], true)
	return {"id": str(own["id"]), "name": str(base.get("name", own["id"])), "tag": str(base.get("tag", "??")), "color": str(base.get("color", "#cfe6ff")),
		"blurb": str(base.get("blurb", "")), "cooldown": float(own.get("cooldown", base.get("cooldown", 30.0))), "params": params}


# --- the frame ----------------------------------------------------------------------------------------

## Advance by `dt` seconds: the cooldowns of the crew of `ship`, and its crew effects (CrewFx.tick).
static func tick(ship, dt: float) -> void:
	if dt <= 0.0:
		return
	for m in ship.crew:
		if m.ability_cd > 0.0:
			m.ability_cd = maxf(m.ability_cd - dt, 0.0)
	CrewFx.tick(ship, dt)


# --- state for the UI -----------------------------------------------------------------------------------

## Seconds an effect of m's ability still runs on `ship` (0 when none, or for an instant ability).
static func active_left(ship, m) -> float:
	var left := 0.0
	var kinds: Array = FX_OF.get(str(m.ability.get("id", "")), [])
	for fx in CrewFx.list(ship):
		if fx["who"] == m.name and kinds.has(fx["kind"]):
			left = maxf(left, float(fx["left"]))
	return left


## What the crew card shows for `m`: {has (they carry an ability), ability (of()), state ("ready", "cooling",
## "running" or "blocked"), cooldown_left, active_left, reason}. `reason` is why it cannot be used now ("" when it can).
static func card(ship, m) -> Dictionary:
	var a := of(m)
	if a.is_empty():
		return {"has": false, "ability": {}, "state": "none", "cooldown_left": 0.0, "active_left": 0.0, "reason": ""}
	var why := can_use(ship, m)
	var run := active_left(ship, m)
	var state := "ready"
	if run > 0.0:
		state = "running"
	elif m.ability_cd > 0.0:
		state = "cooling"
	elif why != "":
		state = "blocked"
	return {"has": true, "ability": a, "state": state, "cooldown_left": m.ability_cd, "active_left": run, "reason": why}


# --- using it ------------------------------------------------------------------------------------------

## "" when `m` may use their ability now, else why not: no ability, down, stunned, or "on cooldown 12 s". Whether
## there is something to act on (a fire, a breach ...) is only known by use().
static func can_use(ship, m) -> String:
	if of(m).is_empty():
		return "has no special ability"
	if m.is_down():
		return "is down"
	if m.is_stunned():
		return "is stunned"
	if m.ability_cd > 0.0:
		return "on cooldown %d s" % ceili(m.ability_cd - 1e-6)
	return ""


## Use the ability of `m` (aboard `ship`) now. `enemy`: the other ship of a fight, or null (hack and scan use it).
## Returns {ok, text}: text says what happened, or why not (no cooldown is spent then). On success the cooldown
## starts and the chronicle of `ship` gets the line.
static func use(ship, m, enemy = null) -> Dictionary:
	var why := can_use(ship, m)
	if why != "":
		return {"ok": false, "text": "%s %s" % [m.name, why]}
	var a := of(m)
	var p: Dictionary = a["params"]
	var r: Dictionary
	match a["id"]:
		"power_system": r = _power_system(ship, m, p)
		"overclock": r = _overclock(ship, m, p)
		"heal_burst": r = _heal_burst(ship, m, p)
		"rally": r = _rally(ship, m, p)
		"repair_burst": r = _repair_burst(ship, m, p)
		"extinguish": r = _extinguish(ship, m)
		"seal_breach": r = _seal_breach(ship, m, p)
		"shield_layer": r = _shield_layer(ship, m, p)
		"scan": r = _scan(ship, m, p, enemy)
		"hack": r = _hack(ship, m, p, enemy)
		"berserk": r = _berserk(ship, m, p)
		"phase": r = _phase(ship, m, p)
		_: r = _fail("nothing is wired to %s" % a["id"])
	if r["ok"]:
		m.ability_cd = float(a["cooldown"])
		ship.log_event("%s: %s" % [a["name"], r["text"]])
	return r


## The melee factor of `m` in an on-foot fight: their trait (melee_mult) times berserk. Nothing fights on foot yet.
static func melee_mult(ship, m) -> float:
	return float(TraitSet.of(m)["melee_mult"]) * CrewFx.berserk_mult(ship, m)


## One melee hit of `attacker` on `victim` (on-foot fights; the hook for them): `base` damage times the attacker's melee_mult and
## the victim's damage_taken.melee. A victim with counter_melee who was up when hit deals that damage straight back (times the
## attacker's own damage_taken.melee; a counter is never countered, and it lands even when the hit put them down). Anyone put
## down drops their job. Returns {dealt, countered}: the hit points each of them lost.
static func melee_hit(ship, attacker, victim, base: float) -> Dictionary:
	var t := TraitSet.of(victim)
	var standing: bool = not victim.is_down()
	var dealt := base * melee_mult(ship, attacker) * float(t["damage_taken"]["melee"])
	var countered := 0.0
	_hurt(ship, victim, dealt)
	if standing and float(t["counter_melee"]) > 0.0 and attacker != victim:
		countered = float(t["counter_melee"]) * float(TraitSet.of(attacker)["damage_taken"]["melee"])
		_hurt(ship, attacker, countered)
	return {"dealt": dealt, "countered": countered}


## `m` loses `amount` hp; one who goes down drops what they were doing (and the chronicle says so).
static func _hurt(ship, m, amount: float) -> void:
	var was_down: bool = m.is_down()
	m.hurt(amount)
	if m.is_down() and not was_down:
		m.job = {}
		m.path.clear()
		ship.log_event("%s is down" % m.name)


static func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text}


static func _fail(text: String) -> Dictionary:
	return {"ok": false, "text": text}


# --- the abilities ---------------------------------------------------------------------------------------

static func _power_system(ship, m, p: Dictionary) -> Dictionary:
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var best := -1
	var best_rank := 99
	for uid in _near_parts(ship, m):
		var power := float(ship.components.def(ship.components.instances[uid]["id"]).get("power", 0))
		if power == 0.0:
			continue
		var rank := (0 if not powered.get(uid, false) else 1) if power < 0.0 else 2  # a system with no power first, a reactor last
		if rank < best_rank:
			best = uid
			best_rank = rank
	if best < 0:
		return _fail("%s has no system within reach to power" % m.name)
	CrewFx.add(ship, {"kind": "power", "uid": best, "bonus": float(p.get("power", 0.0)), "left": float(p.get("duration", 0.0)), "who": m.name})
	return _ok("%s powers the %s by hand for %d s" % [m.name, CrewFx.part_name(ship, best), roundi(float(p.get("duration", 0.0)))])


static func _overclock(ship, m, p: Dictionary) -> Dictionary:
	var uid := -1
	var uids: Array = ship.manned.keys()
	uids.sort()
	for u in uids:
		if ship.manned[u] == m.name and ship.components.instances.has(u):
			uid = u
			break
	if uid < 0:
		return _fail("%s is not manning a system" % m.name)
	var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
	var family := str(def.get("family", ""))
	if not (family in ["engine", "weapon", "shield", "helm"] or float(def.get("power", 0)) > 0.0):
		return _fail("the %s cannot be overclocked" % CrewFx.part_name(ship, uid))
	if CrewFx.overclock_mult(ship, uid) > 1.0 or CrewFx.is_offline(ship, uid):
		return _fail("the %s is already overclocked or cooling off" % CrewFx.part_name(ship, uid))
	CrewFx.add(ship, {"kind": "overclock", "uid": uid, "mult": float(p.get("mult", 1.5)), "rest": float(p.get("rest", 0.0)), "left": float(p.get("duration", 0.0)), "who": m.name})
	return _ok("%s overclocks the %s x%s for %d s" % [m.name, CrewFx.part_name(ship, uid), p.get("mult", 1.5), roundi(float(p.get("duration", 0.0)))])


static func _heal_burst(ship, m, p: Dictionary) -> Dictionary:
	var amount := float(p.get("amount", 0.0)) * float(TraitSet.of(m)["work_mult"]["heal_others"])  # a Basalt is a bad medic
	var healed := 0
	for o in _in_room(ship, m):
		if o.hp >= o.max_hp:
			continue
		var was_down: bool = o.is_down()
		o.heal(amount)
		healed += 1
		if was_down and not o.is_down():
			ship.log_event("%s is back on their feet" % o.name)
	if healed == 0:
		return _fail("nobody here is hurt")
	return _ok("%s heals %d crew by %d hp" % [m.name, healed, roundi(amount)])


static func _rally(ship, m, p: Dictionary) -> Dictionary:
	var others := _in_room(ship, m).filter(func(o): return o != m and not o.is_down())
	if others.is_empty():
		return _fail("nobody else is here to rally")
	CrewFx.add(ship, {"kind": "rally", "mult": float(p.get("mult", 1.5)), "left": float(p.get("duration", 0.0)), "who": m.name})
	return _ok("%s rallies %d crew for %d s" % [m.name, others.size(), roundi(float(p.get("duration", 0.0)))])


static func _repair_burst(ship, m, p: Dictionary) -> Dictionary:
	var amount := float(p.get("amount", 0.0))
	var best := -1
	var best_frac := 2.0
	var best_out := false
	for uid in _near_parts(ship, m):
		var inst: Dictionary = ship.components.instances[uid]
		var frac := float(inst["hp"]) / maxf(float(ship.effective(inst["id"])["hp"]), 1.0)
		var out := false
		if frac >= 1.0 and ship.outside_hurt(uid):  # the part is whole, the outside half of its mount is not
			frac = float(inst["out_hp"]) / maxf(float(ship.components.outside_hp_max(inst["id"])), 1.0)
			out = true
		if frac < 1.0 and frac < best_frac:
			best = uid
			best_frac = frac
			best_out = out
	if best < 0:
		return _fail("nothing hurt within %s's reach" % m.name)
	var inst: Dictionary = ship.components.instances[best]
	if best_out:
		inst["out_hp"] = mini(int(inst["out_hp"]) + ceili(amount), ship.components.outside_hp_max(inst["id"]))
	else:
		inst["hp"] = minf(float(inst["hp"]) + amount, float(ship.effective(inst["id"])["hp"]))
		if inst["status"] == "disabled" and float(inst["hp"]) > 0.0:
			inst["status"] = "ok"
	ship.refresh()
	return _ok("%s patches the %s (+%d hp)" % [m.name, CrewFx.part_name(ship, best), roundi(amount)])


static func _extinguish(ship, m) -> Dictionary:
	var room: int = ship.atmosphere.room_at(m.cell())
	var out := 0
	for c in Fire.sorted_cells(ship.fires.keys()):
		if room >= 0 and ship.atmosphere.room_at(c) == room:
			Fire.extinguish(ship, c)
			out += 1
	if out == 0:
		return _fail("no fire in this room")
	return _ok("%s smothers %d fire%s" % [m.name, out, "" if out == 1 else "s"])


static func _seal_breach(ship, m, p: Dictionary) -> Dictionary:
	var reach := float(p.get("range", 8.0))
	var near: Array = []
	for c in Fire.sorted_cells(ship.grid.breached.keys()):
		var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_to(m.pos)
		if d <= reach:
			near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1].y < b[1].y or (a[1].y == b[1].y and a[1].x < b[1].x))))
	var sealed := 0
	for e in near.slice(0, maxi(int(p.get("count", 1)), 1)):
		if ship.grid.repair(e[1]):
			sealed += 1
	if sealed == 0:
		return _fail("no breach within %s's reach" % m.name)
	ship.mark_dirty()
	return _ok("%s seals %d breach%s" % [m.name, sealed, "" if sealed == 1 else "es"])


static func _shield_layer(ship, m, p: Dictionary) -> Dictionary:
	ship.refresh()
	var powered: Dictionary = ship.power_state.get("powered", {})
	var shield := false
	for uid in ship.components.instances:
		var def: Dictionary = ship.components.def(ship.components.instances[uid]["id"])
		if str(def.get("family", "")) == "shield" and powered.get(uid, false) and int(def.get("stats", {}).get("layers", 0)) > 0:
			shield = true
	if not shield:
		return _fail("no working shield to reinforce")
	CrewFx.add(ship, {"kind": "shield_layer", "layers": int(p.get("layers", 1)), "left": float(p.get("duration", 0.0)), "who": m.name})
	return _ok("%s reinforces the shield (+%d layer for %d s)" % [m.name, int(p.get("layers", 1)), roundi(float(p.get("duration", 0.0)))])


static func _scan(ship, m, p: Dictionary, enemy) -> Dictionary:
	CrewFx.add(ship, {"kind": "scan", "left": float(p.get("duration", 0.0)), "who": m.name})
	if enemy == null:
		return _ok("%s scans: hidden contacts show on the radar for %d s" % [m.name, roundi(float(p.get("duration", 0.0)))])
	var fam := {}
	for uid in enemy.components.instances:
		var f := str(enemy.components.def(enemy.components.instances[uid]["id"]).get("family", "part"))
		fam[f] = int(fam.get(f, 0)) + 1
	var names := fam.keys()
	names.sort()
	return _ok("%s scans %s: %s, %d crew" % [m.name, enemy.name, ", ".join(names.map(func(f): return "%d %s" % [fam[f], f])), enemy.crew.size()])


static func _hack(ship, m, p: Dictionary, enemy) -> Dictionary:
	if enemy == null:
		return _fail("there is no enemy to hack")
	var at_helm := false
	for uid in ship.manned:
		if ship.manned[uid] == m.name and ship.components.instances.has(uid) and str(ship.components.def(ship.components.instances[uid]["id"]).get("family", "")) == "helm":
			at_helm = true
	if not at_helm:
		return _fail("%s must be at the helm to hack" % m.name)
	enemy.refresh()
	var powered: Dictionary = enemy.power_state.get("powered", {})
	var uids: Array = enemy.components.instances.keys()
	uids.sort()
	var duration := float(p.get("duration", 0.0))
	for family in p.get("families", []):
		for uid in uids:
			var inst: Dictionary = enemy.components.instances[uid]
			if str(enemy.components.def(inst["id"]).get("family", "")) == str(family) and inst["status"] == "ok" and powered.get(uid, false) and not CrewFx.is_offline(enemy, uid):
				CrewFx.add(enemy, {"kind": "offline", "uid": uid, "left": duration, "who": m.name, "why": "hack"})
				return _ok("%s hacks the enemy's %s: offline for %d s" % [m.name, CrewFx.part_name(enemy, uid), roundi(duration)])
	return _fail("nothing on the enemy ship to hack")


static func _berserk(ship, m, p: Dictionary) -> Dictionary:
	CrewFx.add(ship, {"kind": "berserk", "who": m.name, "mult": float(p.get("mult", 2.0)), "left": float(p.get("duration", 0.0))})
	return _ok("%s goes berserk (melee x%s for %d s)" % [m.name, p.get("mult", 2.0), roundi(float(p.get("duration", 0.0)))])


## Step through the wall ahead (the way they face, along the nearer axis) to the first spot beyond it where a body fits.
static func _phase(ship, m, p: Dictionary) -> Dictionary:
	var f: Vector2 = m.facing
	var dir := Vector2i(1 if f.x >= 0.0 else -1, 0) if absf(f.x) >= absf(f.y) else Vector2i(0, 1 if f.y >= 0.0 else -1)
	var from: Vector2i = m.anchor()
	var blocked := false
	for k in range(1, int(p.get("range", 6)) + 1):
		var to := from + dir * k
		if not Pathfinder.body_ok(ship.grid, to, Callable(), m.body_size):
			blocked = true
		elif blocked and not _crowded(ship, m, to):
			m.pos = Pathfinder.centre_of(to, m.body_size)
			m.path.clear()
			m.job = {}
			return _ok("%s steps through the wall" % m.name)
	return _fail("no wall to step through there")


# --- targets -------------------------------------------------------------------------------------------

## The parts next to the body of `m` (a cell of the part within one step of a cell of the body), by uid.
static func _near_parts(ship, m) -> Array:
	var body: Array[Vector2i] = m.body_cells()
	var out := []
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var done := false
		for c in ship.components.instances[uid]["cells"]:
			for b in body:
				if absi(b.x - c.x) + absi(b.y - c.y) <= 1:
					done = true
					break
			if done:
				break
		if done:
			out.append(uid)
	return out


## `m` and the other crew in their room (just `m` when they stand in none).
static func _in_room(ship, m) -> Array:
	var room: int = ship.atmosphere.room_at(m.cell())
	var out := []
	for o in ship.crew:
		if o == m or (room >= 0 and ship.atmosphere.room_at(o.cell()) == room):
			out.append(o)
	return out


## Would a body on `anchor` overlap another crew member's?
static func _crowded(ship, m, anchor: Vector2i) -> bool:
	for o in ship.crew:
		if o != m:
			var a: Vector2i = o.anchor()
			if absi(a.x - anchor.x) < Pathfinder.BODY and absi(a.y - anchor.y) < Pathfinder.BODY:
				return true
	return false


# --- the checks of the data ---------------------------------------------------------------------------------

## Every problem in the ability data: the vocabulary, the `ability` of species, and all characters
## (data/characters.json and the packs'), one message each, naming the file and the id.
static func problems() -> Array[String]:
	var out: Array[String] = []
	var vocab := vocabulary()
	if vocab.is_empty():
		return [PATH + ": missing, or has no \"abilities\""]
	for id in vocab:
		out.append_array(_vocab_problems("%s: ability '%s'" % [PATH, id], vocab[id]))
	for s in Content.list("species"):
		if s.has("ability"):
			out.append_array(ability_problems(_at("species", s), s["ability"]))
	var names := {}
	for c in Content.list("characters"):
		out.append_array(character_problems(c))
		var who := str(c.get("name", ""))
		if names.has(who):
			out.append("%s: the name '%s' is also the name of '%s'" % [_at("characters", c), who, names[who]])
		names[who] = c["id"]
	return out


static func _at(kind: String, e: Dictionary) -> String:
	var file := Content.file_of(kind, str(e.get("id", "")))
	return "%s: %s '%s'" % [file if file != "" else "(inline data)", kind, e.get("id", "?")]


static func _vocab_problems(at: String, e) -> Array[String]:
	var out: Array[String] = []
	if not e is Dictionary:
		return [at + " must be an object"]
	for k in ["name", "blurb"]:
		if str(e.get(k, "")).strip_edges() == "":
			out.append("%s: has no %s" % [at, k])
	if str(e.get("tag", "")).length() != 2:
		out.append(at + ": tag must be two letters")
	if not _is_hex(e.get("color")):
		out.append(at + ": color must be #rrggbb")
	if not (_is_num(e.get("cooldown")) and float(e["cooldown"]) > 0.0):
		out.append(at + ": cooldown must be a number above 0")
	if not e.get("params") is Dictionary:
		out.append(at + ": params must be an object")
	else:
		for k in e["params"]:
			var v = e["params"][k]
			if not (_is_num(v) or (k == "families" and v is Array)):
				out.append("%s: param '%s' must be a number%s" % [at, k, " (or a list for families)" if k == "families" else ""])
	return out


## Problems in one `ability` entry ({id, cooldown?, params?}); `at` names where it is.
static func ability_problems(at: String, a) -> Array[String]:
	var out: Array[String] = []
	if not a is Dictionary:
		return [at + ": ability must be an object {id, cooldown?, params?}"]
	for k in a:
		if not ABILITY_KEYS.has(k):
			out.append("%s: ability has the unknown key '%s' (known: %s)" % [at, k, ", ".join(ABILITY_KEYS)])
	var base: Dictionary = vocabulary().get(str(a.get("id", "")), {})
	if base.is_empty():
		out.append("%s: ability '%s' is not in the vocabulary (%s)" % [at, a.get("id", ""), ", ".join(vocabulary().keys())])
		return out
	if a.has("cooldown") and not (_is_num(a["cooldown"]) and float(a["cooldown"]) > 0.0):
		out.append(at + ": ability cooldown must be a number above 0")
	if a.has("params"):
		if not a["params"] is Dictionary:
			out.append(at + ": ability params must be an object")
		else:
			for k in a["params"]:
				if not base.get("params", {}).has(k):
					out.append("%s: ability %s has no param '%s' (known: %s)" % [at, a["id"], k, ", ".join(base.get("params", {}).keys())])
				elif not (_is_num(a["params"][k]) or (k == "families" and a["params"][k] is Array)):
					out.append("%s: ability param '%s' must be a number" % [at, k])
	return out


## Problems in one character of data/characters.json (see its `_doc` for the schema).
static func character_problems(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var at := _at("characters", c)
	for k in c:
		if not CHARACTER_KEYS.has(k):
			out.append("%s: unknown key '%s' (known: %s)" % [at, k, ", ".join(CHARACTER_KEYS)])
	if not _is_snake(str(c.get("id", ""))):
		out.append(at + ": the id must be snake_case")
	for k in ["name", "obtained", "lore"]:
		if not (c.get(k) is String and str(c[k]).strip_edges() != ""):
			out.append("%s: %s must be text" % [at, k])
	var rig_base := "human"  # the art folder the look is on, to check the head frame against
	if c.has("species") == c.has("unique_species"):
		out.append(at + ": needs exactly one of species and unique_species")
	elif c.has("species"):
		if not (c["species"] is String and Content.has("species", c["species"])):
			out.append("%s: species '%s' is not in data/species.json" % [at, c["species"]])
		else:
			var sp := Content.entry("species", c["species"])
			rig_base = str(sp.get("rig", c["species"]))
	else:
		var u = c["unique_species"]
		if not u is Dictionary:
			out.append(at + ": unique_species must be an object")
		else:
			out.append_array(_unique_problems(at + " unique_species", u))
			rig_base = str(u.get("rig", "human"))
	if c.has("rig"):
		out.append_array(_rig_problems(at, c["rig"], rig_base))
	if c.has("traits"):
		out.append_array(_traits_problems(at + " traits", c["traits"]))
	if not c.has("ability"):
		out.append(at + ": needs an ability")
	else:
		out.append_array(ability_problems(at, c["ability"]))
	return out


static func _unique_problems(at: String, u: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in u:
		if not SPECIES_KEYS.has(k) and not TraitSet.KEYS.has(k):
			out.append("%s: unknown key '%s'" % [at, k])
	if str(u.get("name", "")).strip_edges() == "":
		out.append(at + ": needs a name")
	for k in ["hp", "speed"]:
		if not (_is_num(u.get(k)) and float(u[k]) > 0.0):
			out.append("%s: %s must be a number above 0" % [at, k])
	if u.has("traits"):
		out.append_array(_traits_problems(at + " traits", u["traits"], true))
	out.append_array(_key_problems(at, u))
	if u.has("rig") and not (u["rig"] is String and FileAccess.file_exists("%s%s/crew.json" % [ART_CREW, u["rig"]])):
		out.append("%s: rig '%s' has no art folder art/crew/<rig>/ with a crew.json" % [at, u["rig"]])
	if u.has("sidearm") and not Content.has("hand_weapons", str(u["sidearm"])):
		out.append("%s: sidearm '%s' is not in data/hand_weapons.json" % [at, u["sidearm"]])
	return out


static func _rig_problems(at: String, rig, base: String) -> Array[String]:
	var out: Array[String] = []
	if not rig is Dictionary:
		return [at + ": rig must be an object {tint?, head?}"]
	for k in rig:
		if not RIG_KEYS.has(k):
			out.append("%s: rig has the unknown key '%s' (known: %s)" % [at, k, ", ".join(RIG_KEYS)])
	if rig.has("tint") and not _is_hex(rig["tint"]):
		out.append(at + ": rig tint must be #rrggbb")
	if rig.has("head"):
		var file := "%s%s/crew.json" % [ART_CREW, base]
		var frames := {}
		if FileAccess.file_exists(file):
			var d = JSON.parse_string(FileAccess.get_file_as_string(file))
			if d is Dictionary:
				var layers = d.get("layers", d)
				frames = layers.get("head", {}).get("frames", {}) if layers is Dictionary and layers.get("head") is Dictionary else {}
			if not (rig["head"] is String and frames.has(rig["head"])):
				out.append("%s: rig head '%s' is not a head frame of art/crew/%s (%s)" % [at, rig["head"], base, ", ".join(frames.keys())])
	return out


## Personal traits: a list of ids of the trait library, or (when `ids_only` is false) an object of trait keys.
static func _traits_problems(at: String, t, ids_only := false) -> Array[String]:
	var out: Array[String] = []
	if t is Array:
		for id in t:
			if not TraitSet.library().has(str(id)):
				out.append("%s: trait '%s' is not defined" % [at, id])
	elif t is Dictionary and not ids_only:
		for k in t:
			if not TraitSet.KEYS.has(k):
				out.append("%s: unknown trait key '%s' (known: %s)" % [at, k, ", ".join(TraitSet.KEYS.keys())])
		out.append_array(_key_problems(at, t))
	else:
		out.append(at + (" must be a list of trait ids" if ids_only else " must be a list of trait ids or an object of trait keys"))
	return out


## The trait keys of `e` (the known ones only) hold numbers, in the groups' own sub-keys.
static func _key_problems(at: String, e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in e:
		if not TraitSet.KEYS.has(k):
			continue
		var subs: Array = TraitSet.KEYS[k]
		var v = e[k]
		if TraitSet.OPEN.has(k):
			out.append_array(TraitSet.extra_problems(at, k, v))
		elif subs.is_empty():
			var flag: bool = TraitSet.FLAGS.has(k)
			if not (v is bool if flag else _is_num(v)):
				out.append("%s: '%s' must be %s" % [at, k, "true or false" if flag else "a number"])
			elif k == "body" and not TraitSet.BODIES.has(int(v)):
				out.append("%s: 'body' must be %s" % [at, " or ".join(TraitSet.BODIES.map(func(b): return str(b)))])
			else:
				out.append_array(TraitSet.extra_problems(at, k, v))
		elif not v is Dictionary:
			out.append("%s: '%s' must be an object of %s" % [at, k, ", ".join(subs)])
		else:
			for sub in v:
				if not subs.has(sub):
					out.append("%s: '%s' has the unknown key '%s' (known: %s)" % [at, k, sub, ", ".join(subs)])
				elif not _is_num(v[sub]):
					out.append("%s: '%s.%s' must be a number" % [at, k, sub])
			out.append_array(TraitSet.extra_problems(at, k, v))
	return out


static func _is_num(v) -> bool:
	return v is float or v is int


static func _is_hex(v) -> bool:
	return v is String and v.length() == 7 and v.begins_with("#") and v.substr(1).is_valid_hex_number()


static func _is_snake(id: String) -> bool:
	if id == "" or not (id[0] >= "a" and id[0] <= "z"):
		return false
	for ch in id:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true
