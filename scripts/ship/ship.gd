extends RefCounted
## One ship (or station): its grid, components, cables, atmosphere, power, cargo and crew, plus a
## world transform. The game holds a list of ships and nothing may assume there is only one.
## Pure data and logic, no nodes. Everything here is edited in place, so other objects can keep
## a reference to `grid`, `inventory` and the rest across a load.
## Structure edits call mark_dirty(); refresh() then rebuilds the rooms and re-solves power.

const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const Components = preload("res://scripts/ship/components.gd")
const Cables = preload("res://scripts/ship/cables.gd")
const Inventory = preload("res://scripts/ship/inventory.gd")
const Atmosphere = preload("res://scripts/sim/atmosphere.gd")
const Power = preload("res://scripts/sim/power.gd")

## Save format. 3 adds name, world transform, components, cables and oxygen on top of the
## grid and cargo of 2; versions 1 and 2 still load (no components, no cables).
const VERSION := 3
const TILES_PATH := "res://data/tiles.json"
const COMPONENTS_PATH := "res://data/components.json"
const START_PATH := "res://data/start.json"
const START_SIZE := Vector2i(31, 31)
const START_RADIUS := 14.0

var name := "Ship"
var grid: ShipGrid
var components: Components
var cables: Cables
var atmosphere: Atmosphere
var inventory: Inventory  ## the cargo: materials and items (crafted systems)
var power_state := {}  ## the last Power.solve result; empty until the first refresh()
var crew: Array = []  ## CrewMember objects aboard; not saved yet
var world_pos := Vector2.ZERO  ## pixels; for drawing, 0 for now
var rot_quarters := 0  ## quarter turns; for drawing, 0 for now
var _structure_dirty := true
var _signature := 0  ## of the parts and cables the last refresh() saw


func _init(p_name := "Ship", p_grid: ShipGrid = null, components_path := COMPONENTS_PATH) -> void:
	name = p_name
	grid = p_grid if p_grid != null else ShipGrid.new()
	components = Components.new()
	components.load_defs(components_path)
	cables = Cables.new()
	atmosphere = Atmosphere.new()
	inventory = Inventory.new()


## The ship a new game starts with: the circular hull, no tiles, and the cargo of data/start.json.
static func new_starter(tiles_path := TILES_PATH, components_path := COMPONENTS_PATH, start_path := START_PATH) -> RefCounted:
	var defs := TileDefs.new()
	defs.load_file(tiles_path)
	var g := ShipGrid.new(START_SIZE, defs)
	g.fill_circle_hull(START_RADIUS)
	var s := new("Starter", g, components_path)
	s.inventory.load_dict(start_cargo(start_path))
	return s


## The cargo a new ship starts with (data/start.json).
static func start_cargo(path := START_PATH) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary and data.get("cargo") is Dictionary, "bad start data: " + path)
	return data["cargo"]


## The structure changed (tiles, doors): the next refresh() rebuilds the rooms and re-solves power.
func mark_dirty() -> void:
	_structure_dirty = true


## Bring the derived state up to date. Rooms are rebuilt after a structure change; power is
## re-solved then too, and also when a component or cable was added or removed behind our back.
## Returns true when something was recomputed. Cheap when nothing changed.
func refresh() -> bool:
	var uids := components.instances.keys()
	uids.sort()
	var sig := hash([uids, cables.cells.size()])
	if not _structure_dirty and sig == _signature:
		return false
	if _structure_dirty:
		atmosphere.rebuild(grid)
	power_state = Power.solve(components, cables)
	_structure_dirty = false
	_signature = sig
	return true


## Everything, as plain JSON-friendly data. Refreshes first so the oxygen matches the rooms.
func to_dict() -> Dictionary:
	refresh()
	var d := grid.to_dict()
	d["version"] = VERSION
	d["name"] = name
	d["world_pos"] = [world_pos.x, world_pos.y]
	d["rot"] = rot_quarters
	d["cargo"] = inventory.to_dict()
	d["components"] = components.to_dict()
	d["cables"] = cables.to_dict()
	d["oxygen"] = atmosphere.pressure.duplicate()
	return d


## Replace everything with a saved ship, in place. Versions 1 and 2 (grid, cargo and doors) load
## with no components and no cables; version 1 also gets the starting cargo. Returns "" on
## success, else the reason, and nothing changes then.
func load_dict(d: Dictionary) -> String:
	var version := int(d.get("version", 0))
	if version < 1 or version > VERSION:
		return "unsupported ship version"
	var cargo := Inventory.new()
	if version == 1:
		cargo.load_dict(start_cargo())
	else:
		if not (d.get("cargo") is Dictionary):
			return "bad ship data"
		var why: String = cargo.load_dict(d["cargo"])
		if why != "":
			return why
	if version >= 3:
		var why := _check_layers(d)
		if why != "":
			return why
	var gd := d.duplicate()
	gd["version"] = mini(version, ShipGrid.VERSION)
	var err: String = grid.load_dict(gd)
	if err != "":
		return err
	inventory.counts = cargo.counts
	var empty_parts := {"version": Components.VERSION, "next_uid": 1, "instances": []}
	var empty_cables := {"version": Cables.VERSION, "cells": []}
	components.load_dict(d["components"] if version >= 3 else empty_parts)
	cables.load_dict(d["cables"] if version >= 3 else empty_cables)
	if version >= 3:
		name = str(d.get("name", name))
		var p = d.get("world_pos")
		world_pos = Vector2(float(p[0]), float(p[1])) if p is Array and p.size() == 2 else Vector2.ZERO
		rot_quarters = posmod(int(d.get("rot", 0)), 4)
	atmosphere.rooms = []
	atmosphere.room_of = {}
	atmosphere.doors = []
	atmosphere.pressure.clear()
	_structure_dirty = true
	refresh()
	var air = d.get("oxygen")
	if air is Array and air.size() == atmosphere.pressure.size():
		for i in air.size():
			atmosphere.pressure[i] = clampf(float(air[i]), 0.0, 1.0)
	return ""


## Is the components/cables part of a version 3 save well formed? Checked before anything is
## replaced, so a bad save changes nothing.
func _check_layers(d: Dictionary) -> String:
	var c = d.get("components")
	var k = d.get("cables")
	if not (c is Dictionary and k is Dictionary):
		return "bad ship data"
	if int(c.get("version", 0)) != Components.VERSION:
		return "unsupported components version"
	if int(k.get("version", 0)) != Cables.VERSION:
		return "unsupported cables version"
	if not (c.get("instances") is Array and c.has("next_uid") and k.get("cells") is Array):
		return "bad ship data"
	for i in c["instances"]:
		if not (i is Dictionary and i.has_all(["uid", "id", "anchor", "rot"]) and i["anchor"] is Array and i["anchor"].size() == 2):
			return "bad ship data"
		if not components.has(str(i["id"])):
			return "unknown component " + str(i["id"])
	for p in k["cells"]:
		if not (p is Array and p.size() == 2):
			return "bad ship data"
	return ""
