extends RefCounted
## Weapon stats (data/weapons.json, keyed by component id), aiming and firing. A ship's weapons are
## "mounts": one per placed weapon component, plus virtual ones the arena can add by weapon id.
## A mount is a hull mount (docs/CONTENT.md 4f): its barrel turns about a pivot on the outside half and
## points outward through the wall (`dir`, ship-local); shots leave from the muzzle, `reach` cells along
## the barrel's live direction `aim`. A FIXED gun fires along `dir`, turned up to its `gimbal` degrees
## toward the point aimed at, so the ship is aimed. A TURRET (`turret` true) turns its barrel within
## its `arc` at `track` degrees per second toward the lead point on the enemy (tick_turrets) and fires by
## itself when ready and on target (the owner's T key toggles it); each of its shots rolls a hit
## against the target's evasion on the arena's rng: a hit aims at a random outer cell facing the
## turret, a miss at a point just off the hull. A weapon's AIM CLASS (`aim`: fixed, swivel or turret; docs/GUNS.md 2) says how it
## aims: swivel and turret track by themselves (`turret` true) inside their arc, a swivel in a narrower one at 0.8 of the entry's
## damage, a turret at 0.6 (`aim_share` in the data, was `turret_damage`); a fixed gun deals all of it.
## A turret with an `intercept` {range} effect (point defence, effects.gd) turns on the nearest incoming threat within that
## range before any ship: an enemy missile, or a shot at or below `pd_speed` px/s (or marked `interceptable`), and each shot
## rolls its accuracy to destroy it outright. It shoots a ship only when nothing incoming is in range.
## Works on the arena (arena.gd).

const Projectiles = preload("res://scripts/combat/projectiles.gd")
const Shields = preload("res://scripts/combat/shields.gd")
const Collisions = preload("res://scripts/combat/collisions.gd")
const PilotAI = preload("res://scripts/combat/pilot_ai.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Content = preload("res://scripts/data/content.gd")
const Effects = preload("res://scripts/combat/effects.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const Volley = preload("res://scripts/combat/volley.gd")

const PATH := "res://data/weapons.json"
const BASE := {"damage_type": "energy", "damage": 1.0, "cooldown": 1.0, "range": 900.0, "arc": 360.0,
	"shots": 1, "pierce": 0, "fire_chance": 0.0, "spread": 0.0, "splash": 0.0, "pass_shields": false,
	"ammo": "", "jam_chance": 0.0, "heat_per_shot": 0.0,
	"turret": false, "gimbal": 0.0, "track": 90.0, "accuracy": 0.75}  # ammo: cargo item id used per shot; jam_chance: per shot; heat_per_shot: added to the part; gimbal (fixed guns) and arc, track, accuracy (turrets): see the top
## Fire group (LMB = 1, RMB = 2) by kind; an entry's own `group` wins.
const GROUPS := {"laser": 1, "bolt": 1, "beam": 1, "missile": 2, "flak": 2}
const KIND_DEFAULTS := {
	"laser": {},
	"bolt": {"speed": 840.0},
	"flak": {"speed": 720.0, "shots": 5, "spread": 12.0},
	"missile": {"speed": 360.0, "turn": 1.5, "splash": 2.0, "pass_shields": true},
	"beam": {"duration": 2.0, "tick": 0.25},  # damage is per second, dealt every `tick` seconds
}

const AP_ITEM := "piercing_rounds"  ## the ammo a gun in Piercing mode spends, one a shot (docs/GUNS.md 14)
const AP_DAMAGE := 0.6  ## the share of its damage a piercing round deals
const CHAIN_WINDOW_S := 1.5  ## seconds past its cooldown that a chain gun's next volley still adds a step
const ON_TARGET_DEG := 4.0  ## a turret fires when its barrel is this close to the lead direction
const SPEED_EVASION := 0.25  ## evasion of a ship at full speed (docs/CONTENT.md 4)
const MISS_MARGIN := 40.0  ## px past the hull's edge that a missed turret shot aims at

var defs := {}  ## weapon id -> entry as written in the data file
var turret_damage := 0.6  ## the share of its entry's damage that a turret deals (aim_share["turret"])
var aim_share := {"fixed": 1.0, "swivel": 0.8, "turret": 0.6}  ## aim class -> the share of its entry's damage a weapon of that class deals
var pd_speed := 500.0  ## point defence also shoots down any shot flying at or below this speed (px/s)
var shapes := {}  ## gun shape name -> {name, outside [w, h], breech [w, h], aim, gimbal?}: docs/GUNS.md 3 (the data's `shapes`)
var aim_classes := {}  ## aim class -> its bands {gimbal_max?, arc [min, max]?, track}: what tests/test_gun_shapes.gd holds every gun to


func _init(path := PATH) -> void:
	if path != "":
		load_defs(path)


func load_defs(path: String) -> void:
	var data = Content.read(path)
	assert(data is Dictionary and data.get("weapons") is Dictionary, "bad weapon data: " + path)
	defs = data["weapons"]
	turret_damage = float(data.get("turret_damage", turret_damage))  # the old key: the turret share when `aim_share` has none
	aim_share = {"fixed": 1.0, "swivel": 0.8, "turret": turret_damage}
	if data.get("aim_share") is Dictionary:
		for k in data["aim_share"]:
			aim_share[str(k)] = float(data["aim_share"][k])
	turret_damage = float(aim_share["turret"])
	pd_speed = float(data.get("pd_speed", pd_speed))
	shapes = {}
	for s in data.get("shapes", {}):
		var e: Dictionary = data["shapes"][s].duplicate()
		for k in ["outside", "breech"]:
			if e.get(k) is Array:
				e[k] = [int(e[k][0]), int(e[k][1])]
		shapes[str(s)] = e
	aim_classes = data.get("aim_classes", {})


func has(id: String) -> bool:
	return defs.has(id)


## The full stats of weapon `id`: base values, then the kind's defaults, then its own entry. `aim` is its class (the entry's, else
## turret/fixed by `turret`) and `turret` is true for swivel and turret. A tracking weapon's damage is its class's share of the
## entry's (the fixed equivalent at its tier).
func def(id: String) -> Dictionary:
	var e: Dictionary = defs.get(id, {})
	var out := BASE.duplicate()
	out.merge(KIND_DEFAULTS.get(e.get("kind", "laser"), {}), true)
	out.merge(e, true)
	out["id"] = id  # the art looks for art/projectiles/<id> before the kind's
	var cls := str(e.get("aim", ""))
	if cls == "":
		cls = "turret" if out["turret"] else "fixed"
	out["aim"] = cls
	out["turret"] = cls != "fixed"
	out["damage"] = float(out["damage"]) * float(aim_share.get(cls, 1.0))
	return out


## How weapon `d` aims, for the cards and the generator: {class (fixed, swivel, turret), arc (the width in degrees of the wedge it can
## fire in: 2 x gimbal for a fixed gun, its arc for a tracking one), gimbal, shape (the gun shape name of a component def, else "")}.
## `d` is a weapon entry (def()) or a component def (it has an `id` of a weapon).
func aim_of(d: Dictionary) -> Dictionary:
	var w: Dictionary = d if d.has("kind") else def(str(d.get("id", "")))
	var cls := str(w.get("aim", "fixed"))
	return {"class": cls, "arc": float(w["arc"]) if cls != "fixed" else 2.0 * float(w["gimbal"]), "gimbal": float(w["gimbal"]), "shape": str(d.get("shape", ""))}


## The fire group of weapon `id`: 1 (LMB), 2 (RMB), 3 (Q) or 0 (AUTO, it fires by itself). The mount's own `choice` (0-3; -1 none) wins,
## else a fixed gun's `group` entry, else by kind (lasers, bolts and beams 1; missiles and flak 2); a turret or swivel is AUTO.
func group_of(id: String, choice := -1) -> int:
	var w := def(id)
	if choice >= 0 and choice <= 3:
		return choice
	if bool(w.get("turret", false)) or str(w.get("aim", "fixed")) != "fixed":
		return 0
	return int(w["group"]) if w.has("group") else int(GROUPS.get(w["kind"], 1))


## The group gun `uid` of `components` falls in with no choice of its own: group_of() by kind, except that when no gun of the ship
## ends up in LMB (counting the others' saved choices), a gun that is not AUTO takes LMB so a new player's click fires something.
func default_group(components, uid: int) -> int:
	var g := group_of(str(components.instances[uid]["id"]))
	if g == 0 or g == 1 or g == 3:
		return g
	for u in components.instances:
		var id: String = components.instances[u]["id"]
		if u != uid and has(id) and str(components.def(id).get("family", "")) != "drone_bay" and group_of(id, components.group_choice(u)) == 1:
			return g
	return 1


## The fire group of placed gun `uid`: the player's choice, else default_group().
func group_in(components, uid: int) -> int:
	var c: int = components.group_choice(uid)
	return c if c >= 0 else default_group(components, uid)


## The fire group of mount `uid` of ship `idx`: group_of() with the choice the player made for a placed gun.
func mount_group(arena, idx: int, uid: int) -> int:
	var co = arena.ships[idx]
	var m = co.mounts.get(uid)
	if m == null:
		return 0
	if not m["virtual"] and co.ship.components.instances.has(uid):
		return group_in(co.ship.components, uid)
	return group_of(m["id"])


## A mount for every placed component that has weapon stats: {uid: {id, pos (the barrel's pivot, cell
## coordinates; the middle of its barrels), dir (outward, ship-local unit vector), reach (cells from the pivot to the muzzle), aim
## (the barrels' live direction, ship-local; starts as dir), offsets (each barrel's place against pos, one for a single barrel),
## shots (how many it has fired: the next shot leaves from barrel `shots` mod their number), virtual: false}}. A part with no
## outside half pivots at the middle of its inside half and fires from there.
func mounts_of(ship) -> Dictionary:
	var out := {}
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for uid in uids:
		var inst: Dictionary = ship.components.instances[uid]
		if not has(inst["id"]):
			continue
		var dir := Mounts.dir_of(inst)  # the true outward direction: a mount on a slope faces along it
		var pos := Vector2.ZERO
		var reach := 0.0
		var barrels: Array = []
		if ship.components.has_outside(uid):
			var b := Mounts.barrel_of(ship.components.def(inst["id"]), inst)
			pos = b["pivot"]
			reach = b["reach"]
			barrels = b["pivots"]
		else:
			for c in inst["cells"]:
				pos += Vector2(c) + Vector2(0.5, 0.5)
			pos /= inst["cells"].size()
		var offsets: Array[Vector2] = []  # a base with several barrels (broadside, strip): each one's place against `pos`, their middle
		for p in barrels:
			offsets.append(p - pos)
		out[uid] = {"id": inst["id"], "pos": pos, "dir": dir, "reach": reach, "aim": dir, "virtual": false, "offsets": offsets, "shots": 0}
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
	if inst == null:
		return "ok"
	match co.ship.components.offline_reason(co.ship.grid, uid):
		"outside half disabled":
			return "disabled"
		"link cut":
			return "offline"
	return str(inst.get("status", "ok"))


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
## such weapon, its status (malfunction, overheated, disabled: an outside half shot out; offline: a
## cut link), unpowered, no ammo (ammo.gd: "no ammo", "no ammo rack in reach", "rack empty", "belt stopped"), cooling down,
## then "feeding" (the belt has not delivered the next unit yet). A fixed gun fires wherever it points, so it is never
## out of arc; a turret is, when the enemy it would shoot at is outside its arc, and has "no target"
## when nothing is left to shoot at (`aim` is not used by a turret).
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
	var w := def(m["id"])
	var ammo := str(w["ammo"])
	var feed := ""  # a placed gun on a ship with ammo racks draws from them (ammo.gd), else from the cargo
	if ammo != "":
		feed = Ammo.refusal(co.ship, uid, ammo, maxi(Effects.ammo_cost(m, w), 1))
		if feed != "" and feed != "feeding":
			return feed
	if arena.tick < int(co.cooldowns.get(uid, 0)):
		return "cooling down"
	if feed != "":
		return feed  # the next unit is on its way along the belt: the reload waits for it
	if w["turret"]:
		var mis = missile_target(arena, idx, m, w)
		var tgt := target_of(arena, idx)
		if tgt < 0 and mis == null:
			return "no target"
		if not in_arc(arena, idx, m, missile_point(arena, idx, m, w, mis) if mis != null else lead_point_of(arena, idx, m, tgt)):
			return "out of arc"
	return ""


## Can mount `mount` of ship `idx` bear on the world point `aim`? A fixed gun, when the point lies inside
## its gimbal cone (else it fires along the edge of that cone); a turret, inside its arc.
func in_arc(arena, idx: int, mount: Dictionary, aim: Vector2) -> bool:
	var to_aim: Vector2 = aim - arena.local_to_world(idx, mount["pos"])
	if to_aim.length_squared() < 1e-6:
		return false
	var w := def(mount["id"])
	var limit := float(w["arc"]) * 0.5 if w["turret"] else float(w["gimbal"])
	if limit >= 180.0:
		return true
	var local: Vector2 = to_aim.rotated(-arena.ships[idx].flight.angle)
	return absf(Vector2(mount["dir"]).angle_to(local)) <= deg_to_rad(limit) + 1e-6


## The direction (ship-local unit vector) a fixed gun `mount` of ship `idx` fires along toward the
## world point `aim`: toward it, but at most `gimbal` degrees off the mount's outward direction.
func fixed_dir(arena, idx: int, mount: Dictionary, aim: Vector2) -> Vector2:
	var want: Vector2 = (aim - arena.local_to_world(idx, mount["pos"])).rotated(-arena.ships[idx].flight.angle)
	return clamp_dir(want, mount["dir"], float(def(mount["id"])["gimbal"]))


## `want` turned toward `centre` until it is at most `limit_deg` degrees off it (a unit vector). Both
## directions as ship-local vectors; a zero `want` gives `centre`.
static func clamp_dir(want: Vector2, centre: Vector2, limit_deg: float) -> Vector2:
	if want.length_squared() < 1e-9:
		return centre
	if limit_deg >= 180.0:
		return want.normalized()
	var lim := deg_to_rad(limit_deg)
	return centre.rotated(clampf(centre.angle_to(want), -lim, lim))


## Point the barrel of fixed gun `uid` of ship `idx` at the world point `aim` (its gimbal limits how
## far it turns): what the view draws, and where the next shot goes. A turret turns itself.
func point_barrel(arena, idx: int, uid: int, aim: Vector2) -> void:
	var m = arena.ships[idx].mounts.get(uid)
	if m != null and not def(m["id"])["turret"]:
		m["aim"] = fixed_dir(arena, idx, m, aim)


## Where a shot of mount `m` (ship `idx`) leaves, in the world: the muzzle, `reach` cells along its barrel. A mount with several
## barrels fires from them in turn: barrel `k` (default: the one that fires next, `shots` mod their number).
func muzzle_of(arena, idx: int, m: Dictionary, k := -1) -> Vector2:
	var offs: Array = m.get("offsets", [])
	var off: Vector2 = offs[(int(m.get("shots", 0)) if k < 0 else k) % offs.size()] if offs.size() > 1 else Vector2.ZERO
	return arena.local_to_world(idx, m["pos"] + off + Vector2(m["aim"]) * float(m["reach"]))


## Fire mount `uid` of ship `idx` at the world point `aim`. Returns false (and does nothing) when
## can_fire() says no. Lasers resolve at once, projectiles are launched, a beam starts burning. A
## fixed gun fires along its gimbal-limited direction toward `aim`; a turret at the enemy ship
## (target_of), rolling its hit (see the top).
func fire(arena, idx: int, uid: int, aim: Vector2) -> bool:
	if can_fire(arena, idx, uid, aim) != "":
		return false
	var co = arena.ships[idx]
	var m: Dictionary = co.mounts[uid]
	var w := Effects.adjust(arena, idx, uid, m, def(m["id"]))  # less power or rate without the operator or crew it needs
	var ticks := int(ceil(float(w["cooldown"]) * _chain_mult(arena, m, w) / arena.SUBSTEP - 1e-6))
	var queued := 0
	if w.get("charge") is Dictionary:  # the stored volleys leave `gap_s` apart behind this one; the cooldown starts after the last
		queued = int(m.get("stored", 0))
		ticks += queued * _gap_ticks(arena, w)
	co.cooldowns[uid] = arena.tick + ticks
	m["store_at"] = -1
	_volley(arena, idx, uid, m, w, aim)
	if queued > 0:
		m["stored"] = 0
		m["queue"] = queued
		m["next_rel"] = arena.tick + _gap_ticks(arena, w)
		m["rel_aim"] = aim
	return true


## One volley of mount `uid` (ship `idx`) with the stats `w`, aimed at the world point `aim`: the barrel turns, the shot event, the
## ammo and heat, then the shots (or the point-defence intercept, or the beam), the on-fire effects and the shield drop.
func _volley(arena, idx: int, uid: int, m: Dictionary, w: Dictionary, aim: Vector2) -> void:
	var co = arena.ships[idx]
	var mis = missile_target(arena, idx, m, w) if w["turret"] else null  # point defence shoots a missile before a ship
	if w["turret"]:
		var point: Vector2 = missile_point(arena, idx, m, w, mis) if mis != null else _turret_point(arena, idx, uid, m, w, target_of(arena, idx))
		var want: Vector2 = (point - arena.local_to_world(idx, m["pos"])).rotated(-co.flight.angle)
		m["aim"] = clamp_dir(want, m["dir"], float(w["arc"]) * 0.5)
	else:
		m["aim"] = fixed_dir(arena, idx, m, aim)
	if mis == null:
		w = _piercing(arena, idx, uid, m, w)
	var origin: Vector2 = muzzle_of(arena, idx, m)  # (the first barrel of a volley: the shot event and the shield drop use it)
	var dir: Vector2 = Vector2(m["aim"]).rotated(co.flight.angle)
	arena.log_event("shot", idx, Vector2i(-1, -1), {"weapon": m["id"], "uid": uid, "kind": w["kind"], "origin": origin, "dir": dir})
	_spend(arena, idx, uid, m, w)
	if mis != null:
		_intercept(arena, idx, w, origin, mis)
		Effects.on_fire(arena, idx, uid, m, w)
		return  # (a point-defence shot leaves through its own port: it does not open the shield)
	if w["kind"] == "beam":
		var every := maxi(1, roundi(float(w["tick"]) / arena.SUBSTEP))
		arena.beams.append({"owner": idx, "uid": uid, "w": w, "local_dir": m["aim"], "k": int(m.get("shots", 0)),
			"end": arena.tick + int(ceil(float(w["duration"]) / arena.SUBSTEP - 1e-6)), "every": every, "next": arena.tick + 1})
	else:
		var spread := deg_to_rad(float(w["spread"]))
		for i in int(w["shots"]):
			var d := dir
			if spread > 0.0:
				d = dir.rotated(arena.rng.randf_range(-spread * 0.5, spread * 0.5))
			var from: Vector2 = muzzle_of(arena, idx, m, int(m["shots"]) + i)  # round-robin over the barrels
			if w["kind"] == "laser":
				_line(arena, idx, w, m["id"], from, from + d * float(w["range"]))
			else:
				Projectiles.spawn(arena, idx, w, from, d)
	m["shots"] = int(m.get("shots", 0)) + (1 if w["kind"] == "beam" else int(w["shots"]))
	Effects.on_fire(arena, idx, uid, m, w)
	Shields.drop(arena, idx, w, origin, dir)  # after the shots: those in contact this tick were resolved first


# --- piercing rounds (docs/GUNS.md 14) ------------------------------------------------------------------------

## Can a gun of weapon entry `w` (a def()) load piercing rounds: a rapid-fire gun (or one whose entry says `ap_ok`: the chain slug gun) that
## fires bolts or flak of any damage type but ion, and is not point defence.
static func can_pierce(w: Dictionary) -> bool:
	return (bool(w.get("rapid", false)) or bool(w.get("ap_ok", false))) and str(w.get("kind", "")) in ["bolt", "flak"] and str(w.get("damage_type", "")) != "ion" and not Volley.is_pd(w)


## Is mount `m` (uid `uid`) of ship `idx` set to Piercing (the choice, not whether it has rounds)? A virtual mount keeps it in `m["ap"]`.
func ap_on(arena, idx: int, uid: int, m: Dictionary) -> bool:
	if m["virtual"]:
		return bool(m.get("ap", false))
	return bool(arena.ships[idx].ship.ap_guns.get(uid, false))


## Switch mount `uid` of ship `idx` to Piercing (or back to Standard). False when its gun cannot load them.
func set_ap(arena, idx: int, uid: int, on: bool) -> bool:
	var m = arena.ships[idx].mounts.get(uid)
	if m == null or not can_pierce(def(m["id"])):
		return false
	if m["virtual"]:
		m["ap"] = on
	elif on:
		arena.ships[idx].ship.ap_guns[uid] = true
	else:
		arena.ships[idx].ship.ap_guns.erase(uid)
	return true


## The stats of the shot(s) mount `uid` fires now: `w` as it is for a Standard gun; for a Piercing one that has the rounds, the shots pass
## shields, deal AP_DAMAGE of the damage and spend a round each. With too few rounds left the gun falls back to Standard and says so once.
func _piercing(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> Dictionary:
	if not can_pierce(w) or not ap_on(arena, idx, uid, m):
		return w
	var co = arena.ships[idx]
	var n := int(w["shots"])
	if co.ship.inventory.count(AP_ITEM) < n:
		set_ap(arena, idx, uid, false)
		var gun: String = str(m["id"]) if m["virtual"] else str(co.ship.components.def(m["id"]).get("name", m["id"]))
		co.ship.log_event("%s is out of piercing rounds: back to standard" % gun)
		arena.log_event("ap_out", idx, Vector2i(-1, -1), {"uid": uid, "weapon": m["id"]})
		return w
	co.ship.inventory.add(AP_ITEM, -n)
	var out := w.duplicate()
	out["pass_shields"] = true
	out["damage"] = float(out["damage"]) * AP_DAMAGE
	out["ap"] = true
	return out


# --- chain and charge (docs/GUNS.md 6) ----------------------------------------------------------------------

## The chain steps mount `m` has now: those it won with its last volley, less one for every second it has been idle past
## `decay_s`. 0 for a gun with no `chain` entry.
func _steps(arena, m: Dictionary, w: Dictionary) -> int:
	var spec = w.get("chain")
	if not spec is Dictionary or int(m.get("chain", 0)) <= 0:
		return 0
	var idle: float = float(arena.tick - int(m.get("chain_tick", 0))) * arena.SUBSTEP
	var lost := int(floor(idle - float(spec["decay_s"]))) + 1 if idle > float(spec["decay_s"]) else 0
	return maxi(int(m["chain"]) - lost, 0)


## The cooldown multiplier of the volley mount `m` fires now, and (a side effect) the step it earns: a volley inside the window
## (the last cooldown plus CHAIN_WINDOW_S) adds a step up to `steps`, and each step cuts the cooldown by `cut`, one after the other.
func _chain_mult(arena, m: Dictionary, w: Dictionary) -> float:
	var spec = w.get("chain")
	if not spec is Dictionary:
		return 1.0
	var steps := _steps(arena, m, w)
	if arena.tick <= int(m.get("chain_until", -1)):
		steps = mini(steps + 1, int(spec["steps"]))
	m["chain"] = steps
	m["chain_tick"] = arena.tick
	m["chain_until"] = arena.tick + int(ceil((float(w["cooldown"]) * pow(1.0 - float(spec["cut"]), steps) + CHAIN_WINDOW_S) / arena.SUBSTEP))
	return pow(1.0 - float(spec["cut"]), steps)


func _gap_ticks(arena, w: Dictionary) -> int:
	return maxi(1, int(ceil(float(w["charge"]["gap_s"]) / arena.SUBSTEP - 1e-6)))


## Read-only state for the weapon bar and the art. chain_steps: the steps mount `uid` of ship `idx` has now (0 for a gun with no `chain`);
## chain_max: the most steps weapon entry `w` (a def()) can have; charges: the volleys stored in the mount (0 for a gun with no `charge`);
## charge_max: the most it stores.
func chain_steps(arena, idx: int, uid: int) -> int:
	var m = arena.ships[idx].mounts.get(uid)
	return 0 if m == null else _steps(arena, m, def(m["id"]))


func chain_max(w: Dictionary) -> int:
	return int(w["chain"]["steps"]) if w.get("chain") is Dictionary else 0


func charges(arena, idx: int, uid: int) -> int:
	var m = arena.ships[idx].mounts.get(uid)
	return 0 if m == null or not def(m["id"]).get("charge") is Dictionary else int(m.get("stored", 0))


func charge_max(w: Dictionary) -> int:
	return int(w["charge"]["max"]) if w.get("charge") is Dictionary else 0


## Should the AI or the autofire hold the fire order of mount `m` (ship `idx`) back from ship `target`? A charge gun waits to release
## until it holds `max` volleys, or the target's shields are down. False for any other gun.
func holds_charge(arena, idx: int, m: Dictionary, target: int) -> bool:
	var w := def(m["id"])
	if not w.get("charge") is Dictionary or target < 0:
		return false
	return int(m.get("stored", 0)) < int(w["charge"]["max"]) and arena.ships[target].layers > 0


## Store a volley in every idle charge gun that has been ready for a cooldown, and let the release of a fire order run: one stored
## volley every `gap_s`, on the aim of the order.
func tick_charge(arena) -> void:
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked:
			continue
		for uid in co.mounts:
			var m: Dictionary = co.mounts[uid]
			var w := def(m["id"])
			var spec = w.get("charge")
			if not spec is Dictionary:
				continue
			var ok: bool = status_of(arena, idx, uid) == "ok" and (m["powered"] if m["virtual"] else co.powered.get(uid, false))
			if int(m.get("queue", 0)) > 0:
				if not ok or (w["turret"] and target_of(arena, idx) < 0) or (str(w["ammo"]) != "" and Ammo.refusal(co.ship, uid, str(w["ammo"]), 1) not in ["", "feeding"]):
					m["queue"] = 0
				elif arena.tick >= int(m["next_rel"]):
					var aim: Vector2 = arena.aim_points.get(idx, m["rel_aim"])
					m["queue"] = int(m["queue"]) - 1
					m["next_rel"] = arena.tick + _gap_ticks(arena, w)
					_volley(arena, idx, uid, m, Effects.adjust(arena, idx, uid, m, w), aim)
				continue
			var stored := int(m.get("stored", 0))
			if not ok or arena.tick < int(co.cooldowns.get(uid, 0)) or stored >= int(spec["max"]):
				m["store_at"] = -1
			elif int(m.get("store_at", -1)) < 0:
				m["store_at"] = arena.tick + int(ceil(float(w["cooldown"]) / arena.SUBSTEP - 1e-6))
			elif arena.tick >= int(m["store_at"]):
				m["stored"] = stored + 1
				m["store_at"] = -1


# --- turrets ------------------------------------------------------------------------------------

## The ship a turret of `idx` shoots at: the nearest ship that is not wrecked; -1 when none.
func target_of(arena, idx: int) -> int:
	var best := -1
	var best_d := INF
	for i in arena.ships.size():
		if i == idx or arena.ships[i].wrecked:
			continue
		var d: float = arena.ships[i].flight.pos.distance_squared_to(arena.ships[idx].flight.pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## Can point defence shoot down the shots of weapon entry `w` (def()): a missile, one marked `interceptable`, or one at or below `pd_speed`?
## A hitscan laser or beam has no shot to stop.
func pd_can_stop(w: Dictionary) -> bool:
	return str(w["kind"]) == "missile" or bool(w.get("interceptable", false)) or (w.has("speed") and float(w["speed"]) <= pd_speed)


## Is shot `p` (an entry of arena.projectiles) something point defence shoots down: a missile, a shot at or below `pd_speed`, or one
## whose weapon is marked `interceptable`? A fast bolt is not.
func interceptable(p: Dictionary) -> bool:
	var w: Dictionary = p["w"]
	return str(w["kind"]) == "missile" or bool(w.get("interceptable", false)) or Vector2(p["vel"]).length() <= pd_speed


## The incoming shot (an entry of arena.projectiles) turret mount `m` of ship `idx` would shoot down now: the nearest enemy one
## (interceptable()) within the `intercept` range of its entry `w`, or null (a weapon without the effect, or nothing in range).
func missile_target(arena, idx: int, m: Dictionary, w: Dictionary):
	var spec = Effects.of(w).get("intercept")
	if not spec is Dictionary:
		return Drones.turret_target(arena, idx, m, w, _uid_of(arena, idx, m), false)  # a gun answers some drones (drones.gd)
	var from: Vector2 = arena.local_to_world(idx, m["pos"])
	var best = null
	var best_d := float(spec["range"]) * float(spec["range"])
	for p in arena.projectiles:
		if p["owner"] == idx or not interceptable(p):
			continue
		var d := from.distance_squared_to(p["pos"])
		if d <= best_d:
			best_d = d
			best = p
	var dr = Drones.turret_target(arena, idx, m, w, _uid_of(arena, idx, m), true)  # point defence counts drones as incoming
	if dr != null and (best == null or float(dr["d2"]) <= best_d):  # (a limpet is seen from further off than a shell)
		return dr
	return best


## The uid of mount `m` of ship `idx` (a drone pick rotates by it).
func _uid_of(arena, idx: int, m: Dictionary) -> int:
	for u in arena.ships[idx].mounts:
		if arena.ships[idx].mounts[u] == m:
			return int(u)
	return 0


## The world point turret mount `m` of ship `idx` aims at to hit the missile `mis`, with perfect lead for the shot's speed.
func missile_point(arena, idx: int, m: Dictionary, w: Dictionary, mis: Dictionary) -> Vector2:
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	return PilotAI.lead_point(arena.local_to_world(idx, m["pos"]), mis["pos"], mis["vel"], speed)


## A point-defence shot at the incoming shot `mis` from `origin`: a tracer to where it is, and it is destroyed when the shot rolls
## its accuracy (no evasion: a shell does not dodge). Logs an `intercept` effect event ({weapon, hit}, at the missile).
func _intercept(arena, idx: int, w: Dictionary, origin: Vector2, mis: Dictionary) -> void:
	var id := str(w["id"])
	var drone: bool = mis.has("drone")  # a drone loses hp instead of being destroyed outright (drones.gd)
	var hit: bool = Drones.shot_at(arena, idx, w, mis, Effects.of(w).get("intercept") is Dictionary) if drone else arena.rng.randf() < float(w["accuracy"])
	arena.log_event("beam", idx, Vector2i(-1, -1), {"weapon": id, "from": origin, "to": mis["pos"], "dtype": w["damage_type"], "shield": false, "bounce": false})
	arena.log_event("effect", idx, Vector2i(-1, -1), {"kind": "intercept", "weapon": id, "hit": hit, "pos": mis["pos"]})
	if hit and not drone:
		arena.projectiles.erase(mis)


## Evasion of ship `idx` (docs/CONTENT.md 4): 0.25 x speed / max speed, plus a manned helm's bonus and
## any running ability's.
func evasion(arena, idx: int) -> float:
	var co = arena.ships[idx]
	var e: float = SPEED_EVASION * co.flight.vel.length() / maxf(co.flight.max_speed, 1.0)
	return e + Jobs.evasion_bonus(co.ship) + Abilities.evasion_add(co.ship)


## The chance a shot of turret `uid` of ship `idx` hits ship `target`: its accuracy less the target's evasion.
func hit_chance(arena, idx: int, uid: int, target: int) -> float:
	return clampf(float(def(arena.ships[idx].mounts[uid]["id"])["accuracy"]) + Hazards.accuracy_add(arena) - evasion(arena, target), 0.0, 1.0)


## The world point turret mount `m` of ship `idx` should aim at to hit ship `target`'s middle, with
## perfect lead for the shot's speed.
func lead_point_of(arena, idx: int, m: Dictionary, target: int) -> Vector2:
	var w := def(m["id"])
	var tc = arena.ships[target]
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	return PilotAI.lead_point(arena.local_to_world(idx, m["pos"]), tc.flight.pos, tc.flight.vel, speed)


## One shot of a turret: roll for a hit (accuracy less evasion, on the arena's rng). A hit gives a random
## outer cell of ship `target` that faces the turret, led; a miss a point just off the hull, on a
## random side. The world point to aim at.
func _turret_point(arena, idx: int, uid: int, m: Dictionary, w: Dictionary, target: int) -> Vector2:
	var tc = arena.ships[target]
	var pivot: Vector2 = arena.local_to_world(idx, m["pos"])
	var speed := float(w["speed"]) if w["kind"] in ["bolt", "flak", "missile"] else 0.0
	var hit: bool = arena.rng.randf() < hit_chance(arena, idx, uid, target)
	var cells := facing_cells(arena, target, pivot)
	if hit and not cells.is_empty():
		var local := Vector2(cells[arena.rng.randi_range(0, cells.size() - 1)]) + Vector2(0.5, 0.5)
		return PilotAI.lead_point(pivot, arena.local_to_world(target, local), _point_velocity(tc, local), speed)
	var side := 1.0 if arena.rng.randf() < 0.5 else -1.0
	var away: Vector2 = (tc.flight.pos - pivot).normalized().rotated(side * PI / 2.0)
	var edge: Vector2 = tc.flight.pos + away * (float(Collisions.hit_cells(arena, target)["radius"]) + MISS_MARGIN)
	return PilotAI.lead_point(pivot, edge, tc.flight.vel, speed)


## The outer cells of ship `target` (Collisions.hit_cells) that have a free face looking toward the
## world point `from`, in (y, x) order.
func facing_cells(arena, target: int, from: Vector2) -> Array:
	var tc = arena.ships[target]
	var hc := Collisions.hit_cells(arena, target)
	var out := []
	for c in hc["cells"]:
		var info: Dictionary = hc["info"][c]
		var centre: Vector2 = tc.flight.pos + Vector2(info["ctr"]).rotated(tc.flight.angle)
		for k in info["n"].size():
			if info["e"][k] and Vector2(info["n"][k]).rotated(tc.flight.angle).dot(from - centre) > 0.0:
				out.append(c)
				break
	return out


## Velocity of the point of ship `co` at ship-local `local` (its drift plus its spin).
static func _point_velocity(co, local: Vector2) -> Vector2:
	var r: Vector2 = ((local - co.pivot) * 32.0).rotated(co.flight.angle)
	return co.flight.vel + r.rotated(PI / 2.0) * co.flight.ang_vel


## Turn the turrets of every ship toward their enemy for one substep (at `track` degrees per second,
## inside the arc) and fire the ones that are loaded and on target, unless the ship's autofire is off.
func tick_turrets(arena) -> void:
	for idx in arena.ships.size():
		var co = arena.ships[idx]
		if co.wrecked:
			continue
		var uids: Array = co.mounts.keys()
		uids.sort()
		for uid in uids:
			var m: Dictionary = co.mounts[uid]
			var w := def(m["id"])
			if status_of(arena, idx, uid) != "ok" or not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
				continue
			var auto := mount_group(arena, idx, uid) == 0  # AUTO fires by itself; a turret in LMB, RMB or Q tracks but holds fire
			if not w["turret"]:
				if auto:
					_auto_fixed(arena, idx, uid, m, w)
				continue
			var tgt := target_of(arena, idx)
			var mis = missile_target(arena, idx, m, w)  # point defence turns on a missile before a ship
			if tgt < 0 and mis == null:
				continue
			var lead: Vector2 = missile_point(arena, idx, m, w, mis) if mis != null else lead_point_of(arena, idx, m, tgt)
			var want: Vector2 = (lead - arena.local_to_world(idx, m["pos"])).rotated(-co.flight.angle)
			var half := deg_to_rad(float(w["arc"]) * 0.5)
			var goal := clampf(Vector2(m["dir"]).angle_to(want), -half, half)  # the barrel's angle from dir that points best
			var cur := Vector2(m["dir"]).angle_to(m["aim"])
			var step: float = deg_to_rad(float(w["track"])) * arena.SUBSTEP
			cur += clampf(angle_difference(cur, goal), -step, step)
			m["aim"] = Vector2(m["dir"]).rotated(cur)
			if auto and arena.autofire.get(idx, true) and not holds_charge(arena, idx, m, tgt) and absf(angle_difference(cur, Vector2(m["dir"]).angle_to(want))) <= deg_to_rad(ON_TARGET_DEG) \
					and arena.cooldown_left(idx, uid) <= 0.0 and (mis != null or _in_range(arena, idx, m, w, tgt)):
				arena.fire(idx, uid, lead)


## A fixed gun in AUTO: it points its barrel at the enemy and fires when the shot bears (the aim is inside the gimbal cone, or the barrel at
## the edge of the cone still lines up on the foe's hull) and the foe is in range - as the enemy pilot's guns do (pilot_ai.gd).
## The T key holds it like a turret.
func _auto_fixed(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> void:
	var tgt := target_of(arena, idx)
	if tgt < 0 or not arena.autofire.get(idx, true):
		return
	var lead: Vector2 = lead_point_of(arena, idx, m, tgt)
	point_barrel(arena, idx, uid, lead)
	if arena.cooldown_left(idx, uid) > 0.0 or holds_charge(arena, idx, m, tgt) or not _in_range(arena, idx, m, w, tgt):
		return
	if not in_arc(arena, idx, m, lead):
		var dir: Vector2 = Vector2(m["aim"]).rotated(arena.ships[idx].flight.angle)
		if not _pilot(arena, idx, tgt).on_hull(muzzle_of(arena, idx, m), dir, float(w["range"])):
			return
	arena.fire(idx, uid, lead)


var _pilots := {}  # ship index -> a PilotAI used only for its on_hull() test


func _pilot(arena, idx: int, foe: int):
	var p = _pilots.get(idx)
	if p == null or p.arena != arena or p.foe != foe:
		p = PilotAI.new(arena, idx, foe)
		_pilots[idx] = p
	return p


## Is some part of ship `target` within the range of weapon `w` of mount `m` (ship `idx`)?
func _in_range(arena, idx: int, m: Dictionary, w: Dictionary, target: int) -> bool:
	var tc = arena.ships[target]
	var from := muzzle_of(arena, idx, m)
	var hc := Collisions.hit_cells(arena, target)
	var reach := float(w["range"])
	var gap := from.distance_to(tc.flight.pos)  # (no cell is nearer than gap - ctr_r or farther than gap + ctr_r: 1 px spares the rounding)
	if gap > reach + float(hc["ctr_r"]) + 1.0:
		return false
	if gap + float(hc["ctr_r"]) + 1.0 < reach and not hc["cells"].is_empty():
		return true
	for c in hc["cells"]:
		if from.distance_to(tc.flight.pos + Vector2(hc["info"][c]["ctr"]).rotated(tc.flight.angle)) <= reach:
			return true
	return false


## What one shot costs: its ammo from the cargo, heat in the part, and the roll to jam it (the part,
## or a virtual mount, stops until repaired). The jam roll is only made for weapons that can jam.
func _spend(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> void:
	var co = arena.ships[idx]
	if str(w["ammo"]) != "":
		Ammo.spend(co.ship, uid, str(w["ammo"]), Effects.ammo_cost(m, w, true))
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
		var m = co.mounts.get(b["uid"])  # a wrecked weapon is gone
		if m == null or arena.tick > b["end"] or co.wrecked or not (m["powered"] if m["virtual"] else co.powered.get(b["uid"], false)):
			continue
		live.append(b)
		if arena.tick < b["next"]:
			continue
		b["next"] += b["every"]
		var w: Dictionary = b["w"].duplicate()
		w["damage"] = float(w["damage"]) * b["every"] * arena.SUBSTEP
		w["fx_k"] = float(b["every"]) * arena.SUBSTEP  # the effects that act per hit (shard, magnetic) scale the same way
		var origin: Vector2 = muzzle_of(arena, b["owner"], {"pos": m["pos"], "aim": b["local_dir"], "reach": m["reach"], "offsets": m.get("offsets", [])}, int(b.get("k", 0)))
		var d: Vector2 = b["local_dir"].rotated(co.flight.angle)
		_line(arena, b["owner"], w, m["id"], origin, origin + d * float(w["range"]))
	arena.beams = live
