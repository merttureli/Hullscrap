extends "res://tests/base_test.gd"
## The Blank frame (docs/CONTENT.md section 19, data/ships/starter_blank.json): a build-your-own start. The ship is a seed (the helm in a sealed
## 4x2 pod with one door) and the kit in its hold is balanced against the open starters; the run opens in build mode, holds the tide clock and
## refuses to leave its first node until the ship can fly (launch.gd); a scripted build with the kit shows the kit is enough.

const Campaign = preload("res://scripts/space/campaign.gd")
const Hangar = preload("res://scripts/space/hangar.gd")
const HangarView = preload("res://scripts/ui/hangar.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const CrewView = preload("res://scripts/crew/crew_view.gd")
const Launch = preload("res://scripts/space/launch.gd")
const Profile = preload("res://scripts/ui/profile.gd")
const RunStart = preload("res://scripts/space/run_start.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const Content = preload("res://scripts/data/content.gd")

const BLANK := "res://data/ships/starter_blank.json"
const TMP := "user://test_blank_start_profile.json"
const TOLERANCE := 0.10  ## the kit's value against the median open starter
## What a ship needs to fly and fight, by part family: the kit (the seed's helm and the hold) has each.
const NEEDED: Array[String] = ["helm", "reactor", "engine", "oxygen", "weapon", "shield", "bed"]
## The scripted build: a hull of a starter's size round the seed. x 32..51, y 35..46 (240 cells, the starters have 248 to 309).
const BOX := Rect2i(32, 35, 20, 12)


# --- value: the economy's own numbers ----------------------------------------------------------------------------

## The credit value of one unit of each material: data/drift.json values.rarity by the rarity of data/materials.json.
func _unit_values() -> Dictionary:
	var rarity: Dictionary = Content.read("res://data/drift.json")["values"]["rarity"]
	var out := {}
	for m in Content.read("res://data/materials.json")["materials"]:
		out[str(m["id"])] = float(rarity[str(m["rarity"])])
	return out


func _cost_value(cost: Dictionary) -> float:
	var unit := _unit_values()
	var sum := 0.0
	for m in cost:
		sum += float(cost[m]) * float(unit.get(str(m), 0.0))
	return sum


## What a part is worth: the materials of its recipe.
func _part_value(ship: Ship, id: String) -> float:
	var def = ship.crafting.def(id)
	return _cost_value(def["materials"]) if def is Dictionary else 0.0


## The hull's material cost: every tile at its shape's area (the cost the build paid).
func _hull_value(ship: Ship) -> float:
	var sum := 0.0
	for c in ship.grid.tiles:
		sum += _cost_value(ship.grid.cost_of(ship.grid.tiles[c], ship.grid.area_at(c)))
	return sum


## An open starter: installed parts plus its hull. {name, parts, hull, total}.
func _starter_value(e: Dictionary) -> Dictionary:
	var ship: Ship = Ship.from_design(e["path"])
	var parts := 0.0
	for uid in ship.components.instances:
		parts += _part_value(ship, str(ship.components.instances[uid]["id"]))
	var hull := _hull_value(ship)
	return {"name": e["name"], "parts": parts, "hull": hull, "total": parts + hull}


## The open starters (nothing earned, not the blank one) valued, in hangar order.
func open_starters() -> Array:
	var out := []
	for e in Hangar.starters():
		if e["unlock"] == "" and not e["build_first"]:
			out.append(_starter_value(e))
	return out


func median(list: Array) -> float:
	var v: Array = list.map(func(r): return r["total"])
	v.sort()
	return float(v[v.size() / 2]) if v.size() % 2 == 1 else (float(v[v.size() / 2 - 1]) + float(v[v.size() / 2])) / 2.0


## The blank frame's kit: the parts and materials in its hold plus what is built into the seed. {parts, hull, total}.
func kit_value() -> Dictionary:
	var ship: Ship = Ship.from_design(BLANK)
	var parts := 0.0
	var hull := _hull_value(ship)
	for uid in ship.components.instances:
		parts += _part_value(ship, str(ship.components.instances[uid]["id"]))
	var cargo: Dictionary = ship.inventory.to_dict()
	var unit := _unit_values()
	for id in cargo:
		if ship.components.has(str(id)):
			parts += _part_value(ship, str(id)) * float(cargo[id])
		elif unit.has(str(id)) and str(id) != "polymer":  # (the polymer is the reserve every starter carries)
			hull += float(cargo[id]) * float(unit[id])
	return {"parts": parts, "hull": hull, "total": parts + hull}


# --- the card -----------------------------------------------------------------------------------------------------

func test_the_card_is_listed_and_open_with_no_unlocks() -> void:
	var list := Hangar.starters()
	var at := list.map(func(e): return e["id"]).find("starter_blank")
	check(at >= 0, "the Blank frame is in the hangar")
	if at < 0:
		return
	var e: Dictionary = list[at]
	eq(e["unlock"], "", "it has no unlock")
	check(not Hangar.locked(e, null), "it is open to a profile that has earned nothing")
	check(e["build_first"], "it asks for the build-first start")
	eq(Hangar.open_count(list, e["group"], null), [1, 1], "its tab holds it alone")
	eq(e["group"], "Your own", "its own tab, the first of the row (the hangar still opens on the first ship ready to fly)")
	eq(Hangar.validate(), [], "the hangar is sound with it")
	for other in list:
		if other["id"] != "starter_blank":
			check(not other["build_first"], other["id"] + " is no build-first start")


func test_the_seed_is_the_smallest_pod_a_crew_can_stand_in() -> void:
	var ship: Ship = Ship.from_design(BLANK)
	eq(ship.name, "Blank Frame", "the name")
	eq(ship.grid.tiles.size(), 24, "24 tiles: a 6x4 block")
	eq(ship.components.instances.size(), 1, "one part built in")
	eq(ship.components.instances[ship.components.instances.keys()[0]]["id"], "helm", "the helm")
	var doors := 0
	for c in ship.grid.tiles:
		doors += int(ship.grid.tiles[c] == "door")
	eq(doors, 2, "one door piece")
	eq(ship.atmosphere.rooms.size(), 1, "one room")
	check(ship.atmosphere.rooms[0]["sealed"], "sealed")
	eq(ship.grid.hull.size(), 4513, "on the starters' round build area")
	eq(ship.grid.size, Vector2i(83, 83), "in the starters' grid")
	check(ship.build_first, "the ship knows it is a build-first start")


func test_the_crew_is_the_default_starters() -> void:
	var ship: Ship = Ship.from_design(BLANK)
	var rust: Ship = Ship.from_design("res://data/ships/starter_rustbucket.json")
	eq(ship.crew_plan, rust.crew_plan, "the same crew as the default open starter: the soldier alone")


# --- the kit is balanced ------------------------------------------------------------------------------------------

func test_the_kit_is_worth_the_median_open_starter_within_ten_percent() -> void:
	var rows := open_starters()
	eq(rows.size(), 3, "three starters are open from the start")
	var mid := median(rows)
	var kit := kit_value()
	check(absf(kit["total"] - mid) <= TOLERANCE * mid, "kit %s against the median %s of the open starters" % [str(kit["total"]), str(mid)])
	check(kit["parts"] > 0.0 and kit["hull"] > 0.0, "both parts and hull materials")


func test_the_kit_has_every_family_a_ship_needs_and_no_weapon_heap() -> void:
	var ship: Ship = Ship.from_design(BLANK)
	var n := {}
	for uid in ship.components.instances:
		var f := str(ship.components.def(ship.components.instances[uid]["id"]).get("family", ""))
		n[f] = int(n.get(f, 0)) + 1
	var cargo: Dictionary = ship.inventory.to_dict()
	for id in cargo:
		if ship.components.has(str(id)):
			var f := str(ship.components.def(str(id)).get("family", ""))
			n[f] = int(n.get(f, 0)) + int(cargo[id])
	for f in NEEDED:
		check(int(n.get(f, 0)) >= 1, "the kit has a " + f)
	var total := 0
	for f in n:
		total += int(n[f])
	check(int(n.get("weapon", 0)) * 4 <= total, "weapons are at most a quarter of the parts (%d of %d)" % [int(n.get("weapon", 0)), total])
	check(int(n.get("engine", 0)) >= 2, "two engines, like the open starters with a pair")
	var power := 0.0
	for id in cargo:
		if ship.components.has(str(id)):
			power += float(ship.components.def(str(id)).get("power", 0.0)) * float(cargo[id])
	power += float(ship.components.def("helm").get("power", 0.0))
	check(power >= 0.0, "the reactor covers what the parts draw (net %s)" % str(power))


# --- the run -----------------------------------------------------------------------------------------------------

func _profile(ids: Array) -> Profile:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var p := Profile.new(TMP)
	for id in ids:
		p.unlock(str(id))
	return p


## A hangar wired like the scene (as test_run_start.gd does), with a map, and the run started with the Blank frame.
func _run(prof) -> Dictionary:
	var sim := ShipSim.new()
	var build := BuildMode.new()
	build.sim = sim
	var crew := CrewView.new()
	var cam := Camera2D.new()
	var map := MapView.new()
	map.visible = false  # (the scene's _ready does this)
	map.sim = sim
	map.build = build
	map.profile = prof
	map.size = Vector2(1600.0, 900.0)
	build.drift = map
	var h := HangarView.new()
	h.sim = sim
	h.build = build
	h.crew = crew
	h.cam = cam
	h.profile = prof
	build.picker = h
	h.size = Vector2(1600.0, 900.0)
	h.open()
	var at := -1
	for i in h.cards.size():
		if h.cards[i]["id"] == "starter_blank":
			at = i
	var why := h.choose(at)
	return {"h": h, "sim": sim, "build": build, "crew": crew, "cam": cam, "map": map, "why": why}


## A node the first node has a lane to.
func _lane(c: Campaign) -> String:
	var near: Array = c.drift.neighbours(c.current)
	return str(near[0]) if not near.is_empty() else ""


## Spool the drive for the first lane and let it run out: {ok, why} of the jump that fires (campaign.gd start_jump, tick_jump).
func _launch(c: Campaign, ship: Ship) -> Dictionary:
	var r := c.start_jump(_lane(c), ship)
	if not r["ok"]:
		return r
	var fired := ""
	for i in 200:
		fired = c.tick_jump(1.0, false, ship)
		if fired != "spooling":
			break
	return {"ok": fired == "jumped", "why": str(c.last_jump.get("why", fired))}


func _free_all(d: Dictionary) -> void:
	for k in d:
		if d[k] is Object:
			d[k].free()


func test_the_run_opens_in_build_mode_with_the_clock_held() -> void:
	var d := _run(_profile([]))
	eq(d["why"], "", "the card is flown")
	var build: BuildMode = d["build"]
	var map: MapView = d["map"]
	var sim: ShipSim = d["sim"]
	check(build.build_on and sim.paused, "build mode, the world paused")
	check(map.campaign != null and map.campaign.flags.has(Campaign.BUILD_FIRST), "the campaign carries the build-first flag")
	check(build.message.contains("build your ship"), "the first hint says to build, then launch: " + build.message)
	var tide: int = map.campaign.tide.hollow_count()
	var left: float = map.campaign.tide.linger_left()
	build.set_build(false)  # play mode: before this start the tide would run
	check(map.playing(), "play mode on the map")
	for i in 400:
		map.tick_linger(1.0)
	eq(map.campaign.tide.linger_left(), left, "the tide clock stands still before the first launch")
	eq(map.campaign.tide.hollow_count(), tide, "and the tide has not moved")
	_free_all(d)


func test_launch_is_refused_while_the_ship_cannot_fly_and_says_why() -> void:
	var d := _run(_profile([]))
	var map: MapView = d["map"]
	var ship: Ship = d["sim"].player_ship()
	var c: Campaign = map.campaign
	var to := _lane(c)
	check(to != "", "the first node has a lane")
	var r := c.start_jump(to, ship)
	check(not r["ok"], "the jump is refused")
	var why: String = r["why"]
	check(why.begins_with("Can't launch yet:") and why.contains("helm") and why.contains("engine"), "it says what is missing: " + why)
	eq(c.current, c.drift.start_id(), "the ship is still at the first node")
	check(c.flags.has(Campaign.BUILD_FIRST), "and the flag is still up")
	var listed := Launch.problems(ship)
	check(listed.size() >= 2, "the reasons are listed one by one: %s" % str(listed))
	check(c.spool.is_empty(), "and no spool began")
	eq(c.jump_block(to, ship, true), why, "a drift jump is held too")
	_free_all(d)


# --- the scripted build ------------------------------------------------------------------------------------------

func _tile_changes(ship: Ship) -> Array:
	var changes := []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			var c := Vector2i(x, y)
			if ship.grid.tiles.has(c):
				continue  # the seed stays
			var edge: bool = x == BOX.position.x or x == BOX.end.x - 1 or y == BOX.position.y or y == BOX.end.y - 1
			var side: bool = x == BOX.position.x or x == BOX.end.x - 1
			changes.append({"layer": "tile", "cell": c, "to": ("titanium_alloy" if side else "wall") if edge else "floor"})
	return changes


## Place `id` as a hull mount on the first spot of `cells` (outside-half anchors) the mount rules accept.
func _mount(session: BuildSession, id: String, rot: int, cells: Array) -> bool:
	for c in cells:
		if session.apply([{"layer": "component", "id": id, "anchor": c, "rot": rot}])["skipped"] == 0:
			return true
	return false


## The shortest cable path (4-connected over the hull) from the net to any cell of `targets`.
func _route(ship: Ship, net: Dictionary, targets: Array) -> Array:
	var prev := {}
	var queue: Array = net.keys()
	for c in queue:
		prev[c] = null
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if targets.has(c):
			var path := []
			var at = c
			while not net.has(at):
				path.append(at)
				at = prev[at]
			return path
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if not prev.has(n) and ship.grid.hull.has(n) and BOX.has_point(n):
				prev[n] = c
				queue.append(n)
	return []


## The Blank frame built out with its own kit: a hull round the seed, the parts from the hold, a cable to each.
func _built() -> Ship:
	var ship: Ship = Ship.from_design(BLANK)
	var session := BuildSession.new(ship)
	var r := session.apply(_tile_changes(ship))
	check(r["skipped"] == 0, "the hull is built from the hold's materials: %s" % str(r["reason"]))
	for p in [["reactor_mk2", Vector2i(35, 37)], ["oxygen_gen", Vector2i(47, 37)], ["shield_mk1", Vector2i(47, 41)], ["bed", Vector2i(35, 41)], ["fabricator", Vector2i(39, 44)]]:
		var placed := session.apply([{"layer": "component", "id": p[0], "anchor": p[1], "rot": 0}])
		check(placed["skipped"] == 0, "%s is fitted from the cargo: %s" % [p[0], str(placed["reason"])])
	var south: Array = []
	var north: Array = []
	for x in range(BOX.position.x + 2, BOX.end.x - 3):
		south.append(Vector2i(x, BOX.end.y))
		north.append(Vector2i(x, BOX.position.y - 2))
	check(_mount(session, "engine_mk1", 2, south) and _mount(session, "engine_mk1", 2, south), "two engines on the stern wall")
	check(_mount(session, "pulse_mk1", 0, north), "the gun on the bow wall")
	var net := {}
	var reactor := -1
	for uid in ship.components.instances:
		if ship.components.instances[uid]["id"] == "reactor_mk2":
			reactor = uid
	var start: Vector2i = ship.components.instances[reactor]["cells"][0]
	net[start] = true
	var cables := [{"layer": "cable", "cell": start}]
	var rest: Array = ship.components.instances.keys()
	rest.erase(reactor)
	while not rest.is_empty():
		var best := []
		var best_uid := -1
		for uid in rest:
			var path := _route(ship, net, ship.components.instances[uid]["cells"])
			if not path.is_empty() or net.has(ship.components.instances[uid]["cells"][0]):
				if best_uid < 0 or path.size() < best.size():
					best = path
					best_uid = uid
		if best_uid < 0:
			check(false, "a cable reaches every part")
			break
		for c in best:
			net[c] = true
			cables.append({"layer": "cable", "cell": c})
		rest.erase(best_uid)
	var wired := session.apply(cables)
	check(wired["skipped"] == 0, "the cables are laid from the hold's copper: %s" % str(wired["reason"]))
	ship.refresh()
	return ship


func test_a_scripted_build_with_the_kit_can_fly() -> void:
	var ship := _built()
	var hull := 0
	for c in ship.grid.tiles:
		hull += 1
	check(hull >= 240 and hull <= 310, "the hull is a starter's size (%d tiles, the open starters have 248 to 309)" % hull)
	var left := ship.inventory.to_dict()
	for id in ["reactor_mk2", "engine_mk1", "oxygen_gen", "bed", "pulse_mk1", "shield_mk1", "fabricator"]:
		eq(int(left.get(id, 0)), 0, id + " is out of the hold: all of it was fitted")
	eq(Launch.problems(ship), [], "the built ship can fly: " + str(Launch.problems(ship)))
	eq(Launch.why_not(ship), "", "and the launch check is silent")
	var powered: Dictionary = ship.power_state["powered"]
	var dark := 0
	for uid in ship.components.instances:
		dark += int(not powered.get(uid, false))
	eq(dark, 0, "every part has power")


func test_launch_is_allowed_once_built_and_the_tide_clock_starts() -> void:
	var d := _run(_profile([]))
	var map: MapView = d["map"]
	var sim: ShipSim = d["sim"]
	var built := _built()
	sim.ships[0] = built  # the ship the player built (the hold and the grid are the design's)
	var c: Campaign = map.campaign
	var r := _launch(c, built)
	check(r["ok"], "the built ship may launch: " + str(r["why"]))
	check(not c.flags.has(Campaign.BUILD_FIRST), "and the flag is gone: the tide clock runs from here")
	d["build"].set_build(false)
	var before: float = c.tide.linger_left()
	map.tick_linger(5.0)
	check(c.tide.linger_left() < before, "the tide clock runs after the first launch")
	_free_all(d)


# --- saving ------------------------------------------------------------------------------------------------------

func test_a_blank_run_saves_and_loads_before_and_after_the_first_launch() -> void:
	var d := _run(_profile([]))
	var map: MapView = d["map"]
	var sim: ShipSim = d["sim"]
	var c: Campaign = map.campaign
	var again := Campaign.new(1)
	eq(again.load_dict(JSON.parse_string(JSON.stringify(c.to_dict()))), "", "the campaign loads before the first launch")
	check(again.flags.has(Campaign.BUILD_FIRST), "with the flag still up")
	var ship: Ship = sim.player_ship()
	var copy: Ship = Ship.from_design(BLANK)
	eq(copy.load_dict(JSON.parse_string(JSON.stringify(ship.to_dict()))), "", "the ship loads")
	eq(copy.inventory.to_dict(), ship.inventory.to_dict(), "with the same hold")
	var built := _built()
	sim.ships[0] = built
	check(_launch(c, built)["ok"], "the first launch")
	var after := Campaign.new(1)
	eq(after.load_dict(JSON.parse_string(JSON.stringify(c.to_dict()))), "", "the campaign loads after it")
	check(not after.flags.has(Campaign.BUILD_FIRST), "with the flag down")
	eq(after.current, c.current, "at the same node")
	var saved := built.to_dict()
	var back: Ship = Ship.from_design(BLANK)
	eq(back.load_dict(JSON.parse_string(JSON.stringify(saved))), "", "the built ship loads")
	eq(back.grid.tiles.size(), built.grid.tiles.size(), "with all its tiles")
	eq(Launch.problems(back), [], "and still flies")
	var old := Campaign.new(1)
	var legacy := c.to_dict()
	legacy["flags"].erase(Campaign.BUILD_FIRST)
	eq(old.load_dict(JSON.parse_string(JSON.stringify(legacy))), "", "a save with no such flag (every older one) loads")
	_free_all(d)


# --- the soldier -------------------------------------------------------------------------------------------------

func test_the_soldier_choice_applies_as_on_any_ship() -> void:
	var p := _profile(["start_halcyon_scout"])
	var sim := ShipSim.new()
	sim.ships = [Ship.from_design(BLANK)]
	var ship: Ship = sim.ships[0]
	RunStart.apply_ship(ship, {"species": "start_halcyon_scout"}, p)
	eq(ship.crew_plan[0], {"name": "Wick", "species": "human", "player": true}, "the soldier is Wick")
	eq(ship.crew_plan.size(), 2, "and the repair drone is aboard")
	var plain: Ship = Ship.from_design(BLANK)
	RunStart.apply_ship(plain, {}, p)
	eq(plain.crew_plan[0]["name"], "Soldier", "with no choice, the design's soldier")
	check(plain.inventory.count("fuel") >= 6, "and the fuel every run starts with")
	sim.free()
