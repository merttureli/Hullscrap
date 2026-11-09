extends "res://tests/base_test.gd"
## The tide's teeth in sector space (docs/MECHANICS_REVIEW.md F1 and P1, scripts/space/sector.gd `hollow`, the `hollow` block of
## data/sectors.json `ambient`): in a Hollow sector a ghost comes for the ship every 60 s and always closes in, one comes at once
## when the place falls with the ship in it (and only once), the debris spawns at 0.3 x, the flag is set by the campaign (on
## arrival, on a load, when lingering, a wait or a jump takes the place) and survives a save, a ghost contact runs a hollow event
## and ghost fights, every other POI of a Hollow sector (but a station or store) runs a hollow event too, and the sector view
## tells the player, thins the debris field and keeps a red line up while the place is Hollow.

const Campaign = preload("res://scripts/space/campaign.gd")
const Sector = preload("res://scripts/space/sector.gd")
const Radar = preload("res://scripts/space/radar.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Events = preload("res://scripts/space/events.gd")
const Content = preload("res://scripts/data/content.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const SectorView = preload("res://scripts/view/sector_view.gd")
const DebrisView = preload("res://scripts/view/debris_view.gd")
const TideHud = preload("res://scripts/ui/tide_hud.gd")
const SectorViewTest = preload("res://tests/test_sector_view.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const VISUAL := 1500.0  ## px: the radar's reach with no ship (data/sectors.json radar.visual)


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	s.refresh()
	return s


func _node(type: String, i := 0) -> Dictionary:
	return {"id": "t%d" % i, "name": "", "type": type, "place": ""}


## data/sectors.json with every ordinary ambient roll certain, so the old rolls are easy to count.
func _busy() -> Dictionary:
	var cfg: Dictionary = Sector.config().duplicate(true)
	cfg["ambient"]["chance"] = 1.0
	return cfg


## Is `ct` flying at the point `at` (its velocity points at it)?
func _closing_on(ct: Dictionary, at: Vector2) -> bool:
	return (ct["vel"].normalized() - (at - ct["pos"]).normalized()).length() < 1e-4


func _jump(c: Campaign, to: String, ship) -> Dictionary:
	var r: Dictionary = c.start_jump(to, ship, false, false)
	if not r["ok"]:
		return {"ok": false, "why": r["why"], "notes": []}
	c.tick_jump(c.spool_time(), false, ship)
	return c.last_jump


## The id of the place the tide will take on its next step (not a station, the exit or a gate), with the tide set one step short of it.
func _edge_node(c: Campaign) -> String:
	var best := ""
	var best_k := 1000
	for n in c.drift.nodes:
		var id := str(n["id"])
		var k := c.tide.jumps_until(id)
		if k >= 1 and k < best_k and str(n["type"]) != "gate":
			best = id
			best_k = k
	check(best != "", "this map has a place the tide can still take")
	c.tide.steps += best_k - 1
	eq(c.tide.jumps_until(best), 1, "one step short of taking it")
	return best


## A campaign with the ship in the place that is one step from falling, as if it had just arrived (the flag is quiet).
func _on_the_edge(seed_value := 9) -> Dictionary:
	var ship := _ship()
	var c := Campaign.new(seed_value)
	var id := _edge_node(c)
	c.current = id
	c.visited[id] = true
	c._enter(id, ship)
	return {"c": c, "ship": ship, "id": id, "s": c.current_sector()}


func _ghosts(s) -> Array:
	return s.ambient.filter(func(a): return a["event_type"] == "hollow")


# --- the rolls in a Hollow sector ---------------------------------------------------------------------------

func test_in_a_hollow_sector_a_ghost_comes_every_60_seconds_and_closes_in() -> void:
	var s = Sector.generate(5, _node("empty", 1), "clans")
	s.set_hollow(true)
	eq(s.tick(59.0, null), [], "nothing before 60 s")
	var made: Array = s.tick(1.0, null)
	eq(made.size(), 1, "at 60 s a ghost shows")
	var g: Dictionary = made[0]
	eq([g["event_type"], g["type"], g["visibility"]], ["hollow", "unknown", "signal"], "a `hollow` event on an unknown signal contact")
	near(g["pos"].distance_to(s.ship_pos), VISUAL * 0.9, "at the radar's edge: with no radar the visual range x 0.9", 0.5)
	check(s.contains(g["pos"]), "inside the sector")
	check(_closing_on(g, s.ship_pos), "and flying straight at the ship")
	check(s.all_pois().has(g), "one of the sector's contacts")
	for i in 12:  # every minute after, always one, and always closing in
		s.ambient.clear()
		var m: Array = s.tick(60.0, null)
		eq(m.size(), 1, "minute %d: a ghost" % (i + 2))
		if not m.is_empty():
			check(m[0]["event_type"] == "hollow" and _closing_on(m[0], s.ship_pos), "minute %d: a hollow contact, closing in" % (i + 2))


func test_ghosts_count_toward_the_cap_and_the_ship_that_lingers_meets_them() -> void:
	var cfg: Dictionary = Sector.config().duplicate(true)
	cfg["ambient"]["hollow"]["every"] = 15  # a ghost that has passed the ship leaves (3 radar reaches), so they must come faster to fill the sky
	var ship := _ship()
	var s = Sector.generate(5, _node("empty", 1), "clans", cfg)
	s.set_hollow(true)
	var cap := int(s.cfg["ambient"]["max"])
	var most := 0
	for i in 600:
		s.tick(1.0, ship)
		most = maxi(most, s.ambient.size())
		check(s.ambient.size() <= cap, "at most %d about at once" % cap)
	eq(most, cap, "and the cap is reached: the ghosts keep coming")
	check(s.ambient.all(func(a): return a["event_type"] == "hollow"), "all ghosts")


func test_outside_a_hollow_sector_the_old_rolls_are_unchanged() -> void:
	var node := _node("empty", 3)
	var s = Sector.generate(5, node, "clans", _busy())
	eq(s.tick(60.0, null), [], "nothing at 60 s: the roll comes every 90 s")
	var made: Array = s.tick(30.0, null)
	eq(made.size(), 1, "at 90 s a roll (the chance is 1 here)")
	check(["trader", "patrol", "pirate"].has(made[0]["event_type"]), "a trader, a patrol or a pirate (%s)" % made[0]["event_type"])
	var twin = Sector.generate(5, node, "clans", _busy())
	twin.set_hollow(false)
	twin.tick(90.0, null)
	eq([twin.ambient[0]["pos"], twin.ambient[0]["event_type"], twin.ambient[0]["vel"]], [made[0]["pos"], made[0]["event_type"], made[0]["vel"]], "the same seeded roll when told the place is free")
	var passing := 0
	var kinds := {}
	var t = Sector.generate(2, node, "boneyard", _busy())
	for i in 60:
		t.ambient.clear()
		for ct in t.tick(90.0, null):
			kinds[ct["event_type"]] = true
			passing += int(not _closing_on(ct, t.ship_pos))
	check(passing > 0, "some pass by (approach 0.6): %d of 60" % passing)
	check(not kinds.has("hollow"), "and none is a ghost (%s)" % str(kinds.keys()))
	var back = Sector.generate(5, node, "clans", _busy())
	back.set_hollow(true)
	back.set_hollow(false)
	eq(back.tick(60.0, null), [], "a place that is free again rolls every 90 s once more")
	eq(back.tick(30.0, null).size(), 1, "at 90 s")


# --- the place falls with the ship in it ------------------------------------------------------------------

func test_the_current_place_falling_hollow_spawns_one_ghost_at_once_and_only_once() -> void:
	var ship := _ship()  # a ghost that has passed the ship leaves 3 radar reaches (9,000 px) away: this ship's radar sees 3,000
	var s = Sector.generate(5, _node("empty", 1), "clans")
	s.tick(50.0, ship)  # most of the way to an ordinary roll
	s.set_hollow(true, true)
	var made: Array = s.tick(0.1, ship)
	eq(made.size(), 1, "one contact at the next tick")
	eq(made[0]["event_type"], "hollow", "a ghost")
	check(_closing_on(made[0], s.ship_pos), "closing in")
	s.set_hollow(true, true)
	s.set_hollow(true)
	eq(s.tick(0.1, ship), [], "told again, it brings no second one")
	eq(_ghosts(s).size(), 1, "only the one")
	eq(s.tick(58.0, ship), [], "the roll's clock started again at the fall: nothing for the next minute")
	eq(s.tick(2.0, ship).size(), 1, "then the 60 s ghosts follow")
	eq(_ghosts(s).size(), 2, "two now")


func test_a_place_that_is_hollow_on_arrival_brings_no_ghost_at_once() -> void:
	var s = Sector.generate(5, _node("empty", 1), "clans")
	s.set_hollow(true)  # an arrival, or a load: quiet
	eq(s.tick(1.0, null), [], "nothing at once")
	eq(s.tick(58.0, null), [], "nor before the minute")
	eq(s.tick(1.0, null).size(), 1, "the first ghost is at 60 s")
	var left = Sector.generate(5, _node("empty", 1), "clans")
	left.set_hollow(true, true)
	left.enter()  # the ship jumps away before the next tick
	left.set_hollow(true)
	eq(left.tick(1.0, null), [], "a ghost that was due is dropped with the old visit")


func test_the_first_ghost_comes_even_when_the_sky_is_full() -> void:
	var ship := _ship()
	var s = Sector.generate(5, _node("empty", 1), "clans")
	for k in 3:
		s.ambient.append({"id": "x%d" % k, "type": "unknown", "name": "Unknown ship", "pos": s.ship_pos + Vector2(5000.0, 0.0), "visibility": "signal",
			"event_type": "trader", "state": Sector.NEW, "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 1000.0})
	eq(s.ambient.size(), 3, "three ordinary contacts about")
	s.set_hollow(true, true)
	var made: Array = s.tick(0.1, ship)
	eq(made.size(), 1, "the tide is here: its ghost comes anyway")
	eq(s.ambient.size(), 4, "over the cap")
	eq(s.tick(60.0, ship), [], "but the minute rolls still obey the cap")


# --- the campaign sets the flag ---------------------------------------------------------------------------

func test_lingering_a_wait_and_a_jump_that_take_the_current_place_bring_a_ghost_at_once() -> void:
	# lingering
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	check(not s.hollow and not c.is_hollow(e["id"]), "the place is free on arrival")
	eq(s.tick(0.1, e["ship"]), [], "no ghost yet")
	var lines := c.linger(c.tide.linger_s)
	check(lines.has("The Hollow takes 1 more place."), "the tide takes the place: " + str(lines))
	check(c.is_hollow(e["id"]) and s.hollow, "the sector knows")
	var made: Array = s.tick(0.1, e["ship"])
	eq(made.size(), 1, "one ghost at once")
	near(made[0]["pos"].distance_to(s.ship_pos), 3000.0 * 0.9, "at the edge of the helm's radar", 0.5)
	for i in 5:
		c.linger(1.0)
	eq(s.tick(1.0, e["ship"]), [], "lingering on in a Hollow place brings none at once")
	eq(_ghosts(s).size(), 1, "still only the one")
	# a wait
	var w := _on_the_edge()
	w["ship"].inventory.counts.erase("fuel")
	check(w["c"].wait(w["ship"])["ok"], "a wait")
	check(w["s"].hollow, "the wait took the place")
	eq(w["s"].tick(0.1, w["ship"]).size(), 1, "one ghost")
	check(w["c"].wait(w["ship"])["ok"], "another wait")
	eq(w["s"].tick(0.1, w["ship"]), [], "the second brings none")
	# a jump that steps the tide over the place it arrives at
	var ship := _ship()
	var j := Campaign.new(8)
	ship.inventory.add("fuel", 50)
	var to := ""
	for o in j.neighbours(j.current):
		var k := j.tide.jumps_until(o)
		if k >= 1 and j.node(o)["type"] != "gate":
			to = o
			j.tide.steps += k - 1
			break
	check(to != "", "a place next to the start the tide can take")
	var r := _jump(j, to, ship)
	check(r["ok"], "the jump: " + str(r["why"]))
	check(j.is_hollow(to) and j.current_sector().hollow, "it arrives as the tide steps over it")
	eq(j.current_sector().tick(0.1, ship).size(), 1, "one ghost at once")


func test_a_jump_to_a_place_that_is_hollow_already_flags_it_quietly() -> void:
	var ship := _ship()
	var c := Campaign.new(8)
	ship.inventory.add("fuel", 50)
	var to := ""
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate" and c.tide.jumps_until(o) >= 1:
			to = o
			break
	c.tide.steps += c.tide.jumps_until(to) + 2
	check(c.is_hollow(to), "the tide has the place already")
	check(_jump(c, to, ship)["ok"], "the jump")
	var s = c.current_sector()
	check(s.hollow, "the sector knows on arrival")
	eq(s.tick(1.0, ship), [], "no ghost at once")
	eq(s.tick(59.0, ship).size(), 1, "the first comes at 60 s")
	var other := Campaign.new(8)
	check(not other.current_sector().hollow, "a free place is not flagged")


func test_stations_and_the_exit_never_take_the_flag() -> void:
	var c := Campaign.new(8)
	c.tide.steps = 60
	c.linger(1.0)
	check(not c.is_hollow("rusthold"), "a station holds")
	check(not c.current_sector().hollow, "so its sector is never Hollow, and no ghosts come")


func test_the_flag_survives_a_save_and_a_load() -> void:
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	c.linger(c.tide.linger_s)
	eq(s.tick(0.1, e["ship"]).size(), 1, "a ghost came")
	var text := JSON.stringify(c.to_dict())
	var d := Campaign.new(99)
	eq(d.load_dict(JSON.parse_string(text)), "", "loads")
	var t = d.current_sector()
	check(t.hollow, "the loaded place is Hollow")
	eq(_ghosts(t).size(), 1, "the ghost on the radar was saved with the sector")
	eq(JSON.stringify(d.to_dict()), JSON.stringify(c.to_dict()), "and saves as it was")
	eq(t.tick(0.1, e["ship"]), [], "a load brings no second ghost")
	var free := Campaign.new(12)
	var f := Campaign.new(99)
	eq(f.load_dict(JSON.parse_string(JSON.stringify(free.to_dict()))), "", "a free place loads")
	check(not f.current_sector().hollow, "and stays free")
	# a place the tide took while the save sat there
	var late := _on_the_edge()
	var old := JSON.stringify(late["c"].to_dict())
	late["c"].linger(late["c"].tide.linger_s)
	var g := Campaign.new(99)
	eq(g.load_dict(JSON.parse_string(old)), "", "the older save loads")
	check(not g.current_sector().hollow, "still free in it")
	g.tide.steps = late["c"].tide.steps
	g.linger(0.5)
	check(g.current_sector().hollow, "and the tide takes it afterwards")


# --- the debris -------------------------------------------------------------------------------------------

func test_a_hollow_sectors_debris_spawns_at_03_of_its_density() -> void:
	var s = Sector.generate(4, _node("wreck_field", 1), "clans")
	var base: Dictionary = Content.read(DriftDebris.PATH)
	var calm: Dictionary = s.debris_cfg(base)["spawn"]
	s.set_hollow(true)
	var thin: Dictionary = s.debris_cfg(base)["spawn"]
	near((1.0 / float(thin["every"])) / (1.0 / float(calm["every"])), 0.3, "the spawn rate")
	near(float(thin["max_alive"]) / float(calm["max_alive"]), 0.3, "the cap", 0.02)
	near(float(thin["start_alive"]) / float(calm["start_alive"]), 0.3, "the starting pieces", 0.02)
	eq(float(Sector.config()["ambient"]["hollow"]["debris"]), 0.3, "data/sectors.json says 0.3")
	s.set_hollow(false)
	eq(s.debris_cfg(base)["spawn"], calm, "a free place spawns as before")
	var quiet = Sector.generate(4, _node("empty", 2), "clans")
	quiet.set_hollow(true)
	check(int(quiet.debris_cfg(base)["spawn"]["max_alive"]) >= 8, "the cap never drops under 8 pieces")


func test_rescale_thins_a_running_spawner_and_keeps_its_pieces() -> void:
	var s = Sector.generate(4, _node("wreck_field", 1), "clans")
	var ship := _ship()
	var d: DriftDebris = DriftDebris.for_sector(s, 1)
	d.prewarm(ship)
	var kept := d.pieces.size()
	var every := float(d.cfg["spawn"]["every"])
	var cap := int(d.cfg["spawn"]["max_alive"])
	check(kept > 10, "a wreck field starts with plenty (%d)" % kept)
	s.set_hollow(true)
	d.rescale(s)
	eq(d.pieces.size(), kept, "the pieces already adrift stay")
	near(float(d.cfg["spawn"]["every"]) * 0.3, every, "and it spawns at 0.3 x the rate", 1e-6)
	check(int(d.cfg["spawn"]["max_alive"]) < cap, "under a lower cap")
	var fresh: DriftDebris = DriftDebris.for_sector(s, 1)
	eq(d.cfg["spawn"], fresh.cfg["spawn"], "the same numbers a spawner made for the Hollow place has")


# --- the ghost's event ------------------------------------------------------------------------------------

func test_an_ambient_hollow_contact_runs_a_hollow_event_and_ghost_fights() -> void:
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	c.linger(c.tide.linger_s)
	var g: Dictionary = s.tick(0.1, e["ship"])[0]
	s.ship_pos = g["pos"] + Vector2(300.0, 0.0)
	var r: Dictionary = s.trigger(c, e["ship"])
	eq(r["poi"]["id"], g["id"], "the ghost fires within 800 px")
	eq(r["event"]["type"], "hollow", "a hollow event")
	check(str(r["event"]["id"]).begins_with("hollow_"), "from the tide pack (%s)" % str(r["event"]["id"]))
	check(s.fight_design(c, g["id"], "tier").begins_with("gen:hollow:"), "its fights are generated ghost ships")
	s.resolve(g["id"])
	check(s.find(g["id"]).is_empty(), "met, it is gone")
	# with no hollow events at all it is still a fight, as at an arrival
	var bare := Campaign.new(8, {}, Events.new("res://tests"))
	var id := _edge_node(bare)
	var ship := _ship()
	bare.current = id
	bare._enter(id, ship)
	bare.linger(bare.tide.linger_s)
	var bs = bare.current_sector()
	var ghost: Dictionary = bs.tick(0.1, ship)[0]
	bs.ship_pos = ghost["pos"] + Vector2(300.0, 0.0)
	eq(bs.trigger(bare, ship)["event"].get("id", ""), "hollow_hostile", "the built-in fight")


func test_a_ghost_is_a_hostile_for_red_alert_and_shows_on_the_radar() -> void:
	var e := _on_the_edge()
	var s = e["s"]
	e["c"].linger(e["c"].tide.linger_s)
	var g: Dictionary = s.tick(0.1, e["ship"])[0]
	check(s.hostile_ships().has(g["pos"]), "build mode's red alert counts it")
	var seen := Radar.contacts(s, e["ship"]).filter(func(ct): return ct["poi"]["id"] == g["id"])
	eq(seen.size(), 1, "the radar shows it")
	eq(seen[0]["known_type"], Radar.CONTACT, "as a contact, until it is close")
	var trader := {"id": "a9", "type": "unknown", "name": "Unknown ship", "pos": s.ship_pos + Vector2(100.0, 0.0), "visibility": "signal",
		"event_type": "trader", "state": Sector.NEW, "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 100.0}
	s.ambient.append(trader)
	check(not s.hostile_ships().has(trader["pos"]), "a trader is no hostile")


# --- the other POIs of a Hollow sector --------------------------------------------------------------------

## A POI of type `type` as _event_for sees it: its event type is the one the type always runs (or `event`).
func _poi(type: String, event := "") -> Dictionary:
	var t = Sector.config()["poi_types"][type]
	return {"id": "z_" + type, "type": type, "name": type, "pos": Vector2.ZERO, "visibility": "signal", "state": Sector.NEW, "enemy": "", "main": false,
		"event_type": event if event != "" else (t["event"] if t["event"] is String else "wreck_field")}


func test_every_poi_but_a_station_or_store_runs_a_hollow_event_in_a_hollow_sector() -> void:
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	var free := {}
	for type in Sector.config()["poi_types"]:
		free[type] = str(s._event_for(c, e["ship"], _poi(type))["event"].get("type", ""))
	eq(free["wreck"], "wreck_field", "a free place: a wreck runs its own event")
	eq(free["distress"], "distress", "and a distress call")
	check(free["pirate_nest"] != "hollow" and free["mining_field"] != "hollow", "none is a hollow event")
	c.linger(c.tide.linger_s)
	check(s.hollow, "the place has fallen")
	for type in Sector.config()["poi_types"]:
		var ev: Dictionary = s._event_for(c, e["ship"], _poi(type))["event"]
		if bool(Sector.config()["poi_types"][type].get("repeat", false)):
			check(str(ev.get("type", "")) != "hollow", "%s holds: it keeps its own event (%s)" % [type, str(ev.get("type", ""))])
		else:
			eq(str(ev.get("type", "")), "hollow", "%s runs a hollow event" % type)
	var concord: Dictionary = s._event_for(c, e["ship"], _poi("concord_checkpoint"))
	eq(concord["event"]["type"], "hollow", "even a Concord checkpoint: its patrol is a ghost")
	var store: Dictionary = s._event_for(c, e["ship"], _poi("store", "trader"))
	eq(str(store["event"].get("type", "")), "trader", "a store still trades")


func test_a_wreck_and_a_passing_ship_in_a_hollow_sector_trigger_hollow_events() -> void:
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	c.linger(c.tide.linger_s)
	var w: Dictionary = s.add_wreck(s.ship_pos + Vector2(300.0, 0.0))
	var r: Dictionary = s.trigger(c, e["ship"])
	eq(r["poi"]["id"], w["id"], "the wreck fires")
	eq(r["event"]["type"], "hollow", "and it is a hollow event, not a wreck_field one")
	s.resolve(w["id"])
	var trader := {"id": "a9", "type": "unknown", "name": "Unknown ship", "pos": s.ship_pos + Vector2(200.0, 0.0), "visibility": "signal",
		"event_type": "trader", "state": Sector.NEW, "enemy": "", "main": false, "ambient": true, "vel": Vector2.ZERO, "ttl": 100.0}
	s.ambient.append(trader)
	eq(s.trigger(c, e["ship"])["event"]["type"], "hollow", "a trader that was already about is a ghost now")


func test_a_pois_own_enemy_gives_way_to_ghosts_in_a_hollow_sector() -> void:
	var e := _on_the_edge()
	var c: Campaign = e["c"]
	var s = e["s"]
	var poi := _poi("pirate_nest")
	poi["enemy"] = "pirate_raider"
	s.pois.append(poi)
	eq(s.fight_design(c, poi["id"], "tier"), "res://data/ships/pirate_raider.json", "a free place: the POI's own enemy")
	c.linger(c.tide.linger_s)
	check(s.fight_design(c, poi["id"], "tier").begins_with("gen:hollow:"), "a Hollow one: ghost ships")
	eq(s.fight_design(c, poi["id"], "res://data/ships/pirate_raider.json"), "res://data/ships/pirate_raider.json", "a design a fight names outright is still that design")


# --- the view ---------------------------------------------------------------------------------------------

func test_the_hud_tells_when_the_tide_takes_the_place_and_not_on_arrival() -> void:
	var h = SectorViewTest.new()
	var d: Dictionary = h._screen(8)
	var view = d["view"]
	var c: Campaign = d["map"].campaign
	var ship = d["sim"].player_ship()
	var id := _edge_node(c)
	c.current = id
	c.visited[id] = true
	c._enter(id, ship)
	view.frame(0.05)
	check(view.message != SectorView.FALL_TEXT, "nothing to say on arriving at a free place")
	c.linger(c.tide.linger_s)
	view.frame(0.1)
	eq(view.message, "The tide is here. Something is coming.", "the HUD line when the tide steps over the place")
	eq(SectorView.FALL_TEXT, "The tide is here. Something is coming.", "and that is its text")
	var s = c.current_sector()
	eq(_ghosts(s).size(), 1, "with a ghost on the radar")
	view.message = ""
	view.frame(0.1)
	check(view.message != SectorView.FALL_TEXT, "it is said once")
	h._free(d)
	var arr: Dictionary = h._screen(8)
	var c2: Campaign = arr["map"].campaign
	var id2 := _edge_node(c2)
	c2.tide.steps += 3  # the place is Hollow when the ship arrives
	c2.current = id2
	c2._enter(id2, arr["sim"].player_ship())
	check(c2.is_hollow(id2), "the tide had the place")
	arr["view"].frame(0.1)
	check(arr["view"].message != SectorView.FALL_TEXT, "an arrival in a Hollow place does not say it: the Hollow event does")
	h._free(arr)


func test_the_debris_field_thins_once_when_the_place_falls() -> void:
	var h = SectorViewTest.new()
	var d: Dictionary = h._screen(8)
	var view = d["view"]
	var c: Campaign = d["map"].campaign
	var ship = d["sim"].player_ship()
	var id := _edge_node(c)
	c.current = id
	c.visited[id] = true
	c._enter(id, ship)
	view.frame(0.05)
	var dv := DebrisView.new()
	dv.sim = d["sim"]
	dv.build = d["build"]
	dv.sector = view
	dv.frame(0.1)
	check(dv.debris != null, "debris in the sector")
	var field = dv.debris
	var every := float(dv.debris.cfg["spawn"]["every"])
	var pieces: int = dv.debris.pieces.size()
	check(pieces > 0, "pieces adrift (%d)" % pieces)
	c.linger(c.tide.linger_s)
	view.frame(0.05)
	dv.frame(0.1)
	check(dv.debris == field, "the same field: it is rescaled, not rebuilt")
	near(float(dv.debris.cfg["spawn"]["every"]) * 0.4 * 0.3, every * lerpf(1.0, 0.4, 0.3), "spawning at 0.3 x the rate, on top of the 0.4 x of pressure 1 (it was 0.3 before)", 1e-6)
	check(dv.debris.pieces.size() >= pieces - 2, "the pieces already about stay (%d of %d)" % [dv.debris.pieces.size(), pieces])
	var rescaled: Dictionary = dv.debris.cfg["spawn"].duplicate()
	dv.frame(0.1)
	eq(dv.debris.cfg["spawn"], rescaled, "and once")
	dv.free()
	h._free(d)


func test_the_hollow_place_line_stays_while_the_current_place_is_hollow() -> void:
	var h = SectorViewTest.new()
	var d: Dictionary = h._screen(8)
	var map = d["map"]
	var c: Campaign = map.campaign
	var hud := TideHud.new()
	hud.map = map
	eq(hud.warning(), "", "the first place is free: no warning")
	var id := _edge_node(c)
	c.current = id
	c.visited[id] = true
	c._enter(id, d["sim"].player_ship())
	eq(hud.warning(), "", "a free place one step from falling: none")
	c.linger(c.tide.linger_s)
	eq(hud.warning(), "Hollow place: ghosts every 60 s", "the tide has taken it: the line is up")
	check(hud.line() != "", "next to the tide's clock")
	c.linger(100.0)
	eq(hud.warning(), "Hollow place: ghosts every 60 s", "and it stays")
	d["build"].build_on = true
	eq(hud.warning(), "", "hidden in build mode, like the clock")
	d["build"].build_on = false
	map.visible = true
	eq(hud.warning(), "", "and while the map is open")
	map.visible = false
	c.tide.steps = 99
	eq(hud.line(), "", "once the tide has taken everything the clock is gone")
	eq(hud.warning(), "Hollow place: ghosts every 60 s", "but the place is still Hollow")
	c.cfg = c.cfg.duplicate(true)  # the config is shared by every campaign: change a copy
	c.cfg["instant_jump"] = true
	eq(hud.warning(), "", "with the old instant jump there is no sector and no ghost")
	hud.free()
	h._free(d)
