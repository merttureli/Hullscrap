extends "res://tests/base_test.gd"
## The Drift campaign without a screen: the seeded map (same seed, same map; connected; 2 to 4 lanes;
## spacing; the fixed places), fog, jumping and fuel, the debt clock and Ma's Kettle, reputation, the
## danger tiers, the station trades, saving and loading, and the data files that feed it.

const Campaign = preload("res://scripts/space/campaign.gd")
const Drift = preload("res://scripts/space/drift.gd")
const Events = preload("res://scripts/space/events.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Components = preload("res://scripts/ship/components.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const STARTERS := ["res://data/ships/starter_rustbucket.json", "res://data/ships/starter_courier.json", "res://data/ships/starter_prism.json"]


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


## A campaign that has the real events but nothing special.
func _camp(seed_value := 1) -> Campaign:
	return Campaign.new(seed_value)


func _map(seed_value: int) -> Drift:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Drift.generate(rng, Campaign.config())


## The first neighbour of the current node that can be jumped to (not a gate).
func _next(c: Campaign) -> String:
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			return o
	return ""


func _hop(c: Campaign, ship: Ship, n: int) -> void:
	for i in n:
		var r := c.jump(_next(c), ship)
		check(r["ok"], "hop %d: %s" % [i, r["why"]])


# --- the map -----------------------------------------------------------------------------------------------------

func test_same_seed_same_map() -> void:
	var a := _camp(1234)
	var b := _camp(1234)
	eq(a.drift.nodes.size(), 28, "28 nodes")
	for i in a.drift.nodes.size():
		var x: Dictionary = a.drift.nodes[i]
		var y: Dictionary = b.drift.nodes[i]
		eq([x["id"], x["pos"], x["type"], x["clan"]], [y["id"], y["pos"], y["type"], y["clan"]], "node %d: id, position, type" % i)
	eq(a.drift.lanes, b.drift.lanes, "the same lanes")
	var other := _camp(1235)
	check(other.drift.lanes != a.drift.lanes or other.drift.nodes[10]["pos"] != a.drift.nodes[10]["pos"], "another seed, another map")


func test_graph_is_connected_with_2_to_4_lanes_and_spacing_holds() -> void:
	var min_gap := float(Campaign.config()["map"]["min_spacing"])
	var fixed := ["rusthold", "meridian", "prism", "gate_1", "gate_2", "gate_3"]
	for seed_value in 40:
		var d := _map(seed_value)
		check(d.connected(), "seed %d: connected" % seed_value)
		check(d.min_distance() >= min_gap - 0.001, "seed %d: spacing %.1f" % [seed_value, d.min_distance()])
		for n in d.nodes:
			var k: int = d.degree(n["id"])
			if fixed.has(n["id"]):
				check(k >= 2, "seed %d: %s has %d lanes" % [seed_value, n["id"], k])
			else:
				check(k >= 2 and k <= 4, "seed %d: %s has %d lanes" % [seed_value, n["id"], k])
		for l in d.lanes:
			check(l[0] < l[1] and d.linked(l[0], l[1]) and d.linked(l[1], l[0]), "lanes are two-way")


func test_fixed_places_exist_and_rusthold_is_the_start() -> void:
	var d := _map(7)
	for id in ["rusthold", "meridian", "prism", "gate_1", "gate_2", "gate_3"]:
		check(d.has(id), id + " exists")
	eq(d.start_id(), "rusthold", "Rusthold is the start")
	check(d.node("rusthold")["pos"].x < 120.0, "at the left edge")
	check(absf(d.node("meridian")["pos"].x - 800.0) <= 100.0 and absf(d.node("meridian")["pos"].y - 500.0) <= 100.0, "Meridian is mid-map")
	var edge := 0
	for g in ["gate_1", "gate_2", "gate_3"]:
		var p: Vector2 = d.node(g)["pos"]
		eq(d.node(g)["type"], "gate", g + " is a gate")
		if p.x < 80.0 or p.x > 1520.0 or p.y < 80.0 or p.y > 920.0:
			edge += 1
	eq(edge, 3, "the three Dead Gates sit on the far edges")
	eq(d.node("prism")["hidden_until"], "prism_revealed", "the Prism is hidden until prism_revealed")
	eq(_camp(7).current, "rusthold", "a campaign starts at Rusthold")


func test_node_types_follow_the_weights() -> void:
	var w: Dictionary = Campaign.config()["node_weights"]
	eq(w["asteroid_field"], 14.0, "asteroid_field has weight 14")
	eq(w["empty"], 4.0, "empty has weight 4")
	eq(w.values().reduce(func(a, b): return a + b, 0.0), 100.0, "the weights add up to 100")
	var seen := {}
	for seed_value in 30:
		for n in _map(seed_value).nodes:
			if n["place"] == "":
				seen[n["type"]] = int(seen.get(n["type"], 0)) + 1
	for t in w:
		check(seen.has(t), "30 maps roll at least one " + t)
	for t in seen:
		check(w.has(t), "only types from the table: " + t)
	check(seen["pirate"] > seen["empty"] and seen["asteroid_field"] > seen["empty"], "pirates and asteroid fields are far more common than empty space")


# --- fog ----------------------------------------------------------------------------------------------------------

func test_fog_at_the_start_shows_only_rusthold_and_its_neighbours() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		var c := _camp(seed_value)
		var known := []
		for id in c.drift.ids():
			if c.is_known(id):
				known.append(id)
		known.sort()
		var want: Array = ["rusthold"] + c.neighbours("rusthold")
		want.sort()
		eq(known, want, "seed %d: only Rusthold and its lanes show a type" % seed_value)
		for id in c.drift.ids():
			if not c.is_known(id) and not c.is_hidden(id):
				eq(c.label(id), "?", "an unknown node shows ?")


func test_fog_lifts_round_the_new_node_after_a_jump() -> void:
	var c := _camp(3)
	var ship := _ship()
	var to := _next(c)
	check(c.jump(to, ship)["ok"], "jumped")
	for o in c.neighbours(to):
		check(c.is_known(o), "%s next to the new node is revealed" % o)
	check(c.is_known("rusthold") and c.is_known(to), "the visited ones stay known")


func test_the_prism_is_hidden_until_the_flag_is_set() -> void:
	var c := _camp(4)
	check(c.is_hidden("prism") and not c.is_known("prism"), "hidden at the start")
	check(not c.neighbours("gate_3").has("prism"), "hidden nodes drop out of the neighbour lists")
	for o in c.drift.neighbours("prism"):
		c.visited[o] = true
	check(c.is_hidden("prism") and not c.is_known("prism"), "still hidden next to a visited node")
	c.current = c.drift.neighbours("prism")[0]
	check(c.jump_block("prism", _ship()) == "no lane there", "and it cannot be jumped to")
	c.flags["prism_revealed"] = true
	check(not c.is_hidden("prism") and c.is_known("prism"), "revealed by the flag")
	check(c.neighbours(c.current).has("prism"), "and it joins the lanes")
	eq(c.label("prism"), "The Prism", "with its name")


# --- jumping -------------------------------------------------------------------------------------------------------

func test_a_jump_costs_one_fuel_and_one_on_the_counter_along_a_lane_only() -> void:
	var c := _camp(2)
	var ship := _ship()
	var fuel := ship.inventory.count("fuel")
	eq(fuel, 6, "a starter has 6 fuel")
	var far := ""
	for id in c.drift.ids():
		if id != c.current and not c.drift.linked(c.current, id):
			far = id
	eq(c.jump(far, ship)["why"], "no lane there", "not along a lane")
	eq([ship.inventory.count("fuel"), c.jumps], [6, 0], "nothing was spent")
	var to := _next(c)
	var r := c.jump(to, ship)
	check(r["ok"], "along a lane")
	eq([ship.inventory.count("fuel"), c.jumps, c.current], [5, 1, to], "1 fuel, 1 jump, and we are there")
	check(c.visited.has(to), "it is visited")


func test_no_fuel_refuses_the_jump() -> void:
	var c := _camp(2)
	var ship := _ship()
	ship.inventory.counts.erase("fuel")
	var r := c.jump(_next(c), ship)
	check(not r["ok"] and r["why"] == "no fuel", "refused with: no fuel")
	eq([c.jumps, c.current], [0, "rusthold"], "nowhere moved")


func test_a_drift_jump_costs_hull_integrity_instead_of_fuel() -> void:
	var c := _camp(2)
	var ship := _ship()
	check(not c.jump(_next(c), ship, true)["ok"], "not while there is fuel")
	ship.inventory.counts.erase("fuel")
	var top := c.hull_max(ship)
	var to := _next(c)
	var r := c.jump(to, ship, true)
	check(r["ok"] and r["drift"], "allowed with an empty tank")
	eq(c.hull_left(ship), top - 15, "15 hull integrity")
	eq([c.jumps, c.current], [1, to], "and the jump counted")
	c.hull_loss = top - 10
	check(not c.jump(_next(c), ship, true)["ok"], "a hull too weak to survive it refuses")


func test_the_dead_gates_are_dark() -> void:
	var c := _camp(2)
	var ship := _ship()
	var gate: String = "gate_1"
	c.current = c.drift.neighbours(gate)[0]
	var r := c.jump(gate, ship)
	check(not r["ok"] and r["why"] == "The gate is dark.", "the gate is dark")
	eq(ship.inventory.count("fuel"), 6, "and it costs nothing")


func test_the_danger_tier_follows_the_jump_counter() -> void:
	var c := _camp()
	var want := {0: 1, 9: 1, 10: 2, 24: 2, 25: 3, 99: 3}
	for j in want:
		c.jumps = j
		eq(c.tier(), want[j], "tier at jump %d" % j)


func test_a_pirate_node_with_two_missed_payments_sends_the_rammer() -> void:
	var cfg := Campaign.config().duplicate(true)
	for t in ["1", "2", "3"]:
		cfg["enemies"]["rammer"][t] = ["res://data/ships/starter_courier.json"]
	var c := Campaign.new(1, cfg)
	var pirate := "res://data/ships/pirate_raider.json"
	eq(c.fight_path("tier", "pirate"), pirate, "no payments missed: a raider")
	c.jumps = 8
	eq(c.fight_path("tier", "pirate"), pirate, "one missed: still a raider")
	c.jumps = 16
	eq(c.misses(), 2, "two payments in a row missed")
	eq(c.fight_path("tier", "pirate"), "res://data/ships/starter_courier.json", "the next pirate fight is the rammer")
	eq(c.fight_path("tier", "patrol"), pirate, "patrols do not")


# --- the debt ------------------------------------------------------------------------------------------------------------

func test_a_payment_is_due_every_8_jumps_and_a_miss_sets_the_flag() -> void:
	var c := _camp(2)
	var ship := _ship()
	ship.inventory.add("fuel", 100)
	eq([c.debt, c.next_due_in()], [1000, 8], "1000 owed, the first payment in 8 jumps")
	_hop(c, ship, 7)
	check(not c.flags.has("debt_missed") and c.behind() == 0, "nothing is due before jump 8")
	eq(c.next_due_in(), 1, "one jump to go")
	_hop(c, ship, 1)
	check(c.flags.has("debt_missed"), "jump 8 passed with nothing paid: the repo flag is set")
	eq([c.behind(), c.misses()], [100, 1], "100 behind, one miss")
	_hop(c, ship, 8)
	eq(c.misses(), 2, "another date missed: two in a row")


func test_paying_in_time_avoids_the_flag_and_paying_late_clears_it() -> void:
	var c := _camp(2)
	var ship := _ship()
	ship.inventory.add("fuel", 100)
	ship.inventory.add("credits", 1000)
	check(c.pay_debt(ship, 100)["ok"], "paid 100 early")
	_hop(c, ship, 8)
	check(not c.flags.has("debt_missed"), "paid up when the date came: no flag")
	_hop(c, ship, 8)
	check(c.flags.has("debt_missed"), "the second date was missed")
	check(c.pay_debt(ship, 100)["ok"], "paid it")
	check(not c.flags.has("debt_missed"), "caught up: the flag clears")
	eq(c.debt, 800, "800 left")


func test_paying_the_whole_debt_sets_debt_free_and_gives_the_kettle() -> void:
	var c := _camp(2)
	var ship := _ship()
	ship.inventory.add("credits", 1000)
	var credits := ship.inventory.count("credits")
	var r := c.pay_debt(ship, 100000)
	check(r["ok"], "paid: " + r["text"])
	eq([c.debt, c.paid], [0, 1000], "nothing owed")
	check(c.flags.has("debt_free"), "debt_free is set")
	eq(ship.inventory.count("reactor_scrap_kettle"), 1, "Ma's Kettle is in the cargo")
	eq(ship.inventory.count("credits"), credits - 1000, "for 1000 credits")
	check(not c.pay_debt(ship, 10)["ok"], "nothing left to pay")
	var again := Campaign.new(3)
	again.flags["debt_free"] = true
	again.debt = 0
	again.add_debt(ship, -10)
	eq(ship.inventory.count("reactor_scrap_kettle"), 1, "the Kettle comes once")


func test_you_cannot_pay_more_than_you_have() -> void:
	var c := _camp()
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	check(not c.pay_debt(ship, credits + 1)["ok"], "refused")
	eq([c.debt, ship.inventory.count("credits")], [1000, credits], "nothing changed")


func test_mas_kettle_is_a_unique_scrap_reactor_with_a_quirk() -> void:
	var comps := Components.new()
	comps.load_defs("res://data/components.json")
	var k := comps.def("reactor_scrap_kettle")
	var base := comps.def("reactor_scrap_mk1")
	check(k.get("unique", false) == true, "unique")
	eq([k["family"], k["line"], k["tier"], k["size"]], [base["family"], base["line"], base["tier"], base["size"]], "a Scrap reactor like the Mk1")
	eq(k["power"], base["power"] + 2, "two more power")
	for f in ["priority", "hp", "heat_limit", "heat_per_s", "cooling", "manned"]:
		eq(k[f], base[f], f + " as the Mk1")
	var quirk := false
	for a in k.get("abilities", []):
		for s in a.get("side_effects", []):
			quirk = quirk or s["type"] in ["drain_o2", "fire_risk"]
	check(quirk, "a quirk that drains O2 or risks fire")
	check(str(k.get("blurb", "")) != "", "a blurb")


# --- reputation -----------------------------------------------------------------------------------------------------------

func test_reputation_is_clamped_to_ten() -> void:
	var c := _camp()
	eq([c.add_rep("clans", 15), c.rep["clans"]], [10, 10], "up to +10")
	eq([c.add_rep("clans", 5), c.rep["clans"]], [0, 10], "no further")
	eq([c.add_rep("concord", -40), c.rep["concord"]], [-10, -10], "down to -10")
	eq(c.add_rep("rustfangs", 3), 0, "hostile factions have no bar")
	eq(c.rep.keys(), ["clans", "concord", "lumen"], "three bars")


func test_below_minus_five_a_station_refuses_docking() -> void:
	var c := _camp()
	var ship := _ship()
	c.rep["clans"] = -5
	eq(c.dock_block("rusthold"), "", "-5 is still welcome")
	c.rep["clans"] = -6
	eq(c.dock_block("rusthold"), "The dock master turns you away.", "-6 is not")
	var a := c.arrive(ship)
	eq(a["refused"], "The dock master turns you away.", "arriving there is refused")
	check(a["event"].is_empty(), "with no greeting")
	c.rep["clans"] = 0
	c.rep["concord"] = -6
	eq(c.dock_block("rusthold"), "", "another faction's anger does not matter at Rusthold")
	eq(c.dock_block("meridian"), "The dock master turns you away.", "but Meridian turns you away")


func test_hostile_concord_patrols_attack() -> void:
	var c := _camp()
	var ship := _ship()
	var patrol := ""
	for n in c.drift.nodes:
		if n["type"] == "patrol":
			patrol = n["id"]
	if patrol == "":
		return  # no patrol on this seed's map
	c.current = patrol
	c.rep["concord"] = -6
	var ev: Dictionary = c.arrive(ship)["event"]
	eq(ev.get("id", ""), "patrol_hostile", "the patrol opens fire")
	var r := c.events.choose(ev, 0, c, ship, c.node(patrol))
	eq(r["fight"], "tier", "and the fight starts")


func test_at_plus_five_prices_are_twenty_percent_off() -> void:
	var c := _camp()
	eq(c.price(100, "clans"), 100, "full price at 0")
	c.rep["clans"] = 4
	eq(c.price(100, "clans"), 100, "full price at +4")
	c.rep["clans"] = 5
	eq(c.price(100, "clans"), 80, "20% off at +5")
	eq(c.price(8, "clans"), 7, "rounded up")
	eq(c.price(100, "concord"), 100, "only that faction's stations")
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	check(c.buy_fuel(ship, "rusthold", 5)["ok"], "5 fuel")
	eq(ship.inventory.count("credits"), credits - 35, "at 7 credits each")


# --- stations ---------------------------------------------------------------------------------------------------------------------

func test_buy_fuel_at_eight_credits_a_can() -> void:
	var c := _camp()
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	var r := c.buy_fuel(ship, "rusthold", 3)
	check(r["ok"], r["text"])
	eq([ship.inventory.count("fuel"), ship.inventory.count("credits")], [9, credits - 24], "3 fuel for 24")
	ship.inventory.counts.erase("credits")
	check(not c.buy_fuel(ship, "rusthold", 1)["ok"], "no credits, no fuel")
	eq(ship.inventory.count("fuel"), 9, "nothing given")


func test_sell_an_item_at_half_its_value() -> void:
	var c := _camp()
	var ship := _ship()
	ship.inventory.add("titanium", 10)  # uncommon: worth 6
	eq(c.value_of(ship, "titanium"), 6, "titanium is worth 6")
	var credits := ship.inventory.count("credits")
	var titanium := ship.inventory.count("titanium")
	var r := c.sell(ship, "titanium", 4)
	check(r["ok"], r["text"])
	eq([ship.inventory.count("titanium"), ship.inventory.count("credits")], [titanium - 4, credits + 12], "4 sold at 3 each")
	eq(c.sell_price(ship, "pulse_mk1"), 20, "a tier 1 part: value 40, sells for 20")
	eq(c.sell_price(ship, "reactor_scrap_kettle"), 125, "a unique part: value 250")
	check(not c.sell(ship, "credits", 5)["ok"], "credits are not for sale")
	check(not c.sell(ship, "plasma_cell", 0)["ok"], "nothing to sell")
	var held := ship.inventory.count("scrap")
	c.sell(ship, "scrap", 99999)
	eq(ship.inventory.count("scrap"), 0, "you can sell everything you hold, no more")
	check(ship.inventory.count("credits") >= credits + 12 + held, "scrap sells at 1 each")


func test_buy_from_the_stock_of_the_station() -> void:
	var c := _camp()
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	var price := c.stock_price("rusthold", "engine_scrap_mk1")
	eq(price, 90, "the Scrapper engine costs 90 at Rusthold")
	var have := ship.inventory.count("engine_scrap_mk1")
	check(c.buy(ship, "rusthold", "engine_scrap_mk1")["ok"], "bought")
	eq([ship.inventory.count("engine_scrap_mk1"), ship.inventory.count("credits")], [have + 1, credits - 90], "in the cargo, paid")
	check(not c.buy(ship, "rusthold", "reactor_neon_mk1")["ok"], "Rusthold does not sell Neon parts")
	eq(c.stock_price("prism", "reactor_neon_mk1"), 360, "the Prism does")
	ship.inventory.counts.erase("credits")
	check(not c.buy(ship, "rusthold", "radiator")["ok"], "no credits, no radiator")


func test_pay_the_debt_at_a_station() -> void:
	var c := _camp()
	var ship := _ship()
	var credits := ship.inventory.count("credits")
	check(c.pay_debt(ship, 100)["ok"], "paid 100")
	eq([c.debt, ship.inventory.count("credits")], [900, credits - 100], "900 owed")
	check("debt" in c.station_cfg("rusthold")["services"], "Rusthold takes payments")
	check(not ("debt" in c.station_cfg("meridian")["services"]), "Meridian does not")


func test_repair_hull_integrity_at_two_credits_a_point() -> void:
	var c := _camp()
	var ship := _ship()
	check(not c.repair(ship, "rusthold", 5)["ok"], "a sound hull needs nothing")
	c.hull_loss = 30
	var credits := ship.inventory.count("credits")
	var r := c.repair(ship, "rusthold", 10)
	check(r["ok"], r["text"])
	eq([c.hull_loss, ship.inventory.count("credits")], [20, credits - 20], "10 points for 20 credits")
	c.repair(ship, "rusthold", 1000)
	eq(c.hull_loss, 0, "all of it, no more than is missing")
	eq(ship.inventory.count("credits"), credits - 60, "30 points in all for 60")
	c.hull_loss = 50
	ship.inventory.counts.erase("credits")
	check(not c.repair(ship, "rusthold", 5)["ok"], "no credits, no repair")


func test_recruit_for_150_credits() -> void:
	var c := _camp()
	var ship := _ship()
	c.roll_offers("rusthold", ship)
	eq(c.offers["rusthold"].size(), 2, "2 recruits on offer")
	for o in c.offers["rusthold"]:
		check(o["species"] in ["human", "basalt", "fenn"], "species weighted by the station: " + o["species"])
		check(o["name"] != "", "each has a name")
	var first: Dictionary = c.offers["rusthold"][0]
	var crew := ship.crew.size()
	var credits := ship.inventory.count("credits")
	var r := c.recruit(ship, "rusthold", 0)
	check(r["ok"], r["text"])
	eq(ship.crew.size(), crew + 1, "one more aboard")
	eq([ship.crew[-1].name, ship.crew[-1].species], [first["name"], first["species"]], "the one on offer")
	eq(ship.inventory.count("credits"), credits - 150, "for 150 credits")
	eq(c.offers["rusthold"].size(), 1, "and they are no longer on offer")
	ship.inventory.counts.erase("credits")
	check(not c.recruit(ship, "rusthold", 0)["ok"], "no credits, no hire")
	check(not c.recruit(ship, "rusthold", 5)["ok"], "nobody at that index")
	var meridian := _camp(3)
	meridian.roll_offers("meridian", ship)
	check(meridian.offers["meridian"].all(func(o): return o["species"] in ["human", "fenn"]), "Meridian's recruits are Human or Fenn")
	meridian.roll_offers("prism", ship)
	check(meridian.offers["prism"].size() == 2, "the Prism has its own")


func test_arriving_at_a_station_rolls_its_recruits() -> void:
	var c := _camp()
	var ship := _ship()
	c.arrive(ship)
	eq(c.offers.get("rusthold", []).size(), 2, "two recruits at Rusthold on arrival")


func test_a_clan_trader_node_takes_debt_payments_but_has_no_shipyard() -> void:
	var c := _camp()
	var found := false
	for seed_value in 30:
		var d := _map(seed_value)
		for n in d.nodes:
			if n["clan"]:
				found = true
				eq(n["type"], "trader", "only traders are clan")
	check(found, "some trader nodes are Scrapper ones")
	var node := {}
	for n in c.drift.nodes:
		if n["type"] == "trader":
			n["clan"] = true
			node = n
			break
	if not node.is_empty():
		var st := c.station_cfg(node["id"])
		check("debt" in st["services"] and not ("repair" in st["services"]), "a clan trader takes payments, nothing more")


# --- save and load -----------------------------------------------------------------------------------------------------------------

func test_save_and_load_round_trip_and_the_rng_carries_on() -> void:
	var c := _camp(77)
	var ship := _ship()
	ship.inventory.add("fuel", 20)
	_hop(c, ship, 4)
	c.flags["met_ma"] = true
	c.rep["lumen"] = 3
	c.used["x"] = true
	c.hull_loss = 12
	c.paid = 100
	c.debt = 900
	c.revealed["meridian"] = true
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))  # through real JSON
	var back := _camp(1)
	eq(back.load_dict(d), "", "loaded")
	eq(JSON.stringify(back.to_dict()), JSON.stringify(c.to_dict()), "everything survived")
	eq([back.current, back.jumps, back.debt, back.hull_loss, back.rep["lumen"]], [c.current, 4, 900, 12, 3], "the numbers")
	eq(back.drift.lanes, c.drift.lanes, "the lanes")
	var roll_a := []
	var roll_b := []
	for i in 5:
		roll_a.append(c.rng.randi())
		roll_b.append(back.rng.randi())
	eq(roll_a, roll_b, "the rng continues the same sequence")


func test_loading_a_bad_or_old_save_changes_nothing() -> void:
	var c := _camp(5)
	var good := c.to_dict()
	var snapshot := JSON.stringify(c.to_dict())
	var bad := good.duplicate(true)
	bad["version"] = 99
	check(c.load_dict(bad) != "", "a newer version is refused")
	bad = good.duplicate(true)
	bad["map"]["nodes"][0]["pos"] = "here"
	check(c.load_dict(bad) != "", "a broken map is refused")
	bad = good.duplicate(true)
	bad["current"] = "atlantis"
	check(c.load_dict(bad) != "", "a position off the map is refused")
	bad = good.duplicate(true)
	bad.erase("flags")
	check(c.load_dict(bad) != "", "a missing list is refused")
	eq(JSON.stringify(c.to_dict()), snapshot, "after all that the campaign is as it was")
	check(c.load_file("user://no_such_campaign.json") != "", "a missing file is an error, not a crash")
	eq(Campaign.VERSION, 1, "the save format is version 1")


func test_save_file_round_trip() -> void:
	var path := "user://test_campaign_roundtrip.json"
	var c := _camp(11)
	c.flags["met_ma"] = true
	eq(c.save(path), "", "saved")
	var back := _camp(1)
	eq(back.load_file(path), "", "loaded")
	check(back.flags.has("met_ma") and back.seed_value == 11, "the same campaign")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- the data ----------------------------------------------------------------------------------------------------------------------------

func test_drift_data_names_things_that_exist() -> void:
	var cfg := Campaign.config()
	var comps := Components.new()
	comps.load_defs("res://data/components.json")
	var items := {}
	for i in JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))["items"]:
		items[i["id"]] = true
	var factions := Campaign.rep_factions()
	for st in cfg["stations"]:
		var s: Dictionary = cfg["stations"][st]
		check(factions.has(s["faction"]), st + " names a faction with a bar")
		for id in s["stock"]:
			check(comps.has(id) or items.has(id), "%s stocks %s, which exists" % [st, id])
			check(not comps.has(id) or not comps.def(id).get("unique", false), "%s does not stock the unique %s" % [st, id])
		for sp in s["recruit"]:
			check(Events.SPECIES.has(sp), "%s recruits a known species: %s" % [st, sp])
		for svc in s["services"]:
			check(svc in ["fuel", "sell", "stock", "debt", "repair", "recruit"], "%s: known service %s" % [st, svc])
	for kind in cfg["enemies"]:
		for t in ["1", "2", "3"]:
			check(cfg["enemies"][kind].has(t) and not cfg["enemies"][kind][t].is_empty(), "%s has designs for tier %s" % [kind, t])
			for path in cfg["enemies"][kind][t]:
				check(FileAccess.file_exists(path), "%s tier %s: %s exists" % [kind, t, path])
	check("res://data/ships/pirate_raider.json" in cfg["enemies"]["pirate"]["1"], "tier 1 uses the Pirate Raider")
	for p in cfg["places"]:
		check(cfg["types"].has(p["type"]), "the place %s has a known type" % p["id"])
	for t in cfg["node_weights"]:
		check(cfg["types"].has(t), "the type %s is drawn on the map" % t)
	check(comps.has(cfg["debt"]["kettle"]), "the Kettle exists")


func test_starters_carry_six_fuel_and_fuel_is_an_item() -> void:
	for path in STARTERS:
		var ship: Ship = Ship.from_design(path)
		eq(ship.inventory.count("fuel"), 6, path + " carries 6 fuel")
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))["items"]
	check(items.any(func(i): return i["id"] == "fuel" and str(i["name"]) != "" and str(i["blurb"]) != ""), "items.json lists fuel")


func test_factions_file_lists_peoples_and_thresholds() -> void:
	var f := Campaign.factions_data()
	eq([f["rep"]["min"], f["rep"]["max"], f["rep"]["refuse_below"], f["rep"]["discount_from"], f["rep"]["discount"]], [-10.0, 10.0, -5.0, 5.0, 0.2], "the reputation rules")
	var hostile: Array = f["factions"].filter(func(x): return x["hostile"]).map(func(x): return x["id"])
	hostile.sort()
	eq(hostile, ["hollow", "rustfangs", "wardens"], "Rustfangs, Wardens and the Hollow are hostile")
	for x in f["factions"]:
		for k in ["id", "name", "line", "color", "name_style", "hostile"]:
			check(x.has(k), "%s has %s" % [x.get("id", "?"), k])
