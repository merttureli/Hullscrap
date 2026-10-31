extends RefCounted
## Ammo racks, the restock job and the conveyor belts' feed (docs/CONTENT.md 4f). Static functions over a Ship.
## - An ammo rack (family ammo_rack) holds `n` units of one ammo item `ammo` (fields of its component instance, saved).
## - A weapon with `ammo` draws from the racks in the room of its inside half, or, on a belt network that moves, from
##   the nearest rack on it: a belt drive pulls one unit at a time (a drive feeds one unit every stats.belt_interval
##   seconds, the network moves at the best working drive's stats.belt_speed cells a second) and each unit rides the
##   belt, arriving after path length / speed, into the gun's `loaded` units. A ship with NO rack at all draws from
##   the cargo, as before (enemy designs, old saves, the arena's virtual test weapons).
## - A crew job `restock` (jobs.gd) carries ammo from the cargo to a rack below half full.
## - A wrecked rack holding explosive ammo blows up (blast(); damage.gd applies it).
## Refusal reasons of a gun: "no ammo" (cargo mode), "no ammo rack in reach", "rack empty", "belt stopped", and
## "feeding" (the unit is on its way: a reload waits for it). Deterministic: no randomness here.

const Content = preload("res://scripts/data/content.gd")
const Belts = preload("res://scripts/sim/belts.gd")
const CONFIG_PATH := "res://data/ammo.json"
const STEP := 0.1  ## the longest slice tick() simulates in one go, seconds

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return _cfg


# --- what a part is ---------------------------------------------------------------------------------

static func family_of(ship, uid: int) -> String:
	var inst = ship.components.instances.get(uid)
	return "" if inst == null else str(ship.components.def(inst["id"]).get("family", ""))


static func is_rack(ship, uid: int) -> bool:
	return family_of(ship, uid) == "ammo_rack"


## The uids of the ammo racks of `ship`, sorted.
static func rack_uids(ship) -> Array:
	var out := []
	for uid in ship.components.instances:
		if is_rack(ship, uid):
			out.append(uid)
	out.sort()
	return out


## Has `ship` any ammo rack? Then its guns draw from racks; with none they draw from the cargo.
static func uses_racks(ship) -> bool:
	for uid in ship.components.instances:
		if is_rack(ship, uid):
			return true
	return false


## Does weapon `uid` draw from racks (a placed weapon on a ship with a rack) rather than from the cargo?
static func rack_mode(ship, uid: int) -> bool:
	return uid >= 0 and ship.components.instances.has(uid) and uses_racks(ship)


## Is rack `uid` in working order (a disabled one neither gives nor takes)?
static func rack_usable(ship, uid: int) -> bool:
	return is_rack(ship, uid) and ship.components.instances[uid]["status"] == "ok"


static func item_in(ship, uid: int) -> String:
	return str(ship.components.instances[uid].get("ammo", ""))


static func count_in(ship, uid: int) -> int:
	return int(ship.components.instances[uid].get("n", 0))


static func loaded(ship, uid: int) -> int:
	return int(ship.components.instances[uid].get("loaded", 0))


## How many units rack `uid` holds at most: its stats.capacity (else data/ammo.json), times the best
## stats.ammo_cap_mult of a working part in its room (the Grundl Cargo Deck).
static func capacity(ship, uid: int) -> int:
	var inst: Dictionary = ship.components.instances[uid]
	var cap := int(ship.components.def(inst["id"]).get("stats", {}).get("capacity", cfg()["rack"]["capacity"]))
	var mult := 1.0
	var room: int = ship.atmosphere.room_at(inst["cells"][0])
	if room >= 0:
		for other in ship.components.instances:
			var o: Dictionary = ship.components.instances[other]
			var m := float(ship.components.def(o["id"]).get("stats", {}).get("ammo_cap_mult", 1.0))
			if m > mult and o["status"] == "ok" and _rooms_of(ship, o).has(room):
				mult = m
	return roundi(cap * mult)


## The ids of the rooms an instance's cells are in.
static func _rooms_of(ship, inst: Dictionary) -> Array:
	var out := []
	for c in inst["cells"]:
		var r: int = ship.atmosphere.room_at(c)
		if r >= 0 and not out.has(r):
			out.append(r)
	return out


## The ammo item weapon component `id` spends ("" when it needs none), and how many units its shot costs at least (ammo_mult rounded up).
static func ammo_item(weapon_id: String) -> String:
	return str(Content.entry("weapons", weapon_id).get("ammo", ""))


static func shot_cost(weapon_id: String) -> int:
	var e: Dictionary = Content.entry("weapons", weapon_id)
	var fx = e.get("effects")
	var mult := float(e.get("ammo_mult", fx.get("ammo_mult", 1.0) if fx is Dictionary else 1.0))
	return maxi(1, ceili(mult - 1e-9))


static func explosive(item: String) -> bool:
	return bool(Content.entry("items", item).get("explosive", false))


# --- who can reach what ------------------------------------------------------------------------------

## The usable racks in the room of weapon `uid`'s inside half, sorted.
static func room_racks(ship, uid: int) -> Array:
	var rooms := _rooms_of(ship, ship.components.instances[uid])
	var out := []
	for r in rack_uids(ship):
		if rack_usable(ship, r) and rooms.has(ship.atmosphere.room_at(ship.components.instances[r]["cells"][0])):
			out.append(r)
	return out


## Units of `item` in the usable racks of weapon `uid`'s room.
static func room_stock(ship, uid: int, item: String) -> int:
	var n := 0
	for r in room_racks(ship, uid):
		if item_in(ship, r) == item:
			n += count_in(ship, r)
	return n


## Can belt-fed weapon `uid` get ammo? "" when it has `cost` units of `item` now (its feed plus the racks of its room);
## else why not: "no ammo" (cargo mode: the cargo has too little), "no ammo rack in reach", "rack empty", "belt stopped"
## (rack ammo is on its belt, but no working drive moves it) or "feeding" (it is on its way).
static func refusal(ship, uid: int, item: String, cost: int) -> String:
	if not rack_mode(ship, uid):
		return "" if ship.inventory.count(item) >= cost else "no ammo"
	ship.refresh()
	if loaded(ship, uid) + room_stock(ship, uid, item) >= cost:
		return ""
	var b = ship.belts
	var plan: Dictionary = b.analyze(ship) if not b.cells.is_empty() else {}
	var racks := room_racks(ship, uid)
	var net_stock := 0
	var moving := false
	var on_belt := false
	for net_id in plan.get("touch", {}).get(uid, []):
		var net: Dictionary = plan["nets"][net_id]
		for r in net["racks"]:
			if rack_usable(ship, r):
				on_belt = true
				if not racks.has(r):
					racks.append(r)
				if item_in(ship, r) == item:
					net_stock += count_in(ship, r)
		if net_speed(ship, net) > 0.0:
			moving = true
	if racks.is_empty():
		return "no ammo rack in reach"
	for u in b.units:
		if u["to"] == uid:
			return "feeding"
	if net_stock > 0:
		return "feeding" if moving else "belt stopped"
	return "rack empty"


## Could weapon `uid` shoot `cost` units of `item` as soon as its feed delivers (refusal is "" or "feeding")?
static func can_supply(ship, uid: int, item: String, cost: int) -> bool:
	return refusal(ship, uid, item, cost) in ["", "feeding"]


## Weapon `uid` fires: `cost` units go out of its feed, then the racks of its room (cargo mode: out of the cargo).
static func spend(ship, uid: int, item: String, cost: int) -> void:
	if cost <= 0:
		return
	if not rack_mode(ship, uid):
		ship.inventory.add(item, -cost)
		return
	var inst: Dictionary = ship.components.instances[uid]
	var take := mini(int(inst.get("loaded", 0)), cost)
	inst["loaded"] = int(inst.get("loaded", 0)) - take
	var left := cost - take
	for r in room_racks(ship, uid):
		if left <= 0:
			break
		if item_in(ship, r) == item:
			var t := mini(count_in(ship, r), left)
			ship.components.instances[r]["n"] = count_in(ship, r) - t
			left -= t


# --- belts: drives, networks, the feed ----------------------------------------------------------------

## Cells a second belt drive `uid` moves its belt at: 0 when it is not working (not ok, no power, an ion hit).
static func drive_speed(ship, uid: int) -> float:
	var inst = ship.components.instances.get(uid)
	if inst == null or inst["status"] != "ok" or not bool(ship.power_state.get("powered", {}).get(uid, false)):
		return 0.0
	if float(ship.belts.ion.get(uid, 0.0)) > 0.0 or ship.components.offline_reason(ship.grid, uid) != "":
		return 0.0
	return float(ship.components.def(inst["id"]).get("stats", {}).get("belt_speed", 0.0))


## The best working drive speed on `net` (a Belts.analyze net): 0 when none works.
static func net_speed(ship, net: Dictionary) -> float:
	var best := 0.0
	for d in net["drives"]:
		best = maxf(best, drive_speed(ship, d))
	return best


## Is the belt network of `cell` moving (a working drive on it)? For the scrolling treads.
static func moving_at(ship, cell: Vector2i) -> bool:
	var plan: Dictionary = ship.belts.analyze(ship)
	var id: int = plan["net_of"].get(cell, -1)
	return id >= 0 and net_speed(ship, plan["nets"][id]) > 0.0


## Does the ship hold or carry a belt drive (the first one comes with the belt blueprint)?
static func has_drive(ship) -> bool:
	for id in ship.inventory.counts:
		if ship.inventory.counts[id] > 0 and str(ship.components.def(id).get("family", "")) == "belt_drive":
			return true
	for uid in ship.components.instances:
		if family_of(ship, uid) == "belt_drive":
			return true
	return false


## The belt blueprint: known once a belt drive was aboard (and then for good). Latches `belts.known`.
static func learn(ship) -> bool:
	if not ship.belts.known and has_drive(ship):
		ship.belts.known = true
		ship.log_event("Belt blueprint learned: lay belts from the Structure tab")
	return ship.belts.known


## May the player lay belts now: the blueprint is known, or a drive is aboard.
static func belts_unlocked(ship) -> bool:
	return ship.belts.known or has_drive(ship)


## Advance the belts of `ship` by `dt` seconds: units ride, drives feed the guns that want ammo.
static func tick(ship, dt: float) -> void:
	var b = ship.belts
	b.learn_wait -= dt
	if b.learn_wait <= 0.0:  # a drive aboard teaches the belt blueprint; looked for once a second
		b.learn_wait = 1.0
		learn(ship)
	if dt <= 0.0 or (b.cells.is_empty() and b.units.is_empty()):
		return
	var n := maxi(1, ceili(dt / STEP - 1e-9))
	for i in n:
		_slice(ship, dt / n)


static func _slice(ship, h: float) -> void:
	var b = ship.belts
	ship.refresh()
	var plan: Dictionary = b.analyze(ship)
	b.clock += h
	for uid in b.ion.keys():
		b.ion[uid] = float(b.ion[uid]) - h
		if b.ion[uid] <= 0.0:
			b.ion.erase(uid)
	var speed := {}  # net id -> the best working drive's cells a second
	var working := {}  # net id -> its working drives
	for net in plan["nets"]:
		for d in net["drives"]:
			var s := drive_speed(ship, d)
			if s > 0.0:
				speed[net["id"]] = maxf(float(speed.get(net["id"], 0.0)), s)
				if not working.has(net["id"]):
					working[net["id"]] = []
				working[net["id"]].append(d)
	var keep := []
	var inflight := {}  # weapon uid -> units on their way to it
	for u in b.units:
		if not _unit_ok(ship, plan, u):
			_return_unit(ship, u)
			continue
		u["p"] = float(u["p"]) + float(speed.get(plan["net_of"][u["path"][0]], 0.0)) * h
		if float(u["p"]) >= float(u["path"].size()) - 1e-9:
			var gun: Dictionary = ship.components.instances[u["to"]]
			gun["loaded"] = int(gun.get("loaded", 0)) + 1
		else:
			keep.append(u)
			inflight[u["to"]] = int(inflight.get(u["to"], 0)) + 1
	b.units = keep
	if speed.is_empty():
		return
	var wants := []  # [units it has or has coming, uid, item]: the emptiest gun is served first
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	var chamber := int(cfg()["chamber_shots"])
	for uid in uids:
		if family_of(ship, uid) != "weapon" or not plan["touch"].has(uid):
			continue
		var inst: Dictionary = ship.components.instances[uid]
		var item := ammo_item(inst["id"])
		if item == "" or inst["status"] != "ok" or ship.components.offline_reason(ship.grid, uid) != "":
			continue
		var cost := shot_cost(inst["id"])
		var have := int(inst.get("loaded", 0)) + int(inflight.get(uid, 0))
		if have >= cost * chamber or room_stock(ship, uid, item) >= cost:
			continue
		wants.append([have, uid, item])
	wants.sort_custom(func(a, c): return a[0] < c[0] or (a[0] == c[0] and a[1] < c[1]))
	for w in wants:
		for net_id in plan["touch"][w[1]]:
			var drive := _free_drive(b, working.get(net_id, []))
			if drive >= 0 and _launch(ship, plan, w[1], w[2], net_id, drive, float(speed[net_id])):
				break


## The working drive among `drives` that may feed a unit now, else -1.
static func _free_drive(b, drives: Array) -> int:
	for d in drives:
		if float(b.drive_free.get(d, 0.0)) <= b.clock + 1e-9:
			return d
	return -1


## Pull one unit of `item` from the nearest rack with some on the belt network `net_id` for weapon `gun`, through drive
## `drive`. False when no rack there has any.
static func _launch(ship, plan: Dictionary, gun: int, item: String, net_id: int, drive: int, _speed: float) -> bool:
	var goal := {}  # belt cell beside a rack with the item -> its uid (the lowest)
	for r in plan["nets"][net_id]["racks"]:
		if rack_usable(ship, r) and item_in(ship, r) == item and count_in(ship, r) > 0:
			for c in plan["edge"][r]:
				if plan["net_of"][c] == net_id and not goal.has(c):
					goal[c] = r
	if goal.is_empty():
		return false
	var starts: Array = plan["edge"][gun].filter(func(c): return plan["net_of"][c] == net_id)
	var found: Dictionary = Belts.route(plan["net_of"], starts, goal)
	if found.is_empty():
		return false
	var rack: Dictionary = ship.components.instances[found["uid"]]
	rack["n"] = int(rack["n"]) - 1
	ship.belts.units.append({"item": item, "from": found["uid"], "to": gun, "path": found["path"], "p": 0.0, "plan": ship.belts.plan_id})
	var every := float(ship.components.def(ship.components.instances[drive]["id"]).get("stats", {}).get("belt_interval", 1.0))
	ship.belts.drive_free[drive] = ship.belts.clock + every
	return true


## Is unit `u` still good: its gun and rack there, its path still a live belt? Rechecked when the plan changed.
static func _unit_ok(ship, plan: Dictionary, u: Dictionary) -> bool:
	if int(u["plan"]) == ship.belts.plan_id:
		return true
	var gun = ship.components.instances.get(u["to"])
	if gun == null or gun["status"] != "ok" or not ship.components.instances.has(u["from"]):
		return false
	var net: int = plan["net_of"].get(u["path"][0], -1)
	for c in u["path"]:
		if net < 0 or plan["net_of"].get(c, -2) != net:
			return false
	u["plan"] = ship.belts.plan_id
	return true


## A unit that cannot go on goes back into its rack (or is lost with the rack).
static func _return_unit(ship, u: Dictionary) -> void:
	var rack = ship.components.instances.get(u["from"])
	if rack != null and (str(rack.get("ammo", "")) == u["item"] or int(rack.get("n", 0)) == 0):
		rack["ammo"] = u["item"]
		rack["n"] = int(rack.get("n", 0)) + 1


## Damage landed on `cell` of `ship`: the belt on it and on the four cells beside it is cut. Returns how many were cut.
static func cut_near(ship, cell: Vector2i) -> int:
	var b = ship.belts
	if b.cells.is_empty():
		return 0
	var n := 0
	for d in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if b.cut_cell(cell + d):
			n += 1
	return n


## An ion hit on part `uid`: a belt drive with stats.belt_ion_stop stops for data/ammo.json ion_stop_s.
static func ion_hit(ship, uid: int) -> void:
	var inst = ship.components.instances.get(uid)
	if inst != null and float(ship.components.def(inst["id"]).get("stats", {}).get("belt_ion_stop", 0.0)) > 0.0:
		ship.belts.ion[uid] = float(cfg()["ion_stop_s"])


# --- the restock job --------------------------------------------------------------------------------

## The ammo item rack `uid` should be stocked with: what it holds, else (empty) what the guns in its reach spend, the first the
## cargo has. "" when there is none to carry.
static func wanted_item(ship, uid: int) -> String:
	var inst: Dictionary = ship.components.instances[uid]
	if int(inst.get("n", 0)) > 0:
		return item_in(ship, uid) if ship.inventory.count(item_in(ship, uid)) > 0 else ""
	var options: Array = []
	if item_in(ship, uid) != "":
		options.append(item_in(ship, uid))
	var room: int = ship.atmosphere.room_at(inst["cells"][0])
	var plan: Dictionary = ship.belts.analyze(ship) if not ship.belts.cells.is_empty() else {}
	var uids: Array = ship.components.instances.keys()
	uids.sort()
	for g in uids:
		if family_of(ship, g) != "weapon":
			continue
		var item := ammo_item(ship.components.instances[g]["id"])
		if item == "" or options.has(item):
			continue
		var near: bool = _rooms_of(ship, ship.components.instances[g]).has(room)
		for net_id in plan.get("touch", {}).get(uid, []):
			if plan["nets"][net_id]["weapons"].has(g):
				near = true
		if near:
			options.append(item)
	for g in uids:  # a magazine with no gun beside it yet: whatever the ship's guns spend
		if family_of(ship, g) == "weapon":
			var item := ammo_item(ship.components.instances[g]["id"])
			if item != "" and not options.has(item):
				options.append(item)
	for item in options:
		if ship.inventory.count(item) > 0:
			return item
	return ""


## The racks that want a restock job: below the `restock_below` fraction of their capacity, or in `active` (uid -> true: a
## crew member is already filling them) and not full, and with an item in the cargo to carry. Sorted.
static func restock_uids(ship, active: Dictionary) -> Array:
	var out := []
	var below := float(cfg()["rack"]["restock_below"])
	for uid in rack_uids(ship):
		if not rack_usable(ship, uid):
			continue
		var cap := capacity(ship, uid)
		var n := count_in(ship, uid)
		if (float(n) < float(cap) * below or (active.has(uid) and n < cap)) and wanted_item(ship, uid) != "":
			out.append(uid)
	return out


## A crew member carries up to `units` units from the cargo into rack `uid`. Returns how many went in.
static func restock(ship, uid: int, units: int) -> int:
	var item := wanted_item(ship, uid)
	if item == "" or units <= 0:
		return 0
	var inst: Dictionary = ship.components.instances[uid]
	var moved := mini(mini(units, capacity(ship, uid) - count_in(ship, uid)), ship.inventory.count(item))
	if moved <= 0:
		return 0
	inst["ammo"] = item
	inst["n"] = count_in(ship, uid) + moved
	ship.inventory.add(item, -moved)
	return moved


## Is rack `uid` as full as a restock goes (full, or nothing to carry)?
static func restock_done(ship, uid: int) -> bool:
	return not rack_usable(ship, uid) or count_in(ship, uid) >= capacity(ship, uid) or wanted_item(ship, uid) == ""


# --- wrecks, building, saving --------------------------------------------------------------------------

## What rack `uid` does when it is wrecked: {} for most; for one holding explosive ammo {units, item, damage, cells (its room's cells), at}.
static func blast(ship, uid: int) -> Dictionary:
	var inst = ship.components.instances.get(uid)
	if inst == null or not is_rack(ship, uid):
		return {}
	var n := count_in(ship, uid)
	if n <= 0 or not explosive(item_in(ship, uid)):
		return {}
	var room: int = ship.atmosphere.room_at(inst["cells"][0])
	var cells: Array = ship.atmosphere.rooms[room]["cells"].duplicate() if room >= 0 else inst["cells"].duplicate()
	return {"units": n, "item": item_in(ship, uid), "damage": float(n) * float(cfg()["blast_per_unit"]), "cells": cells, "at": inst["cells"][0]}


## Empty what part `uid` holds into the cargo (a rack's units, a gun's loaded ones), because it is taken out or sold.
## Returns {ammo, n, loaded} of what it held (to put back with load_stock), {} when it held nothing.
static func unload(ship, uid: int) -> Dictionary:
	var inst = ship.components.instances.get(uid)
	if inst == null:
		return {}
	var out := {}
	var n := int(inst.get("n", 0))
	if n > 0 and str(inst.get("ammo", "")) != "":
		ship.inventory.add(str(inst["ammo"]), n)
		out = {"ammo": str(inst["ammo"]), "n": n}
	var l := int(inst.get("loaded", 0))
	if l > 0:
		var item := ammo_item(inst["id"])
		if item != "":
			ship.inventory.add(item, l)
			out["loaded"] = l
	return out


## The record load_stock takes: a part's saved contents as part of a components.gd instance record.
static func stock_into(rec: Dictionary, stock: Dictionary) -> void:
	for k in ["ammo", "n", "loaded"]:
		if stock.has(k):
			rec[k] = stock[k]


## Units still riding the belts go back into their racks in a saved components dictionary (`comps`: Components.to_dict()),
## so a save loses none.
static func stow_units(ship, comps: Dictionary) -> void:
	for u in ship.belts.units:
		for rec in comps["instances"]:
			if int(rec["uid"]) == int(u["from"]):
				rec["ammo"] = u["item"]
				rec["n"] = int(rec.get("n", 0)) + 1


# --- drawing helpers ----------------------------------------------------------------------------------

## The animation of a rack's art for what it holds (fill_0..4 for missiles, scrap_0..4, slug_0..4), "" when the part is no
## rack or the sheet has none. `opts.fill_cap`: what the rack holds at most (draw_opts), else its stats.capacity.
static func fill_anim(def: Dictionary, inst: Dictionary, sheet, opts := {}) -> String:
	if str(def.get("family", "")) != "ammo_rack" or not inst.has("n"):
		return ""
	var cap := maxi(1, int(opts.get("fill_cap", def.get("stats", {}).get("capacity", cfg()["rack"]["capacity"]))))
	var level := clampi(ceili(4.0 * float(int(inst["n"])) / float(cap) - 1e-6), 0, 4)
	var prefix: String = {"scrap": "scrap", "slug": "slug"}.get(str(inst.get("ammo", "")), "fill")
	var name := "%s_%d" % [prefix, level]
	return name if sheet.has_anim(name) else ""


## Extra draw options for component `uid` (Visuals.draw_component's opts): a rack's real capacity.
static func draw_opts(ship, uid: int) -> Dictionary:
	return {"fill_cap": capacity(ship, uid)} if is_rack(ship, uid) else {}
