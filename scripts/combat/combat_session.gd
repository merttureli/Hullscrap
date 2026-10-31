extends RefCounted
## The playable fight, headless: an arena with the player's ship (index 0) and one enemy (index 1)
## flown by the pilot AI, the weapon groups and slots, the end of the fight and the camera framing.
## combat_view.gd draws it and feeds it input; every rule lives here so tests can drive it.
## The ships' power, heat, oxygen and reliability keep running in ShipSim (the same Ship objects).

const Abilities = preload("res://scripts/sim/abilities.gd")
const Arena = preload("res://scripts/combat/arena.gd")
const Morale = preload("res://scripts/combat/morale.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

const PIRATE_PATH := "res://data/ships/pirate_raider.json"
const RAMMER_PATH := "res://data/ships/rustfang_rammer.json"  ## the test rammer (Shift+K in the combat view)
const PLAYER := 0
const ENEMY := 1
const SPAWN_DISTANCE := 1200.0  ## px the enemy starts ahead of the player
const LEAVE_DISTANCE := 4000.0  ## px apart at which Esc lets the player disengage
const JUMP_SPOOL := 10.0  ## seconds the jump drive spools (J) before the player can leave a fight anywhere
const STEP := 1.0 / 60.0
const MAX_TICKS := 8  ## substeps one frame may run, so a stall does not snowball
const STEER_MIN_DISTANCE := 48.0  ## px: a cursor closer to the ship than this does not turn it
const WON_TEXT := "Pirate wrecked. Esc to return"
const LOST_TEXT := "Your ship is wrecked. R to restart"
const CAPTURED_TEXT := "Nobody is left standing aboard. She's yours. Esc to return"
const SPARED_TEXT := "Deal struck. Pirate limps away. Esc to return"
const ESCAPED_TEXT := "They got away. Esc to return"
const ESCAPE_LOOK_S := 1.5  ## seconds the camera keeps the place the enemy jumped from in view

var arena: Arena
var ai: PilotAI
var morale: Morale  ## the enemy's morale (morale.gd): surrender, flight, capture
var jump_charge := -1.0  ## seconds the jump drive has spooled (J); -1 while it is not spooling
var input := {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}  ## the player's keys, set by the view: W/S throttle, A/D "turn" (keys steering) or "strafe" (mouse steering)
var cursor: Variant = null  ## the world point the mouse is on, set by the view each frame; the ship turns toward it (mouse steering) and the fixed guns' barrels follow it. null: keys steering, barrels at rest
var enemy_label := "Pirate"
var _acc := 0.0


## A ship from a saved-ship JSON file (Ship.to_dict format), or null when it cannot be loaded. A
## design's `ai` entry ({"style": "rammer"}) is kept on the ship as the meta value "ai" and read by start().
static func load_ship(path: String) -> Ship:
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary and d.get("size") is Array):
		return null
	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new("Ship", ShipGrid.new(Vector2i(int(d["size"][0]), int(d["size"][1])), defs))
	if ship.load_dict(d) != "":
		return null
	if d.get("ai") is Dictionary:
		ship.set_meta("ai", d["ai"])
	return ship


## The test rammer enemy (data/ships/rustfang_rammer.json), or null when it cannot be loaded. The
## combat view starts the fight with `enter(Session.RAMMER_PATH)`.
static func spawn_rammer() -> Ship:
	return load_ship(RAMMER_PATH)


## Put `player` at the origin and `enemy` SPAWN_DISTANCE ahead of it (up), facing it. `seed_value`
## seeds every roll of the fight and the pilot.
func start(player: Ship, enemy: Ship, seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(player, Vector2.ZERO, 0.0)
	arena.add_ship(enemy, Vector2(0.0, -SPAWN_DISTANCE), PI)
	ai = PilotAI.new(arena, ENEMY, PLAYER, enemy.get_meta("ai", {}))
	morale = Morale.new(arena, ENEMY, PLAYER, str(enemy.get_meta("ai", {}).get("morale", "default")))
	ai.morale = morale
	input = {"throttle": 0.0, "turn": 0.0, "strafe": 0.0}
	cursor = null
	_acc = 0.0


## Run `dt` seconds in fixed substeps: the player's helm, the pilot, then the arena.
## J in a fight: start spooling the jump drive. "" when it starts, else why not.
func start_jump() -> String:
	if jump_charge >= 0.0:
		return "The jump drive is already spooling"
	if state() != "fighting":
		return "No need to jump now"
	jump_charge = 0.0
	return ""


## True once the jump drive has spooled: the player can leave at any range.
func jump_ready() -> bool:
	return jump_charge >= JUMP_SPOOL


func tick(dt: float) -> void:
	_acc = minf(_acc + dt, MAX_TICKS * STEP)
	while _acc >= STEP - 1e-9:
		_acc -= STEP
		var helm := helm_input()
		arena.set_input(PLAYER, helm["throttle"], helm["turn"], helm["strafe"])
		if cursor != null:
			arena.aim_points[PLAYER] = cursor
		ai.think(STEP)
		arena.step(STEP)
		morale.tick(STEP)
		if jump_charge >= 0.0 and state() == "fighting":
			jump_charge += STEP


## The helm the player's ship gets this substep. Mouse steering (data/flight.json controls.steer, with
## a cursor): the ship turns toward the cursor at its turn rate and A/D strafe. Keys steering (or no
## cursor yet): A/D turn, no strafe.
func helm_input() -> Dictionary:
	var co = arena.ships[PLAYER]
	var throttle := float(input.get("throttle", 0.0))
	if cursor != null and co.flight.steer == "mouse":
		var to: Vector2 = cursor - co.flight.pos
		var turn := 0.0
		if to.length() > STEER_MIN_DISTANCE:
			turn = co.flight.steer_toward(to.angle() + PI / 2.0, co.mass, co.thrust)
		return {"throttle": throttle, "turn": turn, "strafe": float(input.get("strafe", 0.0))}
	return {"throttle": throttle, "turn": float(input.get("turn", 0.0)), "strafe": 0.0}


## T: the player's turrets fire by themselves, or hold fire. Returns whether they autofire now.
func toggle_autofire() -> bool:
	arena.autofire[PLAYER] = not arena.autofire.get(PLAYER, true)
	return arena.autofire[PLAYER]


## "fighting", "won" (the enemy is wrecked), "captured" (its crew is all down), "spared" (the player took its
## surrender), "escaped" (its jump drive finished) or "lost" (the player is wrecked; this wins over all).
func state() -> String:
	if arena.ships[PLAYER].wrecked:
		return "lost"
	if arena.ships[ENEMY].wrecked:
		return "won"
	return morale.end_state() if morale != null else "fighting"


## Y: take the enemy's surrender offer. "" when taken (the fight ends "spared"), else why not.
func accept_surrender() -> String:
	return morale.accept() if state() == "fighting" else "The fight is over"


## The line for the end of the fight ("" while it goes on).
func end_text() -> String:
	match state():
		"won":
			return WON_TEXT.replace("Pirate", enemy_label)
		"lost":
			return LOST_TEXT
		"captured":
			return CAPTURED_TEXT
		"spared":
			return SPARED_TEXT.replace("Pirate", enemy_label)
		"escaped":
			return ESCAPED_TEXT
	return ""


func distance() -> float:
	return arena.ships[PLAYER].flight.pos.distance_to(arena.ships[ENEMY].flight.pos)


## May the player leave (Esc)? Once the enemy is wrecked, captured, spared or gone, or when the two are far apart.
func can_leave() -> bool:
	return arena.ships[ENEMY].wrecked or morale.end_state() != "fighting" or distance() > LEAVE_DISTANCE or jump_ready()


## The player's weapons in slot order: [{uid, id, name, group, turret}]: placed ones by uid, then virtual mounts as added.
func weapons() -> Array:
	var co = arena.ships[PLAYER]
	var uids: Array = co.mounts.keys()
	uids.sort_custom(func(a, b): return a < b if (a < 0) == (b < 0) and a >= 0 else (a > b if (a < 0) == (b < 0) else a >= 0))
	var out := []
	for uid in uids:
		var m: Dictionary = co.mounts[uid]
		var name := str(m["id"])
		if not m["virtual"]:
			name = str(co.ship.components.def(co.ship.components.instances[uid]["id"]).get("name", name))
		out.append({"uid": uid, "id": m["id"], "name": name, "group": arena.weapons.group_of(m["id"]), "turret": bool(arena.weapons.def(m["id"])["turret"])})
	return out


## Fire every weapon of fire group `group` at the world point `aim`. Returns how many fired.
func fire_group(group: int, aim: Vector2) -> int:
	var n := 0
	for w in weapons():
		if w["group"] == group and arena.fire(PLAYER, w["uid"], aim):
			n += 1
	return n


## Fire weapon slot `slot` (1 = the first). False when there is none or it cannot fire.
func fire_slot(slot: int, aim: Vector2) -> bool:
	var list := weapons()
	return slot >= 1 and slot <= list.size() and arena.fire(PLAYER, list[slot - 1]["uid"], aim)


## What the weapon bar shows for the player's weapon `uid` aiming at `aim`: {cooldown_left, cooldown,
## status ("ready", "cooling down", "out of arc" (a turret), "no target", "unpowered", "no ammo", "malfunction",
## "overheated", "disabled" (an outside half shot out), "offline" (a cut link), "wrecked"), in_arc (the
## point is inside the gun's gimbal cone, or the turret's arc), turret, hit (a turret's chance to hit the
## enemy, 0..1; -1 for a fixed gun)}.
func slot_state(uid: int, aim: Vector2) -> Dictionary:
	var m: Dictionary = arena.ships[PLAYER].mounts[uid]
	var why: String = arena.weapons.can_fire(arena, PLAYER, uid, aim)
	var in_arc: bool = arena.weapons.in_arc(arena, PLAYER, m, aim)
	var turret: bool = arena.weapons.def(m["id"])["turret"]
	return {"cooldown_left": arena.cooldown_left(PLAYER, uid), "cooldown": float(arena.weapons.def(m["id"])["cooldown"]),
		"status": "ready" if why == "" else why, "in_arc": in_arc, "turret": turret,
		"hit": arena.weapons.hit_chance(arena, PLAYER, uid, ENEMY) if turret else -1.0}


## The player's ability slots in key order (Abilities.slots): [{uid, id, slot, key, name, part, ability}].
func ability_slots() -> Array:
	return Abilities.slots(arena.ships[PLAYER].ship)


## The player presses ability key `key` ("engine" Shift, "shield" Space, "utility" Q): every ability
## with that key starts if it can. Returns {"started": [slot ids], "refused": {slot id: reason}}.
func press_ability(key: String) -> Dictionary:
	return arena.use_key(PLAYER, key)


## What the bar shows for ability slot `s` (an ability_slots() entry): {state ("active", "cooling",
## "blocked" or "ready"), active_left, duration, cooldown_left, cooldown, reason}. `reason` is why it
## cannot start now ("" when it can or is running).
func ability_state(s: Dictionary) -> Dictionary:
	var co = arena.ships[PLAYER]
	var left := Abilities.active_left(co.ship, s["uid"], s["id"])
	var cd := Abilities.cooldown_left(co.ship, s["uid"], s["id"])
	var why := "wrecked" if co.wrecked else Abilities.can_trigger(co.ship, s["uid"], s["id"])
	var state := "ready"
	if left > 0.0:
		state = "active"
	elif cd > 0.0:
		state = "cooling"
	elif why != "":
		state = "blocked"
	return {"state": state, "active_left": left, "duration": float(s["ability"].get("duration", 0.0)), "cooldown_left": cd,
		"cooldown": float(s["ability"].get("cooldown", 0.0)), "reason": "" if state in ["active", "ready"] else why}


## The player presses an arrow key: one step of shield balance toward "up" (bow), "down" (stern), "left"
## (port) or "right" (starboard). "" when it moved, else why not.
func shift_shield(dir: String) -> String:
	return Shields.shift(arena.ships[PLAYER], dir)


## The player presses End: every sector back to weight 1. The losers drop at once, the gainers recharge.
func reset_shield() -> void:
	Shields.reset_even(arena.ships[PLAYER])


## What the shield diagram shows: one entry per sector of the player's bubble, bow first, clockwise:
## {layers, cap, weight, open, filling}. Empty with no shield generator.
func shield_sectors() -> Array:
	var co = arena.ships[PLAYER]
	var out := []
	if co.layers_cap <= 0:
		return out
	for s in co.sectors:
		out.append(Shields.sector_state(co, s, arena.tick))
	return out


## Where the camera should be and how far to zoom so both ships fit a viewport of `view` px:
## {center, zoom}. `margin`: the fraction of the screen kept free.
func framing(view: Vector2, margin := 0.2) -> Dictionary:
	var a = arena.ships[PLAYER]
	var b = arena.ships[ENEMY]
	var b_pos: Vector2 = b.flight.pos
	if morale.state == "escaped":  # it jumped away: the camera keeps the place a moment, then the player alone
		b_pos = morale.escape_pos if arena.time() - morale.escape_time < ESCAPE_LOOK_S else a.flight.pos
	var reach_a: float = (Shields.reach(a) + 1.0) * arena.CELL
	var reach_b: float = (Shields.reach(b) + 1.0) * arena.CELL
	var centre: Vector2 = (a.flight.pos + b_pos) / 2.0
	var half: Vector2 = (a.flight.pos - b_pos).abs() / 2.0 + Vector2.ONE * maxf(reach_a, reach_b)
	var zoom := minf(view.x / (2.0 * half.x), view.y / (2.0 * half.y)) * (1.0 - margin)
	return {"center": centre, "zoom": clampf(zoom, 0.05, 1.0)}
