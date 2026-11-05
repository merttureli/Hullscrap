extends "res://tests/base_test.gd"
## The owner's playtest bugs (Beta 3): a boarding leaves nothing of its site behind, a beaten ship floats in open space, the build camera frames the hull, the crew never
## start on a part, a crawler leaves no body, and every ship you board can be walked (the audit is tests/walk_check.gd; the full sweep tests/tool_walkable.gd).

const BoardView = preload("res://scripts/board/board_view.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Site = preload("res://scripts/board/site.gd")
const WreckSite = preload("res://scripts/board/wreck_site.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const ShipGrid = preload("res://scripts/ship/ship_grid.gd")
const TileDefs = preload("res://scripts/ship/tile_defs.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Hangar = preload("res://scripts/space/hangar.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Content = preload("res://scripts/data/content.gd")
const Check = preload("res://tests/walk_check.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.inventory.add("hand_ammo", 40 - s.inventory.count("hand_ammo"))
	return s


func _enemy(faction := "concord", size := "medium", seed_value := 3) -> Dictionary:
	var e: Ship = Shipgen.build(faction, size, seed_value, 150.0)
	Jobs.spawn_enemy_crew(e)
	return JSON.parse_string(JSON.stringify(e.to_dict()))


## A view aboard `site` (no sector behind it).
func _view(site):
	var s = Boarding.start(null, null, "ob", {"kind": site.kind}, _ship())
	s.site = site
	s.soldier.pos = site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({})
	var b := BoardView.new()
	b.ask_party = false
	b.enter(s)
	return b


# --- 1 and 2: the site goes with the visit; a beaten ship has open space round her -----------------------------------

func test_nothing_of_a_station_is_left_when_the_boarding_ends() -> void:
	var site = Site.make(31, "station", {"faction": "clans"})
	check(site.gen == "modules" and not site.backdrop.is_empty(), "the station is a module station with windows")
	var b = _view(site)
	var nodes: Array = [b.ship_view, b._decor, b._sky, b._over, b._lights, b._mod]
	check(nodes.all(func(n): return n != null), "its decor, sky and lights stand while aboard")
	b.leave()
	for n in nodes:
		check(not is_instance_valid(n), "and none is left alive after leaving")
	check(b._decor == null and b._sky == null and b.ship_view == null, "the view lets go of them")
	b.free()


func test_a_wreck_and_a_won_fight_have_no_station_backdrop_and_a_station_keeps_one() -> void:
	for fight in ["won", "captured"]:
		var site = WreckSite.make(77, _enemy(), {"fight": fight})
		check(site != null and site.backdrop.is_empty() and site.gen == "", "a %s ship has no station backdrop" % fight)
		var b = _view(site)
		check(b.sky_up(), "but her stars stay up round the hull")
		check(b._sky == null, "with no backdrop layer in them (%s)" % fight)
		b.leave()
		b.free()
	var st = Site.make(31, "station", {"faction": "clans"})
	check(not st.backdrop.is_empty(), "a station site still has its backdrop")
	var sb = _view(st)
	check(sb._sky != null and sb.sky_up(), "and shows it through its windows")
	sb.leave()
	sb.free()
	var gen = Site.make(5, "derelict")
	var gb = _view(gen)
	check(not gb.sky_up(), "a generated derelict has no windows on the sky")
	gb.leave()
	gb.free()


# --- 3: the build camera frames the hull -------------------------------------------------------------------------------

func _build_off_centre() -> BuildMode:
	var defs := TileDefs.new()
	defs.load_file("res://data/tiles.json")
	var g := ShipGrid.new(Vector2i(40, 40), defs)
	g.fill_circle_hull(19.0)
	for y in range(4, 10):
		for x in range(6, 16):
			g.force_tile(Vector2i(x, y), "floor")  # a hull built in a corner of the plate
	var sim := ShipSim.new()
	sim.ships = [Ship.new("T", g)]
	var b := BuildMode.new()
	b.sim = sim
	b.cam = Camera2D.new()
	return b


func test_the_build_camera_starts_on_the_hull_not_the_plate() -> void:
	var b := _build_off_centre()
	var want: Vector2 = b._origin() + Vector2(6 + 15 + 1, 4 + 9 + 1) * BuildMode.CELL / 2.0
	eq(b.hull_centre(), want, "the middle of the hull's box")
	check(b.hull_centre().distance_to(b.ship.world_pos) > 100.0, "which is well off the plate's middle")
	var v := SectorView.new()
	v.build = b
	v.cam = b.cam
	v._posed = true
	b.cam.position = Vector2(1200.0, -800.0)  # (where the flight left it)
	v._unpose()
	eq(b.cam.position, want, "back in the build screen the camera sits on the hull")
	b.pan = Vector2.ZERO
	b.build_on = true
	b.reset_pan()
	eq(b.cam.position + b.cam.offset, want, "and Home keeps it there")
	b.cam.free()
	b.sim.free()
	b.free()
	v.free()


# --- 4: nobody starts on a part ---------------------------------------------------------------------------------------

func _on_part(ship: Ship) -> Array:
	var parts := {}
	for uid in ship.components.instances:
		for c in ship.components.instances[uid]["cells"]:
			parts[c] = str(ship.components.instances[uid]["id"])
	var out := []
	for m in ship.crew:
		for c in Pathfinder.body_cells(m.anchor(), m.body_size):
			if parts.has(c) and (parts[c] != "bed" or m.is_player):  # (crew start at the beds, the soldier does not)
				out.append("%s on %s at %s" % [m.name, parts[c], c])
	return out


func test_the_crew_of_every_starter_stand_clear_of_the_parts() -> void:
	var starters := Hangar.starters()
	check(starters.size() >= 10, "the hangar lists its starters (%d)" % starters.size())
	for e in starters:
		var s: Ship = Ship.from_design(str(e["path"]))
		if s == null:
			continue
		Jobs.spawn_crew(s)
		check(not s.crew.is_empty(), "%s has a crew" % e["id"])
		eq(_on_part(s), [], "%s: nobody stands on a part" % e["id"])


func test_a_new_recruit_and_a_drone_come_aboard_clear_of_the_parts_too() -> void:
	var s := _ship()
	s.inventory.add("repair_drone", 1)
	Jobs.launch_drones(s)
	eq(_on_part(s), [], "the crew and the drone")


# --- 5: crawlers drop nothing -----------------------------------------------------------------------------------------

func test_a_killed_crawler_leaves_no_body_to_loot_but_a_scavenger_does() -> void:
	var s = Boarding.start(null, null, "cr", {"kind": "station"}, _ship())
	s.site = Site.make(31, "station", {"faction": "clans", "gen": "classic"})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	var room := -1
	for r in s.site.rooms:
		if r["id"] != s.site.airlock["room"]:
			room = r["id"]
			break
	var at: Vector2 = Vector2(s.site.rooms[room]["rect"].position) + Vector2(3, 3)
	var bodies: int = s.site.props.filter(func(p): return p["prop"] == "corpse").size()
	var c: Dictionary = s.foes.add("crawler", at, room)
	check(not c.has("corpse"), "a crawler is made with no body")
	c["m"].hp = 0.0
	s.foes._kill(c)
	check(c["dead"] and not c.has("corpse"), "it dies and leaves none")
	eq(s.site.props.filter(func(p): return p["prop"] == "corpse").size(), bodies, "the site holds no new body")
	var m: Dictionary = s.foes.add("scavenger", at, room)
	check(m.has("corpse"), "a scavenger keeps its body")
	m["m"].hp = 0.0
	s.foes._kill(m)
	check(s.site.props[int(m["corpse"])]["loot"], "and it can be searched")


# --- 6: every ship you board can be walked ----------------------------------------------------------------------------

const SEEDS := [1, 2, 3, 4]


func test_every_generated_ship_has_a_hatch_and_no_room_the_soldier_cannot_reach() -> void:
	var n := 0
	for f in ["clans", "concord", "kett", "human", "rustfangs", "fenn", "hollow", "sporeling"]:
		for size in ["small", "medium", "large"]:
			for sd in SEEDS:
				var e: Ship = Shipgen.build(f, size, sd, 150.0)
				if e == null:
					continue
				Jobs.spawn_enemy_crew(e)
				var a: Dictionary = Check.audit(JSON.parse_string(JSON.stringify(e.to_dict())), sd)
				n += 1
				check(a["site"], "%s %s %d: a hatch can be made" % [f, size, sd])
				eq(a["shipped"], 0, "%s %s %d: every room a body can stand in is reached from the airlock" % [f, size, sd])
	check(n >= 80, "%d ships audited" % n)


func test_every_hand_made_design_can_be_boarded_and_walked() -> void:
	var paths: Array = Content.ships().map(func(e): return str(e["path"]))
	check(paths.size() >= 40, "%d designs found" % paths.size())
	for p in paths:
		var s = Ship.from_design(p)
		if s == null:
			continue
		Jobs.spawn_crew(s)
		var a: Dictionary = Check.audit(JSON.parse_string(JSON.stringify(s.to_dict())))
		check(a["site"], "%s: a hatch can be made (else she is boarded as a generated site)" % p)
		eq(a["shipped"], 0, "%s: every room a body can stand in is reached from the airlock" % p)
