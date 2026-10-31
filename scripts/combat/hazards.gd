extends RefCounted
## Sector hazards (data/hazards.json, README "Hazards", docs/MECHANICS_REVIEW.md P8): FTL's environments. A node of
## a region that lists hazards may roll one (roll); a fight there runs with `arena.hazard` = {id, dir}, which changes
## HOW the fight is fought:
## - ion_storm: shield layers come back at half speed (recharge_mult; the ion lock timer is not slowed).
## - star_heat: every 25 s a flare lights up to 3 fires on each ship, on floor cells beside the outer walls that face
##   the star (`dir` points toward it). The HUD warns 3 s before.
## - gas_cloud: turret accuracy -0.2 (accuracy_add), the pilot's aim error x1.5 (aim_error_mult).
## - radiation: while a ship has no shield layer up (or its shields are ion-locked), every crew member aboard without
##   the `suit` trait loses 0.5 hp/s.
## - debris_surge: every 20 s, 4 kinetic hits of 1 damage land on random outer wall cells that face the current
##   (`dir` points upstream), on each ship, through the normal damage rules (resist, slopes, breaches).
## `dir` is in degrees (0 east, 90 south, as sector.gd). The timers run on the arena tick, so nothing here keeps state;
## a fight with no hazard changes no number and draws nothing from the arena's rng. The arena, weapons and pilot call
## the small getters; the map and the fight HUD read the texts. Randomness comes from the arena's seeded rng.

const Collisions = preload("res://scripts/combat/collisions.gd")
const Damage = preload("res://scripts/combat/damage.gd")
const Fire = preload("res://scripts/sim/fire.gd")

const PATH := "res://data/hazards.json"
const COMPASS: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
const COMPASS_WORDS: Array[String] = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

static var _config := {}  # data/hazards.json, read on first use


## data/hazards.json as a Dictionary (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			_config = data
	return _config


## The entry of hazard `id` (name, hud, glyph, color and its numbers); {} for an id the file does not have.
static func def(id: String) -> Dictionary:
	var d = config().get("hazards", {}).get(id)
	return d if d is Dictionary else {}


# --- rolling -----------------------------------------------------------------------------------------

## The chance that a node of `type` in a region with hazards has one (stations, the exit and dead gates: 0).
static func chance_of(type: String) -> float:
	var c: Dictionary = config().get("chances", {})
	return float(c.get(type, c.get("default", 0.0)))


## The hazard of `node` (a Drift node dictionary) in a region whose file lists `region_hazards`: {} or {id, dir}. The same
## region seed and node always give the same answer; a region with no hazards, and a station or the exit, never have one.
## It picks evenly among the region's hazards and a direction (a multiple of 45 degrees, see the top).
static func roll(region_seed: int, node: Dictionary, region_hazards: Array) -> Dictionary:
	var pool := region_hazards.filter(func(h): return not def(str(h)).is_empty())
	var chance := chance_of(str(node.get("type", "")))
	if pool.is_empty() or chance <= 0.0:
		return {}
	var fnv := 2166136261
	for b in ("hazard:" + str(node.get("id", ""))).to_utf8_buffer():
		fnv = ((fnv ^ int(b)) * 16777619) & 0xFFFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = (region_seed * 1000003) ^ fnv
	if rng.randf() >= chance:
		return {}
	var id := str(pool[rng.randi() % pool.size()])
	return {"id": id, "dir": float(rng.randi() % 8) * 45.0}


## The direction of hazard `h` as a unit vector in the world (x right, y down).
static func dir_vec(h: Dictionary) -> Vector2:
	return Vector2.from_angle(deg_to_rad(float(h.get("dir", 0.0))))


## Where `h` points as a compass name: "NE" (short) or "north-east" (long).
static func compass(h: Dictionary, long := false) -> String:
	var i := posmod(roundi(float(h.get("dir", 0.0)) / 45.0), 8)
	return COMPASS_WORDS[i] if long else COMPASS[i]


## Does hazard `h` point somewhere (the star, the current)?
static func has_dir(h: Dictionary) -> bool:
	return str(h.get("id", "")) in ["star_heat", "debris_surge"]


# --- the numbers the fight reads ---------------------------------------------------------------------

## A number of the arena's hazard (`key` of its data entry), `fallback` when there is none or it has no such number.
static func _num(arena, key: String, fallback: float) -> float:
	var h: Dictionary = arena.hazard
	return fallback if h.is_empty() else float(def(str(h["id"])).get(key, fallback))


## The factor on shield recharge speed (ion storm 0.5, else 1).
static func recharge_mult(arena) -> float:
	return _num(arena, "recharge_mult", 1.0)


## Added to a turret's accuracy (gas cloud -0.2, else 0).
static func accuracy_add(arena) -> float:
	return _num(arena, "accuracy_add", 0.0)


## The factor on the enemy pilot's aim error (gas cloud 1.5, else 1).
static func aim_error_mult(arena) -> float:
	return _num(arena, "aim_error_mult", 1.0)


# --- the timed effects -------------------------------------------------------------------------------

## Advance the arena's hazard by one substep of `dt` seconds: a flare or a surge when its time is due (every
## `every_s` of arena time), radiation hurt. Called by Arena._substep.
static func tick(arena, dt: float) -> void:
	var h: Dictionary = arena.hazard
	if h.is_empty():
		return
	match str(h["id"]):
		"star_heat":
			if _due(arena):
				flare(arena)
		"debris_surge":
			if _due(arena):
				surge(arena)
		"radiation":
			radiate(arena, dt)


## Ticks between two flares or surges of the arena's hazard (0 for a hazard with no timer).
static func _period(arena) -> int:
	var h: Dictionary = arena.hazard
	return 0 if h.is_empty() else roundi(float(def(str(h["id"])).get("every_s", 0.0)) / arena.SUBSTEP)


static func _due(arena) -> bool:
	var n := _period(arena)
	return n > 0 and arena.tick % n == 0


## Seconds until the next flare or surge (0 for a hazard with no timer).
static func next_in(arena) -> float:
	var n := _period(arena)
	return 0.0 if n <= 0 else float(n - arena.tick % n) * arena.SUBSTEP


## A flare: on every ship that is still up, up to `fires` fires start on floor cells beside the outer walls that face the
## star (random ones, the arena's rng). Returns how many fires started in all.
static func flare(arena) -> int:
	var d := def(str(arena.hazard["id"]))
	var dir := dir_vec(arena.hazard)
	var total := 0
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked:
			continue
		var seen := {}
		for w in facing_walls(arena, idx, dir, float(d["face_dot"])):
			for c in w["inner"]:
				seen[c] = true
		var cells: Array = Fire.sorted_cells(seen.keys())
		var n := mini(int(d["fires"]), cells.size())
		for i in n:
			var c: Vector2i = cells.pop_at(arena.rng.randi_range(0, cells.size() - 1))
			Fire.ignite(co.ship, c)
		total += n
		arena.log_event("hazard", idx, Vector2i(-1, -1), {"kind": "flare", "fires": n})
	return total


## A surge: on every ship that is still up, `hits` kinetic hits of `damage` land on random outer wall cells that face the
## current, through Damage.apply (the wall's resist, the slope of the face, breaches). Returns how many hits landed.
static func surge(arena) -> int:
	var d := def(str(arena.hazard["id"]))
	var dir := dir_vec(arena.hazard)
	var total := 0
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked:
			continue
		var walls := facing_walls(arena, idx, dir, float(d["face_dot"]))
		var n := 0
		for i in (int(d["hits"]) if not walls.is_empty() else 0):
			var w: Dictionary = walls[arena.rng.randi_range(0, walls.size() - 1)]
			var obj := Damage.solid_at(co, w["cell"])
			if obj.is_empty() or obj["kind"] != "wall":  # an earlier hit of this surge breached it
				continue
			var nw: Vector2 = Vector2(w["n"]).rotated(co.flight.angle)
			Damage.apply(arena, idx, w["cell"], obj, float(d["damage"]) * Damage.slope_factor("kinetic", float(w["dot"])), "kinetic", {"dir": -dir, "n": nw, "hazard": true})
			n += 1
		total += n
		arena.log_event("hazard", idx, Vector2i(-1, -1), {"kind": "surge", "hits": n})
	return total


## The outer wall cells of ship `idx` with a face toward world direction `dir` (a normal within `face_dot`, a cosine, of it)
## that looks out into open space (not into a room), in (y, x) order: [{cell, n (the face's normal, ship-local), dot (its
## cosine with `dir`), inner (the floor cells just inside that face, sorted)}]. Shaped walls count by their own faces.
static func facing_walls(arena, idx: int, dir: Vector2, face_dot: float) -> Array:
	var co = arena.ships[idx]
	var hc := Collisions.hit_cells(arena, idx)
	var out := []
	for c in hc["cells"]:
		if Damage.solid_at(co, c).get("kind", "") != "wall":
			continue
		var info: Dictionary = hc["info"][c]
		var best := face_dot
		var best_n := Vector2.ZERO
		var inner := {}
		for k in info["n"].size():
			var nl := Vector2(info["n"][k])
			var dot := nl.rotated(co.flight.angle).dot(dir)
			if not info["e"][k] or dot <= face_dot or not _looks_out(co, c, nl):
				continue
			if dot > best:
				best = dot
				best_n = nl
			for s in Fire.SIDES:
				if Vector2(s).dot(nl) < -0.1 and Fire.is_floor(co.ship, c + s):
					inner[c + s] = true
		if best_n != Vector2.ZERO:
			out.append({"cell": c, "n": best_n, "dot": minf(best, 1.0), "inner": Fire.sorted_cells(inner.keys())})
	return out


## Does the face of wall cell `c` with ship-local normal `nl` look into open space: nothing (no tile, no part) in the cells
## just outside it? A face that looks into a room (floor beside it) is not an outer one.
static func _looks_out(co, c: Vector2i, nl: Vector2) -> bool:
	for s in Fire.SIDES:
		if Vector2(s).dot(nl) > 0.1:
			var o: Vector2i = c + s
			if co.ship.grid.get_tile(o) != "" or co.ship.components.at(o) >= 0 or co.ship.components.at_out(o) >= 0:
				return false
	return true


## Is ship `co` shielded: a whole shield layer up and the shields not ion-locked?
static func shielded(co) -> bool:
	return co.layers > 0 and co.ion_lock <= 0.0


## Radiation for one substep: every crew member of an up ship with no shield layer up, who is not down and has no
## `suit` trait, loses hp_per_s x dt. A member that falls is logged and drops their job (as Jobs does).
static func radiate(arena, dt: float) -> void:
	var rate := _num(arena, "hp_per_s", 0.0) * dt
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked or shielded(co):
			continue
		for m in co.ship.crew:
			if m.is_down() or m.traits().has("suit"):
				continue
			m.hurt(rate)
			if m.is_down():
				m.job = {}
				m.path.clear()
				co.ship.log_event("%s is down" % m.name)


# --- what the player reads ---------------------------------------------------------------------------

## The HUD line of the arena's hazard for ship `idx` ("" with none): the data's text, or in the last warn_s before a flare
## or a surge "STAR HEAT: Flare in 3", or for radiation with the ship unshielded "RADIATION: shields down, crew are dying".
static func hud_line(arena, idx := 0) -> String:
	var h: Dictionary = arena.hazard
	if h.is_empty():
		return ""
	var d := def(str(h["id"]))
	var id := str(h["id"])
	if d.has("warn_s") and next_in(arena) <= float(d["warn_s"]) + 1e-6:
		var word := "Flare" if id == "star_heat" else "Hits"
		return "%s: %s in %d" % [str(d["name"]).to_upper(), word, ceili(next_in(arena) - 1e-6)]
	if id == "radiation" and not shielded(arena.ships[idx]):
		return "RADIATION: SHIELDS DOWN, unsuited crew are taking damage"
	return str(d.get("hud", ""))


## The map's lines for a known node's hazard `h`: its name (and where it points) and what it does.
static func map_lines(h: Dictionary) -> Array[String]:
	var d := def(str(h.get("id", "")))
	if d.is_empty():
		return []
	var name := str(d["name"])
	if has_dir(h):
		name += " (%s %s)" % ["star to the" if h["id"] == "star_heat" else "current from the", compass(h, true)]
	var effect := str(d.get("hud", ""))
	var out: Array[String] = ["Hazard: " + name]
	out.append(effect.substr(effect.find(": ") + 2) if effect.contains(": ") else effect)
	return out
