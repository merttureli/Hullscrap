extends RefCounted
## Component definitions (data/components.json) and the components placed on a ship.
## A placed component is an instance with a footprint of grid cells and some runtime state
## (hp, heat, status). Pure data, no nodes.

const Stats = preload("res://scripts/sim/stats.gd")
const Content = preload("res://scripts/data/content.gd")
const Mounts = preload("res://scripts/ship/mounts.gd")
## Save format. 2 adds each instance's hp, heat and status; 3 adds the outside half of a hull mount
## (`out`, `out_hp`) and the wrecks; versions 1 and 2 still load (full hp, cold, ok; a weapon or engine
## with no `out` is mounted through the wall on its outward side if it can be, else back to the cargo). 4 adds the
## optional contents of an ammo rack (`ammo`, `n`) and the units a gun has loaded from a belt (`loaded`). 5 adds the
## mounts on a slope: `angle` (degrees clockwise from up; absent when it is the quarter turn `rot` x 90), `at` (the base
## middle of the outside half on the face) and the cells it holds, `ocells` (empty space under the barrel) and `link`.
## 6 is the gun rework (docs/GUNS.md 8): the guns have new outside halves (shapes of any size), so a mount saved before 6 whose gun
## changed shape (_reshaped()) is re-planned from its inside half; one whose new outside half does not fit goes back to the cargo.
## 7 adds the optional fire group a player chose for a fixed gun (`group`, 1 or 2; absent: the kind's default); older saves load with the defaults.
## 8 widens the choice to every gun and four groups: `group` 1 (LMB), 2 (RMB), 3 (Q) or 0 (AUTO); absent still means the kind's default.
## 9: the fabricator has its own level (`fab_level`, 1 to 4); an older save's takes the level its room's modules gave it (Workshop.migrate)
const VERSION := 9
const FAB := "fabricator"
const ONE_FAB := "One fabricator per ship: click yours to upgrade it"
const OLD_OUTSIDE := [4, 2]  ## the outside half every gun had before version 6 ...
const OLD_OUTSIDE_OF := {"shrapnel_cannon_scrap": [4, 3]}  ## ... but this one
const MIN_VERSION := 1
## An instance's status: ok, or one of the ways it can be out of action.
const STATUSES: Array[String] = ["ok", "overheated", "malfunction", "disabled"]

var by_id := {}
var order: Array[String] = []
var instances := {}  # uid -> {uid, id, anchor, rot, angle, cells, hp, heat, status, out_anchor, out_at, out_cells, link, out_hp}; out_at only means something on a slope (Mounts.is_angled)
var wrecks: Array = []  # [{id, cells}]: parts shot to pieces, their debris on the floor until a crew member clears it
var legacy_fabs: Array[int] = []  # fabricators the last load_dict() read with no saved level: Ship.load_dict gives them the level their modules made (Workshop.migrate)
var returned: Array[Dictionary] = []  # what the last load_dict() could not mount: [{id, text}] (the caller returns them to the cargo)
var _cell_uid := {}  # Vector2i -> uid of the component covering it (inside halves)
var _out_uid := {}  # Vector2i -> uid of the mount whose outside half covers it
var _next_uid := 1   # only grows, so a uid is never reused


func load_defs(path: String) -> void:
	var data = Content.read(path)
	assert(data is Dictionary and data.has("components"), "bad component data: " + path)
	for d in data["components"]:
		for k in ["power", "priority", "tier"]:
			d[k] = int(d.get(k, 0))
		d["hp"] = Stats.max_hp(d)
		d["size"] = [int(d["size"][0]), int(d["size"][1])]
		if d.get("mount") is Dictionary:
			d["mount"] = {"outside": [int(d["mount"]["outside"][0]), int(d["mount"]["outside"][1])], "outside_hp": int(d["mount"]["outside_hp"])}
		if not by_id.has(d["id"]):
			order.append(d["id"])
		by_id[d["id"]] = d


func ids() -> Array[String]:
	return order


## Is `version` a save version this class can load?
static func supports(version: int) -> bool:
	return version >= MIN_VERSION and version <= VERSION


func has(id: String) -> bool:
	return by_id.has(id)


func def(id: String) -> Dictionary:
	return by_id.get(id, {})


## Cells covered by `id` at `anchor` after `rot` quarter turns. Odd turns swap width and height.
## The anchor is the top-left cell of the rotated footprint. Empty for an unknown id.
func footprint(id: String, anchor: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not by_id.has(id):
		return out
	var s: Array = by_id[id]["size"]
	var swap := posmod(rot, 2) == 1
	var w := int(s[1 if swap else 0])
	var h := int(s[0 if swap else 1])
	for y in h:
		for x in w:
			out.append(anchor + Vector2i(x, y))
	return out


## Why `id` cannot go there, or "" when it can. Every cell needs a floor tile inside the hull.
func can_place(grid, id: String, anchor: Vector2i, rot: int) -> String:
	if not by_id.has(id):
		return "unknown component"
	var cells := footprint(id, anchor, rot)
	for c in cells:
		if not grid.in_hull(c):
			return "outside the hull"
	for c in cells:
		if not _is_floor(grid, c):
			return "needs floor underneath"
	if id == FAB and has_fabricator():
		return ONE_FAB
	for c in cells:
		if _cell_uid.has(c):
			return "overlaps " + str(by_id[instances[_cell_uid[c]]["id"]]["name"])
		if wreck_at(c) >= 0:
			return "wreckage in the way"
	return ""


## Does the ship already have a fabricator? (One per ship.)
func has_fabricator() -> bool:
	for uid in instances:
		if instances[uid]["id"] == FAB:
			return true
	return false


## Can part `id` be shot to pieces? The fabricator cannot: a hit only disables it (repairable), or the run would lose crafting for good.
func can_wreck(id: String) -> bool:
	return not bool(by_id.get(id, {}).get("no_wreck", false))


## Place a component. Returns its new uid, or -1 when it cannot go there. A hull mount placed this
## way has no outside half (see place_mount()).
func place(grid, id: String, anchor: Vector2i, rot: int) -> int:
	if can_place(grid, id, anchor, rot) != "":
		return -1
	var uid := _next_uid
	_next_uid += 1
	_add(uid, id, anchor, rot)
	return uid


## The fire group the player chose for gun `uid`: 1 (LMB), 2 (RMB), 3 (Q), 0 (AUTO), or -1 for the kind's default.
func group_choice(uid: int) -> int:
	return int(instances[uid].get("group", -1)) if instances.has(uid) else -1


## Choose gun `uid`'s fire group (0-3; -1 goes back to the default).
func set_group_choice(uid: int, group: int) -> void:
	if instances.has(uid) and group in [-1, 0, 1, 2, 3] and str(def(str(instances[uid]["id"])).get("family", "")) != "drone_bay":  # (a drone bay is never in a fire group: only its key launches it)
		if group < 0:
			instances[uid].erase("group")
		else:
			instances[uid]["group"] = group


## Is `id` a hull mount (a weapon or engine with an outside half)?
func is_mount(id: String) -> bool:
	return Mounts.is_mount(def(id))


## How mount `id` turned `rot` would sit with its outside half's top-left on `out`: Mounts.plan().
## `why` is "" when it can go there.
func plan_mount(grid, id: String, out: Vector2i, rot: int) -> Dictionary:
	if not is_mount(id):
		return {"why": "not a hull mount"}
	return Mounts.plan(grid, self, by_id[id], out, rot)


## Why mount `id` cannot go with its outside half on `out`, or "".
func can_place_mount(grid, id: String, out: Vector2i, rot: int) -> String:
	if not by_id.has(id):
		return "unknown component"
	return plan_mount(grid, id, out, rot)["why"]


## Where mount `id` can go when the pointer is at `point` (grid coordinates) and R has it turned `rot`: plan_mount() with its
## outside half's top-left on `out`, unless that fails and a sloped hull face is near `point`; then Mounts.plan_slope() against
## that face (the plan has `angle`, `at`). Always has why, rot and out.
func plan_mount_at(grid, id: String, out: Vector2i, rot: int, point := Vector2.INF) -> Dictionary:
	var plan := plan_mount(grid, id, out, rot)
	if plan["why"] == "" or not is_mount(id):
		plan.merge({"rot": posmod(rot, 4), "out": out}, true)
		return plan
	var slope := Mounts.plan_slope(grid, self, by_id[id], Vector2(out) + Vector2(0.5, 0.5) if point == Vector2.INF else point)
	if not slope["angled"]:
		plan.merge({"rot": posmod(rot, 4), "out": out}, true)
		return plan
	return slope


## Place mount `id` as `plan` (plan_mount_at(); a straight plan needs the `rot` and `out` it was made with). Returns its new
## uid, or -1 when the plan is refused.
func place_planned(id: String, plan: Dictionary) -> int:
	if plan.get("why", "x") != "":
		return -1
	var uid := _next_uid
	_next_uid += 1
	_add(uid, id, plan["anchor"], int(plan["rot"]), plan["out"], plan)
	return uid


## Place mount `id`, outside half's top-left on `out`. Returns its new uid, or -1 when it cannot go there.
func place_mount(grid, id: String, out: Vector2i, rot: int) -> int:
	var plan := plan_mount(grid, id, out, rot)
	if plan["why"] != "":
		return -1
	var uid := _next_uid
	_next_uid += 1
	_add(uid, id, plan["anchor"], rot, out, plan)
	return uid


## Remove the component covering `c` (either half of a mount takes both). Returns its id, or "" when
## the cell is empty.
func remove_at(c: Vector2i) -> String:
	var uid := any_at(c)
	if uid < 0:
		return ""
	return remove_uid(uid)


## Remove component `uid`. Returns its id, or "" for an unknown uid.
func remove_uid(uid: int) -> String:
	if not instances.has(uid):
		return ""
	var id: String = instances[uid]["id"]
	for cell in instances[uid]["cells"]:
		_cell_uid.erase(cell)
	for cell in instances[uid]["out_cells"]:
		_out_uid.erase(cell)
	instances.erase(uid)
	return id


## Uid of the component whose inside half covers `c` (a part's only half unless it is a mount), or -1.
func at(c: Vector2i) -> int:
	return _cell_uid.get(c, -1)


## Uid of the mount whose outside half covers `c`, or -1.
func at_out(c: Vector2i) -> int:
	return _out_uid.get(c, -1)


## Uid of the component with either half on `c`, or -1.
func any_at(c: Vector2i) -> int:
	return _cell_uid.get(c, _out_uid.get(c, -1))


## Uid of a mount whose link (the wall between its halves) runs through `c`, or -1.
func link_at(c: Vector2i) -> int:
	var uids := instances.keys()
	uids.sort()
	for uid in uids:
		if instances[uid]["link"].has(c):
			return uid
	return -1


## Floor with nothing on it: a floor-type tile, no part and no wreckage.
func free_floor(grid, c: Vector2i) -> bool:
	return _is_floor(grid, c) and not _cell_uid.has(c) and wreck_at(c) < 0


## Does mount `uid` have an outside half that still works (its hp is above 0)?
func outside_alive(uid: int) -> bool:
	var inst: Dictionary = instances.get(uid, {})
	return not inst.is_empty() and not inst["out_cells"].is_empty() and float(inst["out_hp"]) > 0.0


## Does mount `uid` have an outside half at all?
func has_outside(uid: int) -> bool:
	return not instances[uid]["out_cells"].is_empty()


## Is every cell of the link of `uid` still a wall? A breached link cell cuts the mount off (no feed,
## power or control) until it is patched. A part with no outside half has no link to cut.
func link_intact(grid, uid: int) -> bool:
	for c in instances[uid]["link"]:
		if grid.get_tile(c) == "":
			return false
	return true


## Why mount `uid` is out of action because of its outside half or its link, else "": "outside half
## disabled" or "link cut". Parts that are not mounts (or have no outside half) are never offline here.
func offline_reason(grid, uid: int) -> String:
	var inst: Dictionary = instances.get(uid, {})
	if inst.is_empty() or inst["out_cells"].is_empty():
		return ""
	if float(inst["out_hp"]) <= 0.0:
		return "outside half disabled"
	return "" if link_intact(grid, uid) else "link cut"


## Maximum hp of the outside half of mount `id`.
func outside_hp_max(id: String) -> int:
	return int(by_id[id].get("mount", {}).get("outside_hp", 0))


# --- wrecks -------------------------------------------------------------------------------------

## Index into `wrecks` of the debris on `c`, or -1.
func wreck_at(c: Vector2i) -> int:
	for i in wrecks.size():
		if wrecks[i]["cells"].has(c):
			return i
	return -1


## Part `uid` is shot to pieces: it is gone (both halves of a mount), with debris on its inside cells.
## Returns the wreck record.
func wreck(uid: int) -> Dictionary:
	var inst: Dictionary = instances[uid]
	var w := {"id": inst["id"], "cells": inst["cells"].duplicate()}
	remove_uid(uid)
	wrecks.append(w)
	return w


## Clear the debris `index` of `wrecks`. Returns its record ({} for a bad index).
func clear_wreck(index: int) -> Dictionary:
	if index < 0 or index >= wrecks.size():
		return {}
	var w: Dictionary = wrecks[index]
	wrecks.remove_at(index)
	return w


# --- saving -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var uids := instances.keys()
	uids.sort()
	var list := []
	for uid in uids:
		var i: Dictionary = instances[uid]
		var rec := {"uid": uid, "id": i["id"], "anchor": [i["anchor"].x, i["anchor"].y], "rot": i["rot"],
			"hp": i["hp"], "heat": i["heat"], "status": i["status"]}
		if not i["out_cells"].is_empty():
			rec["out"] = [i["out_anchor"].x, i["out_anchor"].y]
			rec["out_hp"] = i["out_hp"]
			rec.merge(slope_record(i).get("slope", {}))
		if int(i.get("n", 0)) > 0 or str(i.get("ammo", "")) != "":  # an ammo rack's contents
			rec["ammo"] = str(i.get("ammo", ""))
			rec["n"] = int(i.get("n", 0))
		if str(i.get("kit", "")) != "":  # the drone kit loaded in a bay (drones.gd)
			rec["kit"] = str(i["kit"])
		if i.has("fab_level"):  # the fabricator's level
			rec["fab_level"] = int(i["fab_level"])
		if int(i.get("loaded", 0)) > 0:  # what a gun has taken off a belt
			rec["loaded"] = int(i["loaded"])
		if i.has("group"):  # the fire group the player chose (0 is AUTO)
			rec["group"] = int(i["group"])
		list.append(rec)
	var d := {"version": VERSION, "next_uid": _next_uid, "instances": list}
	if not wrecks.is_empty():
		d["wrecks"] = wrecks.map(func(w): return {"id": w["id"], "cells": w["cells"].map(func(c): return [c.x, c.y])})
	return d


## Replace the placed components with a saved set. Returns "" on success, else the reason. A weapon
## or engine saved without its outside half (`out`: a save of version 1 or 2) is mounted through the
## wall on its outward side by the same rule as a new one when `grid` is given; one that cannot be goes
## to `returned` (the caller puts it back in the cargo and says so). Without a `grid` it stays a bare
## inside half.
func load_dict(d: Dictionary, grid = null) -> String:
	if not supports(int(d.get("version", 0))):
		return "unsupported components version"
	for i in d["instances"]:
		if not by_id.has(str(i["id"])):
			return "unknown component " + str(i["id"])
	instances.clear()
	_cell_uid.clear()
	_out_uid.clear()
	wrecks.clear()
	returned = []
	legacy_fabs.clear()
	_next_uid = int(d["next_uid"])
	for i in d["instances"]:
		var uid := int(i["uid"])
		_next_uid = maxi(_next_uid, uid + 1)
		var id := str(i["id"])
		if id == FAB and has_fabricator():  # one per ship: the second goes back to the cargo
			returned.append({"id": id, "anchor": Vector2i(int(i["anchor"][0]), int(i["anchor"][1])), "rot": int(i["rot"]), "text": ONE_FAB + ": the extra one is in the hold"})
			continue
		var anchor := Vector2i(int(i["anchor"][0]), int(i["anchor"][1]))
		var rot := int(i["rot"])
		var plan := {}
		var out := Mounts.NONE
		if is_mount(id):
			if i.get("out") is Array and i["out"].size() == 2 and not (int(d.get("version", 0)) < 6 and _reshaped(id)):
				out = Vector2i(int(i["out"][0]), int(i["out"][1]))
				plan = _slope_plan(i, anchor, rot)
				if plan.is_empty():
					plan = Mounts.cells_of(by_id[id], anchor, rot, out)
				if plan.is_empty():  # the halves do not line up: as if it had no outside half
					out = Mounts.NONE
			if plan.is_empty() and grid != null:
				var found := _mount_old(grid, id, anchor, rot)
				if found.is_empty():
					var nm: String = by_id[id].get("name", id)
					returned.append({"id": id, "anchor": anchor, "rot": rot, "text": ("The %s no longer fits there: it is in the hold" % nm) if i.get("out") is Array else "%s has no wall to mount through and went back to the cargo" % nm})
					continue
				rot = found["rot"]
				out = found["out"]
				plan = found
		_add(uid, id, plan["anchor"] if not plan.is_empty() else anchor, rot, out, plan)
		_load_state(instances[uid], i)
		if id == FAB and not (i.get("fab_level") is float or i.get("fab_level") is int):
			legacy_fabs.append(uid)
		if int(d.get("version", 0)) < 6 and instances[uid]["out_cells"].size() > 0 and _reshaped(id) and i.has("out_hp"):  # the old outside half had twice the part's hp: keep its share of the new one
			instances[uid]["out_hp"] = clampi(roundi(float(i["out_hp"]) / (2.0 * float(by_id[id]["hp"])) * outside_hp_max(id)), 0, outside_hp_max(id))
	for w in d.get("wrecks", []):
		if w is Dictionary and w.get("cells") is Array and by_id.has(str(w.get("id", ""))):
			var cells: Array[Vector2i] = []
			for p in w["cells"]:
				cells.append(Vector2i(int(p[0]), int(p[1])))
			wrecks.append({"id": str(w["id"]), "cells": cells})
	return ""


## Did gun `id` get a new outside half in the gun rework (version 6)?
func _reshaped(id: String) -> bool:
	var d: Dictionary = by_id[id]
	return str(d.get("family", "")) == "weapon" and d["mount"]["outside"] != OLD_OUTSIDE_OF.get(id, OLD_OUTSIDE)


## {"slope": the save keys (angle, at, ocells, link) of a mount on a slope}; {} for any other part.
func slope_record(inst: Dictionary) -> Dictionary:
	if not Mounts.is_angled(inst) or inst["out_cells"].is_empty():
		return {}
	return {"slope": {"angle": inst["angle"], "at": [inst["out_at"].x, inst["out_at"].y],
		"ocells": inst["out_cells"].map(func(c): return [c.x, c.y]), "link": inst["link"].map(func(c): return [c.x, c.y])}}


## The plan of a mount saved on a slope (`angle`, `at`, `ocells`, `link` of record `i`), or {} for any other record.
func _slope_plan(i: Dictionary, anchor: Vector2i, rot: int) -> Dictionary:
	var at = i.get("at")
	var ocells = i.get("ocells")
	var link = i.get("link")
	if not ((i.get("angle") is float or i.get("angle") is int) and at is Array and at.size() == 2 and ocells is Array and not ocells.is_empty() and link is Array):
		return {}
	var out_cells: Array[Vector2i] = []
	var wall: Array[Vector2i] = []
	for pair in [[ocells, out_cells], [link, wall]]:
		for p in pair[0]:
			if not (p is Array and p.size() == 2):
				return {}
			pair[1].append(Vector2i(int(p[0]), int(p[1])))
	var plan := {"anchor": anchor, "angle": float(i["angle"]), "at": Vector2(float(at[0]), float(at[1])), "out_cells": out_cells, "link": wall}
	if not Mounts.is_angled({"angle": plan["angle"], "rot": rot}):
		return {}
	return plan


## An old inside-only mount at `anchor`, rotation `rot`: where it can be mounted (Mounts.from_inside),
## trying the rotation it was saved with and then the opposite one (the same inside rectangle, the
## other wall). The plan() entries plus rot and out, or {}.
func _mount_old(grid, id: String, anchor: Vector2i, rot: int) -> Dictionary:
	for r in [rot, rot + 2]:
		var p := Mounts.from_inside(grid, self, by_id[id], anchor, posmod(r, 4))
		if p["why"] == "":
			p["rot"] = posmod(r, 4)
			return p
	return {}


## Add instance `uid`. `plan` (Mounts.plan / cells_of) gives a mount its outside half and link.
func _add(uid: int, id: String, anchor: Vector2i, rot: int, out := Mounts.NONE, plan := {}) -> void:
	var cells := footprint(id, anchor, rot)
	var inst := {"uid": uid, "id": id, "anchor": anchor, "rot": posmod(rot, 4), "angle": posmod(rot, 4) * 90.0, "cells": cells,
		"hp": Stats.max_hp(by_id[id]), "heat": 0.0, "status": "ok",
		"out_anchor": Mounts.NONE, "out_at": Vector2.ZERO, "out_cells": [], "link": [], "out_hp": 0}
	if id == FAB:
		inst["fab_level"] = 1
	if not plan.is_empty():
		inst["out_anchor"] = out
		inst["out_cells"] = plan["out_cells"]
		inst["link"] = plan["link"]
		inst["out_hp"] = outside_hp_max(id)
		if plan.has("angle"):  # on a slope: the outside half is turned to the face
			inst["angle"] = float(plan["angle"])
			inst["out_at"] = plan["at"]
			if not Mounts.is_angled(inst):
				inst["angle"] = posmod(rot, 4) * 90.0
	instances[uid] = inst
	for c in cells:
		_cell_uid[c] = uid
	for c in inst["out_cells"]:
		_out_uid[c] = uid


## Copy the saved runtime state of an instance (hp, heat, status, outside hp), keeping the fresh
## value for whatever is missing or out of range.
func _load_state(inst: Dictionary, saved: Dictionary) -> void:
	var max_hp := Stats.max_hp(by_id[inst["id"]])
	if saved.get("hp") is float or saved.get("hp") is int:
		inst["hp"] = clampi(int(saved["hp"]), 0, max_hp)
	if saved.get("heat") is float or saved.get("heat") is int:
		inst["heat"] = maxf(0.0, float(saved["heat"]))
	if str(saved.get("status", "")) in STATUSES:
		inst["status"] = str(saved["status"])
	if not inst["out_cells"].is_empty() and (saved.get("out_hp") is float or saved.get("out_hp") is int):
		inst["out_hp"] = clampi(int(saved["out_hp"]), 0, outside_hp_max(inst["id"]))
	if saved.get("kit") is String and str(saved["kit"]) != "":
		inst["kit"] = str(saved["kit"])
	if saved.get("n") is float or saved.get("n") is int:
		inst["n"] = maxi(0, int(saved["n"]))
		inst["ammo"] = str(saved.get("ammo", ""))
	if saved.get("loaded") is float or saved.get("loaded") is int:
		inst["loaded"] = maxi(0, int(saved["loaded"]))
	if inst["id"] == FAB and (saved.get("fab_level") is float or saved.get("fab_level") is int):
		inst["fab_level"] = clampi(int(saved["fab_level"]), 1, 4)
	if (saved.get("group") is float or saved.get("group") is int) and int(saved["group"]) in [0, 1, 2, 3]:
		inst["group"] = int(saved["group"])


## A floor-type tile: something is built there and it is neither solid (wall) nor a door.
func _is_floor(grid, c: Vector2i) -> bool:
	var t: String = grid.get_tile(c)
	if t == "":
		return false
	if grid.defs == null:
		return true
	var d: Dictionary = grid.defs.get_def(t)
	return not (bool(d.get("solid", false)) or bool(d.get("door", false)))
