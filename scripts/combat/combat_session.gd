extends RefCounted
## The playable fight, headless: an arena with the player's ship (index 0) and one enemy (index 1)
## flown by the pilot AI, the weapon groups and slots, the end of the fight and the camera framing.
## combat_view.gd draws it and feeds it input; every rule lives here so tests can drive it.
## The ships' power, heat, oxygen and reliability keep running in ShipSim (the same Ship objects).

const Arena = preload("res://scripts/combat/arena.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")

const PIRATE_PATH := "res://data/ships/pirate_raider.json"
const PLAYER := 0
const ENEMY := 1
const SPAWN_DISTANCE := 1200.0  ## px the enemy starts ahead of the player
const LEAVE_DISTANCE := 4000.0  ## px apart at which Esc lets the player disengage
const STEP := 1.0 / 60.0
const MAX_TICKS := 8  ## substeps one frame may run, so a stall does not snowball
const WON_TEXT := "Pirate wrecked. Salvage comes later. Esc to return"
const LOST_TEXT := "Your ship is wrecked. R to restart"

var arena: Arena
var ai: PilotAI
var input := {"throttle": 0.0, "turn": 0.0}  ## the player's helm, set by the view
var enemy_label := "Pirate"
var _acc := 0.0


## A ship from a saved-ship JSON file (Ship.to_dict format), or null when it cannot be loaded.
static func load_ship(path: String) -> Ship:
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary and d.get("size") is Array):
		return null
	var defs := TileDefs.new()
	defs.load_file(Ship.TILES_PATH)
	var ship := Ship.new("Ship", ShipGrid.new(Vector2i(int(d["size"][0]), int(d["size"][1])), defs))
	return ship if ship.load_dict(d) == "" else null


## Put `player` at the origin and `enemy` SPAWN_DISTANCE ahead of it (up), facing it. `seed_value`
## seeds every roll of the fight and the pilot.
func start(player: Ship, enemy: Ship, seed_value := 1) -> void:
	arena = Arena.new(seed_value)
	arena.add_ship(player, Vector2.ZERO, 0.0)
	arena.add_ship(enemy, Vector2(0.0, -SPAWN_DISTANCE), PI)
	ai = PilotAI.new(arena, ENEMY, PLAYER)
	input = {"throttle": 0.0, "turn": 0.0}
	_acc = 0.0


## Run `dt` seconds in fixed substeps: the player's helm, the pilot, then the arena.
func tick(dt: float) -> void:
	_acc = minf(_acc + dt, MAX_TICKS * STEP)
	while _acc >= STEP - 1e-9:
		_acc -= STEP
		arena.set_input(PLAYER, input["throttle"], input["turn"])
		ai.think(STEP)
		arena.step(STEP)


## "fighting", "won" (the enemy is wrecked) or "lost" (the player is; this wins when both are).
func state() -> String:
	if arena.ships[PLAYER].wrecked:
		return "lost"
	return "won" if arena.ships[ENEMY].wrecked else "fighting"


## The line for the end of the fight ("" while it goes on).
func end_text() -> String:
	match state():
		"won":
			return WON_TEXT.replace("Pirate", enemy_label)
		"lost":
			return LOST_TEXT
	return ""


func distance() -> float:
	return arena.ships[PLAYER].flight.pos.distance_to(arena.ships[ENEMY].flight.pos)


## May the player leave (Esc)? Once the enemy is wrecked, or when the two are far apart.
func can_leave() -> bool:
	return arena.ships[ENEMY].wrecked or distance() > LEAVE_DISTANCE


## The player's weapons in slot order: [{uid, id, name, group}]: placed ones by uid, then virtual mounts as added.
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
		out.append({"uid": uid, "id": m["id"], "name": name, "group": arena.weapons.group_of(m["id"])})
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
## status ("ready", "cooling down", "out of arc", "unpowered", "no ammo", "malfunction", "overheated",
## "disabled", "wrecked"), in_arc}.
func slot_state(uid: int, aim: Vector2) -> Dictionary:
	var m: Dictionary = arena.ships[PLAYER].mounts[uid]
	var why: String = arena.weapons.can_fire(arena, PLAYER, uid, aim)
	var in_arc: bool = arena.weapons.in_arc(arena, PLAYER, m, aim)
	if why == "cooling down" and not in_arc:
		why = "out of arc"
	return {"cooldown_left": arena.cooldown_left(PLAYER, uid), "cooldown": float(arena.weapons.def(m["id"])["cooldown"]),
		"status": "ready" if why == "" else why, "in_arc": in_arc}


## Where the camera should be and how far to zoom so both ships fit a viewport of `view` px:
## {center, zoom}. `margin`: the fraction of the screen kept free.
func framing(view: Vector2, margin := 0.2) -> Dictionary:
	var a = arena.ships[PLAYER]
	var b = arena.ships[ENEMY]
	var reach_a: float = (Shields.axes(a).length() + 1.0) * arena.CELL
	var reach_b: float = (Shields.axes(b).length() + 1.0) * arena.CELL
	var centre: Vector2 = (a.flight.pos + b.flight.pos) / 2.0
	var half: Vector2 = (a.flight.pos - b.flight.pos).abs() / 2.0 + Vector2.ONE * maxf(reach_a, reach_b)
	var zoom := minf(view.x / (2.0 * half.x), view.y / (2.0 * half.y)) * (1.0 - margin)
	return {"center": centre, "zoom": clampf(zoom, 0.05, 1.0)}
