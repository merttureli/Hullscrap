extends RefCounted
## Component definitions (data/components.json) and the components placed on a ship.
## A placed component is an instance with a footprint of grid cells and some runtime state
## (hp, heat, status). Pure data, no nodes.

const Stats = preload("res://scripts/sim/stats.gd")
const Content = preload("res://scripts/data/content.gd")
## Save format. 2 adds each instance's hp, heat and status; version 1 saves still load (full hp, cold, ok).
const VERSION := 2
const MIN_VERSION := 1
## An instance's status: ok, or one of the ways it can be out of action.
const STATUSES: Array[String] = ["ok", "overheated", "malfunction", "disabled"]

var by_id := {}
var order: Array[String] = []
var instances := {}  # uid -> {uid, id, anchor, rot, cells, hp, heat, status}
var _cell_uid := {}  # Vector2i -> uid of the component covering it
var _next_uid := 1   # only grows, so a uid is never reused


func load_defs(path: String) -> void:
	var data = Content.read(path)
	assert(data is Dictionary and data.has("components"), "bad component data: " + path)
	for d in data["components"]:
		for k in ["power", "priority", "tier"]:
			d[k] = int(d.get(k, 0))
		d["hp"] = Stats.max_hp(d)
		d["size"] = [int(d["size"][0]), int(d["size"][1])]
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
	for c in cells:
		if _cell_uid.has(c):
			return "overlaps " + str(by_id[instances[_cell_uid[c]]["id"]]["name"])
	return ""


## Place a component. Returns its new uid, or -1 when it cannot go there.
func place(grid, id: String, anchor: Vector2i, rot: int) -> int:
	if can_place(grid, id, anchor, rot) != "":
		return -1
	var uid := _next_uid
	_next_uid += 1
	_add(uid, id, anchor, rot)
	return uid


## Remove the component covering `c`. Returns its id, or "" when the cell is empty.
func remove_at(c: Vector2i) -> String:
	var uid := at(c)
	if uid < 0:
		return ""
	var id: String = instances[uid]["id"]
	for cell in instances[uid]["cells"]:
		_cell_uid.erase(cell)
	instances.erase(uid)
	return id


## Uid of the component covering `c`, or -1.
func at(c: Vector2i) -> int:
	return _cell_uid.get(c, -1)


func to_dict() -> Dictionary:
	var uids := instances.keys()
	uids.sort()
	var list := []
	for uid in uids:
		var i: Dictionary = instances[uid]
		list.append({"uid": uid, "id": i["id"], "anchor": [i["anchor"].x, i["anchor"].y], "rot": i["rot"],
			"hp": i["hp"], "heat": i["heat"], "status": i["status"]})
	return {"version": VERSION, "next_uid": _next_uid, "instances": list}


## Replace the placed components with a saved set. Returns "" on success, else the reason.
func load_dict(d: Dictionary) -> String:
	if not supports(int(d.get("version", 0))):
		return "unsupported components version"
	for i in d["instances"]:
		if not by_id.has(str(i["id"])):
			return "unknown component " + str(i["id"])
	instances.clear()
	_cell_uid.clear()
	_next_uid = int(d["next_uid"])
	for i in d["instances"]:
		var uid := int(i["uid"])
		_next_uid = maxi(_next_uid, uid + 1)
		_add(uid, str(i["id"]), Vector2i(int(i["anchor"][0]), int(i["anchor"][1])), int(i["rot"]))
		_load_state(instances[uid], i)
	return ""


func _add(uid: int, id: String, anchor: Vector2i, rot: int) -> void:
	var cells := footprint(id, anchor, rot)
	instances[uid] = {"uid": uid, "id": id, "anchor": anchor, "rot": posmod(rot, 4), "cells": cells,
		"hp": Stats.max_hp(by_id[id]), "heat": 0.0, "status": "ok"}
	for c in cells:
		_cell_uid[c] = uid


## Copy the saved runtime state of an instance (hp, heat, status), keeping the fresh value for
## whatever is missing or out of range.
func _load_state(inst: Dictionary, saved: Dictionary) -> void:
	var max_hp := Stats.max_hp(by_id[inst["id"]])
	if saved.get("hp") is float or saved.get("hp") is int:
		inst["hp"] = clampi(int(saved["hp"]), 0, max_hp)
	if saved.get("heat") is float or saved.get("heat") is int:
		inst["heat"] = maxf(0.0, float(saved["heat"]))
	if str(saved.get("status", "")) in STATUSES:
		inst["status"] = str(saved["status"])


## A floor-type tile: something is built there and it is neither solid (wall) nor a door.
func _is_floor(grid, c: Vector2i) -> bool:
	var t: String = grid.get_tile(c)
	if t == "":
		return false
	if grid.defs == null:
		return true
	var d: Dictionary = grid.defs.get_def(t)
	return not (bool(d.get("solid", false)) or bool(d.get("door", false)))
