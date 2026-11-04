extends "res://tests/base_test.gd"
## Module stations (scripts/board/station_gen.gd, data/station_modules.json): the catalogue fits together, every station is sound for a 2x2 body,
## the seed makes the station, the keycard and the air rules, stable container ids, the memory of a visit through a save, the classic switch and
## old saves, what each state changes, the windows.

const Site = preload("res://scripts/board/site.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Foes = preload("res://scripts/board/foes.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const STATES: Array[String] = ["abandoned", "half", "operational"]


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


func _station(seed_value: int, state := "", region := "clan_space"):
	var opts := {"faction": "clans", "region": region}
	if state != "":
		opts["state"] = state
	return Site.make(seed_value, "station", opts)


## Everything that makes a site what it is, to compare two.
func _digest(s) -> Array:
	var tiles := []
	for c in s.grid.tiles:
		tiles.append([c.x, c.y, s.grid.tiles[c]])
	tiles.sort()
	return [tiles, s.props.map(func(p): return [p["id"], p["prop"], p["cell"], p["size"], p["slot"], p["key"]]), s.doors.map(func(d): return [d["cells"], d["lock"], d["card"]]),
		s.rooms.map(func(r): return [r["rect"], r["purpose"], r.get("air", 1.0)]), s.airlock, s.site_name, s.state, s.room_light, s.windows, s.beds, s.posts, s.backdrop]


# --- the catalogue --------------------------------------------------------------------------------------------------

func test_there_are_at_least_ten_modules_and_every_footprint_is_sound() -> void:
	var mods := StationGen.modules()
	check(mods.size() >= 10, "at least 10 modules (%d)" % mods.size())
	for mid in mods:
		var def: Dictionary = mods[mid]
		var w: int = def["cells"][0].length()
		check(def["cells"].all(func(r): return r.length() == w), "%s: every row is as wide" % mid)
		for rot in 4:
			var v := StationGen._variant(mid, rot)
			check(not v["conns"].is_empty(), "%s: has a connector" % mid)
			for conn in v["conns"]:
				var n: Vector2i = conn["side"]
				var along := Vector2i(absi(n.y), absi(n.x))
				var cl: Array = conn["cells"]
				eq(cl.size(), 2 if conn["type"] == "door" else 5, "%s: a %s connector's width" % [mid, conn["type"]])
				check(v["cells"].get(cl[0] - along, "") == "x" and v["cells"].get(cl[-1] + along, "") == "x", "%s rot %d: a connector has wall at both ends" % [mid, rot])
				for c in cl:
					check(v["cells"].get(c - n, "") == "f", "%s rot %d: a floor right inside every connector cell" % [mid, rot])
			var rooms := {}
			for c in v["room"]:
				var k: int = v["room"][c]
				if not rooms.has(k):
					rooms[k] = []
				rooms[k].append(c)
			eq(rooms.size(), def["rooms"].size(), "%s: a room def for every room" % mid)
			for k in rooms:
				var a: Vector2i = rooms[k][0]
				var b: Vector2i = rooms[k][0]
				for c in rooms[k]:
					a = a.min(c)
					b = b.max(c)
				eq((b - a + Vector2i.ONE).x * (b - a + Vector2i.ONE).y, rooms[k].size(), "%s: room %d is a rectangle" % [mid, k])
				check((b - a).x >= 1 and (b - a).y >= 1, "%s: room %d is at least 2x2 (a body fits)" % [mid, k])
			for pair in v["inner"]:
				var side := Vector2i((pair[1] - pair[0]).y, (pair[1] - pair[0]).x)
				check(v["room"].has(pair[0] - side) and v["room"].has(pair[0] + side) and v["room"][pair[0] - side] != v["room"][pair[0] + side], "%s: an inner door joins two rooms" % mid)
			for c in v["wins"]:  # a window never holds up a door: it leaves the grid (space shows through)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					check(not v["conns"].any(func(cc): return cc["cells"].has(c + d)) and not v["inner"].any(func(p): return p.has(c + d)), "%s: no window beside a door" % mid)
		for p in def["rooms"].map(func(r): return r["purpose"]):
			for q in (p.keys() if p is Dictionary else [p]):
				check(Site.config()["rooms"].has(q), "%s: purpose %s is a boarding room" % [mid, q])
	check(StationGen._variant("dock", 0)["hatch"].size() == 2, "the dock has a 2-wide hatch")


func test_every_connector_of_every_module_takes_another_module() -> void:
	for mid in StationGen.modules():
		var v := StationGen._variant(mid, 0)
		for k in v["conns"].size():
			var g = StationGen.new()
			g.s = Site.new()
			g.type = "habitat"
			g.rng.seed = 7
			g._stamp({"mod": mid, "v": v, "off": Vector2i.ZERO, "parent": -1, "links": StationGen._open_links(v)})
			var took := false
			for other in StationGen.modules():
				if other != "dock" and g._attach(other, 0, k):
					took = true
					break
			check(took, "%s: connector %d takes a module" % [mid, k])


# --- every station is sound -----------------------------------------------------------------------------------------

func test_stations_are_sound_for_a_2x2_body_in_every_state() -> void:
	var made := 0
	for st in STATES:
		for i in 6:
			var s = _station(300 + i * 41, st)
			if s.gen != "modules":
				continue
			made += 1
			eq(s.problems(), [], "seed %d %s: no problems" % [300 + i * 41, st])
			var seen: Dictionary = s.reach(s.spawn_anchor(), func(_c): return true)
			var near := {}
			for a in seen:
				near[Vector2(a) + Vector2.ONE] = true
			for id in s.containers():
				var c: Vector2 = s.centre_of(s.props[id])
				check(near.keys().any(func(p): return p.distance_to(c) <= float(Site.config()["reach"])), "seed %d: container %d can be reached" % [300 + i * 41, id])
			check(s.modules.size() >= 5, "a station of modules (%d)" % s.modules.size())
			check(s.modules.any(func(m): return m["id"] == "command") and s.modules.any(func(m): return m["id"] == "reactor" or str(StationGen.modules()[m["id"]].get("counts_as", "")) == "reactor"), "it has its type's minimum modules (a forge or a magma hall counts as the reactor)")
	check(made >= 16, "the modules build almost every station (%d of 18)" % made)


func test_the_same_seed_gives_the_same_station_and_others_differ() -> void:
	var a = _station(4242)
	var b = _station(4242)
	eq(_digest(b), _digest(a), "the same seed, the same station")
	var c = _station(4243)
	check(_digest(c) != _digest(a), "another seed, another station")
	var looks := {}
	for i in 8:
		var s = _station(900 + i)
		looks[str(s.modules.map(func(m): return [m["id"], m["rect"]]))] = true
	eq(looks.size(), 8, "8 seeds, 8 different layouts")


func test_the_command_deck_sits_behind_a_checkpoint_with_a_card_door_whose_key_needs_no_suit() -> void:
	for i in 10:
		var s = _station(1300 + i * 7)
		if s.gen != "modules":
			continue
		var cmd: Array = s.modules.filter(func(m): return m["id"] == "command")
		eq(cmd.size(), 1, "one command deck")
		var rid: int = cmd[0]["rooms"][0]
		var doors: Array = s.rooms[rid]["doors"].map(func(d): return s.doors[d])
		eq(doors.size(), 1, "the command deck has one door")
		var other: int = doors[0]["rooms"][0] if doors[0]["rooms"][1] == rid else doors[0]["rooms"][1]
		eq(s.rooms[other]["purpose"], "security", "and it opens on the checkpoint")
		check(doors[0]["lock"] == "card" or doors[0]["lock"] == "hack", "that door is locked")
		check(s.rooms[rid]["locked"], "the command deck is a locked room")
		var free: Dictionary = s.reachable_rooms(["card"], true)
		for d in s.doors:
			if d["lock"] == "card":
				check(s.props.any(func(p): return p["slot"] == "key" and p["key"] == d["card"] and free.has(p["room"])), "the %s keycard lies where he can get without it and without a suit" % d["card"])


func test_container_ids_stay_the_same_for_a_seed() -> void:
	var a = _station(777, "half")
	var b = _station(777, "half")
	eq(a.containers(), b.containers(), "the same container ids")
	for id in a.containers():
		eq([b.props[id]["prop"], b.props[id]["cell"], b.props[id]["room"]], [a.props[id]["prop"], a.props[id]["cell"], a.props[id]["room"]], "container %d is the same one" % id)


func test_a_station_visit_comes_back_the_same_through_a_save() -> void:
	var c := Campaign.new(5, Campaign.config().duplicate(true))
	var sec: Sector = c.current_sector()
	var ship := _ship()
	var b = Boarding.start(null, sec, "st1", {"kind": "station"}, ship)
	eq(b.site.gen, "modules", "a new station is built of modules")
	var ids: Array = b.site.containers()
	b.open(ids[0])
	b.open(ids[2])
	b.take(ids[0])
	var locked: Array = b.site.doors.filter(func(d): return d["lock"] == "hack")
	if not locked.is_empty():
		b.unlock(locked[0]["id"], true)
	b.leave()
	eq(sec.boarded["st1"]["gen"], "modules", "the memory says how it was built")
	eq(sec.boarded["st1"]["state"], b.site.state, "and in what state")
	var json = JSON.parse_string(JSON.stringify(sec.to_save()))
	var sec2: Sector = Campaign.new(5, Campaign.config().duplicate(true)).current_sector()
	eq(sec2.load_save(json), "", "the sector loads")
	var b2 = Boarding.start(null, sec2, "st1", {"kind": "station"}, ship)
	eq(_digest(b2.site), _digest(b.site), "the same station")
	eq(b2.opened.keys(), b.opened.keys(), "the same containers are open")
	eq(b2.left.keys(), b.left.keys(), "the same things are left in them")
	if not locked.is_empty():
		check(b2.door_open_to_soldier(locked[0]["id"]), "the hacked door stays open")


func test_the_classic_switch_and_old_saves_still_build_classic_stations() -> void:
	var s = Site.make(55, "station", {"faction": "clans", "gen": "classic"})
	eq(s.gen, "classic", "gen classic builds the bands")
	check(s.modules.is_empty() and s.windows.is_empty() and s.state == "", "with no modules, windows or state")
	eq(s.problems(), [], "and it is sound")
	var d = Site.make(55, "derelict", {"faction": "clans"})
	eq(d.gen, "", "another kind is never built of modules")
	var c := Campaign.new(6, Campaign.config().duplicate(true))
	var sec: Sector = c.current_sector()
	sec.boarded["old"] = {"kind": "station", "name": "", "parts": [], "opened": [], "unlocked": [], "keys": [], "left": {}}  # (a memory from before module stations)
	var b = Boarding.start(null, sec, "old", {"kind": "station"}, _ship())
	eq(b.site.gen, "classic", "a station visited before the modules stays classic")
	var fresh = Boarding.start(null, sec, "new", {"kind": "station"}, _ship())
	eq(fresh.site.gen, StationGen.switch(), "a new one follows the switch")


# --- states, windows, crossings ----------------------------------------------------------------------------------------

func test_each_state_sets_light_air_power_and_who_is_aboard() -> void:
	for i in 4:
		var op = _station(2000 + i, "operational")
		if op.gen != "modules":
			continue
		check(op.room_light.values().all(func(m): return m == "lit" or m == "flicker"), "operational: every room is lit")
		check(op.rooms.all(func(r): return op.breathable(r["id"]) or op.modules[int(r["module"])]["airless"]), "operational: air everywhere (but in a section of a race that needs none, working and airless)")
		check(not op.doors.any(func(d): return d["lock"] == "hack"), "operational: no dead doors")
		eq(op.crowd, StationGen.config()["states"]["operational"]["crowd"][op.mood], "operational: its mood says who is aboard")
		var ab = _station(2000 + i, "abandoned")
		check(not ab.room_light.values().any(func(m): return m == "lit" or m == "flicker"), "abandoned: no room has power")
		check(ab.modules.all(func(m): return not m["powered"] or m["id"] == "dock"), "abandoned: no module has power")
	var lit := 0
	var dark := 0
	for i in 6:
		var h = _station(2100 + i, "half")
		for m in h.room_light.values():
			lit += 1 if m == "lit" or m == "flicker" else 0
			dark += 1 if m == "dark" or m == "red" else 0
	check(lit > 0 and dark > 0, "half-active: some rooms lit, some dark (%d, %d)" % [lit, dark])
	var airless := 0
	for i in 12:
		var ab = _station(2200 + i, "abandoned")
		airless += ab.rooms.filter(func(r): return not ab.breathable(r["id"])).size()
		check(ab.breathable(ab.airlock["room"]), "the airlock always has air")
	check(airless > 0, "abandoned stations have breached, airless sections")


func test_windows_look_out_on_space_and_a_station_with_windows_has_a_backdrop() -> void:
	for i in 6:
		var s = _station(3000 + i * 3)
		if s.gen != "modules":
			continue
		check(not s.windows.is_empty(), "a station has windows")
		check(not s.backdrop.is_empty() and StationGen.config()["backdrop"]["kinds"].has(str(s.backdrop["kind"])), "and something to see through them")
		for run in s.windows:
			for c in run["cells"]:
				check(not s.grid.tiles.has(c), "a window is not drawn as wall")
				check(not s.grid.tiles.has(c + run["normal"]), "space right outside a window")
				check(s.opaque(c), "a shot stops at the glass")


func test_glass_tubes_are_crossings_some_airless_some_watched() -> void:
	var tubes := 0
	var watched := 0
	var airless := 0
	for i in 60:  # (a station is now about one race room different from what it was: a few more to find a sentried tube)
		var s = _station(4000 + i * 11, "abandoned")
		for m in s.modules:
			if m["id"] != "glass_tube":
				continue
			tubes += 1
			var rid: int = m["rooms"][0]
			eq(s.rooms[rid]["doors"].size(), 2, "a tube joins two sections")
			airless += 0 if s.breathable(rid) else 1
			watched += s.posts.filter(func(p): return p["room"] == rid).size()
	check(tubes > 0 and watched > 0 and airless > 0, "tubes %d, watched %d, airless %d" % [tubes, watched, airless])
	for i in 6:
		var f = _station(4500 + i, "operational")
		if f.mood == "friendly":
			check(f.posts.is_empty(), "no sentry on a friendly station")


func test_who_stands_aboard_follows_the_state() -> void:
	for i in 8:
		for st in ["abandoned", "operational"]:
			var site = _station(5000 + i * 3, st)
			if site.gen != "modules":
				continue
			var b = Boarding.start(null, null, "w%d" % i, {"kind": "station"}, null)
			b.site = site
			b.soldier.pos = site.airlock["spawn"]
			b.foes = Foes.new(b)
			b.foes.spawn_site({})
			var n: int = b.foes.list.filter(func(f): return f["kind"] != "crawler").size()
			var span: Array = site.crowd["spawn"]["count"]
			check(n >= int(span[0]) and n <= int(span[1]) + site.posts.size(), "%s %d: %d foes in %s (+%d posted)" % [st, i, n, str(span), site.posts.size()])
			if site.mood == "friendly":
				eq(n, 0, "nobody hostile on a friendly station")

