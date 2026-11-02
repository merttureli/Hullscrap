extends RefCounted
## Hand weapons on a boarding site (docs/BOARDING.md, stage B2): the numbers of a weapon (data/hand_weapons.json plus the magazine and reload
## of its class in data/boarding.json `combat`), a gun's state (magazine, cooldown, reload) and the hitscan that every shot is. Pure logic.
## - A weapon is {id, name, class, damage, rate (uses a second), range (cells), mag (0 = no magazine: melee and tools), reload_s, spread (radians), melee}.
## - A gun is {id, w (the weapon), mag, cd, reload}: `cd` seconds until it may be used again, `reload` seconds left of a reload (0 = none).
## - trace() walks a ray in small steps: walls and closed doors stop it, a prop it enters may stop it (cover), and the first body it touches is hit.

const Site = preload("res://scripts/board/site.gd")
const Content = preload("res://scripts/data/content.gd")

const STEP := 0.2  ## cells a ray advances between two looks


static func cfg() -> Dictionary:
	return Site.config()["combat"]


## The weapon `id` of data/hand_weapons.json with the numbers a fight needs, {} when there is none.
static func weapon(id: String) -> Dictionary:
	var e := Content.entry("hand_weapons", id)
	if e.is_empty():
		return {}
	var c := cfg()
	var cls := str(e.get("class", "pistol"))
	var mag: int = int(c["mag"].get(cls, 0))
	return {"id": id, "name": str(e.get("name", id)), "class": cls, "art": str(e.get("art", id)), "damage": float(e.get("damage", 1.0)), "rate": float(e.get("rate", 1.0)),
		"range": float(e.get("range", 300.0)) / float(c["cell_px"]), "mag": mag, "reload_s": float(c["reload_s"].get(cls, 0.0)),
		"spread": deg_to_rad(float(c["spread_deg"].get(cls, 0.0))), "melee": cls == "melee" or cls == "tool"}


## The hand weapon a cargo item stands for ("pistol" is a service pistol), "" when it is not one.
static func item_weapon(item: String) -> String:
	return str(cfg()["hand_items"].get(item, ""))


## A gun of weapon `id`, loaded when `loaded`; null for an unknown weapon.
static func make_gun(id: String, loaded := true):
	var w := weapon(id)
	if w.is_empty():
		return null
	return {"id": id, "w": w, "mag": int(w["mag"]) if loaded else 0, "cd": 0.0, "reload": 0.0}


static func has_mag(gun: Dictionary) -> bool:
	return int(gun["w"]["mag"]) > 0


## Can the gun be used now: off cooldown, not reloading, and a round in it (a melee weapon needs none)?
static func ready(gun: Dictionary) -> bool:
	return float(gun["cd"]) <= 0.0 and float(gun["reload"]) <= 0.0 and (not has_mag(gun) or int(gun["mag"]) > 0)


## Start a reload with `reserve` rounds to take from: false when there is nothing to do (full, no reserve, already reloading, no magazine).
static func start_reload(gun: Dictionary, reserve: int) -> bool:
	if not has_mag(gun) or float(gun["reload"]) > 0.0 or int(gun["mag"]) >= int(gun["w"]["mag"]) or reserve <= 0:
		return false
	gun["reload"] = float(gun["w"]["reload_s"])
	return true


## `dt` seconds pass. `take` is a Callable(n) -> int that hands over up to n rounds from the reserve; a reload that ends fills the magazine with them.
## Returns true in the tick a reload ends.
static func tick(gun: Dictionary, dt: float, take: Callable) -> bool:
	gun["cd"] = maxf(float(gun["cd"]) - dt, 0.0)
	if float(gun["reload"]) <= 0.0:
		return false
	gun["reload"] = float(gun["reload"]) - dt
	if float(gun["reload"]) > 0.0:
		return false
	gun["reload"] = 0.0
	gun["mag"] = int(gun["mag"]) + int(take.call(int(gun["w"]["mag"]) - int(gun["mag"])))
	return true


## Fire the gun once (the caller checked ready()): a round is spent and the cooldown starts.
static func spend(gun: Dictionary) -> void:
	if has_mag(gun):
		gun["mag"] = int(gun["mag"]) - 1
	gun["cd"] = 1.0 / maxf(float(gun["w"]["rate"]), 0.01)


## Shoot a ray from `from` along `dir` (radians) for at most `reach` cells. `bodies`: [{pos, r, ref}] what it can hit. Returns {end (where it stopped),
## ref (the body hit, or null), kind ("body", "wall", "prop" or "air"), cover (props crossed)}. A prop the ray enters stops it with chance cfg prop_stop.
static func trace(site, from: Vector2, dir: float, reach: float, bodies: Array, rng: RandomNumberGenerator, skip = null) -> Dictionary:
	var v := Vector2.from_angle(dir)
	var stop: float = float(cfg()["prop_stop"])
	var last_prop := -1
	var cover := 0
	var t := 0.0
	while t < reach:
		t = minf(t + STEP, reach)
		var p := from + v * t
		for b in bodies:
			if b["ref"] != skip and p.distance_squared_to(b["pos"]) <= float(b["r"]) * float(b["r"]):
				return {"end": p, "ref": b["ref"], "kind": "body", "cover": cover}
		var c := Vector2i(floori(p.x), floori(p.y))
		if site.opaque(c):
			return {"end": from + v * maxf(t - STEP, 0.0), "ref": null, "kind": "wall", "cover": cover}
		var pid: int = int(site.prop_of.get(c, -1))
		if pid >= 0 and pid != last_prop and site.props[pid]["blocks"]:
			last_prop = pid
			cover += 1
			if rng.randf() < stop:
				return {"end": p, "ref": null, "kind": "prop", "cover": cover}
		elif pid < 0:
			last_prop = -1
	return {"end": from + v * reach, "ref": null, "kind": "air", "cover": cover}


## The ray hits the circle (centre `c`, radius `r`) before `reach`: a melee swing and the "is it in the line" tests use this.
static func in_arc(from: Vector2, dir: float, half: float, reach: float, c: Vector2) -> bool:
	var d := c - from
	return d.length() <= reach and absf(angle_difference(dir, d.angle())) <= half
