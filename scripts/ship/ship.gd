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
const Stats = preload("res://scripts/sim/stats.gd")
const Fire = preload("res://scripts/sim/fire.gd")
const Abilities = preload("res://scripts/sim/abilities.gd")
const Crafting = preload("res://scripts/craft/crafting.gd")
const ShieldBalance = preload("res://scripts/combat/shield_balance.gd")

## Save format. 3 adds name, world transform, components, cables and oxygen on top of the
## grid and cargo of 2; versions 1 and 2 still load (no components, no cables). The optional
## "crafting" list (blueprints and queue) was added within 3: a save without it starts with the
## blueprints known at the start. 4 adds the optional "shield_balance" (the chosen sector weights and the
## two custom presets of the Shields tab); older saves load with it fresh (even weights, empty slots).
const VERSION := 4
const TILES_PATH := "res://data/tiles.json"
const COMPONENTS_PATH := "res://data/components.json"
const START_PATH := "res://data/start.json"
const RECIPES_PATH := "res://data/recipes.json"
const MATERIALS_PATH := "res://data/materials.json"
const MAX_EVENTS := 50
const START_SIZE := Vector2i(63, 63)
const START_RADIUS := 28.0

var name := "Ship"
var grid: ShipGrid
var components: Components
var cables: Cables
var atmosphere: Atmosphere
var inventory: Inventory  ## the cargo: materials and items (crafted systems)
var crafting: Crafting  ## the known blueprints and the fabricator's queue (saved); ShipSim ticks it
var lines := {}  ## equipment lines (data/lines.json): line id -> multipliers
var power_state := {}  ## the last Power.solve result; empty until the first refresh()
var events: Array = []  ## the chronicle, newest last: {t, text}; at most MAX_EVENTS; not saved
var clock := 0.0  ## seconds this ship has been simulated; the `t` of new events
var rng_seed := 1  ## seeds the ship's random rolls (malfunctions), see ShipSim
var crew: Array = []  ## CrewMember objects aboard; not saved yet
var crew_plan: Array = []  ## the design's crew list [{name, species}] (from_design); Jobs.spawn_crew and spawn_enemy_crew use it; empty = the default crew
var shield_balance := ShieldBalance.fresh()  ## {weights: the chosen sector weights ([] = even), presets: 2 custom slots (lists, [] = empty)}; every fight starts with it (Shields.start); saved when set
var fires := {}  ## Vector2i -> intensity (0..1) of the cells on fire (scripts/sim/fire.gd); saved as the optional "fires" list
var manned := {}  ## part uid -> name of the crew member at its station, this tick (jobs.gd); not saved
var ability_state := Abilities.fresh_state()  ## abilities running or resting (abilities.gd); not saved
var world_pos := Vector2.ZERO  ## pixels; for drawing, 0 for now
var rot_quarters := 0  ## quarter turns; for drawing, 0 for now
var _structure_dirty := true
var _signature := 0  ## of the parts and cables the last refresh() saw


func _init(p_name := "Ship", p_grid: ShipGrid = null, components_path := COMPONENTS_PATH) -> void:
	name = p_name
	lines = Stats.load_lines()
	grid = p_grid if p_grid != null else ShipGrid.new()
	components = Components.new()
	components.load_defs(components_path)
	cables = Cables.new()
	atmosphere = Atmosphere.new()
	inventory = Inventory.new()
	crafting = Crafting.new()
	crafting.load(RECIPES_PATH, MATERIALS_PATH)


## The ship a new game starts with: the circular hull, no tiles, and the cargo of data/start.json.
static func new_starter(tiles_path := TILES_PATH, components_path := COMPONENTS_PATH, start_path := START_PATH) -> RefCounted:
	var defs := TileDefs.new()
	defs.load_file(tiles_path)
	var g := ShipGrid.new(START_SIZE, defs)
	g.fill_circle_hull(START_RADIUS)
	var s := new("Starter", g, components_path)
	s.inventory.load_dict(start_cargo(start_path))
	return s


## A ship from a design file (data/ships/*.json, the Ship.to_dict format), or null when it cannot be loaded.
## The grid takes the file's size and hull; the starter designs sit in the middle of a 63x63 grid.
## An optional "crew" list ([{name, species}]) becomes `crew_plan`.
static func from_design(path: String) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary and d.get("size") is Array and d["size"].size() == 2):
		return null
	var defs := TileDefs.new()
	defs.load_file(TILES_PATH)
	var s := new("Ship", ShipGrid.new(Vector2i(int(d["size"][0]), int(d["size"][1])), defs))
	if s.load_dict(d) != "":
		return null
	var list = d.get("crew")
	if list is Array:
		for e in list:
			if e is Dictionary and str(e.get("name", "")) != "":
				s.crew_plan.append({"name": str(e["name"]), "species": str(e.get("species", "human"))})
	return s


## The cargo a new ship starts with (data/start.json).
static func start_cargo(path := START_PATH) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary and data.get("cargo") is Dictionary, "bad start data: " + path)
	return data["cargo"]


## The effective stats (Stats.effective) of component id `id` on this ship.
func effective(id: String) -> Dictionary:
	return Stats.effective(components.def(id), lines)


## Components that are out of action (status is not "ok", or a hull mount whose outside half is
## disabled or whose link is cut): uid -> true. They neither make nor use power.
func disabled_uids() -> Dictionary:
	var out := {}
	var uids := components.instances.keys()
	uids.sort()
	for uid in uids:
		if components.instances[uid]["status"] != "ok" or components.offline_reason(grid, uid) != "":
			out[uid] = true
	return out


## Add a line to the chronicle (newest last), dropping the oldest beyond MAX_EVENTS.
func log_event(text: String) -> void:
	events.append({"t": clock, "text": text})
	while events.size() > MAX_EVENTS:
		events.pop_front()


## Repair a component: status back to ok and hp to the maximum. Returns false for an unknown uid.
## Heat is left alone, so a part that is still too hot trips again at once. A hull mount with a
## damaged outside half and an intact link heals the outside half first (one repair each).
func repair(uid: int) -> bool:
	if not components.instances.has(uid):
		return false
	var inst: Dictionary = components.instances[uid]
	if outside_hurt(uid):
		inst["out_hp"] = components.outside_hp_max(inst["id"])
		return true
	inst["status"] = "ok"
	inst["hp"] = Stats.max_hp(components.def(inst["id"]))
	return true


## Is mount `uid`'s outside half below its hp, with the link intact so a crew member can reach it?
func outside_hurt(uid: int) -> bool:
	var inst: Dictionary = components.instances.get(uid, {})
	return not inst.is_empty() and components.has_outside(uid) and int(inst["out_hp"]) < components.outside_hp_max(inst["id"]) and components.link_intact(grid, uid)


## What clearing the wreck of component `id` gives back: half its recipe materials, rounded down. A
## unique (found) part has no recipe and gives nothing.
func wreck_refund(id: String) -> Dictionary:
	var out := {}
	if bool(components.def(id).get("unique", false)):
		return out
	var mats: Dictionary = crafting.def(id).get("materials", {})
	for m in mats:
		var n := floori(float(mats[m]) / 2.0)
		if n > 0:
			out[m] = n
	return out


## The structure changed (tiles, doors): the next refresh() rebuilds the rooms and re-solves power.
func mark_dirty() -> void:
	_structure_dirty = true


## Bring the derived state up to date. Rooms are rebuilt after a structure change; power is
## re-solved then too, and also when a component or cable was added or removed behind our back or
## a component went out of action or came back. Power uses the line-adjusted numbers (Stats).
## Returns true when something was recomputed. Cheap when nothing changed.
func refresh() -> bool:
	var uids := components.instances.keys()
	uids.sort()
	var off := disabled_uids()
	var sig := hash([uids, cables.cells.size(), off.keys(), Abilities.rev(self)])
	if not _structure_dirty and sig == _signature:
		return false
	if _structure_dirty:
		atmosphere.rebuild(grid)
	power_state = Power.solve(Stats.view(components, lines), cables, off, Abilities.power_mods(self))
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
	d["crafting"] = crafting.to_dict()
	d["oxygen"] = atmosphere.pressure.duplicate()
	if not ShieldBalance.is_fresh(shield_balance):  # optional: only written when the player set something
		d["shield_balance"] = shield_balance.duplicate(true)
	if not fires.is_empty():  # optional, like the grid's damage lists: only written when something burns
		var list := []
		for c in Fire.sorted_cells(fires.keys()):
			list.append([c.x, c.y, fires[c]])
		d["fires"] = list
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
	var burning = _read_fires(d)
	if burning == null:
		return "bad ship data"
	if d.has("crafting"):
		if not (d["crafting"] is Dictionary):
			return "bad ship data"
		var why: String = crafting.check_dict(d["crafting"])
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
	components.load_dict(d["components"] if version >= 3 else empty_parts, grid)
	for r in components.returned:  # old weapons and engines with no wall to mount through
		inventory.add(r["id"], 1)
		log_event(r["text"])
	cables.load_dict(d["cables"] if version >= 3 else empty_cables)
	if version >= 3:
		name = str(d.get("name", name))
		var p = d.get("world_pos")
		world_pos = Vector2(float(p[0]), float(p[1])) if p is Array and p.size() == 2 else Vector2.ZERO
		rot_quarters = posmod(int(d.get("rot", 0)), 4)
	fires = burning
	shield_balance = ShieldBalance.sanitize(d.get("shield_balance"))
	manned = {}
	ability_state = Abilities.fresh_state()
	if d.has("crafting"):
		crafting.load_dict(d["crafting"])
	else:
		crafting.reset()
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


## The optional "fires" list of a save ([[x, y, intensity], ...]) as cell -> intensity; {} when
## absent, null when malformed.
func _read_fires(d: Dictionary):
	var list = d.get("fires", [])
	if not list is Array:
		return null
	var out := {}
	for p in list:
		if not (p is Array and p.size() == 3 and (p[2] is float or p[2] is int)):
			return null
		out[Vector2i(int(p[0]), int(p[1]))] = clampf(float(p[2]), 0.0, 1.0)
	return out


## Is the components/cables part of a version 3 save well formed? Checked before anything is
## replaced, so a bad save changes nothing.
func _check_layers(d: Dictionary) -> String:
	var c = d.get("components")
	var k = d.get("cables")
	if not (c is Dictionary and k is Dictionary):
		return "bad ship data"
	if not Components.supports(int(c.get("version", 0))):
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
