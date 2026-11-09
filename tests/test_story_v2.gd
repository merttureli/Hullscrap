extends "res://tests/base_test.gd"
## Story v2 (the Hollow tide, docs/CONTENT.md section 8): the alarm-night opening at Rusthold, Rusthold going Hollow on the first
## jump, Ma's barge, Ma's calls and the endings.

const Campaign = preload("res://scripts/space/campaign.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")

const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"
const OPENINGS := ["station_opening_blank", "station_opening_hull"]


func _ship() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	s.crew_plan = [{"name": "Soldier", "species": "human"}]
	Jobs.spawn_crew(s)
	s.inventory.add("fuel", 30)
	return s


func _crew(s: Ship) -> int:
	return s.crew.filter(func(m): return not m.is_drone()).size()


## A jump along the first lane that does not lead to a gate.
func _hop(c: Campaign, ship: Ship) -> Dictionary:
	var to := ""
	for o in c.neighbours(c.current):
		if c.node(o)["type"] != "gate":
			to = o
			break
	var r: Dictionary = c.start_jump(to, ship, false, false)
	check(r["ok"], "a jump: " + str(r.get("why", "")))
	c.tick_jump(c.spool_time(), false, ship)
	return c.last_jump


# --- the opening ---------------------------------------------------------------------------------------------------

func test_the_blank_frame_and_the_ready_hull_each_have_their_own_opening() -> void:
	var ship := _ship()
	var c := Campaign.new(5)
	var node := c.node("rusthold")
	var blank: Dictionary = c.events.get_event("station_opening_blank")
	var hull: Dictionary = c.events.get_event("station_opening_hull")
	check(c.events.eligible(hull, c, node, ship) and not c.events.eligible(blank, c, node, ship), "a ready-made starter gets the hull's opening")
	c.flags[Campaign.BUILD_FIRST] = true
	check(c.events.eligible(blank, c, node, ship) and not c.events.eligible(hull, c, node, ship), "a build-your-own start gets the frame's")
	check(str(blank["text"]).contains("frame") and str(hull["text"]).contains("hull"), "and each says so")
	for ev in [blank, hull]:
		check(bool(ev["once"]) and bool(ev.get("opening", false)), str(ev["id"]) + " is a once-event marked as the opening")
		check(c.events.crew_factor(str(ev["id"]), c) == 1.0 and not c.events.offers_crew(str(ev["id"]), c), "and its survivors are never gated or counted as a crew offer")
	c.flags["met_ma"] = true
	check(not c.events.eligible(blank, c, node, ship), "spent once met_ma is set")


func test_the_opening_choices_set_flags_and_hand_out_survivors_or_scrap() -> void:
	for id in OPENINGS:
		for choice in 3:
			for seed_value in [1, 2, 3, 4]:
				var ship := _ship()
				var c := Campaign.new(seed_value)
				var ev: Dictionary = c.events.get_event(id)
				var crew := _crew(ship)
				var scrap := ship.inventory.count("scrap")
				var nets := ship.inventory.count("net_mouth_scrap")
				var r: Dictionary = c.events.choose(ev, choice, c, ship, c.node("rusthold"))
				var where := "%s choice %d seed %d" % [id, choice, seed_value]
				check(r["ok"], where + " is on offer")
				check(c.flags.has("met_ma"), where + ": met_ma set")
				eq(ship.inventory.count("net_mouth_scrap"), nets, where + ": no second net mouth")
				match choice:
					0:
						eq(_crew(ship), crew + 2, where + ": two survivors join as crew")
						check(not c.flags.has("helped_barge"), where + ": and the barge was not helped")
					1:
						eq(_crew(ship), crew + 1, where + ": one survivor fewer")
						check(c.flags.has("helped_barge"), where + ": helped_barge")
						eq(c.rep["clans"], 1, where + ": a little Clans reputation")
					2:
						eq(_crew(ship), crew, where + ": no survivors")
						check(ship.inventory.count("scrap") > scrap, where + ": scrap or parts instead")
						check(not c.flags.has("helped_barge"), where + ": the barge was not helped")


# --- Rusthold falls ------------------------------------------------------------------------------------------------

func test_rusthold_goes_hollow_on_the_first_jump_with_no_trade_and_a_chronicle_line() -> void:
	var ship := _ship()
	var c := Campaign.new(3)
	check(not c.is_hollow("rusthold") and not c.station_cfg("rusthold").is_empty(), "before the first jump Rusthold is a station")
	var r := _hop(c, ship)
	check(c.is_hollow("rusthold"), "after it Rusthold is Hollow")
	check(c.station_cfg("rusthold").is_empty(), "a ghost station: no trade, no services")
	check(r["notes"].has(Campaign.RUSTHOLD_TEXT), "the jump says so: " + str(r["notes"]))
	eq(Campaign.RUSTHOLD_TEXT, "Rusthold's lights stay on. Its radio goes quiet.", "in these words")
	check(c.chronicle.any(func(x): return str(x["text"]) == Campaign.RUSTHOLD_TEXT), "and the chronicle keeps the line")
	var n := c.chronicle.size()
	_hop(c, ship)
	eq(c.chronicle.size(), n, "once")
	var back := Campaign.new(1)
	eq(back.load_dict(JSON.parse_string(JSON.stringify(c.to_dict()))), "", "saved and loaded")
	check(back.is_hollow("rusthold"), "Rusthold is still Hollow")
	check(back.arrive(ship)["event"].get("type", "") == "hollow" or back.current != "rusthold", "(a ghost place sends ghosts)")
