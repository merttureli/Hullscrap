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
const ShipSim = preload("res://scripts/sim/ship_sim.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
const EventPanel = preload("res://scripts/ui/event_panel.gd")
const StationPanel = preload("res://scripts/ui/station_panel.gd")
const BuildMode = preload("res://scripts/build/build_mode.gd")

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
	var patrol: String = c.drift.ids()[10]  # any random node, made a patrol
	c.drift.node(patrol)["type"] = "patrol"
	c.current = patrol
	var calm: Dictionary = c.arrive(ship)["event"]
	check(calm.get("id", "") != "patrol_hostile", "at peace the patrol only inspects")
	c.rep["concord"] = -6
	var ev: Dictionary = c.arrive(ship)["event"]
	eq(ev.get("id", ""), "patrol_hostile", "below -5 the patrol opens fire")
	var r := c.events.choose(ev, 0, c, ship, c.node(patrol))
	eq(r["fight"], "tier", "and the fight starts")
	eq(c.fight_path("tier", "patrol"), "res://data/ships/pirate_raider.json", "from the patrol table")


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
	eq(Campaign.VERSION, 2, "the save format is version 2 (version 1 has no fuel_part and still loads: see test_engines1.gd)")


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


# --- the screens: map, event panel, station panel ---------------------------------------------------------------------------

## A stand-in for the combat view: it records the design it was asked to fight and lets a test end the fight.
class FakeCombat extends Node:
	signal finished(result: Dictionary)
	var active := false
	var entered := ""

	func enter(path := "") -> String:
		entered = path
		active = true
		return ""


## A map view on a sim with the Rustbucket, a seeded campaign started (Ma's introduction is up), and a fake combat view.
func _screen(seed_value := 5) -> Dictionary:
	var sim := ShipSim.new()
	sim.ships = [_ship()]
	var fake := FakeCombat.new()
	var map := MapView.new()
	map.sim = sim
	map.combat = fake
	fake.finished.connect(map._on_fight_finished)
	map.size = Vector2(1600.0, 900.0)
	map.new_seed = seed_value
	map.open()
	map.event_panel.size = map.size
	map.station_panel.size = map.size
	return {"map": map, "sim": sim, "fake": fake}


func _free_screen(d: Dictionary) -> void:
	d["map"].free()
	d["sim"].free()
	d["fake"].free()


func _press(node: Node, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	node._input(e)


## The index in the panel's view of the choice whose text contains `part`.
func _find(panel: EventPanel, part: String) -> int:
	for i in panel.view.size():
		if panel.view[i]["text"].contains(part):
			return i
	return -1


func _click(node: Control, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.pressed = true
	e.button_index = MOUSE_BUTTON_LEFT
	node._gui_input(e)


func test_a_new_run_opens_with_ma_gantry_then_the_station_menu() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	check(map.visible, "the map is open")
	check(map.event_panel.visible and map.event_panel.event.get("id", "") == "station_debt_intro", "Ma Gantry's introduction is up")
	check(not map.station_panel.visible, "the menu waits")
	eq(map.event_panel.choose(0), "", "'Sign me up'")
	check(map.event_panel.page == "result" and map.event_panel.result["text"] != "", "the outcome is shown")
	check(map.campaign.flags.has("met_ma"), "met_ma is set")
	_press(map.event_panel, KEY_ENTER)
	check(not map.event_panel.visible, "Enter goes on")
	check(map.station_panel.visible and map.station_panel.station == "rusthold", "and Rusthold's menu opens")
	_press(map.station_panel, KEY_ESCAPE)
	check(not map.station_panel.visible and map.visible, "Esc leaves the menu for the map")
	_press(map, KEY_M)
	check(not map.visible, "M closes the map")
	_free_screen(d)


func test_clicking_a_linked_node_jumps_and_a_far_one_does_not() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var c: Campaign = map.campaign
	map.event_panel.close()
	var ship: Ship = d["sim"].player_ship()
	var to := _next(c)
	_click(map, map.node_pos(to))
	eq(c.current, to, "the click on a linked node jumped")
	eq([ship.inventory.count("fuel"), c.jumps], [5, 1], "1 fuel, 1 jump")
	map.event_panel.close()
	map.station_panel.close()
	var far := ""
	for id in c.drift.ids():
		if id != c.current and not c.drift.linked(c.current, id) and not c.is_hidden(id):
			far = id
	var fuel := ship.inventory.count("fuel")
	eq(map.click_node(far), "no lane there", "a node with no lane is refused")
	eq(ship.inventory.count("fuel"), fuel, "for free")
	check(map.message_bad and map.message != "", "and it says so")
	ship.inventory.counts.erase("fuel")
	var back: String = c.drift.neighbours(c.current)[0]
	check(map.click_node(back).begins_with("no fuel"), "no fuel, no jump")
	check(map.message.contains("Shift+click"), "the message points at the drift jump")
	_free_screen(d)


func test_node_positions_fit_the_map_area_and_hit_testing_agrees() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var area := map.map_rect()
	for id in map.campaign.drift.ids():
		var p := map.node_pos(id)
		check(area.has_point(p), "%s is inside the map area" % id)
		if not map.campaign.is_hidden(id):
			eq(map.node_at(p), id, "%s is found at its own position" % id)
	eq(map.node_at(Vector2(2.0, 2.0)), "", "empty space finds nothing")
	check(map.node_at(map.node_pos("prism")) != "prism", "the hidden Prism cannot be clicked")
	_free_screen(d)


func test_an_event_with_a_blue_option_changes_the_cargo() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var ship: Ship = d["sim"].player_ship()
	map.event_panel.close()
	var ev: Dictionary = map.campaign.events.get_event("wreck_dead_freighter")
	map.event_panel.open_event(ev)
	var blue := _find(map.event_panel, "[Basalt]")
	check(blue >= 0 and map.event_panel.view[blue]["blue"], "the Basalt option is on offer, and blue")
	var scrap := ship.inventory.count("scrap")
	var ti := ship.inventory.count("titanium")
	eq(map.event_panel.choose(blue), "", "taken")
	eq([ship.inventory.count("scrap"), ship.inventory.count("titanium")], [scrap + 60, ti + 10], "the cargo changed")
	check(map.event_panel.result["lines"].has("+60 Scrap"), "and the panel says so")
	_press(map.event_panel, KEY_SPACE)
	check(not map.event_panel.visible, "Space goes on, and the chain ends")
	_free_screen(d)


func test_event_panel_keys_clicks_and_greyed_rows() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var ship: Ship = d["sim"].player_ship()
	var panel: EventPanel = map.event_panel
	panel.close()
	ship.inventory.counts.erase("credits")
	panel.open_event(map.campaign.events.get_event("trader_fuel_peddler"))
	var buy := _find(panel, "Buy one can")
	check(buy >= 0 and panel.view[buy]["grey"] and panel.view[buy]["need"] == "24 credits", "with no credits the can is greyed, with the need")
	check(panel.choose(buy).contains("24 credits"), "and it cannot be taken")
	check(panel.page == "choices", "the panel stays on its choices")
	ship.inventory.add("credits", 100)
	panel.open_event(map.campaign.events.get_event("trader_fuel_peddler"))
	var fuel := ship.inventory.count("fuel")
	_click(panel, panel.choice_rect(_find(panel, "Buy one can")).get_center())
	eq([ship.inventory.count("fuel"), ship.inventory.count("credits")], [fuel + 1, 76], "a click buys a can for 24")
	check(panel.page == "result", "the outcome is up")
	_click(panel, panel.layout()["button"].get_center())
	check(not panel.visible, "the Continue button ends it")
	panel.open_event(map.campaign.events.get_event("trader_fuel_peddler"))
	_press(panel, KEY_2)
	eq(ship.inventory.count("fuel"), fuel + 4, "key 2 buys three more")
	_free_screen(d)


func test_goto_opens_the_next_page_in_the_panel() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var panel: EventPanel = map.event_panel
	panel.close()
	panel.open_event(map.campaign.events.get_event("repo_collectors"))
	map.campaign.flags["debt_missed"] = true
	var talk := _find(panel, "Take it up with Ma")
	check(talk >= 0, "that choice is on offer")
	panel.choose(talk)
	check(panel.result["goto"] == "repo_fight", "it leads on")
	panel.proceed()
	eq(panel.event.get("id", ""), "repo_fight", "the next page is shown")
	check(panel.page == "choices", "with its own choices")
	_free_screen(d)


func test_a_fight_from_an_event_starts_combat_and_calls_back_with_the_result() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var ship: Ship = d["sim"].player_ship()
	var fake: FakeCombat = d["fake"]
	var panel: EventPanel = map.event_panel
	panel.close()
	panel.open_event(map.campaign.events.get_event("repo_fight"))
	panel.choose(0)
	panel.proceed()
	eq(fake.entered, "res://data/ships/pirate_raider.json", "the combat view was asked to fight the raider")
	check(not map.visible, "the map steps aside")
	var credits := ship.inventory.count("credits")
	var foe: Ship = Ship.from_design("res://data/ships/pirate_raider.json")
	fake.finished.emit({"state": "won", "enemy": foe, "hull": 200.0, "hull_max": 228.0})
	check(map.visible and panel.visible, "back on the map with a page up")
	check(panel.result["text"].contains("ledger") and panel.result["lines"].any(func(l): return l.begins_with("+")), "the after_win text and the loot are shown")
	check(ship.inventory.count("credits") >= credits + 60, "the loot (and the 40 of the ledger) is in the cargo")
	eq(map.campaign.hull_loss, 28, "the damage of the fight stays")
	panel.proceed()
	check(panel.visible and panel.event.get("type", "") == "wreck_field", "then a salvage event")
	_free_screen(d)


func test_losing_a_fight_starts_a_new_run() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var fake: FakeCombat = d["fake"]
	map.event_panel.close()
	map.campaign.jumps = 12
	map.campaign.debt = 400
	map.event_panel.open_event(map.campaign.events.get_event("repo_fight"))
	map.event_panel.choose(0)
	map.event_panel.proceed()
	fake.finished.emit({"state": "lost"})
	eq([map.campaign.jumps, map.campaign.debt], [0, 1000], "a fresh campaign")
	check(not map.event_panel.visible, "with nothing open")
	_free_screen(d)


func test_a_fight_the_map_did_not_start_is_ignored() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var fake: FakeCombat = d["fake"]
	map.event_panel.close()
	var jumps: int = map.campaign.jumps
	fake.finished.emit({"state": "won", "enemy": null, "hull": 1.0, "hull_max": 2.0})
	eq(map.campaign.hull_loss, 0, "the K-key test pirate gives no loot and changes nothing")
	eq(map.campaign.jumps, jumps, "(nothing moved)")
	_free_screen(d)


func test_station_menu_trades_pays_repairs_and_recruits() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var ship: Ship = d["sim"].player_ship()
	var c: Campaign = map.campaign
	var st: StationPanel = map.station_panel
	map.event_panel.close()
	c.hull_loss = 40
	st.open("rusthold")
	ship.inventory.add("credits", 2000)
	var rows0 := st.rows(0)
	eq(rows0[0]["id"], "fuel", "BUY starts with fuel")
	check(rows0.size() > 5, "and Rusthold's stock")
	var credits := ship.inventory.count("credits")
	st.act(0, 0)
	eq([ship.inventory.count("fuel"), ship.inventory.count("credits")], [7, credits - 8], "one can of fuel for 8")
	st.act(0, 0, MOUSE_BUTTON_RIGHT)
	eq(ship.inventory.count("fuel"), 12, "right-click buys five")
	ship.inventory.add("titanium", 10)
	var sell := -1
	for i in st.rows(1).size():
		if st.rows(1)[i]["id"] == "titanium":
			sell = i
	credits = ship.inventory.count("credits")
	st.act(1, sell)
	eq(ship.inventory.count("credits"), credits + 3, "one titanium sold at half of 6")
	var buy := -1
	for i in rows0.size():
		if rows0[i].get("id", "") == "engine_scrap_mk1":
			buy = i
	credits = ship.inventory.count("credits")
	var engines := ship.inventory.count("engine_scrap_mk1")
	st.act(0, buy)
	eq([ship.inventory.count("engine_scrap_mk1"), ship.inventory.count("credits")], [engines + 1, credits - 90], "stock bought")
	var srv := st.rows(2)
	var pay := -1
	var repair := -1
	var recruit := -1
	for i in srv.size():
		match srv[i]["kind"]:
			"pay":
				pay = i
			"repair":
				repair = i
			"recruit":
				recruit = i
	credits = ship.inventory.count("credits")
	st.act(2, pay)
	eq([c.debt, ship.inventory.count("credits")], [900, credits - 100], "100 paid on the debt")
	st.act(2, repair)
	eq(c.hull_loss, 30, "10 points of hull repaired")
	var crew := ship.crew.size()
	st.act(2, recruit)
	eq(ship.crew.size(), crew + 1, "a recruit hired")
	check(not st.message_bad, "no complaint: " + st.message)
	ship.inventory.counts.erase("credits")
	st.act(0, 0)
	check(st.message_bad, "no credits: refused")
	_click(st, st.row_rect(0, 0).get_center())
	check(st.message_bad, "a click on a row does the same")
	_press(st, KEY_ESCAPE)
	check(not st.visible, "Esc leaves")
	_free_screen(d)


func test_a_refused_dock_shows_the_dock_masters_words() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	map.event_panel.close()
	map.campaign.rep["clans"] = -8
	check(map.dock() == "The dock master turns you away.", "dock() is refused")
	check(not map.station_panel.visible, "no menu")
	map._arrive()
	check(map.event_panel.visible and map.event_panel.result["text"] == "The dock master turns you away.", "arriving shows it as a notice")
	_free_screen(d)


func test_the_event_panel_layout_keeps_the_choices_inside_the_panel() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var panel: EventPanel = map.event_panel
	for id in ["wreck_dead_freighter", "pirate_toll", "asteroid_tumbling_rock"]:
		panel.open_event(map.campaign.events.get_event(id))
		var lay := panel.layout()
		var p: Rect2 = lay["panel"]
		check(Rect2(Vector2.ZERO, panel.size).encloses(p), id + ": the panel fits the screen")
		eq(lay["rows"].size(), panel.view.size(), id + ": one row per choice")
		for r in lay["rows"]:
			check(p.encloses(r), id + ": a row is inside the panel")
	_free_screen(d)


func test_m_opens_the_map_from_play_mode_only() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	map.event_panel.close()
	map.visible = false
	var build := BuildMode.new()
	build.sim = d["sim"]
	build.drift = map
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	build._on_key(key)
	check(not map.visible and build.message.contains("play mode"), "in build mode M only says why not")
	build.build_on = false
	build._on_key(key)
	check(map.visible, "in play mode M opens the map")
	build.free()
	_free_screen(d)


func test_the_campaign_is_saved_and_loaded_with_the_ship() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	map.event_panel.close()
	map.save_path = "user://test_campaign_map.json"
	map.campaign.flags["met_ma"] = true
	map.campaign.jumps = 3
	eq(map.save_campaign(), "", "saved")
	map.new_game(99)
	eq(map.campaign.jumps, 0, "a different campaign now")
	eq(map.load_campaign(), "", "loaded")
	check(map.campaign.flags.has("met_ma") and map.campaign.jumps == 3 and map.campaign.seed_value == 5, "the saved one is back")
	check(not map.event_panel.visible, "without replaying the arrival")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(map.save_path))
	check(map.load_campaign() != "", "an old save with no campaign file says so")
	eq(map.campaign.jumps, 0, "and a new campaign begins")
	_free_screen(d)


func test_a_derelict_log_is_shown_in_the_result_page() -> void:
	var d := _screen()
	var map: MapView = d["map"]
	var panel: EventPanel = map.event_panel
	panel.close()
	var id: String = map.campaign.events.logs.keys()[0]
	var custom := Events.new("res://tests")
	custom.add({"id": "log_event", "type": "wreck_field", "weight": 10, "once": false, "requires": {}, "text": "A pad glints in the wreck.",
		"choices": [{"text": "Read it.", "outcomes": [{"weight": 1, "text": "You read.", "effects": {"log": id}}]}]}, "test.json")
	map.campaign.events = custom
	panel.open_event(custom.get_event("log_event"))
	panel.choose(0)
	eq(panel.result["logs"].size(), 1, "the log is in the result")
	check(map.campaign.logs_found.has(id), "and remembered")
	var lay := panel.layout()
	check(lay["log"].size.y > 40.0 and lay["button"].position.y > lay["log"].end.y, "its box is laid out above the Continue button")
	check(lay["panel"].encloses(lay["log"]) and lay["panel"].encloses(lay["button"]), "inside the panel")
	check(EventPanel.tone_of("Log found: x") == 1 and EventPanel.tone_of("-20 credits") == -1 and EventPanel.tone_of("Debt -100 (900 left)") == 1 and EventPanel.tone_of("Debt +50") == -1 and EventPanel.tone_of("Hull integrity -10") == -1, "change lines are coloured by whether they help")
	_free_screen(d)
