extends RefCounted
## Enemy morale: the ways a fight ends besides the wreck (structure under the defeat line) (data/morale.json, README "Combat"). A losing
## enemy breaks once: structure at or under `break_structure`, or no weapon able to fire for `unarmed_s`. It then rolls
## its style (surrender / flee / fight weights) with the arena's seeded rng.
## - surrender ("offering"): the pilot holds fire and cuts throttle, and the offer (credits, an extra, now and
##   then a part) stands for `offer_s`. accept() ("spared") takes it; damage dealt to the enemy, or the time
##   running out, makes it "fighting_on": it fights to the end and morale never triggers again. The player's
##   turrets hold fire while it stands (a turret hit would refuse it) and go back to how they were after.
## - flee ("fleeing"): the pilot burns away stern to the player (pilot_ai.gd) while the jump drive charges for
##   `spool_s` (a style may set its own); the charge holds by spool_hold(): every engine out, the helm down or every crew
##   member down (the same rule holds the player's own J spool, combat_session.gd). Full: "escaped", the ship is moved
##   `escape_distance` px away and stopped. A style with `fades` (the Hollow's ghosts) flees every time and quicker: it
##   thins back into the Hollow, which Campaign.fight_done counts as a won fight with nothing to salvage.
## - captured: the enemy had crew aboard and all of it is down (or gone) for `captured_s`: guns and helm stop.
## The session ticks it every substep after the arena; the pilot reads pilot_mode(). No nodes, no drawing.

const Ammo = preload("res://scripts/sim/ammo.gd")
const CONFIG_PATH := "res://data/morale.json"
const END_STATES: Array[String] = ["spared", "escaped", "captured"]
const DAMAGE_EVENTS: Array[String] = ["hit", "shield", "deflect", "ricochet"]  ## arena events on the enemy that are the player's attack

static var _config := {}  # data/morale.json, read on first use

var arena
var enemy: int
var player: int
var style := "default"
var cfg: Dictionary
var state := "steady"  ## steady, offering, fleeing, spared, escaped, captured or fighting_on
var offer := {}  ## item id -> count: what the enemy pays (offering, and spared)
var offer_left := 0.0  ## seconds the offer still stands
var spool := 0.0  ## seconds the jump drive has charged (fleeing)
var escape_pos := Vector2.ZERO  ## where the enemy was when it jumped away (escaped)
var escape_time := -1.0  ## the arena time it jumped
var refused_at := -1.0  ## arena time the offer was refused (fighting_on after an offer), else -1
var rolls := 0  ## style rolls made: one per fight at most
var faction := ""  ## the faction of a generated enemy (its ai `faction`), whose lines in cfg["lines"] it says; "" for an authored design
var captain := ""  ## the name of its captain (the `captain` of its ai, else the first of its crew plan) when it has a faction

var _unarmed := 0.0  # seconds with no weapon able to fire
var _down := 0.0  # seconds every crew member has been down
var _had_crew := false  # crew has been seen aboard (the sim spawns an enemy's crew on its first tick)
var _spent: Array = []  # the player's shots in flight when the offer began: their hits are no refusal
var _cursor := 0  # arena events read so far
var _player_auto := true  # the player's turret autofire before the offer


## data/morale.json as a Dictionary (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary:
			_config = data
	return _config


## `style`: a key of cfg["styles"] (an unknown one uses "default"); `cfg`: a variant of config() (default: config() itself).
func _init(p_arena, p_enemy: int, p_player: int, p_style := "default", p_cfg := {}) -> void:
	arena = p_arena
	enemy = p_enemy
	player = p_player
	style = p_style
	cfg = p_cfg if not p_cfg.is_empty() else config()
	_cursor = arena.events.size()
	var ship = arena.ships[enemy].ship
	var ai: Dictionary = ship.get_meta("ai", {})
	faction = str(ai.get("faction", ""))
	if faction != "":
		captain = str(ai.get("captain", ship.crew_plan[0]["name"] if not ship.crew_plan.is_empty() else ""))


## The style's entry of cfg["styles"] (an unknown style uses "default").
func _style_cfg() -> Dictionary:
	var styles: Dictionary = cfg["styles"]
	return styles.get(style, styles["default"])


## The style's weights: {surrender, flee, fight}.
func weights() -> Dictionary:
	var s := _style_cfg()
	return {"surrender": float(s.get("surrender", 0.0)), "flee": float(s.get("flee", 0.0)), "fight": float(s.get("fight", 0.0))}


## Seconds this enemy's jump drive spools when it flees: the style's own `spool_s`, else morale.json's.
func spool_total() -> float:
	return float(_style_cfg().get("spool_s", cfg["spool_s"]))


## Does this enemy fade when it flees (a Hollow ghost thins back into the Hollow)?
func fades() -> bool:
	return bool(_style_cfg().get("fades", false))


## Does a ship of morale style `style` (the `morale` of its ai) fade when it flees? (data/morale.json)
static func fades_style(style: String) -> bool:
	var styles: Dictionary = config().get("styles", {})
	var s = styles.get(style, {})
	return s is Dictionary and bool(s.get("fades", false))


## Roll the style: "surrender", "flee" or "fight" (the last when every weight is 0).
func roll_style() -> String:
	rolls += 1
	var w := weights()
	var total: float = w["surrender"] + w["flee"] + w["fight"]
	var r: float = arena.rng.randf() * total
	if r < w["surrender"]:
		return "surrender"
	return "flee" if r < w["surrender"] + w["flee"] else "fight"


## "spared", "escaped" or "captured" once the fight is over that way, else "fighting".
func end_state() -> String:
	return state if state in END_STATES else "fighting"


## What the enemy pilot does now: "" (fights), "hold" (no fire, no throttle), "flee" (stern to the player,
## full burn, guns still fire when they bear) or "stop" (captured, spared or gone).
func pilot_mode() -> String:
	match state:
		"offering":
			return "hold"
		"fleeing":
			return "flee"
		"spared", "captured", "escaped":
			return "stop"
	return ""


## Advance `dt` seconds (the session calls it each substep, after the arena stepped).
func tick(dt: float) -> void:
	if state in END_STATES or arena.ships[enemy].wrecked or arena.ships[player].wrecked:
		return
	_watch_crew(dt)
	match state:
		"steady":
			_watch_break(dt)
		"offering":
			_tick_offer(dt)
		"fleeing":
			_tick_flee(dt)


## Y: take the offer. "" when taken (the fight ends "spared"), else why not.
func accept() -> String:
	if state != "offering":
		return "Nobody is offering anything"
	state = "spared"
	_stand_down()
	return ""


## The line for the HUD banner ("" for none): the hail, the offer with its hail, the spool, the refusal. A generated
## enemy speaks in its faction's words (data/morale.json lines) as "Captain Vex of the Dental Plan"; an authored design
## keeps the plain lines.
func banner() -> String:
	var who := speaker()
	match state:
		"steady":
			var window: Array = cfg.get("hail_s", [])
			var hail := say("hail")
			if hail != "" and window.size() == 2 and arena.time() >= float(window[0]) and arena.time() < float(window[1]):
				return "%s hails: '%s'" % [who, hail]
		"offering":
			return "%s hails: '%s' Offer: %s. Y accept / keep firing to refuse (%d s)" % [who, say("surrender", "Enough! Take it and let us go."), offer_text(), ceili(offer_left)]
		"fleeing":
			var cry := say("flee")
			var what := "Fading back into the Hollow!" if fades() else "Spooling its jump drive!"
			if cry != "":
				return "%s: '%s' %s Knock out its engines or helm" % [who, cry, what]
			return "%s is %s%s Knock out its engines or helm" % [who, what.substr(0, 1).to_lower(), what.substr(1)]
		"fighting_on":
			if refused_at >= 0.0 and arena.time() - refused_at < float(cfg["refused_banner_s"]):
				var no := say("refuse")
				return "%s: '%s'" % [who, no] if no != "" else "They take that as a no"
	return ""


## Who speaks for the enemy: "Captain Vex of the Dental Plan" for a ship with a faction that names a captain, else "The <ship>".
func speaker() -> String:
	var ship_name := str(arena.ships[enemy].ship.name)
	var title := str(_lines().get("title", ""))
	if title != "" and captain != "":
		return "%s %s of the %s" % [title, captain, ship_name.trim_prefix("The ")]
	return ship_name if ship_name.begins_with("The ") else "The " + ship_name


## One `kind` line (hail, surrender, flee or refuse) of the enemy's faction, picked by the hash of its ship's name so it always
## says the same one; `fallback` when the faction has none (an authored design).
func say(kind: String, fallback := "") -> String:
	var pool = _lines().get(kind, [])
	if not (pool is Array) or pool.is_empty():
		return fallback
	var ship_name := str(arena.ships[enemy].ship.name)
	return str(pool[(ship_name + kind).hash() % pool.size()]).format({"captain": captain, "ship": ship_name})


func _lines() -> Dictionary:
	var all = cfg.get("lines", {})
	var mine = all.get(faction, {}) if all is Dictionary and faction != "" else {}
	return mine if mine is Dictionary else {}


## The offer in words: "45 credits, 2 missiles".
func offer_text() -> String:
	var bits: Array[String] = []
	for id in offer:
		var n: int = offer[id]
		match id:
			"credits":
				bits.append("%d credits" % n)
			"fuel":
				bits.append("%d fuel" % n)
			"missile":
				bits.append("%d missile%s" % [n, "" if n == 1 else "s"])
			_:
				var comps = arena.ships[enemy].ship.components
				var nm: String = str(comps.def(id).get("name", id)) if comps.has(id) else str(id)
				bits.append(nm if n == 1 else "%d x %s" % [n, nm])
	return ", ".join(bits)


## Why the enemy's jump drive is not charging ("" when it is): see spool_hold().
func hold() -> String:
	return spool_hold(arena, enemy)


## Why the jump drive of ship `idx` cannot charge, for a fleeing enemy and the player's J alike: "engines out"
## (every engine disabled, offline or unpowered, or none), "helm down" (no helm, or none working and powered) or
## "no crew" (crew aboard and every one down, or all of them dead); "" when it charges. Things the player can
## cause and see; whether somebody happens to stand at the helm does not count. A ship with an empty crew list and
## nobody dead (the arena alone spawns no crew) is not "no crew".
static func spool_hold(arena, idx: int) -> String:
	var co = arena.ships[idx]
	var comps = co.ship.components
	var engine := false
	var helm := false
	for uid in comps.instances:
		var inst: Dictionary = comps.instances[uid]
		var family: String = comps.def(inst["id"]).get("family", "")
		if family != "engine" and family != "helm":
			continue
		if inst.get("status", "ok") != "ok" or not co.powered.get(uid, false) or comps.offline_reason(co.ship.grid, uid) != "":
			continue
		engine = engine or family == "engine"
		helm = helm or family == "helm"
	if not engine:
		return "engines out"
	if not helm:
		return "helm down"
	var crew: Array = co.ship.crew
	if (not crew.is_empty() or not co.ship.dead_crew.is_empty()) and crew.all(func(m): return m.is_down()):
		return "no crew"
	return ""


# --- the break ----------------------------------------------------------------------------------------

func _watch_break(dt: float) -> void:
	var co = arena.ships[enemy]
	_unarmed = 0.0 if _can_shoot() else _unarmed + dt
	if co.structure <= float(cfg["break_structure"]) + 1e-6 or _unarmed >= float(cfg["unarmed_s"]) - 1e-6:
		match roll_style():
			"surrender":
				_begin_offer()
			"flee":
				state = "fleeing"
			_:
				state = "fighting_on"


## Has the enemy a weapon that could fire (working, powered, with ammo)?
func _can_shoot() -> bool:
	var co = arena.ships[enemy]
	for uid in co.mounts:
		var m: Dictionary = co.mounts[uid]
		if arena.weapons.status_of(arena, enemy, uid) != "ok" or not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
			continue
		var ammo := str(arena.weapons.def(m["id"])["ammo"])
		if ammo == "" or Ammo.can_supply(co.ship, uid, ammo, 1):
			return true
	return false


# --- surrender ----------------------------------------------------------------------------------------

func _begin_offer() -> void:
	state = "offering"
	offer_left = float(cfg["offer_s"])
	offer = _roll_offer()
	_spent = arena.projectiles.filter(func(p): return p["owner"] == player)
	_cursor = arena.events.size()
	arena.autofire[enemy] = false
	_player_auto = bool(arena.autofire.get(player, true))
	arena.autofire[player] = false


## credits, one extra and maybe an intact part: item id -> count.
func _roll_offer() -> Dictionary:
	var o: Dictionary = _style_cfg().get("offer", cfg["offer"])  # a style may make its own offer (a flagship's, data/morale.json)
	var out := {"credits": arena.rng.randi_range(int(o["credits"][0]), int(o["credits"][1]))}
	var extras: Array = o["extra"]
	if not extras.is_empty():
		var x: Dictionary = extras[arena.rng.randi() % extras.size()]
		out[str(x["item"])] = arena.rng.randi_range(int(x["count"][0]), int(x["count"][1]))
	if arena.rng.randf() < float(o["part_chance"]):
		var ids := _intact_parts()
		if not ids.is_empty():
			var id: String = ids[arena.rng.randi() % ids.size()]
			out[id] = int(out.get(id, 0)) + 1
	return out


## The ids of the enemy's parts that still work, in uid order.
func _intact_parts() -> Array[String]:
	var comps = arena.ships[enemy].ship.components
	var uids: Array = comps.instances.keys()
	uids.sort()
	var out: Array[String] = []
	for uid in uids:
		var inst: Dictionary = comps.instances[uid]
		if float(inst.get("hp", 1)) > 0.0 and inst.get("status", "ok") != "disabled" and (inst["out_cells"].is_empty() or float(inst["out_hp"]) > 0.0):
			out.append(str(inst["id"]))
	return out


func _tick_offer(dt: float) -> void:
	offer_left -= dt
	var shielded := not _spent.is_empty()  # shots already flying when it broke may still land
	while _cursor < arena.events.size():
		var e: Dictionary = arena.events[_cursor]
		_cursor += 1
		if not shielded and _is_attack(e):
			offer_left = 0.0
	if shielded:
		_spent = _spent.filter(func(p): return arena.projectiles.any(func(q): return is_same(p, q)))
	if offer_left <= 0.0:
		state = "fighting_on"  # "They take that as a no"
		refused_at = arena.time()
		arena.autofire.erase(enemy)
		arena.autofire[player] = _player_auto


## Is event `e` the player hurting the enemy (a hit or a shield hit on it, or a ram)?
func _is_attack(e: Dictionary) -> bool:
	if e["type"] == "ram":
		return int(e.get("a", -1)) == enemy or int(e.get("b", -1)) == enemy
	return int(e["ship"]) == enemy and e["type"] in DAMAGE_EVENTS and not e.get("hazard", false)  # a surge hit is no refusal


# --- flight -------------------------------------------------------------------------------------------

func _tick_flee(dt: float) -> void:
	if hold() == "":
		spool += dt
	if spool >= spool_total() - 1e-6:
		_escape()


## The jump drive is charged: the enemy is gone, far away along the line from the player and at rest.
func _escape() -> void:
	var co = arena.ships[enemy]
	escape_pos = co.flight.pos
	escape_time = arena.time()
	arena.log_event("escape", enemy, Vector2i(-1, -1), {"angle": co.flight.angle})
	var away: Vector2 = co.flight.pos - arena.ships[player].flight.pos
	co.flight.pos += (away.normalized() if away.length_squared() > 1.0 else Vector2.UP) * float(cfg["escape_distance"])
	co.flight.vel = Vector2.ZERO
	co.flight.ang_vel = 0.0
	state = "escaped"
	_stand_down()


# --- capture ------------------------------------------------------------------------------------------

## Crew aboard and all of it down (or gone) for `captured_s`: the ship goes dark.
func _watch_crew(dt: float) -> void:
	var crew: Array = arena.ships[enemy].ship.crew
	_had_crew = _had_crew or not crew.is_empty()
	if not _had_crew:
		return
	if not crew.all(func(m): return m.is_down()):
		_down = 0.0
		return
	_down += dt
	if _down >= float(cfg["captured_s"]) - 1e-6:
		state = "captured"
		_stand_down()


## The fight is over (spared, escaped, captured): nobody fires, the enemy's helm lets go.
func _stand_down() -> void:
	arena.autofire[enemy] = false
	arena.autofire[player] = false
	arena.set_input(enemy, 0.0, 0.0)
