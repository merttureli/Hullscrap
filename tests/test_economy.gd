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
	near(float(weights["fuel_canister"]), 0.25, "fuel is a rare find too (down from 3, then 0.5, then halved again)")
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


func test_about_seventy_percent_of_the_stations_sell_fuel() -> void:
	var c := Campaign.new(3)
	var list := _stations(c)
	list.append({"id": "clan_trader", "menu": c.cfg["stations"]["clan_trader"], "region": {}})
	var sells := list.filter(func(s): return s["menu"]["services"].has("fuel"))
	var share := float(sells.size()) / list.size()
	check(share > 0.68 and share < 0.78, "%d of %d stations sell fuel (%.0f%%)" % [sells.size(), list.size(), share * 100.0])
	check(not c.cfg["stations"]["clan_trader"]["services"].has("fuel"), "the Scrapper trader does not")
	for id in ["rusthold", "meridian", "prism"]:
		check(c.station_cfg(id).get("services", []).has("fuel") or Regions.station(id, c.cfg)["services"].has("fuel"), "%s, the main station of its region, sells fuel" % id)
	for stage in range(1, 9):  # every stage has regions whose station sells it, and a share of them near 70%
		var here := list.filter(func(s): return not s["region"].is_empty() and s["region"]["stages"][0] <= stage and stage <= s["region"]["stages"][1])
		var fuel_here := here.filter(func(s): return s["menu"]["services"].has("fuel"))
		check(fuel_here.size() >= 1 and (here.size() <= 2 or float(fuel_here.size()) / here.size() < 0.9), "stage %d: %d of %d region stations sell fuel" % [stage, fuel_here.size(), here.size()])


func test_fuel_costs_fourteen_and_a_visit_has_four_to_eight_seeded() -> void:
	var c := Campaign.new(5)
	eq(int(c.cfg["fuel"]["price"]), 14, "fuel price 14")
	eq(c.cfg["fuel"]["stock"].map(func(v): return int(v)), [4, 8], "4 to 8 units a visit")
	var counts := {}
	for seed_value in 60:
		var k := Campaign.new(seed_value)
		var n := k.fuel_left("rusthold")
		counts[n] = true
		check(n >= 4 and n <= 8, "seed %d: %d on sale" % [seed_value, n])
		eq(Campaign.new(seed_value).fuel_left("rusthold"), n, "the same seed has the same stock")
	eq(counts.keys().size(), 5, "all of 4 to 8 come up: %s" % [counts.keys()])
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
	check(next >= 4 and next <= 8, "a new visit has a new stock: %d" % next)
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


# --- small shops -------------------------------------------------------------------------------------------------

const Shops = preload("res://scripts/space/shops.gd")
const StationPanel = preload("res://scripts/ui/station_panel.gd")
const Sector = preload("res://scripts/space/sector.gd")


## A stand-in for the map view the station panel asks for the campaign and the ship.
class MapStub extends Control:
	var campaign
	var _ship
	func ship():
		return _ship
	func refresh() -> void:
		pass


## Every node id of the campaign's current region map.
func _node_ids(c: Campaign) -> Array:
	return c.drift.nodes.map(func(n): return str(n["id"]))


func test_a_shop_has_three_to_five_items_and_one_or_two_unique() -> void:
	var c := Campaign.new(11)
	var seen_unique := {}
	for r in Regions.all():
		c.enter_region(str(r["id"]))
		for node_id in _node_ids(c).slice(0, 4):
			for poi in ["p0", "p1", "p2"]:
				var cfg := c.station_cfg(Campaign.shop_id(node_id, poi))
				if cfg.is_empty():
					continue  # (a Hollow place: no trade)
				var n: int = cfg["stock"].size()
				check(n >= 3 and n <= 5, "%s %s %s: %d items" % [r["id"], node_id, poi, n])
				check(cfg["unique"].size() >= 1 and cfg["unique"].size() <= 2, "%s %s %s: %d unique" % [r["id"], node_id, poi, cfg["unique"].size()])
				for u in cfg["unique"]:
					check(cfg["stock"].has(u), "a unique item is on the shelf")
					seen_unique[u] = true
				for id in cfg["stock"]:
					check(cfg["unique"].has(id) or Campaign.config()["shops"]["common"].has(id), "%s is common or unique" % id)
	check(seen_unique.size() > 40, "a wide variety of finds over all the shops (%d)" % seen_unique.size())
	var kinds := {"racial": false, "tier": false, "material": false, "drone": false, "blueprint": false}
	for id in seen_unique:
		if str(id).begins_with("bp:"):
			kinds["blueprint"] = true
		elif Campaign.config()["shops"]["materials"].has(id):
			kinds["material"] = true
		elif Campaign.config()["shops"]["drone"].has(id):
			kinds["drone"] = true
		elif Content.origin("components", str(id)).begins_with("tech_"):
			kinds["racial"] = true
		else:
			kinds["tier"] = true
	check(kinds.values().all(func(v): return v), "racial parts, tier 2-3 parts, rare materials, the drone and blueprints all turn up: %s" % [kinds])


func test_station_stocks_never_hold_a_regions_unique_finds() -> void:
	var c := Campaign.new(12)
	var cfg := Campaign.config()
	var stocked := {}  # every id any station sells
	for st in cfg["stations"]:
		for id in cfg["stations"][st]["stock"]:
			stocked[id] = true
	for r in Regions.all():
		for id in r.get("stock", {}):
			stocked[id] = true
	for id in cfg["shops"]["materials"]:
		check(not stocked.has(id), "no station sells the rare material %s" % id)
	for r in cfg["shops"]["blueprints"]:
		check(not stocked.has("bp:" + r), "no station sells the blueprint %s" % r)
	for id in cfg["shops"]["common"]:
		check(stocked.has(id), "the common %s is on sale at some station" % id)
	for r in Regions.all():
		c.enter_region(str(r["id"]))
		var here := {}
		for p in r.get("places", []):
			if str(p.get("type", "")) == "station":
				for id in Regions.station(str(p["id"]), cfg).get("stock", {}):
					here[id] = true
		for node_id in _node_ids(c).slice(0, 6):
			for poi in ["p0", "p1", "p2", "p3"]:
				for u in c.station_cfg(Campaign.shop_id(node_id, poi)).get("unique", []):
					check(not here.has(u), "%s: the station there sells %s, so it is no unique find in %s" % [r["id"], u, node_id])
	for id in cfg["shops"]["common"]:
		for kind in Shops.unique_pool(cfg, []):
			check(not Shops.unique_pool(cfg, [])[kind].has(id), "the common %s is not in the unique pool" % id)


func test_the_same_seed_gives_the_same_shop() -> void:
	var a := Campaign.new(21)
	var b := Campaign.new(21)
	var other := Campaign.new(22)
	var differ := 0
	for node_id in _node_ids(a).slice(0, 8):
		var id := Campaign.shop_id(node_id, "p1")
		eq(a.station_cfg(id), b.station_cfg(id), "seed 21, shop %s" % id)
		eq(a.station_cfg(id), a.station_cfg(id), "and asked twice")
		if a.station_cfg(id)["stock"].keys() != other.station_cfg(id)["stock"].keys():
			differ += 1
	check(differ >= 5, "another seed stocks other things (%d of 8 differ)" % differ)
	var pois := {}
	for poi in ["p0", "p1", "p2", "p3", "p4"]:
		pois[str(a.station_cfg(Campaign.shop_id(_node_ids(a)[0], poi))["stock"].keys())] = true
	check(pois.size() >= 3, "and the shops of one sector differ from each other")


func test_what_is_bought_leaves_the_shelf_and_a_blueprint_is_learned() -> void:
	var c := Campaign.new(31)
	var ship := Ship.from_design("res://data/ships/starter_courier.json")
	ship.inventory.add("credits", 5000)
	var id := Campaign.shop_id(_node_ids(c)[0], "p0")
	var cfg := c.station_cfg(id)
	var items: Array = cfg["stock"].keys()
	var item: String = items[0]
	var price: int = cfg["stock"][item]
	var credits: int = ship.inventory.count("credits")
	var r := c.buy(ship, id, item, 1)
	check(r["ok"], str(r["text"]))
	eq(credits - ship.inventory.count("credits"), price, "paid the shelf price")
	var after := c.station_cfg(id)
	eq(int(after["qty"].get(item, 0)), int(cfg["qty"][item]) - 1, "one unit left the shelf")
	var back := Campaign.new(31)
	check(back.load_dict(c.to_dict()) == "", "it loads")
	eq(back.station_cfg(id)["qty"], after["qty"], "the save keeps what was bought")
	eq(back.station_cfg(id)["stock"].size(), after["stock"].size(), "and the rest of the shelf")
	# a blueprint: forced into the shop's roll so the test does not depend on the seed
	var bp := "bp:pulse_mk2"
	c._shops[id]["stock"][bp] = 360
	c._shops[id]["qty"][bp] = 1
	c._shops[id]["unique"].append(bp)
	check(not ship.crafting.known.has("pulse_mk2"), "the blueprint is unknown")
	var b := c.buy(ship, id, bp, 1)
	check(b["ok"] and ship.crafting.known.has("pulse_mk2"), "bought and learned: " + str(b["text"]))
	check(not c.station_cfg(id)["stock"].has(bp), "and gone from the shelf")
	check(not c.buy(ship, id, bp, 1)["ok"], "it cannot be bought twice")


func test_the_shop_panel_marks_the_unique_items_rare() -> void:
	var c := Campaign.new(41)
	var ship := Ship.from_design("res://data/ships/starter_courier.json")
	var stub := MapStub.new()
	stub.campaign = c
	stub._ship = ship
	var panel := StationPanel.new()
	panel.map = stub
	var id := Campaign.shop_id(_node_ids(c)[0], "p0")
	panel.open(id)
	var cfg := c.station_cfg(id)
	var rows := panel.rows(0)
	eq(rows.size(), cfg["stock"].size(), "a row for every item (no fuel, no blueprint you know)")
	var rare := rows.filter(func(r): return bool(r.get("rare", false)))
	eq(rare.map(func(r): return r["id"]), rows.filter(func(r): return cfg["unique"].has(r["id"])).map(func(r): return r["id"]), "the rare rows are the unique items")
	check(rare.size() >= 1 and rare.size() <= 2, "one or two of them")
	check(rows.all(func(r): return r["kind"] == "buy"), "a shop sells no fuel")
	var first: Dictionary = rows[0]
	var credits: int = ship.inventory.count("credits")
	ship.inventory.add("credits", 5000)
	panel.act(0, 0)
	check(not panel.message_bad, "a click buys: " + panel.message)
	check(c.station_cfg(id)["qty"].get(first["id"], 0) < int(cfg["qty"][first["id"]]), "and the shelf is lighter")
	check(credits >= 0, "fixture")
	panel.free()
	stub.free()


func test_trader_and_store_pois_open_a_shop() -> void:
	var cfg := Sector.config()
	check(bool(cfg["poi_types"]["trader"].get("shop", false)) and bool(cfg["poi_types"]["store"].get("shop", false)), "the Trader and Store POI types are shops")
	check(not bool(cfg["poi_types"]["station"].get("shop", false)) and not bool(cfg["poi_types"]["wreck"].get("shop", false)), "a station and a wreck are not")
	var found := 0
	for seed_value in 30:
		var c := Campaign.new(seed_value)
		var ship := Ship.from_design("res://data/ships/starter_courier.json")
		for n in c.drift.nodes:
			if str(n["type"]) != "trader":
				continue
			c.current = str(n["id"])
			var s = c.current_sector()
			for poi in s.pois:
				if str(poi["type"]) != "store" and str(poi["type"]) != "trader":
					continue
				s.ship_pos = poi["pos"]
				var res: Dictionary = s.trigger(c, ship)
				if res.is_empty() or res["refused"] != "":
					continue
				eq(res["shop"], Campaign.shop_id(str(n["id"]), str(poi["id"])), "the trigger names the shop")
				check(res["dock"], "and docks into it")
				check(not c.station_cfg(res["shop"]).is_empty(), "which has a menu")
				found += 1
				break
			if found >= 6:
				break
		if found >= 6:
			break
	check(found >= 3, "Trader and Store POIs were met in the seeds tried (%d)" % found)
