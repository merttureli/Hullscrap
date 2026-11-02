extends "res://tests/base_test.gd"
## The progression balance pass (Beta 3, track `balance`, docs/audit/progression.md section 12): the Scan pick shared by a salvage and a boarding,
## the fabricator ladder's recipes (start-known, shop blueprints, event blueprints), the debris floor, the fuel numbers, data/progression.json.

const Boarding = preload("res://scripts/board/boarding.gd")
const Campaign = preload("res://scripts/space/campaign.gd")
const Content = preload("res://scripts/data/content.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Events = preload("res://scripts/space/events.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const Loot = preload("res://scripts/board/loot.gd")
const RunStart = preload("res://scripts/space/run_start.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Shops = preload("res://scripts/space/shops.gd")
const Site = preload("res://scripts/board/site.gd")
const Workshop = preload("res://scripts/craft/workshop.gd")

const STARTER := "res://data/ships/starter_courier.json"
## The recipes the fabricator ladder needs (docs/audit/progression.md section 12) and the events that now teach them: event id -> recipe.
const BLUEPRINT_EVENTS := {
	"station_rusthold_scrap_market": "assembly_rig", "station_meridian_shipyard_queue": "assembly_rig", "scrapyard_graft_row_dock": "assembly_rig",
	"trader_pawnbarge": "laser_mk2", "trader_concord_requisitions": "pulse_mk2", "anomaly_frozen_flare": "laser_mk2",
	"lumen_listening_array": "shield_mk2", "concord_survey_buoy": "shield_mk2", "bsite_terminal_still_logged_in": "laser_mk2",
	"bsite_terminal_last_message": "assembly_rig",
}


## A test-room ship with a powered fabricator: level 1, or level 2 with a Robot Arm; `cutter` adds a powered Laser Cutter (the tool) to the room.
func _ship(arm := false, cutter := false) -> Ship:
	var ship := Fixture.room_ship()
	Fixture.put(ship, "reactor_mk1", 10, 10)
	Fixture.put(ship, "fabricator", 15, 10)
	var wires := [Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11), Vector2i(15, 11)]
	if arm or cutter:
		wires.append_array([Vector2i(18, 11), Vector2i(19, 11)])
	if arm:
		Fixture.put(ship, "robot_arm", 19, 10)
	if cutter:
		Fixture.put(ship, "laser_cutter", 19, 12)
		wires.append(Vector2i(19, 12))
	Fixture.wire(ship, wires)
	ship.refresh()
	return ship


# --- the Scan pick ----------------------------------------------------------------------------------------------

func test_the_pick_is_a_recipe_the_ship_can_craft_next() -> void:
	var ship := _ship()
	eq(Workshop.best(ship)["level"], 1, "a lone fabricator is level 1")
	check(ship.crafting.is_known("laser_cutter"), "the cutter is start-known: its tool is known, so a recipe that needs it is within reach")
	eq(Salvage.next_recipe(ship, ["reactor_mk2"]), "", "a level 3 recipe is out of reach of a level 1 fabricator (level + 1 at most)")
	eq(Salvage.next_recipe(ship, ["reactor_mk2", "laser_mk2"]), "laser_mk2", "a level 2 recipe is next")
	eq(Salvage.next_recipe(ship, ["laser_mk1", "robot_arm", "pulse_mk2"]), "pulse_mk2", "known recipes are not picked")
	eq(Salvage.next_recipe(ship, ["not_a_recipe", ""]), "", "an unknown id is no candidate")
	eq(Salvage.next_recipe(ship, ["titanium"]), "", "a material is no blueprint to find")
	ship.crafting.known.erase("laser_cutter")
	eq(Salvage.next_recipe(ship, ["laser_mk2"]), "", "its tool neither known nor on the fabricator: out of reach")
	var tooled := _ship(false, true)
	tooled.crafting.known.erase("laser_cutter")
	eq(Workshop.best(tooled)["tools"], ["laser_cutter"], "a cutter in the room is the tool")
	eq(Salvage.next_recipe(tooled, ["laser_mk2"]), "laser_mk2", "the tool is present: in reach")


func test_a_level_two_ship_reaches_level_three_recipes_but_not_a_toolless_neon_one() -> void:
	var ship := _ship(true)
	eq(Workshop.best(ship)["level"], 2, "an arm makes level 2")
	eq(Salvage.next_recipe(ship, ["reactor_mk2"]), "reactor_mk2", "level 3 is level + 1")
	ship.crafting.known.erase("laser_cutter")
	eq(Salvage.next_recipe(ship, ["engine_neon_mk1", "shield_neon_mk1"]), "", "level 3 neon parts need the cutter, which this ship has no way to make or use")
	eq(Salvage.next_recipe(_ship(), ["engine_neon_mk1", "shield_neon_mk1"]), "", "and a level 1 ship is two levels short")


func test_the_pick_prefers_modules_weapons_and_shields_and_leaves_out_the_top_tier_of_the_rest() -> void:
	var ship := _ship(true)
	# laser_mk2 (tier 2, a weapon), pulse_mk1 (tier 1, a weapon), intake_mk1 (tier 1, other), reactor_mk2 (tier 2, other)
	eq(Salvage.next_recipe(ship, ["intake_mk1", "pulse_mk1", "laser_mk2"]), "laser_mk2", "a weapon beats an intake, the higher tier first")
	eq(Salvage.next_recipe(ship, ["reactor_mk2", "intake_mk1"]), "intake_mk1", "of the other parts the top tier on offer is left out while a lower one remains")
	eq(Salvage.next_recipe(ship, ["reactor_mk2"]), "reactor_mk2", "and kept when it is all there is")
	eq(Salvage.next_recipe(ship, ["reactor_mk2", "pulse_mk1"]), "pulse_mk1", "a weapon beats a reactor, whatever the tier")
	eq(Salvage.next_recipe(ship, ["laser_mk2", "shield_mk2", "pulse_mk2"]), "laser_mk2", "all of one tier: they stay, the first by id")
	eq(Salvage.next_recipe(ship, ["intake_mk1", "assembly_rig", "laser_mk2"]), "assembly_rig", "a fabricator module ranks first (it opens the next level)")
	eq(Salvage.next_recipe(ship, ["basalt_quarry_driver", "pulse_mk1"]), "pulse_mk1", "a weapon of the core game beats a racial one of a higher tier")
	eq(Salvage.next_recipe(ship, ["basalt_quarry_driver", "intake_mk1"]), "basalt_quarry_driver", "and a racial weapon beats a plain part")
	eq(Salvage.next_recipe(ship, ["intake_mk1", "radar_mk1"]), "intake_mk1", "plain parts of a tier: the first by id")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen := {}
	for i in 30:
		seen[Salvage.next_recipe(ship, ["laser_mk2", "shield_mk2", "pulse_mk2"], rng)] = true
	eq(seen.size(), 3, "with an rng the equals are drawn: %s" % [seen.keys()])


func test_the_scan_row_offers_the_next_craftable_recipe_not_the_grandest() -> void:
	var c := Campaign.new(5)
	var ship := Ship.from_design(STARTER)  # a level 1 fabricator, the design's own blueprints (no cutter)
	var enemy := _enemy(["engine_mk1", "reactor_mk2", "shield_mk2", "pulse_mk1"])
	var ev := Salvage.event_for(enemy, "won", c, ship, false, 5)  # (5 skulls: every part is on the page)
	var scan := -1
	for i in ev["choices"].size():
		if str(ev["choices"][i]["text"]).begins_with("Scan the "):
			scan = i
	check(scan >= 0, "there is a scan row")
	eq(ev["choices"][scan]["outcomes"][0]["effects"], {"blueprint": ["shield_mk2"]}, "the tier 2 shield beats the tier 1 pulse, and the reactor that is a level 3 recipe is out of reach")
	var only_far := Salvage.event_for(_enemy(["engine_mk1", "reactor_mk2"]), "won", c, ship, false, 5)
	eq(only_far["choices"].filter(func(ch): return str(ch["text"]).begins_with("Scan the ")).size(), 0, "a recipe out of reach is not offered at all")


## The Pirate Raider keeping the parts whose ids are in `keep`, one of each, as the ids given (a part of the raider is renamed to the next id).
func _enemy(keep: Array) -> Ship:
	var e: Ship = Ship.from_design("res://data/ships/pirate_raider.json")
	for uid in e.components.instances.keys().duplicate():
		e.components.remove_uid(uid)
	var n := 0
	for id in keep:
		e.components.instances[100 + n] = {"id": id, "anchor": Vector2i(n, 0), "rot": 0}
		n += 1
	return e


func test_a_boarding_blueprint_is_the_same_pick() -> void:
	var ship := _ship()
	var unknown: Array = []
	for rid in ship.crafting.order:
		if not ship.crafting.is_known(rid) and str(ship.crafting.def(rid).get("category", "")) != "material":
			unknown.append(rid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got: String = Loot._blueprint({"tier": 1, "unknown": unknown, "levels": {}, "ship": ship}, 1, rng)
	check(got != "" and Salvage.next_recipe(ship, [got]) == got, "%s is a recipe this ship can craft next" % got)
	check(int(ship.crafting.def(got)["fab_level"]) <= 2, "no more than a level above the fabricator (%s)" % got)
	var no_ship := Loot._blueprint({"tier": 1, "unknown": ["reactor_mk2"], "levels": {"reactor_mk2": 3}}, 1, rng)
	eq(no_ship, "reactor_mk2", "with no ship in the context it is the weighted pick of before")
	var far := Loot._blueprint({"tier": 1, "unknown": ["reactor_mk2"], "levels": {"reactor_mk2": 3}, "ship": ship}, 1, rng)
	eq(far, "reactor_mk2", "and when nothing is within reach the weighted pick still gives a blueprint")


func test_a_container_gives_the_boarding_the_ships_next_recipe() -> void:
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
	check(rid != "" and Salvage.next_recipe(ship, [rid]) == rid, "it holds a recipe the ship can craft next (%s)" % rid)


# --- the fabricator ladder: start-known, shops, events -----------------------------------------------------------------

func test_the_new_start_known_recipes_are_known_on_a_new_run() -> void:
	var start: Array = Content.read("res://data/recipes.json")["start_known"]
	for id in ["laser_cutter", "titanium"]:
		check(start.has(id), id + " is in recipes.json start_known")
	check(not start.has("assembly_rig"), "the Assembly Rig stays a blueprint to find")
	var ship := Ship.from_design(STARTER)
	check(not ship.crafting.is_known("laser_cutter"), "(the design saved its own, older list)")
	RunStart.apply_ship(ship, {}, null)
	for id in ["laser_cutter", "titanium"]:
		check(ship.crafting.is_known(id), id + " is known when the run starts")
	check(not ship.crafting.is_known("assembly_rig") and not ship.crafting.is_known("laser_mk2"), "the Rig and the Mk2 parts are not")
	eq(ship.inventory.count("fuel"), int(Campaign.config()["fuel"]["start"]), "(and the run starts with the fuel of the data)")


func test_the_shop_blueprint_pool_has_the_rig_and_the_mk2_laser_and_shield() -> void:
	var cfg := Campaign.config()
	var pool: Array = Shops.unique_pool(cfg, [])["blueprint"]
	for id in ["laser_mk2", "shield_mk2", "assembly_rig"]:
		check(pool.has("bp:" + id), "bp:%s is for sale in a shop" % id)
		eq(Shops.unique_price(cfg, "bp:" + id), Shops.unique_price(cfg, "bp:pulse_mk2"), id + " costs what the other Mk2 blueprints do")
	var recipes: Dictionary = {}
	for r in Content.read("res://data/recipes.json")["recipes"]:
		recipes[str(r["id"])] = true
	for id in cfg["shops"]["blueprints"]:
		check(recipes.has(str(id)), "the shop's blueprint %s is a recipe" % id)


func test_the_ladders_blueprints_have_events_and_none_is_free() -> void:
	var ev = Events.shared()
	var wanted := ["laser_mk2", "shield_mk2", "assembly_rig", "pulse_mk2"]
	var found := {}
	for id in BLUEPRINT_EVENTS:
		check(ev.events.has(id), id + " is an event")
		var e: Dictionary = ev.events.get(id, {})
		var got := false
		for ch in e.get("choices", []):
			for o in ch.get("outcomes", []):
				var eff: Dictionary = o.get("effects", {})
				if str(eff.get("blueprint", "")) != str(BLUEPRINT_EVENTS[id]):
					continue
				got = true
				found[str(BLUEPRINT_EVENTS[id])] = true
				var items: Dictionary = eff.get("items", {})
				var pays := items.values().any(func(v): return int(v) < 0) or int(eff.get("hull", 0)) < 0 or int(eff.get("crew_hp", 0)) < 0 or eff.has("site_fight")
				check(pays or ch.get("requires", {}).has("credits"), "%s: a blueprint costs something (%s)" % [id, str(eff)])
		check(got, "%s teaches %s" % [id, BLUEPRINT_EVENTS[id]])
	eq(found.keys().size(), wanted.size(), "every recipe the ladder needs has an event: %s" % [found.keys()])
	var rig := BLUEPRINT_EVENTS.keys().filter(func(id): return BLUEPRINT_EVENTS[id] == "assembly_rig")
	check(rig.size() >= 3, "the Rig, the key to fabricator level 3, has several: %s" % [rig])
	check(BLUEPRINT_EVENTS.size() >= 6 and BLUEPRINT_EVENTS.size() <= 10, "6 to 10 events")


func test_a_gated_blueprint_choice_closes_once_it_is_taken_and_the_other_rig_offers_close_with_it() -> void:
	var c := Campaign.new(2)
	var ship := Ship.from_design(STARTER)
	ship.inventory.add("credits", 400)
	ship.inventory.add("scrap", 200)
	ship.inventory.add("copper", 30)
	var e: Dictionary = c.events.get_event("station_meridian_shipyard_queue")
	var market: Dictionary = c.events.get_event("station_rusthold_scrap_market")
	var graft: Dictionary = c.events.get_event("scrapyard_graft_row_dock")
	var row := _row_of(c, e, ship, "Ask about the folder")
	check(row >= 0, "the folder choice is on the page, open with 160 credits")
	check(_row_of(c, market, ship, "Ask the old man under the crane") >= 0 and _row_of(c, graft, ship, "Ask Gasket about the arm") >= 0, "so are the other two Rig offers")
	var before: int = ship.inventory.count("credits")
	var r: Dictionary = c.events.choose(e, row, c, ship, {})
	check(r["ok"], "taken")
	check(ship.crafting.is_known("assembly_rig"), "the Assembly Rig blueprint is learned")
	eq(ship.inventory.count("credits"), before - 160, "for 160 credits")
	eq(_row_of(c, e, ship, "Ask about the folder"), -1, "the choice is gone afterwards (not_flag): no paying twice")
	eq(_row_of(c, market, ship, "Ask the old man under the crane"), -1, "the Rusthold market offer goes with it: it is the same blueprint")
	eq(_row_of(c, graft, ship, "Ask Gasket about the arm"), -1, "and so does Graft Row's")


## The index of the open choice of `e` that begins with `start`; -1 when the page does not show it (or shows it greyed).
func _row_of(c: Campaign, e: Dictionary, ship: Ship, start: String) -> int:
	for v in c.events.choice_view(e, c, ship, {}):
		if str(v["text"]).begins_with(start) and not bool(v["grey"]):
			return int(v["index"])
	return -1


# --- debris and mass ------------------------------------------------------------------------------------------------

func test_the_debris_flow_has_a_floor_a_heavy_ship_still_meets() -> void:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	var floor_v := float(cfg["spawn"]["flow_min"])
	check(floor_v >= 2.0 and floor_v < 6.0, "the floor is a real share of the full flow (%s of 6)" % str(floor_v))
	var d := DriftDebris.new(1, cfg)
	d.frame_vel = Vector2.ZERO
	check(d._stream_weights()[0] >= floor_v - 1e-4, "a ship that does not move meets the floor: %s" % str(d._stream_weights()))
	d.frame_vel = -d.stream_vel(0).normalized() * 30.0  # barely moving upstream: the flow past it is 1.75 x the current
	check(d._stream_weights()[0] >= floor_v - 1e-4, "so does a slow one: %s" % str(d._stream_weights()))
	d.frame_vel = -d.stream_vel(0).normalized() * 600.0
	near(d._stream_weights()[0], 6.0, "a fast one still tops out at 6 x")
	cfg["spawn"]["flow_min"] = 1.0
	var plain := DriftDebris.new(1, cfg)
	plain.frame_vel = Vector2.ZERO
	near(plain._stream_weights()[0], 1.0, "(with the floor at 1 a still ship meets the bare current, as before)")
	cfg["spawn"].erase("flow_min")
	var none := DriftDebris.new(1, cfg)
	none.frame_vel = Vector2.ZERO
	near(none._stream_weights()[0], 1.0, "(and data with no floor reads as 1)")


func near(got: float, want: float, msg: String, eps := 1e-4) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])
