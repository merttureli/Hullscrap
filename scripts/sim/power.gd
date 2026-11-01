extends RefCounted
## Power solver. Cables form networks (4-connected cable cells). A component joins every network
## its footprint touches, so one touching two bridges them into a single network. Each network
## feeds its consumers all-or-nothing in (priority, uid) order. Pure and deterministic: the result
## never depends on insertion order.

const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const EPS := 0.0001  ## slack for float power (line multipliers make 5.4 and 2.4)


## `components`: a components.gd instance (or a Stats.View of one, for line-adjusted power); `cables`: a cables.gd instance; `disabled`: uid -> true
## for damaged parts that neither make nor use power (they still bridge cables).
## `mods`: Abilities.power_mods, the abilities running now: {mult: uid -> factor on the part's power
## figure, extra: uid -> power_spike draw added to its demand (a producer gives that much less),
## bonus: uid -> power added to the part's figure, after the factor: the manned-station bonus of an
## operator's traits, TraitSet.station_bonus; hand: uid -> power a crew member gives the part by hand (crew
## ability power_system, CrewFx.power_bonus): added like a bonus, and enough of it runs a part that is on no cable}.
## Returns {powered: {uid: bool}, networks: [{id, cells, members, supply, demand, used}],
## network_of: {uid: network id}}. Network ids follow each network's first cell in reading order.
static func solve(components, cables, disabled := {}, mods := {}) -> Dictionary:
	var mults: Dictionary = mods.get("mult", {})
	var extras: Dictionary = mods.get("extra", {})
	var bonuses: Dictionary = mods.get("bonus", {})
	var hands: Dictionary = mods.get("hand", {})
	var cells: Array = cables.cells.keys()
	cells.sort_custom(_before)
	var label := {}  # cable cell -> cable group
	var groups := 0
	for start in cells:
		if label.has(start):
			continue
		label[start] = groups
		var stack: Array = [start]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in SIDES:
				if cables.cells.has(c + d) and not label.has(c + d):
					label[c + d] = groups
					stack.append(c + d)
		groups += 1
	var uids: Array = components.instances.keys()
	uids.sort()
	var parent: Array = range(groups)
	var touched := {}  # uid -> cable groups its footprint touches
	for uid in uids:
		var gs: Array = []
		for c in components.instances[uid]["cells"]:
			if label.has(c) and not gs.has(label[c]):
				gs.append(label[c])
		touched[uid] = gs
		for i in range(1, gs.size()):
			_union(parent, gs[0], gs[i])
	var net_id := {}  # root cable group -> network id
	var nets: Array = []
	for g in groups:
		if _find(parent, g) == g:
			net_id[g] = nets.size()
			nets.append({"id": nets.size(), "cells": [], "members": [], "supply": 0, "demand": 0, "used": 0})
	for c in cells:
		nets[net_id[_find(parent, label[c])]]["cells"].append(c)
	var powered := {}
	var network_of := {}
	for uid in uids:
		powered[uid] = false
		if not touched[uid].is_empty():
			var n: Dictionary = nets[net_id[_find(parent, touched[uid][0])]]
			n["members"].append(uid)
			network_of[uid] = n["id"]
	for n in nets:
		var consumers: Array = []  # [priority, uid, need]
		for uid in n["members"]:
			if disabled.get(uid, false):
				continue
			var d: Dictionary = components.def(components.instances[uid]["id"])
			var p = d.get("power", 0)  # an int, or a float for line-adjusted parts
			var extra := float(extras.get(uid, 0.0))
			if mults.has(uid):
				p = p * float(mults[uid])
			if bonuses.has(uid):
				p = p + float(bonuses[uid])
			if hands.has(uid):
				p = p + float(hands[uid])
			if p > 0 and extra > 0.0:
				p = maxf(p - extra, 0.0)
				extra = 0.0
			if p > 0:
				n["supply"] += p
				powered[uid] = true
			elif p < 0 or extra > 0.0:
				var need = -p + extra if extra > 0.0 else -p  # stays an int for a plain part
				n["demand"] += need
				consumers.append([int(d.get("priority", 0)), uid, need])
			else:
				powered[uid] = true
		consumers.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var left = n["supply"]
		for k in consumers:
			if k[2] <= left + EPS:
				left -= k[2]
				n["used"] += k[2]
				powered[k[1]] = true
	for uid in uids:  # a part on no cable runs by hand when the power it is given covers what it needs
		if hands.has(uid) and touched[uid].is_empty() and not disabled.get(uid, false):
			var p = components.def(components.instances[uid]["id"]).get("power", 0)
			if mults.has(uid):
				p = p * float(mults[uid])
			powered[uid] = p + float(hands[uid]) >= -EPS
	return {"powered": powered, "networks": nets, "network_of": network_of}


## The repair drones (R1) draw power with no cable: each of the working drones `names` (sorted) takes `draw` from the ship's
## surplus after the parts on the cables have had theirs (supply left over in the networks, pooled), in that order. A drone the
## surplus does not cover is off. Adds `drones` to the solve result `state`: {fed: name -> bool, demand: the draw of every
## working drone, used: the draw of the fed ones, draw}. The networks are left as they are: HUD figures add `drones.demand`.
static func feed_drones(state: Dictionary, names: Array, draw: float) -> void:
	var left := 0.0
	for n in state.get("networks", []):
		left += maxf(float(n["supply"]) - float(n["used"]), 0.0)
	var fed := {}
	var used := 0.0
	for name in names:
		fed[name] = left + EPS >= draw
		if fed[name]:
			left -= draw
			used += draw
	state["drones"] = {"fed": fed, "demand": draw * names.size(), "used": used, "draw": draw}


## Is the drone called `name` running on the solve result `state` (it is working and the surplus covered it)?
static func drone_fed(state: Dictionary, name: String) -> bool:
	return bool(state.get("drones", {}).get("fed", {}).get(name, false))


static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## Merge two groups; the lower index stays the root, so roots stay in reading order.
static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)
