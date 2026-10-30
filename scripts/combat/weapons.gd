extends RefCounted
## Weapon stats (data/weapons.json, keyed by component id) and firing. A ship's weapons are
## "mounts": one per placed weapon component, plus virtual ones the arena can add by weapon id.
## A mount fires from its own spot on the ship, within its arc, when off cooldown and powered.
## Works on the arena (arena.gd).

const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Content = preload("res://scripts/data/content.gd")

const PATH := "res://data/weapons.json"
const BASE := {"damage_type": "energy", "damage": 1.0, "cooldown": 1.0, "range": 900.0, "arc": 120.0,
	"shots": 1, "pierce": 0, "fire_chance": 0.0, "spread": 0.0, "splash": 0.0, "pass_shields": false,
	"ammo": "", "jam_chance": 0.0, "heat_per_shot": 0.0}  # ammo: cargo item id used per shot; jam_chance: per shot; heat_per_shot: added to the part
## Fire group (LMB = 1, RMB = 2) by kind; an entry's own `group` wins.
const GROUPS := {"laser": 1, "bolt": 1, "beam": 1, "missile": 2, "flak": 2}
const KIND_DEFAULTS := {
	"laser": {},
	"bolt": {"speed": 700.0},
	"flak": {"speed": 600.0, "shots": 5, "spread": 12.0},
	"missile": {"speed": 300.0, "turn": 1.5, "splash": 2.0, "pass_shields": true},
	"beam": {"duration": 2.0, "tick": 0.25},  # damage is per second, dealt every `tick` seconds
}

var defs := {}  ## weapon id -> entry as written in the data file


func _init(path := PATH) -> void:
	if path != "":
		load_defs(path)


func load_defs(path: String) -> void:
	var data = Content.read(path)
	assert(data is Dictionary and data.get("weapons") is Dictionary, "bad weapon data: " + path)
	defs = data["weapons"]


func has(id: String) -> bool:
	return defs.has(id)


## The full stats of weapon `id`: base values, then the kind's defaults, then its own entry.
func def(id: String) -> Dictionary:
	var e: Dictionary = defs.get(id, {})
	var out := BASE.duplicate()
	out.merge(KIND_DEFAULTS.get(e.get("kind", "laser"), {}), true)
	out.merge(e, true)
	return out


## The fire group (1 or 2) of weapon `id`: its `group` entry, else by kind (lasers, bolts and beams 1; missiles and flak 2).
func group_of(id: String) -> int:
	var w := def(id)
	return int(w["group"]) if w.has("group") else int(GROUPS.get(w["kind"], 1))


## A mount for every placed component that has weapon stats: {uid: {id, pos (cell coordinates of
## its centre), virtual: false}}.
func mounts_of(ship) -> Dictionary:
	var out := {}
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if not has(inst["id"]):
			continue
		var sum := Vector2.ZERO
		for c in inst["cells"]:
			sum += Vector2(c) + Vector2(0.5, 0.5)
		out[uid] = {"id": inst["id"], "pos": sum / inst["cells"].size(), "virtual": false}
	return out


## The part's state when it is out of action ("malfunction" for a jam, "overheated", "disabled"), else "ok".
func status_of(arena, idx: int, uid: int) -> String:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return "ok"
	if m["virtual"]:
		return "malfunction" if m.get("jammed", false) else "ok"
	var inst = co.ship.components.instances.get(uid)
	return str(inst.get("status", "ok")) if inst != null else "ok"


## Put a jammed (or otherwise stopped) mount back to work, like a crew repair.
func repair(arena, idx: int, uid: int) -> void:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return
	if m["virtual"]:
		m.erase("jammed")
	else:
		co.ship.repair(uid)
	co.dirty = true


## "" when mount `uid` of ship `idx` can fire at the world point `aim`, else why not: wrecked, no
## such weapon, its status (malfunction, overheated, disabled), unpowered, no ammo, cooling down, out of arc.
func can_fire(arena, idx: int, uid: int, aim: Vector2) -> String:
	var co = arena.ships[idx]
	if co.wrecked:
		return "wrecked"
	var m = co.mounts.get(uid)
	if m == null:
		return "no such weapon"
	arena.sync(idx)
	var status := status_of(arena, idx, uid)
	if status != "ok":
		return status
	if not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
		return "unpowered"
	var ammo := str(def(m["id"])["ammo"])
	if ammo != "" and co.ship.inventory.count(ammo) < 1:
		return "no ammo"
	if arena.tick < int(co.cooldowns.get(uid, 0)):
		return "cooling down"
	if not in_arc(arena, idx, m, aim):
		return "out of arc"
	return ""


## Is `aim` (world) inside the firing arc of `mount`? The arc is centred on the direction from the
## ship's centre through the mount, turned with the ship; 360 degrees is a turret.
func in_arc(arena, idx: int, mount: Dictionary, aim: Vector2) -> bool:
	var to_aim: Vector2 = aim - arena.local_to_world(idx, mount["pos"])
	if to_aim.length_squared() < 1e-6:
		return false
	var arc := float(def(mount["id"])["arc"])
	if arc >= 360.0:
		return true
	var co = arena.ships[idx]
	var axis: Vector2 = mount["pos"] - co.pivot
	if axis.length_squared() < 1e-6:
		axis = Vector2.UP
	return absf(axis.rotated(co.flight.angle).angle_to(to_aim)) <= deg_to_rad(arc * 0.5) + 1e-6


## Fire mount `uid` of ship `idx` at the world point `aim`. Returns false (and does nothing) when
## can_fire() says no. Lasers resolve at once, projectiles are launched, a beam starts burning.
func fire(arena, idx: int, uid: int, aim: Vector2) -> bool:
	if can_fire(arena, idx, uid, aim) != "":
		return false
	var co = arena.ships[idx]
	var m: Dictionary = co.mounts[uid]
	var w := def(m["id"])
	co.cooldowns[uid] = arena.tick + int(ceil(float(w["cooldown"]) / arena.SUBSTEP - 1e-6))
	var origin: Vector2 = arena.local_to_world(idx, m["pos"])
	var dir := (aim - origin).normalized()
	arena.log_event("shot", idx, Vector2i(-1, -1), {"weapon": m["id"], "uid": uid, "kind": w["kind"], "origin": origin, "dir": dir})
	_spend(arena, idx, uid, m, w)
	if w["kind"] == "beam":
		var every := maxi(1, roundi(float(w["tick"]) / arena.SUBSTEP))
		arena.beams.append({"owner": idx, "uid": uid, "w": w, "local_dir": dir.rotated(-co.flight.angle),
			"end": arena.tick + int(ceil(float(w["duration"]) / arena.SUBSTEP - 1e-6)), "every": every, "next": arena.tick + 1})
	else:
		var spread := deg_to_rad(float(w["spread"]))
		for i in int(w["shots"]):
			var d := dir
			if spread > 0.0:
				d = dir.rotated(arena.rng.randf_range(-spread * 0.5, spread * 0.5))
			if w["kind"] == "laser":
				_line(arena, idx, w, m["id"], origin, origin + d * float(w["range"]))
			else:
				Projectiles.spawn(arena, idx, w, origin, d)
	Shields.drop(arena, idx, w, origin, dir)  # after the shots: those in contact this tick were resolved first
	return true


## What one shot costs: its ammo from the cargo, heat in the part, and the roll to jam it (the part,
## or a virtual mount, stops until repaired). The jam roll is only made for weapons that can jam.
func _spend(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> void:
	var co = arena.ships[idx]
	if str(w["ammo"]) != "":
		co.ship.inventory.add(str(w["ammo"]), -1)
	var inst = null if m["virtual"] else co.ship.components.instances.get(uid)
	if inst != null:
		inst["heat"] = float(inst.get("heat", 0.0)) + float(w["heat_per_shot"])
	var chance := float(w["jam_chance"])
	if chance > 0.0 and (chance >= 1.0 or arena.rng.randf() < chance):
		if inst != null:
			inst["status"] = "malfunction"
			co.ship.log_event("%s jammed" % co.ship.components.def(inst["id"]).get("name", inst["id"]))
		else:
			m["jammed"] = true
		co.dirty = true
		arena.log_event("jam", idx, Vector2i(-1, -1), {"uid": uid, "weapon": m["id"]})


## A hitscan line of weapon `w` from `from` to `to` (world); a "beam" event says where each part of it
## ended: one, or two when a cell glanced it off and it bounced once (the second has bounce true).
func _line(arena, idx: int, w: Dictionary, id: String, from: Vector2, to: Vector2) -> void:
	for seg in Projectiles.hitscan(arena, idx, w, from, to):
		arena.log_event("beam", idx, Vector2i(-1, -1), {"weapon": id, "from": seg["from"], "to": seg["to"], "dtype": w["damage_type"], "shield": seg["shield"], "bounce": seg["bounce"]})


## Burn the active beams for one substep: each ends after its duration, with its ship wrecked or
## its mount unpowered, and deals damage x tick length every `every` substeps along its line.
func tick_beams(arena) -> void:
	var live: Array = []
	for b in arena.beams:
		var co = arena.ships[b["owner"]]
		var m: Dictionary = co.mounts[b["uid"]]
		if arena.tick > b["end"] or co.wrecked or not (m["powered"] if m["virtual"] else co.powered.get(b["uid"], false)):
			continue
		live.append(b)
		if arena.tick < b["next"]:
			continue
		b["next"] += b["every"]
		var w: Dictionary = b["w"].duplicate()
		w["damage"] = float(w["damage"]) * b["every"] * arena.SUBSTEP
		var origin: Vector2 = arena.local_to_world(b["owner"], m["pos"])
		var d: Vector2 = b["local_dir"].rotated(co.flight.angle)
		_line(arena, b["owner"], w, m["id"], origin, origin + d * float(w["range"]))
	arena.beams = live
