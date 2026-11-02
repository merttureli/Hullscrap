extends "res://tests/base_test.gd"
## Playtest 2, the economy round: rare debris (data/debris.json `rare` types, drift_debris.gd, radar.gd), fuel that is scarce
## (stations, stocks, trader events) and the small shops of the traders (shops.gd). Fuel numbers: tests/tool_fuel_rate.gd.

const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Radar = preload("res://scripts/space/radar.gd")
const Content = preload("res://scripts/data/content.gd")
const Wall = preload("res://tests/fixture_wall.gd")
const Ship = preload("res://scripts/ship/ship.gd")

const RARE: Array[String] = ["crystal_shard", "titanium_plate", "silicon_wafer"]


func near(got: float, want: float, msg: String, eps := 1e-3) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, str(want), str(got)])


## A spawner with the file's numbers and a still, northerly current (so pieces are easy to place).
func _dd(seed_value := 1) -> DriftDebris:
	var cfg: Dictionary = Content.read(DriftDebris.PATH).duplicate(true)
	cfg["current"]["angle"] = 90
	cfg["current"]["wobble_deg"] = 0
	cfg["current"]["speed_wobble"] = 0
	return DriftDebris.new(seed_value, cfg)


# --- rare debris -------------------------------------------------------------------------------------------

func test_rare_types_are_in_the_data_and_very_rare() -> void:
	var d := _dd()
	var weights := {}
	var total := 0.0
	for t in d.types:
		weights[str(t["id"])] = float(t["weight"])
		total += float(t["weight"])
	for id in RARE:
		check(weights.has(id), "%s is a debris type" % id)
		check(weights.get(id, 99.0) <= 0.5 and weights.get(id, 0.0) > 0.0, "%s is very rare (weight %s, scrap is 40)" % [id, str(weights.get(id))])
		check(bool(d.type_of({"type": id}).get("rare", false)), "%s is flagged rare" % id)
	eq(RARE.map(func(id): return int(d.type_of({"type": id})["yield"].values()[0])), [2, 3, 2], "what each gives: crystal 2, titanium 3, silicon 2")
	eq(RARE.map(func(id): return d.type_of({"type": id})["yield"].keys()[0]), ["crystal", "titanium", "silicon"], "and which material")
	near(float(weights["fuel_canister"]), 0.5, "fuel is a rare find too (down from 3)")
	check(total > 80.0 and total < 100.0, "the flow is still mostly scrap, copper and polymer (total weight %s)" % str(total))


func test_rare_pieces_spawn_about_their_weight_share() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd(7)
	var n := 40000
	var seen := {}
	var total := 0.0
	for t in d.types:
		total += float(t["weight"])
	for i in n:
		d.pieces.clear()
		var p := d._spawn(ship)
		seen[p["type"]] = int(seen.get(p["type"], 0)) + 1
	for id in RARE:
		var want := float(d.type_of({"type": id})["weight"]) / total
		var got := float(seen.get(id, 0)) / n
		check(got > want * 0.7 and got < want * 1.3, "%s is %.3f%% of the flow, want about %.3f%%" % [id, got * 100.0, want * 100.0])
	check(not seen.has("ice_chunk_s"), "no ice")


func test_the_radar_lists_rare_pieces_within_range() -> void:
	var d := _dd()
	var here := Vector2(1000.0, 1000.0)
	d.add_piece("crystal_shard", here + Vector2(0.0, -800.0), Vector2.ZERO)  # due north
	d.add_piece("scrap_chunk_s", here + Vector2(100.0, 0.0), Vector2.ZERO)
	d.add_piece("titanium_plate", here + Vector2(2500.0, 0.0), Vector2.ZERO)
	var near_list := Radar.rare_pieces(d, here, 1500.0)
	eq(near_list.map(func(r): return r["type"]), ["crystal_shard"], "one rare piece in 1,500 px; scrap is no rare piece, titanium is too far")
	near(float(near_list[0]["bearing"]), 0.0, "straight up is bearing 0")
	near(float(near_list[0]["distance"]), 800.0, "the distance")
	var far_list := Radar.rare_pieces(d, here, 3000.0)
	eq(far_list.map(func(r): return r["type"]), ["crystal_shard", "titanium_plate"], "a 3,000 px radar sees both, nearest first")
	near(float(far_list[1]["bearing"]), PI / 2.0, "east is a quarter turn clockwise")
	eq(Radar.rare_pieces(null, here, 3000.0), [], "no debris, no list")


func test_a_rare_piece_announces_itself_once_when_it_comes_into_view() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	d.view_centre = Vector2.ZERO
	d.view_half = Vector2(800.0, 450.0)
	var p := d.add_piece("crystal_shard", Vector2(3000.0, 0.0), Vector2.ZERO)
	d._note_rare()
	eq(d.take_events(), [], "out of view: nothing yet")
	p["pos"] = Vector2(100.0, 100.0)
	d._note_rare()
	d._note_rare()
	var ev := d.take_events()
	eq(ev.map(func(e): return [e["kind"], e["text"]]), [["rare", "Rare drift: crystal shard"]], "once, with its name")
	d.add_piece("scrap_chunk_s", Vector2(50.0, 50.0), Vector2.ZERO)
	d._note_rare()
	eq(d.take_events(), [], "ordinary debris says nothing")
	check(ship != null, "fixture")


func test_collecting_a_rare_piece_gives_its_material() -> void:
	var ship := Wall.wall_ship(1, 0)
	var d := _dd()
	var before := ship.inventory.count("crystal")
	var t := d.type_of({"type": "crystal_shard"})
	check(d._store(ship, t, d._gains(t, ship)), "the hold takes it")
	eq(ship.inventory.count("crystal"), before + 2, "crystal 2")
	check(d.hud_line().contains("+2 crystal"), "the HUD lists it: " + d.hud_line())


# --- fuel is scarce ----------------------------------------------------------------------------------------------

const Campaign = preload("res://scripts/space/campaign.gd")
const Regions = preload("res://scripts/space/regions.gd")
const Events = preload("res://scripts/space/events.gd")
const FUEL_TRADERS_BEFORE := 14  ## trader events that offered fuel before the economy round (a python audit of the effects)


## Every station place of every region, plus the Scrapper trader: [{id, menu}].
func _stations(c: Campaign) -> Array:
	var out := []
	for r in Regions.all():
		for p in r.get("places", []):
			if str(p.get("type", "")) == "station":
				out.append({"id": str(p["id"]), "menu": Regions.station(str(p["id"]), c.cfg), "region": r})
	return out


func test_about_forty_percent_of_the_stations_sell_fuel() -> void:
	var c := Campaign.new(3)
	var list := _stations(c)
	list.append({"id": "clan_trader", "menu": c.cfg["stations"]["clan_trader"], "region": {}})
	var sells := list.filter(func(s): return s["menu"]["services"].has("fuel"))
	var share := float(sells.size()) / list.size()
	check(share > 0.33 and share < 0.47, "%d of %d stations sell fuel (%.0f%%)" % [sells.size(), list.size(), share * 100.0])
	check(not c.cfg["stations"]["clan_trader"]["services"].has("fuel"), "the Scrapper trader does not")
	for id in ["rusthold", "meridian", "prism"]:
		check(c.station_cfg(id).get("services", []).has("fuel") or Regions.station(id, c.cfg)["services"].has("fuel"), "%s, the main station of its region, sells fuel" % id)
	for stage in range(1, 9):  # every stage has regions whose station sells it, and a share of them near 40%
		var here := list.filter(func(s): return not s["region"].is_empty() and s["region"]["stages"][0] <= stage and stage <= s["region"]["stages"][1])
		var fuel_here := here.filter(func(s): return s["menu"]["services"].has("fuel"))
		check(fuel_here.size() >= 1 and (here.size() <= 2 or float(fuel_here.size()) / here.size() < 0.55), "stage %d: %d of %d region stations sell fuel" % [stage, fuel_here.size(), here.size()])


func test_fuel_costs_fourteen_and_a_visit_has_two_to_four_seeded() -> void:
	var c := Campaign.new(5)
	eq(int(c.cfg["fuel"]["price"]), 14, "fuel price 14")
	eq(c.cfg["fuel"]["stock"].map(func(v): return int(v)), [2, 4], "2 to 4 units a visit")
	var counts := {}
	for seed_value in 60:
		var k := Campaign.new(seed_value)
		var n := k.fuel_left("rusthold")
		counts[n] = true
		check(n >= 2 and n <= 4, "seed %d: %d on sale" % [seed_value, n])
		eq(Campaign.new(seed_value).fuel_left("rusthold"), n, "the same seed has the same stock")
	eq(counts.keys().size(), 3, "all of 2, 3 and 4 come up: %s" % [counts.keys()])
	eq(c.fuel_left("nowhere"), 0, "no station, no fuel")
	eq(c.fuel_left("clan_trader"), 0, "the Scrapper trader has none")


func test_the_stock_refills_on_the_next_visit_and_is_saved() -> void:
	var c := Campaign.new(8)
	var ship := Ship.from_design("res://data/ships/starter_courier.json")
	ship.inventory.add("credits", 500)
	var first := c.fuel_left("rusthold")
	c.buy_fuel(ship, "rusthold", 1)
	eq(c.fuel_left("rusthold"), first - 1, "one bought")
	var back := Campaign.new(8)
	check(back.load_dict(c.to_dict()) == "", "it loads")
	eq(back.fuel_left("rusthold"), first - 1, "the save keeps what is left of the visit")
	c.buy_fuel(ship, "rusthold", 9)
	eq(c.fuel_left("rusthold"), 0, "sold out")
	c.jumps += 1  # the ship jumped away and came back: a new visit
	var next := c.fuel_left("rusthold")
	check(next >= 2 and next <= 4, "a new visit has a new stock: %d" % next)
	eq(Campaign.new(8).load_dict(c.to_dict()), "", "still saves and loads")
	var old: Dictionary = c.to_dict()
	old.erase("fuel_stock")
	check(Campaign.new(8).load_dict(old) == "", "a save from before the scarce fuel loads")


func test_few_trader_events_offer_fuel_and_only_a_unit_or_two() -> void:
	var ev = Events.shared()
	var offering := []
	var traders := 0
	for id in ev.order:
		var e: Dictionary = ev.events[id]
		if str(e.get("type", "")) != "trader":
			continue
		traders += 1
		var most := 0
		for ch in e.get("choices", []):
			for o in ch.get("outcomes", []):
				var eff = o.get("effects", {})
				if eff is Dictionary and eff.get("items") is Dictionary:
					most = maxi(most, int(eff["items"].get("fuel", 0)))
		if most > 0:
			offering.append(id)
			check(most <= 2, "%s offers %d fuel at most, want 1 or 2" % [id, most])
	check(offering.size() * 3 <= FUEL_TRADERS_BEFORE, "at most a third of the %d trader events that offered fuel still do: %s" % [FUEL_TRADERS_BEFORE, offering])
	check(offering.size() * 3 <= traders, "and they are a small part of the %d trader events (%d)" % [traders, offering.size()])
	check(offering.has("trader_fuel_peddler"), "the generic fuel peddler is one of them")


func test_a_run_starts_with_the_fuel_of_the_data() -> void:
	const RunStart = preload("res://scripts/space/run_start.gd")
	var start := int(Campaign.config()["fuel"]["start"])
	check(start > 6, "the tank was raised from 6 when the other fuel was cut (%d)" % start)
	var ship := Ship.from_design("res://data/ships/starter_courier.json")
	eq(ship.inventory.count("fuel"), 6, "the design carries 6")
	RunStart.apply_ship(ship, {}, null)
	eq(ship.inventory.count("fuel"), start, "and starts the run topped up to fuel.start")
	ship.inventory.add("fuel", 5)
	RunStart.fuel_up(ship)
	eq(ship.inventory.count("fuel"), start + 5, "a ship with more keeps it")
