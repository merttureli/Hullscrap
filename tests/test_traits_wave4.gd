extends "res://tests/base_test.gd"
## The trait keys race wave 4 needs (docs/waves/races_2_4.md; scripts/crew/traits.gd): mining_mult, low_pressure_heal, haggler,
## loot_bonus, mimic and station.pull_bonus, one test each through the system it changes, plus the races that need no new key
## (Ferro's ion immunity and hull_mend, the Warden-frame's, Brine's), the merge rules and the validators. Traits the data has no
## use for yet are made up in the library for the test (`_trait`) and removed again.

const Campaign = preload("res://scripts/space/campaign.gd")
const CrewAbilities = preload("res://scripts/crew/crew_abilities.gd")
const CrewMember = preload("res://scripts/crew/crew_member.gd")
const DriftDebris = preload("res://scripts/space/drift_debris.gd")
const Fixture = preload("res://tests/fixture_ship.gd")
const BuildSession = preload("res://scripts/ship/build_session.gd")
const Jobs = preload("res://scripts/crew/jobs.gd")
const Pathfinder = preload("res://scripts/crew/pathfinder.gd")
const Salvage = preload("res://scripts/space/salvage.gd")
const Ship = preload("res://scripts/ship/ship.gd")
const Shipgen = preload("res://scripts/space/shipgen.gd")
const TestContent = preload("res://tests/test_content.gd")
const Tractor = preload("res://scripts/space/tractor.gd")
const TraitSet = preload("res://scripts/crew/traits.gd")
const Wall = preload("res://tests/fixture_wall.gd")

const STEP := 0.1
const RUSTBUCKET := "res://data/ships/starter_rustbucket.json"


func near(got: float, want: float, msg: String, eps := 1e-6) -> void:
	check(absf(got - want) <= eps, "%s: expected %s, got %s" % [msg, want, got])


func _trait(id: String, bag: Dictionary) -> void:
	var e := {"name": id}
	e.merge(bag)
	TraitSet.library()[id] = e


func _done() -> void:
	TraitSet.reset()


## A person on the body anchor (x, y), with the made-up traits `ids` worn (read again: gear does not change the body later).
func _person(p_name: String, x: int, y: int, ids: Array = [], player := false) -> CrewMember:
	var m := CrewMember.new(p_name, Pathfinder.centre_of(Vector2i(x, y)))
	m.gear_traits = ids
	m.set_species("human")
	m.pos = Pathfinder.centre_of(Vector2i(x, y), m.body_size)
	m.is_player = player
	return m


func _run(ship: Ship, jobs: Jobs, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-9:
		jobs.tick(ship, STEP)
		t += STEP


## The sealed room of the fixture ship plus a second one under it (y 19..25), full of air.
func _two_rooms() -> Ship:
	var ship := Fixture.room_ship()
	BuildSession.new(ship).apply(BuildSession.room_changes(Vector2i(8, 18), Vector2i(22, 26), "wall", "floor"))
	ship.refresh()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 1.0
	return ship


## The starter with a crew, for the campaign tests.
func _starter() -> Ship:
	var s: Ship = Ship.from_design(RUSTBUCKET)
	Jobs.spawn_crew(s)
	return s


# --- mining_mult ----------------------------------------------------------------------------------------

func test_mining_mult_scales_rock_damage_of_the_tool_they_man_or_the_cut_of_their_hands() -> void:
	_trait("t_digger", {"mining_mult": 1.5})
	_trait("t_claws", {"mining_mult": 2.0})
	var ship := Fixture.room_ship()
	var mole := _person("Mole", 11, 12, ["t_digger"])
	var plain := _person("Plain", 16, 12)
	ship.crew.append_array([mole, plain])
	near(TraitSet.mining_factor(ship, 7), 1.0, "nobody at the tool: x1")
	ship.manned[7] = "Plain"
	near(TraitSet.mining_factor(ship, 7), 1.0, "a plain crew member: x1")
	ship.manned[7] = "Mole"
	near(TraitSet.mining_factor(ship, 7), 1.5, "the digger at the tool: x1.5")
	near(TraitSet.mining_factor(ship, 8), 1.0, "a tool nobody mans: x1")
	mole.hurt(1000.0)
	near(TraitSet.mining_factor(ship, 7), 1.0, "a downed operator mans nothing")
	near(TraitSet.of(mole)["mining_mult"], 1.5, "cutting by hand reads the key itself: x1.5")
	near(TraitSet.of(plain)["mining_mult"], 1.0, "and a plain crew member cuts at x1")
	var both := _person("Both", 11, 14, ["t_digger", "t_claws"])
	near(TraitSet.of(both)["mining_mult"], 3.0, "factors multiply")
	_done()


# --- low_pressure_heal ----------------------------------------------------------------------------------

func test_low_pressure_heal_heals_only_in_a_room_under_half_its_air() -> void:
	_trait("t_bell", {"low_pressure_heal": 1.0})
	var ship := _two_rooms()
	var thin: int = ship.atmosphere.room_at(Vector2i(12, 12))
	var full: int = ship.atmosphere.room_at(Vector2i(12, 21))
	check(thin >= 0 and full >= 0 and thin != full, "two rooms")
	var bell := _person("Bell", 11, 12, ["t_bell"], true)
	var other := _person("Other", 16, 12, [], true)
	var elsewhere := _person("Elsewhere", 12, 21, ["t_bell"], true)
	ship.crew.append_array([bell, other, elsewhere])
	for m in ship.crew:
		m.hp = 50.0
	ship.atmosphere.pressure[thin] = 0.4
	var jobs := Jobs.new()
	_run(ship, jobs, 5.0)
	near(bell.hp, 55.0, "1 hp a second in a room under half its air", 1e-3)
	near(other.hp, 50.0, "a plain crew member there heals nothing")
	near(elsewhere.hp, 50.0, "nor does the trait in a room with air")
	ship.atmosphere.pressure[thin] = 0.5
	_run(ship, jobs, 3.0)
	near(bell.hp, 55.0, "at exactly half it stops: the room is not below it")
	ship.atmosphere.pressure[thin] = 0.16
	_run(ship, jobs, 2.0)
	near(bell.hp, 57.0, "and in thin air above the suffocation line it heals again", 1e-3)
	ship.atmosphere.pressure[thin] = 0.0
	var t := TraitSet.of(bell)
	near(TraitSet.low_pressure_heal_rate(t, 0.49), 1.0, "the rate below the line")
	near(TraitSet.low_pressure_heal_rate(t, 0.5), 0.0, "none at it")
	near(TraitSet.low_pressure_heal_rate(TraitSet.of(other), 0.0), 0.0, "none without the trait")
	bell.hp = bell.max_hp - 0.5
	ship.atmosphere.pressure[thin] = 0.3
	_run(ship, jobs, 3.0)
	near(bell.hp, bell.max_hp, "it never heals past the max")
	_done()


# --- haggler --------------------------------------------------------------------------------------------

func test_haggler_takes_a_fraction_off_the_prices_and_the_best_one_counts() -> void:
	_trait("t_crow", {"haggler": 0.1})
	_trait("t_shark", {"haggler": 0.25})
	var c := Campaign.new(1)
	var ship := _starter()
	var base_stock := c.stock_price("rusthold", "engine_scrap_mk1", ship)
	eq(base_stock, 90, "the Scrapper engine costs 90 at Rusthold with nobody haggling")
	eq(c.price(100, "", ship), 100, "a crew with no haggler pays the base price")
	eq(c.price(100, ""), 100, "and so does a call with no ship")
	var crow := _person("Crow", 11, 12, ["t_crow"])
	ship.crew.append(crow)
	eq(c.price(100, "", ship), 90, "a haggler aboard: -10%")
	eq(c.price(100, "", null), 100, "but only for the ship asked")
	eq(c.stock_price("rusthold", "engine_scrap_mk1", ship), 81, "the stock of a station follows it")
	var shark := _person("Shark", 16, 12, ["t_shark"])
	ship.crew.append(shark)
	eq(c.price(100, "", ship), 75, "the best haggler counts, they do not add up across the crew")
	shark.hurt(1000.0)
	eq(c.price(100, "", ship), 90, "a downed one haggles for nobody")
	shark.hp = shark.max_hp
	c.rep["clans"] = 5
	eq(c.price(100, "clans", ship), 55, "it adds to the faction's 20%: 25% more here")
	eq(c.price(1, "clans", ship), 1, "and a price is never below 1")
	c.rep["clans"] = 0
	var credits := ship.inventory.count("credits")
	var bought: int = mini(5, c.fuel_left("rusthold"))
	check(c.buy_fuel(ship, "rusthold", 5)["ok"], "5 fuel (or what the visit has)")
	eq(credits - ship.inventory.count("credits"), bought * c.price(int(c.cfg["fuel"]["price"]), "clans", ship), "paid at the haggled price")
	credits = ship.inventory.count("credits")
	check(c.buy(ship, "rusthold", "engine_scrap_mk1")["ok"], "bought")
	eq(credits - ship.inventory.count("credits"), 68, "the Scrapper engine at 90 less 25% (67.5, rounded up)")
	c.hull_loss = 4
	credits = ship.inventory.count("credits")
	check(c.repair(ship, "rusthold", 4)["ok"], "repaired")
	eq(credits - ship.inventory.count("credits"), 4 * c.price(int(c.cfg["prices"]["repair"]), "clans", ship), "repairs follow it too")
	_done()


# --- loot_bonus -----------------------------------------------------------------------------------------

func _cut_rows(ev: Dictionary) -> int:
	var n := 0
	for ch in ev["choices"]:
		if str(ch["text"]).begins_with("Cut out"):
			n += 1
	return n


func test_loot_bonus_adds_rows_to_the_salvage_pick() -> void:
	_trait("t_eye", {"loot_bonus": 1})
	_trait("t_eye2", {"loot_bonus": 2})
	var enemy := Shipgen.build("wardens", "large", 7, 300.0)
	check(Salvage.parts(enemy).size() >= 9, "a big wreck, plenty to cut out")
	var c := Campaign.new(3)
	var ship := _starter()
	eq(Salvage.picks_for("won", 0, c, ship), 3, "no crow: the usual 3")
	eq(Salvage.picks_for("won", 0, c), 3, "and with no ship")
	eq(_cut_rows(Salvage.event_for(enemy, "won", c, ship)), 3, "three parts to cut out")
	var crow := _person("Crow", 11, 12, ["t_eye"])
	ship.crew.append(crow)
	eq(Salvage.picks_for("won", 0, c, ship), 4, "loot_bonus 1: one more")
	eq(Salvage.picks_for("captured", 0, c, ship), 5, "on a captured ship too")
	var ev := Salvage.event_for(enemy, "won", c, ship)
	eq(_cut_rows(ev), 4, "four parts to cut out")
	check(not str(ev["text"]).contains("dangerous"), "the bonus is not the enemy's danger: no word of it")
	var ev5 := Salvage.event_for(enemy, "won", c, ship, null, 5)
	eq(_cut_rows(ev5), 3 + 2 + 1, "a five-skull wreck adds its own two")
	check(str(ev5["text"]).contains("dangerous"), "and says so")
	var wise := _person("Wise", 16, 12, ["t_eye2"])
	ship.crew.append(wise)
	eq(Salvage.picks_for("won", 0, c, ship), 5, "the best one aboard counts: 2, not 1 + 2")
	wise.hurt(1000.0)
	eq(Salvage.picks_for("won", 0, c, ship), 4, "a downed one counts for nothing")
	var tiny := Ship.from_design("res://data/ships/pirate_raider.json")
	for uid in tiny.components.instances.keys():
		if not ["laser_mk1", "reactor_scrap_mk1"].has(tiny.components.instances[uid]["id"]):
			tiny.components.remove_uid(uid)
	eq(_cut_rows(Salvage.event_for(tiny, "won", c, ship)), 2, "a wreck with two parts offers two, bonus or none")
	eq(Salvage.event_for(enemy, "won", c, ship, true)["choices"].size(), 1, "a ghost ship still offers only the strip row")
	_done()


func test_loot_bonus_adds_rolls_to_a_loot_table() -> void:
	_trait("t_eye", {"loot_bonus": 1})
	var ship := _starter()
	var one := {"id": "x", "roll": [{"weight": 1, "item": "scrap", "count": [2, 2]}]}
	var d := DriftDebris.new(1)
	eq(d._gains(one, ship), {"scrap": 2}, "a crate rolls once")
	eq(d._gains(one), {"scrap": 2}, "and with no ship")
	ship.crew.append(_person("Crow", 11, 12, ["t_eye"]))
	eq(d._gains(one, ship), {"scrap": 4}, "a crow aboard: two rolls, the finds add up")
	var mixed := {"id": "y", "roll": [{"weight": 1, "item": "scrap", "count": [1, 1]}, {"weight": 1, "item": "copper", "count": [1, 1]}]}
	for i in 20:
		var got: Dictionary = d._gains(mixed, ship)
		var units := 0
		for id in got:
			check(id == "scrap" or id == "copper", "only items of the table: %s" % id)
			units += int(got[id])
		eq(units, 2, "two rolls of one unit each, whatever they find")
	# A real crate: collected at an intake it pays the extra roll.
	var counts := {}
	for who in ["plain", "crow"]:
		var rig := Wall.wall_ship(1, 0)
		var depth: int = rig.components.by_id["net_mouth_scrap"]["mount"]["outside"][1]
		rig.components.place_mount(rig.grid, "net_mouth_scrap", Wall.out_anchor(0, depth), 0)
		rig.refresh()
		if who == "crow":
			rig.crew.append(_person("Crow", 11, 12, ["t_eye"]))
		var dd := DriftDebris.new(1)
		var rect: Rect2 = dd.intakes(rig)[0]["rect"]
		dd.add_piece("sealed_crate", rect.get_center() + Vector2(0, -10), Vector2.ZERO)
		var before := rig.inventory.counts.duplicate()
		dd.step(rig, 0.05)
		var gained := 0
		for id in rig.inventory.counts:
			if id != "credits":
				gained += int(rig.inventory.counts[id]) - int(before.get(id, 0))
		counts[who] = gained
		eq(dd.picked, 1, "%s: the crate was collected" % who)
	check(counts["plain"] >= 1 and counts["crow"] >= 2, "a collected crate gives more with a crow aboard: %s" % str(counts))
	_done()


# --- mimic ----------------------------------------------------------------------------------------------

func test_mimic_copies_the_best_trait_of_the_others_in_its_room_while_there() -> void:
	_trait("t_echo", {"mimic": true})
	_trait("t_fix", {"work_mult": {"repair": 2.0}})
	_trait("t_tough", {"damage_taken": {"fire": 0.5}})
	_trait("t_small", {"body": 1, "hp_mult": 0.5, "revive_once": {"after": 5, "hp": 50}})
	_trait("t_fast", {"speed_mult": 2.0})
	var ship := _two_rooms()
	var echo := _person("Echo", 11, 12, ["t_echo"], true)
	var fixer := _person("Fixer", 16, 12, ["t_fix"], true)
	var tough := _person("Tough", 18, 14, ["t_tough"], true)
	var small := _person("Small", 14, 14, ["t_small"], true)
	ship.crew.append_array([echo, fixer, tough, small])
	var jobs := Jobs.new()
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, ["t_tough"], "the best trait of the room: damage_taken is ahead of work_mult in MIMIC_ORDER")
	near(TraitSet.of(echo)["damage_taken"]["fire"], 0.5, "and its keys are the Echo's now")
	near(TraitSet.of(echo)["work_mult"]["repair"], 1.0, "only that one")
	near(TraitSet.work_rate(ship, echo, "repair"), 1.0, "so the Echo does not repair faster")
	check(not TraitSet.of(echo)["revive_once"]["hp"] > 0.0, "a trait that holds a body key is never copied, whatever else it has")
	near(echo.max_hp, 100.0, "the Echo's own body is as it was")
	eq(fixer.mimicking, [], "a crew member who is no mimic copies nothing")
	# The copied trait goes with the room: Tough steps out, the next best is copied.
	tough.pos = Pathfinder.centre_of(Vector2i(12, 21), tough.body_size)
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, ["t_fix"], "Tough left the room: the next best, work_mult")
	near(TraitSet.work_rate(ship, echo, "repair"), 2.0, "the Echo repairs twice as fast now")
	near(TraitSet.of(echo)["damage_taken"]["fire"], 1.0, "and the old copy is gone")
	fixer.pos = Pathfinder.centre_of(Vector2i(12, 21), fixer.body_size)
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, [], "only a body trait is left in the room: nothing to copy")
	near(TraitSet.work_rate(ship, echo, "repair"), 1.0, "the Echo is itself again")
	# A mate with the trait the Echo has already adds nothing, and one that is down is not copied.
	fixer.pos = Pathfinder.centre_of(Vector2i(16, 12), fixer.body_size)
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, ["t_fix"], "back with Fixer")
	fixer.hurt(1000.0)
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, [], "a downed crew member is copied no more")
	fixer.hp = fixer.max_hp
	echo.gear_traits = ["t_echo", "t_fix"]
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, [], "a trait the Echo has already is not copied again")
	near(TraitSet.of(echo)["work_mult"]["repair"], 2.0, "it stays x2, not x4")
	# Two Echoes do not copy one another (a mimic's trait is never copied), and a downed Echo copies nothing.
	var echo2 := _person("Echo2", 18, 12, ["t_echo"], true)
	ship.crew.append(echo2)
	echo.gear_traits = ["t_echo"]
	fixer.hurt(1000.0)
	jobs.tick(ship, 0.01)
	eq([echo.mimicking, echo2.mimicking], [[], []], "two Echoes alone copy nothing")
	fixer.hp = fixer.max_hp
	jobs.tick(ship, 0.01)
	eq([echo.mimicking, echo2.mimicking], [["t_fix"], ["t_fix"]], "both copy the one trait there is")
	echo.hurt(1000.0)
	jobs.tick(ship, 0.01)
	eq(echo.mimicking, [], "a downed Echo copies nothing")
	# TraitSet.of is cached per copy: no stale set after the copy ends.
	check(TraitSet.of(echo2)["work_mult"]["repair"] == 2.0 and TraitSet.of(_person("P", 11, 16)).get("work_mult")["repair"] == 1.0, "the sets are per copy")
	_done()


func test_mimic_ranks_by_a_fixed_order_and_breaks_ties_by_crew_order() -> void:
	_trait("t_echo", {"mimic": true})
	_trait("t_a", {"work_mult": {"repair": 1.5}, "haggler": 0.1})
	_trait("t_b", {"work_mult": {"extinguish": 3.0}})
	_trait("t_c", {"hull_mend": {"rate": 1.0}})
	_trait("t_d", {"ion_stun": 5.0})
	_trait("t_e", {"no_tools": true, "mechanical": true})
	var ship := _two_rooms()
	var echo := _person("Echo", 11, 12, ["t_echo"], true)
	var a := _person("A", 14, 12, ["t_d", "t_e", "t_a"], true)
	var b := _person("B", 16, 12, ["t_b"], true)
	ship.crew.append_array([echo, a, b])
	eq(TraitSet.mimic_pick(ship, echo), "t_a", "traits with no copyable key are skipped; a ties goes to the first crew member")
	b.gear_traits = ["t_c", "t_b"]
	eq(TraitSet.mimic_pick(ship, echo), "t_c", "hull_mend ranks ahead of work_mult")
	eq(TraitSet.mimic_pick(ship, a), "t_c", "anyone can ask: the others' traits, not their own")
	var outside := _person("Out", 11, 21, ["t_echo"], true)
	ship.crew.append(outside)
	eq(TraitSet.mimic_pick(ship, outside), "", "alone in a room: nothing")
	var keys: Array[String] = TraitSet.MIMIC_ORDER
	for k in keys:
		check(TraitSet.KEYS.has(k), "%s in MIMIC_ORDER is a trait key" % k)
		check(not TraitSet.BODY_KEYS.has(k), "%s is not a body key" % k)
	_done()


# --- station.pull_bonus ---------------------------------------------------------------------------------

## The wall fixture with part `id` through the wall (powered when it draws power); returns {ship, uid}.
func _mount(id: String) -> Dictionary:
	var ship := Wall.wall_ship(1, 0)
	var depth: int = ship.components.by_id[id]["mount"]["outside"][1]
	var uid := ship.components.place_mount(ship.grid, id, Wall.out_anchor(0, depth), 0)
	if int(ship.components.def(id)["power"]) < 0:
		ship.components.place(ship.grid, "reactor_mk1", Wall.corner(0, 2, 5, 1, 4), 0)
		for c in [Wall.at(0, 1, 1), Wall.at(0, 2, 1)]:
			ship.cables.place(ship.grid, c)
	ship.refresh()
	return {"ship": ship, "uid": uid}


func test_pull_bonus_reaches_further_with_the_intake_they_man() -> void:
	_trait("t_magnet", {"station": {"pull_bonus": 1}})
	var r := _mount("net_mouth_scrap")
	var ship: Ship = r["ship"]
	var uid: int = r["uid"]
	var ferro := _person("Ferro", 11, 20, ["t_magnet"])
	ship.crew.append(ferro)
	var d := DriftDebris.new(1)
	near(float(d.intakes(ship)[0]["pull"]), 2.0 * 32.0, "nobody at the intake: its own pull radius of 2 cells")
	ship.manned[uid] = "Ferro"
	near(float(d.intakes(ship)[0]["pull"]), 3.0 * 32.0, "Ferro at it: one cell further")
	near(TraitSet.pull_bonus(ship, uid), 1.0, "the bonus is the station key")
	# A piece 85 px off the mouth is out of reach of 64 px and in reach of 96.
	var rect: Rect2 = d.intakes(ship)[0]["rect"]
	d.add_piece("scrap_chunk_s", Vector2(rect.get_center().x, rect.position.y - 85.0), Vector2.ZERO)
	d.step(ship, 0.02)
	check(d.pulling.has(uid), "the mouth with Ferro at it pulls the piece")
	ship.manned.erase(uid)
	var d2 := DriftDebris.new(1)
	d2.add_piece("scrap_chunk_s", Vector2(rect.get_center().x, rect.position.y - 85.0), Vector2.ZERO)
	d2.step(ship, 0.02)
	check(not d2.pulling.has(uid), "the same mouth with nobody at it does not")
	ship.manned[uid] = "Ferro"
	ferro.hurt(1000.0)
	near(float(d.intakes(ship)[0]["pull"]), 2.0 * 32.0, "a downed operator gives nothing")
	_done()


func test_pull_bonus_reaches_further_with_the_tractor_they_man() -> void:
	_trait("t_magnet", {"station": {"pull_bonus": 1}})
	var r := _mount("tractor_mk1")
	var ship: Ship = r["ship"]
	var uid: int = r["uid"]
	var ferro := _person("Ferro", 11, 20, ["t_magnet"])
	ship.crew.append(ferro)
	var beams := Tractor.beams(ship, Vector2.ZERO)
	eq(beams.size(), 1, "one working beam")
	near(float(beams[0]["range"]), 300.0, "range 300 px with nobody at it")
	ship.manned[uid] = "Ferro"
	beams = Tractor.beams(ship, Vector2.ZERO)
	near(float(beams[0]["range"]), 332.0, "Ferro at it: one cell (32 px) further")
	near(float(beams[0]["pull"]), 150.0, "the haul speed is as it was")
	var mouths := [{"rect": Rect2(Vector2(0, 0), Vector2(64, 32))}]
	var at: Vector2 = beams[0]["at"]
	var lp := at + Vector2(0, -320)  # 320 px out: beyond 300, within 332
	eq(Tractor.pull(beams, mouths, lp, 0.0).is_empty(), false, "a piece 320 px out is hauled by Ferro's beam")
	ship.manned.erase(uid)
	eq(Tractor.pull(Tractor.beams(ship, Vector2.ZERO), mouths, lp, 0.0).is_empty(), true, "and not by the same beam unmanned")
	_done()


# --- races that need no new key -------------------------------------------------------------------------

func test_ferro_is_immune_to_ion_and_mends_walls_with_existing_keys() -> void:
	_trait("t_ferro", {"damage_taken": {"ion": 0}, "hull_mend": {"rate": 0.5}, "station": {"pull_bonus": 1}})
	var ship := Fixture.room_ship()
	var ferro := _person("Ferro", 9, 10, ["t_ferro"])
	var plain := _person("Plain", 16, 12)
	ferro.hold = 1000.0
	plain.hold = 1000.0
	ship.crew.append_array([ferro, plain])
	Jobs.ion_hit(ship, Vector2i(12, 12), 4.0)
	near(ferro.hp, ferro.max_hp, "an ion hit on the room does Ferro nothing")
	check(ferro.stun <= 0.0, "and does not stun")
	check(plain.hp < plain.max_hp, "while a plain crew member in the room is hurt")
	var west := Vector2i(8, 10)
	var top := ship.grid.max_hp_of(west)
	ship.grid.hp[west] = top - 3.0
	_run(ship, Jobs.new(), 4.0)
	near(float(ship.grid.hp[west]), top - 1.0, "hull_mend 0.5: the wall beside Ferro gains half an hp a second", 1e-3)
	ship.grid.breach(west)
	ship.mark_dirty()
	ship.refresh()
	_run(ship, Jobs.new(), 30.0)
	check(ship.grid.breached.has(west), "with no seal time in the trait a breach stays: seal is its own sub-key")
	_done()


func test_warden_frame_and_brine_resolve_from_existing_keys() -> void:
	_trait("t_frame", {"mechanical": true, "o2_use": 0, "ranged_mult": 1.5, "damage_taken": {"ion": 3.0}})
	_trait("t_dock", {"damage_taken": {"melee": 0.7, "ranged": 0.7}, "work_mult": {"restock": 1.5}, "no_suit": true})
	var ship := Fixture.room_ship()
	for i in ship.atmosphere.pressure.size():
		ship.atmosphere.pressure[i] = 0.0
	var frame := _person("Frame", 11, 12, ["t_frame"], true)
	var human := _person("Human", 16, 12, [], true)
	ship.crew.append_array([frame, human])
	var t := TraitSet.of(frame)
	check(t["mechanical"], "mechanical")
	near(t["heal_mult"]["bed"], 0.0, "and so no bed heals it")
	near(t["o2_use"], 0.0, "o2_use 0")
	near(t["ranged_mult"], 1.5, "ranged x1.5")
	near(t["damage_taken"]["ion"], 3.0, "ion x3")
	_run(ship, Jobs.new(), 5.0)
	near(frame.hp, frame.max_hp, "in a room with no air a machine does not suffocate")
	check(human.hp < human.max_hp, "a human does")
	var jobs := Jobs.new()
	frame.hp = 50.0
	jobs.build_board(ship)
	check(jobs.board.has("mend:Frame"), "a hurt machine gets a repair_crew job")
	var ion := float(CrewMember.config().get("ion_hp", 0.0))
	frame.hp = frame.max_hp
	human.hp = human.max_hp
	Jobs.ion_hit(ship, Vector2i(12, 12), 4.0)
	near(frame.max_hp - frame.hp, 3.0 * (human.max_hp - human.hp), "an ion hit does it three times what it does a human", 1e-3)
	check(ion > 0.0, "crew.json has an ion_hp")
	var dock := _person("Dock", 11, 14, ["t_dock"])
	var d := TraitSet.of(dock)
	near(d["damage_taken"]["melee"], 0.7, "Brine takes 0.7 of a melee hit")
	near(d["damage_taken"]["ranged"], 0.7, "and of a ranged one")
	near(d["work_mult"]["restock"], 1.5, "restocks x1.5")
	check(d["no_suit"], "and cannot wear a suit")
	_done()


# --- the keys merge -------------------------------------------------------------------------------------

func test_the_wave_4_keys_default_and_merge() -> void:
	var plain := TraitSet.of(CrewMember.new("X"))
	near(plain["mining_mult"], 1.0, "mining_mult 1")
	near(plain["low_pressure_heal"], 0.0, "no low-pressure heal")
	near(plain["haggler"], 0.0, "no haggling")
	near(plain["loot_bonus"], 0.0, "no loot bonus")
	check(not plain["mimic"], "no mimic")
	near(plain["station"]["pull_bonus"], 0.0, "no pull bonus")
	_trait("t_a", {"mining_mult": 1.5, "low_pressure_heal": 1.0, "haggler": 0.1, "loot_bonus": 1, "station": {"pull_bonus": 1}})
	_trait("t_b", {"mining_mult": 2.0, "low_pressure_heal": 0.5, "haggler": 0.05, "loot_bonus": 2, "mimic": true, "station": {"pull_bonus": 2, "power_bonus": 1}})
	var m := CrewMember.new("X")
	m.gear_traits = ["t_a", "t_b"]
	var t := TraitSet.of(m)
	near(t["mining_mult"], 3.0, "mining_mult multiplies")
	near(t["low_pressure_heal"], 1.5, "low_pressure_heal adds")
	near(t["haggler"], 0.15, "haggler adds")
	near(t["loot_bonus"], 3.0, "loot_bonus adds")
	check(t["mimic"], "a flag is true if any trait says so")
	near(t["station"]["pull_bonus"], 3.0, "pull_bonus adds")
	near(t["station"]["power_bonus"], 1.0, "next to the old station keys")
	_done()


func test_every_wave_4_key_is_in_the_doc_of_the_trait_library() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/traits.json"))["_doc"]["keys"]
	for k in ["mining_mult", "low_pressure_heal", "haggler", "loot_bonus", "mimic"]:
		check(TraitSet.KEYS.has(k) and doc.has(k), "%s is a key and data/traits.json _doc.keys describes it" % k)
	check(TraitSet.KEYS["station"].has("pull_bonus") and str(doc["station"]).contains("pull_bonus"), "station.pull_bonus is a sub-key and described")
	check(TraitSet.FLAGS.has("mimic"), "mimic is a flag")
	for k in ["haggler", "loot_bonus", "low_pressure_heal", "counter_melee"]:
		check(TraitSet.AMOUNTS.has(k), "%s is an amount" % k)
	check(FileAccess.get_file_as_string("res://docs/CONTENT_PLAN.md").contains("pull_bonus"), "docs/CONTENT_PLAN.md section 2 names pull_bonus")
	for k in ["mining_mult", "low_pressure_heal", "haggler", "loot_bonus", "mimic"]:
		check(FileAccess.get_file_as_string("res://docs/CONTENT_PLAN.md").contains("`%s`" % k), "docs/CONTENT_PLAN.md names %s" % k)


# --- the validators -------------------------------------------------------------------------------------

func test_the_validators_know_the_wave_4_keys() -> void:
	var good := [
		{"id": "a", "name": "A", "mining_mult": 1.5, "low_pressure_heal": 1, "haggler": 0.1, "loot_bonus": 1, "mimic": true, "station": {"pull_bonus": 1}},
		{"id": "b", "name": "B", "haggler": 0, "loot_bonus": 0, "mining_mult": 1},
	]
	var checker = TestContent.new()
	eq(checker.trait_problems(good), [] as Array[String], "well-formed wave 4 traits pass")
	var bad := [
		{"id": "c", "name": "C", "mining_mult": "big"},
		{"id": "d", "name": "D", "mimic": 1},
		{"id": "e", "name": "E", "station": {"pull_bonus": "far"}},
		{"id": "f", "name": "F", "haggler": 1.5},
		{"id": "g", "name": "G", "loot_bonus": 1.5},
		{"id": "h", "name": "H", "mining_mult": 0},
		{"id": "i", "name": "I", "low_pressure_heal": -1},
		{"id": "j", "name": "J", "loot_bonus": -1},
		{"id": "k", "name": "K", "haggler": {"x": 1}},
	]
	var problems: Array[String] = checker.trait_problems(bad)
	for t in ["'mining_mult' must be a number", "'mimic' must be true or false", "'station.pull_bonus' must be a number", "'haggler' must be from 0 to 1",
			"'loot_bonus' must be a whole number from 0", "'mining_mult' must be above 0", "'low_pressure_heal' must be from 0", "'haggler' must be a number"]:
		check(problems.any(func(p): return p.contains(t)), "a problem says: %s (%s)" % [t, str(problems)])
	for who in "cdefghijk".split(""):
		check(problems.any(func(p): return p.contains("'%s'" % who)), "trait %s is flagged" % who)
	var chars: Array[String] = CrewAbilities._traits_problems("x", {"haggler": 2, "mimic": 1, "mining_mult": 0, "station": {"pull_bonus": "x"}, "bogus": 1})
	eq(chars.size(), 5, "a character's own trait keys are checked the same way: %s" % str(chars))
	eq(CrewAbilities._traits_problems("x", {"haggler": 0.1, "mimic": true, "mining_mult": 1.5, "loot_bonus": 1, "station": {"pull_bonus": 1}}), [] as Array[String], "and pass when well formed")
	_done()
