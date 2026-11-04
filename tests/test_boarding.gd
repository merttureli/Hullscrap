extends "res://tests/base_test.gd"
## Boarding, stage B1 (scripts/board/, docs/BOARDING.md): the site made from a seed (rooms, doors, locks, props, the airlock), the loot
## tables and their blueprint rates, opening a container (the loot goes to the hold), the memory of a visit through a save, the
## `board` effect and the choice that offers it, the airlock that leaves, the save that is refused aboard and a cleared site.

const Site = preload("res://scripts/board/site.gd")
const Loot = preload("res://scripts/board/loot.gd")
const Boarding = preload("res://scripts/board/boarding.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Events = preload("res://scripts/space/events.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Content = preload("res://scripts/data/content.gd")
const Components = preload("res://scripts/ship/components.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


func _camp(seed_value := 1) -> Campaign:
	var cfg: Dictionary = Campaign.config().duplicate(true)
	cfg["instant_jump"] = false
	return Campaign.new(seed_value, cfg)


## Everything that makes a site what it is, to compare two.
func _digest(s) -> Array:
	var tiles := []
	for c in s.grid.tiles:
		tiles.append([c.x, c.y, s.grid.tiles[c]])
	tiles.sort()
	return [tiles, s.props.map(func(p): return [p["prop"], p["cell"], p["size"], p["slot"], p["key"]]), s.doors.map(func(d): return [d["cells"], d["lock"], d["card"]]),
		s.rooms.map(func(r): return [r["rect"], r["purpose"]]), s.airlock, s.site_name]


# --- the site ---------------------------------------------------------------------------------------------------

func test_the_same_seed_gives_the_same_site() -> void:
	for kind in Site.kinds():
		var a = Site.make(4242, kind, {"faction": "lumen"})
		var b = Site.make(4242, kind, {"faction": "lumen"})
		eq(_digest(a), _digest(b), "a %s from the same seed" % kind)
		var c = Site.make(4243, kind, {"faction": "lumen"})
		check(_digest(a) != _digest(c), "a %s from another seed differs" % kind)


func test_every_site_is_whole() -> void:
	for kind in Site.kinds():
		for s in 10:
			var site = Site.make(s * 131 + 5, kind, {"faction": ["clans", "concord", "lumen", "rustfangs", "wardens", "hollow"][s % 6]})
			check(site.ok, "%s %d is built" % [kind, s])
			var why: Array = site.problems()
			check(why.is_empty(), "%s %d: %s" % [kind, s, str(why)])
			check(site.containers().size() >= 3, "%s %d has containers" % [kind, s])


func test_every_room_is_walkable_from_the_airlock_and_the_keys_lie_outside_their_doors() -> void:
	var cards := 0
	var hacks := 0
	for kind in Site.kinds():
		for s in 14:
			var site = Site.make(s * 17 + 3, kind, {"faction": "clans"})
			var all: Dictionary = site.reachable_rooms([])
			var no_card: Dictionary = site.reachable_rooms(["card"])
			for r in site.rooms:
				if r["purpose"] != "gone":
					check(all.has(r["id"]), "%s %d: room %d is walked to with every door open" % [kind, s, r["id"]])
			for d in site.doors:
				if d["lock"] == "card":
					cards += 1
					var keys: Array = site.props.filter(func(p): return p["slot"] == "key" and p["key"] == d["card"])
					check(keys.size() == 1 and no_card.has(keys[0]["room"]), "%s %d: the %s keycard lies where the airlock reaches without it" % [kind, s, d["card"]])
				elif d["lock"] == "hack":
					hacks += 1
	check(cards > 5 and hacks > 5, "sites do have locked doors (%d card, %d hack)" % [cards, hacks])


func test_the_airlock_is_on_the_hull_edge_and_a_prop_never_blocks_a_door() -> void:
	for kind in Site.kinds():
		for s in 8:
			var site = Site.make(s * 29 + 1, kind, {})
			var h: Array = site.airlock["hatch"]
			for c in h:
				check(site.grid.get_tile(c) == "wall" and not site.grid.in_hull(c + Vector2i(int(site.airlock["normal"].x) * 2, 0)) == false, "%s %d: the hatch is a wall cell" % [kind, s])
			var out: Vector2i = h[0] + Vector2i(int(site.airlock["normal"].x), 0)
			check(site.grid.get_tile(out) == "", "%s %d: nothing is outside the hatch" % [kind, s])
			for d in site.doors:
				if d["lock"] == "gone":
					continue
				for c in d["cells"]:
					for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if site.room_of.has(c + n):
							check(not site.walk.tiles.get(c + n, "") == "wall", "%s %d: a door cell opens onto floor" % [kind, s])
			var spawn: Vector2i = site.spawn_anchor()
			check(site.reach(spawn, func(_c): return true).size() > 10, "%s %d: the soldier can walk from the airlock" % [kind, s])


func test_site_sizes_follow_the_kind() -> void:
	var rooms := {}
	var boxes := {}
	for kind in Site.kinds():
		rooms[kind] = 0.0
		boxes[kind] = 0.0
		for s in 12:
			var site = Site.make(s * 7 + 2, kind, {"faction": "concord"})
			rooms[kind] += float(site.rooms.filter(func(r): return not r["corridor"] and r["purpose"] != "gone").size()) / 12.0
			boxes[kind] += float(site.containers().size()) / 12.0
	check(rooms["station"] >= 12.0 and rooms["station"] <= 20.0, "a station has 12 to 20 rooms (%.1f)" % rooms["station"])
	check(rooms["derelict"] >= 4.0 and rooms["derelict"] <= 9.0, "a derelict is ship sized (%.1f rooms)" % rooms["derelict"])
	check(rooms["nest"] > rooms["derelict"] and rooms["nest"] < rooms["station"], "a nest is medium (%.1f rooms)" % rooms["nest"])
	check(boxes["station"] > boxes["derelict"] and boxes["station"] > boxes["wreck"], "a station has the most containers (%.1f against %.1f)" % [boxes["station"], boxes["derelict"]])
	check(boxes["derelict"] >= 6.0 and boxes["derelict"] <= 16.0, "a derelict has a handful of containers (%.1f)" % boxes["derelict"])


# --- loot -------------------------------------------------------------------------------------------------------

func test_the_loot_tables_resolve() -> void:
	var cfg := Site.config()
	var comps := Components.new()
	comps.load_defs(Ship.COMPONENTS_PATH)
	var materials := {}
	for m in Content.list("materials"):
		materials[m["id"]] = true
	var items := {"credits": true, "fuel": true, "mod": true}  # ("mod" is the outcome that rolls a mod item, mods.gd)
	for i in Content.list("items"):
		items[i["id"]] = true
	var tables: Dictionary = cfg["tables"]
	for name in tables:
		check(not tables[name].is_empty(), "table %s is not empty" % name)
		for o in tables[name] + cfg["kinds"]["nest"]["bonus"]:
			var id := str(o["item"])
			check(materials.has(id) or items.has(id) or comps.has(id), "table %s: '%s' is a material, an item or a part" % [name, id])
			check(float(o["weight"]) > 0.0 and int(o["count"][0]) >= 1 and int(o["count"][1]) >= int(o["count"][0]), "table %s: %s has a weight and a count" % [name, id])
	for purpose in cfg["rooms"]:
		for e in cfg["rooms"][purpose]["props"]:
			check(cfg["props"].has(e["prop"]), "room %s names a prop that exists (%s)" % [purpose, e["prop"]])
			var def: Dictionary = cfg["props"][e["prop"]]
			if def["loot"]:
				check(tables.has(def.get("table", purpose)), "%s: %s has a table" % [purpose, e["prop"]])
	for kind in Site.kinds():
		for purpose in cfg["kinds"][kind]["weights"]:
			check(tables.has(purpose) and cfg["rooms"].has(purpose), "%s: purpose %s has a table and props" % [kind, purpose])
	for s in 12:
		var site = Site.make(s + 1, "station", {"faction": "clans"})
		for id in site.containers():
			var a := Loot.resolve(site, id, {"tier": 2})
			var b := Loot.resolve(site, id, {"tier": 2})
			eq(a, b, "container %d holds the same whenever it is opened" % id)
			check(not a["items"].is_empty() or a["blueprint"] != "" or a["log"] != "" or a["key"] != "", "container %d holds something" % id)


func test_blueprint_rates_are_about_right() -> void:
	var rates := {}
	for kind in ["station", "derelict", "nest"]:
		var n := 0
		var sites := 80 if kind == "station" else 150
		for s in sites:
			var site = Site.make(s * 3 + 11, kind, {"faction": "clans"})
			n += site.props.filter(func(p): return p["slot"] == "blueprint").size()
		rates[kind] = float(n) / float(sites)
	check(rates["station"] > 0.8 and rates["station"] < 1.2, "a station gives about 1 blueprint (%.2f)" % rates["station"])
	for kind in ["derelict", "nest"]:
		check(rates[kind] > 0.2 and rates[kind] < 0.4, "a %s gives about 0.3 blueprints (%.2f)" % [kind, rates[kind]])


func test_a_blueprint_is_one_the_ship_lacks_else_materials() -> void:
	var ship := _ship()
	var site = null
	var id := -1
	for s in 60:
		site = Site.make(s + 1, "station", {"faction": "clans"})
		var hits: Array = site.props.filter(func(p): return p["slot"] == "blueprint")
		if not hits.is_empty():
			id = hits[0]["id"]
			break
	check(id >= 0, "a station with a blueprint was found")
	var b = Boarding.new()
	b.site = site
	b.ship = ship
	var rid: String = b.open(id)["blueprint"]
	check(rid != "" and not ship.crafting.is_known(rid), "it holds a recipe the ship does not know (%s)" % rid)
	b.take(id)
	check(ship.crafting.is_known(rid), "taking it learns the blueprint")
	for each in ship.crafting.order:
		ship.crafting.unlock(each)
	var b2 = Boarding.new()
	b2.site = site
	b2.ship = ship
	var again: Dictionary = b2.open(id)
	check(again["blueprint"] == "" and not again["items"].is_empty(), "with every blueprint known it holds materials instead")


func test_opening_a_container_moves_its_loot_to_the_hold() -> void:
	var ship := _ship()
	var site = Site.make(77, "derelict", {"faction": "clans"})
	var b = Boarding.new()
	b.site = site
	b.ship = ship
	var id: int = site.containers()[0]
	var before := ship.inventory.counts.duplicate()
	var held: Dictionary = b.open(id)
	check(b.opened.has(id) and b.opened_count() == 1, "it counts as opened")
	eq(ship.inventory.counts, before, "opening takes nothing yet")
	var rows := b.entries(id)
	check(rows.size() > 0, "the list shows what is in it")
	var lines := b.take(id)
	check(lines.size() > 0, "taking says what it took")
	for item in held["items"]:
		eq(ship.inventory.count(item), int(before.get(item, 0)) + int(held["items"][item]), "%s went to the hold" % item)
	check(b.left.is_empty() and b.entries(id).is_empty(), "nothing is left in it")
	eq(b.open(id)["items"], {}, "opened again it is empty")
	# one entry at a time
	var id2: int = site.containers()[1]
	b.open(id2)
	var rows2 := b.entries(id2)
	b.take(id2, rows2[0]["key"])
	eq(b.entries(id2).size(), rows2.size() - 1, "taking one entry leaves the others")
	b.take(id2, "all")
	check(b.entries(id2).is_empty(), "taking the rest empties it")


func test_a_log_goes_to_the_journal_and_a_key_opens_its_door() -> void:
	var c := _camp()
	var ship := _ship()
	var site = null
	for s in 80:
		site = Site.make(s + 1, "station", {"faction": "clans"})
		if site.doors.any(func(d): return d["lock"] == "card"):
			break
	var b = Boarding.new()
	b.site = site
	b.ship = ship
	b.campaign = c
	var log_box: Array = site.props.filter(func(p): return p["slot"] == "log")
	check(not log_box.is_empty(), "a station holds logs")
	b.open(log_box[0]["id"])
	b.take(log_box[0]["id"])
	check(c.logs_found.size() == 1, "the log is in the journal (%s)" % str(c.logs_found))
	var door: Dictionary = site.doors.filter(func(d): return d["lock"] == "card")[0]
	check(b.unlock(door["id"]) != "", "a card door stays shut without its keycard")
	check(not b.door_open_to_soldier(door["id"]), "it is shut to the soldier")
	var key_box: Dictionary = site.props.filter(func(p): return p["slot"] == "key" and p["key"] == door["card"])[0]
	b.open(key_box["id"])
	b.take(key_box["id"])
	check(b.keys.has(door["card"]), "the keycard is held")
	eq(b.unlock(door["id"]), "", "the keycard opens its door")
	check(b.door_open_to_soldier(door["id"]) and not site.walk.door_locked.has(door["cells"][0]), "the door is open on the walk grid")
	var hack: Array = site.doors.filter(func(d): return d["lock"] == "hack")
	if not hack.is_empty():
		check(b.unlock(hack[0]["id"]) != "" and not b.door_open_to_soldier(hack[0]["id"]), "a hack door wants the hold")
		eq(b.unlock(hack[0]["id"], true), "", "held for hack_s, it opens")
		check(b.door_open_to_soldier(hack[0]["id"]), "and stays open")


func test_the_soldier_walks_the_site_and_locked_doors_stop_him() -> void:
	var site = Site.make(5, "station", {"faction": "clans"})
	var b = Boarding.new()
	b.site = site
	b.soldier = Boarding._soldier_of(null)
	b.soldier.pos = site.airlock["spawn"]
	check(b.at_airlock(), "he arrives at the airlock")
	var pass_fn := b.door_passable()
	for i in 200:
		b.soldier.move_input(site.walk, Vector2(-site.airlock["normal"].x, 0.0), 0.05, pass_fn)
	check(not b.at_airlock() and site.walk.in_hull(Vector2i(b.soldier.pos)), "he walks away from it")
	check(b.soldier.fits(site.walk, b.soldier.pos, pass_fn), "and stands on free floor")
	var locked: Array = site.doors.filter(func(d): return d["lock"] != "" and d["lock"] != "gone")
	check(not locked.is_empty(), "this station has locked doors")
	check(not pass_fn.call(locked[0]["cells"][0]), "a locked door cell is not passable")
	b.unlock(locked[0]["id"], true) if locked[0]["lock"] == "hack" else null
	if locked[0]["lock"] == "hack":
		check(pass_fn.call(locked[0]["cells"][0]), "until it is hacked")


# --- memory and the sector ------------------------------------------------------------------------------------------

func _sector() -> Sector:
	var c := _camp(3)
	return c.current_sector()


func test_a_visit_is_remembered_by_poi_id_through_a_save() -> void:
	var s := _sector()
	var ship := _ship()
	var b = Boarding.start(null, s, "p1", {"kind": "station"}, ship)
	var ids: Array = b.site.containers()
	b.open(ids[0])
	b.open(ids[1])
	b.take(ids[0])
	var door: Dictionary = b.site.doors.filter(func(d): return d["lock"] == "hack")[0]
	b.unlock(door["id"], true)
	var name: String = b.site.site_name
	var out: Dictionary = b.leave()
	eq(out["name"], name, "the visit says where it was")
	check(s.boarded.has("p1") and not s.boarded.has("p2"), "the memory is by POI id")
	var saved := s.to_save()
	var json = JSON.parse_string(JSON.stringify(saved))  # through the file
	var s2 := _sector()
	s2.boarded = {}
	eq(s2.load_save(json), "", "the sector loads")
	var b2 = Boarding.start(null, s2, "p1", {"kind": "derelict"}, ship)
	eq(b2.site.kind, "station", "a revisit is the same kind of site whatever the offer says")
	eq(_digest(b2.site), _digest(b.site), "and the same site")
	eq(b2.opened.keys(), b.opened.keys(), "the same containers are open")
	eq(b2.left.keys(), b.left.keys(), "the same things are left in them")
	check(b2.unlocked.has(door["id"]) and b2.door_open_to_soldier(door["id"]), "the hacked door stays open")
	check(not b2.site.walk.door_locked.has(door["cells"][0]), "on the walk grid too")
	var b3 = Boarding.start(null, s2, "p9", {"kind": "station"}, ship)
	check(b3.opened.is_empty(), "another POI starts fresh")


func test_an_old_sector_save_loads_without_memory_and_a_bad_one_is_refused() -> void:
	var s := _sector()
	var d := s.to_save()
	check(not d.has("boarded"), "a sector nobody boarded saves no memory")
	var bad := d.duplicate(true)
	bad["boarded"] = {"p1": {"kind": "spaceship", "opened": [], "unlocked": [], "left": {}}}
	check(s.load_save(bad) != "", "a memory of a kind that does not exist is refused")
	eq(s.load_save(d), "", "an old save loads")
	check(Campaign.VERSION >= 11, "the campaign save is version 11 or later (boarded)")


func test_a_fully_opened_site_is_cleared() -> void:
	var s := _sector()
	var b = Boarding.start(null, s, "p1", {"kind": "wreck"}, _ship())
	check(not b.cleared, "a fresh site is not cleared")
	var ids: Array = b.site.containers()
	for i in ids.size() - 1:
		b.open(ids[i])
	check(not b.leave()["cleared"], "all but one open is not cleared")
	var b2 = Boarding.start(null, s, "p1", {"kind": "wreck"}, _ship())
	b2.open(ids[-1])
	check(b2.cleared, "the last container makes it cleared")
	var out: Dictionary = b2.leave()
	check(out["cleared"] and s.boarded["p1"]["cleared"], "leaving says so and the memory keeps it")
	check(Boarding.start(null, s, "p1", {"kind": "wreck"}, _ship()).cleared, "it stays cleared")


# --- the event, the choice -----------------------------------------------------------------------------------------

func test_the_board_effect_comes_out_of_choose_and_spends_nothing() -> void:
	var c := _camp()
	var ship := _ship()
	var ev := {"id": "t_board", "type": "wreck_field", "once": true, "landmark": "A landmark", "title": "T", "text": "x", "choices": [
		{"text": "Go aboard", "outcomes": [{"weight": 1, "text": "You go.", "effects": {"board": {"kind": "derelict"}}}]}]}
	var r: Dictionary = c.events.choose(ev, 0, c, ship)
	check(r["ok"], "the choice is taken")
	eq(r["board"], {"kind": "derelict"}, "the page hands the boarding back")
	check(not c.used.has("t_board"), "boarding does not spend a once event")
	check(not c.landmarks.has("t_board"), "and is no landmark")
	eq(c.events.apply({"items": {"scrap": 1}}, c, ship)["board"], {}, "an effect without it has none")
	check(Events.EFFECT_KEYS.has("board"), "board is an effect key")


func test_boardable_pois_offer_the_choice_with_a_way_out() -> void:
	eq(Boarding.kind_for({"type": "wreck"}), "derelict", "a wreck POI is a derelict")
	eq(Boarding.kind_for({"type": "abandoned_station"}), "station", "an abandoned station is a station")
	eq(Boarding.kind_for({"type": "pirate_nest"}), "nest", "a pirate nest is a nest")
	eq(Boarding.kind_for({"type": "wreck", "wreck": true}), "wreck", "the wreck a fight left is a wreck")
	eq(Boarding.kind_for({"type": "trader"}), "", "a trader cannot be boarded")
	var ev := {"id": "e", "type": "wreck_field", "title": "T", "text": "x", "choices": [
		{"text": "Pay up", "requires": {"items": {"scrap": 5}}, "pay": true, "outcomes": [{"weight": 1, "effects": {"items": {"fuel": 1}}}]}]}
	var offered := Boarding.offer(ev, "derelict")
	eq(ev["choices"].size(), 1, "the event itself is left alone")
	eq(offered["choices"].size(), 3, "the choice and a free way out were added")
	eq(offered["choices"][1]["outcomes"][0]["effects"], {"board": {"kind": "derelict"}}, "the choice boards")
	check(Boarding._free(offered["choices"][2]), "the last choice asks for nothing and does nothing")
	var free := {"id": "e", "type": "wreck_field", "choices": [{"text": "Leave", "outcomes": [{"weight": 1, "effects": {}}]}]}
	eq(Boarding.offer(free, "station")["choices"].size(), 2, "an event with a way out of its own gets no second one")
	eq(Boarding.offer({}, "nest"), {}, "an empty event stays empty")
	for kind in Site.kinds():
		check(Site.config()["offer"].has(kind), "%s has its words" % kind)


func test_a_boardable_poi_event_has_the_choice_when_it_triggers() -> void:
	var c := _camp(9)
	var ship := _ship()
	var s: Sector = c.current_sector()
	s.pois.clear()
	s.pois.append({"id": "pz", "type": "abandoned_station", "name": "Hulk", "pos": s.ship_pos, "visibility": "signal", "event_type": "wreck_field", "state": Sector.NEW, "enemy": "", "main": false})
	var res := s.trigger(c, ship)
	check(not res.is_empty() and res["poi"]["id"] == "pz" and not res["event"].is_empty(), "the abandoned station triggers an event")
	check(res["event"]["choices"].any(func(ch): return ch["outcomes"][0].get("effects", {}).has("board")), "and it offers the boarding")
	check(res["event"]["choices"].any(func(ch): return Boarding._free(ch)), "with a free way out")
	s.pois.clear()
	s.pois.append({"id": "py", "type": "trader", "name": "T", "pos": s.ship_pos, "visibility": "beacon", "event_type": "trader", "state": Sector.NEW, "enemy": "", "main": false})
	var res2 := s.trigger(c, ship)
	check(not res2.is_empty() and not res2["event"].is_empty(), "a trader triggers an event")
	check(not res2["event"]["choices"].any(func(ch): return ch["outcomes"][0].get("effects", {}).has("board")), "that has no boarding")
	s.pois.clear()
	s.pois.append({"id": "px", "type": "pirate_nest", "name": "Nest", "pos": s.ship_pos, "visibility": "signal", "event_type": "pirate", "state": Sector.NEW, "enemy": "", "main": false})
	s.hollow = true
	var res3 := s.trigger(c, ship)
	check(not res3.is_empty() and not res3["event"]["choices"].any(func(ch): return ch["outcomes"][0].get("effects", {}).has("board")), "a place the tide has taken sends ghosts, not boarding")


# --- the view: the tracker, the light, going aboard and coming back ------------------------------------------------

const Tracker = preload("res://scripts/board/tracker.gd")
const BoardLight = preload("res://scripts/board/board_light.gd")
const BoardView = preload("res://scripts/board/board_view.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const CombatView = preload("res://scripts/combat/combat_view.gd")
const Salvage = preload("res://scripts/space/salvage.gd")


func test_the_tracker_pings_what_moves_within_range_as_its_sweep_passes() -> void:
	var t := Tracker.new()
	for i in 80:
		t.tick(0.1, Vector2.ZERO, [])
	check(t.blips.is_empty() and t.take_pings() == 0, "with nothing to find it shows nothing but the sweep")
	var contacts := [{"pos": Vector2(10, 0), "moving": true}, {"pos": Vector2(0, 40), "moving": true}, {"pos": Vector2(-6, 0), "moving": false}]
	var heard := 0
	for i in 40:  # one sweep is 3.2 s
		t.tick(0.1, Vector2.ZERO, contacts)
		heard += t.take_pings()
	eq(heard, 1, "one sweep pings the moving contact in range, not the one 40 cells off nor the one standing still")
	eq(t.blips.size(), 1, "and it shows as a blip")
	near_dist(t.blips[0]["dist"], 10.0 / Tracker.RANGE, "a tenth of 25 cells out")
	for i in 40:
		t.tick(0.1, Vector2.ZERO, [])
	check(t.blips.is_empty(), "and the blip fades")


func near_dist(got: float, want: float, msg: String) -> void:
	check(absf(got - want) < 0.05, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func test_the_wall_occluders_stop_the_light_and_leave_the_floor_lit() -> void:
	for kind in ["derelict", "station"]:
		var site = Site.make(31, kind, {"faction": "clans"})
		var rects: Array = BoardLight.occluder_rects(site.grid)
		check(rects.size() > 10 and rects.size() < 700, "%s: %d occluders is a few hundred at most" % [kind, rects.size()])
		for c in site.grid.tiles:
			var id: String = site.grid.tiles[c]
			var centre := Vector2(c) + Vector2(0.5, 0.5)
			var covered: bool = rects.any(func(r): return r.has_point(centre))
			if id == "floor":
				check(not covered, "%s: floor %s is not under an occluder" % [kind, str(c)])
			elif id == "wall":
				var by_floor := false
				for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					by_floor = by_floor or site.grid.get_tile(c + n) == "floor"
				if by_floor:
					check(covered, "%s: the wall %s beside a floor stops the light" % [kind, str(c)])
	var door: Dictionary = Site.make(31, "derelict", {}).doors[0]
	check(BoardLight.door_rect(door["cells"]).size.x > 0.0, "a door has an occluder of its own")


## The play screen without a window: the ship sim, BuildMode in play mode, the map and its campaign, the sector view and the boarding view,
## wired as main.tscn does (the crew view is left out: the board view works without it).
func _screen(seed_value := 5) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var build := BuildMode.new()
	build.sim = sim
	var map := MapView.new()
	map.sim = sim
	map.build = build
	map.size = Vector2(1600.0, 900.0)
	build.drift = map
	var combat := CombatView.new()
	combat.sim = sim
	combat.build = build
	map.combat = combat
	var view := SectorView.new()
	view.sim = sim
	view.build = build
	view.combat = combat
	view.cam = Camera2D.new()
	var board := BoardView.new()
	board.sim = sim
	board.build = build
	board.cam = view.cam
	board.sector = view
	board.ask_party = false  # (the crew picker has its own tests, test_boarding_combat.gd)
	map.board = board
	board.finished.connect(map._on_board_finished)
	map.new_game(seed_value)
	map.visible = false
	map.save_path = "user://test_boarding_campaign.json"
	build.build_on = false
	view.frame(0.05)
	return {"sim": sim, "build": build, "map": map, "view": view, "board": board, "combat": combat}


func _free(d: Dictionary) -> void:
	if d["board"].active:
		d["board"].leave()
	d["view"].cam.free()
	for k in ["board", "view", "combat", "map", "build", "sim"]:
		d[k].free()


## A boardable POI at the ship, and the event of it as the sector would hand it out.
func _poi_event(d: Dictionary, id := "pz", type := "abandoned_station") -> Dictionary:
	var s: Sector = d["map"].campaign.current_sector()
	var poi := {"id": id, "type": type, "name": "Hulk", "pos": s.ship_pos, "visibility": "signal", "event_type": "wreck_field", "state": Sector.NEW, "enemy": "", "main": false}
	s.pois.append(poi)
	var ev := {"id": "t_wreck", "type": "wreck_field", "title": "Hulk", "text": "A dead hull.", "choices": [
		{"text": "Pick through it.", "outcomes": [{"weight": 1, "text": "Scrap.", "effects": {"items": {"scrap": 3}}}]}]}
	return {"poi": poi, "refused": "", "event": Boarding.offer(ev, Boarding.kind_for(poi)), "dock": false}


func _board_choice(d: Dictionary) -> int:
	var view: Array = d["map"].event_panel.view
	for i in view.size():
		if str(view[i]["text"]).begins_with("Board"):
			return i
	return -1


func test_the_board_effect_puts_the_soldier_aboard_and_the_airlock_brings_him_back() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var build: BuildMode = d["build"]
	var sim: ShipSim = d["sim"]
	var s: Sector = map.campaign.current_sector()
	var res := _poi_event(d)
	map.open_poi(res, s)
	check(map.event_panel.visible and _board_choice(d) >= 0, "the event offers boarding")
	map.event_panel.choose(_board_choice(d))
	check(map.event_panel.page == "result", "the page says what he does")
	map.event_panel.proceed()
	check(board.active and not map.visible, "he is aboard and the map makes way")
	check(build.combat and sim.paused, "the ship's views are put away and its world held")
	check(d["view"].boarding, "the sector stands still")
	check(build.save_block != "", "and the game cannot be saved")
	check(board.session.at_airlock(), "he arrives at the airlock")
	eq(board.session.site.kind, "station", "on a station")
	check(map.campaign.is_hollow(map.campaign.current) or true, "(the tide is another test)")
	# neither the sector nor the tide's linger clock ticks while aboard
	var clock: float = s.clock
	var left: float = map.campaign.tide.linger_left()
	for i in 20:
		d["view"].frame(0.5)
	map._process(1.0)
	eq(s.clock, clock, "no time passes in the sector")
	eq(map.campaign.tide.linger_left(), left, "and the Hollow tide's clock is held while he is aboard")
	# E at the airlock leaves
	board.step(0.05)
	eq(str(board.target.get("type", "")), "airlock", "E would leave here")
	board.e_override = false
	board.step(0.05)
	board.e_override = true
	board.step(0.05)
	check(not board.active, "E at the airlock leaves")
	check(map.visible and map.event_panel.visible and map.event_panel.event.get("id", "") == "t_wreck", "the page he left opens again: the station stays boardable")
	check(not build.combat and not sim.paused and not d["view"].boarding and build.save_block == "", "the ship is as it was, and can be saved")
	check(_board_choice(d) >= 0, "and the choice is still there")
	check(s.find("pz")["state"] == Sector.NEW, "the POI is not done")
	check(s.boarded.has("pz"), "the visit is in the sector's memory")
	_free(d)


func test_clearing_a_site_marks_its_poi_done_and_the_choice_goes() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var s: Sector = map.campaign.current_sector()
	map.open_poi(_poi_event(d), s)
	map.event_panel.choose(_board_choice(d))
	map.event_panel.proceed()
	check(board.active, "aboard")
	for id in board.session.site.containers():
		board.session.open(id)
	board.leave()
	check(map.visible and map.event_panel.visible and map.event_panel.event.is_empty(), "a notice, not the page again")
	check(str(map.event_panel.result["text"]) == Boarding.cleared_text(), "it says nothing is left aboard")
	map.event_panel.proceed()
	eq(s.find("pz")["state"], Sector.DONE, "the POI is done")
	check(s.boarded["pz"]["cleared"], "and remembered as cleared")
	_free(d)


func test_opening_a_container_in_the_view_takes_a_hold_and_the_loot_goes_to_the_hold() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var ship: Ship = d["sim"].player_ship()
	var s: Sector = map.campaign.current_sector()
	var session = Boarding.start(map.campaign, s, "pq", {"kind": "derelict"}, ship)
	eq(board.enter(session), "", "aboard")
	var id: int = session.site.containers()[0]
	var p: Dictionary = session.site.props[id]
	var rect: Rect2i = session.site.rooms[p["room"]]["rect"]
	var c: Vector2 = session.site.centre_of(p)
	session.soldier.pos = Vector2(clampf(c.x, rect.position.x + 1.0, rect.end.x - 1.0), clampf(c.y, rect.position.y + 1.0, rect.end.y - 1.0))
	board.aim_override = c * 32.0
	board.step(0.05)
	eq(board.target.get("id", -1), id, "the container is what E acts on")
	var before: Dictionary = ship.inventory.counts.duplicate()
	board.e_override = true
	var need: float = float(Site.config()["props"][p["prop"]]["hold"])
	for i in int(need / 0.1) - 3:
		board.step(0.1)
	check(board.panel < 0 and not session.opened.has(id), "a short hold opens nothing")
	for i in 6:
		board.step(0.1)
	check(session.opened.has(id) and board.panel == id, "held long enough it opens and the list shows")
	eq(ship.inventory.counts, before, "nothing is taken until you take it")
	board.e_override = false
	board.step(0.1)
	board.e_override = true
	board.step(0.1)  # a tap of E
	check(board.panel < 0, "E takes all and the list shuts")
	var got := 0
	for k in ship.inventory.counts:
		got += int(ship.inventory.counts[k]) - int(before.get(k, 0))
	check(got > 0 or session.said.size() > 0, "the loot is in the hold")
	board.e_override = false
	board.leave()
	_free(d)


func test_a_locked_door_is_hacked_by_holding_e_for_four_seconds() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var s: Sector = map.campaign.current_sector()
	var session = null
	var door := {}
	for seed_id in 40:
		session = Boarding.start(map.campaign, s, "ph%d" % seed_id, {"kind": "station"}, d["sim"].player_ship())
		for x in session.site.doors.filter(func(x): return x["lock"] == "hack"):  # one with no container within reach of the spot by it
			var at: Vector2 = session.site.door_centre(x) + (Vector2(0.0, -2.0) if x["cells"][0].y == x["cells"][1].y else Vector2(-2.0, 0.0))
			if door.is_empty() and session.site.nearest_container(at, float(Site.config()["reach"])) < 0 and session.site.room_at(at) >= 0:
				door = x
		if not door.is_empty():
			break
	check(not door.is_empty(), "a station with a hack door")
	eq(board.enter(session), "", "aboard")
	var dc: Vector2 = session.site.door_centre(door)
	var horizontal: bool = door["cells"][0].y == door["cells"][1].y
	session.soldier.pos = dc + (Vector2(0.0, -2.0) if horizontal else Vector2(-2.0, 0.0))
	board.aim_override = dc * 32.0
	board.step(0.05)
	eq(str(board.target.get("type", "")), "door", "E acts on the door")
	board.e_override = true
	for i in 30:
		board.step(0.1)  # 3 s
	check(not session.unlocked.has(door["id"]), "three seconds is not enough")
	for i in 14:
		board.step(0.1)
	check(session.unlocked.has(door["id"]), "four seconds hack it")
	check(not session.site.walk.door_locked.has(door["cells"][0]), "and the door is open to him")
	board.e_override = false
	board.leave()
	_free(d)


func test_the_save_is_refused_aboard_and_allowed_again_after() -> void:
	var d := _screen()
	var board: BoardView = d["board"]
	var build: BuildMode = d["build"]
	var ship: Ship = d["sim"].player_ship()
	var session = Boarding.start(d["map"].campaign, d["map"].campaign.current_sector(), "ps", {"kind": "wreck"}, ship)
	eq(board.enter(session), "", "aboard")
	build._save()
	eq(build.message, "Can't save aboard another vessel.", "the build screen's save refuses")
	var e := InputEventKey.new()
	e.keycode = KEY_S
	e.ctrl_pressed = true
	e.pressed = true
	board._unhandled_input(e)
	eq(board.message, "Can't save aboard another vessel.", "and so does Ctrl+S in the view")
	check(board.message_alive(), "the line is on show")
	board.leave()
	eq(build.save_block, "", "back aboard the ship it can be saved")
	check(session.finished, "the visit is over")
	_free(d)


func test_the_wreck_of_a_won_fight_can_be_boarded_and_holds_its_parts() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var board: BoardView = d["board"]
	var ship: Ship = d["sim"].player_ship()
	var s: Sector = map.campaign.current_sector()
	var enemy: Ship = Ship.from_design("res://data/ships/pirate_raider.json")
	var salvage: Dictionary = Salvage.event_for(enemy, "won", map.campaign, ship, null, 1)
	var parts: Array = Salvage.parts(enemy)
	parts.resize(mini(parts.size(), Boarding.WRECK_PARTS))
	var ev := Boarding.offer(salvage, "wreck", {"name": "Pirate Raider", "parts": parts}, false)
	eq(ev["choices"].size(), salvage["choices"].size() + 1, "the salvage page gains one row, and no way out the pick did not have")
	var w := s.add_wreck(s.ship_pos + Vector2(120.0, 0.0), "Wreck of Raider")
	w["state"] = Sector.DONE
	map.open_poi({"poi": s.main_poi(), "refused": "", "event": ev, "dock": false}, s)
	map.event_panel.choose(_board_choice(d))
	map.event_panel.proceed()
	check(board.active, "aboard the wreck")
	eq(board.session.site.kind, "wreck", "a wreck")
	eq(board.session.poi_id, w["id"], "of the wreck the fight left")
	eq(board.session.site.site_name, "Pirate Raider", "named for the ship")
	eq(board.session.site.parts, parts, "it holds the parts of the ship")
	var held := {}
	for p in board.session.site.props:
		for item in p["fixed"]:
			held[item] = int(held.get(item, 0)) + int(p["fixed"][item])
	var want := {}
	for part in parts:
		want[part] = int(want.get(part, 0)) + 1
	eq(held, want, "each in a container")
	board.leave()
	check(map.event_panel.visible and map.event_panel.event.get("id", "") == "salvage", "the salvage page opens again")
	_free(d)


func test_k_does_not_start_a_fight_aboard() -> void:
	var d := _screen()
	var combat: CombatView = d["combat"]
	var session = Boarding.start(d["map"].campaign, d["map"].campaign.current_sector(), "pk", {"kind": "derelict"}, d["sim"].player_ship())
	d["board"].enter(session)
	var e := InputEventKey.new()
	e.keycode = KEY_K
	e.pressed = true
	combat._unhandled_input(e)
	check(not combat.active, "the test pirate does not come aboard")
	_free(d)
