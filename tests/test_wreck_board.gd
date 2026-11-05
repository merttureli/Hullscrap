extends "res://tests/base_test.gd"
## Boarding the ship you beat (docs/BOARDING.md, Beta 4.1): the site made from the enemy Ship as the fight left it (wreck_site.gd), air on foot (air.gd),
## the suit it takes to go into a ship with no air, and what a beaten foe leaves (loot.gd).

const Site = preload("res://scripts/board/site.gd")
const WreckSite = preload("res://scripts/board/wreck_site.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Air = preload("res://scripts/board/air.gd")
const Foes = preload("res://scripts/board/foes.gd")
const Party = preload("res://scripts/board/party.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


## An enemy ship as a fight might leave her: `air` the pressure of every room, `dead` how many of her crew bled out (they lie where they stood).
func _enemy(seed_value := 3, faction := "concord", air := 1.0, dead := 0) -> Dictionary:
	var e: Ship = Shipgen.build(faction, "medium", seed_value, 150.0)
	Jobs.spawn_enemy_crew(e)
	for i in e.atmosphere.pressure.size():
		e.atmosphere.pressure[i] = air
	for i in dead:
		if e.crew.is_empty():
			break
		var m = e.crew.pop_front()
		e.dead_crew.append(m.name)
		e.dead_at[m.name] = {"pos": [m.pos.x, m.pos.y], "species": m.species}
	return JSON.parse_string(JSON.stringify(e.to_dict()))


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.crew.append(CrewMember.new("Bram", Vector2(10, 10), "human"))
	s.inventory.add("hand_ammo", 40)
	return s


func _digest(s) -> Array:
	return [s.rooms.map(func(r): return [r["rect"], r["purpose"], r["air"]]), s.props.map(func(p): return [p["prop"], p["cell"], p["size"], p["blocks"]]), s.airlock, s.doors.map(func(d): return d["cells"]), s.foe_crew]


## A visit to a site made from `d`, with no sector or campaign behind it.
func _visit(d: Dictionary, fight := "won"):
	var s = Boarding.start(null, null, "w1", {"kind": "wreck"}, _ship())
	s.site = WreckSite.make(77, d, {"fight": fight})
	s.soldier.pos = s.site.airlock["spawn"]
	s.foes = Foes.new(s)
	s.foes.spawn_site({"mem": {}})
	return s


func test_a_beaten_ships_site_keeps_her_rooms_holes_parts_and_hatch() -> void:
	var e := _enemy()
	var ship = WreckSite.load_ship(e)
	var hole := Vector2i(-1, -1)
	for c in ship.grid.tiles:  # shoot an outer wall open
		if ship.grid.tiles[c] != "floor" and ship.grid.tiles[c] != "door" and ship.grid.get_tile(c + Vector2i.UP) == "":
			hole = c
			break
	check(hole != Vector2i(-1, -1), "a wall to shoot")
	ship.grid.breach(hole)
	var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
	var site = WreckSite.make(5, d, {"fight": "won"})
	check(site != null and site.ok, "the site is built")
	eq(site.rooms.size(), ship.atmosphere.rooms.size(), "her rooms are the site's rooms")
	eq(site.grid.get_tile(hole), "", "the shot-away wall is a hole")
	check(not Pathfinder.walkable(site.walk, hole), "and no body walks out through it")
	var parts: Array = site.props.filter(func(p): return p.has("part"))
	eq(parts.size(), ship.components.instances.size(), "every part stands as a prop")
	check(parts.any(func(p): return p["blocks"]), "and they block like walls")
	var h: Array = site.airlock["hatch"]
	check(site.grid.tile_flag(site.grid.get_tile(h[0]), "solid") and site.grid.tile_flag(site.grid.get_tile(h[1]), "solid"), "the hatch is in her wall")
	eq(site.rooms[site.airlock["room"]]["purpose"], "airlock", "of the airlock room")
	eq(site.problems(), [], "the site is sound")
	eq(_digest(WreckSite.make(5, d, {"fight": "won"})), _digest(site), "the same ship and seed give the same site")
	var purposes := {}
	for r in site.rooms:
		purposes[r["purpose"]] = true
	check(purposes.has("engineering") or purposes.has("command"), "the rooms take their purpose from their parts")


func test_a_destroyed_part_is_wreckage() -> void:
	var ship = WreckSite.load_ship(_enemy(4))
	var uid: int = ship.components.instances.keys()[2]
	var cells: Array = ship.components.instances[uid]["cells"].duplicate()
	ship.components.instances.erase(uid)
	ship.components.wrecks.append({"id": "reactor_mk1", "cells": cells})
	var site = WreckSite.make(5, JSON.parse_string(JSON.stringify(ship.to_dict())), {})
	check(site.props.any(func(p): return p["prop"] == "heap"), "the wreckage is a scrap heap")


func test_a_ship_drained_of_air_boards_airless_with_no_foes_and_bodies() -> void:
	var s = _visit(_enemy(3, "concord", 0.0, 99))
	for r in s.site.rooms:
		check(Air.bad(s.site.air_of(r["id"])), "room %d has no air" % r["id"])
	eq(s.foes.live().size(), 0, "nobody is left standing")
	var bodies: Array = s.site.props.filter(func(p): return p["prop"] == "body")
	check(bodies.size() >= 3, "her crew who died lie where they fell")
	check(s.needs_suit(), "the airlock has no air: a suit is needed to board her")


func test_a_captured_ship_has_no_foes_and_a_won_one_has_her_crew_standing() -> void:
	var e := _enemy(3, "concord", 1.0, 0)
	var won = _visit(e, "won")
	check(won.foes.live().size() > 0, "after a win her crew on their feet are foes")
	for f in won.foes.live():
		check(won.site.walk.get_tile(Vector2i(floori(f["m"].pos.x), floori(f["m"].pos.y))) != "", "%s stands on her floor" % f["m"].name)
	var cap = _visit(e, "captured")
	eq(cap.foes.live().size(), 0, "a captured ship has no hostile foes")
	check(cap.site.props.filter(func(p): return p["prop"] == "body").size() >= 3, "her crew lie as bodies")


func test_an_edge_room_with_air_is_the_airlock() -> void:
	var better := 0
	for sd in [3, 7, 11]:
		var site = WreckSite.make(1, _enemy(sd))
		var first: int = site.airlock["room"]
		var ship = WreckSite.load_ship(_enemy(sd))
		ship.atmosphere.pressure[first] = 0.0
		var d: Dictionary = JSON.parse_string(JSON.stringify(ship.to_dict()))
		var again = WreckSite.make(1, d)
		check(again != null, "built")
		if again.airlock["room"] != first:
			better += 1
			check(not Air.bad(again.air_of(again.airlock["room"])), "the hatch moved to a room with air")
	check(better >= 1, "an airless edge room is passed over for one with air")


func test_suffocation_on_foot_and_a_sealed_suit_stops_it() -> void:
	var s = _visit(_enemy(3, "concord", 0.0, 3))
	var hp: float = s.soldier.hp
	s.tick(2.0)
	check(s.soldier.hp < hp, "the soldier loses hp in a room with no air")
	eq(Air.line(s.site, s.soldier, s.soldier.pos)["word"], "NONE", "the AIR line says so")
	var secs := float(Air.line(s.site, s.soldier, s.soldier.pos)["secs"])
	check(secs > 0.0 and secs < 40.0, "and counts the seconds left")
	s.soldier.hp = s.soldier.max_hp
	s.soldier.kit = {"weapons": ["service_pistol", ""], "body": "eva_suit", "mods": ["", ""]}
	s.tick(2.0)
	eq(s.soldier.hp, s.soldier.max_hp, "a sealed suit stops it")
	s.soldier.kit = {"weapons": ["service_pistol", ""], "body": "basic_armor", "mods": ["", ""]}
	check(not Air.sealed(s.soldier), "plain armour is not sealed")
	var open := Foes.new(s)
	check(Site.config()["enemies"]["pirate"]["sealed"], "a generated foe wears a suit")
	check(open != null, "(foes)")


func test_a_door_into_a_room_with_no_air_is_shut_to_the_unsuited_soldier() -> void:
	var s = _visit(_enemy(3, "concord", 0.0, 1))
	var d: Dictionary = s.site.doors[0]
	var cell: Vector2i = d["cells"][0]
	check(not s.soldier_passable().call(cell), "the door will not let him through")
	s.soldier.pos = s.site.door_centre(d)
	s.tick(0.1)
	var told := false
	for e in s.take_events():
		told = told or (e["type"] == "line" and str(e["text"]) == Air.NO_SUIT_DOOR)
	check(told, "and he is told why")
	check(not s.site.grid.is_door_open(cell), "the door stays shut")
	s.soldier.kit = {"weapons": ["service_pistol", ""], "body": "exosuit", "mods": ["", ""]}
	check(s.soldier_passable().call(cell), "in a sealed suit he goes through")
	s.tick(0.1)
	check(s.site.grid.is_door_open(cell), "and the door opens")


func test_a_follower_without_a_suit_waits_at_the_door_of_an_airless_room() -> void:
	var s = _visit(_enemy(3, "concord", 1.0, 0))
	s.join_party(["Bram"])
	check(not s.party.is_empty(), "Bram came along")
	var p: Dictionary = s.party[0]
	var d: Dictionary = s.site.doors[0]
	var here: int = d["rooms"][0]
	var far: int = d["rooms"][1]
	check(here != far and not s.site.free_anchors(here).is_empty() and not s.site.free_anchors(far).is_empty(), "a door between two rooms")
	s.site.rooms[far]["air"] = 0.0
	p["m"].pos = Vector2(s.site.free_anchors(here)[0]) + Vector2.ONE
	var target: Vector2 = Vector2(s.site.free_anchors(far)[0]) + Vector2.ONE
	s.foes.path_to(p, target)
	check(not p["m"].path.is_empty(), "a path to it")
	check(Air.wait(s, p), "Bram holds at the door")
	check(p["m"].path.is_empty(), "and goes no further")
	var told: bool = s.take_events().any(func(e): return e["type"] == "line" and str(e["text"]).contains("waits at the door"))
	check(told, "and says so")
	p["m"].kit = {"weapons": ["service_pistol", ""], "body": "eva_suit", "mods": ["", ""]}
	s.foes.path_to(p, target)
	check(not Air.wait(s, p), "in a sealed suit he goes in")


func test_a_wreck_survives_a_save_and_an_old_saves_wreck_is_a_generated_site() -> void:
	var c := Campaign.new(3, Campaign.config().duplicate(true))
	var sec: Sector = c.current_sector()
	var d := _enemy(7)
	sec.wreck_ships["w1"] = {"ship": d, "fight": "won"}
	var json = JSON.parse_string(JSON.stringify(sec.to_save()))
	var sec2: Sector = Campaign.new(3, Campaign.config().duplicate(true)).current_sector()
	eq(sec2.load_save(json), "", "the sector loads")
	check(sec2.wreck_ships.has("w1"), "the beaten ship is kept")
	var a = Boarding.start(null, sec, "w1", {"kind": "wreck"}, _ship())
	var b = Boarding.start(null, sec2, "w1", {"kind": "wreck"}, _ship())
	check(a.site.ship != null and b.site.ship != null, "she is boarded as that ship")
	eq(_digest(b.site), _digest(a.site), "the same on every visit")
	json["wreck_ships"] = {}
	var sec3: Sector = Campaign.new(3, Campaign.config().duplicate(true)).current_sector()
	eq(sec3.load_save(json), "", "an older save loads")
	var old = Boarding.start(null, sec3, "w1", {"kind": "wreck"}, _ship())
	check(old.site.ok and old.site.ship == null, "its wreck is a generated site")
	check(Campaign.VERSION >= 13, "the save version came with the wreck ships")


func test_board_her_is_locked_with_no_suit_and_open_with_one() -> void:
	var c := Campaign.new(3, Campaign.config().duplicate(true))
	var ship := _ship()
	var ev := {"id": "salvage", "type": "salvage", "title": "S", "text": "t", "choices": [{"text": "Strip", "outcomes": [{"weight": 1, "text": "", "effects": {"items": {"scrap": 1}}}]}]}
	var offered := Boarding.offer(ev, "wreck", {}, false, true)
	var view: Array = c.events.choice_view(offered, c, ship)
	var row: Dictionary = view[view.size() - 1]
	check(row["grey"] and str(row["locked"]) == Air.NO_SUIT_BOARD, "no suit: the row is locked with the reason")
	eq(view.size(), 2, "the other rows stay")
	check(not view[0]["grey"], "and open")
	eq(c.events.choose(offered, offered["choices"].size() - 1, c, ship)["why"], Air.NO_SUIT_BOARD, "choosing it is refused")
	ship.inventory.add("eva_suit", 1)
	view = c.events.choice_view(offered, c, ship)
	check(not view[view.size() - 1]["grey"], "a suit in the hold opens it")
	check(not c.events.choice_view(Boarding.offer(ev, "wreck", {}, false, false), c, _ship())[1]["grey"], "a wreck with air is open to all")


func test_go_aboard_is_refused_until_the_soldier_wears_a_sealed_suit() -> void:
	const BoardView = preload("res://scripts/board/board_view.gd")
	var ship := _ship()
	ship.inventory.add("eva_suit", 1)
	var s = Boarding.start(null, null, "w1", {"kind": "wreck"}, ship)
	s.site = WreckSite.make(77, _enemy(3, "concord", 0.0, 1), {})
	var v = BoardView.new()
	v.session = s
	v.picking = true
	v.confirm_party()
	check(v.picking and v.load_msg == Air.NO_SUIT_BOARD, "refused, with the reason")
	for m in ship.crew:
		if m.is_player:
			m.kit = {"weapons": ["service_pistol", ""], "body": "eva_suit", "mods": ["", ""]}
	v.confirm_party()
	check(not v.picking, "he goes aboard once he wears one")
	v.free()


func test_a_beaten_foe_leaves_a_body_with_ammo_and_credits() -> void:
	var s = _visit(_enemy(3, "concord", 1.0, 0))
	var site = s.site
	var before: int = site.containers().size()
	var f: Dictionary = s.foes.add("pirate", site.airlock["spawn"] + Vector2(4, 0), 0, true)
	var id: int = f["corpse"]
	check(not site.props[id]["loot"], "a standing foe's body holds nothing yet")
	s.foes.hurt(f, 999.0, f["m"].pos)
	check(site.props[id]["loot"], "a beaten foe's body can be searched")
	eq(site.containers().size(), before, "but it is no part of what clears the site")
	s.open(id)
	var items: Dictionary = s.left[id]["items"]
	check(int(items.get("hand_ammo", 0)) >= 3, "it always has ammo")
	check(int(items.get("credits", 0)) >= 1, "and credits")
	eq(s.opened_count(), 0, "an opened body is not an opened container")
	var rolls := 0
	var weapons := 0
	for i in 200:  # the weapon at about foe_drop (0.2 since the playtest cut guns by half), from the dice of the site and the body
		site.seed_value = i
		var got: Dictionary = Loot.resolve(site, id, {})["items"]
		rolls += 1
		weapons += int(got.has("doorbuster"))
	check(weapons > 24 and weapons < 58, "the weapon comes at about 20 percent (%d of %d)" % [weapons, rolls])
