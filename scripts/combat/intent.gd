extends RefCounted
## Enemy intent (README "Combat"): what the enemy pilot is about to hit, for the player's schematic to show
## (Into the Breach's lesson in real time: see the shot coming, then move the shield balance or turn the armour).
## Static and read-only on the fight (the pilot is not changed). `of(arena, ai, foe_idx)` returns
##   {target_uid, target_family, heavy}
## - target_uid: the part of ship `foe_idx` (the player) that the pilot `ai` aims at (pilot_ai.target_uid), -1 for
##   none. A new target is shown only once the one before it has been up for `hold_s`, so the reticle does not
##   flicker; a part that is gone switches it at once. The shown target is kept as meta on the pilot.
## - heavy: [{uid, name, eta}] for the enemy's weapons that can shoot (ok, powered, with ammo), are heavy and
##   have `eta` <= `warn_s` seconds of cooldown left, in uid order. Heavy: damage >= `heavy_damage`, or a shot
##   kind in `heavy_kinds` (missile, beam), or a damage type in `heavy_damage_types` (ion). A gun that fires faster
##   than you can react (a cooldown under `min_cooldown`) is never warned about, whatever its damage.
## - Nothing once either ship is wrecked or the enemy pilot holds fire (surrendering) or has stopped.
## Numbers: data/combat_ui.json, "intent".

const Effects = preload("res://scripts/combat/effects.gd")
const Ammo = preload("res://scripts/sim/ammo.gd")

const CONFIG_PATH := "res://data/combat_ui.json"
const META := "intent_shown"  ## meta on the pilot: {uid, tick} of the target now shown and when it was first shown

static var _config := {}  # data/combat_ui.json "intent", read on first use


## The "intent" entry of data/combat_ui.json (read once; empty when the file is missing or unusable).
static func config() -> Dictionary:
	if _config.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if data is Dictionary and data.get("intent") is Dictionary:
			_config = data["intent"]
	return _config


static func empty() -> Dictionary:
	return {"target_uid": -1, "target_family": "", "heavy": []}


## What enemy pilot `ai` is about to do to ship `foe_idx` (see the top).
static func of(arena, ai, foe_idx: int) -> Dictionary:
	var out := empty()
	var co = arena.ships[ai.me]
	var foe = arena.ships[foe_idx]
	var mode: String = ai.morale.pilot_mode() if ai.morale != null else ""
	if co.wrecked or foe.wrecked or mode in ["hold", "stop"]:
		return out
	var cfg := config()
	var uid := _shown(arena, ai, foe_idx, int(ai.target_uid), float(cfg.get("hold_s", 0.5)))
	if uid >= 0:
		out["target_uid"] = uid
		out["target_family"] = str(foe.ship.components.def(foe.ship.components.instances[uid]["id"]).get("family", ""))
	var warn := float(cfg.get("warn_s", 1.5))
	var uids: Array = co.mounts.keys()
	uids.sort()
	for u in uids:
		var m: Dictionary = co.mounts[u]
		var w: Dictionary = arena.weapons.def(m["id"])
		if not warns(w, cfg) or not _can_shoot(arena, ai.me, u, m, w):
			continue
		var eta: float = arena.cooldown_left(ai.me, u)
		if eta <= warn + 1e-6:
			out["heavy"].append({"uid": u, "name": str(co.ship.components.def(m["id"]).get("name", m["id"])), "eta": eta})
	return out


## Is weapon `w` (Weapons.def) heavy by the numbers of `cfg`?
static func is_heavy(w: Dictionary, cfg := config()) -> bool:
	return float(w["damage"]) >= float(cfg.get("heavy_damage", 3.0)) or str(w["kind"]) in cfg.get("heavy_kinds", ["missile", "beam"]) \
		or str(w["damage_type"]) in cfg.get("heavy_damage_types", ["ion"])


## Does weapon `w` earn a warning row: heavy, and slow enough (cooldown >= `min_cooldown`) that the warning is a thing to react to?
static func warns(w: Dictionary, cfg := config()) -> bool:
	return is_heavy(w, cfg) and float(w["cooldown"]) >= float(cfg.get("min_cooldown", 3.0)) - 1e-6


## The target to show: the pilot's own, but a new one only after the shown one has been up for `hold_s`.
static func _shown(arena, ai, idx: int, cur: int, hold_s: float) -> int:
	if cur >= 0 and not _alive(arena, idx, cur):
		cur = -1  # the pilot has not noticed yet that it is gone
	var st: Dictionary = ai.get_meta(META, {"uid": -1, "tick": 0})
	var uid: int = st["uid"]
	if cur != uid and (uid < 0 or not _alive(arena, idx, uid) or arena.tick - int(st["tick"]) >= roundi(hold_s / arena.SUBSTEP)):
		uid = cur
		ai.set_meta(META, {"uid": uid, "tick": arena.tick})
	return uid


## The pilot's own test for a part worth aiming at (pilot_ai._part_ok): there, not disabled, with hp, and online.
static func _alive(arena, idx: int, uid: int) -> bool:
	var ship = arena.ships[idx].ship
	var inst = ship.components.instances.get(uid)
	return inst != null and inst.get("status", "ok") != "disabled" and float(inst.get("hp", 1)) > 0.0 and ship.components.offline_reason(ship.grid, uid) == ""


## Could mount `uid` shoot as soon as it is cooled down? (Not out of action, powered, with ammo: Weapons.can_fire less the cooldown and aim.)
static func _can_shoot(arena, idx: int, uid: int, m: Dictionary, w: Dictionary) -> bool:
	var co = arena.ships[idx]
	if arena.weapons.status_of(arena, idx, uid) != "ok" or not (m["powered"] if m["virtual"] else co.powered.get(uid, false)):
		return false
	var ammo := str(w["ammo"])
	return ammo == "" or Ammo.can_supply(co.ship, uid, ammo, maxi(Effects.ammo_cost(m, w), 1))


## "Artemis Mk1" -> "Artemis".
static func short_name(part_name: String) -> String:
	var words := part_name.split(" ", false)
	if words.size() > 1 and words[-1].begins_with("Mk"):
		words.remove_at(words.size() - 1)
	return " ".join(words)


## A part family as the reticle's line names it: "weapon" -> "Weapons".
static func family_label(family: String) -> String:
	return str(config().get("family_names", {}).get(family, family.capitalize()))
