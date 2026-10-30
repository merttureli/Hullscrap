extends RefCounted
## One ship's motion in space. Engines push against the ship's mass; the same engines steer.
## Pure logic and deterministic: the same inputs give the same state. Constants come from
## data/flight.json. Units: pixels, px/s and radians. Angle 0 faces up (-y); a positive angle
## turns clockwise on screen.

const CONFIG_PATH := "res://data/flight.json"
const VERSION := 1
const REVERSE := 0.5  ## reverse thrust as a fraction of forward thrust
const UNKNOWN_TILE_MASS := 1.0
const MIN_MASS := 1.0

var tile_mass := {"floor": 1.0, "wall": 2.0, "door": 2.0}
var component_mass := {"reactor_mk1": 14.0, "reactor_mk2": 16.0}  ## component id -> whole mass
var component_mass_per_cell := 3.0  ## for components not in component_mass
var cable_mass_per_cell := 0.1
var linear_damping := 0.25  ## per second
var angular_damping := 1.5  ## per second
var thrust_to_accel := 40.0  ## px/s^2 per thrust unit per mass unit
var turn_factor := 0.6  ## rad/s^2 per thrust unit per mass unit
var max_speed := 600.0  ## px/s

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0  ## radians, kept in -PI..PI
var ang_vel := 0.0  ## radians per second


## Pass "" to skip the config file and keep the built-in defaults.
func _init(config_path := CONFIG_PATH) -> void:
	if config_path != "":
		load_config(config_path)


## Read the constants from a JSON file. Returns false (and keeps the current values) if unusable.
func load_config(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	for k in ["tile_mass", "component_mass"]:
		if data.get(k) is Dictionary:
			var masses := {}
			for id in data[k]:
				if _is_num(data[k][id]):
					masses[str(id)] = maxf(0.0, float(data[k][id]))
			set(k, masses)
	for k in ["component_mass_per_cell", "cable_mass_per_cell", "linear_damping", "angular_damping", "thrust_to_accel", "turn_factor", "max_speed"]:
		if _is_num(data.get(k)):
			set(k, maxf(0.0, float(data[k])))
	return true


## Total mass of the ship (at least 1.0): tiles, components and cables. `mass_mult`: component id ->
## the line's mass multiplier (Stats.mass_mults); ids it lacks weigh as listed. For line-adjusted
## thrust pass thrust_of / can_fly a Stats.view(components, lines) instead of the components.
func mass_of(grid, components, cables, mass_mult := {}) -> float:
	var total := 0.0
	var tiles := {}  # tile id -> count
	for c in grid.tiles:
		tiles[grid.tiles[c]] = int(tiles.get(grid.tiles[c], 0)) + 1
	for id in _sorted(tiles.keys()):
		total += float(tiles[id]) * float(tile_mass.get(id, UNKNOWN_TILE_MASS))
	var comps := {}  # component id -> [instances, footprint cells]
	for uid in components.instances:
		var i: Dictionary = components.instances[uid]
		var e: Array = comps.get(i["id"], [0, 0])
		e[0] += 1
		e[1] += i["cells"].size()
		comps[i["id"]] = e
	for id in _sorted(comps.keys()):
		var m := float(mass_mult.get(id, 1.0))
		if component_mass.has(id):
			total += float(comps[id][0]) * float(component_mass[id]) * m
		else:
			total += float(comps[id][1]) * component_mass_per_cell * m
	total += float(cables.cells.size()) * cable_mass_per_cell
	return maxf(total, MIN_MASS)


## Total thrust of the powered engines. `boost`: component uid -> thrust multiplier (default 1.0).
func thrust_of(components, powered: Dictionary, boost := {}) -> float:
	var total := 0.0
	for uid in _sorted(components.instances.keys()):
		if not powered.get(uid, false):
			continue
		var d: Dictionary = components.def(components.instances[uid]["id"])
		if d.get("family", "") == "engine":
			total += float(d.get("stats", {}).get("thrust", 0.0)) * maxf(0.0, float(boost.get(uid, 1.0)))
	return total


## Advance `dt` seconds. `input`: {"throttle": -1..1, "turn": -1..1}; negative throttle is reverse
## at half power, positive turn is clockwise. Both thrust and turning scale with `thrust` / `mass`.
func step(dt: float, input: Dictionary, mass: float, thrust: float) -> void:
	if dt <= 0.0:
		return
	var throttle := clampf(float(input.get("throttle", 0.0)), -1.0, 1.0)
	var turn := clampf(float(input.get("turn", 0.0)), -1.0, 1.0)
	if throttle < 0.0:
		throttle *= REVERSE
	mass = maxf(mass, MIN_MASS)
	vel += Vector2.UP.rotated(angle) * (throttle * thrust * thrust_to_accel / mass * dt)
	ang_vel += turn * thrust * turn_factor / mass * dt
	vel = (vel * exp(-linear_damping * dt)).limit_length(max_speed)
	ang_vel *= exp(-angular_damping * dt)
	pos += vel * dt
	angle = wrapf(angle + ang_vel * dt, -PI, PI)


## "" when the ship can fly, else why not. A powered helm and a powered engine are required.
func can_fly(components, powered: Dictionary) -> String:
	var helm := false
	var engine := false
	for uid in components.instances:
		if powered.get(uid, false):
			var family = components.def(components.instances[uid]["id"]).get("family", "")
			helm = helm or family == "helm"
			engine = engine or family == "engine"
	if not helm:
		return "no powered helm"
	if not engine:
		return "no powered engine"
	return ""


func to_dict() -> Dictionary:
	return {"version": VERSION, "pos": [pos.x, pos.y], "vel": [vel.x, vel.y], "angle": angle, "ang_vel": ang_vel}


## Replace the motion state with a saved one. Returns "" on success, else the reason; nothing
## changes when it fails.
func load_dict(d: Dictionary) -> String:
	if int(d.get("version", 0)) != VERSION:
		return "unsupported flight version"
	var p = d.get("pos")
	var v = d.get("vel")
	if not (p is Array and p.size() == 2 and v is Array and v.size() == 2):
		return "bad flight data"
	for n in [p[0], p[1], v[0], v[1], d.get("angle"), d.get("ang_vel")]:
		if not _is_num(n):
			return "bad flight data"
	pos = Vector2(float(p[0]), float(p[1]))
	vel = Vector2(float(v[0]), float(v[1]))
	angle = float(d["angle"])
	ang_vel = float(d["ang_vel"])
	return ""


static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _sorted(keys: Array) -> Array:
	keys.sort()
	return keys
