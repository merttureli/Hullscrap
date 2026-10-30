extends RefCounted
## One ship's motion in space. Engines push against the ship's mass; the same engines steer.
## Pure logic and deterministic: the same inputs give the same state. Constants come from
## data/flight.json. Units: pixels, px/s and radians. Angle 0 faces up (-y); a positive angle
## turns clockwise on screen.

const Shapes = preload("res://scripts/ship/shapes.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const CONFIG_PATH := "res://data/flight.json"
const TILES_PATH := "res://data/tiles.json"  ## the one source of tile masses
const VERSION := 1
const REVERSE := 0.5  ## reverse thrust as a fraction of forward thrust
const UNKNOWN_TILE_MASS := 1.0
const MIN_MASS := 1.0
const CELL_PX := 32.0  ## pixels per grid cell, for the moment of inertia (arena.gd's CELL)

var tile_mass := {"floor": 1.0, "wall": 2.0, "door": 2.0}  ## code defaults; load_tile_masses() replaces them with data/tiles.json
var component_mass := {"reactor_mk1": 14.0, "reactor_mk2": 16.0}  ## component id -> whole mass
var component_mass_per_cell := 3.0  ## for components not in component_mass
var cable_mass_per_cell := 0.1
var linear_damping := 0.25  ## per second
var angular_damping := 1.5  ## per second
var thrust_to_accel := 40.0  ## px/s^2 per thrust unit per mass unit
var turn_factor := 0.6  ## rad/s^2 per thrust unit per mass unit
var max_speed := 600.0  ## px/s
var steer := "mouse"  ## data/flight.json controls.steer: "mouse" (the ship turns toward the cursor, A/D strafe) or "keys" (A/D turn)

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0  ## radians, kept in -PI..PI
var ang_vel := 0.0  ## radians per second


## Pass "" to skip the config files and keep the built-in defaults. Tile masses come from `tiles_path`
## (data/tiles.json, where every tile lists its own `mass`), everything else from `config_path`.
func _init(config_path := CONFIG_PATH, tiles_path := TILES_PATH) -> void:
	if config_path != "":
		load_config(config_path)
		if tiles_path != "":
			load_tile_masses(tiles_path)


## Read the mass of every tile from a tiles.json (a tile without `mass` weighs UNKNOWN_TILE_MASS).
## Returns false (and keeps the current values) if unusable.
func load_tile_masses(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary and data.get("tiles") is Array):
		return false
	var masses := {}
	for t in data["tiles"]:
		if t is Dictionary and t.has("id") and _is_num(t.get("mass")):
			masses[str(t["id"])] = maxf(0.0, float(t["mass"]))
	tile_mass = masses
	return true


## Read the constants from a JSON file. Returns false (and keeps the current values) if unusable.
func load_config(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	if data.get("component_mass") is Dictionary:
		var masses := {}
		for id in data["component_mass"]:
			if _is_num(data["component_mass"][id]):
				masses[str(id)] = maxf(0.0, float(data["component_mass"][id]))
		component_mass = masses
	if data.get("controls") is Dictionary and str(data["controls"].get("steer", "")) in ["mouse", "keys"]:
		steer = str(data["controls"]["steer"])
	for k in ["component_mass_per_cell", "cable_mass_per_cell", "linear_damping", "angular_damping", "thrust_to_accel", "turn_factor", "max_speed"]:
		if _is_num(data.get(k)):
			set(k, maxf(0.0, float(data[k])))
	return true


## Total mass of the ship (at least 1.0): tiles, components and cables. `mass_mult`: component id ->
## the line's mass multiplier (Stats.mass_mults); ids it lacks weigh as listed. For line-adjusted
## thrust pass thrust_of / can_fly a Stats.view(components, lines) instead of the components.
func mass_of(grid, components, cables, mass_mult := {}) -> float:
	var total := 0.0
	var tiles := {}  # tile id -> cells (a sloped or curved cell counts as its solid area)
	for c in grid.tiles:
		tiles[grid.tiles[c]] = float(tiles.get(grid.tiles[c], 0.0)) + grid.area_at(c)
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


## The mass distribution of the ship: {mass (as mass_of), com (centre of mass, grid cell coordinates),
## inertia (moment of inertia about the centre of mass, mass x px^2)}. Tiles weigh their tile mass x
## solid area at the centre of that area; a component's mass is spread evenly over its cells; a cable
## cell weighs cable_mass_per_cell. Each cell also counts as a square plate (m / 6 in cell units).
func mass_props(grid, components, cables, mass_mult := {}) -> Dictionary:
	var m := 0.0
	var sum := Vector2.ZERO  # sum of m * position
	var sq := 0.0  # sum of m * |position|^2, plus the plates' own inertia
	var cells := _sorted_cells(grid.tiles.keys())
	for c in cells:
		var id: String = grid.tiles[c]
		var mi: float = float(tile_mass.get(id, UNKNOWN_TILE_MASS)) * grid.area_at(c)
		var at := Vector2(c) + Vector2(0.5, 0.5)
		if grid.shapes.has(c):
			var sh: Dictionary = grid.shapes[c]
			at = Vector2(c) + Shapes.centroid(str(sh["shape"]), int(sh["rot"]), bool(sh["mirror"]))
		m += mi
		sum += mi * at
		sq += mi * (at.dot(at) + 1.0 / 6.0)
	var uids := _sorted(components.instances.keys())
	for uid in uids:
		var inst: Dictionary = components.instances[uid]
		var k := float(mass_mult.get(inst["id"], 1.0))
		var spread: Array = inst["cells"] + inst["out_cells"]  # both halves of a mount weigh
		var whole: float = float(component_mass[inst["id"]]) if component_mass.has(inst["id"]) else float(spread.size()) * component_mass_per_cell
		var mi: float = whole * k / float(maxi(spread.size(), 1))
		for c in spread:
			var at := Vector2(c) + Vector2(0.5, 0.5)
			m += mi
			sum += mi * at
			sq += mi * (at.dot(at) + 1.0 / 6.0)
	for c in _sorted_cells(cables.cells.keys()):
		var at := Vector2(c) + Vector2(0.5, 0.5)
		m += cable_mass_per_cell
		sum += cable_mass_per_cell * at
		sq += cable_mass_per_cell * (at.dot(at) + 1.0 / 6.0)
	var com := sum / m if m > 1e-9 else Vector2.ZERO
	var inertia := maxf(sq - m * com.dot(com), 0.0) * CELL_PX * CELL_PX
	return {"mass": maxf(m, MIN_MASS), "com": com, "inertia": maxf(inertia, MIN_MASS * CELL_PX * CELL_PX / 6.0)}


## Moment of inertia of the ship about its centre of mass (see mass_props), in mass x px^2.
func moment_of_inertia(grid, components, cables, mass_mult := {}) -> float:
	return float(mass_props(grid, components, cables, mass_mult)["inertia"])


## Centre of mass of the ship in grid cell coordinates (see mass_props).
func centre_of_mass(grid, components, cables, mass_mult := {}) -> Vector2:
	return mass_props(grid, components, cables, mass_mult)["com"]


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


## The thrust of the powered engines by direction (docs/CONTENT.md 4f): an engine pushes opposite its
## nozzle (the mount's outward direction), so {fwd: the sum of thrust x cos(angle between its push and
## the ship's forward) (at least 0), left and right: thrust x the sideways part of its push, summed
## over the engines that push that way}. Rear engines (rotation 2) give full forward thrust and no
## sideways, engines on a side wall give none forward and all sideways. `boost` as in thrust_of.
func thrusts_of(components, powered: Dictionary, boost := {}) -> Dictionary:
	var fwd := 0.0
	var left := 0.0
	var right := 0.0
	for uid in _sorted(components.instances.keys()):
		if not powered.get(uid, false):
			continue
		var d: Dictionary = components.def(components.instances[uid]["id"])
		if d.get("family", "") != "engine":
			continue
		var t := float(d.get("stats", {}).get("thrust", 0.0)) * maxf(0.0, float(boost.get(uid, 1.0)))
		var push := -Vector2(Mounts.outward(int(components.instances[uid]["rot"])))
		fwd += t * push.dot(Vector2.UP)
		if push.x > 0.0:
			right += t * push.x
		elif push.x < 0.0:
			left -= t * push.x
	return {"fwd": maxf(fwd, 0.0), "left": left, "right": right}


## The helm turn (-1..1) that swings the heading toward `target` (an `angle`, radians) and stops it
## there: it asks for the fastest turn it can still brake from. Mouse steering and the pilot AI use it.
func steer_toward(target: float, mass: float, thrust: float) -> float:
	var err := wrapf(target - angle, -PI, PI)
	var alpha := thrust * turn_factor / maxf(mass, MIN_MASS)  # rad/s^2 at full turn
	if alpha <= 1e-4:
		return 0.0
	var w_cap := alpha / maxf(angular_damping, 0.1) * 0.8
	var w_des := signf(err) * minf(sqrt(2.0 * alpha * 0.5 * absf(err)), w_cap)
	return clampf((w_des - ang_vel) / (alpha * 0.12), -1.0, 1.0)


## Advance `dt` seconds. `input`: {"throttle": -1..1, "turn": -1..1, "strafe": -1..1}; negative
## throttle is reverse at half power, positive turn is clockwise, positive strafe slides to the
## ship's right. Turning scales with `thrust` / `mass`; thrust forward with `thrusts.fwd` (by default
## all of `thrust`) and strafing with `thrusts.right` or `.left` (by default none), see thrusts_of.
func step(dt: float, input: Dictionary, mass: float, thrust: float, thrusts := {}) -> void:
	if dt <= 0.0:
		return
	var throttle := clampf(float(input.get("throttle", 0.0)), -1.0, 1.0)
	var turn := clampf(float(input.get("turn", 0.0)), -1.0, 1.0)
	var strafe := clampf(float(input.get("strafe", 0.0)), -1.0, 1.0)
	if throttle < 0.0:
		throttle *= REVERSE
	mass = maxf(mass, MIN_MASS)
	vel += Vector2.UP.rotated(angle) * (throttle * float(thrusts.get("fwd", thrust)) * thrust_to_accel / mass * dt)
	var side := float(thrusts.get("right", 0.0)) if strafe > 0.0 else float(thrusts.get("left", 0.0))
	vel += Vector2.RIGHT.rotated(angle) * (strafe * side * thrust_to_accel / mass * dt)
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


## Cells in (y, x) order, so sums over them are the same every run.
static func _sorted_cells(keys: Array) -> Array:
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return keys
